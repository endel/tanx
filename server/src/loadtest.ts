import { Client, Room } from "@colyseus/sdk";
import { Callbacks } from "@colyseus/sdk";
import { cli, Options } from "@colyseus/loadtest";
import { LEVEL } from "./rooms/BattleRoom";

// Bot behaviour constants
const TICK_MS = 100;
const CHASE_RANGE = 20;
const SHOOT_RANGE = 14;
const PICKUP_RANGE = 10;
const TANK_RADIUS = 0.75;
const PATH_RECOMPUTE_MS = 500;
const WAYPOINT_REACH_DIST = 0.8;

// ── Navigation grid (A* pathfinding) ────────────────────────

const GRID_SIZE = 48;
const CELL_SIZE = 1; // 1 world unit per cell
const INFLATE = Math.ceil(TANK_RADIUS); // inflate obstacles by tank radius

// Build walkability grid once (true = blocked)
const blocked: boolean[] = new Array(GRID_SIZE * GRID_SIZE).fill(false);

for (const [cx, cy, w, h] of LEVEL) {
  const minGX = Math.floor(cx - w / 2 - INFLATE);
  const minGY = Math.floor(cy - h / 2 - INFLATE);
  const maxGX = Math.ceil(cx + w / 2 + INFLATE);
  const maxGY = Math.ceil(cy + h / 2 + INFLATE);
  for (let gy = Math.max(0, minGY); gy < Math.min(GRID_SIZE, maxGY); gy++) {
    for (let gx = Math.max(0, minGX); gx < Math.min(GRID_SIZE, maxGX); gx++) {
      blocked[gy * GRID_SIZE + gx] = true;
    }
  }
}

// Also block map edges
for (let i = 0; i < GRID_SIZE; i++) {
  blocked[i] = true;                           // top row
  blocked[(GRID_SIZE - 1) * GRID_SIZE + i] = true; // bottom row
  blocked[i * GRID_SIZE] = true;               // left col
  blocked[i * GRID_SIZE + GRID_SIZE - 1] = true;   // right col
}

function isBlocked(gx: number, gy: number): boolean {
  if (gx < 0 || gy < 0 || gx >= GRID_SIZE || gy >= GRID_SIZE) return true;
  return blocked[gy * GRID_SIZE + gx];
}

function worldToGrid(wx: number, wy: number): [number, number] {
  return [
    Math.max(0, Math.min(GRID_SIZE - 1, Math.floor(wx / CELL_SIZE))),
    Math.max(0, Math.min(GRID_SIZE - 1, Math.floor(wy / CELL_SIZE))),
  ];
}

function gridToWorld(gx: number, gy: number): [number, number] {
  return [gx * CELL_SIZE + CELL_SIZE / 2, gy * CELL_SIZE + CELL_SIZE / 2];
}

// 8-directional neighbors
const DIRS = [
  [1, 0], [-1, 0], [0, 1], [0, -1],
  [1, 1], [1, -1], [-1, 1], [-1, -1],
];
const SQRT2 = Math.SQRT2;

// A* pathfinding — returns list of world-space waypoints (excluding start)
function findPath(fromX: number, fromY: number, toX: number, toY: number): [number, number][] | null {
  const [sx, sy] = worldToGrid(fromX, fromY);
  const [ex, ey] = worldToGrid(toX, toY);

  if (sx === ex && sy === ey) return [];
  if (isBlocked(ex, ey)) {
    // Target is inside a wall — find nearest unblocked cell
    let bestDist = Infinity;
    let bestX = ex, bestY = ey;
    for (let r = 1; r <= 3; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          const nx = ex + dx, ny = ey + dy;
          if (!isBlocked(nx, ny)) {
            const d = dx * dx + dy * dy;
            if (d < bestDist) { bestDist = d; bestX = nx; bestY = ny; }
          }
        }
      }
      if (bestDist < Infinity) break;
    }
    if (bestDist === Infinity) return null;
    return findPath(fromX, fromY, ...gridToWorld(bestX, bestY));
  }

  // Min-heap using array (simple binary heap by f-score)
  const gScore = new Map<number, number>();
  const fScore = new Map<number, number>();
  const cameFrom = new Map<number, number>();

  const key = (x: number, y: number) => y * GRID_SIZE + x;
  const heuristic = (x: number, y: number) => {
    const dx = Math.abs(x - ex), dy = Math.abs(y - ey);
    return Math.max(dx, dy) + (SQRT2 - 1) * Math.min(dx, dy); // octile distance
  };

  const startKey = key(sx, sy);
  const endKey = key(ex, ey);
  gScore.set(startKey, 0);
  fScore.set(startKey, heuristic(sx, sy));

  // Simple open set with sorted insertion (fast enough for 48x48 grid)
  const open: number[] = [startKey];
  const inOpen = new Set<number>([startKey]);
  const closed = new Set<number>();

  let iterations = 0;
  const MAX_ITERATIONS = 2500;

  while (open.length > 0 && iterations++ < MAX_ITERATIONS) {
    // Find node with lowest f-score
    let bestIdx = 0;
    let bestF = fScore.get(open[0])!;
    for (let i = 1; i < open.length; i++) {
      const f = fScore.get(open[i])!;
      if (f < bestF) { bestF = f; bestIdx = i; }
    }

    const currentKey = open[bestIdx];
    open[bestIdx] = open[open.length - 1];
    open.pop();
    inOpen.delete(currentKey);

    if (currentKey === endKey) {
      // Reconstruct path
      const path: [number, number][] = [];
      let cur = endKey;
      while (cur !== startKey) {
        const gx = cur % GRID_SIZE;
        const gy = (cur - gx) / GRID_SIZE;
        path.push(gridToWorld(gx, gy));
        cur = cameFrom.get(cur)!;
      }
      path.reverse();
      return path;
    }

    closed.add(currentKey);
    const cx = currentKey % GRID_SIZE;
    const cy = (currentKey - cx) / GRID_SIZE;
    const currentG = gScore.get(currentKey)!;

    for (const [ddx, ddy] of DIRS) {
      const nx = cx + ddx;
      const ny = cy + ddy;
      if (isBlocked(nx, ny)) continue;

      // For diagonal moves, check that both adjacent cardinal cells are free
      if (ddx !== 0 && ddy !== 0) {
        if (isBlocked(cx + ddx, cy) || isBlocked(cx, cy + ddy)) continue;
      }

      const nk = key(nx, ny);
      if (closed.has(nk)) continue;

      const moveCost = (ddx !== 0 && ddy !== 0) ? SQRT2 : 1;
      const tentativeG = currentG + moveCost;

      const prevG = gScore.get(nk);
      if (prevG !== undefined && tentativeG >= prevG) continue;

      gScore.set(nk, tentativeG);
      fScore.set(nk, tentativeG + heuristic(nx, ny));
      cameFrom.set(nk, currentKey);

      if (!inOpen.has(nk)) {
        open.push(nk);
        inOpen.add(nk);
      }
    }
  }

  return null; // no path found
}

// ── Interfaces ──────────────────────────────────────────────

interface EnemyInfo {
  x: number;
  y: number;
  dead: boolean;
  team: number;
  hp: number;
}

interface PickableInfo {
  x: number;
  y: number;
  type: string;
}

// ── Main ────────────────────────────────────────────────────

async function main(options: Options) {
  const client = new Client(options.endpoint);
  const room: Room = await client.joinOrCreate(options.roomName);
  const callbacks = Callbacks.get(room as any);

  let myX = 0;
  let myY = 0;
  let myTeam = -1;
  let myDead = true;
  let myHp = 10;
  let myShield = 0;

  // Pathfinding state
  let currentPath: [number, number][] = [];
  let pathTargetX = 0;
  let pathTargetY = 0;
  let lastPathTime = 0;

  const enemies = new Map<string, EnemyInfo>();
  const pickables = new Map<string, PickableInfo>();

  // Track all tanks
  callbacks.onAdd("tanks", (tank: any, key: string) => {
    if (key === room.sessionId) {
      myX = tank.x;
      myY = tank.y;
      myTeam = tank.team;
      myDead = tank.dead;
      myHp = tank.hp;
      myShield = tank.shield;
      callbacks.listen(tank, "x", (v: number) => (myX = v));
      callbacks.listen(tank, "y", (v: number) => (myY = v));
      callbacks.listen(tank, "dead", (v: boolean) => (myDead = v));
      callbacks.listen(tank, "hp", (v: number) => (myHp = v));
      callbacks.listen(tank, "shield", (v: number) => (myShield = v));
    } else {
      const info: EnemyInfo = { x: tank.x, y: tank.y, dead: tank.dead, team: tank.team, hp: tank.hp };
      enemies.set(key, info);
      callbacks.listen(tank, "x", (v: number) => (info.x = v));
      callbacks.listen(tank, "y", (v: number) => (info.y = v));
      callbacks.listen(tank, "dead", (v: boolean) => (info.dead = v));
      callbacks.listen(tank, "hp", (v: number) => (info.hp = v));
    }
  });

  callbacks.onRemove("tanks", (_tank: any, key: string) => {
    enemies.delete(key);
  });

  // Track pickables
  callbacks.onAdd("pickables", (pick: any, key: string) => {
    const info: PickableInfo = { x: pick.x, y: pick.y, type: pick.type };
    pickables.set(key, info);
  });

  callbacks.onRemove("pickables", (_pick: any, key: string) => {
    pickables.delete(key);
  });

  // Bot AI loop
  const interval = setInterval(() => {
    if (myDead) {
      room.send("shoot", false);
      room.send("move", { x: 0, y: 0 });
      currentPath = [];
      return;
    }

    const now = Date.now();

    // Find closest enemy on a different team
    let closestEnemy: EnemyInfo | null = null;
    let closestDist = Infinity;

    for (const [, enemy] of enemies) {
      if (enemy.dead || enemy.team === myTeam) continue;
      const dx = enemy.x - myX;
      const dy = enemy.y - myY;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < closestDist) {
        closestDist = dist;
        closestEnemy = enemy;
      }
    }

    // Check for nearby pickables worth grabbing
    let bestPickable: PickableInfo | null = null;
    let bestPickDist = Infinity;

    for (const [, pick] of pickables) {
      const dx = pick.x - myX;
      const dy = pick.y - myY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      const wantRepair = pick.type === "repair" && myHp < 7;
      const wantShield = pick.type === "shield" && myShield === 0;
      const wantDamage = pick.type === "damage";

      if ((wantRepair || wantShield || wantDamage) && dist < PICKUP_RANGE && dist < bestPickDist) {
        bestPickDist = dist;
        bestPickable = pick;
      }
    }

    // Decide movement target
    let targetX: number;
    let targetY: number;
    let shouldShoot = false;

    const goForPickup = bestPickable && (myHp < 5 || !closestEnemy || closestDist > CHASE_RANGE || bestPickDist < 3);

    if (goForPickup && bestPickable) {
      targetX = bestPickable.x;
      targetY = bestPickable.y;
      if (closestEnemy && closestDist < SHOOT_RANGE) {
        shouldShoot = true;
      }
    } else if (closestEnemy && closestDist < CHASE_RANGE) {
      targetX = closestEnemy.x;
      targetY = closestEnemy.y;
      shouldShoot = closestDist < SHOOT_RANGE;
    } else {
      // Wander toward center
      targetX = 24 + (Math.random() - 0.5) * 10;
      targetY = 24 + (Math.random() - 0.5) * 10;
    }

    // Recompute path if target moved significantly or enough time has passed
    const targetMoved = Math.abs(targetX - pathTargetX) + Math.abs(targetY - pathTargetY) > 2;
    if (currentPath.length === 0 || targetMoved || now - lastPathTime > PATH_RECOMPUTE_MS) {
      const newPath = findPath(myX, myY, targetX, targetY);
      if (newPath) {
        currentPath = newPath;
        pathTargetX = targetX;
        pathTargetY = targetY;
        lastPathTime = now;
      }
    }

    // Consume reached waypoints
    while (currentPath.length > 0) {
      const [wx, wy] = currentPath[0];
      const dx = wx - myX;
      const dy = wy - myY;
      if (Math.sqrt(dx * dx + dy * dy) < WAYPOINT_REACH_DIST) {
        currentPath.shift();
      } else {
        break;
      }
    }

    // Move toward next waypoint (or directly toward target if path is empty)
    let moveX = 0;
    let moveY = 0;

    const [nextX, nextY] = currentPath.length > 0
      ? currentPath[0]
      : [targetX, targetY];

    const dx = nextX - myX;
    const dy = nextY - myY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist > 0.3) {
      moveX = Math.round(dx / dist);
      moveY = Math.round(dy / dist);
    }

    room.send("move", { x: moveX, y: moveY });

    // Aim at closest enemy
    if (closestEnemy) {
      const aimDx = closestEnemy.x - myX;
      const aimDy = closestEnemy.y - myY;
      let aimAngle = Math.atan2(aimDx, aimDy) * (180 / Math.PI);
      aimAngle = ((aimAngle % 360) + 360) % 360;
      room.send("target", aimAngle);
    }

    room.send("shoot", shouldShoot);
  }, TICK_MS);

  room.onLeave(() => clearInterval(interval));
}

cli(main);
