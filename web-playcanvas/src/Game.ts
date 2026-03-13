import * as pc from "playcanvas";
import { Callbacks, Room } from "@colyseus/sdk";
import { Network } from "./Network";
import { TankEntity, preloadTankModel, getShieldPickableMesh } from "./Tank";
import { MapRenderer } from "./MapRenderer";
import { Sound } from "./Sound";
import type { BattleState } from "../../server/src/schema/BattleState";

const TEAM_COLORS_HEX = [0xff4444, 0x4488ff, 0x44ff44, 0xffff44];
const TEAM_NAMES = ["Red", "Blue", "Green", "Yellow"];

function hexToColor(hex: number): pc.Color {
  return new pc.Color(
    ((hex >> 16) & 0xff) / 255,
    ((hex >> 8) & 0xff) / 255,
    (hex & 0xff) / 255
  );
}

function unlitMaterial(color: pc.Color, opacity = 1): pc.StandardMaterial {
  const mat = new pc.StandardMaterial();
  mat.diffuse = pc.Color.BLACK;
  mat.emissive = color;
  if (opacity < 1) {
    mat.opacity = opacity;
    mat.blendType = pc.BLEND_NORMAL;
    mat.depthWrite = false;
  }
  mat.update();
  return mat;
}

// ── Per-tank HUD health bar ──
interface TankHud {
  container: HTMLElement;
  hpFill: HTMLElement;
  shieldFill: HTMLElement;
}

export class Game {
  app!: pc.AppBase;
  cameraEntity!: pc.Entity;

  network: Network;
  sound: Sound;
  map!: MapRenderer;
  room!: Room<BattleState>;

  tanks = new Map<string, TankEntity>();
  tankHuds = new Map<string, TankHud>();
  bulletEntities = new Map<string, pc.Entity>();
  pickableEntities = new Map<string, pc.Entity>();

  mySessionId = "";
  keys = new Set<string>();
  mouseX = 0;
  mouseY = 0;
  mouseDown = false;

  lastSentDirX = -999;
  lastSentDirY = -999;
  lastSentAngle = -999;

  // HUD elements
  healthFill!: HTMLElement;
  shieldFill!: HTMLElement;
  scoresList!: HTMLElement;
  scoreElements = new Map<number, HTMLElement>();
  deathScreen!: HTMLElement;
  winnerScreen!: HTMLElement;
  ammoDisplay!: HTMLElement;
  connectStatus!: HTMLElement;
  tankHudContainer!: HTMLElement;

  constructor() {
    this.sound = new Sound();

    const params = new URLSearchParams(window.location.search);
    const serverUrl =
      params.get("server") ||
      `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.hostname}:2567`;
    this.network = new Network(serverUrl);

    this.healthFill = document.getElementById("health-fill")!;
    this.shieldFill = document.getElementById("shield-fill")!;
    this.scoresList = document.getElementById("scores-list")!;
    this.deathScreen = document.getElementById("death-screen")!;
    this.winnerScreen = document.getElementById("winner-screen")!;
    this.ammoDisplay = document.getElementById("ammo-display")!;
    this.connectStatus = document.getElementById("connect-status")!;
    this.tankHudContainer = document.getElementById("tank-huds")!;

    this.setupInput();
  }

  async start() {
    const canvas = document.getElementById("application-canvas") as HTMLCanvasElement;
    const device = await pc.createGraphicsDevice(canvas);
    device.maxPixelRatio = Math.min(window.devicePixelRatio, 2);

    const createOptions = new pc.AppOptions();
    createOptions.graphicsDevice = device;
    createOptions.componentSystems = [
      pc.RenderComponentSystem,
      pc.CameraComponentSystem,
      pc.LightComponentSystem,
    ];
    createOptions.resourceHandlers = [pc.TextureHandler, pc.ContainerHandler];

    this.app = new pc.AppBase(canvas);
    this.app.init(createOptions);
    this.app.start();

    this.app.setCanvasFillMode(pc.FILLMODE_FILL_WINDOW);
    this.app.setCanvasResolution(pc.RESOLUTION_AUTO);

    const resize = () => this.app.resizeCanvas();
    window.addEventListener("resize", resize);

    // Scene
    this.app.scene.ambientLight = new pc.Color(0.37, 0.37, 0.47);
    const fog = this.app.scene.fog;
    fog.type = pc.FOG_LINEAR;
    fog.color = new pc.Color(0.051, 0.106, 0.165);
    fog.start = 35;
    fog.end = 65;

    // Camera
    this.cameraEntity = new pc.Entity("camera");
    this.cameraEntity.addComponent("camera", {
      projection: pc.PROJECTION_ORTHOGRAPHIC,
      orthoHeight: 11,
      nearClip: 0.1,
      farClip: 200,
      clearColor: new pc.Color(0.051, 0.106, 0.165),
    });
    this.cameraEntity.setPosition(24 + 20, 20, 24 + 20);
    this.cameraEntity.lookAt(new pc.Vec3(24, 0, 24));
    this.app.root.addChild(this.cameraEntity);

    // Lighting
    const sun = new pc.Entity("sun");
    sun.addComponent("light", {
      type: "directional",
      color: new pc.Color(1, 0.93, 0.87),
      intensity: 1.2,
      castShadows: true,
      shadowBias: 0.05,
      normalOffsetBias: 0.05,
      shadowResolution: 2048,
      shadowDistance: 60,
    });
    sun.setEulerAngles(50, 30, 0);
    this.app.root.addChild(sun);

    // Map
    this.map = new MapRenderer(this.app);

    // Preload tank model
    await preloadTankModel(this.app);

    // Connect
    try {
      this.room = await this.network.connect();
      this.mySessionId = this.room.sessionId;
      this.connectStatus.style.display = "none";
      this.bindRoomEvents();
    } catch (e) {
      this.connectStatus.textContent = "Failed to connect. Is server running?";
      console.error(e);
      return;
    }

    this.app.on("update", (dt: number) => this.animate(dt));
  }

  // ── Per-tank HUD helpers ──

  private createTankHud(key: string): TankHud {
    const container = document.createElement("div");
    container.className = "tank-hud";

    const shieldBar = document.createElement("div");
    shieldBar.className = "tank-shield-bar";
    const shieldFill = document.createElement("div");
    shieldFill.className = "tank-shield-fill";
    shieldBar.appendChild(shieldFill);
    container.appendChild(shieldBar);

    const hpBar = document.createElement("div");
    hpBar.className = "tank-hp-bar";
    const hpFill = document.createElement("div");
    hpFill.className = "tank-hp-fill";
    hpBar.appendChild(hpFill);
    container.appendChild(hpBar);

    this.tankHudContainer.appendChild(container);
    const hud: TankHud = { container, hpFill, shieldFill };
    this.tankHuds.set(key, hud);
    return hud;
  }

  private removeTankHud(key: string) {
    const hud = this.tankHuds.get(key);
    if (hud) {
      hud.container.remove();
      this.tankHuds.delete(key);
    }
  }

  private updateTankHudPositions() {
    const camera = this.cameraEntity.camera!;

    for (const [key, tank] of this.tanks) {
      const hud = this.tankHuds.get(key);
      if (!hud) continue;

      const worldPos = tank.entity.getPosition();
      const screenPos = camera.worldToScreen(new pc.Vec3(worldPos.x, worldPos.y + 2.4, worldPos.z));

      // worldToScreen returns CSS pixels (via device.clientRect)
      const visible = !tank.dead || Date.now() % 500 < 250;
      hud.container.style.display = visible ? "block" : "none";
      hud.container.style.left = `${screenPos.x}px`;
      hud.container.style.top = `${screenPos.y}px`;
    }
  }

  private bindRoomEvents() {
    const state = this.room.state;
    const callbacks = Callbacks.get(this.room);

    // ── Tanks ──
    callbacks.onAdd("tanks", (tank, key: string) => {
      const entity = new TankEntity(this.app, tank.team);
      entity.targetX = tank.x;
      entity.targetZ = tank.y;
      entity.entity.setLocalPosition(tank.x, 0, tank.y);
      entity.dead = tank.dead;
      this.app.root.addChild(entity.entity);
      this.tanks.set(key, entity);

      // Create HUD health bar for this tank
      const hud = this.createTankHud(key);
      this.setTankHudHealth(hud, tank.hp);
      this.setTankHudShield(hud, tank.shield);

      callbacks.listen(tank, "x", (val: number) => (entity.targetX = val));
      callbacks.listen(tank, "y", (val: number) => (entity.targetZ = val));
      callbacks.listen(tank, "angle", (val: number) => (entity.targetAngle = val));
      callbacks.listen(tank, "dead", (val: boolean, prev: boolean) => {
        entity.setDead(val);
        if (val && prev === false) this.sound.explosion();
        if (key === this.mySessionId) {
          if (val && prev === false) {
            this.deathScreen.style.display = "block";
          } else if (!val) {
            this.deathScreen.style.display = "none";
          }
        }
      });
      callbacks.listen(tank, "hp", (val: number, prev: number) => {
        this.setTankHudHealth(hud, val);
        if (val < prev) {
          const myTank = this.tanks.get(this.mySessionId);
          if (myTank) {
            const myPos = myTank.entity.getPosition();
            const ePos = entity.entity.getPosition();
            const dx = ePos.x - myPos.x;
            const dz = ePos.z - myPos.z;
            const dist = Math.sqrt(dx * dx + dz * dz);
            const vol = Math.max(0, 0.25 * (1 - dist / 25));
            if (vol > 0.01) this.sound.hit(vol);
          }
        }
        if (key === this.mySessionId) {
          this.healthFill.style.width = `${Math.max(0, val) * 10}%`;
        }
      });
      callbacks.listen(tank, "shield", (val: number) => {
        entity.setShield(val);
        this.setTankHudShield(hud, val);
        if (key === this.mySessionId) {
          const active = val > 0;
          (this.shieldFill.parentElement as HTMLElement).style.display = active ? "block" : "none";
          this.shieldFill.style.width = `${Math.max(0, val) * 10}%`;
        }
      });
      callbacks.listen(tank, "score", () => this.updateScores());
    });

    callbacks.onRemove("tanks", (_tank, key: string) => {
      const entity = this.tanks.get(key);
      if (entity) {
        entity.dispose();
        this.tanks.delete(key);
      }
      this.removeTankHud(key);
    });

    // ── Bullets ──
    callbacks.onAdd("bullets", (bullet, key: string) => {
      const isSpecial = bullet.special;
      let bulletColor = isSpecial ? hexToColor(0xff8800) : hexToColor(0xffff66);
      const ownerTank = state.tanks.get(bullet.owner);
      if (ownerTank) {
        bulletColor = isSpecial
          ? hexToColor(0xff8800)
          : hexToColor(TEAM_COLORS_HEX[ownerTank.team] || 0xffff66);
      }

      const mat = unlitMaterial(bulletColor);
      const entity = new pc.Entity("bullet");
      entity.addComponent("render", { type: "sphere", material: mat, castShadows: false });
      const radius = isSpecial ? 0.2 : 0.12;
      entity.setLocalScale(radius * 2, radius * 2, radius * 2);
      entity.setLocalPosition(bullet.x, 1.5, bullet.y);
      (entity as any)._sx = bullet.x;
      (entity as any)._sy = bullet.y;

      this.app.root.addChild(entity);
      this.bulletEntities.set(key, entity);

      callbacks.listen(bullet, "x", (val: number) => { (entity as any)._sx = val; });
      callbacks.listen(bullet, "y", (val: number) => { (entity as any)._sy = val; });

      if (bullet.owner === this.mySessionId) {
        isSpecial ? this.sound.shootSpecial() : this.sound.shoot();
      }
    });

    callbacks.onRemove("bullets", (_bullet, key: string) => {
      const entity = this.bulletEntities.get(key);
      if (entity) {
        entity.destroy();
        this.bulletEntities.delete(key);
      }
    });

    // ── Pickables ──
    callbacks.onAdd("pickables", (pick, key: string) => {
      const colorMap: Record<string, pc.Color> = {
        repair: new pc.Color(0.267, 1, 0.267),
        damage: new pc.Color(1, 0.267, 0.267),
        shield: new pc.Color(0.267, 0.533, 1),
      };

      const color = colorMap[pick.type] || new pc.Color(1, 1, 1);
      const itemMat = new pc.StandardMaterial();
      itemMat.diffuse = color;
      itemMat.emissive = new pc.Color(color.r * 0.4, color.g * 0.4, color.b * 0.4);
      itemMat.update();

      const group = new pc.Entity("pickable");

      if (pick.type === "repair") {
        // Plus/cross shape
        const hBar = new pc.Entity("h");
        hBar.addComponent("render", { type: "box", material: itemMat, castShadows: false });
        hBar.setLocalScale(0.7, 0.2, 0.15);
        group.addChild(hBar);
        const vBar = new pc.Entity("v");
        vBar.addComponent("render", { type: "box", material: itemMat, castShadows: false });
        vBar.setLocalScale(0.2, 0.7, 0.15);
        group.addChild(vBar);
      } else if (pick.type === "shield") {
        // Shield shape — proper extruded silhouette
        const shieldMesh = getShieldPickableMesh(this.app.graphicsDevice);
        const mi = new pc.MeshInstance(shieldMesh, itemMat);
        const shape = new pc.Entity("shape");
        shape.addComponent("render", { type: "asset", meshInstances: [mi], castShadows: false });
        shape.setLocalScale(1, 1, 1);
        group.addChild(shape);
      } else {
        // Damage — diamond shape (two cones)
        const top = new pc.Entity("top");
        top.addComponent("render", { type: "cone", material: itemMat, castShadows: false });
        top.setLocalScale(0.5, 0.35, 0.5);
        top.setLocalPosition(0, 0.175, 0);
        group.addChild(top);
        const bot = new pc.Entity("bot");
        bot.addComponent("render", { type: "cone", material: itemMat, castShadows: false });
        bot.setLocalScale(0.5, 0.35, 0.5);
        bot.setLocalPosition(0, -0.175, 0);
        bot.setLocalEulerAngles(180, 0, 0);
        group.addChild(bot);
      }

      // Glow
      const glowMat = unlitMaterial(color, 0.15);
      const glow = new pc.Entity("glow");
      glow.addComponent("render", { type: "sphere", material: glowMat, castShadows: false });
      glow.setLocalScale(1.0, 1.0, 1.0);
      group.addChild(glow);

      group.setLocalPosition(pick.x, 0.6, pick.y);
      this.app.root.addChild(group);
      this.pickableEntities.set(key, group);
    });

    callbacks.onRemove("pickables", (pick, key: string) => {
      const entity = this.pickableEntities.get(key);
      if (entity) {
        entity.destroy();
        this.pickableEntities.delete(key);
        if (pick.type === "repair") this.sound.pickupRepair();
        else if (pick.type === "shield") this.sound.pickupShield();
        else if (pick.type === "damage") this.sound.pickupDamage();
      }
    });

    // @ts-ignore
    window.game = this;

    callbacks.listen("winnerTeam", (val: number) => {
      if (val >= 0) this.showWinnerScreen(val);
    });

    callbacks.onAdd("teams", (team) => {
      callbacks.listen(team, "score", () => this.updateScores());
    });
  }

  private setTankHudHealth(hud: TankHud, hp: number) {
    const pct = Math.max(0, hp / 10) * 100;
    hud.hpFill.style.width = `${pct}%`;
    if (pct > 50) hud.hpFill.style.background = "#4f4";
    else if (pct > 25) hud.hpFill.style.background = "#fa4";
    else hud.hpFill.style.background = "#f44";
  }

  private setTankHudShield(hud: TankHud, shield: number) {
    const active = shield > 0;
    hud.shieldFill.parentElement!.style.display = active ? "block" : "none";
    hud.shieldFill.style.width = `${Math.max(0, shield / 10) * 100}%`;
  }

  private updateScores() {
    const state = this.room.state as any;
    const teams: { id: number; score: number }[] = [];
    for (let i = 0; i < 4; i++) {
      const team = state.teams[i];
      if (team) teams.push({ id: i, score: team.score });
    }
    teams.sort((a, b) => b.score - a.score);
    const rowHeight = 28;
    for (const t of teams) {
      if (!this.scoreElements.has(t.id)) {
        const el = document.createElement("div");
        el.className = `team-score team-${t.id}`;
        el.innerHTML = `<span class="team-name">${TEAM_NAMES[t.id]}</span><span class="team-pts">0</span>`;
        this.scoresList.appendChild(el);
        this.scoreElements.set(t.id, el);
      }
    }
    for (let rank = 0; rank < teams.length; rank++) {
      const t = teams[rank];
      const el = this.scoreElements.get(t.id)!;
      el.style.top = `${rank * rowHeight}px`;
      el.querySelector(".team-pts")!.textContent = `${t.score}`;
    }
    this.scoresList.style.height = `${teams.length * rowHeight}px`;
  }

  private showWinnerScreen(winnerTeamId: number) {
    const stripeRgba = [
      "rgba(200,40,40,0.92)", "rgba(40,100,220,0.92)",
      "rgba(40,180,40,0.92)", "rgba(200,200,40,0.92)",
    ];
    const lineRgba = [
      "rgba(255,120,120,0.8)", "rgba(100,170,255,0.8)",
      "rgba(100,255,100,0.8)", "rgba(255,255,100,0.8)",
    ];
    const tintRgba = [
      "rgba(255,0,0,0.08)", "rgba(0,80,255,0.08)",
      "rgba(0,200,0,0.08)", "rgba(200,200,0,0.08)",
    ];

    const myTank = (this.room.state as any).tanks.get(this.mySessionId);
    const isWinner = myTank && myTank.team === winnerTeamId;

    const label = document.getElementById("winner-label")!;
    const teamLine = document.getElementById("winner-team")!;
    const stripe = document.getElementById("winner-stripe")!;
    const lineTop = document.getElementById("winner-line-top")!;
    const lineBot = document.getElementById("winner-line-bot")!;
    const tint = document.getElementById("winner-tint")!;

    label.textContent = isWinner ? "VICTORY" : "DEFEAT";
    label.style.color = "#fff";
    teamLine.textContent = `${TEAM_NAMES[winnerTeamId]} Team Wins`;
    teamLine.style.color = "rgba(255,255,255,0.9)";

    stripe.style.background = stripeRgba[winnerTeamId] || stripeRgba[0];
    lineTop.style.background = lineRgba[winnerTeamId] || lineRgba[0];
    lineBot.style.background = lineRgba[winnerTeamId] || lineRgba[0];
    tint.style.background = tintRgba[winnerTeamId] || tintRgba[0];

    this.winnerScreen.className = "ready";
    void this.winnerScreen.offsetWidth;
    this.winnerScreen.className = "ready active";

    setTimeout(() => {
      this.winnerScreen.className = "exit";
      setTimeout(() => { this.winnerScreen.className = ""; }, 800);
    }, 2800);
  }

  private setupInput() {
    window.addEventListener("keydown", (e) => this.keys.add(e.key.toLowerCase()));
    window.addEventListener("keyup", (e) => this.keys.delete(e.key.toLowerCase()));
    window.addEventListener("mousemove", (e) => { this.mouseX = e.clientX; this.mouseY = e.clientY; });
    window.addEventListener("mousedown", (e) => {
      if (e.button === 0) { this.mouseDown = true; this.network.sendShoot(true); }
    });
    window.addEventListener("mouseup", (e) => {
      if (e.button === 0) { this.mouseDown = false; this.network.sendShoot(false); }
    });
    window.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  private sendInput() {
    let rawX = 0, rawY = 0;
    if (this.keys.has("w") || this.keys.has("arrowup")) rawY -= 1;
    if (this.keys.has("s") || this.keys.has("arrowdown")) rawY += 1;
    if (this.keys.has("a") || this.keys.has("arrowleft")) rawX -= 1;
    if (this.keys.has("d") || this.keys.has("arrowright")) rawX += 1;

    const angle = -Math.PI / 4;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const dirX = Math.round(rawX * cos - rawY * sin);
    const dirY = Math.round(rawX * sin + rawY * cos);

    if (dirX !== this.lastSentDirX || dirY !== this.lastSentDirY) {
      this.network.sendMove(dirX, dirY);
      this.lastSentDirX = dirX;
      this.lastSentDirY = dirY;
    }

    const myTank = this.tanks.get(this.mySessionId);
    if (myTank) {
      const camera = this.cameraEntity.camera!;
      const from = new pc.Vec3();
      const to = new pc.Vec3();
      camera.screenToWorld(this.mouseX, this.mouseY, camera.nearClip, from);
      camera.screenToWorld(this.mouseX, this.mouseY, camera.farClip, to);
      const dir = new pc.Vec3().sub2(to, from).normalize();

      if (Math.abs(dir.y) > 0.001) {
        const t = -from.y / dir.y;
        const targetX = from.x + dir.x * t;
        const targetZ = from.z + dir.z * t;
        const tankPos = myTank.entity.getPosition();
        const dx = targetX - tankPos.x;
        const dz = targetZ - tankPos.z;
        let aimAngle = Math.atan2(dx, dz) * (180 / Math.PI);
        aimAngle = ((aimAngle % 360) + 360) % 360;

        if (Math.abs(aimAngle - this.lastSentAngle) > 1) {
          this.network.sendTarget(aimAngle);
          this.lastSentAngle = aimAngle;
          myTank.targetAngle = aimAngle;
        }
      }
    }
  }

  private animate(dt: number) {
    if (this.room) this.sendInput();

    // Update tanks
    for (const [, tank] of this.tanks) {
      tank.update(dt);
    }

    // Animate pickables
    const t = Date.now() * 0.001;
    for (const [, entity] of this.pickableEntities) {
      const pos = entity.getLocalPosition();
      entity.setLocalPosition(pos.x, 0.6 + Math.sin(t * 2) * 0.15, pos.z);
      entity.setLocalEulerAngles(0, t * (180 / Math.PI), 0);
    }

    // Bullet interpolation
    for (const [, entity] of this.bulletEntities) {
      const data = entity as any;
      if (data._sx !== undefined) {
        const pos = entity.getLocalPosition();
        entity.setLocalPosition(
          pc.math.lerp(pos.x, data._sx, 0.4),
          1.5,
          pc.math.lerp(pos.z, data._sy, 0.4)
        );
      }
    }

    // Camera follow
    const myTank = this.tanks.get(this.mySessionId);
    if (myTank) {
      const tankPos = myTank.entity.getPosition();
      const nx = (this.mouseX / this.app.graphicsDevice.width) * 2 - 1;
      const ny = (this.mouseY / this.app.graphicsDevice.height) * 2 - 1;
      const lookAhead = 3;
      const offsetX = (nx + ny) * 0.707 * lookAhead;
      const offsetZ = (-nx + ny) * 0.707 * lookAhead;
      const cp = this.cameraEntity.getPosition();
      const newCamX = pc.math.lerp(cp.x, tankPos.x + 20 + offsetX, 0.08);
      const newCamZ = pc.math.lerp(cp.z, tankPos.z + 20 + offsetZ, 0.08);
      this.cameraEntity.setPosition(newCamX, 20, newCamZ);
      this.cameraEntity.lookAt(new pc.Vec3(newCamX - 20, 0, newCamZ - 20));
    }

    // Update HUD health bar positions
    this.updateTankHudPositions();
  }
}
