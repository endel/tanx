import * as THREE from "three";
import { FBXLoader } from "three/examples/jsm/loaders/FBXLoader.js";

const TEAM_COLORS = [0xff4444, 0x4488ff, 0x44ff44, 0xffff44];
const TEAM_TEXTURES_PATHS = [
  "./models/T_pixelTank_red.png",
  "./models/T_pixelTank_blue.png",
  "./models/T_pixelTank_green.png",
  "./models/T_pixelTank_yellow.png",
];

let tankModelTemplate: THREE.Group | null = null;
let teamTextures: THREE.Texture[] = [];
let modelLoadPromise: Promise<THREE.Group> | null = null;

export function preloadTankModel(): Promise<THREE.Group> {
  if (modelLoadPromise) return modelLoadPromise;
  modelLoadPromise = new Promise((resolve, reject) => {
    const loader = new FBXLoader();
    const texLoader = new THREE.TextureLoader();

    // Load all team textures
    teamTextures = TEAM_TEXTURES_PATHS.map((path) => {
      const tex = texLoader.load(path);
      tex.magFilter = THREE.NearestFilter;
      tex.minFilter = THREE.NearestFilter;
      tex.colorSpace = THREE.SRGBColorSpace;
      return tex;
    });

    loader.load(
      "./models/pixelTank.fbx",
      (fbx) => {
        fbx.scale.setScalar(0.012);
        fbx.traverse((child) => {
          if ((child as THREE.Mesh).isMesh) {
            child.castShadow = true;
          }
        });
        tankModelTemplate = fbx;
        resolve(fbx);
      },
      undefined,
      reject
    );
  });
  return modelLoadPromise;
}

function makeTeamMaterial(team: number): THREE.MeshStandardMaterial {
  return new THREE.MeshStandardMaterial({
    map: teamTextures[team] || teamTextures[2],
    roughness: 0.8,
    metalness: 0.1,
  });
}

export class TankEntity {
  group = new THREE.Group();
  body = new THREE.Group();
  turret = new THREE.Group();
  teamIndicator: THREE.Mesh;
  healthBar: THREE.Sprite;
  healthBg: THREE.Sprite;
  shieldBubble: THREE.Mesh;

  targetX = 0;
  targetZ = 0;
  targetAngle = 0;
  currentTurretAngle = 0;
  targetBodyAngle = 0;
  currentBodyAngle = 0;
  dead = false;
  shieldActive = false;
  shieldBreakTime = 0;
  shieldFragments: THREE.Mesh[] = [];
  explosionTime = 0;
  explosionParts: THREE.Object3D[] = [];
  team = 0;

  constructor(team: number) {
    this.team = team;

    if (tankModelTemplate) {
      // Clone model twice: one for body, one for turret
      // Each hides the other's part — keeps transforms/scale/axis identical
      const bodyModel = tankModelTemplate.clone();
      const turretModel = tankModelTemplate.clone();

      const teamMat = makeTeamMaterial(team);

      // Body clone: apply team texture, hide turret parts
      bodyModel.traverse((child) => {
        if (child.name.toLowerCase().includes("turret")) {
          child.visible = false;
        } else if ((child as THREE.Mesh).isMesh) {
          (child as THREE.Mesh).material = teamMat;
        }
      });

      // Turret clone: apply team texture, hide body parts
      turretModel.traverse((child) => {
        if (
          (child as THREE.Mesh).isMesh &&
          !child.name.toLowerCase().includes("turret")
        ) {
          (child as THREE.Mesh).material = new THREE.MeshBasicMaterial({
            visible: false,
          });
        } else if ((child as THREE.Mesh).isMesh) {
          (child as THREE.Mesh).material = teamMat;
        }
      });

      this.body.add(bodyModel);

      // Turret mesh sits at (0, 1.125, -0.3) after scale.
      // Move turret group pivot to that Z so it rotates in place.
      this.turret.position.set(0, 0, -0.3);
      turretModel.position.z += 0.3; // counter-offset the model
      this.turret.add(turretModel);
    } else {
      this.createFallbackTank();
    }

    this.group.add(this.body);
    this.group.add(this.turret);

    // Team color indicator (ring under tank)
    const ringGeo = new THREE.RingGeometry(0.9, 1.2, 20);
    ringGeo.rotateX(-Math.PI / 2);
    this.teamIndicator = new THREE.Mesh(
      ringGeo,
      new THREE.MeshBasicMaterial({
        color: TEAM_COLORS[team] || 0xffffff,
        transparent: true,
        opacity: 0.7,
      })
    );
    this.teamIndicator.position.y = 0.02;
    this.group.add(this.teamIndicator);

    // Health bar (floating above tank, billboard sprites)
    const hbBgMat = new THREE.SpriteMaterial({
      color: 0x333333,
      transparent: true,
      opacity: 0.6,
    });
    this.healthBg = new THREE.Sprite(hbBgMat);
    this.healthBg.scale.set(1.4, 0.15, 1);
    this.healthBg.position.y = 2.2;
    this.group.add(this.healthBg);

    const hbMat = new THREE.SpriteMaterial({ color: 0x44ff44 });
    this.healthBar = new THREE.Sprite(hbMat);
    this.healthBar.scale.set(1.4, 0.15, 1);
    this.healthBar.position.y = 2.2;
    this.group.add(this.healthBar);

    // Shield bubble (translucent cylinder force field)
    const shieldGeo = new THREE.CylinderGeometry(1.4, 1.4, 2.6, 20, 1, true);
    const shieldMat = new THREE.MeshBasicMaterial({
      color: 0x44ccff,
      transparent: true,
      opacity: 0.12,
      side: THREE.DoubleSide,
      depthWrite: false,
    });
    this.shieldBubble = new THREE.Mesh(shieldGeo, shieldMat);
    this.shieldBubble.position.y = 1.3;
    this.shieldBubble.visible = false;
    this.group.add(this.shieldBubble);
  }

  private createFallbackTank() {
    // Body
    const bodyGeo = new THREE.BoxGeometry(1.0, 0.4, 1.4);
    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x668866,
      roughness: 0.7,
    });
    const bodyMesh = new THREE.Mesh(bodyGeo, bodyMat);
    bodyMesh.position.y = 0.3;
    bodyMesh.castShadow = true;
    this.body.add(bodyMesh);

    // Tracks
    for (const side of [-0.55, 0.55]) {
      const trackGeo = new THREE.BoxGeometry(0.2, 0.25, 1.5);
      const track = new THREE.Mesh(
        trackGeo,
        new THREE.MeshStandardMaterial({ color: 0x444444 })
      );
      track.position.set(side, 0.2, 0);
      track.castShadow = true;
      this.body.add(track);
    }

    // Turret (sibling of body, rotates independently)
    const tBaseGeo = new THREE.CylinderGeometry(0.35, 0.4, 0.25, 8);
    const tBase = new THREE.Mesh(
      tBaseGeo,
      new THREE.MeshStandardMaterial({ color: 0x557755 })
    );
    tBase.position.y = 0.55;
    this.turret.add(tBase);

    const barrelGeo = new THREE.CylinderGeometry(0.06, 0.08, 1.0, 6);
    barrelGeo.rotateX(Math.PI / 2);
    barrelGeo.translate(0, 0, 0.5);
    const barrel = new THREE.Mesh(
      barrelGeo,
      new THREE.MeshStandardMaterial({ color: 0x555555 })
    );
    barrel.position.y = 0.55;
    this.turret.add(barrel);
  }

  update(dt: number) {
    // Compute movement delta before lerping
    const moveX = this.targetX - this.group.position.x;
    const moveZ = this.targetZ - this.group.position.z;
    const moveDist = Math.sqrt(moveX * moveX + moveZ * moveZ);

    // Smooth position interpolation
    this.group.position.x = THREE.MathUtils.lerp(
      this.group.position.x,
      this.targetX,
      0.2
    );
    this.group.position.z = THREE.MathUtils.lerp(
      this.group.position.z,
      this.targetZ,
      0.2
    );

    // Rotate body toward movement direction
    if (moveDist > 0.02) {
      this.targetBodyAngle = Math.atan2(moveX, moveZ);
    }
    let bodyDiff = this.targetBodyAngle - this.currentBodyAngle;
    while (bodyDiff > Math.PI) bodyDiff -= Math.PI * 2;
    while (bodyDiff < -Math.PI) bodyDiff += Math.PI * 2;
    this.currentBodyAngle += bodyDiff * 0.15;
    this.body.rotation.y = this.currentBodyAngle;

    // Turret aim (absolute — turret is sibling of body, not a child)
    const targetTurretRad = this.targetAngle * (Math.PI / 180);
    let turretDiff = targetTurretRad - this.currentTurretAngle;
    while (turretDiff > Math.PI) turretDiff -= Math.PI * 2;
    while (turretDiff < -Math.PI) turretDiff += Math.PI * 2;
    this.currentTurretAngle += turretDiff * 0.25;
    this.turret.rotation.y = this.currentTurretAngle;

    // Keep turret pivot aligned with the body's mount point as body rotates
    const mountZ = -0.3;
    this.turret.position.x = mountZ * Math.sin(this.currentBodyAngle);
    this.turret.position.z = mountZ * Math.cos(this.currentBodyAngle);

    // Shield bubble pulse
    if (this.shieldActive) {
      this.shieldBubble.visible = true;
      const pulse = 0.10 + Math.sin(Date.now() * 0.004) * 0.05;
      (this.shieldBubble.material as THREE.MeshBasicMaterial).opacity = pulse;
      (this.shieldBubble.material as THREE.MeshBasicMaterial).color.setHex(0x44ccff);
      this.shieldBubble.scale.set(1, 1, 1);
      this.shieldBubble.rotation.y += 0.008;
    } else if (this.shieldBreakTime > 0) {
      // Shield break animation
      const elapsed = Date.now() - this.shieldBreakTime;
      const duration = 250;
      const t = Math.min(elapsed / duration, 1);

      // Bubble expands and flashes then fades
      this.shieldBubble.visible = true;
      const scale = 1 + t * 0.5;
      this.shieldBubble.scale.set(scale, 1 + t * 0.15, scale);
      const mat = this.shieldBubble.material as THREE.MeshBasicMaterial;
      mat.color.setHex(0xffffff);
      mat.opacity = 0.35 * (1 - t);

      // Animate fragments outward
      for (const frag of this.shieldFragments) {
        const vel = (frag as any)._vel as THREE.Vector3;
        frag.position.add(vel.clone().multiplyScalar(0.016));
        vel.y -= 0.06; // gravity
        const fragMat = frag.material as THREE.MeshBasicMaterial;
        fragMat.opacity = 0.7 * (1 - t);
        frag.rotation.x += 0.1;
        frag.rotation.z += 0.15;
      }

      if (t >= 1) {
        this.shieldBreakTime = 0;
        this.shieldBubble.visible = false;
        // Clean up fragments
        for (const frag of this.shieldFragments) {
          this.group.remove(frag);
          frag.geometry.dispose();
        }
        this.shieldFragments = [];
      }
    } else {
      this.shieldBubble.visible = false;
    }

    // Explosion animation
    if (this.explosionTime > 0) {
      const elapsed = Date.now() - this.explosionTime;
      const duration = 600;
      const t = Math.min(elapsed / duration, 1);
      // Ease-out: fast start, slow end
      const e = 1 - (1 - t) * (1 - t);

      for (const part of this.explosionParts) {
        const data = part as any;
        if (data._type === "fireball") {
          const s = 1.0 + e * 3.0;
          part.scale.set(s, s, s);
          const mat = (part as THREE.Mesh).material as THREE.MeshBasicMaterial;
          mat.opacity = 0.9 * (1 - t * t);
          const r = 1.0 - t * 0.6;
          const g = 0.6 - t * 0.6;
          const b = 0.1 * (1 - t);
          mat.color.setRGB(r, Math.max(0, g), Math.max(0, b));
        } else if (data._type === "debris") {
          const vel = data._vel as THREE.Vector3;
          part.position.add(vel.clone().multiplyScalar(0.016));
          vel.y -= 0.08;
          part.rotation.x += data._spin.x;
          part.rotation.z += data._spin.z;
          const mat = (part as THREE.Mesh).material as THREE.MeshBasicMaterial;
          mat.opacity = 0.9 * (1 - t);
        } else if (data._type === "ring") {
          const s = 1.0 + e * 4.0;
          part.scale.set(s, 1, s);
          const mat = (part as THREE.Mesh).material as THREE.MeshBasicMaterial;
          mat.opacity = 0.5 * (1 - t);
        }
      }

      if (t >= 1) {
        this.explosionTime = 0;
        for (const part of this.explosionParts) {
          this.group.remove(part);
          if ((part as THREE.Mesh).geometry) (part as THREE.Mesh).geometry.dispose();
        }
        this.explosionParts = [];
      }
    }

    // Dead state — blink individual parts, not the whole group
    const tankVisible = !this.dead || Date.now() % 500 < 250;
    this.body.visible = tankVisible;
    this.turret.visible = tankVisible;
    this.teamIndicator.visible = tankVisible;
    this.healthBar.visible = tankVisible;
    this.healthBg.visible = tankVisible;
  }

  setDead(val: boolean) {
    const wasDead = this.dead;
    this.dead = val;

    if (val && !wasDead) {
      this.explosionTime = Date.now();

      // Fireball — expanding glowing sphere
      const fbGeo = new THREE.SphereGeometry(0.5, 10, 10);
      const fbMat = new THREE.MeshBasicMaterial({
        color: 0xffaa22,
        transparent: true,
        opacity: 0.8,
        depthWrite: false,
      });
      const fireball = new THREE.Mesh(fbGeo, fbMat);
      fireball.position.y = 1.0;
      (fireball as any)._type = "fireball";
      this.group.add(fireball);
      this.explosionParts.push(fireball);

      // Shockwave ring on the ground
      const ringGeo = new THREE.RingGeometry(0.4, 0.7, 20);
      ringGeo.rotateX(-Math.PI / 2);
      const ringMat = new THREE.MeshBasicMaterial({
        color: 0xff6600,
        transparent: true,
        opacity: 0.5,
        side: THREE.DoubleSide,
        depthWrite: false,
      });
      const ring = new THREE.Mesh(ringGeo, ringMat);
      ring.position.y = 0.05;
      (ring as any)._type = "ring";
      this.group.add(ring);
      this.explosionParts.push(ring);

      // Debris chunks
      for (let i = 0; i < 10; i++) {
        const angle = (i / 10) * Math.PI * 2 + Math.random() * 0.5;
        const size = 0.1 + Math.random() * 0.15;
        const geo = new THREE.BoxGeometry(size, size, size);
        const mat = new THREE.MeshBasicMaterial({
          color: Math.random() > 0.5 ? 0x444444 : 0x886633,
          transparent: true,
          opacity: 0.9,
          depthWrite: false,
        });
        const debris = new THREE.Mesh(geo, mat);
        debris.position.set(
          Math.cos(angle) * 0.4,
          0.5 + Math.random() * 1.0,
          Math.sin(angle) * 0.4
        );
        const speed = 0.15 + Math.random() * 0.15;
        (debris as any)._type = "debris";
        (debris as any)._vel = new THREE.Vector3(
          Math.cos(angle) * speed,
          0.12 + Math.random() * 0.15,
          Math.sin(angle) * speed
        );
        (debris as any)._spin = {
          x: (Math.random() - 0.5) * 0.3,
          z: (Math.random() - 0.5) * 0.3,
        };
        this.group.add(debris);
        this.explosionParts.push(debris);
      }
    }
  }

  setShield(val: number) {
    const wasActive = this.shieldActive;
    this.shieldActive = val > 0;

    // Shield just broke — trigger break animation
    if (wasActive && !this.shieldActive) {
      this.shieldBreakTime = Date.now();

      // Spawn shard fragments flying outward
      for (let i = 0; i < 8; i++) {
        const angle = (i / 8) * Math.PI * 2;
        const geo = new THREE.PlaneGeometry(0.25, 0.35);
        const mat = new THREE.MeshBasicMaterial({
          color: 0x44ccff,
          transparent: true,
          opacity: 0.7,
          side: THREE.DoubleSide,
          depthWrite: false,
        });
        const frag = new THREE.Mesh(geo, mat);
        frag.position.set(
          Math.cos(angle) * 1.4,
          1.0 + Math.random() * 1.2,
          Math.sin(angle) * 1.4
        );
        frag.rotation.set(Math.random() * Math.PI, angle, Math.random() * Math.PI);
        // Store velocity on the mesh
        const speed = 0.12 + Math.random() * 0.08;
        (frag as any)._vel = new THREE.Vector3(
          Math.cos(angle) * speed,
          0.06 + Math.random() * 0.1,
          Math.sin(angle) * speed
        );
        this.group.add(frag);
        this.shieldFragments.push(frag);
      }
    }
  }

  setHealth(hp: number) {
    const pct = Math.max(0, hp / 10);
    this.healthBar.scale.set(1.4 * pct, 0.15, 1);
    this.healthBar.position.x = -(1.4 * (1 - pct)) / 2;

    const mat = this.healthBar.material as THREE.SpriteMaterial;
    if (pct > 0.5) {
      mat.color.setHex(0x44ff44);
    } else if (pct > 0.25) {
      mat.color.setHex(0xffaa44);
    } else {
      mat.color.setHex(0xff4444);
    }
  }

  dispose() {
    this.group.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        (child as THREE.Mesh).geometry?.dispose();
      }
    });
  }
}
