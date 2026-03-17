extends Node3D

const TEAM_COLORS: Array[Color] = [
	Color(1.0, 0.267, 0.267),   # Red
	Color(0.267, 0.533, 1.0),   # Blue
	Color(0.267, 1.0, 0.267),   # Green
	Color(1.0, 1.0, 0.267),     # Yellow
]
const TEAM_NAMES: Array[String] = ["Red", "Blue", "Green", "Yellow"]

# Server endpoint — override via command line: --server=wss://example.com
var server_url: String

# Colyseus
var client: ColyseusClient
var room: ColyseusRoom
var callbacks: Object  # Colyseus.callbacks(room)
var my_session_id: String = ""

# Scene
var camera: Camera3D
var sun: DirectionalLight3D
var map_renderer: MapRenderer

# Entity containers
var tanks_node: Node3D
var bullets_node: Node3D
var pickables_node: Node3D

# Entity maps
var tanks: Dictionary = {}         # session_id -> TankEntity
var bullet_meshes: Dictionary = {} # id -> MeshInstance3D
var bullet_data: Dictionary = {}   # id -> {sx, sy} for interpolation
var pickable_meshes: Dictionary = {} # id -> Node3D

# Camera
var _camera_needs_snap: bool = false

# Input state
var mouse_position: Vector2 = Vector2.ZERO
var mouse_down: bool = false
var last_sent_dir_x: float = -999.0
var last_sent_dir_y: float = -999.0
var last_sent_angle: float = -999.0
var last_target_send_time: float = 0.0

# HUD
var health_bar: ColorRect
var health_bg: ColorRect
var shield_bar: ColorRect
var shield_bg: ColorRect
var death_label: Label
var respawn_label: Label
var winner_container: PanelContainer
var winner_label: Label
var winner_team_label: Label
var connect_label: Label
var leaderboard_container: PanelContainer
var score_labels: Array[Label] = []
var tank_health_bars: Dictionary = {}  # session_id -> {bg: ColorRect, fill: ColorRect}
var hud_root: Control  # reference for adding per-tank bars


func _ready() -> void:
	# Use localhost for debug builds, production server for release/export builds
	if OS.has_feature("debug"):
		server_url = "ws://localhost:2567"
	else:
		server_url = "wss://tanks-demo.colyseus.dev"
	_parse_args()
	TankEntity.preload_model()
	_setup_scene()
	_setup_hud()
	_connect_to_server()


func _parse_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--server="):
			server_url = arg.substr(9)


func _setup_scene() -> void:
	# Background color (environment)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.051, 0.106, 0.165)  # #0d1b2a
	env.fog_enabled = true
	env.fog_light_color = Color(0.051, 0.106, 0.165)
	env.fog_density = 0.01
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Orthographic camera (isometric view)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22.0
	camera.near = 0.1
	camera.far = 200.0
	camera.position = Vector3(44, 20, 44)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(24, 0, 24))

	# Ambient light
	var ambient := DirectionalLight3D.new()
	ambient.light_color = Color(0.533, 0.533, 0.667)
	ambient.light_energy = 0.7
	ambient.position = Vector3(0, 10, 0)
	ambient.rotation_degrees = Vector3(-90, 0, 0)
	ambient.shadow_enabled = false
	add_child(ambient)

	# Sun (directional light with shadows)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.933, 0.867)  # #ffeedd
	sun.light_energy = 1.2
	sun.position = Vector3(30, 40, 20)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	sun.look_at(Vector3(0, 0, 0))

	# Map
	map_renderer = MapRenderer.new()
	map_renderer.name = "Map"
	add_child(map_renderer)
	map_renderer.build()

	# Entity containers
	tanks_node = Node3D.new()
	tanks_node.name = "Tanks"
	add_child(tanks_node)

	bullets_node = Node3D.new()
	bullets_node.name = "Bullets"
	add_child(bullets_node)

	pickables_node = Node3D.new()
	pickables_node.name = "Pickables"
	add_child(pickables_node)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	canvas.layer = 1
	add_child(canvas)

	# Full-screen Control root so anchors work correctly
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_root)

	# Connection status
	connect_label = Label.new()
	connect_label.text = "Connecting..."
	connect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect_label.add_theme_font_size_override("font_size", 16)
	connect_label.add_theme_color_override("font_color", Color.WHITE)
	connect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	connect_label.size = Vector2(300, 30)
	connect_label.position.y = 20
	connect_label.position.x = -150
	hud_root.add_child(connect_label)

	# Health/shield bar container — fixed position, no anchor resizing issues
	var bar_container := Control.new()
	bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar_container.size = Vector2(200, 30)
	bar_container.position = Vector2(-100, -58)
	hud_root.add_child(bar_container)

	# Shield bar background (top)
	shield_bg = ColorRect.new()
	shield_bg.color = Color(0.15, 0.15, 0.15, 0.5)
	shield_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_bg.position = Vector2(0, 0)
	shield_bg.size = Vector2(200, 6)
	bar_container.add_child(shield_bg)

	# Shield bar fill
	shield_bar = ColorRect.new()
	shield_bar.color = Color(0.282, 1.0, 1.0)
	shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_bar.position = Vector2(0, 0)
	shield_bar.size = Vector2(0, 6)
	bar_container.add_child(shield_bar)

	# Health bar background
	health_bg = ColorRect.new()
	health_bg.color = Color(0.15, 0.15, 0.15, 0.7)
	health_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bg.position = Vector2(0, 10)
	health_bg.size = Vector2(200, 12)
	bar_container.add_child(health_bg)

	# Health bar fill
	health_bar = ColorRect.new()
	health_bar.color = Color(0.267, 1.0, 0.267)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.position = Vector2(0, 10)
	health_bar.size = Vector2(200, 12)
	bar_container.add_child(health_bar)

	# Death screen — use anchors directly for reliable centering
	death_label = Label.new()
	death_label.text = "DESTROYED"
	death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_label.add_theme_font_size_override("font_size", 48)
	death_label.add_theme_color_override("font_color", Color(1.0, 0.267, 0.267))
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_label.visible = false
	hud_root.add_child(death_label)
	death_label.anchor_left = 0.0
	death_label.anchor_right = 1.0
	death_label.anchor_top = 0.4
	death_label.anchor_bottom = 0.4
	death_label.offset_left = 0
	death_label.offset_right = 0
	death_label.offset_top = -30
	death_label.offset_bottom = 30

	respawn_label = Label.new()
	respawn_label.text = "Respawning..."
	respawn_label.add_theme_font_size_override("font_size", 16)
	respawn_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	respawn_label.visible = false
	respawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(respawn_label)
	respawn_label.anchor_left = 0.0
	respawn_label.anchor_right = 1.0
	respawn_label.anchor_top = 0.5
	respawn_label.anchor_bottom = 0.5
	respawn_label.offset_left = 0
	respawn_label.offset_right = 0
	respawn_label.offset_top = 0
	respawn_label.offset_bottom = 30

	# Winner screen — centered using anchors
	winner_container = PanelContainer.new()
	winner_container.visible = false
	winner_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var winner_style := StyleBoxFlat.new()
	winner_style.bg_color = Color(0, 0, 0, 0.8)
	winner_style.corner_radius_top_left = 8
	winner_style.corner_radius_top_right = 8
	winner_style.corner_radius_bottom_left = 8
	winner_style.corner_radius_bottom_right = 8
	winner_container.add_theme_stylebox_override("panel", winner_style)

	var winner_vbox := VBoxContainer.new()
	winner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	winner_label = Label.new()
	winner_label.add_theme_font_size_override("font_size", 36)
	winner_label.add_theme_color_override("font_color", Color.WHITE)
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_vbox.add_child(winner_label)

	winner_team_label = Label.new()
	winner_team_label.add_theme_font_size_override("font_size", 18)
	winner_team_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	winner_team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_vbox.add_child(winner_team_label)

	winner_container.add_child(winner_vbox)
	hud_root.add_child(winner_container)
	winner_container.anchor_left = 0.5
	winner_container.anchor_right = 0.5
	winner_container.anchor_top = 0.5
	winner_container.anchor_bottom = 0.5
	winner_container.offset_left = -200
	winner_container.offset_right = 200
	winner_container.offset_top = -60
	winner_container.offset_bottom = 60

	# Leaderboard — top-right using anchors
	leaderboard_container = PanelContainer.new()
	leaderboard_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lb_style := StyleBoxFlat.new()
	lb_style.bg_color = Color(0, 0, 0, 0.5)
	lb_style.corner_radius_top_left = 6
	lb_style.corner_radius_top_right = 6
	lb_style.corner_radius_bottom_left = 6
	lb_style.corner_radius_bottom_right = 6
	lb_style.content_margin_left = 8
	lb_style.content_margin_right = 8
	lb_style.content_margin_top = 8
	lb_style.content_margin_bottom = 8
	leaderboard_container.add_theme_stylebox_override("panel", lb_style)

	var lb_vbox := VBoxContainer.new()

	var lb_title := Label.new()
	lb_title.text = "LEADERBOARD"
	lb_title.add_theme_font_size_override("font_size", 10)
	lb_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_vbox.add_child(lb_title)

	for i in range(4):
		var row := Label.new()
		row.text = "%s: 0" % TEAM_NAMES[i]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", TEAM_COLORS[i])
		lb_vbox.add_child(row)
		score_labels.append(row)

	leaderboard_container.add_child(lb_vbox)
	hud_root.add_child(leaderboard_container)
	leaderboard_container.anchor_left = 1.0
	leaderboard_container.anchor_right = 1.0
	leaderboard_container.anchor_top = 0.0
	leaderboard_container.anchor_bottom = 0.0
	leaderboard_container.offset_left = -130
	leaderboard_container.offset_right = -10
	leaderboard_container.offset_top = 10
	leaderboard_container.offset_bottom = 120


# ── Networking ──

func _connect_to_server() -> void:
	print("[Game] Connecting to server: ", server_url)
	connect_label.text = "Connecting to %s..." % server_url

	client = Colyseus.create_client()
	client.set_endpoint(server_url)

	print("[Game] Client created, joining room 'battle'...")
	room = client.join_or_create("battle")
	if not room:
		print("[Game] ERROR: join_or_create returned null")
		connect_label.text = "Failed to connect. Is server running?"
		return

	print("[Game] Room object received, waiting for joined signal...")
	room.joined.connect(_on_room_joined)
	room.state_changed.connect(_on_state_changed)
	room.error.connect(_on_room_error)
	room.left.connect(_on_room_left)


func _on_room_joined() -> void:
	my_session_id = room.get_session_id()
	print("[Game] Joined room! session_id=", my_session_id)
	connect_label.visible = false
	_bind_room_events()


func _on_state_changed() -> void:
	pass


func _on_room_error(code: int, message: String) -> void:
	print("[Game] Room error [", code, "]: ", message)
	connect_label.text = "Error [%d]: %s" % [code, message]
	connect_label.visible = true


func _on_room_left(code: int, _reason: String) -> void:
	print("[Game] Left room [", code, "]: ", _reason)
	connect_label.text = "Disconnected [%d]" % code
	connect_label.visible = true


func _bind_room_events() -> void:
	callbacks = Colyseus.callbacks(room)

	callbacks.on_add("tanks", _on_tank_add)
	callbacks.on_remove("tanks", _on_tank_remove)
	callbacks.on_add("bullets", _on_bullet_add)
	callbacks.on_remove("bullets", _on_bullet_remove)
	callbacks.on_add("pickables", _on_pickable_add)
	callbacks.on_remove("pickables", _on_pickable_remove)
	callbacks.listen("winnerTeam", _on_winner_changed)
	callbacks.on_add("teams", _on_team_add)


func _create_tank_hud(key: String, team_idx: int) -> void:
	var bar_w := 40.0
	var bar_h := 4.0
	var team_color := TEAM_COLORS[team_idx] if team_idx < TEAM_COLORS.size() else Color.WHITE

	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 0.7)
	bg.size = Vector2(bar_w, bar_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible = false
	hud_root.add_child(bg)

	var fill := ColorRect.new()
	fill.color = team_color
	fill.size = Vector2(bar_w, bar_h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.visible = false
	hud_root.add_child(fill)

	tank_health_bars[key] = {"bg": bg, "fill": fill, "width": bar_w}


func _remove_tank_hud(key: String) -> void:
	if tank_health_bars.has(key):
		var bars: Dictionary = tank_health_bars[key]
		bars["bg"].queue_free()
		bars["fill"].queue_free()
		tank_health_bars.erase(key)


func _on_tank_add(tank, key) -> void:
	var team_idx: int = tank.get("team", 0)
	var entity := TankEntity.new()
	entity.setup(team_idx)
	entity.target_x = tank.get("x", 0.0)
	entity.target_z = tank.get("y", 0.0)
	entity.position = Vector3(tank.get("x", 0.0), 0, tank.get("y", 0.0))
	entity.is_dead = tank.get("dead", false)
	entity.set_health(tank.get("hp", 10))
	tanks_node.add_child(entity)
	tanks[key] = entity

	_create_tank_hud(key, team_idx)

	# Flag camera to snap to our tank on next _process
	if key == my_session_id:
		_camera_needs_snap = true

	callbacks.listen(tank, "x", func(val, _prev): entity.target_x = val)
	callbacks.listen(tank, "y", func(val, _prev): entity.target_z = val)
	callbacks.listen(tank, "angle", func(val, _prev):
		if key != my_session_id:
			entity.target_angle = val
	)
	callbacks.listen(tank, "dead", func(val, prev):
		entity.set_dead(val)
		if key == my_session_id:
			if val and prev == false:
				death_label.visible = true
				respawn_label.visible = true
			elif not val:
				death_label.visible = false
				respawn_label.visible = false
	)
	callbacks.listen(tank, "hp", func(val, _prev):
		entity.set_health(val)
		if key == my_session_id:
			health_bar.size.x = maxf(0, val) * 20.0
	)
	callbacks.listen(tank, "shield", func(val, _prev):
		entity.set_shield(val)
		if key == my_session_id:
			shield_bar.size.x = maxf(0, val) * 20.0
	)
	callbacks.listen(tank, "score", func(_val, _prev):
		_update_scores()
	)


func _on_tank_remove(_tank: Dictionary, key: String) -> void:
	_remove_tank_hud(key)
	if tanks.has(key):
		var entity: TankEntity = tanks[key]
		tanks_node.remove_child(entity)
		entity.dispose()
		entity.queue_free()
		tanks.erase(key)


func _on_bullet_add(bullet: Dictionary, key: String) -> void:
	var is_special: bool = bullet.get("special", false)
	var bullet_color := Color(1.0, 1.0, 0.4)  # default yellow

	# Color by owner team
	var state := room.get_state()
	var state_tanks = state.get("tanks", {})
	var owner_id: String = bullet.get("owner", "")
	if state_tanks is Dictionary and state_tanks.has(owner_id):
		var owner_tank = state_tanks[owner_id]
		var team_idx: int = owner_tank.get("team", 0)
		if not is_special and team_idx < TEAM_COLORS.size():
			bullet_color = TEAM_COLORS[team_idx]

	if is_special:
		bullet_color = Color(1.0, 0.533, 0.0)  # orange

	var sphere := SphereMesh.new()
	sphere.radius = 0.2 if is_special else 0.12
	sphere.height = 0.4 if is_special else 0.24
	sphere.radial_segments = 6
	sphere.rings = 6

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = bullet_color

	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.position = Vector3(bullet.get("x", 0.0), 0.55, bullet.get("y", 0.0))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bullets_node.add_child(mesh)
	bullet_meshes[key] = mesh
	bullet_data[key] = {"sx": bullet.get("x", 0.0), "sy": bullet.get("y", 0.0)}

	callbacks.listen(bullet, "x", func(val, _prev): bullet_data[key]["sx"] = val)
	callbacks.listen(bullet, "y", func(val, _prev): bullet_data[key]["sy"] = val)


func _on_bullet_remove(_bullet: Dictionary, key: String) -> void:
	if bullet_meshes.has(key):
		var mesh: MeshInstance3D = bullet_meshes[key]
		bullets_node.remove_child(mesh)
		mesh.queue_free()
		bullet_meshes.erase(key)
		bullet_data.erase(key)


func _on_pickable_add(pick: Dictionary, key: String) -> void:
	var pick_type: String = pick.get("type", "repair")
	var group := Node3D.new()

	var color_map := {
		"repair": Color(0.267, 1.0, 0.267),
		"damage": Color(1.0, 0.267, 0.267),
		"shield": Color(0.267, 0.533, 1.0),
	}
	var color: Color = color_map.get(pick_type, Color.WHITE)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.4

	if pick_type == "repair":
		# Plus/cross shape
		var h_mesh := BoxMesh.new()
		h_mesh.size = Vector3(0.7, 0.2, 0.15)
		var h_bar := MeshInstance3D.new()
		h_bar.mesh = h_mesh
		h_bar.material_override = mat
		group.add_child(h_bar)

		var v_mesh := BoxMesh.new()
		v_mesh.size = Vector3(0.2, 0.7, 0.15)
		var v_bar := MeshInstance3D.new()
		v_bar.mesh = v_mesh
		v_bar.material_override = mat
		group.add_child(v_bar)
	elif pick_type == "shield":
		# Simple diamond shape as shield stand-in
		var prism_mesh := PrismMesh.new()
		prism_mesh.size = Vector3(0.6, 0.8, 0.15)
		var prism := MeshInstance3D.new()
		prism.mesh = prism_mesh
		prism.material_override = mat
		group.add_child(prism)
	else:
		# Octahedron-like shape (use a sphere as approximation)
		var oct_mesh := SphereMesh.new()
		oct_mesh.radius = 0.35
		oct_mesh.height = 0.7
		oct_mesh.radial_segments = 4
		oct_mesh.rings = 2
		var oct := MeshInstance3D.new()
		oct.mesh = oct_mesh
		oct.material_override = mat
		group.add_child(oct)

	# Glow sphere
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.5
	glow_mesh.height = 1.0
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(color.r, color.g, color.b, 0.15)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glow := MeshInstance3D.new()
	glow.mesh = glow_mesh
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(glow)

	group.position = Vector3(pick.get("x", 0.0), 0.6, pick.get("y", 0.0))
	pickables_node.add_child(group)
	pickable_meshes[key] = group


func _on_pickable_remove(_pick: Dictionary, key: String) -> void:
	if pickable_meshes.has(key):
		var group: Node3D = pickable_meshes[key]
		pickables_node.remove_child(group)
		group.queue_free()
		pickable_meshes.erase(key)


func _on_team_add(team: Dictionary, _key) -> void:
	callbacks.listen(team, "score", func(_val, _prev): _update_scores())


func _on_winner_changed(val, _prev) -> void:
	if val is int and val >= 0:
		_show_winner_screen(val)
	elif val is float and val >= 0:
		_show_winner_screen(int(val))
	# Hide death/respawn labels when winner is announced
	death_label.visible = false
	respawn_label.visible = false


func _update_scores() -> void:
	var state := room.get_state()
	var state_teams = state.get("teams", [])

	var teams_data: Array[Dictionary] = []
	for i in range(mini(4, state_teams.size() if state_teams is Array else 4)):
		var team = state_teams[i] if state_teams is Array and i < state_teams.size() else null
		var score: int = 0
		if team is Dictionary:
			score = team.get("score", 0)
		teams_data.append({"id": i, "score": score})

	teams_data.sort_custom(func(a, b): return a["score"] > b["score"])

	for rank in range(teams_data.size()):
		if rank < score_labels.size():
			var t = teams_data[rank]
			score_labels[rank].text = "%s: %d" % [TEAM_NAMES[t["id"]], t["score"]]
			score_labels[rank].add_theme_color_override("font_color", TEAM_COLORS[t["id"]])


func _show_winner_screen(winner_team_id: int) -> void:
	var state := room.get_state()
	var state_tanks = state.get("tanks", {})
	var my_tank = state_tanks.get(my_session_id) if state_tanks is Dictionary else null

	var is_winner := false
	if my_tank is Dictionary:
		is_winner = my_tank.get("team", -1) == winner_team_id

	winner_label.text = "VICTORY" if is_winner else "DEFEAT"
	var team_name: String = TEAM_NAMES[winner_team_id] if winner_team_id < TEAM_NAMES.size() else "Unknown"
	winner_team_label.text = "%s Team Wins" % team_name
	winner_container.visible = true

	# Auto-hide after 2.8 seconds
	get_tree().create_timer(2.8).timeout.connect(func():
		winner_container.visible = false
	)


# ── Input ──

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = event.pressed
			if room:
				room.send_message("shoot", event.pressed)


func _send_input() -> void:
	if not room:
		return

	# Movement
	var raw_x: float = 0.0
	var raw_y: float = 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		raw_y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		raw_y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		raw_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		raw_x += 1.0

	# Rotate input by -45° to match isometric camera
	var angle := -PI / 4.0
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	var dir_x := roundf(raw_x * cos_a - raw_y * sin_a)
	var dir_y := roundf(raw_x * sin_a + raw_y * cos_a)

	if dir_x != last_sent_dir_x or dir_y != last_sent_dir_y:
		room.send_message("move", {"x": dir_x, "y": dir_y})
		last_sent_dir_x = dir_x
		last_sent_dir_y = dir_y

	# Turret angle from mouse
	if tanks.has(my_session_id):
		var my_tank: TankEntity = tanks[my_session_id]

		# Raycast from camera through mouse position to ground plane (Y=0)
		var from := camera.project_ray_origin(mouse_position)
		var dir := camera.project_ray_normal(mouse_position)

		if dir.y != 0:
			var t := -from.y / dir.y
			var world_pos := from + dir * t

			var dx := world_pos.x - my_tank.position.x
			var dz := world_pos.z - my_tank.position.z
			var target_angle_deg := rad_to_deg(atan2(dx, dz))
			target_angle_deg = fmod(fmod(target_angle_deg, 360.0) + 360.0, 360.0)

			my_tank.target_angle = target_angle_deg

			var angle_diff := fmod(target_angle_deg - last_sent_angle + 540.0, 360.0) - 180.0
			var now := float(Time.get_ticks_msec())
			if absf(angle_diff) > 1.0 and (now - last_target_send_time) >= 100.0:
				room.send_message("target", target_angle_deg)
				last_sent_angle = target_angle_deg
				last_target_send_time = now


# ── Game Loop ──

func _process(delta: float) -> void:
	# Required for web builds
	ColyseusClient.poll()

	if room:
		_send_input()

	# Update tanks and their screen-space health bars
	for key in tanks:
		var tank: TankEntity = tanks[key]
		tank.update_tank(delta)

		if tank_health_bars.has(key):
			var bars: Dictionary = tank_health_bars[key]
			var bg: ColorRect = bars["bg"]
			var fill: ColorRect = bars["fill"]
			var bar_w: float = bars["width"]

			var show := not tank.is_dead
			bg.visible = show
			fill.visible = show

			if show and camera:
				var world_pos := tank.global_position + Vector3(0, 1.8, 0)
				var screen_pos := camera.unproject_position(world_pos)
				bg.position = screen_pos - Vector2(bar_w * 0.5, 0)
				fill.position = bg.position
				fill.size.x = bar_w * tank.health_pct

				# Color by health percentage
				if tank.health_pct > 0.5:
					fill.color = Color(0.267, 1.0, 0.267)
				elif tank.health_pct > 0.25:
					fill.color = Color(1.0, 0.667, 0.267)
				else:
					fill.color = Color(1.0, 0.267, 0.267)

	# Animate pickables (float + rotate)
	var t := Time.get_ticks_msec() * 0.001
	for key in pickable_meshes:
		var group: Node3D = pickable_meshes[key]
		group.position.y = 0.6 + sin(t * 2.0) * 0.15
		group.rotation.y = t

	# Bullet interpolation
	for key in bullet_meshes:
		var mesh: MeshInstance3D = bullet_meshes[key]
		if bullet_data.has(key):
			var data: Dictionary = bullet_data[key]
			mesh.position.x = lerpf(mesh.position.x, data["sx"], 0.4)
			mesh.position.z = lerpf(mesh.position.z, data["sy"], 0.4)

	# Camera follow with mouse look-ahead
	if tanks.has(my_session_id):
		var my_tank: TankEntity = tanks[my_session_id]
		var tx := my_tank.position.x
		var tz := my_tank.position.z

		var viewport_size := get_viewport().get_visible_rect().size
		var nx := (mouse_position.x / viewport_size.x) * 2.0 - 1.0
		var ny := (mouse_position.y / viewport_size.y) * 2.0 - 1.0

		var look_ahead := 3.0
		var offset_x := (nx + ny) * 0.707 * look_ahead
		var offset_z := (-nx + ny) * 0.707 * look_ahead

		var target_cam_x := tx + 20.0 + offset_x
		var target_cam_z := tz + 20.0 + offset_z

		if _camera_needs_snap:
			_camera_needs_snap = false
			camera.position = Vector3(target_cam_x, 20.0, target_cam_z)
		else:
			camera.position.x = lerpf(camera.position.x, target_cam_x, 0.08)
			camera.position.z = lerpf(camera.position.z, target_cam_z, 0.08)
			camera.position.y = 20.0

		camera.look_at(Vector3(
			camera.position.x - 20.0,
			0,
			camera.position.z - 20.0
		))


func _exit_tree() -> void:
	if room and room.is_connected():
		room.leave()
