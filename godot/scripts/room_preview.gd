extends Node3D

signal card_sound(kind: String)

const SeatActor := preload("res://scripts/seat_actor.gd")
const CardTable := preload("res://scripts/card_table.gd")
const Dealer := preload("res://scripts/dealer.gd")
const Parlor := preload("res://scripts/parlor.gd")
const TABLE_WIDTH := 1.7
const CHAIR_HEIGHT := 0.95
const LAMP_WIDTH := 0.38
const FELT_Y := 0.70
const FELT_TOP := FELT_Y + 0.013
const FELT_RADIUS := 0.755
const SHADE_BOTTOM := 1.62
const CAST := [
	{"id": 2, "name": "kaya", "angle": 180.0, "style": "lead"},
	{"id": 1, "name": "sis", "angle": 270.0, "style": "watch"},
	{"id": 3, "name": "karaca", "angle": 90.0, "style": "settle"},
]
const ROSTER := [
	{"id": "kaya", "name": "Kaya"},
	{"id": "sis", "name": "Sis"},
	{"id": "kok", "name": "Kök"},
	{"id": "karaca", "name": "Karaca"},
	{"id": "sirtlan", "name": "Sırtlan"},
	{"id": "dere", "name": "Dere"},
]
const SEAT_TUCK := 0.04
const _FEEL_PATH := "res://data/feel.tres"
# Walking out: the ring around the table clear of the chairs, the doorway in
# the wall behind the seated player, and for that player the seconds from
# getting up to the door and how long the screen takes to go dark there.
const EXIT_RING := 1.85
const DOOR := Vector3(0.0, 0.0, 4.3)
const EXIT_WALK := 3.6
const EXIT_FADE := 1.0
const CHAIR_PUSH := 0.32
# The croupier stands at the rim in the gap between the far seat and the one
# on the right, so the seated player sees every card it handles.
const DEALER_ANGLE := 135.0
const DEALER_RADIUS := 1.17

var play_mode := false
var _actors: Dictionary = {}
var _table: Node3D
var _chairs: Array[Node3D] = []
var _player_preset := "kok"
var _seat_titles := {}
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
var _seat_chairs := {}
var _shake := 0.0
var _follow := -1
var _exit_t := -1.0
var _exit_from := Transform3D.IDENTITY
var _exit_ready := false
var _door_shut := false
var _blackout := 0.0
var _dealer: Node3D


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
		_chairs = _place_chairs(chair)
		_seat_cast(_chairs)
	if play_mode:
		_place_dealer()
	if lamp != null:
		_fit_xz(lamp, LAMP_WIDTH)
		_center_xz(lamp)
		var lamp_box := _world_aabb(lamp)
		lamp.position.y += SHADE_BOTTOM - lamp_box.position.y
	_cover_felt()
	_dress_room()
	var feel := _feel()
	_grade(feel)
	$SpotLight3D.position = Vector3(0.0, SHADE_BOTTOM - 0.05, 0.0)
	$SpotLight3D.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	if play_mode:
		_open_table()
	else:
		var camera := $Camera3D as Camera3D
		var seat_z := TABLE_WIDTH * 0.5 + 0.48
		camera.position = Vector3(0.0, 1.18, seat_z)
		camera.fov = 62.0
		camera.look_at(Vector3(0.0, 1.0, -0.02))


func roster() -> Array:
	return ROSTER


func player_preset() -> String:
	return _player_preset


func set_player(preset: String) -> void:
	if preset == _player_preset or not play_mode:
		return
	var known := false
	for entry in ROSTER:
		if str(entry["id"]) == preset:
			known = true
	if not known:
		return
	_player_preset = preset
	_clear_cast()
	_reset_exits()
	if not _chairs.is_empty():
		_seat_cast(_chairs)
	_open_table()


func reset_seats() -> void:
	# Everyone back at the table after a sitting in which someone walked out.
	if not play_mode:
		return
	var stale := _exit_t >= 0.0 or _blackout > 0.0
	for actor in _actors.values():
		if actor.gone or actor.leaving():
			stale = true
	if not stale:
		return
	_clear_cast()
	_reset_exits()
	if not _chairs.is_empty():
		_seat_cast(_chairs)
	_open_table()


func blackout() -> float:
	return _blackout


func _reset_exits() -> void:
	for id in _seat_chairs:
		var chair: Node3D = _seat_chairs[id][0]
		if is_instance_valid(chair):
			chair.transform = _seat_chairs[id][1]
	_seat_chairs.clear()
	_shake = 0.0
	_follow = -1
	_exit_t = -1.0
	_exit_ready = false
	_door_shut = false
	_blackout = 0.0


func seat_preset(id: int) -> String:
	for spec in _play_specs():
		if int(spec["id"]) == id:
			return str(spec["name"])
	return _player_preset


func seat_names() -> Array:
	var names: Array = []
	for id in [0, 1, 2, 3]:
		names.append(str(_seat_titles.get(id, "")))
	return names


func _clear_cast() -> void:
	for id in _actors.keys():
		var actor: Node = _actors[id]
		if is_instance_valid(actor):
			actor.free()
	_actors.clear()
	if _table != null and is_instance_valid(_table):
		_table.free()
		_table = null


func _open_table() -> void:
	if not play_mode or not _actors.has(0):
		return
	var camera := $Camera3D as Camera3D
	var feel := _feel()
	var me: Node3D = _actors[0]
	var eye: Vector3 = me.eye_point()
	var look := Vector3(0.0, FELT_TOP + 0.2, 0.22)
	var back := eye - look
	back.y = 0.0
	back = back.normalized()
	camera.global_position = eye + back * 0.48 + Vector3(0.0, 0.34, 0.0)
	camera.fov = float(feel.camera_fov)
	camera.near = float(feel.camera_near)
	camera.look_at(look)
	_cam_rest = camera.global_transform
	_cam_live = true
	_aim_yaw = 0.0
	_aim_pitch = 0.0
	_look_yaw = 0.0
	_look_pitch = 0.0
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	me.make_first_person(camera)
	for id in _actors:
		_actors[id].camera = camera
		if id != 0:
			_actors[id].make_fingered()
	if _actors.size() != 4:
		return
	_table = CardTable.new()
	_table.name = "CardTable"
	add_child(_table)
	var dirs := {}
	for id in _actors:
		var at: Vector3 = (_actors[id] as Node3D).global_position
		dirs[id] = Vector3(at.x, 0.0, at.z).normalized()
	_table.setup(_actors, dirs, camera, FELT_TOP, _dealer)
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
	_push_chairs(delta)
	if _exit_t >= 0.0:
		_exit_t += delta
		if _exit_t >= SeatActor.RISE_AT:
			_walk_camera(_exit_t - SeatActor.RISE_AT)
			return
	_follow_walker()
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
	_shake = maxf(0.0, _shake - step * 2.4)
	var jolt := _shake * _shake
	var basis := Basis(Vector3.UP, _look_yaw + lean) * _cam_rest.basis * Basis(Vector3.RIGHT, pitch + lean * 0.65 - 0.03 * jolt * sin(_clock * 57.0))
	var shift := _cam_rest.basis * Vector3(0.0, -0.02 * _reveal, -float(feel.reveal_dolly) * _reveal)
	shift += Vector3(sin(_clock * 71.0), cos(_clock * 53.0), 0.0) * (0.009 * jolt)
	var camera := $Camera3D as Camera3D
	camera.global_transform = Transform3D(basis, _cam_rest.origin + Vector3(sway, breath, sway * 0.35) + shift)
	if _actors.has(0):
		_actors[0].set_look_yaw(_look_yaw * float(feel.body_follow))


func _follow_walker() -> void:
	# Turn the view after whoever is walking out, as far as the head turns;
	# the croupier watches them go too.
	if _follow < 0 or not _actors.has(_follow):
		return
	var walker: Node3D = _actors[_follow]
	if _dealer != null and not walker.gone:
		_dealer.look_point = walker.head_point()
	if walker.gone:
		_follow = -1
		_aim_yaw = 0.0
		_aim_pitch = 0.0
		return
	if not walker.standing():
		return
	var ahead := -_cam_rest.basis.z
	var to: Vector3 = walker.head_point() - _cam_rest.origin
	var yaw := Vector3(ahead.x, 0.0, ahead.z).signed_angle_to(Vector3(to.x, 0.0, to.z), Vector3.UP)
	if not is_finite(yaw):
		return
	var limit := float(_feel().look_yaw_limit)
	_aim_yaw = clampf(yaw, -limit, limit)
	_aim_pitch = 0.08


func _walk_camera(t: float) -> void:
	# The seated player gets up, turns to the door behind them and walks to
	# it while the room goes dark.
	var camera := $Camera3D as Camera3D
	if not _exit_ready:
		_exit_ready = true
		_exit_from = camera.global_transform
	var from_ahead := -_exit_from.basis.z
	var yaw0 := atan2(-from_ahead.x, -from_ahead.z)
	var pitch0 := asin(clampf(from_ahead.y, -1.0, 1.0))
	var rise := _ease(t / 0.9)
	var turn := _ease((t - 0.5) / 1.2)
	var walk := _ease((t - 1.3) / (EXIT_WALK - 1.3))
	var back := Vector3(_exit_from.origin.x, 0.0, _exit_from.origin.z).normalized()
	var origin := _exit_from.origin + Vector3.UP * (0.36 * rise) + back * (0.25 * rise)
	var to_door := DOOR - origin
	var yaw_door := atan2(-to_door.x, -to_door.z)
	origin = origin.lerp(Vector3(DOOR.x, origin.y, DOOR.z - 0.6), walk)
	origin.y += 0.012 * sin(t * 9.0) * clampf((t - 1.3) * 3.0, 0.0, 1.0) * (1.0 - walk)
	var pitch := lerpf(pitch0, -0.04, rise)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, lerp_angle(yaw0, yaw_door, turn), 0.0)), origin)
	_blackout = _ease((t - (EXIT_WALK - EXIT_FADE * 0.6)) / EXIT_FADE)
	if not _door_shut and t >= EXIT_WALK:
		_door_shut = true
		card_sound.emit("door")


func _ease(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _push_chairs(delta: float) -> void:
	# A chair scrapes back as its player gets up.
	for id in _seat_chairs:
		if id == 0 or not _actors.has(id):
			continue
		var actor: Node3D = _actors[id]
		if not (actor.gone or actor.standing()):
			continue
		var chair: Node3D = _seat_chairs[id][0]
		var rest: Transform3D = _seat_chairs[id][1]
		var out := Vector3(rest.origin.x, 0.0, rest.origin.z).normalized()
		var goal := rest.origin + out * CHAIR_PUSH
		chair.position = chair.position.lerp(goal, 1.0 - exp(-7.0 * delta))


func _spring(current: float, velocity: float, target: float, omega: float, delta: float) -> Vector2:
	# Exact step of the critically damped spring. Stepping it by Euler blew
	# up once omega * delta passed about 2 (slow frames), and the camera with it.
	var off := current - target
	var k := velocity + omega * off
	var decay := exp(-omega * delta)
	return Vector2(target + (off + k * delta) * decay, (velocity - omega * k * delta) * decay)


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
	# A little haze so the far wall falls away and the lamp's beam shows.
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.22, 0.15)
	env.fog_light_energy = 0.6
	env.fog_density = 0.03
	env.fog_sky_affect = 0.0
	var spot := $SpotLight3D as SpotLight3D
	spot.light_color = feel.lamp_color
	spot.light_energy = float(feel.lamp_energy)
	spot.spot_angle = float(feel.lamp_angle)
	var fill := $Fill as DirectionalLight3D
	fill.light_energy = float(feel.fill_energy)


func _dress_room() -> void:
	for node_name in ["Floor", "WallBack", "WallLeft", "WallRight"]:
		var old := get_node_or_null(node_name)
		if old:
			old.visible = false
	var parlor := Parlor.new()
	parlor.name = "Parlor"
	add_child(parlor)
	parlor.build(4.2, 2.95, Vector3(0.0, SHADE_BOTTOM, 0.0))


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
	# Four places square round the table, a quarter turn apart, as a table
	# laid for four players is.
	var angles: Array[float] = [180.0, 270.0, 90.0]
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


func _play_specs() -> Array:
	var others: Array[String] = []
	for entry in ROSTER:
		var preset := str(entry["id"])
		if preset != _player_preset:
			others.append(preset)
	return [
		{"id": 2, "name": others[0], "angle": 180.0, "style": "lead"},
		{"id": 1, "name": others[1], "angle": 270.0, "style": "watch"},
		{"id": 3, "name": others[2], "angle": 90.0, "style": "settle"},
		{"id": 0, "name": _player_preset, "angle": 0.0, "style": "player"},
	]


func _title_for(preset: String) -> String:
	for entry in ROSTER:
		if str(entry["id"]) == preset:
			return str(entry["name"])
	return preset


func _seat_cast(chairs: Array[Node3D]) -> void:
	var specs: Array = CAST.duplicate()
	if play_mode:
		specs = _play_specs()
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
			var seat_id := int(spec["id"])
			_actors[seat_id] = actor
			_seat_titles[seat_id] = _title_for(str(spec["name"]))
			_seat_chairs[seat_id] = [chair, chair.transform]
			actor.connect("thumped", _on_thump)
			actor.connect("departed", _on_departed.bind(seat_id))


func _place_dealer() -> void:
	var packed: PackedScene = load("res://assets/characters/krupiye.glb")
	if packed == null:
		return
	_dealer = packed.instantiate() as Node3D
	_dealer.set_script(Dealer)
	add_child(_dealer)
	var radians := deg_to_rad(DEALER_ANGLE)
	_dealer.position = Vector3(sin(radians), 0.0, cos(radians)) * DEALER_RADIUS
	_dealer.rotation = Vector3(0.0, radians + PI, 0.0)
	_dealer.call("setup", _table_info())
	_dealer.connect("sound", func(kind: String): card_sound.emit(kind))
	# Black feathers stand outside the lamp's cone: a soft warm fill from the
	# table side and a cool rim from behind lift the crow off the wall.
	var out := Vector3(sin(radians), 0.0, cos(radians))
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.78, 0.55)
	fill.light_energy = 0.7
	fill.omni_range = 1.6
	fill.position = out * (DEALER_RADIUS - 0.75) + Vector3.UP * 1.45
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.62, 0.7, 0.95)
	rim.light_energy = 0.9
	rim.omni_range = 1.3
	rim.position = out * (DEALER_RADIUS + 0.55) + Vector3.UP * 1.7
	add_child(rim)


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
	_stage_duel(game, in_match)


func _stage_duel(game: Match, in_match: bool) -> void:
	# The throw after a hand, and whoever loses it from last place walking out.
	if not play_mode or _actors.size() != 4:
		return
	var seated := in_match and game.players.size() == Match.SEATS
	var dueling := seated and game.phase == Match.PHASE_DUEL and game.duel_loser >= 0 and game.duel_winner >= 0
	for id in _actors:
		var actor: Node3D = _actors[id]
		if actor.gone or actor.leaving():
			continue
		if not seated:
			actor.duel_rest()
			continue
		var storming: bool = dueling and game.duel_out and game.duel_loser == id
		if game.players[id].out and not storming:
			actor.vanish()
			continue
		if dueling and _dealer != null and not _dealer.busy():
			_dealer.look_point = (_eye_of(game.duel_loser) + _eye_of(game.duel_winner)) * 0.5
		if not dueling or (id != game.duel_loser and id != game.duel_winner):
			actor.duel_rest()
			if dueling and id != 0:
				actor.look_point = (_eye_of(game.duel_loser) + _eye_of(game.duel_winner)) * 0.5 + Vector3.DOWN * 0.15
			continue
		var other: int = game.duel_winner if id == game.duel_loser else game.duel_loser
		if game.duel_stage == Match.DUEL_AFTER:
			# Hands come down once the throw is settled; the loser's fist goes
			# into the table instead.
			if not storming:
				actor.duel_rest()
			elif id == 0:
				_exit_t = 0.0
				actor.storm_out([])
			else:
				_follow = id
				actor.storm_out(_exit_path(id))
			if id != 0:
				actor.look_point = _eye_of(other)
			continue
		actor.duel_pose(game.duel_stage, game.duel_age, int(game.duel_throws.get(id, -1)), _eye_of(other))
		if id != 0:
			actor.look_point = _eye_of(other)


func _eye_of(id: int) -> Vector3:
	if id == 0 or not _actors.has(id):
		return ($Camera3D as Camera3D).global_position
	return _actors[id].head_point()


func _exit_path(id: int) -> Array:
	# A step out beside the chair, round the table clear of the other chairs
	# on the near side, then past the seated player to the door behind them.
	var at: Vector3 = (_actors[id] as Node3D).global_position
	var side := -1.0 if at.x <= 0.05 else 1.0
	var seat := atan2(at.x, at.z)
	if side < 0.0 and seat > 0.0:
		seat -= TAU
	if side > 0.0 and seat < 0.0:
		seat += TAU
	var travel := -side
	var goal := side * 1.0
	var angle := seat + travel * 0.3
	var path: Array = [_on_floor(angle, Vector2(at.x, at.z).length() + 0.25), _on_floor(angle, EXIT_RING)]
	while (goal - angle) * travel > 0.3:
		angle += travel * 0.3
		path.append(_on_floor(angle, EXIT_RING))
	path.append(_on_floor(goal, EXIT_RING))
	path.append(Vector3(side * 1.8, 0.0, 2.3))
	path.append(Vector3(side * 0.6, 0.0, 3.75))
	path.append(DOOR)
	return path


func _on_floor(angle: float, radius: float) -> Vector3:
	return Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)


func _on_thump() -> void:
	_shake = 1.0
	card_sound.emit("thump")
	if _table != null:
		_table.hop()


func _on_departed(id: int) -> void:
	card_sound.emit("door")
	if _follow == id:
		_follow = -1
		_aim_yaw = 0.0
		_aim_pitch = 0.0


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


func resync(game: Match) -> void:
	if _table != null:
		_table.resync(game)


func reveal_ready() -> bool:
	return _table == null or _table.reveal_ready()


func revealed() -> Array:
	return [] if _table == null else _table.revealed()


func hurry(on: bool) -> void:
	if _table != null:
		_table.hurry(on)


func busy() -> bool:
	if _table != null and _table.busy():
		return true
	if _exit_t >= 0.0 and _exit_t < SeatActor.RISE_AT + EXIT_WALK:
		return true
	for actor in _actors.values():
		if actor.leaving():
			return true
	return false


func seat_caption(player_id: int) -> String:
	return str(_seat_titles.get(player_id, ""))


func seat_screen_pos(player_id: int) -> Vector2:
	if not _actors.has(player_id) or player_id == 0 or _actors[player_id].gone:
		return Vector2(-1, -1)
	var actor := _actors[player_id] as Node3D
	var point: Vector3 = actor.head_point() + Vector3.UP * 0.25
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
