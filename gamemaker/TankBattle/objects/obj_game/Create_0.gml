// =============================================================================
// obj_game - Create Event
// =============================================================================

// --- Globals ---
global.net_connected = false;
global.net_room = 0;
global.net_session_id = "";

// --- Player state ---
my_tank = noone;
winner_team = -1;

// --- Team scores ---
team_scores = array_create(4, 0);
team_tanks = array_create(4, 0);

// --- Input tracking (send only on change) ---
last_move_x = 0;
last_move_y = 0;
last_aim_angle = 0;
last_target_send_time = 0;
is_shooting = false;

// --- Camera ---
camera = camera_create();
var vw = CAMERA_VIEW_PIXELS;
var vh = round(vw * (display_get_height() / max(1, display_get_width())));
camera_set_view_size(camera, vw, vh);
camera_set_view_pos(camera, 0, 0);
view_enabled = true;
view_visible[0] = true;
view_camera[0] = camera;
cam_x = MAP_PIXELS / 2;
cam_y = MAP_PIXELS / 2;

// --- Instance tracking (structs, keyed by server ID) ---
tank_instances = {};
bullet_instances = {};
pickable_instances = {};

// --- State callbacks handle (set on join) ---
callbacks = 0;

// --- Spawn map blocks ---
var blocks = get_level_blocks();
for (var i = 0; i < array_length(blocks); i++) {
    var b = blocks[i];
    var blk = instance_create_layer(game_to_pixel(b[0]), game_to_pixel(b[1]), "Instances", obj_block);
    blk.block_w = b[2];
    blk.block_h = b[3];
}

// --- Colyseus connection ---
var server_url = debug_mode ? "ws://localhost:2567" : "wss://tanks-demo.colyseus.dev";
var client = colyseus_client_create(server_url);
global.net_room = colyseus_client_join_or_create(client, "battle", "{}");
var net_room = global.net_room;

// =============================================================================
// Room events
// =============================================================================

colyseus_on_error(net_room, function(code, msg) {
    show_debug_message("Room error [" + string(code) + "]: " + msg);
});

colyseus_on_leave(net_room, method(id, function(code, reason) {
    show_debug_message("Left room [" + string(code) + "]: " + reason);
    global.net_connected = false;
}));

// =============================================================================
// On Join — set up all state listeners here
// =============================================================================

colyseus_on_join(net_room, method(id, function(_room) {
    global.net_connected = true;
    global.net_session_id = colyseus_room_get_session_id(_room);
    show_debug_message("Joined room: " + colyseus_room_get_id(_room));
    show_debug_message("Session ID: " + global.net_session_id);

    // Create state callbacks
    callbacks = colyseus_callbacks_create(_room);

    // --- Winner team ---
    colyseus_listen(callbacks, "winnerTeam", method({ game: id }, function(v, prev) {
        game.winner_team = v;
    }));

    // =========================================================================
    // Tanks (MapSchema)
    // =========================================================================

    colyseus_on_add(callbacks, "tanks", method(id, function(instance, key) {
        show_debug_message("Tank onAdd: " + key);

        // Create tank object
        var _ix = colyseus_schema_get(instance, "x");
        var _iy = colyseus_schema_get(instance, "y");
        show_debug_message("  pos: " + string(_ix) + ", " + string(_iy));

        var tank = instance_create_layer(game_to_pixel(_ix), game_to_pixel(_iy), "Instances", obj_tank);
        tank.session_id = key;
        tank.target_x = tank.x;
        tank.target_y = tank.y;

        // Initial values
        tank.team = colyseus_schema_get(instance, "team");
        tank.tank_name = colyseus_schema_get(instance, "name");
        tank.hp = colyseus_schema_get(instance, "hp");
        tank.shield = colyseus_schema_get(instance, "shield");
        tank.dead = colyseus_schema_get(instance, "dead");
        tank.server_angle = colyseus_schema_get(instance, "angle");
        tank.score = colyseus_schema_get(instance, "score");

        // Assign team sprites
        set_tank_team_sprites(tank, tank.team);

        // Store mapping
        tank_instances[$ key] = tank;

        // Track our own tank
        if (key == global.net_session_id) {
            my_tank = tank;
            show_debug_message("  -> This is MY tank! team=" + string(tank.team));
        }

        // --- Field listeners ---
        colyseus_listen(callbacks, instance, "x", method({ t: tank }, function(v, prev) {
            t.target_x = game_to_pixel(v);
        }));

        colyseus_listen(callbacks, instance, "y", method({ t: tank }, function(v, prev) {
            t.target_y = game_to_pixel(v);
        }));

        colyseus_listen(callbacks, instance, "angle", method({ t: tank }, function(v, prev) {
            // Skip server angle updates for the current player's tank —
            // the client already sets its turret angle locally from mouse input,
            // and applying the delayed server value causes visual jitter.
            if (t.session_id == global.net_session_id) return;
            t.server_angle = v;
        }));

        colyseus_listen(callbacks, instance, "hp", method({ t: tank }, function(v, prev) {
            if (v <= 0 && prev > 0) {
                t.explosion_active = true;
                t.explosion_timer = 600;
            }
            t.hp = v;
        }));

        colyseus_listen(callbacks, instance, "shield", method({ t: tank }, function(v, prev) {
            t.shield = v;
        }));

        colyseus_listen(callbacks, instance, "dead", method({ t: tank }, function(v, prev) {
            t.dead = v;
            if (!v) {
                t.x = t.target_x;
                t.y = t.target_y;
                t.prev_x = t.x;
                t.prev_y = t.y;
            }
        }));

        colyseus_listen(callbacks, instance, "name", method({ t: tank }, function(v, prev) {
            t.tank_name = v;
        }));

        colyseus_listen(callbacks, instance, "team", method({ t: tank }, function(v, prev) {
            t.team = v;
            set_tank_team_sprites(t, v);
        }));

        colyseus_listen(callbacks, instance, "score", method({ t: tank }, function(v, prev) {
            t.score = v;
        }));

        show_debug_message("Tank added: " + key + " (team " + string(tank.team) + ")");
    }));

    colyseus_on_remove(callbacks, "tanks", method(id, function(instance, key) {
        show_debug_message("Tank removed: " + key);
        if (variable_struct_exists(tank_instances, key)) {
            var tank = tank_instances[$ key];
            if (instance_exists(tank)) {
                instance_destroy(tank);
            }
            variable_struct_remove(tank_instances, key);
            if (key == global.net_session_id) {
                my_tank = noone;
            }
        }
    }));

    // =========================================================================
    // Bullets (MapSchema)
    // =========================================================================

    colyseus_on_add(callbacks, "bullets", method(id, function(instance, key) {
        var _bx = colyseus_schema_get(instance, "x");
        var _by = colyseus_schema_get(instance, "y");
        var _tx = colyseus_schema_get(instance, "tx");
        var _ty = colyseus_schema_get(instance, "ty");
        var bullet = instance_create_layer(game_to_pixel(_bx), game_to_pixel(_by), "Effects", obj_bullet);
        bullet.bullet_id = key;
        bullet.owner = colyseus_schema_get(instance, "owner");
        bullet.special = colyseus_schema_get(instance, "special");

        // Initial target = spawn position (NOT final destination)
        // Server x/y updates will drive the interpolation progressively
        bullet.target_x = bullet.x;
        bullet.target_y = bullet.y;

        // Set initial move angle from spawn toward final target (for visual direction)
        var _dx = game_to_pixel(_tx) - bullet.x;
        var _dy = game_to_pixel(_ty) - bullet.y;
        if (abs(_dx) > 0.1 || abs(_dy) > 0.1) {
            bullet.move_angle = point_direction(0, 0, _dx, _dy) - 90;
        }

        // Assign team-colored bullet sprite
        if (variable_struct_exists(tank_instances, bullet.owner)) {
            var owner_tank = tank_instances[$ bullet.owner];
            switch (owner_tank.team) {
                case 0: bullet.bullet_sprite = spr_bullet_red; break;
                case 1: bullet.bullet_sprite = spr_bullet_blue; break;
                case 2: bullet.bullet_sprite = spr_bullet_green; break;
                case 3: bullet.bullet_sprite = spr_bullet_yellow; break;
            }
        }

        bullet_instances[$ key] = bullet;

        // Server x/y updates drive smooth interpolation
        colyseus_listen(callbacks, instance, "x", method({ b: bullet }, function(v, prev) {
            b.target_x = game_to_pixel(v);
        }));
        colyseus_listen(callbacks, instance, "y", method({ b: bullet }, function(v, prev) {
            b.target_y = game_to_pixel(v);
        }));
    }));

    colyseus_on_remove(callbacks, "bullets", method(id, function(instance, key) {
        if (variable_struct_exists(bullet_instances, key)) {
            var bullet = bullet_instances[$ key];
            if (instance_exists(bullet)) {
                instance_destroy(bullet);
            }
            variable_struct_remove(bullet_instances, key);
        }
    }));

    // =========================================================================
    // Pickables (MapSchema)
    // =========================================================================

    colyseus_on_add(callbacks, "pickables", method(id, function(instance, key) {
        var _px = colyseus_schema_get(instance, "x");
        var _py = colyseus_schema_get(instance, "y");
        var pick = instance_create_layer(game_to_pixel(_px), game_to_pixel(_py), "Instances", obj_pickable);
        pick.pickable_id = key;
        pick.type = colyseus_schema_get(instance, "type");
        pick.base_y = pick.y;
        pickable_instances[$ key] = pick;
    }));

    colyseus_on_remove(callbacks, "pickables", method(id, function(instance, key) {
        if (variable_struct_exists(pickable_instances, key)) {
            var pick = pickable_instances[$ key];
            if (instance_exists(pick)) {
                instance_destroy(pick);
            }
            variable_struct_remove(pickable_instances, key);
        }
    }));

    // =========================================================================
    // Teams (ArraySchema)
    // =========================================================================

    colyseus_on_add(callbacks, "teams", method(id, function(instance, index) {
        var _idx = real(index);
        colyseus_listen(callbacks, instance, "score", method({ game: id, idx: _idx }, function(v, prev) {
            game.team_scores[idx] = v;
        }));
        colyseus_listen(callbacks, instance, "tanks", method({ game: id, idx: _idx }, function(v, prev) {
            game.team_tanks[idx] = v;
        }));
    }));

    show_debug_message("State callbacks registered.");
}));
