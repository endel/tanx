// Heaps coordinate system: X=right, Y=forward, Z=up
// No js.* dependencies — cross-compiles to JS, Neko, CPP, HL

import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import schema.BattleState;
import schema.TankState;
import schema.BulletState;
import schema.PickableState;
import schema.TeamState;

private typedef TankHud = {
	container:h2d.Object,
	hpFill:h2d.Graphics,
	shieldFill:h2d.Graphics,
};

private typedef BulletVisual = {
	mesh:h3d.scene.Mesh,
	targetX:Float,
	targetY:Float
};

private typedef PickableVisual = {
	group:h3d.scene.Object,
	type:String
};

class Game {
	static final TEAM_COLORS_HEX:Array<Int> = [0xFF4444, 0x4488FF, 0x44FF44, 0xFFFF44];
	static final TEAM_NAMES:Array<String> = ["Red", "Blue", "Green", "Yellow"];
	static final SERVER_URL = #if release "wss://tanks-demo.colyseus.dev" #else "ws://localhost:2567" #end;

	var s3d:h3d.scene.Scene;
	var s2d:h2d.Scene;

	var network:Network;
	var sound:Sound;
	var mapRenderer:MapRenderer;
	var room:Room<BattleState>;

	var tanks:Map<String, Tank> = new Map();
	var tankHuds:Map<String, TankHud> = new Map();
	var bulletVisuals:Map<String, BulletVisual> = new Map();
	var pickableVisuals:Map<String, PickableVisual> = new Map();

	var mySessionId:String = "";
	var mouseX:Float = 0;
	var mouseY:Float = 0;
	var mouseDown:Bool = false;

	var lastSentDirX:Float = -999;
	var lastSentDirY:Float = -999;
	var lastSentAngle:Float = -999;
	var lastTargetSendTime:Float = 0;

	// h2d HUD elements
	var hudLayer:h2d.Object;
	var tankHudLayer:h2d.Object;
	var connectText:h2d.Text;
	var healthBarBg:h2d.Graphics;
	var healthBarFill:h2d.Graphics;
	var shieldBarBg:h2d.Graphics;
	var shieldBarFill:h2d.Graphics;
	var deathText:h2d.Text;
	var winnerBg:h2d.Graphics;
	var winnerLabel:h2d.Text;
	var winnerTeamText:h2d.Text;
	var winnerTimer:Float = 0;
	var scoresBg:h2d.Graphics;
	var scoreTexts:Array<h2d.Text> = [];
	var font:h2d.Font;

	public function new(s3d:h3d.scene.Scene, s2d:h2d.Scene) {
		this.s3d = s3d;
		this.s2d = s2d;

		sound = new Sound();
		font = hxd.res.DefaultFont.get();

		setupHud();
		setupInput();
		setupScene();
		connect();
	}

	function setupHud() {
		tankHudLayer = new h2d.Object(s2d);
		hudLayer = new h2d.Object(s2d);

		// Connect status
		connectText = new h2d.Text(font, hudLayer);
		connectText.text = "Connecting...";
		connectText.textColor = 0xAAAAAA;
		connectText.setScale(2);

		// Health bar
		healthBarBg = new h2d.Graphics(hudLayer);
		healthBarFill = new h2d.Graphics(hudLayer);
		drawRect(healthBarBg, 0x333333, 200, 12);
		drawRect(healthBarFill, 0x44FF44, 200, 12);

		// Shield bar
		shieldBarBg = new h2d.Graphics(hudLayer);
		shieldBarFill = new h2d.Graphics(hudLayer);
		drawRect(shieldBarBg, 0x333333, 200, 6);
		drawRect(shieldBarFill, 0x4488FF, 200, 6);
		shieldBarBg.visible = false;
		shieldBarFill.visible = false;

		// Scores background + team rows
		scoresBg = new h2d.Graphics(hudLayer);
		for (i in 0...4) {
			var t = new h2d.Text(font, hudLayer);
			t.textColor = TEAM_COLORS_HEX[i];
			t.text = TEAM_NAMES[i] + ": 0";
			t.setScale(1.5);
			scoreTexts.push(t);
		}

		// Death screen
		deathText = new h2d.Text(font, hudLayer);
		deathText.text = "DESTROYED\nRespawning...";
		deathText.textColor = 0xFF4444;
		deathText.textAlign = Center;
		deathText.setScale(3);
		deathText.visible = false;

		// Winner screen
		winnerBg = new h2d.Graphics(hudLayer);
		winnerBg.visible = false;
		winnerLabel = new h2d.Text(font, hudLayer);
		winnerLabel.textAlign = Center;
		winnerLabel.setScale(6);
		winnerLabel.visible = false;
		winnerTeamText = new h2d.Text(font, hudLayer);
		winnerTeamText.textAlign = Center;
		winnerTeamText.setScale(2);
		winnerTeamText.visible = false;
	}

	function layoutHud() {
		var w = hxd.Window.getInstance();
		var sw = w.width;
		var sh = w.height;

		connectText.x = (sw - connectText.textWidth * 2) / 2;
		connectText.y = sh / 2 - 10;

		healthBarBg.x = (sw - 200) / 2;
		healthBarBg.y = sh - 42;
		healthBarFill.x = healthBarBg.x;
		healthBarFill.y = healthBarBg.y;

		shieldBarBg.x = (sw - 200) / 2;
		shieldBarBg.y = sh - 54;
		shieldBarFill.x = shieldBarBg.x;
		shieldBarFill.y = shieldBarBg.y;

		// Scores top-right
		var sx = sw - 150;
		var rowH = 22;
		var pad = 10;
		scoresBg.clear();
		scoresBg.beginFill(0x000000, 0.5);
		scoresBg.drawRect(0, 0, 150, pad + rowH * 4 + pad);
		scoresBg.endFill();
		scoresBg.x = sx - pad;
		scoresBg.y = 5;
		for (i in 0...scoreTexts.length) {
			scoreTexts[i].x = sx;
			scoreTexts[i].y = 5 + pad + i * rowH;
		}

		deathText.x = sw / 2;
		deathText.y = sh / 2 - 30;

		winnerBg.clear();
		winnerBg.beginFill(0x000000, 0.6);
		winnerBg.drawRect(0, 0, sw, sh);
		winnerBg.endFill();
		winnerLabel.x = sw / 2;
		winnerLabel.y = sh / 2 - 40;
		winnerTeamText.x = sw / 2;
		winnerTeamText.y = sh / 2 + 30;
	}

	function setupScene() {
		s3d.camera.pos.set(44, 44, 20);
		s3d.camera.target.set(24, 24, 0);
		updateCameraBounds();

		var fwdLS = Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem);
		if (fwdLS != null)
			fwdLS.ambientLight.set(0.37, 0.37, 0.47);

		var sunDir = new h3d.Vector(0.3, 0.5, -0.8);
		sunDir.normalize();
		var sun = new h3d.scene.fwd.DirLight(sunDir, s3d);
		sun.color.set(1.0, 0.93, 0.87);

		mapRenderer = new MapRenderer(s3d);
	}

	function updateCameraBounds() {
		var w = hxd.Window.getInstance();
		var aspect = w.width / w.height;
		var halfH = 11.0;
		var halfW = halfH * aspect;
		s3d.camera.orthoBounds = h3d.col.Bounds.fromValues(-halfW, -halfH, 0.1, halfW * 2, halfH * 2, 200);
	}

	function connect() {
		network = new Network(SERVER_URL);
		network.connect(function(room) {
			this.room = room;
			mySessionId = room.sessionId;
			connectText.visible = false;
			bindRoomEvents();
		}, function(err) {
			connectText.text = "Failed to connect.";
			trace("Connection error: " + err);
		});
	}

	function bindRoomEvents() {
		// Callbacks.get(room) enables MainLoop-based thread marshaling on sys targets.
		// All callbacks below run on the main thread — safe to touch scene graph directly.
		var cb = Callbacks.get(room);

		// -- Tanks --
		cb.onAdd("tanks", function(tank:Dynamic, key:Dynamic) {
			var t:TankState = cast tank;
			var k:String = Std.string(key);

			var entity = new Tank(s3d, t.team);
			entity.targetX = t.x;
			entity.targetY = t.y;
			entity.entity.x = t.x;
			entity.entity.y = t.y;
			entity.dead = t.dead;
			tanks.set(k, entity);

			var hud = createTankHud(k);
			setTankHudHealth(hud, t.hp);
			setTankHudShield(hud, t.shield);

			cb.listen(t, "x", function(val:Dynamic, prev:Dynamic) {
				entity.targetX = (val : Float);
			});
			cb.listen(t, "y", function(val:Dynamic, prev:Dynamic) {
				entity.targetY = (val : Float);
			});
			cb.listen(t, "angle", function(val:Dynamic, prev:Dynamic) {
				if (k != mySessionId)
					entity.targetAngle = (val : Float);
			});
			cb.listen(t, "dead", function(val:Dynamic, prev:Dynamic) {
				var isDead:Bool = cast val;
				entity.setDead(isDead);
				if (isDead) sound.explosion();
				if (k == mySessionId) deathText.visible = isDead;
			});
			cb.listen(t, "hp", function(val:Dynamic, prev:Dynamic) {
				var hp:Int = cast val;
				var prevHp:Int = prev != null ? cast prev : 10;
				setTankHudHealth(hud, hp);
				if (hp < prevHp) {
					var myTank = tanks.get(mySessionId);
					if (myTank != null) {
						var dx = entity.entity.x - myTank.entity.x;
						var dy = entity.entity.y - myTank.entity.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						var vol = Math.max(0, 0.25 * (1 - dist / 25));
						if (vol > 0.01) sound.hit(vol);
					}
				}
				if (k == mySessionId) healthBarFill.scaleX = Math.max(0, hp) / 10;
			});
			cb.listen(t, "shield", function(val:Dynamic, prev:Dynamic) {
				var shield:Int = cast val;
				entity.setShield(shield);
				setTankHudShield(hud, shield);
				if (k == mySessionId) {
					var active = shield > 0;
					shieldBarBg.visible = active;
					shieldBarFill.visible = active;
					shieldBarFill.scaleX = Math.max(0, shield) / 10;
				}
			});
			cb.listen(t, "score", function(val:Dynamic, prev:Dynamic) {
				updateScores();
			});
		});

		cb.onRemove("tanks", function(tank:Dynamic, key:Dynamic) {
			var k:String = Std.string(key);
			var entity = tanks.get(k);
			if (entity != null) {
				entity.dispose();
				tanks.remove(k);
			}
			removeTankHud(k);
		});

		// -- Bullets --
		cb.onAdd("bullets", function(bullet:Dynamic, key:Dynamic) {
			var b:BulletState = cast bullet;
			var k:String = Std.string(key);

			var color:Int = b.special ? 0xFF8800 : 0xFFFF66;
			var ownerTank = room.state.tanks.get(b.owner);
			if (ownerTank != null && !b.special)
				color = TEAM_COLORS_HEX[ownerTank.team];

			var radius:Float = b.special ? 0.2 : 0.12;
			var prim = new h3d.prim.Sphere(8, 6);
			prim.addNormals();
			var mesh = new h3d.scene.Mesh(prim, s3d);
			mesh.material.color.setColor(color);
			mesh.material.mainPass.enableLights = false;
			mesh.material.shadows = false;
			mesh.setScale(radius * 0.12);
			mesh.x = b.x;
			mesh.y = b.y;
			mesh.z = 0.55;

			var visual:BulletVisual = {mesh: mesh, targetX: b.x, targetY: b.y};
			bulletVisuals.set(k, visual);

			cb.listen(b, "x", function(val:Dynamic, prev:Dynamic) {
				visual.targetX = (val : Float);
			});
			cb.listen(b, "y", function(val:Dynamic, prev:Dynamic) {
				visual.targetY = (val : Float);
			});

			if (b.owner == mySessionId) {
				if (b.special) sound.shootSpecial(); else sound.shoot();
			}
		});

		cb.onRemove("bullets", function(bullet:Dynamic, key:Dynamic) {
			var k:String = Std.string(key);
			var visual = bulletVisuals.get(k);
			if (visual != null) {
				visual.mesh.visible = false;
				visual.mesh.remove();
				bulletVisuals.remove(k);
			}
		});

		// -- Pickables --
		cb.onAdd("pickables", function(pick:Dynamic, key:Dynamic) {
			var p:PickableState = cast pick;
			var k:String = Std.string(key);

			var existing = pickableVisuals.get(k);
			if (existing != null) {
				existing.group.visible = true;
				existing.group.x = p.x;
				existing.group.y = p.y;
				return;
			}

			var group = new h3d.scene.Object(s3d);
			var r:Float = 1.0;
			var g:Float = 1.0;
			var bl:Float = 1.0;
			if (p.type == "repair") { r = 0.267; g = 1.0; bl = 0.267; }
			else if (p.type == "damage") { r = 1.0; g = 0.267; bl = 0.267; }
			else if (p.type == "shield") { r = 0.267; g = 0.533; bl = 1.0; }
			var colorInt = (Std.int(r * 255) << 16) | (Std.int(g * 255) << 8) | Std.int(bl * 255);

			if (p.type == "repair") {
				var hPrim = new h3d.prim.Cube(0.7, 0.15, 0.2, true);
				hPrim.addNormals();
				new h3d.scene.Mesh(hPrim, group).material.color.setColor(colorInt);
				var vPrim = new h3d.prim.Cube(0.2, 0.15, 0.7, true);
				vPrim.addNormals();
				new h3d.scene.Mesh(vPrim, group).material.color.setColor(colorInt);
			} else if (p.type == "shield") {
				var shieldPrim = buildShieldPrim();
				var shape = new h3d.scene.Mesh(shieldPrim, group);
				shape.material.color.setColor(colorInt);
				shape.material.mainPass.culling = None;
			} else {
				var dPrim = new h3d.prim.Cube(0.35, 0.35, 0.35, true);
				dPrim.addNormals();
				var diamond = new h3d.scene.Mesh(dPrim, group);
				diamond.material.color.setColor(colorInt);
				diamond.setRotation(Math.PI / 4, 0, Math.PI / 4);
			}

			var glowPrim = new h3d.prim.Sphere(8, 6);
			glowPrim.addNormals();
			var glow = new h3d.scene.Mesh(glowPrim, group);
			glow.setScale(0.08);
			glow.material.color.set(r, g, bl, 0.15);
			glow.material.blendMode = Alpha;
			glow.material.mainPass.depthWrite = false;
			glow.material.mainPass.enableLights = false;
			glow.material.shadows = false;

			group.x = p.x;
			group.y = p.y;
			group.z = 0.6;
			pickableVisuals.set(k, {group: group, type: p.type});
		});

		cb.onRemove("pickables", function(pick:Dynamic, key:Dynamic) {
			var p:PickableState = cast pick;
			var k:String = Std.string(key);
			var visual = pickableVisuals.get(k);
			if (visual != null) {
				visual.group.visible = false;
				if (p.type == "repair") sound.pickupRepair();
				else if (p.type == "shield") sound.pickupShield();
				else if (p.type == "damage") sound.pickupDamage();
			}
		});

		// -- Teams --
		cb.onAdd("teams", function(team:Dynamic, idx:Dynamic) {
			var t:TeamState = cast team;
			cb.listen(t, "score", function(val:Dynamic, prev:Dynamic) {
				updateScores();
			});
		});

		// -- Winner --
		cb.listen("winnerTeam", function(val:Dynamic, prev:Dynamic) {
			var v:Int = cast val;
			if (v >= 0) showWinnerScreen(v);
		});
	}

	// -- Per-tank HUD --

	function createTankHud(key:String):TankHud {
		var container = new h2d.Object(tankHudLayer);

		var hpBg = new h2d.Graphics(container);
		hpBg.beginFill(0x000000, 0.5);
		hpBg.drawRect(0, 0, 48, 5);
		hpBg.endFill();

		var hpFill = new h2d.Graphics(container);
		drawRect(hpFill, 0x44FF44, 48, 5);

		var shieldBg = new h2d.Graphics(container);
		shieldBg.beginFill(0x000000, 0.3);
		shieldBg.drawRect(0, -4, 48, 3);
		shieldBg.endFill();
		shieldBg.visible = false;

		var shieldFill = new h2d.Graphics(container);
		drawRect(shieldFill, 0x4488FF, 48, 3);
		shieldFill.y = -4;
		shieldFill.visible = false;

		var hud:TankHud = {container: container, hpFill: hpFill, shieldFill: shieldFill};
		tankHuds.set(key, hud);
		return hud;
	}

	function removeTankHud(key:String) {
		var hud = tankHuds.get(key);
		if (hud != null) {
			hud.container.remove();
			tankHuds.remove(key);
		}
	}

	function setTankHudHealth(hud:TankHud, hp:Int) {
		var pct = Math.max(0, hp / 10);
		var color = if (pct > 0.5) 0x44FF44 else if (pct > 0.25) 0xFFAA44 else 0xFF4444;
		hud.hpFill.clear();
		drawRect(hud.hpFill, color, Std.int(48 * pct), 5);
	}

	function setTankHudShield(hud:TankHud, shield:Int) {
		var active = shield > 0;
		hud.shieldFill.parent.visible = active; // shieldBg parent
		hud.shieldFill.visible = active;
		if (active) {
			hud.shieldFill.clear();
			drawRect(hud.shieldFill, 0x4488FF, Std.int(48 * Math.max(0, shield) / 10), 3);
			hud.shieldFill.y = -4;
		}
	}

	function updateTankHudPositions() {
		var w = hxd.Window.getInstance();
		for (key => tank in tanks) {
			var hud = tankHuds.get(key);
			if (hud == null) continue;
			var screenPos = s3d.camera.project(tank.entity.x, tank.entity.y, 2.4, w.width, w.height);
			var visible = !tank.dead || (Std.int(haxe.Timer.stamp() * 1000) % 500 < 250);
			hud.container.visible = visible;
			hud.container.x = screenPos.x - 24;
			hud.container.y = screenPos.y;
		}
	}

	function updateScores() {
		if (room == null) return;
		var state = room.state;
		var teams:Array<{id:Int, score:Int}> = [];
		for (i in 0...4) {
			var team = state.teams[i];
			if (team != null) teams.push({id: i, score: team.score});
		}
		teams.sort(function(a, b) return b.score - a.score);
		for (rank in 0...teams.length) {
			var t = teams[rank];
			if (t.id < scoreTexts.length) {
				scoreTexts[t.id].text = TEAM_NAMES[t.id] + ": " + t.score;
				scoreTexts[t.id].y = 16 + rank * 20;
			}
		}
	}

	function showWinnerScreen(winnerTeamId:Int) {
		var myTank = room.state.tanks.get(mySessionId);
		var isWinner = myTank != null && myTank.team == winnerTeamId;

		winnerBg.visible = true;
		winnerBg.clear();
		var tintColor = TEAM_COLORS_HEX[winnerTeamId];
		winnerBg.beginFill(tintColor, 0.3);
		var w = hxd.Window.getInstance();
		winnerBg.drawRect(0, 0, w.width, w.height);
		winnerBg.endFill();

		winnerLabel.visible = true;
		winnerLabel.text = isWinner ? "VICTORY" : "DEFEAT";
		winnerLabel.textColor = 0xFFFFFF;

		winnerTeamText.visible = true;
		winnerTeamText.text = TEAM_NAMES[winnerTeamId] + " Team Wins";
		winnerTeamText.textColor = TEAM_COLORS_HEX[winnerTeamId];

		winnerTimer = 3.0;
		layoutHud();
	}

	// -- Input --

	function setupInput() {
		hxd.Window.getInstance().addEventTarget(function(e:hxd.Event) {
			switch (e.kind) {
				case EPush:
					if (e.button == 0) {
						mouseDown = true;
						if (network != null) network.sendShoot(true);
					}
				case ERelease:
					if (e.button == 0) {
						mouseDown = false;
						if (network != null) network.sendShoot(false);
					}
				default:
			}
		});
	}

	function sendInput() {
		if (room == null) return;

		var rawX:Float = 0;
		var rawY:Float = 0;
		if (hxd.Key.isDown(hxd.Key.W) || hxd.Key.isDown(hxd.Key.UP)) rawY -= 1;
		if (hxd.Key.isDown(hxd.Key.S) || hxd.Key.isDown(hxd.Key.DOWN)) rawY += 1;
		if (hxd.Key.isDown(hxd.Key.A) || hxd.Key.isDown(hxd.Key.LEFT)) rawX -= 1;
		if (hxd.Key.isDown(hxd.Key.D) || hxd.Key.isDown(hxd.Key.RIGHT)) rawX += 1;

		var angle = -Math.PI / 4;
		var cos = Math.cos(angle);
		var sin = Math.sin(angle);
		var dirX = Math.round(rawX * cos - rawY * sin);
		var dirY = Math.round(rawX * sin + rawY * cos);

		if (dirX != lastSentDirX || dirY != lastSentDirY) {
			network.sendMove(dirX, dirY);
			lastSentDirX = dirX;
			lastSentDirY = dirY;
		}

		// Aim at mouse
		var myTank = tanks.get(mySessionId);
		if (myTank != null) {
			mouseX = s2d.mouseX;
			mouseY = s2d.mouseY;
			var ray = s3d.camera.rayFromScreen(mouseX, mouseY);
			var origin = ray.getPos();
			var dir = ray.getDir();
			if (Math.abs(dir.z) > 0.001) {
				var t = -origin.z / dir.z;
				var hitX = origin.x + dir.x * t;
				var hitY = origin.y + dir.y * t;
				var dx = hitX - myTank.entity.x;
				var dy = hitY - myTank.entity.y;
				var aimAngle = Math.atan2(dx, dy) * (180 / Math.PI);
				aimAngle = ((aimAngle % 360) + 360) % 360;
				myTank.targetAngle = aimAngle;

				var now = haxe.Timer.stamp() * 1000;
				if (Math.abs(aimAngle - lastSentAngle) > 1 && now - lastTargetSendTime >= 100) {
					network.sendTarget(aimAngle);
					lastSentAngle = aimAngle;
					lastTargetSendTime = now;
				}
			}
		}
	}

	// -- Main update loop --

	public function update(dt:Float) {
		sendInput();
		updateCameraBounds();
		layoutHud();

		for (_ => tank in tanks)
			tank.update(dt);

		// Pickable bobbing + spin
		var t = haxe.Timer.stamp();
		for (_ => visual in pickableVisuals) {
			if (!visual.group.visible) continue;
			visual.group.z = 0.6 + Math.sin(t * 2) * 0.15;
			visual.group.rotate(0, 0, dt * 1.0);
		}

		// Bullet interpolation
		for (_ => visual in bulletVisuals) {
			visual.mesh.x = lerp(visual.mesh.x, visual.targetX, 0.4);
			visual.mesh.y = lerp(visual.mesh.y, visual.targetY, 0.4);
			visual.mesh.z = 0.55;
		}

		// Camera follow
		var myTank = tanks.get(mySessionId);
		if (myTank != null) {
			var w = hxd.Window.getInstance();
			var nx = (mouseX / w.width) * 2 - 1;
			var ny = (mouseY / w.height) * 2 - 1;
			var lookAhead = 3.0;
			var offsetX = (nx + ny) * 0.707 * lookAhead;
			var offsetY = (-nx + ny) * 0.707 * lookAhead;
			var camX = lerp(s3d.camera.pos.x, myTank.entity.x + 20 + offsetX, 0.08);
			var camY = lerp(s3d.camera.pos.y, myTank.entity.y + 20 + offsetY, 0.08);
			s3d.camera.pos.set(camX, camY, 20);
			s3d.camera.target.set(camX - 20, camY - 20, 0);
		}

		// Winner timer
		if (winnerTimer > 0) {
			winnerTimer -= dt;
			if (winnerTimer <= 0) {
				winnerBg.visible = false;
				winnerLabel.visible = false;
				winnerTeamText.visible = false;
			}
		}

		updateTankHudPositions();
	}

	static var shieldPrimCache:h3d.prim.Polygon = null;

	static function buildShieldPrim():h3d.prim.Polygon {
		if (shieldPrimCache != null) return shieldPrimCache;

		// Shield profile: flat top, curved sides, pointed bottom
		// Build in XZ plane (X=width, Z=up), then extrude along Y
		var profile:Array<{x:Float, z:Float}> = [];

		// Top edge (flat)
		profile.push({x: 0.0, z: 0.4});
		profile.push({x: 0.35, z: 0.25});
		profile.push({x: 0.35, z: 0.0});

		// Bottom curve (quadratic bezier: P0=(0.35,0), P1=(0.3,-0.3), P2=(0,-0.45))
		var steps = 6;
		for (i in 0...steps + 1) {
			var t = i / steps;
			var mt = 1.0 - t;
			var px = mt * mt * 0.35 + 2 * mt * t * 0.3 + t * t * 0;
			var pz = mt * mt * 0 + 2 * mt * t * -0.3 + t * t * -0.45;
			profile.push({x: px, z: pz});
		}

		var depth = 0.12;
		var points = new Array<h3d.col.Point>();
		var indices = new hxd.IndexBuffer();

		// Front face: triangle fan from center (0, -depth/2, 0)
		var centerFront = points.length;
		points.push(new h3d.col.Point(0, -depth / 2, 0));

		var frontStart = points.length;
		for (p in profile) {
			points.push(new h3d.col.Point(p.x, -depth / 2, p.z)); // right
			points.push(new h3d.col.Point(-p.x, -depth / 2, p.z)); // left mirror
		}

		for (i in 0...profile.length - 1) {
			var rC = frontStart + i * 2;
			var lC = frontStart + i * 2 + 1;
			var rN = frontStart + (i + 1) * 2;
			var lN = frontStart + (i + 1) * 2 + 1;
			indices.push(centerFront); indices.push(rC); indices.push(rN);
			indices.push(centerFront); indices.push(lN); indices.push(lC);
		}
		// Close top
		indices.push(centerFront); indices.push(frontStart + 1); indices.push(frontStart);

		// Back face: same but at +depth/2, reversed winding
		var centerBack = points.length;
		points.push(new h3d.col.Point(0, depth / 2, 0));

		var backStart = points.length;
		for (p in profile) {
			points.push(new h3d.col.Point(p.x, depth / 2, p.z));
			points.push(new h3d.col.Point(-p.x, depth / 2, p.z));
		}

		for (i in 0...profile.length - 1) {
			var rC = backStart + i * 2;
			var lC = backStart + i * 2 + 1;
			var rN = backStart + (i + 1) * 2;
			var lN = backStart + (i + 1) * 2 + 1;
			indices.push(centerBack); indices.push(rN); indices.push(rC);
			indices.push(centerBack); indices.push(lC); indices.push(lN);
		}
		indices.push(centerBack); indices.push(backStart); indices.push(backStart + 1);

		var prim = new h3d.prim.Polygon(points, indices);
		prim.addNormals();
		shieldPrimCache = prim;
		return prim;
	}

	static function drawRect(g:h2d.Graphics, color:Int, w:Int, h:Int) {
		g.beginFill(color);
		g.drawRect(0, 0, w, h);
		g.endFill();
	}

	static inline function lerp(a:Float, b:Float, t:Float):Float {
		return a + (b - a) * t;
	}
}
