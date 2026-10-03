extends Node3D

const ROOM_FIT := 1.16
const SCALE := {
	"kaya": 1.0,
	"sis": 1.0,
	"kok": 1.0,
	"karaca": 1.0,
	"sirtlan": 1.0,
	"dere": 0.97,
}
const SIDES := ["Left", "Right"]
const CARD := Vector2(0.096, 0.134)
const THROW_KEYS := [0.28, 0.46, 0.78, 1.02, 1.36]
const TAKE_KEYS := [0.36, 0.76, 1.04]
const CLEAR := 0.016
const _FEEL_PATH := "res://data/feel.tres"

var first_person := false
var driven := false
var thinking := false
var watching := false
var inspecting := false
var look_point := Vector3.ZERO
var selected: Node3D = null
var fan: Array = []
var camera: Camera3D

var _skel: Skeleton3D
var _style := "lead"
var _time := 0.0
var _body: Dictionary = {}
var _nod: Dictionary = {}
var _yaw_axis: Dictionary = {}
var _upper: Dictionary = {}
var _fore: Dictionary = {}
var _paw: Dictionary = {}
var _paw_pts: Dictionary = {}
var _fore_pts: Dictionary = {}
var _unit := 0.0116
var _center := Vector3.ZERO
var _table_radius := 0.85
var _felt_radius := 0.787
var _felt_top := 0.713
var _wood_top := 0.70
var _yaw := 0.0
var _pitch := 0.0
var _head_yaw := 0.0
var _torso_yaw := 0.0
var _lean := 0.0
var _lean_goal := 0.0
var _raise := 0.0
var _head := Vector3.ZERO
var _fan_frame := Transform3D.IDENTITY
var _fan_local: Dictionary = {}
var _held: Node3D = null
var _held_from := Transform3D.IDENTITY
var _held_to := Transform3D.IDENTITY
var _held_mix := 0.0
var _act: Dictionary = {}
var _queue: Array = []
var _goal: Dictionary = {}
var _player_yaw := 0.0
var _use_player_yaw := false
var _lift: Dictionary = {}
var _gather := 0.0
var _present := 0.0
var _feel_data: Resource


func setup(preset: String, style: String, table: Dictionary) -> void:
	_style = style
	_center = table.get("center", Vector3.ZERO)
	_table_radius = float(table.get("radius", 0.85))
	_felt_radius = float(table.get("felt_radius", 0.787))
	_felt_top = float(table.get("felt_top", 0.713))
	_wood_top = float(table.get("wood_top", 0.70))
	var size: float = float(SCALE.get(preset, 1.0)) * ROOM_FIT
	scale = Vector3(size, size, size)
	_skel = find_child("Skeleton3D", true, false) as Skeleton3D
	_stop_clips()
	_cloth()
	_pose_legs()
	_plant_feet()
	_skel.force_update_all_bone_transforms()
	_measure_arms()
	_remember_axes()
	_body = _capture()
	_unit = _skel.global_transform.basis.get_scale().x
	_study_paws()
	look_point = Vector3(_center.x, _felt_top, _center.z)
	_head = _bone_world("Head")
	var frame := _frame()
	for side in SIDES:
		_goal[side] = _rest_goal(side, frame)
	_process(0.0)


func set_look_yaw(yaw: float) -> void:
	_use_player_yaw = true
	_player_yaw = clampf(yaw, -1.92, 1.92)


func make_first_person(cam: Camera3D) -> void:
	first_person = true
	camera = cam
	var idx := _skel.find_bone("Head")
	if idx >= 0:
		_skel.set_bone_pose_scale(idx, Vector3.ONE * 0.001)
	_scale_hand("LeftHand", 0.62)
	_scale_hand("RightHand", 0.55)
	var clip := _near_clip_shader()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if source == null:
				source = mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = clip
			mat.set_shader_parameter("albedo_tex", source.albedo_texture)
			mat.set_shader_parameter("albedo_color", source.albedo_color)
			mat.set_shader_parameter("roughness_amount", source.roughness)
			mat.set_shader_parameter("use_tex", source.albedo_texture != null)
			mesh.set_surface_override_material(surface, mat)


func _near_clip_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness_amount = 0.86;
uniform bool use_tex = true;
void fragment() {
	if (length(VERTEX) < 0.2) {
		discard;
	}
	vec3 color = albedo_color.rgb;
	if (use_tex) {
		color *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = color;
	ROUGHNESS = roughness_amount;
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
"""
	return shader


func eye_point() -> Vector3:
	var head := _bone_world("Head")
	var front := _bone_world("headfront")
	var top := _bone_world("head_end")
	if is_inf(front.x) or is_inf(top.x):
		return head + Vector3.UP * 0.08
	return head + (front - head) * 0.45 + (top - head) * 0.22


func head_point() -> Vector3:
	return _head + Vector3.UP * 0.06


func hips_point() -> Vector3:
	return _bone_world("Hips")


func fan_frame() -> Transform3D:
	return _fan_frame


func holds(card: Node3D) -> bool:
	if fan.has(card) or _held == card or _act.get("card") == card:
		return true
	for item in _queue:
		if item.get("card") == card:
			return true
	return false


func busy() -> bool:
	return not _act.is_empty() or not _queue.is_empty()


func add_to_fan(card: Node3D, index := -1) -> void:
	if card == null or fan.has(card):
		return
	var at := fan.size() if index < 0 else clampi(index, 0, fan.size())
	fan.insert(at, card)
	_fan_local[card] = _fan_frame.affine_inverse() * card.global_transform


func remove_from_fan(card: Node3D) -> void:
	fan.erase(card)
	_fan_local.erase(card)
	_warm_card(card, false)
	if selected == card:
		selected = null


func order_fan(cards: Array) -> void:
	var ordered: Array = []
	for card in cards:
		if fan.has(card):
			ordered.append(card)
	for card in fan:
		if not ordered.has(card):
			ordered.append(card)
	fan = ordered


func clear_fan() -> void:
	fan.clear()
	_fan_local.clear()
	_held = null
	_act = {}
	_queue.clear()
	selected = null


func throw_card(card: Node3D, aim: Vector3, done: Callable) -> void:
	_queue.append({"kind": "throw", "card": card, "aim": aim, "done": done})


func take_card(card: Node3D, index: int, done: Callable) -> void:
	_queue.append({"kind": "take", "card": card, "index": index, "done": done})


func cancel(card: Node3D) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].get("card") == card:
			_queue.remove_at(i)
	if _act.get("card") == card:
		if _held == card:
			_held = null
		_act = {}
	remove_from_fan(card)


func pick(cam: Camera3D, point: Vector2) -> Node3D:
	var w := CARD.x * 0.5
	var h := CARD.y * 0.5
	for i in range(fan.size() - 1, -1, -1):
		var card: Node3D = fan[i]
		var xf := card.global_transform
		var left := -w
		var right := w
		var outline := PackedVector2Array()
		for corner in [Vector3(left, h, 0.0), Vector3(right, h, 0.0), Vector3(right, -h, 0.0), Vector3(left, -h, 0.0)]:
			var spot: Vector3 = xf * corner
			if cam.is_position_behind(spot):
				outline.clear()
				break
			outline.append(cam.unproject_position(spot))
		if outline.size() == 4 and Geometry2D.is_point_in_polygon(point, outline):
			return card
	return null


func _process(delta: float) -> void:
	if _skel == null:
		return
	_time += delta
	if not driven:
		_demo()
	_pose_body(delta)
	_advance(delta)
	_pose_arms(delta)


func _pose_body(delta: float) -> void:
	_restore(_body)
	var aim := _look_angles(look_point)
	if _use_player_yaw:
		aim.x = _player_yaw
	var feel := _feel()
	var head_k := 1.0 - exp(-delta / maxf(float(feel.head_lag), 0.02))
	var torso_k := 1.0 - exp(-delta / maxf(float(feel.torso_lag), 0.02))
	_head_yaw = lerpf(_head_yaw, aim.x, head_k)
	_pitch = lerpf(_pitch, aim.y, head_k)
	_yaw = _head_yaw
	_lean = lerpf(_lean, _lean_goal, _rate(4.0, delta))
	var breath := 0.0 if first_person else sin(_time * 1.35 + _phase()) * 0.025
	var shares := _look_shares()
	var torso_target := _head_yaw if first_person else _head_yaw * shares.x
	_torso_yaw = lerpf(_torso_yaw, torso_target, torso_k)
	var torso := clampf(_torso_yaw, -0.28, 0.28) if first_person else clampf(_torso_yaw, -0.35, 0.35)
	_set_extra("Spine01", breath * 0.45 + _lean * 0.10, torso * 0.45)
	_set_extra("Spine02", breath + _lean * 0.17, torso * 0.55)
	if not first_person:
		var rest_yaw := _head_yaw - torso
		var upper := maxf(shares.y + shares.z, 0.001)
		_set_extra("neck", -_pitch * 0.35, rest_yaw * (shares.y / upper))
		_set_extra("Head", -_pitch * 0.65 + sin(_time * 0.7 + _phase()) * 0.02, rest_yaw * (shares.z / upper) + sin(_time * 0.42 + _phase()) * 0.03)
	_skel.force_update_all_bone_transforms()
	_head = _bone_world("Head")


func _look_angles(point: Vector3) -> Vector2:
	var f := _flat(global_transform.basis.z)
	var l := Vector3.UP.cross(f).normalized()
	var to := point - _head
	var ahead := to.dot(f)
	var side := to.dot(l)
	var yaw := atan2(side, ahead)
	var pitch := atan2(to.y, maxf(Vector2(ahead, side).length(), 0.01))
	return Vector2(clampf(yaw, -1.25, 1.25), clampf(pitch, -0.75, 0.45))


func _advance(delta: float) -> void:
	var frame := _frame()
	var raise_goal := 0.0
	if not fan.is_empty():
		if first_person:
			raise_goal = 0.0
		else:
			raise_goal = 0.55 if thinking else 0.2
	_raise = lerpf(_raise, raise_goal, _rate(4.0, delta))
	if _act.is_empty() and not _queue.is_empty():
		_act = _queue.pop_front()
		_act["t"] = 0.0
		_act["stage"] = -1
		_act["from"] = _goal["Right"]
	if _act.is_empty():
		_lean_goal = 0.0 if first_person else (0.28 if thinking else (0.1 if watching else 0.05))
		_goal["Right"] = _mix(_goal["Right"], _idle_right(frame), _rate(7.0, delta))
		if thinking and not fan.is_empty():
			look_point = _fan_frame.origin + _fan_frame.basis.y * 0.04
		return
	_act["t"] = float(_act["t"]) + delta
	if str(_act["kind"]) == "throw":
		_run_throw(frame)
	else:
		_run_take(frame)


func _run_throw(frame: Dictionary) -> void:
	var card: Node3D = _act["card"]
	var t: float = _act["t"]
	if int(_act["stage"]) < 1 and not fan.has(card):
		_finish(card)
		_act = {}
		return
	var stage := _stage_of(t, THROW_KEYS)
	if stage >= THROW_KEYS.size():
		_act = {}
		return
	if stage != int(_act["stage"]):
		var entering := int(_act["stage"])
		_act["from"] = _goal["Right"]
		_act["stage"] = stage
		if stage >= 1 and entering < 1:
			_act["pull"] = _goal["Right"]
			_grab(card, Transform3D(Basis.IDENTITY, Vector3(0.0, -CARD.y * 0.42, 0.012)))
		if stage >= 3 and entering < 3:
			_release()
	var to: Dictionary
	match stage:
		0:
			to = _grip_goal(card, frame)
		1:
			to = _pull_goal()
		2:
			to = _release_goal(frame)
		3:
			to = _follow_goal(frame)
		_:
			to = _idle_right(frame)
	var start := 0.0 if stage == 0 else float(THROW_KEYS[stage - 1])
	var u := clampf((t - start) / maxf(float(THROW_KEYS[stage]) - start, 0.01), 0.0, 1.0)
	if first_person:
		_goal["Right"] = _fp_hand_rest(1.0)
	else:
		_goal["Right"] = _mix(_act["from"], to, _smooth(u))
	if _held != null:
		_held_mix = _smooth(clampf((t - float(THROW_KEYS[0])) / (float(THROW_KEYS[2]) - float(THROW_KEYS[0])), 0.0, 1.0))
	var swing := _smooth(clampf((t - 0.3) / 0.32, 0.0, 1.0)) * (1.0 - _smooth(clampf((t - 0.7) / 0.4, 0.0, 1.0)))
	_lean_goal = 0.0 if first_person else 0.12 + 0.55 * swing
	if stage == 0 and not first_person:
		look_point = card.global_position
	elif not first_person:
		look_point = _act.get("aim", _center)


func _run_take(frame: Dictionary) -> void:
	var card: Node3D = _act["card"]
	var t: float = _act["t"]
	var keys: Array = TAKE_KEYS.duplicate()
	if not _queue.is_empty():
		keys[2] = float(keys[1]) + 0.12
	var stage := _stage_of(t, keys)
	if stage >= keys.size():
		_act = {}
		return
	if stage != int(_act["stage"]):
		var entering := int(_act["stage"])
		_act["from"] = _goal["Right"]
		_act["stage"] = stage
		if stage >= 1 and entering < 1:
			_grab(card, Transform3D.IDENTITY)
			_held_to = _held_from
		if stage >= 2 and entering < 2:
			_drop(card, int(_act.get("index", -1)))
	var to: Dictionary
	match stage:
		0:
			to = _pick_goal(card, frame)
		1:
			to = _drop_goal(frame)
		_:
			to = _idle_right(frame)
	var start := 0.0 if stage == 0 else float(keys[stage - 1])
	var u := clampf((t - start) / maxf(float(keys[stage]) - start, 0.01), 0.0, 1.0)
	if first_person:
		_goal["Right"] = _fp_hand_rest(1.0)
	else:
		_goal["Right"] = _mix(_act["from"], to, _smooth(u))
	var reach := _smooth(clampf(t / 0.3, 0.0, 1.0)) * (1.0 - _smooth(clampf((t - 0.4) / 0.35, 0.0, 1.0)))
	_lean_goal = 0.0 if first_person else 0.1 + 0.5 * reach
	if not first_person:
		look_point = card.global_position


func _stage_of(t: float, keys: Array) -> int:
	var stage := 0
	while stage < keys.size() and t >= float(keys[stage]):
		stage += 1
	return stage


func _grab(card: Node3D, to_local: Transform3D) -> void:
	remove_from_fan(card)
	_held = card
	if first_person:
		_act["card_from"] = card.global_transform
	_held_from = _grip_frame().affine_inverse() * card.global_transform
	_held_to = to_local
	_held_mix = 0.0


func _release() -> void:
	var card := _held
	_held = null
	if card != null:
		_finish(card)


func _finish(card: Node3D) -> void:
	if _act.get("finished", false):
		return
	_act["finished"] = true
	var done: Callable = _act.get("done", Callable())
	if done.is_valid():
		done.call(card)


func _drop(card: Node3D, index: int) -> void:
	_held = null
	if index == -2:
		index = randi_range(0, fan.size())
	add_to_fan(card, index)
	_finish(card)


func _frame() -> Dictionary:
	var f := _flat(global_transform.basis.z)
	var l := Vector3.UP.cross(f).normalized()
	var chest := (_bone_world("LeftArm") + _bone_world("RightArm")) * 0.5
	return {"f": f, "l": l, "chest": chest}


func _rest_goal(side: String, frame: Dictionary) -> Dictionary:
	var sign := 1.0 if side == "Left" else -1.0
	if first_person and camera != null and side == "Right":
		return _fp_right_rest(frame)
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	var chest: Vector3 = frame["chest"]
	var away := Vector2(chest.x - _center.x, chest.z - _center.z)
	if away.length() < 0.01:
		away = Vector2(f.x, f.z)
	away = away.normalized()
	var toward := Vector2(-away.x, -away.y)
	var hand_xz := Vector2(chest.x, chest.z) + toward * 0.26 + Vector2(l.x, l.z) * (0.12 * sign)
	var limit := _felt_radius - 0.1
	if hand_xz.length() > limit:
		hand_xz = hand_xz.normalized() * limit
	var p := Vector3(hand_xz.x, _felt_top + _clear() + 0.012, hand_xz.y)
	var along := (f * 0.96 + Vector3.UP * float(_feel().finger_lift)).normalized()
	var pole := (l * (0.82 * sign) + Vector3.DOWN * 0.2).normalized()
	return {"p": p, "len": along, "palm": Vector3.DOWN, "pole": pole, "contact": false, "plant": true}


func _fp_right_rest(_frame: Dictionary) -> Dictionary:
	return _fp_hand_rest(1.0)


func _fp_hand_rest(sign: float) -> Dictionary:
	var cam := camera.global_transform
	var ahead := _flat(-cam.basis.z)
	var right := _flat(cam.basis.x)
	var p := cam.origin + right * (0.42 * sign) + ahead * 0.86 + Vector3.DOWN * 0.6
	p.y = _felt_top + _clear() + 0.02
	return {
		"p": p,
		"len": (Vector3.DOWN * 0.88 + ahead * 0.28).normalized(),
		"palm": Vector3.DOWN,
		"pole": (Vector3.DOWN * 0.75 - right * sign * 0.45 - ahead * 0.15).normalized(),
		"contact": false,
	}


func _fan_goal(frame: Dictionary) -> Dictionary:
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	var raise := clampf(_raise, -1.0, 1.0)
	if first_person and camera != null:
		return _fp_hold_goal()
	var p: Vector3 = frame["chest"] + f * (0.30 + 0.03 * raise) + l * (0.13 - 0.07 * _gather)
	p.y = _felt_top + 0.125 + 0.04 * raise
	var eye := eye_point()
	var palm := (eye - p).normalized()
	var along := (Vector3.UP * 0.55 + f * 0.1 - l * 0.5).normalized()
	return {"p": p, "len": along, "palm": palm, "pole": _pole("Left", frame)}


func _idle_right(frame: Dictionary) -> Dictionary:
	return _rest_goal("Right", frame)


func _think_goal(frame: Dictionary) -> Dictionary:
	return _rest_goal("Right", frame)


func _grip_goal(card: Node3D, frame: Dictionary) -> Dictionary:
	var xf := card.global_transform
	var n := _fan_frame.basis.z * _grip_side()
	var top := xf * Vector3(0.0, CARD.y * 0.46, 0.0)
	if first_person and camera != null:
		var right := _flat(camera.global_transform.basis.x)
		var p := top + right * 0.16 + Vector3.DOWN * 0.02
		p.y = maxf(p.y, _felt_top + 0.1)
		return {
			"p": p,
			"len": (-right * 0.75 + Vector3.UP * 0.35).normalized(),
			"palm": (camera.global_position - p).normalized(),
			"pole": (Vector3.DOWN * 0.65 - right * 0.45).normalized(),
		}
	var p := top - xf.basis.y * _paw_reach("Right") + n * 0.035
	return {"p": p, "len": xf.basis.y, "palm": -n, "pole": _pole("Right", frame)}


func _pull_goal() -> Dictionary:
	var from: Dictionary = _act.get("pull", _goal["Right"])
	var goal := from.duplicate()
	var p: Vector3 = Vector3(from["p"]) + _fan_frame.basis.y * 0.015 + _fan_frame.basis.z * (0.01 * _grip_side())
	goal["p"] = p
	return goal


func _grip_side() -> float:
	return -1.0 if first_person else 1.0


func _release_goal(frame: Dictionary) -> Dictionary:
	if first_person and camera != null:
		var cam := camera.global_transform
		var ahead := _flat(-cam.basis.z)
		var right := _flat(cam.basis.x)
		var p := cam.origin + right * 0.24 + ahead * 0.66 + Vector3.DOWN * 0.32
		p.y = maxf(_felt_top + 0.1, p.y)
		return {
			"p": p,
			"len": (ahead * 0.65 + Vector3.DOWN * 0.4).normalized(),
			"palm": (Vector3.DOWN * 0.75 + ahead * 0.25).normalized(),
			"pole": _pole("Right", frame),
		}
	var aim: Vector3 = _act.get("aim", _center + Vector3.UP * _felt_top)
	aim.y = _felt_top + 0.02
	var shoulder := _bone_world("RightArm")
	var flat := aim - shoulder
	flat.y = 0.0
	var dir: Vector3 = flat.normalized() if flat.length() > 0.01 else frame["f"]
	var p := aim - dir * (_paw_reach("Right") + CARD.y * 0.2)
	p.y = _felt_top + _clear() + 0.01
	var pole := (-Vector3(frame["l"]) * 0.75 + Vector3.DOWN * 0.25).normalized()
	return {"p": p, "len": (dir * 0.92 + Vector3.UP * float(_feel().finger_lift)).normalized(), "palm": Vector3.DOWN, "pole": pole, "plant": true}


func _follow_goal(frame: Dictionary) -> Dictionary:
	var goal := _release_goal(frame)
	var p: Vector3 = goal["p"]
	p.y = maxf(_felt_top + _clear(), p.y - 0.006)
	goal["p"] = p
	return goal


func _pick_goal(card: Node3D, frame: Dictionary) -> Dictionary:
	var at := card.global_position
	var dir := at - _bone_world("RightArm")
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(frame["f"])
	return {"p": at - dir * 0.02 + Vector3.UP * 0.04, "len": dir, "palm": Vector3.DOWN, "pole": _pole("Right", frame), "contact": true}


func _drop_goal(frame: Dictionary) -> Dictionary:
	var deck := _fan_frame
	if fan.is_empty():
		var rest := _fan_goal(frame)
		rest["p"] = Vector3(rest["p"]) + Vector3(frame["f"]) * 0.02
		return rest
	var side := _grip_side()
	return {"p": deck * Vector3(0.05, CARD.y * 0.5, 0.06 * side), "len": deck.basis.y, "palm": -deck.basis.z * side, "pole": _pole("Right", frame)}


func _pole(side: String, frame: Dictionary) -> Vector3:
	var sign := 1.0 if side == "Left" else -1.0
	if first_person:
		return (Vector3.DOWN * 0.9 + Vector3(frame["l"]) * (0.4 * sign) - Vector3(frame["f"]) * 0.2).normalized()
	return (Vector3.DOWN * 0.8 + Vector3(frame["l"]) * (0.55 * sign) - Vector3(frame["f"]) * 0.25).normalized()


func _demo() -> void:
	var cycle := fmod(_time + _phase() * 2.0, 12.0)
	var f := _flat(global_transform.basis.z)
	var l := Vector3.UP.cross(f).normalized()
	look_point = Vector3(_center.x, _felt_top, _center.z)
	if cycle > 4.0 and cycle < 6.5:
		look_point = global_position + f * 1.4 + l * 1.2 + Vector3.UP * 0.9
	elif cycle > 8.5 and cycle < 10.5:
		look_point = global_position + f * 1.4 - l * 1.2 + Vector3.UP * 0.9
	thinking = false


func _pose_arms(delta: float) -> void:
	var gather_goal := 0.0
	if not _act.is_empty():
		var stage := int(_act.get("stage", -1))
		var kind := str(_act.get("kind", ""))
		if (kind == "throw" and stage <= 1) or (kind == "take" and stage == 1):
			gather_goal = 1.0
	_gather = lerpf(_gather, gather_goal, _rate(9.0, delta))
	if first_person:
		var present_goal := 1.0 if thinking or inspecting else 0.0
		_present = lerpf(_present, present_goal, _rate(4.5, delta))
	var frame := _frame()
	var left := _fan_goal(frame) if not fan.is_empty() else _rest_goal("Left", frame)
	_goal["Left"] = _mix(_goal.get("Left", left), left, _rate(8.0, delta))
	_solve("Left", _goal["Left"], delta)
	_fan_frame = _make_fan_frame()
	_layout_fan(delta)
	_solve("Right", _goal["Right"], delta)
	_carry()


func _solve(side: String, goal: Dictionary, delta: float) -> void:
	var along: Vector3 = Vector3(goal["len"]).normalized()
	var palm: Vector3 = goal["palm"]
	palm = palm - along * palm.dot(along)
	if palm.length() < 0.01:
		palm = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.UP)
	palm = palm.normalized()
	var world_basis := _paw_basis(side, along, palm)
	var paw: Dictionary = _paw[side]
	var wrist := Vector3(goal["p"])
	if not bool(goal.get("plant", false)):
		wrist = Vector3(goal["p"]) - world_basis * (Vector3(paw["center"]) * _unit)
	var pole: Vector3 = goal["pole"]
	if bool(goal.get("plant", false)):
		_seat_on_table(side, wrist, pole, world_basis)
		return
	if first_person:
		_lift_paw(side, wrist, pole, world_basis, float(_feel().plant_lift) * 0.6)
		return
	for i in 12:
		_reach(side, wrist, pole)
		_orient(side, world_basis)
		var gaps := _gaps(side)
		var low := minf(gaps.x, gaps.y)
		if low >= _clear():
			break
		wrist.y += clampf(_clear() - low, 0.003, 0.02)
	_lift[side] = 0.0


func _feel() -> Resource:
	if _feel_data == null:
		_feel_data = load(_FEEL_PATH) as Resource
		if _feel_data == null:
			_feel_data = preload("res://scripts/feel_config.gd").new()
	return _feel_data


func _clear() -> float:
	return float(_feel().table_clearance)


func _look_shares() -> Vector3:
	var feel := _feel()
	var spine := maxf(float(feel.look_spine), 0.0)
	var neck := maxf(float(feel.look_neck), 0.0)
	var head := maxf(float(feel.look_head), 0.0)
	var total := maxf(spine + neck + head, 0.001)
	return Vector3(spine / total, neck / total, head / total)


func _lift_paw(side: String, wrist: Vector3, pole: Vector3, world_basis: Basis, budget: float) -> Vector3:
	var raised := 0.0
	for _step in 3:
		_reach(side, wrist, pole)
		_orient(side, world_basis)
		var low := _gaps(side).x
		if low >= _clear() or raised >= budget:
			break
		var step := clampf(_clear() - low + 0.003, 0.0, budget - raised)
		wrist.y += step
		raised += step
	_reach(side, wrist, pole)
	_orient(side, world_basis)
	return wrist


func _seat_on_table(side: String, wrist: Vector3, pole: Vector3, world_basis: Basis) -> void:
	# Paw vertices decide the wrist height. Sleeve vertices far from the
	# bone used to drag the whole hand into the air, so they are ignored.
	wrist = _lift_paw(side, wrist, pole, world_basis, float(_feel().plant_lift))
	var shoulder := _bone_world(side + "Arm")
	var slid := 0.0
	var limit := float(_feel().arm_slide)
	for _slide in 2:
		var low := _bone_clearance(side, float(_feel().arm_skin))
		if low >= _clear() or slid >= limit:
			break
		var away := Vector3(shoulder.x - wrist.x, 0.0, shoulder.z - wrist.z)
		var pull := clampf(_clear() - low, 0.0, limit - slid)
		if away.length() > 0.05:
			wrist += away.normalized() * pull
		else:
			wrist.y += pull
		slid += pull
		_reach(side, wrist, pole)
		_orient(side, world_basis)
	_reach(side, wrist, pole)
	_orient(side, world_basis)


func _bone_clearance(side: String, skin: float) -> float:
	var elbow := _bone_world(side + "ForeArm")
	var hand := _bone_world(side + "Hand")
	var low := INF
	for k in 5:
		var at: Vector3 = elbow.lerp(hand, float(k) / 4.0) + Vector3.DOWN * skin
		var radius := Vector2(at.x - _center.x, at.z - _center.z).length()
		if radius > _felt_radius:
			continue
		low = minf(low, at.y - _felt_top)
	return low


func _reach(side: String, wrist: Vector3, pole: Vector3) -> void:
	var shoulder := _bone_world(side + "Arm")
	var a: float = _upper.get(side, 0.25)
	var b: float = _fore.get(side, 0.25)
	var to := wrist - shoulder
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else _flat(global_transform.basis.z)
	var d := clampf(dist, absf(a - b) + 0.01, a + b - 0.003)
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * dir.y
	bend = bend.normalized()
	var elbow := shoulder + dir * (a * cos_a) + bend * (a * sin_a)
	_aim(side + "Arm", elbow - shoulder)
	var joint := _bone_world(side + "ForeArm")
	_aim(side + "ForeArm", shoulder + dir * d - joint)


func _orient(side: String, world_basis: Basis) -> void:
	var idx := _skel.find_bone(side + "Hand")
	if idx < 0:
		return
	var parent := _skel.get_bone_parent(idx)
	var skel_rot := _skel.global_transform.basis.orthonormalized()
	var want := skel_rot.inverse() * world_basis
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		parent_basis = _skel.get_bone_global_pose(parent).basis.orthonormalized()
	var local := (parent_basis.inverse() * want).orthonormalized()
	_skel.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
	_skel.force_update_all_bone_transforms()


func _paw_basis(side: String, along: Vector3, palm: Vector3) -> Basis:
	var paw: Dictionary = _paw[side]
	var la: Vector3 = paw["len"]
	var ln: Vector3 = paw["palm"]
	var target := Basis(along, palm, along.cross(palm))
	var local := Basis(la, ln, la.cross(ln))
	return target * local.inverse()


func _gap(side: String) -> float:
	var gaps := _gaps(side)
	return minf(gaps.x, gaps.y)


func _gaps(side: String) -> Vector3:
	var hand_xf := _bone_xf(side + "Hand")
	var fore_xf := _bone_xf(side + "ForeArm")
	var paw := INF
	var fore := INF
	var reach := 0.0
	for p in _paw_pts[side]:
		paw = minf(paw, _above(hand_xf * p))
	for p in _fore_pts[side]:
		var at: Vector3 = fore_xf * p
		var g := _above(at)
		if g < fore:
			fore = g
			reach = Vector2(at.x - _center.x, at.z - _center.z).length()
	var elbow := _bone_world(side + "ForeArm")
	var wrist := _bone_world(side + "Hand")
	for k in 5:
		var at: Vector3 = elbow.lerp(wrist, float(k) / 4.0)
		var g := _above(at)
		if g < fore:
			fore = g
			reach = Vector2(at.x - _center.x, at.z - _center.z).length()
	return Vector3(paw, fore, reach)


func _above(point: Vector3) -> float:
	var r := Vector2(point.x - _center.x, point.z - _center.z).length()
	if r > _table_radius:
		return INF
	var top := _felt_top if r <= _felt_radius else _wood_top
	return point.y - top


func _make_fan_frame() -> Transform3D:
	if first_person and camera != null:
		return _fp_fan_frame()
	var xf := _bone_xf("LeftHand")
	var basis := xf.basis.orthonormalized()
	var paw: Dictionary = _paw["Left"]
	var n := (basis * Vector3(paw["palm"])).normalized()
	var along := (basis * Vector3(paw["len"])).normalized()
	var grip: Vector3 = Vector3(paw["center"]) + Vector3(paw["palm"]) * float(paw["surface"]) + Vector3(paw["len"]) * (float(paw["reach"]) * 0.45)
	var pivot: Vector3 = xf * grip + n * 0.006
	var up := Vector3.UP * 0.85 + along * 0.15
	up = up - n * up.dot(n)
	if up.length() < 0.01:
		up = along
	up = up.normalized()
	var x := up.cross(n).normalized()
	return Transform3D(Basis(x, up, n), pivot)


func _fp_hold_goal() -> Dictionary:
	var fan := _fp_fan_frame()
	var right := _flat(camera.global_transform.basis.x)
	var p := fan.origin - fan.basis.z * 0.12 - fan.basis.y * 0.06
	return {
		"p": p,
		"len": (fan.basis.y * 0.85 + fan.basis.z * 0.15).normalized(),
		"palm": fan.basis.z,
		"pole": (Vector3.DOWN * 0.65 - right * 0.55).normalized(),
	}


func _fp_fan_frame() -> Transform3D:
	var cam := camera.global_transform
	var ahead := _flat(-cam.basis.z)
	var right := _flat(cam.basis.x)
	var rest := cam.origin + right * -0.2 + ahead * 0.34 + Vector3.DOWN * 0.4
	var play := cam.origin + right * -0.05 + ahead * 0.4 + Vector3.DOWN * 0.34
	var pivot := rest.lerp(play, _present)
	pivot.y = maxf(pivot.y, _felt_top + 0.06)
	var n := (cam.origin - pivot).normalized()
	var up := Vector3.UP - n * n.dot(Vector3.UP)
	up = up.normalized()
	var x := up.cross(n).normalized()
	return Transform3D(Basis(x, up, n), pivot)


func _scale_hand(bone_name: String, amount: float) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return
	_scale_bone(idx, amount)


func _scale_bone(idx: int, amount: float) -> void:
	_skel.set_bone_pose_scale(idx, Vector3.ONE * amount)
	for child in _skel.get_bone_children(idx):
		_scale_bone(int(child), amount)


func _warm_card(card: Node3D, on: bool) -> void:
	var mesh := card as MeshInstance3D
	if mesh == null:
		return
	var marked := mesh.get_surface_override_material(0) != null
	if on == marked:
		return
	if not on:
		mesh.set_surface_override_material(0, null)
		return
	var source := mesh.get_active_material(0) as StandardMaterial3D
	if source == null:
		return
	var mat := source.duplicate() as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color(0.86, 0.64, 0.3)
	mat.emission_energy_multiplier = 0.25
	mesh.set_surface_override_material(0, mat)


func _layout_fan(delta: float) -> void:
	var count := fan.size()
	if count == 0:
		return
	var step := 0.042 if first_person else 0.07
	var cap := 0.52 if first_person else 0.78
	var spread := minf(step * float(count - 1), cap)
	var k := _rate(13.0, delta)
	for i in count:
		var card: Node3D = fan[i]
		var u := 0.5 if count == 1 else float(i) / float(count - 1)
		var lift := 0.018 if card == selected else 0.0
		if first_person:
			_warm_card(card, card == selected)
		var stack := 0.0016 * float(i)
		var goal: Transform3D
		if first_person:
			var open := lerpf(0.42, 1.0, 1.0 - _gather)
			var size := lerpf(0.62, 1.0, _present)
			var arc := minf(0.185 * float(count - 1), 2.15) * open * lerpf(0.78, 1.0, _present)
			var rot := Basis(Vector3.BACK, arc * (0.5 - u))
			goal = Transform3D(rot, rot * Vector3(0.0, CARD.y * 0.62 * size + lift, 0.0) + Vector3(0.0, 0.0, stack + lift * 0.2))
		else:
			var rot := Basis(Vector3.BACK, spread * (0.5 - u))
			goal = Transform3D(rot, rot * Vector3(0.0, CARD.y * 0.32 + lift, 0.0) + Vector3(0.0, 0.0, stack))
		var cur: Transform3D = _fan_local.get(card, goal)
		cur = goal if first_person else cur.interpolate_with(goal, k)
		_fan_local[card] = cur
		card.global_transform = _fan_frame * cur


func _grip_frame() -> Transform3D:
	var xf := _bone_xf("RightHand")
	var basis := xf.basis.orthonormalized()
	var paw: Dictionary = _paw["Right"]
	var y := (basis * Vector3(paw["len"])).normalized()
	var z := (basis * Vector3(paw["palm"])).normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var tip: Vector3 = xf * (Vector3(paw["center"]) + Vector3(paw["len"]) * float(paw["reach"]))
	return Transform3D(Basis(x, y, z), tip)


func _paw_reach(side: String) -> float:
	var paw: Dictionary = _paw[side]
	return float(paw["reach"]) * _unit


func _carry() -> void:
	if _held == null or not is_instance_valid(_held):
		return
	if first_person and camera != null:
		var from: Transform3D = _act.get("card_from", _held.global_transform)
		var aim: Vector3 = _act.get("aim", _fan_frame.origin)
		if str(_act.get("kind", "")) == "take":
			aim = _fan_frame.origin + _fan_frame.basis.y * (CARD.y * 0.4)
		var u := clampf((float(_act.get("t", 0.0)) - 0.2) / 0.75, 0.0, 1.0)
		var aim_at := aim
		if str(_act.get("kind", "")) != "take":
			aim_at.y = _felt_top + 0.012
		var along := _smooth(u)
		var pos := from.origin.lerp(aim_at, along)
		pos.y = lerpf(from.origin.y, aim_at.y, clampf(along * 2.2, 0.0, 1.0))
		var n := camera.global_position - pos
		if n.length() < 0.05:
			n = Vector3.UP
		n = n.normalized()
		var up := Vector3.UP - n * n.dot(Vector3.UP)
		if up.length() < 0.01:
			up = Vector3.FORWARD
		up = up.normalized()
		var x := up.cross(n).normalized()
		_held.global_transform = Transform3D(Basis(x, up, n), pos)
		return
	var local := _held_from.interpolate_with(_held_to, _held_mix)
	_held.global_transform = _grip_frame() * local


func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	return {
		"p": Vector3(a["p"]).lerp(Vector3(b["p"]), w),
		"len": _nlerp(a["len"], b["len"], w),
		"palm": _nlerp(a["palm"], b["palm"], w),
		"pole": _nlerp(a["pole"], b["pole"], w),
		"contact": bool(b.get("contact", false)),
		"plant": bool(b.get("plant", false)),
	}


func _nlerp(a: Vector3, b: Vector3, w: float) -> Vector3:
	var out := a.lerp(b, w)
	if out.length() < 0.001:
		return b.normalized()
	return out.normalized()


func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


func _rate(speed: float, delta: float) -> float:
	if delta <= 0.0:
		return 1.0
	return 1.0 - exp(-speed * delta)


func _phase() -> float:
	match _style:
		"watch":
			return 2.2
		"settle":
			return 4.6
		"player":
			return 1.3
		_:
			return 0.4


func _measure_arms() -> void:
	for side in SIDES:
		var shoulder := _bone_world(side + "Arm")
		var elbow := _bone_world(side + "ForeArm")
		var hand := _bone_world(side + "Hand")
		_upper[side] = maxf(shoulder.distance_to(elbow), 0.08)
		_fore[side] = maxf(elbow.distance_to(hand), 0.08)


func _study_paws() -> void:
	var meshes := find_children("*", "MeshInstance3D", true, false)
	for side in SIDES:
		var hand_idx := _skel.find_bone(side + "Hand")
		var fore_idx := _skel.find_bone(side + "ForeArm")
		var hand_pts := PackedVector3Array()
		var fore_pts := PackedVector3Array()
		for node in meshes:
			_collect(node as MeshInstance3D, hand_idx, fore_idx, hand_pts, fore_pts)
		_paw[side] = _describe(side, hand_idx, hand_pts)
		_paw_pts[side] = _with_lowest(_thin(hand_pts, 120), hand_pts, 16)
		_fore_pts[side] = _with_lowest(_thin(_core(fore_pts), 120), fore_pts, 12)


func _collect(mi: MeshInstance3D, hand_idx: int, fore_idx: int, hand_pts: PackedVector3Array, fore_pts: PackedVector3Array) -> void:
	if mi == null or mi.mesh == null:
		return
	var skin := mi.skin
	var binds := {}
	if skin != null:
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = _skel.find_bone(skin.get_bind_name(b))
			binds[b] = [bone, skin.get_bind_pose(b)]
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var per: int = bones.size() / verts.size()
		for v in verts.size():
			var best := -1
			var best_w := 0.0
			for k in per:
				var w: float = weights[v * per + k]
				if w > best_w:
					best_w = w
					best = int(bones[v * per + k])
			if best < 0:
				continue
			var bone_idx := best
			var bind := Transform3D.IDENTITY
			if binds.has(best):
				bone_idx = int(binds[best][0])
				bind = binds[best][1]
			elif bone_idx < _skel.get_bone_count():
				bind = _skel.get_bone_global_rest(bone_idx).affine_inverse()
			if bone_idx == hand_idx:
				hand_pts.append(bind * verts[v])
			elif bone_idx == fore_idx:
				fore_pts.append(bind * verts[v])


func _describe(side: String, hand_idx: int, pts: PackedVector3Array) -> Dictionary:
	if pts.size() < 12 or hand_idx < 0:
		return {"len": Vector3.UP, "palm": Vector3.BACK, "center": Vector3(0.0, 8.0, 0.0), "surface": 3.0, "reach": 7.0}
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var cov := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in pts:
		var d := p - c
		var row := [d.x, d.y, d.z]
		for r in 3:
			for q in 3:
				cov[r][q] += row[r] * row[q]
	var axes := _jacobi(cov)
	var palm: Vector3 = axes[2]
	var along := c - palm * c.dot(palm)
	if along.length() < 0.001:
		along = Vector3.UP - palm * palm.y
	along = along.normalized()
	palm = (palm - along * palm.dot(along)).normalized()
	var rest := _skel.get_bone_global_rest(hand_idx)
	var rest_world := _skel.global_transform.basis.orthonormalized() * rest.basis.orthonormalized()
	var left := global_transform.basis.x.normalized()
	var medial := -left if side == "Left" else left
	if (rest_world * palm).dot(medial * 0.7 + Vector3.DOWN * 0.7) < 0.0:
		palm = -palm
	var faces := PackedFloat32Array()
	var tips := PackedFloat32Array()
	for p in pts:
		faces.append((p - c).dot(palm))
		tips.append((p - c).dot(along))
	faces.sort()
	tips.sort()
	return {
		"len": along,
		"palm": palm,
		"center": c,
		"surface": faces[int(faces.size() * 0.85)],
		"reach": tips[int(tips.size() * 0.85)],
	}


func _core(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 12:
		return pts
	var radii := PackedFloat32Array()
	for p in pts:
		radii.append(Vector2(p.x, p.z).length())
	var sorted := radii.duplicate()
	sorted.sort()
	var cap: float = sorted[int(sorted.size() * 0.5)]
	var out := PackedVector3Array()
	for i in pts.size():
		if radii[i] <= cap:
			out.append(pts[i])
	return out


func _thin(pts: PackedVector3Array, count: int) -> PackedVector3Array:
	if pts.size() <= count:
		return pts
	var out := PackedVector3Array()
	var step := float(pts.size()) / float(count)
	for i in count:
		out.append(pts[int(float(i) * step)])
	return out


func _with_lowest(base: PackedVector3Array, pts: PackedVector3Array, extra: int) -> PackedVector3Array:
	if pts.is_empty():
		return base
	var ranked: Array = []
	for p in pts:
		ranked.append(p)
	ranked.sort_custom(func(a, b): return a.y < b.y)
	var out := base
	for i in mini(extra, ranked.size()):
		out.append(ranked[i])
	return out


func _jacobi(m: Array) -> Array:
	var a := [[m[0][0], m[0][1], m[0][2]], [m[1][0], m[1][1], m[1][2]], [m[2][0], m[2][1], m[2][2]]]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for _sweep in 24:
		for p in 3:
			for q in range(p + 1, 3):
				if absf(a[p][q]) < 1e-12:
					continue
				var theta: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
				var t: float = signf(theta) / (absf(theta) + sqrt(theta * theta + 1.0))
				if theta == 0.0:
					t = 1.0
				var c := 1.0 / sqrt(t * t + 1.0)
				var s := t * c
				for k in 3:
					var akp: float = a[k][p]
					var akq: float = a[k][q]
					a[k][p] = c * akp - s * akq
					a[k][q] = s * akp + c * akq
				for k in 3:
					var apk: float = a[p][k]
					var aqk: float = a[q][k]
					a[p][k] = c * apk - s * aqk
					a[q][k] = s * apk + c * aqk
				for k in 3:
					var vkp: float = v[k][p]
					var vkq: float = v[k][q]
					v[k][p] = c * vkp - s * vkq
					v[k][q] = s * vkp + c * vkq
	var values := [a[0][0], a[1][1], a[2][2]]
	var vectors := [Vector3(v[0][0], v[1][0], v[2][0]), Vector3(v[0][1], v[1][1], v[2][1]), Vector3(v[0][2], v[1][2], v[2][2])]
	var order := [0, 1, 2]
	order.sort_custom(func(x, y): return values[x] > values[y])
	return [vectors[order[0]], vectors[order[1]], vectors[order[2]]]


func _flat(v: Vector3) -> Vector3:
	var out := Vector3(v.x, 0.0, v.z)
	if out.length() < 0.001:
		return Vector3.FORWARD
	return out.normalized()


func _pose_legs() -> void:
	var forward := global_transform.basis.z
	var left := global_transform.basis.x
	var down := Vector3.DOWN
	_bend("Spine02", 0.06)
	_bend("Head", 0.08)
	_aim("LeftUpLeg", forward + left * 0.16 + down * 0.28)
	_aim("RightUpLeg", forward - left * 0.16 + down * 0.28)
	_aim("LeftLeg", forward * 0.12 + left * 0.04 + down)
	_aim("RightLeg", forward * 0.12 - left * 0.04 + down)
	_aim("LeftFoot", forward + down * 0.05)
	_aim("RightFoot", forward + down * 0.05)


func _bend(bone_name: String, angle: float) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return
	_skel.force_update_all_bone_transforms()
	var axis := _local_axis(idx, global_transform.basis.x)
	var pose := _skel.get_bone_pose_rotation(idx)
	_skel.set_bone_pose_rotation(idx, pose * Quaternion(axis, angle))


func _aim(bone_name: String, world_dir: Vector3) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0 or world_dir.length() < 0.001:
		return
	_skel.force_update_all_bone_transforms()
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	var local_target: Vector3 = global.basis.orthonormalized().inverse() * (skel_basis.inverse() * world_dir.normalized())
	if local_target.length() < 0.001:
		return
	var extra := _quat_from_to(Vector3.UP, local_target.normalized())
	var pose := _skel.get_bone_pose_rotation(idx)
	_skel.set_bone_pose_rotation(idx, pose * extra)
	_skel.force_update_all_bone_transforms()


func _remember_axes() -> void:
	for bone_name in ["Spine02", "Spine01", "neck", "Head"]:
		var idx := _skel.find_bone(bone_name)
		if idx < 0:
			continue
		_nod[bone_name] = _local_axis(idx, global_transform.basis.x)
		_yaw_axis[bone_name] = _local_axis(idx, global_transform.basis.y)


func _local_axis(idx: int, world_axis: Vector3) -> Vector3:
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	return (global.basis.orthonormalized().inverse() * (skel_basis.inverse() * world_axis)).normalized()


func _set_extra(bone_name: String, nod: float, yaw: float) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0 or not _body.has(bone_name):
		return
	var extra := Quaternion.IDENTITY
	if absf(nod) > 0.0001 and _nod.has(bone_name):
		extra = extra * Quaternion(_nod[bone_name], nod)
	if absf(yaw) > 0.0001 and _yaw_axis.has(bone_name):
		extra = extra * Quaternion(_yaw_axis[bone_name], yaw)
	var base: Quaternion = _body[bone_name]
	_skel.set_bone_pose_rotation(idx, base * extra)


func _plant_feet() -> void:
	_skel.force_update_all_bone_transforms()
	var lowest := 1000.0
	for bone_name in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
		var point := _bone_world(bone_name)
		if is_inf(point.x):
			continue
		lowest = minf(lowest, point.y)
	if lowest < 100.0:
		position.y -= lowest


func _bone_world(bone_name: String) -> Vector3:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return Vector3(INF, INF, INF)
	return _skel.global_transform * _skel.get_bone_global_pose(idx).origin


func _bone_xf(bone_name: String) -> Transform3D:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return global_transform
	return _skel.global_transform * _skel.get_bone_global_pose(idx)


func _capture() -> Dictionary:
	var poses := {}
	for i in _skel.get_bone_count():
		poses[_skel.get_bone_name(i)] = _skel.get_bone_pose_rotation(i)
	return poses


func _restore(poses: Dictionary) -> void:
	for bone_name in poses.keys():
		var idx := _skel.find_bone(str(bone_name))
		if idx < 0:
			continue
		var rotation: Quaternion = poses[bone_name]
		_skel.set_bone_pose_rotation(idx, rotation)


func _stop_clips() -> void:
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	player.active = false
	player.stop()


func _cloth() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			mat.metallic = 0.0
			if mat.roughness_texture == null:
				mat.roughness = 0.86
			mat.metallic_specular = 0.18
			mesh.set_surface_override_material(surface, mat)


static func _quat_from_to(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.99999999:
		return Quaternion.IDENTITY
	if dot < -0.9999:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length() < 0.001:
			axis = a.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	var cross := a.cross(b)
	return Quaternion(cross.x, cross.y, cross.z, 1.0 + dot).normalized()
