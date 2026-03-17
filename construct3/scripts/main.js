// =============================================================================
// Realtime Tanks Demo - Construct 3 Client (Event Sheet + Script Hybrid)
// =============================================================================

// --- Constants (matching server) ---
const UNIT_SIZE = 32;
const MAP_SIZE = 48;
const MAP_PIXELS = MAP_SIZE * UNIT_SIZE;

const TANK_RADIUS = 0.75;
const BULLET_RADIUS = 0.25;

const LERP_POSITION = 0.2;
const LERP_BODY_ROTATION = 0.15;
const LERP_TURRET_ROTATION = 0.25;
const LERP_CAMERA = 0.08;
const LERP_BULLET = 0.4;

const DEG_TO_RAD = Math.PI / 180;
const RAD_TO_DEG = 180 / Math.PI;

const TEAM_ANIMS = ["Red", "Blue", "Green", "Yellow"]; // Animation names (case-sensitive)
const TEAM_LABELS = ["RED", "BLUE", "GREEN", "YELLOW"];
const TEAM_COLORS_CSS = ["#ff4444", "#4488ff", "#44ff44", "#ffff44"];
const TEAM_COLORS_RGB = [[1, 0.27, 0.27], [0.27, 0.53, 1], [0.27, 1, 0.27], [1, 1, 0.27]];

// Level blocks: [centerX, centerY, width, height]
const LEVEL_BLOCKS = [
	[13.5, 2, 1, 4], [13.5, 12, 1, 2], [12.5, 13.5, 3, 1], [2, 13.5, 4, 1],
	[11.5, 15, 1, 2], [11.5, 23.5, 1, 5], [10, 26.5, 4, 1], [6, 26.5, 4, 1],
	[2, 34.5, 4, 1], [12.5, 34.5, 3, 1], [13.5, 36, 1, 2], [15, 36.5, 2, 1],
	[13.5, 46, 1, 4], [23.5, 36.5, 5, 1], [26.5, 38, 1, 4], [26.5, 42, 1, 4],
	[34.5, 46, 1, 4], [34.5, 36, 1, 2], [35.5, 34.5, 3, 1], [36.5, 33, 1, 2],
	[46, 34.5, 4, 1], [36.5, 24.5, 1, 5], [38, 21.5, 4, 1], [42, 21.5, 4, 1],
	[46, 13.5, 4, 1], [35.5, 13.5, 3, 1], [34.5, 12, 1, 2], [33, 11.5, 2, 1],
	[34.5, 2, 1, 4], [24.5, 11.5, 5, 1], [21.5, 10, 1, 4], [21.5, 6, 1, 4],
	// center
	[18.5, 22, 1, 6], [19, 18.5, 2, 1], [26, 18.5, 6, 1], [29.5, 19, 1, 2],
	[29.5, 26, 1, 6], [29, 29.5, 2, 1], [22, 29.5, 6, 1], [18.5, 29, 1, 2],
];

// Wall definitions: [centerX, centerY, width, height]
const WALLS = [
	[MAP_SIZE / 2, 0.75, MAP_SIZE, 1.5],         // Top
	[MAP_SIZE / 2, MAP_SIZE - 0.75, MAP_SIZE, 1.5], // Bottom
	[0.75, MAP_SIZE / 2, 1.5, MAP_SIZE],           // Left
	[MAP_SIZE - 0.75, MAP_SIZE / 2, 1.5, MAP_SIZE], // Right
];

// =============================================================================
// Game State
// =============================================================================

let mySessionId = "";

// Entity tracking
const tanks = {};       // sessionId -> { body, barrel, data }
const bullets = {};     // key -> { instance, data }
const pickables = {};   // key -> { instance, data }
const blockInstances = [];

// Team scores
const teamScores = [0, 0, 0, 0];

// Winner
let winnerTeam = -1;

// Input state
let lastMoveX = 0;
let lastMoveY = 0;
let lastAimAngle = 0;
let lastTargetSendTime = 0;
let isShooting = false;

// Camera
let camX = MAP_PIXELS / 2;
let camY = MAP_PIXELS / 2;
let cameraSnapped = false;

// HUD instances (created lazily)
let hudDestroyedText = null;
let hudWinText = null;
let hudWinSubText = null;
let hudLeaderboard = null; // array of { label, score } text instances

// =============================================================================
// Utility Functions
// =============================================================================

function lerp(a, b, t) {
	return a + (b - a) * t;
}

function lerpAngle(current, target, amount) {
	let diff = target - current;
	// Normalize to [-PI, PI]
	while (diff > Math.PI) diff -= 2 * Math.PI;
	while (diff < -Math.PI) diff += 2 * Math.PI;
	return current + diff * amount;
}

function clamp(val, min, max) {
	return Math.max(min, Math.min(max, val));
}

/** Convert server angle (0=south, 90=east) to C3 radians (sprite faces UP at 0) */
function serverAngleToC3(serverAngleDeg) {
	return (180 - serverAngleDeg) * DEG_TO_RAD;
}

/** Compute server-format aim angle from tank to mouse (world pixels) */
function clientAimAngle(tankX, tankY, mouseX, mouseY) {
	const dx = mouseX - tankX;
	const dy = mouseY - tankY;
	// atan2(dx, dy) matches the server convention (0=south, 90=east)
	let a = Math.atan2(dx, dy) * RAD_TO_DEG;
	return ((a % 360) + 360) % 360;
}

/** Compute C3 body angle from movement delta (sprite faces UP at 0) */
function movementToBodyAngle(dx, dy) {
	// atan2(dy, dx) gives screen angle (0=right, PI/2=down)
	// Add PI/2 because sprite faces UP at angle 0
	return Math.atan2(dy, dx) + Math.PI / 2;
}

// =============================================================================
// Level Setup
// =============================================================================

function spawnBlocks(runtime) {
	// Spawn blocks
	for (const [cx, cy, w, h] of LEVEL_BLOCKS) {
		const inst = runtime.objects.Block.createInstance("Layer 0",
			cx * UNIT_SIZE, cy * UNIT_SIZE);
		inst.width = w * UNIT_SIZE;
		inst.height = h * UNIT_SIZE;
		inst.colorRgb = [0.15, 0.35, 0.6];
		inst.opacity = 0.7;
		blockInstances.push(inst);
	}

	// Spawn wall borders
	for (const [cx, cy, w, h] of WALLS) {
		const inst = runtime.objects.Block.createInstance("Layer 0",
			cx * UNIT_SIZE, cy * UNIT_SIZE);
		inst.width = w * UNIT_SIZE;
		inst.height = h * UNIT_SIZE;
		inst.colorRgb = [0.1, 0.27, 0.53];
		inst.opacity = 0.9;
		blockInstances.push(inst);
	}
}

// =============================================================================
// Input
// =============================================================================

function handleInput(runtime) {
	if (!mySessionId) return;

	const kb = runtime.keyboard;

	// --- Movement ---
	let mx = 0, my = 0;
	if (kb.isKeyDown("KeyD") || kb.isKeyDown("ArrowRight")) mx = 1;
	if (kb.isKeyDown("KeyA") || kb.isKeyDown("ArrowLeft")) mx = -1;
	if (kb.isKeyDown("KeyS") || kb.isKeyDown("ArrowDown")) my = 1;
	if (kb.isKeyDown("KeyW") || kb.isKeyDown("ArrowUp")) my = -1;

	if (mx !== lastMoveX || my !== lastMoveY) {
		lastMoveX = mx;
		lastMoveY = my;
		runtime.callFunction("sendMove", mx, my);
	}

	// --- Aim ---
	const myTank = tanks[mySessionId];
	if (myTank) {
		const [mouseX, mouseY] = runtime.mouse.getMousePosition("Layer 0");
		const aimAngle = clientAimAngle(myTank.body.x, myTank.body.y, mouseX, mouseY);
		const aimRounded = Math.round(aimAngle);

		// Always update local turret immediately (smooth visual)
		myTank.serverAngle = aimRounded;

		const now = performance.now();
		if (Math.abs(aimRounded - lastAimAngle) > 1 && now - lastTargetSendTime >= 100) {
			lastAimAngle = aimRounded;
			lastTargetSendTime = now;
			runtime.callFunction("sendTarget", aimRounded);
		}
	}

	// --- Shoot ---
	const mouseDown = runtime.mouse.isMouseButtonDown(0);
	if (mouseDown && !isShooting) {
		isShooting = true;
		runtime.callFunction("sendShoot", 1);
	} else if (!mouseDown && isShooting) {
		isShooting = false;
		runtime.callFunction("sendShoot", 0);
	}
}

// =============================================================================
// Tank Updates
// =============================================================================

function updateTanks(dt, runtime) {
	for (const [key, data] of Object.entries(tanks)) {
		const { body, barrel } = data;

		// --- Position interpolation ---
		body.x = lerp(body.x, data.targetX, LERP_POSITION);
		body.y = lerp(body.y, data.targetY, LERP_POSITION);

		// Barrel follows body
		barrel.x = body.x;
		barrel.y = body.y;

		// --- Body rotation (from movement direction) ---
		const dx = body.x - data.prevX;
		const dy = body.y - data.prevY;
		if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
			const targetBodyAngle = movementToBodyAngle(dx, dy);
			data.bodyAngle = lerpAngle(data.bodyAngle, targetBodyAngle, LERP_BODY_ROTATION);
		}
		body.angle = data.bodyAngle;
		data.prevX = body.x;
		data.prevY = body.y;

		// --- Turret rotation ---
		const targetTurret = serverAngleToC3(data.serverAngle);
		data.turretAngle = lerpAngle(data.turretAngle, targetTurret, LERP_TURRET_ROTATION);
		barrel.angle = data.turretAngle;

		// --- Health bar + shield bar + name tag ---
		const barYOff = -35;
		const shieldBarYOff = barYOff - 6;
		const BAR_W = 40;

		if (data.hpBarBg) {
			const hpPct = Math.max(0, Math.min(1, data.hp / 10));
			// Position
			data.hpBarBg.x = body.x;
			data.hpBarBg.y = body.y + barYOff;
			data.hpBarFill.x = body.x - BAR_W / 2 * (1 - hpPct);
			data.hpBarFill.y = body.y + barYOff;
			data.hpBarFill.width = BAR_W * hpPct;
			// Color by HP
			if (hpPct > 0.5) data.hpBarFill.colorRgb = [0.5, 1.0, 0.5];
			else if (hpPct > 0.25) data.hpBarFill.colorRgb = [1.0, 0.8, 0.3];
			else data.hpBarFill.colorRgb = [1.0, 0.4, 0.4];
			// Hide when dead
			data.hpBarBg.isVisible = !data.dead;
			data.hpBarFill.isVisible = !data.dead;
		}

		if (data.shieldBarBg) {
			const shieldPct = Math.max(0, Math.min(1, data.shield / 10));
			data.shieldBarBg.x = body.x;
			data.shieldBarBg.y = body.y + shieldBarYOff;
			data.shieldBarFill.x = body.x - BAR_W / 2 * (1 - shieldPct);
			data.shieldBarFill.y = body.y + shieldBarYOff;
			data.shieldBarFill.width = BAR_W * shieldPct;
			data.shieldBarBg.isVisible = data.shield > 0 && !data.dead;
			data.shieldBarFill.isVisible = data.shield > 0 && !data.dead;
		}

		if (data.nameTag) {
			data.nameTag.x = body.x - 40;
			data.nameTag.y = body.y - 58;
			data.nameTag.isVisible = !data.dead;
		}

		// --- Shield bubble ---
		if (data.shieldInst) {
			data.shieldInst.x = body.x;
			data.shieldInst.y = body.y;
			if (data.shield > 0 && !data.dead) {
				data.shieldInst.isVisible = true;
				data.shieldPulse += 0.05;
				data.shieldInst.opacity = 0.2 + Math.sin(data.shieldPulse) * 0.1;
			} else {
				data.shieldInst.isVisible = false;
			}
		}

		// --- Shield break effect ---
		if (data.shieldBreakActive) {
			data.shieldBreakTimer -= dt;
			if (data.shieldBreakTimer <= 0) {
				data.shieldBreakActive = false;
				if (data.shieldBreakInst) {
					data.shieldBreakInst.destroy();
					data.shieldBreakInst = null;
				}
			} else {
				if (!data.shieldBreakInst) {
					data.shieldBreakInst = runtime.objects.Shield.createInstance("Layer 0", body.x, body.y);
					data.shieldBreakInst.colorRgb = [0.3, 0.6, 1.0];
				}
				const t = 1 - (data.shieldBreakTimer / 0.4); // 0→1
				const breakSize = (TANK_RADIUS * UNIT_SIZE * 4.0) + t * 4 * UNIT_SIZE;
				data.shieldBreakInst.x = body.x;
				data.shieldBreakInst.y = body.y;
				data.shieldBreakInst.width = breakSize;
				data.shieldBreakInst.height = breakSize;
				data.shieldBreakInst.opacity = (1 - t) * 0.6;
			}
		}

		// --- Death blinking ---
		if (data.dead) {
			data.blinkTimer += dt;
			const blink = Math.floor(data.blinkTimer / 0.5) % 2 === 0;
			body.isVisible = blink;
			barrel.isVisible = blink;
			body.opacity = 0.5;
			barrel.opacity = 0.5;
		} else {
			body.isVisible = true;
			barrel.isVisible = true;
			body.opacity = 1;
			barrel.opacity = 1;
			data.blinkTimer = 0;
		}

		// --- Explosion effect ---
		if (data.explosionActive) {
			data.explosionTimer -= dt;
			if (data.explosionTimer <= 0) {
				data.explosionActive = false;
				// Clean up explosion sprite
				if (data.explosionInst) {
					data.explosionInst.destroy();
					data.explosionInst = null;
				}
			} else {
				// Create explosion sprite on first frame
				if (!data.explosionInst) {
					data.explosionInst = runtime.objects.Shield.createInstance("Layer 0", body.x, body.y);
					data.explosionInst.colorRgb = [1.0, 0.6, 0.1]; // orange
				}
				const t = 1 - (data.explosionTimer / 0.6); // 0→1
				const expSize = t * 6 * UNIT_SIZE;
				data.explosionInst.x = body.x;
				data.explosionInst.y = body.y;
				data.explosionInst.width = expSize;
				data.explosionInst.height = expSize;
				data.explosionInst.opacity = (1 - t) * 0.8;
			}
		}
	}
}

// =============================================================================
// Pickable Updates (bobbing animation)
// =============================================================================

function updatePickables(dt) {
	for (const [key, data] of Object.entries(pickables)) {
		data.bobOffset += dt * 3;
		data.instance.y = data.baseY + Math.sin(data.bobOffset) * 4;
	}
}

// =============================================================================
// Bullet Updates
// =============================================================================

function updateBullets(dt) {
	for (const [key, data] of Object.entries(bullets)) {
		const inst = data.instance;

		// Interpolate
		const prevX = inst.x;
		const prevY = inst.y;
		inst.x = lerp(inst.x, data.targetX, LERP_BULLET);
		inst.y = lerp(inst.y, data.targetY, LERP_BULLET);

		// Rotation from movement direction
		const dx = inst.x - prevX;
		const dy = inst.y - prevY;
		if (Math.abs(dx) > 0.1 || Math.abs(dy) > 0.1) {
			inst.angle = Math.atan2(dy, dx) + Math.PI / 2;
		}
	}
}

// =============================================================================
// Camera
// =============================================================================

function updateCamera(runtime) {
	const myTank = tanks[mySessionId];
	if (!myTank) return;

	const vpW = runtime.viewportWidth;
	const vpH = runtime.viewportHeight;

	// Snap camera to player immediately on first frame
	if (!cameraSnapped) {
		cameraSnapped = true;
		camX = myTank.body.x;
		camY = myTank.body.y;
		runtime.layout.scrollX = camX;
		runtime.layout.scrollY = camY;
		return; // skip look-ahead on first frame (mouse pos is unreliable)
	}

	// Look-ahead: offset camera toward mouse direction
	const [mouseX, mouseY] = runtime.mouse.getMousePosition("Layer 0");
	const dx = mouseX - myTank.body.x;
	const dy = mouseY - myTank.body.y;
	const dist = Math.sqrt(dx * dx + dy * dy);
	const lookDist = 3 * UNIT_SIZE;
	// Clamp look-ahead so distant mouse (e.g. at screen edge) doesn't overshoot
	const maxRange = 6 * UNIT_SIZE;
	const lookMult = Math.min(dist / maxRange, 1);
	const lookX = dist > 1 ? (dx / dist) * lookDist * lookMult : 0;
	const lookY = dist > 1 ? (dy / dist) * lookDist * lookMult : 0;

	const targetX = myTank.body.x + lookX;
	const targetY = myTank.body.y + lookY;

	camX = lerp(camX, targetX, LERP_CAMERA);
	camY = lerp(camY, targetY, LERP_CAMERA);

	// Clamp to world bounds
	camX = clamp(camX, vpW / 2, MAP_PIXELS - vpW / 2);
	camY = clamp(camY, vpH / 2, MAP_PIXELS - vpH / 2);

	runtime.layout.scrollX = camX;
	runtime.layout.scrollY = camY;
}

// =============================================================================
// HUD (screen-space UI on "UI" layer)
// =============================================================================

function updateHUD(runtime) {
	const myTank = tanks[mySessionId];
	const vpW = runtime.viewportWidth;
	const vpH = runtime.viewportHeight;

	// --- Leaderboard (top-right) ---
	if (!hudLeaderboard) {
		hudLeaderboard = [];
		const lbX = vpW - 150;
		const lbBg = runtime.objects.Block.createInstance("UI", lbX + 70, 58);
		lbBg.width = 150;
		lbBg.height = 110;
		lbBg.colorRgb = [0.85, 0.85, 0.9];
		lbBg.opacity = 0.9;
		hudLeaderboard.bg = lbBg;

		// Bright team colors for readability on dark background
		const LB_COLORS = [
			[0.8, 0.1, 0.1],  // red on light bg
			[0.1, 0.3, 0.8],  // blue on light bg
			[0.1, 0.6, 0.1],  // green on light bg
			[0.7, 0.6, 0.0],  // yellow/gold on light bg
		];

		for (let i = 0; i < 4; i++) {
			const y = 16 + i * 24;
			const label = runtime.objects.HUDText.createInstance("UI", lbX + 5, y);
			label.width = 85;
			label.height = 22;
			label.sizePt = 12;
			label.isBold = true;
			label.fontColor = LB_COLORS[i];
			label.text = TEAM_LABELS[i];

			const score = runtime.objects.HUDText.createInstance("UI", lbX + 95, y);
			score.width = 45;
			score.height = 22;
			score.sizePt = 12;
			score.isBold = true;
			score.fontColor = [0.1, 0.1, 0.1];
			score.horizontalAlign = "right";
			score.text = "0";

			hudLeaderboard.push({ label, score });
		}
	}

	// Update scores
	for (let i = 0; i < 4; i++) {
		if (hudLeaderboard[i]) {
			hudLeaderboard[i].score.text = String(teamScores[i] || 0);
		}
	}

	// --- "DESTROYED" text ---
	const showDestroyed = myTank && myTank.dead && winnerTeam < 0;
	if (showDestroyed) {
		if (!hudDestroyedText) {
			hudDestroyedText = runtime.objects.HUDText.createInstance("UI", vpW / 2 - 100, vpH / 2 - 20);
			hudDestroyedText.width = 200;
			hudDestroyedText.height = 40;
			hudDestroyedText.sizePt = 24;
			hudDestroyedText.isBold = true;
			hudDestroyedText.fontColor = [1, 0.2, 0.2];
			hudDestroyedText.horizontalAlign = "center";
		}
		hudDestroyedText.text = "DESTROYED";
		hudDestroyedText.isVisible = true;
	} else if (hudDestroyedText) {
		hudDestroyedText.isVisible = false;
	}

	// --- WIN / LOSE screen ---
	if (winnerTeam >= 0) {
		if (!hudWinText) {
			hudWinText = runtime.objects.HUDText.createInstance("UI", vpW / 2 - 150, vpH / 2 - 30);
			hudWinText.width = 300;
			hudWinText.height = 36;
			hudWinText.sizePt = 22;
			hudWinText.isBold = true;
			hudWinText.fontColor = [1, 1, 1];
			hudWinText.horizontalAlign = "center";
		}
		if (!hudWinSubText) {
			hudWinSubText = runtime.objects.HUDText.createInstance("UI", vpW / 2 - 100, vpH / 2 + 10);
			hudWinSubText.width = 200;
			hudWinSubText.height = 30;
			hudWinSubText.sizePt = 18;
			hudWinSubText.isBold = true;
			hudWinSubText.horizontalAlign = "center";
		}

		hudWinText.text = "TEAM " + TEAM_LABELS[winnerTeam] + " WINS!";
		hudWinText.fontColor = TEAM_COLORS_RGB[winnerTeam] || [1, 1, 1];
		hudWinText.isVisible = true;

		const isVictory = myTank && winnerTeam === myTank.team;
		hudWinSubText.text = isVictory ? "VICTORY!" : "DEFEAT";
		hudWinSubText.fontColor = isVictory ? [0.2, 1, 0.2] : [1, 0.2, 0.2];
		hudWinSubText.isVisible = true;

		// Hide destroyed text during win screen
		if (hudDestroyedText) hudDestroyedText.isVisible = false;
	} else {
		if (hudWinText) hudWinText.isVisible = false;
		if (hudWinSubText) hudWinSubText.isVisible = false;
	}
}

// =============================================================================
// Global Game Interface (called from event sheet inline scripts)
// =============================================================================

globalThis.game = {
	// Access the Colyseus addon's SDK instance to read lastKey/lastValue directly
	_colyseusInst: null,
	getColyseus(runtime) {
		if (!this._colyseusInst) {
			// Find the SDK instance by walking the wrapper
			const wrapper = runtime.objects.Colyseus.getFirstInstance();
			// Try various known C3 internal paths
			const candidates = [
				wrapper?._inst?._sdkInst,
				wrapper?._sdkInst,
				wrapper?.sdkInstance,
				// Walk all own properties looking for the one with 'lastKey'
			];
			for (const c of candidates) {
				if (c && 'lastKey' in c) { this._colyseusInst = c; break; }
			}
			if (!this._colyseusInst) {
				// Brute-force: search wrapper's properties
				const search = (obj, depth) => {
					if (!obj || depth > 3) return null;
					if (obj.lastKey !== undefined || obj.sessionId !== undefined) return obj;
					for (const key of Object.getOwnPropertyNames(obj)) {
						if (key.startsWith('_') || key === 'constructor') {
							try {
								const child = obj[key];
								if (child && typeof child === 'object') {
									const found = search(child, depth + 1);
									if (found) return found;
								}
							} catch(e) {}
						}
					}
					return null;
				};
				this._colyseusInst = search(wrapper, 0);
			}
			if (!this._colyseusInst) {
				console.error("Could not find Colyseus SDK instance. Available on wrapper:", Object.getOwnPropertyNames(wrapper));
				// Fallback: return wrapper itself
				this._colyseusInst = wrapper;
			}
		}
		return this._colyseusInst;
	},

	onJoinRoom(runtime) {
		const c = this.getColyseus(runtime);
		mySessionId = c.sessionId || c.room?.sessionId || "";
		spawnBlocks(runtime);
		console.log("Joined room, session:", mySessionId);
	},

	onTankAdded(runtime, key, tank) {
		console.log("Tank added:", key);

		const px = tank.x * UNIT_SIZE;
		const py = tank.y * UNIT_SIZE;

		const body = runtime.objects.TankBody.createInstance("Layer 0", px, py);
		const barrel = runtime.objects.TankBarrel.createInstance("Layer 0", px, py);

		// Scale to match tank radius
		const scale = 0.7;
		body.width = 75 * scale;
		body.height = 70 * scale;
		barrel.width = 16 * scale;
		barrel.height = 50 * scale;

		const teamAnim = TEAM_ANIMS[tank.team] || "Red";
		body.setAnimation(teamAnim);
		barrel.setAnimation(teamAnim);

		// Shield bubble (circular sprite)
		const shieldSize = TANK_RADIUS * UNIT_SIZE * 4.0;
		const shieldInst = runtime.objects.Shield.createInstance("Layer 0", px, py);
		shieldInst.width = shieldSize;
		shieldInst.height = shieldSize;
		shieldInst.colorRgb = [0.27, 0.53, 1.0];
		shieldInst.opacity = tank.shield > 0 ? 0.25 : 0;
		shieldInst.isVisible = tank.shield > 0;

		// Health bar (world-space, above tank)
		const BAR_W = 40, BAR_H = 4, BAR_Y_OFFSET = -35;
		const hpBarBg = runtime.objects.Block.createInstance("Layer 0", px, py + BAR_Y_OFFSET);
		hpBarBg.width = BAR_W;
		hpBarBg.height = BAR_H;
		hpBarBg.colorRgb = [0.08, 0.08, 0.1];
		hpBarBg.opacity = 0.5;

		const hpBarFill = runtime.objects.Block.createInstance("Layer 0", px, py + BAR_Y_OFFSET);
		hpBarFill.width = BAR_W;
		hpBarFill.height = BAR_H;
		hpBarFill.colorRgb = [0.5, 1.0, 0.5];
		hpBarFill.opacity = 0.9;

		// Shield bar (above health bar)
		const SHIELD_BAR_H = 3, SHIELD_Y_OFFSET = BAR_Y_OFFSET - 6;
		const shieldBarBg = runtime.objects.Block.createInstance("Layer 0", px, py + SHIELD_Y_OFFSET);
		shieldBarBg.width = BAR_W;
		shieldBarBg.height = SHIELD_BAR_H;
		shieldBarBg.colorRgb = [0.08, 0.08, 0.1];
		shieldBarBg.opacity = 0.5;
		shieldBarBg.isVisible = tank.shield > 0;

		const shieldBarFill = runtime.objects.Block.createInstance("Layer 0", px, py + SHIELD_Y_OFFSET);
		shieldBarFill.width = BAR_W;
		shieldBarFill.height = SHIELD_BAR_H;
		shieldBarFill.colorRgb = [0.5, 0.7, 1.0];
		shieldBarFill.opacity = 0.9;
		shieldBarFill.isVisible = tank.shield > 0;

		// Name tag
		const nameTag = runtime.objects.HUDText.createInstance("Layer 0", px, py - 44);
		nameTag.text = tank.name || key.substring(0, 6);
		nameTag.sizePt = 9;
		nameTag.width = 80;
		nameTag.height = 16;
		nameTag.horizontalAlign = "center";
		nameTag.fontColor = TEAM_COLORS_RGB[tank.team] || [1, 1, 1];

		const data = {
			body,
			barrel,
			shieldInst,
			hpBarBg, hpBarFill,
			shieldBarBg, shieldBarFill,
			nameTag,
			targetX: px,
			targetY: py,
			prevX: px,
			prevY: py,
			bodyAngle: 0,
			turretAngle: serverAngleToC3(tank.angle),
			serverAngle: tank.angle,
			hp: tank.hp,
			shield: tank.shield,
			dead: tank.dead,
			wasDead: tank.dead,
			name: tank.name,
			team: tank.team,
			score: tank.score,
			blinkTimer: 0,
			shieldPulse: 0,
			explosionActive: false,
			explosionTimer: 0,
			shieldBreakActive: false,
			shieldBreakTimer: 0,
			shieldBreakInst: null,
		};

		tanks[key] = data;
	},

	onTankChanged(runtime, key, tank) {
		if (!tanks[key]) return;
		const data = tanks[key];

		data.targetX = tank.x * UNIT_SIZE;
		data.targetY = tank.y * UNIT_SIZE;

		if (key !== mySessionId) {
			data.serverAngle = tank.angle;
		}

		// Check for death (hp transition)
		if (tank.hp <= 0 && data.hp > 0) {
			data.explosionActive = true;
			data.explosionTimer = 0.6;
		}
		data.hp = tank.hp;

		// Shield break effect: shield dropped to 0 from positive
		if (tank.shield <= 0 && data.shield > 0) {
			data.shieldBreakActive = true;
			data.shieldBreakTimer = 0.4;
		}
		data.shield = tank.shield;
		data.name = tank.name;
		if (data.nameTag && tank.name) {
			data.nameTag.text = tank.name;
		}

		if (data.team !== tank.team) {
			data.team = tank.team;
			const tn = TEAM_ANIMS[tank.team] || "Red";
			data.body.setAnimation(tn);
			data.barrel.setAnimation(tn);
		}

		data.score = tank.score;

		// Check for respawn: dead changed from true to false
		if (data.wasDead && !tank.dead) {
			data.body.x = data.targetX;
			data.body.y = data.targetY;
			data.prevX = data.targetX;
			data.prevY = data.targetY;
			if (key === mySessionId) cameraSnapped = false;
		}
		data.wasDead = tank.dead;
		data.dead = tank.dead;
	},

	onTankRemoved(runtime, key) {
		if (tanks[key]) {
			const t = tanks[key];
			t.body.destroy();
			t.barrel.destroy();
			if (t.shieldInst) t.shieldInst.destroy();
			if (t.explosionInst) t.explosionInst.destroy();
			if (t.shieldBreakInst) t.shieldBreakInst.destroy();
			if (t.hpBarBg) t.hpBarBg.destroy();
			if (t.hpBarFill) t.hpBarFill.destroy();
			if (t.shieldBarBg) t.shieldBarBg.destroy();
			if (t.shieldBarFill) t.shieldBarFill.destroy();
			if (t.nameTag) t.nameTag.destroy();
			delete tanks[key];
		}
	},

	onBulletAdded(runtime, key, bullet) {
		const px = bullet.x * UNIT_SIZE;
		const py = bullet.y * UNIT_SIZE;

		const inst = runtime.objects.Bullet.createInstance("Layer 0", px, py);
		const scale = 0.8;
		inst.width = 12 * scale;
		inst.height = 26 * scale;

		// Set team color from owner
		let animName = "Red";
		if (bullet.special) {
			animName = "Special";
		} else if (tanks[bullet.owner]) {
			animName = TEAM_ANIMS[tanks[bullet.owner].team] || "Red";
		}
		inst.setAnimation(animName);

		// Set initial angle from trajectory target (tx, ty)
		const tx = (bullet.tx || bullet.x) * UNIT_SIZE;
		const ty = (bullet.ty || bullet.y) * UNIT_SIZE;
		const tdx = tx - px;
		const tdy = ty - py;
		if (Math.abs(tdx) > 0.1 || Math.abs(tdy) > 0.1) {
			inst.angle = Math.atan2(tdy, tdx) + Math.PI / 2;
		}

		const data = {
			instance: inst,
			targetX: px,
			targetY: py,
			owner: bullet.owner,
			special: bullet.special,
		};
		bullets[key] = data;
	},

	onBulletChanged(runtime, key, bullet) {
		if (!bullets[key]) return;
		bullets[key].targetX = bullet.x * UNIT_SIZE;
		bullets[key].targetY = bullet.y * UNIT_SIZE;
	},

	onBulletRemoved(runtime, key) {
		if (bullets[key]) {
			bullets[key].instance.destroy();
			delete bullets[key];
		}
	},

	onPickableAdded(runtime, key, pickable) {
		const px = pickable.x * UNIT_SIZE;
		const py = pickable.y * UNIT_SIZE;
		const size = 0.8 * UNIT_SIZE;

		let inst;
		switch (pickable.type) {
			case "repair":
				inst = runtime.objects.PickRepair.createInstance("Layer 0", px, py);
				break;
			case "shield":
				inst = runtime.objects.PickShield.createInstance("Layer 0", px, py);
				break;
			case "damage":
				inst = runtime.objects.PickDamage.createInstance("Layer 0", px, py);
				break;
			default:
				inst = runtime.objects.Block.createInstance("Layer 0", px, py);
				break;
		}
		inst.width = size;
		inst.height = size;

		pickables[key] = { instance: inst, type: pickable.type, baseY: py, bobOffset: 0 };
	},

	onPickableRemoved(runtime, key) {
		if (pickables[key]) {
			pickables[key].instance.destroy();
			delete pickables[key];
		}
	},

	onTeamAdded(runtime, key, team) {
		const idx = Number(key);
		if (team.score !== undefined) teamScores[idx] = team.score;
	},

	onTeamChanged(runtime, key, team) {
		const idx = Number(key);
		if (team.score !== undefined) teamScores[idx] = team.score;
	},

	onWinnerChange(value) {
		winnerTeam = Number(value);
		if (winnerTeam >= 0) {
			console.log("Winner: Team", TEAM_LABELS[winnerTeam]);
		}
	},

	onTick(runtime) {
		const dt = runtime.dt;
		handleInput(runtime);
		updateTanks(dt, runtime);
		updateBullets(dt);
		updatePickables(dt);
		updateCamera(runtime);
		updateHUD(runtime);
	}
};
