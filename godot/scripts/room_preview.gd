extends Node3D

signal card_sound(kind: String)

const SeatActor := preload("res://scripts/seat_actor.gd")
const CardTable := preload("res://scripts/card_table.gd")
const TABLE_WIDTH := 1.7
const CHAIR_HEIGHT := 0.95
const LAMP_WIDTH := 0.38
const FELT_Y := 0.70
const FELT_TOP := FELT_Y + 0.013
const FELT_RADIUS := 0.755
const SHADE_BOTTOM := 1.62
const CAST := [
	{"id": 2, "name": "kaya", "angle": 180.0, "style": "lead"},
	{"id": 1, "name": "sis", "angle": 250.0, "style": "watch"},
	{"id": 3, "name": "karaca", "angle": 110.0, "style": "settle"},
]
const PLAYER := {"id": 0, "name": "kok", "angle": 0.0, "style": "player"}
const SEAT_NAME := {1: "Sis", 2: "Kaya", 3: "Karaca"}
const SEAT_TUCK := 0.04
const _FEEL_PATH := "res://data/feel.tres"

var play_mode := false
var _actors: Dictionary = {}
var _table: Node3D
var _feel_data: Resource
var _clock := 0.0
var _cam_rest := Transform3D.IDENTITY
var _cam_live := false
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _yaw_vel := 0.0
var _pitch_vel := 0.0
var _inspect := 0.0
var _inspect_goal := 0.0
var _reveal := 0.0


func _ready() -> void:
	var table := _spawn("masa")
	var chair := _spawn("sandalye")
	var lamp := _spawn("lamba")
	if table == null:
		return
	_fit_xz(table, TABLE_WIDTH)
	_fit_floor_height(table, FELT_Y)
	_sit_on_floor(table, FELT_Y, true)
	if chair != null:
		_fit_height(chair, CHAIR_HEIGHT)
		_seat_cast(_place_chairs(chair))
	if lamp != null:
		_fit_xz(lamp, LAMP_WIDTH)
		_center_xz(lamp)
		var lamp_box := _world_aabb(lamp)
		lamp.position.y += SHADE_BOTTOM - lamp_box.position.y
	_cover_felt()
	var camera := $Camera3D as Camera3D
	var feel := _feel()
	_grade(feel)
	if play_mode and _actors.has(0):
		var me: Node3D = _actors[0]
		var eye: Vector3 = me.eye_point()
		camera.global_position = eye + Vector3(0.0, float(feel.eye_lift), 0.0)
		camera.fov = float(feel.camera_fov)
		camera.near = float(feel.camera_near)
		camera.look_at(Vector3(0.0, FELT_TOP + 0.2, 0.22))
		_cam_rest = camera.global_transform
		_cam_live = true
		me.make_first_person(camera)
	else:
		var seat_z := TABLE_WIDTH * 0.5 + 0.48
		camera.position = Vector3(0.0, 1.18, seat_z)
		camera.fov = 62.0
		camera.look_at(Vector3(0.0, 1.0, -0.02))
	$SpotLight3D.position = Vector3(0.0, SHADE_BOTTOM - 0.05, 0.0)
	$SpotLight3D.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	if play_mode:
		for id in _actors:
			_actors[id].camera = camera
	if play_mode and _actors.size() == 4:
		_table = CardTable.new()
		_table.name = "CardTable"
		add_child(_table)
		var dirs := {}
		for id in _actors:
			var at: Vector3 = (_actors[id] as Node3D).global_position
			dirs[id] = Vector3(at.x, 0.0, at.z).normalized()
		_table.setup(_actors, dirs, camera, FELT_TOP)
		_table.sound.connect(func(kind: String): card_sound.emit(kind))


func add_look(relative: Vector2) -> void:
	if not _cam_live:
		return
	var feel := _feel()
	if not bool(feel.look_enabled):
		return
	var sens := float(feel.look_sensitivity)
	_aim_yaw = clampf(_aim_yaw - relative.x * sens, -float(feel.look_yaw_limit), float(feel.look_yaw_limit))
	_aim_pitch = clampf(_aim_pitch - relative.y * sens, float(feel.look_pitch_min), float(feel.look_pitch_max))


func recenter_look() -> void:
	_aim_yaw = 0.0
	_aim_pitch = 0.0


func set_inspect(on: bool) -> void:
	_inspect_goal = 1.0 if on else 0.0
	if _actors.has(0):
		_actors[0].inspecting = on


func set_reveal(amount: float) -> void:
	_reveal = clampf(amount, 0.0, 1.0)


func camera_debug() -> String:
	var gap := 0.0
	if _actors.has(1) and _actors[1].has_method("_gaps"):
		var gaps: Vector3 = _actors[1].call("_gaps", "Right")
		gap = gaps.x
	return "yaw %.0f  pitch %.0f  inspect %.2f  paw %.3f" % [
		rad_to_deg(_look_yaw), rad_to_deg(_look_pitch), _inspect, gap,
	]


func _process(delta: float) -> void:
	if not _cam_live:
		return
	var step := minf(delta, 0.05)
	_clock += delta
	var feel := _feel()
	var yaw_state := _spring(_look_yaw, _yaw_vel, _aim_yaw, float(feel.look_omega), step)
	var pitch_state := _spring(_look_pitch, _pitch_vel, _aim_pitch, float(feel.look_omega), step)
	_look_yaw = yaw_state.x
	_yaw_vel = yaw_state.y
	_look_pitch = pitch_state.x
	_pitch_vel = pitch_state.y
	_inspect = lerpf(_inspect, _inspect_goal, 1.0 - exp(-6.0 * step))
	var breath := 0.0
	var sway := 0.0
	var lean := 0.0
	if bool(feel.sway_enabled):
		breath = sin(_clock * TAU * float(feel.breath_hz)) * float(feel.breath_meters)
		sway = sin(_clock * 0.37) * float(feel.sway_meters)
		lean = sin(_clock * 0.53 + 1.2) * float(feel.sway_radians)
	var pitch := _look_pitch + float(feel.inspect_pitch) * _inspect + float(feel.reveal_pitch) * _reveal
	var basis := Basis(Vector3.UP, _look_yaw + lean) * _cam_rest.basis * Basis(Vector3.RIGHT, pitch + lean * 0.65)
	var shift := _cam_rest.basis * Vector3(0.0, -0.02 * _reveal, -float(feel.reveal_dolly) * _reveal)
	var camera := $Camera3D as Camera3D
	camera.global_transform = Transform3D(basis, _cam_rest.origin + Vector3(sway, breath, sway * 0.35) + shift)
	if _actors.has(0):
		_actors[0].set_look_yaw(_look_yaw * float(feel.body_follow))


func _spring(current: float, velocity: float, target: float, omega: float, delta: float) -> Vector2:
	var accel := omega * omega * (target - current) - 2.0 * omega * velocity
	velocity += accel * delta
	current += velocity * delta
	return Vector2(current, velocity)


func _feel() -> Resource:
	if _feel_data == null:
		_feel_data = load(_FEEL_PATH) as Resource
		if _feel_data == null:
			_feel_data = preload("res://scripts/feel_config.gd").new()
	return _feel_data


func _grade(feel: Resource) -> void:
	var world := $WorldEnvironment as WorldEnvironment
	var env := world.environment
	if env == null:
		return
	env = env.duplicate()
	world.environment = env
	env.ambient_light_color = feel.ambient_color
	env.ambient_light_energy = float(feel.ambient_energy)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = float(feel.glow_strength)
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = float(feel.contrast)
	env.adjustment_saturation = float(feel.saturation)
	var spot := $SpotLight3D as SpotLight3D
	spot.light_color = feel.lamp_color
	spot.light_energy = float(feel.lamp_energy)
	spot.spot_angle = float(feel.lamp_angle)
	var fill := $Fill as DirectionalLight3D
	fill.light_energy = float(feel.fill_energy)


func _table_info() -> Dictionary:
	return {
		"center": Vector3.ZERO,
		"radius": TABLE_WIDTH * 0.5 + 0.16,
		"felt_radius": FELT_RADIUS + 0.05,
		"felt_top": FELT_TOP,
		"wood_top": FELT_TOP,
	}


func _cover_felt() -> void:
	var felt := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = FELT_RADIUS
	disc.bottom_radius = FELT_RADIUS
	disc.height = 0.012
	var felt_mat := StandardMaterial3D.new()
	felt_mat.albedo_color = Color(0.035, 0.145, 0.078)
	felt_mat.roughness = 0.94
	felt_mat.metallic = 0.0
	disc.material = felt_mat
	felt.mesh = disc
	felt.position = Vector3(0.0, FELT_Y + 0.007, 0.0)
	add_child(felt)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.742
	torus.outer_radius = 0.785
	torus.rings = 48
	torus.ring_segments = 8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.46, 0.22)
	brass.metallic = 0.85
	brass.roughness = 0.38
	torus.material = brass
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.3, 1.0)
	ring.position = Vector3(0.0, FELT_Y + 0.010, 0.0)
	add_child(ring)


func _spawn(name: String) -> Node3D:
	var packed: PackedScene = load("res://assets/room/%s.glb" % name)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	add_child(model)
	_matte(model)
	return model


func _place_chairs(source: Node3D) -> Array[Node3D]:
	source.position = Vector3.ZERO
	source.rotation = Vector3.ZERO
	_sit_on_floor(source, 0.0, false)
	var back_z := _back_offset_z(source)
	var box := _world_aabb(source)
	var front := box.size.z * 0.5
	var distance := TABLE_WIDTH * 0.5 - SEAT_TUCK + front
	var feet_y := source.position.y
	var angles: Array[float] = [180.0, 250.0, 110.0]
	if play_mode:
		angles.append(0.0)
	var copies: Array[Node3D] = [source]
	while copies.size() < angles.size():
		copies.append(source.duplicate() as Node3D)
	for index in copies.size():
		var model: Node3D = copies[index]
		if model.get_parent() == null:
			add_child(model)
		var radians := deg_to_rad(angles[index])
		model.position = Vector3(sin(radians) * distance, feet_y, cos(radians) * distance)
		model.rotation = Vector3.ZERO
		model.look_at(Vector3(0.0, feet_y, 0.0), Vector3.UP)
		if back_z < 0.0:
			model.rotate_y(PI)
	return copies


func _seat_cast(chairs: Array[Node3D]) -> void:
	var specs: Array = CAST.duplicate()
	if play_mode:
		specs.append(PLAYER)
	for spec in specs:
		var chair := _chair_nearest(chairs, float(spec["angle"]))
		if chair == null:
			continue
		var packed: PackedScene = load("res://assets/characters/%s.glb" % str(spec["name"]))
		if packed == null:
			continue
		var actor := packed.instantiate() as Node3D
		actor.set_script(SeatActor)
		add_child(actor)
		var forward := chair.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.001:
			forward = forward.normalized()
		actor.rotation = chair.rotation
		actor.position = chair.position - forward * 0.06
		actor.set("driven", play_mode)
		actor.call("setup", str(spec["name"]), str(spec["style"]), _table_info())
		if play_mode:
			_actors[int(spec["id"])] = actor


func _chair_nearest(chairs: Array[Node3D], degrees: float) -> Node3D:
	var radians := deg_to_rad(degrees)
	var wanted := Vector3(sin(radians), 0.0, cos(radians))
	var best: Node3D = null
	var best_dot := -2.0
	for chair in chairs:
		var flat := Vector3(chair.position.x, 0.0, chair.position.z).normalized()
		var facing := flat.dot(wanted)
		if facing > best_dot:
			best_dot = facing
			best = chair
	return best


func _fit_xz(model: Node3D, width: float) -> void:
	model.scale = Vector3.ONE
	var box := _world_aabb(model)
	var span := maxf(box.size.x, box.size.z)
	if span < 0.001:
		return
	var s := width / span
	model.scale = Vector3(s, s, s)


func _fit_floor_height(model: Node3D, height: float) -> void:
	var box := _world_aabb(model)
	if box.size.y < 0.001:
		return
	model.scale.y *= height / box.size.y


func _fit_height(model: Node3D, height: float) -> void:
	model.scale = Vector3.ONE
	var box := _world_aabb(model)
	if box.size.y < 0.001:
		return
	var s := height / box.size.y
	model.scale = Vector3(s, s, s)


func _sit_on_floor(model: Node3D, surface_y: float, use_top: bool) -> void:
	var box := _world_aabb(model)
	if use_top:
		model.position.y += surface_y - (box.position.y + box.size.y)
	else:
		model.position.y += surface_y - box.position.y
	box = _world_aabb(model)
	model.position.x += -box.get_center().x
	model.position.z += -box.get_center().z


func _center_xz(model: Node3D) -> void:
	var box := _world_aabb(model)
	model.position.x += -box.get_center().x
	model.position.z += -box.get_center().z


func _back_offset_z(model: Node3D) -> float:
	var box := _world_aabb(model)
	var high := box.position.y + box.size.y * 0.72
	var back_z := 0.0
	var back_n := 0
	var seat_z := 0.0
	var seat_n := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in verts:
			var world: Vector3 = mesh.global_transform * vertex
			if world.y >= high:
				back_z += world.z
				back_n += 1
			elif world.y <= box.position.y + box.size.y * 0.42:
				seat_z += world.z
				seat_n += 1
	if back_n == 0 or seat_n == 0:
		return -1.0
	return (back_z / float(back_n)) - (seat_z / float(seat_n))


func _matte(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if source.metallic_texture != null:
				continue
			var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			mat.metallic = 0.0
			mat.roughness = 0.82
			mesh.set_surface_override_material(surface, mat)


func sync_match(game: Match, in_match: bool, delta: float) -> void:
	if _table != null:
		_table.sync(game, in_match, delta)


func pick_card(point: Vector2) -> int:
	if _table == null:
		return -1
	return _table.pick(point)


func select_card(index: int) -> void:
	if _table != null:
		_table.select(index)


func fan_count(player_id: int) -> int:
	if _table == null:
		return 0
	return _table.fan_count(player_id)


func busy() -> bool:
	return _table != null and _table.busy()


func seat_caption(player_id: int) -> String:
	return str(SEAT_NAME.get(player_id, ""))


func seat_screen_pos(player_id: int) -> Vector2:
	if not _actors.has(player_id) or player_id == 0:
		return Vector2(-1, -1)
	var actor := _actors[player_id] as Node3D
	var point: Vector3 = actor.head_point() + Vector3.UP * 0.34
	var camera := $Camera3D as Camera3D
	if camera.is_position_behind(point):
		return Vector2(-1, -1)
	return camera.unproject_position(point)


func _world_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var piece: AABB = mesh.global_transform * mesh.get_aabb()
		if not found:
			merged = piece
			found = true
		else:
			merged = merged.merge(piece)
	return merged
