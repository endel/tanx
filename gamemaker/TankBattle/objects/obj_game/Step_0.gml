// =============================================================================
// obj_game - Step Event
// =============================================================================

// --- Process Colyseus events (REQUIRED every frame) ---
colyseus_process();

// --- Input ---
var move_x = keyboard_check(ord("D")) - keyboard_check(ord("A"));
var move_y = keyboard_check(ord("S")) - keyboard_check(ord("W"));

// Arrow keys as alternative
if (move_x == 0) move_x = keyboard_check(vk_right) - keyboard_check(vk_left);
if (move_y == 0) move_y = keyboard_check(vk_down) - keyboard_check(vk_up);

// Send movement only on change
if (move_x != last_move_x || move_y != last_move_y) {
    last_move_x = move_x;
    last_move_y = move_y;
    network_send_move(move_x, move_y);
}

// --- Aim ---
if (instance_exists(my_tank)) {
    var mouse_wx = mouse_x;
    var mouse_wy = mouse_y;
    var aim_angle = client_aim_angle(my_tank.x, my_tank.y, mouse_wx, mouse_wy);
    var aim_rounded = round(aim_angle);

    // Update local turret immediately (don't wait for server round-trip)
    my_tank.server_angle = aim_rounded;

    var now_ms = current_time;
    if (abs(aim_rounded - last_aim_angle) > 1 && (now_ms - last_target_send_time) >= 100) {
        last_aim_angle = aim_rounded;
        last_target_send_time = now_ms;
        network_send_target(aim_rounded);
    }
}

// --- Shoot ---
if (mouse_check_button_pressed(mb_left)) {
    is_shooting = true;
    network_send_shoot(true);
}
if (!mouse_check_button(mb_left) && is_shooting) {
    is_shooting = false;
    network_send_shoot(false);
}

// --- Camera Follow ---
if (instance_exists(my_tank)) {
    var vw = camera_get_view_width(camera);
    var vh = camera_get_view_height(camera);

    // Normalized mouse offset from center (-1 to 1)
    var screen_mx = (window_mouse_get_x() / max(1, window_get_width())) * 2 - 1;
    var screen_my = (window_mouse_get_y() / max(1, window_get_height())) * 2 - 1;

    var look_dist = 3 * UNIT_SIZE;
    var target_x = my_tank.x + screen_mx * look_dist - vw / 2;
    var target_y = my_tank.y + screen_my * look_dist - vh / 2;

    cam_x = lerp(cam_x, target_x, LERP_CAMERA);
    cam_y = lerp(cam_y, target_y, LERP_CAMERA);

    cam_x = clamp(cam_x, 0, MAP_PIXELS - vw);
    cam_y = clamp(cam_y, 0, MAP_PIXELS - vh);

    camera_set_view_pos(camera, cam_x, cam_y);
}
