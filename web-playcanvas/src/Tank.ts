import * as pc from "playcanvas";

const TEAM_COLORS: pc.Color[] = [
  new pc.Color(1, 0.267, 0.267),     // red
  new pc.Color(0.267, 0.533, 1),     // blue
  new pc.Color(0.267, 1, 0.267),     // green
  new pc.Color(1, 1, 0.267),         // yellow
];

const TEAM_TEXTURES_PATHS = [
  "./models/T_pixelTank_red.png",
  "./models/T_pixelTank_blue.png",
  "./models/T_pixelTank_green.png",
  "./models/T_pixelTank_yellow.png",
];

// ── Preloaded model data ──
let tankModelContainer: pc.ContainerResource | null = null;
let teamTextures: pc.Texture[] = [];

export async function preloadTankModel(app: pc.AppBase): Promise<void> {
  // Load team textures
  teamTextures = await Promise.all(
    TEAM_TEXTURES_PATHS.map(
      (path) =>
        new Promise<pc.Texture>((resolve) => {
          const img = new Image();
          img.crossOrigin = "anonymous";
          img.onload = () => {
            const tex = new pc.Texture(app.graphicsDevice, {
              width: img.width,
              height: img.height,
              magFilter: pc.FILTER_NEAREST,
              minFilter: pc.FILTER_NEAREST_MIPMAP_NEAREST,
            });
            tex.setSource(img);
            resolve(tex);
          };
          img.src = path;
        })
    )
  );

  // Load GLB model
  tankModelContainer = await new Promise<pc.ContainerResource>((resolve, reject) => {
    const url = "./models/pixelTank.glb";
    app.assets.loadFromUrl(url, "container", (err, asset) => {
      if (err || !asset) return reject(err || new Error("Failed to load tank model"));
      resolve(asset.resource as pc.ContainerResource);
    });
  });
}

// ── Helpers ──

function createRingMesh(device: pc.GraphicsDevice, innerRadius: number, outerRadius: number, segments: number): pc.Mesh {
  const rows = segments + 1;
  const vertCount = 2 * rows;
  const positions: number[] = new Array(vertCount * 3).fill(0);
  const normals: number[] = new Array(vertCount * 3).fill(0);
  const indices: number[] = [];

  for (let i = 0; i < rows; i++) {
    const angle = (i / segments) * Math.PI * 2;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const vi = i * 2;
    positions[vi * 3] = cos * innerRadius;
    positions[vi * 3 + 1] = 0;
    positions[vi * 3 + 2] = sin * innerRadius;
    normals[vi * 3 + 1] = 1;
    positions[(vi + 1) * 3] = cos * outerRadius;
    positions[(vi + 1) * 3 + 1] = 0;
    positions[(vi + 1) * 3 + 2] = sin * outerRadius;
    normals[(vi + 1) * 3 + 1] = 1;
    if (i < segments) {
      const next = (i + 1) * 2;
      indices.push(vi, next, vi + 1, vi + 1, next, next + 1);
    }
  }
  const mesh = new pc.Mesh(device);
  mesh.setPositions(positions);
  mesh.setNormals(normals);
  mesh.setIndices(indices);
  mesh.update(pc.PRIMITIVE_TRIANGLES);
  return mesh;
}

function createShieldMesh(device: pc.GraphicsDevice, segments: number): pc.Mesh {
  // Shield silhouette: pointed bottom, flat top with inward curve
  const profile: [number, number][] = [];
  // Top flat edge
  profile.push([0, 0.4]);
  profile.push([0.35, 0.25]);
  profile.push([0.35, 0]);
  // Bottom curve (quadratic Bezier approximation)
  const steps = 6;
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    // Quadratic bezier: P0=(0.35,0), P1=(0.3,-0.3), P2=(0,-0.45)
    const mt = 1 - t;
    const x = mt * mt * 0.35 + 2 * mt * t * 0.3 + t * t * 0;
    const y = mt * mt * 0 + 2 * mt * t * -0.3 + t * t * -0.45;
    profile.push([x, y]);
  }

  // Create mesh by extruding the profile with depth
  const depth = 0.12;
  const numProfile = profile.length;
  // Front face + back face vertices (closed polygon via triangle fan)
  // For simplicity, create front and back as flat surfaces with the profile outline

  // Build front and back face vertices
  const positions: number[] = [];
  const normals: number[] = [];
  const indices: number[] = [];

  // Center vertex for front face (index 0)
  positions.push(0, 0, depth / 2);
  normals.push(0, 0, 1);
  // Front face profile vertices
  for (let i = 0; i < numProfile; i++) {
    positions.push(profile[i][0], profile[i][1], depth / 2);
    normals.push(0, 0, 1);
    // Mirror X
    positions.push(-profile[i][0], profile[i][1], depth / 2);
    normals.push(0, 0, 1);
  }

  // Front face triangles (fan from center)
  // Right side: center, profile[i].right, profile[i+1].right
  // Left side: center, profile[i+1].left, profile[i].left
  const frontStart = 1; // first profile vertex index
  for (let i = 0; i < numProfile - 1; i++) {
    const rCurr = frontStart + i * 2;     // right vertex
    const lCurr = frontStart + i * 2 + 1; // left vertex
    const rNext = frontStart + (i + 1) * 2;
    const lNext = frontStart + (i + 1) * 2 + 1;
    // Right triangle
    indices.push(0, rCurr, rNext);
    // Left triangle
    indices.push(0, lNext, lCurr);
  }
  // Connect right top to left top through center
  const rTop = frontStart;
  const lTop = frontStart + 1;
  indices.push(0, lTop, rTop);

  // Back face
  const backCenter = positions.length / 3;
  positions.push(0, 0, -depth / 2);
  normals.push(0, 0, -1);
  for (let i = 0; i < numProfile; i++) {
    positions.push(profile[i][0], profile[i][1], -depth / 2);
    normals.push(0, 0, -1);
    positions.push(-profile[i][0], profile[i][1], -depth / 2);
    normals.push(0, 0, -1);
  }
  const backStart = backCenter + 1;
  for (let i = 0; i < numProfile - 1; i++) {
    const rCurr = backStart + i * 2;
    const lCurr = backStart + i * 2 + 1;
    const rNext = backStart + (i + 1) * 2;
    const lNext = backStart + (i + 1) * 2 + 1;
    indices.push(backCenter, rNext, rCurr);
    indices.push(backCenter, lCurr, lNext);
  }
  const rTopB = backStart;
  const lTopB = backStart + 1;
  indices.push(backCenter, rTopB, lTopB);

  // Side faces (connect front and back profile edges)
  // Right side
  for (let i = 0; i < numProfile - 1; i++) {
    const fr = frontStart + i * 2;
    const frN = frontStart + (i + 1) * 2;
    const br = backStart + i * 2;
    const brN = backStart + (i + 1) * 2;
    indices.push(fr, brN, br);
    indices.push(fr, frN, brN);
  }
  // Left side
  for (let i = 0; i < numProfile - 1; i++) {
    const fl = frontStart + i * 2 + 1;
    const flN = frontStart + (i + 1) * 2 + 1;
    const bl = backStart + i * 2 + 1;
    const blN = backStart + (i + 1) * 2 + 1;
    indices.push(fl, bl, blN);
    indices.push(fl, blN, flN);
  }
  // Top edge (connect right-top front to right-top back, left-top front to left-top back)
  indices.push(rTop, rTopB, lTopB);
  indices.push(rTop, lTopB, lTop);

  const mesh = new pc.Mesh(device);
  mesh.setPositions(positions);
  mesh.setNormals(pc.calculateNormals(positions, indices));
  mesh.setIndices(indices);
  mesh.update(pc.PRIMITIVE_TRIANGLES);
  return mesh;
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

function litMaterial(color: pc.Color, opts: { roughness?: number; opacity?: number } = {}): pc.StandardMaterial {
  const mat = new pc.StandardMaterial();
  mat.diffuse = color;
  mat.gloss = 1 - (opts.roughness ?? 0.7);
  mat.useMetalness = true;
  mat.metalness = 0.1;
  if (opts.opacity !== undefined && opts.opacity < 1) {
    mat.opacity = opts.opacity;
    mat.blendType = pc.BLEND_NORMAL;
    mat.depthWrite = false;
  }
  mat.update();
  return mat;
}

let shieldPickableMesh: pc.Mesh | null = null;

export function getShieldPickableMesh(device: pc.GraphicsDevice): pc.Mesh {
  if (!shieldPickableMesh) {
    shieldPickableMesh = createShieldMesh(device, 12);
  }
  return shieldPickableMesh;
}

export class TankEntity {
  entity: pc.Entity;
  body: pc.Entity;
  turret: pc.Entity;
  teamIndicator: pc.Entity;
  shieldBubble: pc.Entity;

  targetX = 0;
  targetZ = 0;
  targetAngle = 0;
  currentTurretAngle = 0;
  targetBodyAngle = 0;
  currentBodyAngle = 0;
  dead = false;
  shieldActive = false;
  shieldBreakTime = 0;
  shieldFragments: pc.Entity[] = [];
  explosionTime = 0;
  explosionParts: { entity: pc.Entity; type: string; vel?: pc.Vec3; spin?: { x: number; z: number } }[] = [];
  team = 0;

  private shieldMat: pc.StandardMaterial;

  constructor(private app: pc.AppBase, team: number) {
    this.team = team;
    this.entity = new pc.Entity("tank");

    // ── Body & Turret ──
    this.body = new pc.Entity("body");
    this.turret = new pc.Entity("turret");
    this.turret.setLocalPosition(0, 0, -0.3);

    if (tankModelContainer) {
      this.createModelTank(team);
    } else {
      this.createFallbackBody(team);
      this.createFallbackTurret(team);
    }

    this.entity.addChild(this.body);
    this.entity.addChild(this.turret);

    // ── Team indicator ring ──
    const teamColor = TEAM_COLORS[team] || new pc.Color(1, 1, 1);
    const ringMesh = createRingMesh(app.graphicsDevice, 0.9, 1.2, 20);
    const ringMat = unlitMaterial(teamColor, 0.7);
    const ringMi = new pc.MeshInstance(ringMesh, ringMat);
    this.teamIndicator = new pc.Entity("indicator");
    this.teamIndicator.addComponent("render", {
      type: "asset",
      meshInstances: [ringMi],
      castShadows: false,
    });
    this.teamIndicator.setLocalPosition(0, 0.02, 0);
    this.entity.addChild(this.teamIndicator);

    // ── Shield bubble ──
    this.shieldMat = unlitMaterial(new pc.Color(0.267, 0.8, 1), 0.12);
    this.shieldMat.cull = pc.CULLFACE_NONE;
    this.shieldMat.update();
    this.shieldBubble = new pc.Entity("shield");
    this.shieldBubble.addComponent("render", {
      type: "sphere",
      material: this.shieldMat,
      castShadows: false,
    });
    this.shieldBubble.setLocalPosition(0, 1.3, 0);
    this.shieldBubble.setLocalScale(2.8, 2.6, 2.8);
    this.shieldBubble.enabled = false;
    this.entity.addChild(this.shieldBubble);
  }

  private createModelTank(team: number) {
    const container = tankModelContainer!;

    // Create team material with the pixel texture
    const teamMat = new pc.StandardMaterial();
    teamMat.diffuseMap = teamTextures[team] || teamTextures[2];
    teamMat.gloss = 0.2;
    teamMat.useMetalness = true;
    teamMat.metalness = 0.1;
    teamMat.update();

    // Clone the model hierarchy for body
    const bodyInstance = container.instantiateRenderEntity();
    bodyInstance.setLocalScale(1, 1, 1);

    // Hide turret parts in body clone, apply team material to body parts
    bodyInstance.forEach((node) => {
      const e = node as pc.Entity;
      if (e.name.toLowerCase().includes("turret")) {
        e.enabled = false;
      } else if (e.render) {
        for (const mi of e.render.meshInstances) {
          mi.material = teamMat;
        }
        e.render.castShadows = true;
      }
    });
    this.body.addChild(bodyInstance);

    // Clone the model hierarchy for turret
    const turretInstance = container.instantiateRenderEntity();
    turretInstance.setLocalScale(1, 1, 1);
    turretInstance.setLocalPosition(0, 0, 0.3); // counter-offset turret pivot

    // Hide body parts in turret clone, apply team material to turret parts
    turretInstance.forEach((node) => {
      const e = node as pc.Entity;
      if (e.render) {
        if (!e.name.toLowerCase().includes("turret")) {
          for (const mi of e.render.meshInstances) {
            mi.visible = false;
          }
        } else {
          for (const mi of e.render.meshInstances) {
            mi.material = teamMat;
          }
          e.render.castShadows = true;
        }
      }
    });
    this.turret.addChild(turretInstance);
  }

  private createFallbackBody(team: number) {
    const teamColor = TEAM_COLORS[team] || new pc.Color(0.4, 0.533, 0.4);
    const bodyColor = new pc.Color(teamColor.r * 0.6 + 0.1, teamColor.g * 0.6 + 0.1, teamColor.b * 0.6 + 0.1);
    const bodyMat = litMaterial(bodyColor, { roughness: 0.7 });

    const bodyMesh = new pc.Entity("body-mesh");
    bodyMesh.addComponent("render", { type: "box", material: bodyMat, castShadows: true });
    bodyMesh.setLocalPosition(0, 0.3, 0);
    bodyMesh.setLocalScale(1.0, 0.4, 1.4);
    this.body.addChild(bodyMesh);

    const trackMat = litMaterial(new pc.Color(0.267, 0.267, 0.267));
    for (const side of [-0.55, 0.55]) {
      const track = new pc.Entity("track");
      track.addComponent("render", { type: "box", material: trackMat, castShadows: true });
      track.setLocalPosition(side, 0.2, 0);
      track.setLocalScale(0.2, 0.25, 1.5);
      this.body.addChild(track);
    }
  }

  private createFallbackTurret(team: number) {
    const teamColor = TEAM_COLORS[team] || new pc.Color(0.333, 0.467, 0.333);
    const turretColor = new pc.Color(teamColor.r * 0.5 + 0.1, teamColor.g * 0.5 + 0.1, teamColor.b * 0.5 + 0.1);
    const turretMat = litMaterial(turretColor);
    const barrelMat = litMaterial(new pc.Color(0.333, 0.333, 0.333));

    const tBase = new pc.Entity("turret-base");
    tBase.addComponent("render", { type: "cylinder", material: turretMat, castShadows: true });
    tBase.setLocalPosition(0, 0.55, 0.3);
    tBase.setLocalScale(0.75, 0.25, 0.8);
    this.turret.addChild(tBase);

    const barrel = new pc.Entity("barrel");
    barrel.addComponent("render", { type: "cylinder", material: barrelMat, castShadows: true });
    barrel.setLocalPosition(0, 0.55, 0.5 + 0.3);
    barrel.setLocalEulerAngles(90, 0, 0);
    barrel.setLocalScale(0.14, 1.0, 0.16);
    this.turret.addChild(barrel);
  }

  update(dt: number) {
    const pos = this.entity.getLocalPosition();

    // Movement delta
    const moveX = this.targetX - pos.x;
    const moveZ = this.targetZ - pos.z;
    const moveDist = Math.sqrt(moveX * moveX + moveZ * moveZ);

    // Smooth position interpolation
    const newX = pc.math.lerp(pos.x, this.targetX, 0.2);
    const newZ = pc.math.lerp(pos.z, this.targetZ, 0.2);
    this.entity.setLocalPosition(newX, 0, newZ);

    // Rotate body toward movement direction
    if (moveDist > 0.02) {
      this.targetBodyAngle = Math.atan2(moveX, moveZ);
    }
    let bodyDiff = this.targetBodyAngle - this.currentBodyAngle;
    while (bodyDiff > Math.PI) bodyDiff -= Math.PI * 2;
    while (bodyDiff < -Math.PI) bodyDiff += Math.PI * 2;
    this.currentBodyAngle += bodyDiff * 0.15;
    this.body.setLocalEulerAngles(0, this.currentBodyAngle * (180 / Math.PI), 0);

    // Turret aim (absolute, not relative to body)
    const targetTurretRad = this.targetAngle * (Math.PI / 180);
    let turretDiff = targetTurretRad - this.currentTurretAngle;
    while (turretDiff > Math.PI) turretDiff -= Math.PI * 2;
    while (turretDiff < -Math.PI) turretDiff += Math.PI * 2;
    this.currentTurretAngle += turretDiff * 0.25;
    this.turret.setLocalEulerAngles(0, this.currentTurretAngle * (180 / Math.PI), 0);

    // Keep turret pivot aligned with body mount point
    const mountZ = -0.3;
    this.turret.setLocalPosition(
      mountZ * Math.sin(this.currentBodyAngle),
      0,
      mountZ * Math.cos(this.currentBodyAngle)
    );

    // Shield bubble pulse
    if (this.shieldActive) {
      this.shieldBubble.enabled = true;
      const pulse = 0.10 + Math.sin(Date.now() * 0.004) * 0.05;
      this.shieldMat.opacity = pulse;
      this.shieldMat.emissive = new pc.Color(0.267, 0.8, 1);
      this.shieldMat.update();
      this.shieldBubble.setLocalScale(2.8, 2.6, 2.8);
      const rot = this.shieldBubble.getLocalEulerAngles();
      this.shieldBubble.setLocalEulerAngles(rot.x, rot.y + 0.5, rot.z);
    } else if (this.shieldBreakTime > 0) {
      const elapsed = Date.now() - this.shieldBreakTime;
      const duration = 250;
      const t = Math.min(elapsed / duration, 1);

      this.shieldBubble.enabled = true;
      const scale = 1 + t * 0.5;
      this.shieldBubble.setLocalScale(2.8 * scale, 2.6 * (1 + t * 0.15), 2.8 * scale);
      this.shieldMat.emissive = new pc.Color(1, 1, 1);
      this.shieldMat.opacity = 0.35 * (1 - t);
      this.shieldMat.update();

      for (const frag of this.shieldFragments) {
        const fragData = frag as any;
        const vel = fragData._vel as pc.Vec3;
        const p = frag.getLocalPosition();
        frag.setLocalPosition(p.x + vel.x * 0.016, p.y + vel.y * 0.016, p.z + vel.z * 0.016);
        vel.y -= 0.06;
        const fragMat = frag.render?.meshInstances[0]?.material as pc.StandardMaterial;
        if (fragMat) {
          fragMat.opacity = 0.7 * (1 - t);
          fragMat.update();
        }
        const r = frag.getLocalEulerAngles();
        frag.setLocalEulerAngles(r.x + 6, r.y, r.z + 9);
      }

      if (t >= 1) {
        this.shieldBreakTime = 0;
        this.shieldBubble.enabled = false;
        for (const frag of this.shieldFragments) frag.destroy();
        this.shieldFragments = [];
      }
    } else {
      this.shieldBubble.enabled = false;
    }

    // Explosion animation
    if (this.explosionTime > 0) {
      const elapsed = Date.now() - this.explosionTime;
      const duration = 600;
      const t = Math.min(elapsed / duration, 1);
      const e = 1 - (1 - t) * (1 - t);

      for (const part of this.explosionParts) {
        const mat = part.entity.render?.meshInstances[0]?.material as pc.StandardMaterial;
        if (!mat) continue;
        if (part.type === "fireball") {
          const s = 1.0 + e * 3.0;
          part.entity.setLocalScale(s, s, s);
          mat.opacity = 0.9 * (1 - t * t);
          mat.emissive = new pc.Color(1.0 - t * 0.6, Math.max(0, 0.6 - t * 0.6), Math.max(0, 0.1 * (1 - t)));
          mat.update();
        } else if (part.type === "debris" && part.vel) {
          const p = part.entity.getLocalPosition();
          part.entity.setLocalPosition(p.x + part.vel.x * 0.016, p.y + part.vel.y * 0.016, p.z + part.vel.z * 0.016);
          part.vel.y -= 0.08;
          const spin = part.spin!;
          const rot = part.entity.getLocalEulerAngles();
          part.entity.setLocalEulerAngles(rot.x + spin.x * 6, rot.y, rot.z + spin.z * 9);
          mat.opacity = 0.9 * (1 - t);
          mat.update();
        } else if (part.type === "ring") {
          const s = 1.0 + e * 4.0;
          part.entity.setLocalScale(s, 1, s);
          mat.opacity = 0.5 * (1 - t);
          mat.update();
        }
      }

      if (t >= 1) {
        this.explosionTime = 0;
        for (const part of this.explosionParts) part.entity.destroy();
        this.explosionParts = [];
      }
    }

    // Dead state — blink
    const tankVisible = !this.dead || Date.now() % 500 < 250;
    this.body.enabled = tankVisible;
    this.turret.enabled = tankVisible;
    this.teamIndicator.enabled = tankVisible;
  }

  setDead(val: boolean) {
    const wasDead = this.dead;
    this.dead = val;

    if (val && !wasDead) {
      this.explosionTime = Date.now();

      const fbMat = unlitMaterial(new pc.Color(1, 0.667, 0.133), 0.8);
      const fireball = new pc.Entity("fireball");
      fireball.addComponent("render", { type: "sphere", material: fbMat, castShadows: false });
      fireball.setLocalPosition(0, 1.0, 0);
      this.entity.addChild(fireball);
      this.explosionParts.push({ entity: fireball, type: "fireball" });

      const ringMat = unlitMaterial(new pc.Color(1, 0.4, 0), 0.5);
      const ring = new pc.Entity("ring");
      ring.addComponent("render", { type: "cylinder", material: ringMat, castShadows: false });
      ring.setLocalPosition(0, 0.05, 0);
      ring.setLocalScale(1.4, 0.02, 1.4);
      this.entity.addChild(ring);
      this.explosionParts.push({ entity: ring, type: "ring" });

      for (let i = 0; i < 10; i++) {
        const angle = (i / 10) * Math.PI * 2 + Math.random() * 0.5;
        const size = 0.1 + Math.random() * 0.15;
        const color = Math.random() > 0.5 ? new pc.Color(0.267, 0.267, 0.267) : new pc.Color(0.533, 0.4, 0.2);
        const dMat = unlitMaterial(color, 0.9);
        const debris = new pc.Entity("debris");
        debris.addComponent("render", { type: "box", material: dMat, castShadows: false });
        debris.setLocalPosition(Math.cos(angle) * 0.4, 0.5 + Math.random() * 1.0, Math.sin(angle) * 0.4);
        debris.setLocalScale(size, size, size);
        const speed = 0.15 + Math.random() * 0.15;
        this.entity.addChild(debris);
        this.explosionParts.push({
          entity: debris, type: "debris",
          vel: new pc.Vec3(Math.cos(angle) * speed, 0.12 + Math.random() * 0.15, Math.sin(angle) * speed),
          spin: { x: (Math.random() - 0.5) * 0.3, z: (Math.random() - 0.5) * 0.3 },
        });
      }
    }
  }

  setShield(val: number) {
    const wasActive = this.shieldActive;
    this.shieldActive = val > 0;

    if (wasActive && !this.shieldActive) {
      this.shieldBreakTime = Date.now();
      for (let i = 0; i < 8; i++) {
        const angle = (i / 8) * Math.PI * 2;
        const fragMat = unlitMaterial(new pc.Color(0.267, 0.8, 1), 0.7);
        fragMat.cull = pc.CULLFACE_NONE;
        fragMat.update();
        const frag = new pc.Entity("shard");
        frag.addComponent("render", { type: "box", material: fragMat, castShadows: false });
        frag.setLocalPosition(Math.cos(angle) * 1.4, 1.0 + Math.random() * 1.2, Math.sin(angle) * 1.4);
        frag.setLocalScale(0.25, 0.35, 0.04);
        frag.setLocalEulerAngles(Math.random() * 180, angle * (180 / Math.PI), Math.random() * 180);
        const speed = 0.12 + Math.random() * 0.08;
        (frag as any)._vel = new pc.Vec3(Math.cos(angle) * speed, 0.06 + Math.random() * 0.1, Math.sin(angle) * speed);
        this.entity.addChild(frag);
        this.shieldFragments.push(frag);
      }
    }
  }

  dispose() {
    this.entity.destroy();
  }
}
