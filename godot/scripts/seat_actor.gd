extends Node3D

const FPHands := preload("res://scripts/fp_hands.gd")
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
# First person: fan pivot in camera space while waiting and while playing,
# with the roll of the fan; how far the sleeve runs up the hand's forearm;
# the widest fan; how far the right hand turns about its hooked index when
# it takes a standing card, so the wrist comes in from the lower right; how
# strongly the elbows are drawn toward where they hang at rest.
const FP_FAN_WAIT := Vector3(-0.21, -0.25, -0.5)
const FP_FAN_PLAY := Vector3(-0.12, -0.19, -0.4)
const FP_ROLL_WAIT := -0.16
const FP_ROLL_PLAY := -0.06
const FP_SLEEVE := 0.05
const FP_SLEEVE_GIRTH := Vector3(0.8, 1.0, 0.8)
const FP_SPREAD := 0.72
const FP_SPREAD_PLAY := 0.98
const FP_STEP_WAIT := 0.12
const FP_STEP_PLAY := 0.165
const FP_DROP_WAIT := 0.03
const FP_DROP_PLAY := 0.085
const FP_PLUCK_TURN := 0.5
const FP_ELBOW_HANG := 1.5
# A seated opponent's fan, waiting and while choosing: how far out before the
# chest, to the left of it and above the felt its pivot sits, and how far at
# most it tips back toward the eyes. It faces them square to the chair, not
# turned sideways after them, so the seats either side see its back, not
# its edge, and the higher camera does not look onto its faces.
const SEAT_FAN_OUT := Vector2(0.3, 0.29)
const SEAT_FAN_SIDE := Vector2(0.07, 0.04)
const SEAT_FAN_HIGH := Vector2(0.1, 0.13)
const SEAT_FAN_TIP := 0.45
# The head and neck as a solid: one point of skin per HEAD_CELL cube. No card of
# the fan comes nearer it than HEAD_CLEAR; the fan backs away along its
# normal at once and eases back in at HEAD_EASE metres a second. Head points
# further than HEAD_REACH from the pivot cannot be under a card, and one
# HEAD_DEEP behind the cards is a horn or ear past the fan's edge, not
# something to push the fan beyond; the push stops at HEAD_PUSH_MAX.
const HEAD_CELL := 0.028
const HEAD_CLEAR := 0.04
const HEAD_EASE := 0.08
const HEAD_REACH := 0.26
const HEAD_DEEP := 0.08
const HEAD_PUSH_MAX := 0.14
# After a hand: the rock-paper-scissors throw, and for a last-placed player
# who loses it, a fist on the table and the walk out. Seconds into that: fist
# at the top of the swing, fist on the felt, getting up, and how long getting
# up takes. Then walking pace, leg cycle in radians a second, and how far the
# fist's little-finger edge sits below the wrist line.
const THROW_SHAPES := ["rock", "paper", "scissors"]
const FIST_TOP := 0.5
const FIST_HIT := 0.64
const RISE_AT := 1.45
const RISE_TIME := 0.9
const WALK_SPEED := 1.05
const STEP_RATE := 5.4
const FIST_DROP := 0.048

signal thumped
signal departed

var first_person := false
# Seated opponents wear fingered hands too, driven by the same grips.
var fingered := false
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
# Cards picked up under the held one, a dealt pile lifted as a whole, each
# by its frame relative to the held card.
var _held_rest: Dictionary = {}
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
var _preset := "kaya"
var _hands: Node3D = null
var _fp_xf: Dictionary = {}
var _fp_mix: Dictionary = {}
var _held_local_from := Transform3D.IDENTITY
var _held_local_to := Transform3D.IDENTITY
var _held_blend := 1.0
var _held_rate := 10.0
var gone := false
var punched := false
var _duel: Dictionary = {}
var _exit: Dictionary = {}
var _stand: Dictionary = {}
var _head_parts: Array = []
var _head_push := 0.0
static var _coats := {}


func setup(preset: String, style: String, table: Dictionary) -> void:
	_preset = preset
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
	_stand = _capture()
	_cloth()
	_pose_legs()
	_plant_feet()
	_skel.force_update_all_bone_transforms()
	_measure_arms()
	_remember_axes()
	_body = _capture()
	_unit = _skel.global_transform.basis.get_scale().x
	_study_paws()
	_study_head()
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
	var fill := cam.get_node_or_null("HandFill") as OmniLight3D
	if fill == null:
		fill = OmniLight3D.new()
		fill.name = "HandFill"
		cam.add_child(fill)
	fill.light_color = Color(1.0, 0.92, 0.8)
	fill.light_energy = 0.85
	fill.omni_range = 1.6
	fill.shadow_enabled = false
	var idx := _skel.find_bone("Head")
	if idx >= 0:
		_skel.set_bone_pose_scale(idx, Vector3.ONE * 0.001)
	# The Meshy paw is a single bone, so the seated player gets fingered hands
	# at the end of the sleeves instead.
	_scale_hand("LeftHand", 0.001)
	_scale_hand("RightHand", 0.001)
	# This close to the eye the coat sleeves would dwarf the wrists coming out
	# of them, so they are slimmed across, never along the arm.
	for side in SIDES:
		var fore := _skel.find_bone(side + "ForeArm")
		if fore >= 0:
			_skel.set_bone_pose_scale(fore, FP_SLEEVE_GIRTH)
	for bone_name in ["LeftUpLeg", "RightUpLeg"]:
		var leg := _skel.find_bone(bone_name)
		if leg >= 0:
			_scale_bone(leg, 0.001)
	var clip := _near_clip_shader()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if _hands == null:
		_hands = FPHands.new()
		_hands.name = "FirstPersonHands"
		add_child(_hands)
		_hands.setup(_preset, scale.x)
		for side in SIDES:
			_fp_xf[side] = _fp_rest(side)
			_fp_mix[side] = {"relax": 1.0}


func _near_clip_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness_amount = 0.86;
uniform bool use_tex = true;
void fragment() {
	if (length(VERTEX) < 0.08) {
		discard;
	}
	vec3 color = albedo_color.rgb;
	if (use_tex) {
		color *= texture(albedo_tex, UV).rgb;
	}
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(0.34, 0.24, 0.16), color, smoothstep(0.02, 0.22, luma));
	ALBEDO = color;
	ROUGHNESS = roughness_amount;
	METALLIC = 0.0;
	SPECULAR = 0.18;
	EMISSION = color * 0.28;
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


func duel_pose(stage: int, age: float, throw: int, toward: Vector3) -> void:
	# Raised hand for the throw: a fist through the chant, then `throw`.
	_duel = {"stage": stage, "age": age, "throw": throw, "toward": toward}


func duel_rest() -> void:
	_duel = {}


func storm_out(path: Array) -> void:
	# Fist on the table, then up and along `path` (floor points) to the door.
	if gone or not _exit.is_empty():
		return
	_exit = {"t": 0.0, "path": path, "leg": 0, "step": 0.0, "from": _fp_xf.get("Right", null)}
	_duel = {}
	punched = false


func leaving() -> bool:
	return not _exit.is_empty() and not gone


func standing() -> bool:
	return leaving() and float(_exit["t"]) >= RISE_AT


func vanish() -> void:
	gone = true
	visible = false
	_exit = {}
	_duel = {}
	clear_fan()


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
	_held_rest.clear()
	_act = {}
	_queue.clear()
	selected = null


func throw_card(card: Node3D, aim: Vector3, done: Callable) -> void:
	_queue.append({"kind": "throw", "card": card, "aim": aim, "done": done})


func take_card(card: Node3D, index: int, done: Callable, rest := []) -> void:
	# Picks `card` up off the felt into the fan; `rest` lie under it in the
	# same pile and come up with it.
	_queue.append({"kind": "take", "card": card, "index": index, "done": done, "rest": rest})


func cancel(card: Node3D) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].get("card") == card:
			_queue.remove_at(i)
	if _act.get("card") == card:
		if _held == card:
			_held = null
			_held_rest.clear()
		_act = {}
	remove_from_fan(card)


func pick(cam: Camera3D, point: Vector2) -> Node3D:
	for i in range(fan.size() - 1, -1, -1):
		var card: Node3D = fan[i]
		var xf := card.global_transform
		var w := CARD.x * 0.5
		var h := CARD.y * 0.5
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
	if _skel == null or gone:
		return
	_time += delta
	if not driven:
		_demo()
	if not _exit.is_empty():
		_exit["t"] = float(_exit["t"]) + delta
		if not punched and float(_exit["t"]) >= FIST_HIT:
			punched = true
			thumped.emit()
		if float(_exit["t"]) >= RISE_AT:
			if first_person:
				# The room carries the camera out from here.
				vanish()
				return
			_pose_walk(delta)
			return
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
	var sit := 0.55 if first_person else 0.0
	_set_extra("Spine01", breath * 0.45 + _lean * 0.10 + sit * 0.4, torso * 0.45)
	_set_extra("Spine02", breath + _lean * 0.17 + sit * 0.6, torso * 0.55)
	if first_person:
		_bend("Hips", -0.45)
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
	if _fingered():
		_fp_act_events()
	elif str(_act["kind"]) == "throw":
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
	# One stage a frame at most, so a long frame never skips a stage's entry.
	var stage := mini(_stage_of(t, THROW_KEYS), int(_act["stage"]) + 1)
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
	_goal["Right"] = _mix(_act["from"], to, _smooth(u))
	if _held != null:
		_held_mix = _smooth(clampf((t - float(THROW_KEYS[0])) / (float(THROW_KEYS[2]) - float(THROW_KEYS[0])), 0.0, 1.0))
	var swing := _smooth(clampf((t - 0.3) / 0.32, 0.0, 1.0)) * (1.0 - _smooth(clampf((t - 0.7) / 0.4, 0.0, 1.0)))
	_lean_goal = 0.12 + 0.55 * swing
	if stage == 0:
		look_point = card.global_position
	else:
		look_point = _act.get("aim", _center)


func _run_take(frame: Dictionary) -> void:
	var card: Node3D = _act["card"]
	var t: float = _act["t"]
	var keys: Array = TAKE_KEYS.duplicate()
	if not _queue.is_empty():
		keys[2] = float(keys[1]) + 0.12
	var stage := mini(_stage_of(t, keys), int(_act["stage"]) + 1)
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
	_goal["Right"] = _mix(_act["from"], to, _smooth(u))
	var reach := _smooth(clampf(t / 0.3, 0.0, 1.0)) * (1.0 - _smooth(clampf((t - 0.4) / 0.35, 0.0, 1.0)))
	_lean_goal = 0.1 + 0.5 * reach
	look_point = card.global_position


func _stage_of(t: float, keys: Array) -> int:
	var stage := 0
	while stage < keys.size() and t >= float(keys[stage]):
		stage += 1
	return stage


func _grab(card: Node3D, to_local: Transform3D) -> void:
	remove_from_fan(card)
	_held = card
	_lift_rest(card)
	# The skeleton is still the seated rest pose here. Arm IK runs afterwards,
	# so the card has to be parented in that posed hand, not measured against it now.
	_held_from = to_local
	_held_to = to_local
	_held_mix = 1.0


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
	for under in _held_rest:
		if is_instance_valid(under):
			add_to_fan(under)
	_held_rest.clear()
	add_to_fan(card, index)
	_finish(card)


func _lift_rest(card: Node3D) -> void:
	# The cards under a picked-up one, if it was lifted off a pile.
	_held_rest.clear()
	if str(_act.get("kind", "")) != "take":
		return
	var inverse := card.global_transform.affine_inverse()
	for under in _act.get("rest", []):
		if is_instance_valid(under) and under != card:
			_held_rest[under] = inverse * (under as Node3D).global_transform


func _frame() -> Dictionary:
	var f := _flat(global_transform.basis.z)
	var l := Vector3.UP.cross(f).normalized()
	var chest := (_bone_world("LeftArm") + _bone_world("RightArm")) * 0.5
	return {"f": f, "l": l, "chest": chest}


func _rest_goal(side: String, frame: Dictionary) -> Dictionary:
	var sign := 1.0 if side == "Left" else -1.0
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


func _fan_goal(frame: Dictionary) -> Dictionary:
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	var raise := clampf(_raise, -1.0, 1.0)
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
	var n := _fan_frame.basis.z
	var top := xf * Vector3(0.0, CARD.y * 0.46, 0.0)
	var p := top - xf.basis.y * _paw_reach("Right") + n * 0.035
	return {"p": p, "len": xf.basis.y, "palm": -n, "pole": _pole("Right", frame)}


func _pull_goal() -> Dictionary:
	var from: Dictionary = _act.get("pull", _goal["Right"])
	var goal := from.duplicate()
	var p: Vector3 = Vector3(from["p"]) + _fan_frame.basis.y * 0.015 + _fan_frame.basis.z * 0.01
	goal["p"] = p
	return goal


func _release_goal(frame: Dictionary) -> Dictionary:
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
	return {"p": deck * Vector3(0.05, CARD.y * 0.5, 0.06), "len": deck.basis.y, "palm": -deck.basis.z, "pole": _pole("Right", frame)}


func _pole(side: String, frame: Dictionary) -> Vector3:
	var sign := 1.0 if side == "Left" else -1.0
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
	if _fingered():
		_fp_pose(delta)
		return
	var gather_goal := 0.0
	if not _act.is_empty():
		var stage := int(_act.get("stage", -1))
		var kind := str(_act.get("kind", ""))
		if (kind == "throw" and stage <= 1) or (kind == "take" and stage == 1):
			gather_goal = 1.0
	_gather = lerpf(_gather, gather_goal, _rate(9.0, delta))
	var frame := _frame()
	var left := _fan_goal(frame) if not fan.is_empty() else _rest_goal("Left", frame)
	_goal["Left"] = _mix(_goal.get("Left", left), left, _rate(8.0, delta))
	_solve("Left", _goal["Left"], delta)
	_fan_frame = _make_fan_frame()
	_layout_fan(delta)
	if not _gesture(false).is_empty():
		# A throw or a fist needs fingers; from here on the fingered
		# pipeline poses this seat.
		make_fingered()
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
	if not bool(goal.get("plant", false)) and not bool(goal.get("wrist", false)):
		wrist = Vector3(goal["p"]) - world_basis * (Vector3(paw["center"]) * _unit)
	var pole: Vector3 = goal["pole"]
	if bool(goal.get("plant", false)):
		_seat_on_table(side, wrist, pole, world_basis)
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
	var xf := _bone_xf("LeftHand")
	var basis := xf.basis.orthonormalized()
	var paw: Dictionary = _paw["Left"]
	var n := (basis * Vector3(paw["palm"])).normalized()
	var along := (basis * Vector3(paw["len"])).normalized()
	var heel := 0.45
	var grip: Vector3 = Vector3(paw["center"]) + Vector3(paw["palm"]) * float(paw["surface"]) + Vector3(paw["len"]) * (float(paw["reach"]) * heel)
	var pivot: Vector3 = xf * grip + n * 0.006
	var up := Vector3.UP * 0.85 + along * 0.15
	up = up - n * up.dot(n)
	if up.length() < 0.01:
		up = along
	up = up.normalized()
	var x := up.cross(n).normalized()
	return Transform3D(Basis(x, up, n), pivot)


func _fp_pose(delta: float) -> void:
	var present_goal := 1.0 if thinking or inspecting else 0.0
	_present = lerpf(_present, present_goal, _rate(4.5, delta))
	var holding := not fan.is_empty()
	var grip: Transform3D = _hands.grip() if first_person else _hands.hold()
	var left := _fp_rest("Left")
	if holding:
		var target := _fp_fan_target()
		if not first_person:
			target.origin -= target.basis.z * _head_room(target, delta)
		left = _fp_hand_for(target, grip)
	_fp_xf["Left"] = Transform3D(_fp_xf["Left"]).interpolate_with(_fp_within_reach("Left", left), _rate(8.0, delta))
	_fp_mix["Left"] = _shape_toward(_fp_mix["Left"], "fan" if holding else "relax", _rate(9.0, delta))
	_hands.place("Left", _fp_xf["Left"])
	_hands.shape("Left", _fp_mix["Left"])
	_fan_frame = _hands.world_frame("Left", grip)
	_layout_fan(delta)
	var gesture := _gesture(first_person)
	if not gesture.is_empty():
		_follow_gesture(gesture, delta)
	elif _act.is_empty():
		var idle := _fp_idle_right()
		_fp_xf["Right"] = Transform3D(_fp_xf["Right"]).interpolate_with(idle["xf"], _rate(6.0, delta))
		_fp_mix["Right"] = _shape_toward(_fp_mix["Right"], idle["shape"], _rate(8.0, delta))
	else:
		var to := _fp_stage_goal()
		var u := _smooth(float(_act.get("u", 1.0)))
		var xf := Transform3D(_act["xf0"]).interpolate_with(to["xf"], u)
		xf.origin += Vector3(to.get("arc", Vector3.ZERO)) * sin(PI * u)
		_fp_xf["Right"] = xf
		_fp_mix["Right"] = _shape_toward(_act["mix0"], to["shape"], u)
	_fp_xf["Right"] = _fp_within_reach("Right", _fp_xf["Right"])
	_hands.place("Right", _fp_xf["Right"])
	_hands.shape("Right", _fp_mix["Right"])
	_held_blend = minf(_held_blend + delta * _held_rate, 1.0)
	_carry()
	for side in SIDES:
		_fp_arm(side, _fp_xf[side])


func _fp_fan_target() -> Transform3D:
	# Fan pivot in front of the camera, facing it: low on the left while the
	# others play, raised toward the middle while choosing a card. A seated
	# opponent holds it low before the chest, tipped back toward their eyes
	# (see SEAT_FAN_OUT).
	if not first_person:
		var frame := _frame()
		var f: Vector3 = frame["f"]
		var l: Vector3 = frame["l"]
		var spot: Vector3 = Vector3(frame["chest"]) + f * lerpf(SEAT_FAN_OUT.x, SEAT_FAN_OUT.y, _present) + l * lerpf(SEAT_FAN_SIDE.x, SEAT_FAN_SIDE.y, _present)
		spot.y = _felt_top + lerpf(SEAT_FAN_HIGH.x, SEAT_FAN_HIGH.y, _present)
		var to := _reading_point() - spot
		var tip := clampf(atan2(to.y, maxf(-to.dot(f), 0.01)), 0.0, SEAT_FAN_TIP)
		var n := -f * cos(tip) + Vector3.UP * sin(tip)
		var up := Vector3.UP - n * Vector3.UP.dot(n)
		up = up.normalized().rotated(n, lerpf(-0.22, -0.08, _present))
		return Transform3D(Basis(up.cross(n).normalized(), up, n), spot)
	var cam := camera.global_transform
	var spot: Vector3 = cam * FP_FAN_WAIT.lerp(FP_FAN_PLAY, _present)
	var n := (cam.origin - spot).normalized()
	var up := cam.basis.y - n * cam.basis.y.dot(n)
	up = up.normalized().rotated(n, lerpf(FP_ROLL_WAIT, FP_ROLL_PLAY, _present))
	return Transform3D(Basis(up.cross(n).normalized(), up, n), spot)


func _reading_point() -> Vector3:
	# Where a seated opponent's eyes are: eye_point() sits low on the muzzle
	# of the long-faced heads, which is right for where they look from but
	# would have them read their cards off their chin.
	var head := _bone_world("Head")
	var front := _bone_world("headfront")
	var top := _bone_world("head_end")
	if is_inf(front.x) or is_inf(top.x):
		return eye_point()
	return head + (top - head) * 0.42 + (front - head) * 0.5


func _head_room(target: Transform3D, delta: float) -> float:
	# How far to move the fan at `target` back along its normal, away from
	# the eyes, so that no card of it comes within HEAD_CLEAR of the head:
	# at once when one would, easing back in once there is room.
	var need := 0.0
	if not fan.is_empty():
		var half := FPHands.CARD_HALF_SIZE + Vector2.ONE * HEAD_CLEAR
		var reach := HEAD_REACH * HEAD_REACH
		var cards: Array = []
		for card in fan:
			cards.append(_fan_local.get(card, Transform3D.IDENTITY))
		var to_fan := target.affine_inverse()
		for part: Dictionary in _head_parts:
			var into_fan := to_fan * _skel.global_transform * _skel.get_bone_global_pose(int(part["bone"]))
			for p in PackedVector3Array(part["pts"]):
				var q := into_fan * p
				if q.length_squared() > reach:
					continue
				for local: Transform3D in cards:
					var r := local.basis.transposed() * (q - local.origin)
					if absf(r.x) <= half.x and absf(r.y) <= half.y and r.z > -HEAD_DEEP:
						need = maxf(need, HEAD_CLEAR + FPHands.CARD_HALF - r.z)
	need = minf(need, HEAD_PUSH_MAX)
	if need > _head_push:
		_head_push = need
	else:
		_head_push = maxf(need, _head_push - HEAD_EASE * delta)
	return _head_push


func _fp_hand_for(frame: Transform3D, local: Transform3D) -> Transform3D:
	# Hand placement that lays the hand-space frame `local` onto `frame`.
	var basis := frame.basis.orthonormalized() * local.basis.inverse()
	return Transform3D(basis, frame.origin - basis * (local.origin * float(_hands.size)))


func _fp_held_local() -> Transform3D:
	return _held_local_from.interpolate_with(_held_local_to, _smooth(_held_blend))


func _fp_hold(to: Transform3D, seconds: float) -> void:
	# Ease the held card from wherever it sits in the hand into `to`.
	_held_local_from = _fp_held_local()
	_held_local_to = to
	_held_blend = 0.0
	_held_rate = 1.0 / maxf(seconds, 0.01)


func _fp_rest(side: String) -> Transform3D:
	# Relaxed on the felt beside the fan, palm down, fingers toward the middle.
	var frame := _frame()
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	var sign := 1.0 if side == "Right" else -1.0
	var p: Vector3 = frame["chest"] + f * 0.36 - l * (0.2 * sign)
	var along := f.rotated(Vector3.UP, 0.42 * sign)
	p.y = _felt_top + _hands.ground_lift(side)
	return Transform3D(Basis(along.cross(Vector3.UP).normalized(), along, Vector3.UP), p)


func _fp_idle_right() -> Dictionary:
	var rest := _fp_rest("Right")
	if not thinking or fan.is_empty():
		return {"xf": rest, "shape": "relax"}
	# Choosing: off the cloth and drawn in toward the fan.
	var toward := _flat(_fan_frame.origin - rest.origin).normalized()
	return {"xf": Transform3D(rest.basis, rest.origin + toward * 0.05 + Vector3.UP * 0.02), "shape": "ready"}


func _fp_act_events() -> void:
	var card: Node3D = _act["card"]
	var t: float = _act["t"]
	var throwing := str(_act["kind"]) == "throw"
	var keys: Array = THROW_KEYS.duplicate() if throwing else TAKE_KEYS.duplicate()
	if not throwing and not _queue.is_empty():
		keys[2] = float(keys[1]) + 0.12
	if throwing and int(_act["stage"]) < 1 and not fan.has(card):
		_finish(card)
		_act = {}
		return
	var stage := mini(_stage_of(t, keys), int(_act["stage"]) + 1)
	if stage >= keys.size():
		_act = {}
		return
	if stage != int(_act["stage"]):
		var entering := int(_act["stage"])
		_act["stage"] = stage
		_act["xf0"] = _fp_xf["Right"]
		_act["mix0"] = _fp_mix["Right"].duplicate()
		if stage >= 1 and entering < 1:
			# The card stays where the fingers closed on it and settles
			# into the grip while it is carried.
			if throwing:
				remove_from_fan(card)
			_held = card
			_lift_rest(card)
			_held_local_from = _hands.local_frame("Right", card.global_transform)
			_held_local_to = _held_local_from
			_held_blend = 1.0
			if not throwing:
				_fp_hold(_hands.pluck(), float(keys[1]) - float(keys[0]))
		if throwing and stage >= 2 and entering < 2:
			_fp_hold(_hands.pluck(), float(keys[2]) - float(keys[1]))
		if throwing and stage >= 3 and entering < 3:
			_release()
		if not throwing and stage >= 2 and entering < 2:
			_drop(card, -1 if int(_act.get("index", -1)) == -2 else int(_act.get("index", -1)))
	var start := 0.0 if stage == 0 else float(keys[stage - 1])
	_act["u"] = clampf((t - start) / maxf(float(keys[stage]) - start, 0.01), 0.0, 1.0)


func _fp_stage_goal() -> Dictionary:
	# Both ways the right hand holds a card by its top edge, index hooked
	# over it and thumb on the face, so the wrist stays below and in front
	# of the card instead of turning the forearm up past the camera.
	var card: Node3D = _act["card"]
	var stage := int(_act["stage"])
	var toward_cam := (_viewer() - _fan_frame.origin).normalized()
	if str(_act["kind"]) == "throw":
		match stage:
			0:
				return {"xf": _fp_pluck_hand(card.global_transform), "shape": "pluck", "arc": toward_cam * 0.05 - _fan_frame.basis.y * 0.03}
			1:
				var from := Transform3D(_act["xf0"])
				return {"xf": Transform3D(from.basis, from.origin + _fan_frame.basis.y * 0.08 + toward_cam * 0.02), "shape": "pluck"}
			2:
				return {"xf": _fp_hand_for(_fp_toss_card(), _hands.pluck()), "shape": "pluck", "arc": Vector3.UP * 0.04}
			3:
				var toss := _fp_hand_for(_fp_toss_card(), _hands.pluck())
				var ahead := _flat(Vector3(_act.get("aim", _center)) - toss.origin)
				return {"xf": Transform3D(toss.basis, toss.origin + ahead * 0.05 + Vector3.UP * 0.015), "shape": "open"}
		var idle := _fp_idle_right()
		return {"xf": idle["xf"], "shape": idle["shape"]}
	match stage:
		0:
			return {"xf": _fp_hand_for(_fp_lift_card(card), _hands.pluck()), "shape": "pluck", "arc": Vector3.UP * 0.05}
		1:
			var slot := _fan_frame * Transform3D(Basis.IDENTITY, Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y + 0.06, 0.006))
			return {"xf": _fp_pluck_hand(slot), "shape": "pluck", "arc": toward_cam * 0.04 + Vector3.UP * 0.03}
	var rest := _fp_idle_right()
	return {"xf": rest["xf"], "shape": rest["shape"]}


func _viewer() -> Vector3:
	# Whose eyes the fan is held for.
	if first_person and camera != null:
		return camera.global_position
	return eye_point()


func _fingered() -> bool:
	return _hands != null and (first_person or fingered)


func make_fingered() -> void:
	# Fingered hands for a seated opponent, furred like the paws they replace.
	if first_person or fingered:
		return
	fingered = true
	if _hands == null:
		_hands = FPHands.new()
		_hands.name = "Hands"
		add_child(_hands)
		_hands.setup(_preset, scale.x, true, 8, true, _coat_tone())
	_hands.visible = true
	(_hands.get_node("LeftHand") as Node3D).visible = true
	_scale_hand("LeftHand", 0.001)
	_scale_hand("RightHand", 0.001)
	for side in SIDES:
		_fp_xf[side] = _fp_rest(side)
		_fp_mix[side] = {"relax": 1.0}


func _fp_pluck_hand(card_xf: Transform3D) -> Transform3D:
	# Right hand on a standing card's top edge, turned about the hooked index:
	# the wrist moves to the lower right and the outer fingers lift off the
	# edge rather than into the card.
	var hook := Transform3D(Basis.IDENTITY, Vector3(-FPHands.PLUCK_AT, CARD.y * 0.5, 0.0))
	var turned := card_xf * hook * Transform3D(Basis(Vector3.BACK, FP_PLUCK_TURN), Vector3.ZERO) * hook.affine_inverse()
	return _fp_hand_for(turned, _hands.pluck())


func _fp_toss_card() -> Transform3D:
	# Where the hand lets the card go: flat, face up, top edge leading, a
	# short way out over the cloth toward where it will land.
	var aim: Vector3 = _act.get("aim", _center)
	var start := _fp_rest("Right").origin
	var ahead := _flat(aim - start)
	var at := start + ahead * minf(0.16, Vector2(aim.x - start.x, aim.z - start.z).length() * 0.5)
	at.y = _felt_top + 0.07
	if not first_person:
		return Transform3D(Basis(ahead.cross(Vector3.DOWN).normalized(), ahead, Vector3.DOWN), at)
	return Transform3D(Basis(ahead.cross(Vector3.UP).normalized(), ahead, Vector3.UP), at)


func _fp_lift_card(card: Node3D) -> Transform3D:
	# A card lying on the felt, as the hand closes on its far edge: face up,
	# a little above the cloth so the hooked index stays out of it.
	var top := _flat(card.global_transform.basis.y)
	var at := card.global_position
	at.y = _felt_top + 0.015
	return Transform3D(Basis(top.cross(Vector3.UP).normalized(), top, Vector3.UP), at)


func _fp_within_reach(side: String, hand: Transform3D) -> Transform3D:
	# Pull the hand in if the sleeve could not reach its forearm.
	var shoulder := _bone_world(side + "Arm")
	var wrist := hand.origin - hand.basis.y.normalized() * _sleeve()
	var limit := (float(_upper.get(side, 0.25)) + float(_fore.get(side, 0.25))) * 0.98
	var span := wrist - shoulder
	if span.length() <= limit:
		return hand
	return Transform3D(hand.basis, hand.origin - span.normalized() * (span.length() - limit))


func _fp_arm(side: String, hand: Transform3D) -> void:
	# Sleeve over the hand's forearm. The elbow bends toward the line that
	# forearm points along, pulled toward where an elbow hangs at rest, below
	# the shoulder and a little out and forward; aimed along the forearm alone
	# it swings up past the camera whenever the hand works close to the chest.
	var back := -hand.basis.y.normalized()
	var wrist := hand.origin + back * _sleeve()
	var shoulder := _bone_world(side + "Arm")
	var frame := _frame()
	var outward: Vector3 = -frame["l"] if side == "Right" else frame["l"]
	var hang := (Vector3.DOWN * 0.24 + Vector3(frame["f"]) * 0.08 + outward * 0.06).normalized()
	var along := (wrist + back * float(_fore.get(side, 0.25)) - shoulder).normalized()
	_reach(side, wrist, along + hang * FP_ELBOW_HANG)


func _gesture(fp: bool) -> Dictionary:
	# Right hand while throwing or punching: where it goes and its shape;
	# empty when the hand is free for cards.
	if not _exit.is_empty():
		return _punch(fp)
	if _duel.is_empty() or (fp and camera == null):
		return {}
	var stage := int(_duel["stage"])
	var age := float(_duel["age"])
	var throw := int(_duel["throw"])
	var anchor := _duel_anchor(fp)
	var p := anchor.origin
	var shape := "rock"
	var rate := 11.0
	if stage == Match.DUEL_CHANT:
		# Down on every word of the chant, and once more for the throw.
		p += anchor.basis.y * (0.075 * sin(PI * fmod(age, Match.CHANT_BEAT) / Match.CHANT_BEAT))
		rate = 30.0
	elif (stage == Match.DUEL_SHOW or stage == Match.DUEL_AFTER) and throw >= 0 and throw < THROW_SHAPES.size():
		shape = THROW_SHAPES[throw]
		p += -anchor.basis.z * (0.05 * _smooth(clampf(age / 0.16, 0.0, 1.0))) + anchor.basis.y * 0.025
		rate = 24.0
	return {"xf": Transform3D(anchor.basis, p), "shape": shape, "rate": rate}


func _duel_anchor(fp: bool) -> Transform3D:
	# Bottom of the pump, fingers up and the palm toward whoever has to read
	# the throw: the opponent, turned partly to the seated player's camera.
	if fp:
		var cam := camera.global_transform
		var up := (cam.basis.y * 0.92 - cam.basis.z * 0.3).normalized()
		var back := (cam.basis.z - up * cam.basis.z.dot(up)).normalized()
		return Transform3D(Basis(up.cross(back).normalized(), up, back), cam * Vector3(0.15, -0.2, -0.46))
	var frame := _frame()
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	# Out over the table and up beside the head: seated players lean in, so
	# lower down the hand would sit under the chin, against the coat.
	var p := _bone_world("RightArm") + f * 0.36 - l * 0.06 + Vector3.UP * 0.08
	p.y = maxf(p.y, _felt_top + 0.12)
	var face := _flat(Vector3(_duel.get("toward", p + f)) - p)
	if camera != null:
		face = (face + _flat(camera.global_position - p)).normalized() if face.dot(_flat(camera.global_position - p)) > -0.9 else face
	var up := (Vector3.UP * 0.88 + f * 0.3).normalized()
	var back := -(face - up * face.dot(up)).normalized()
	return Transform3D(Basis(up.cross(back).normalized(), up, back), p)


func _punch(fp: bool) -> Dictionary:
	# Fist up past the shoulder, then down on its little-finger edge, thumb
	# up and knuckles to the middle, with a small rebound off the felt.
	var t := float(_exit["t"])
	var frame := _frame()
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	var hammer := Basis(f.cross(-l).normalized(), f, -l)
	var top: Vector3
	var hit: Vector3
	if fp:
		# Kept to the right of the view so the sleeve stays low in frame.
		top = camera.global_transform * Vector3(0.24, -0.05, -0.5)
		hit = _fp_rest("Right").origin + f * 0.06
	else:
		top = _bone_world("RightArm") + f * 0.05 - l * 0.16 + Vector3.UP * 0.36
		hit = Vector3(frame["chest"]) + f * 0.44 - l * 0.12
	hit.y = _felt_top + FIST_DROP * scale.x
	var p := hit
	var basis := hammer
	if t < FIST_TOP:
		var u := _smooth(t / FIST_TOP)
		var from = _exit.get("from")
		var start: Transform3D = from if from is Transform3D else Transform3D(hammer, top)
		p = start.origin.lerp(top, u)
		basis = start.basis.orthonormalized().slerp(hammer, u)
	elif t < FIST_HIT:
		var u := (t - FIST_TOP) / (FIST_HIT - FIST_TOP)
		p = top.lerp(hit, u * u)
	else:
		var after := t - FIST_HIT
		p = hit + Vector3.UP * (0.012 * sin(PI * clampf(after / 0.2, 0.0, 1.0)) + 0.05 * _smooth(clampf((after - 0.5) / 0.3, 0.0, 1.0)))
	if not fp:
		look_point = hit
		_lean_goal = 0.35
	return {"xf": Transform3D(basis, p), "shape": "rock", "rate": -1.0}


func _follow_gesture(gesture: Dictionary, delta: float) -> void:
	var goal: Transform3D = gesture["xf"]
	var rate := float(gesture.get("rate", 11.0))
	if rate < 0.0:
		_fp_xf["Right"] = goal
	else:
		_fp_xf["Right"] = Transform3D(_fp_xf["Right"]).interpolate_with(goal, _rate(rate, delta))
	_fp_mix["Right"] = _shape_toward(_fp_mix["Right"], gesture["shape"], _rate(18.0, delta))


func _coat_tone() -> Color:
	# Middle colour of the fur on the character's own head and neck, in its
	# texture: the fur that reads on screen, which the borrowed hands then
	# match. Transparent when it cannot be read.
	if _coats.has(_preset):
		return _coats[_preset]
	var want := {}
	for bone in ["Head", "neck", "Neck"]:
		var idx := _skel.find_bone(bone)
		if idx >= 0:
			want[idx] = true
	var samples: Array = []
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null:
			continue
		var binds := {}
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			binds[b] = bone if bone >= 0 else _skel.find_bone(mi.skin.get_bind_name(b))
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var image := mat.albedo_texture.get_image()
			if image == null or image.is_empty():
				continue
			if image.is_compressed():
				image.decompress()
			var arrays := mi.mesh.surface_get_arrays(surface)
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if uvs == null or bones == null or weights == null or uvs.is_empty():
				continue
			var per: int = bones.size() / uvs.size()
			var size := Vector2(image.get_width(), image.get_height())
			for v in uvs.size():
				var best := -1
				var best_w := 0.0
				for k in per:
					if weights[v * per + k] > best_w:
						best_w = weights[v * per + k]
						best = int(bones[v * per + k])
				if best < 0 or not want.has(int(binds.get(best, best))):
					continue
				var uv: Vector2 = uvs[v]
				var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * size.x), 0, int(size.x) - 1), clampi(int(fposmod(uv.y, 1.0) * size.y), 0, int(size.y) - 1))
				samples.append(image.get_pixelv(px) * mat.albedo_color)
	var tone := Color(0.0, 0.0, 0.0, 0.0)
	if not samples.is_empty():
		samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
		tone = samples[samples.size() / 2]
		tone.a = 1.0
	_coats[_preset] = tone
	return tone


func _sleeve() -> float:
	# Wrist showing between the coat sleeve and the fingered hand: the
	# seated player's own reach out of the sleeves; an opponent's hands come
	# almost straight out of theirs.
	return (FP_SLEEVE if first_person else FPHands.SEATED_SLEEVE) * float(_hands.size)


func _pose_walk(delta: float) -> void:
	# Out of the chair into the rest pose, then a walk along the exit path:
	# legs swing from the hip with the knee folding as each comes through,
	# arms hang and swing against them, and the lower foot stays on the floor.
	var t := float(_exit["t"]) - RISE_AT
	var rise := _smooth(clampf(t / RISE_TIME, 0.0, 1.0))
	var stride := clampf((t - RISE_TIME * 0.7) / 0.5, 0.0, 1.0)
	for bone_name in _body:
		var idx := _skel.find_bone(str(bone_name))
		if idx < 0:
			continue
		var seated_q: Quaternion = _body[bone_name]
		var stand_q: Quaternion = _stand.get(bone_name, seated_q)
		_skel.set_bone_pose_rotation(idx, seated_q.slerp(stand_q, rise))
	_skel.force_update_all_bone_transforms()
	var phase := float(_exit["step"])
	for k in 2:
		var cycle := phase + PI * float(k)
		_bend(SIDES[k] + "UpLeg", -0.42 * sin(cycle) * stride)
		_bend(SIDES[k] + "Leg", 0.85 * pow(maxf(0.0, cos(cycle)), 1.3) * stride)
	var frame := _frame()
	var f: Vector3 = frame["f"]
	var l: Vector3 = frame["l"]
	for k in 2:
		var side: String = SIDES[k]
		var sign := 1.0 if side == "Left" else -1.0
		var length := float(_upper.get(side, 0.25)) + float(_fore.get(side, 0.25))
		var swing := 0.16 * sin(phase + PI * float(1 - k)) * stride
		var shoulder := _bone_world(side + "Arm")
		var wrist := shoulder + Vector3.DOWN * (length * 0.92) + f * swing + l * (0.06 * sign)
		_reach(side, wrist, (-f + l * (0.3 * sign)).normalized())
	_skel.force_update_all_bone_transforms()
	if _fingered():
		# Fingered hands hang off the sleeves, palms in, as they walk.
		for k in 2:
			var side: String = SIDES[k]
			var sign := 1.0 if side == "Left" else -1.0
			var joint := _bone_world(side + "Hand")
			var along := (joint - _bone_world(side + "ForeArm")).normalized()
			var out := l * sign
			var back := (out - along * out.dot(along)).normalized()
			_hands.place(side, Transform3D(Basis(along.cross(back).normalized(), along, back), joint + along * _sleeve()))
			_hands.shape(side, {"relax": 1.0})
	var lowest := INF
	for bone_name in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
		var point := _bone_world(bone_name)
		if not is_inf(point.x):
			lowest = minf(lowest, point.y)
	if lowest < 100.0:
		position.y -= lowest
	_head = _bone_world("Head")
	var path: Array = _exit["path"]
	var leg := int(_exit["leg"])
	if leg >= path.size():
		vanish()
		departed.emit()
		return
	if stride <= 0.0:
		return
	var goal: Vector3 = path[leg]
	var to := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	var step := WALK_SPEED * stride * delta
	if to.length() <= maxf(step, 0.04):
		_exit["leg"] = leg + 1
	if to.length() > 0.001:
		position += to.normalized() * minf(step, to.length())
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), _rate(5.0, delta))
	_exit["step"] = phase + delta * STEP_RATE * stride


func _shape_toward(mix: Dictionary, key: String, w: float) -> Dictionary:
	var out := {}
	for name in mix:
		var keep := float(mix[name]) * (1.0 - w)
		if keep > 0.002:
			out[name] = keep
	out[key] = float(out.get(key, 0.0)) + w
	return out


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
	var shaded := mesh.get_active_material(0) as ShaderMaterial
	if shaded != null:
		var warm := shaded.duplicate() as ShaderMaterial
		warm.set_shader_parameter("glow", 0.25)
		mesh.set_surface_override_material(0, warm)
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
	var step := 0.07
	var cap := 0.78
	var raised := 0.018
	if fingered:
		step = 0.1
		cap = 0.62
	if first_person:
		# Opened wider while choosing so every corner index clears the card
		# in front of it; the chosen card stands well proud of the rest.
		step = lerpf(FP_STEP_WAIT, FP_STEP_PLAY, _present)
		cap = lerpf(FP_SPREAD, FP_SPREAD_PLAY, _present)
		raised = 0.032
	var spread := minf(step * float(count - 1), cap)
	# The fan turns about a point this far below the thumb, so the tops part
	# much more than the bottoms; the front card stays where the thumb holds it.
	var drop := lerpf(FP_DROP_WAIT, FP_DROP_PLAY, _present) if first_person else (0.02 if fingered else 0.0)
	var front := Basis(Vector3.BACK, -spread * 0.5) * Vector3(0.0, drop, 0.0)
	var k := _rate(13.0, delta)
	for i in count:
		var card: Node3D = fan[i]
		var u := 0.5 if count == 1 else float(i) / float(count - 1)
		var lift := raised if card == selected else 0.0
		var goal: Transform3D
		if _fingered():
			# One flat stack, front card last, so cards never cut through
			# each other.
			if first_person:
				_warm_card(card, card == selected)
			var rot := Basis(Vector3.BACK, spread * (0.5 - u))
			var pivot := Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y + lift + drop, 0.0)
			goal = Transform3D(rot, rot * pivot - front + Vector3(0.0, 0.0, -0.0009 * float(count - 1 - i)))
		else:
			var rot := Basis(Vector3.BACK, spread * (0.5 - u))
			goal = Transform3D(rot, rot * Vector3(0.0, CARD.y * 0.32 + lift, 0.0) + Vector3(0.0, 0.0, 0.0016 * float(i)))
		var cur: Transform3D = _fan_local.get(card, goal)
		cur = cur.interpolate_with(goal, k)
		if _fingered():
			cur.origin.z = goal.origin.z
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
	if _fingered():
		_held.global_transform = _hands.world_frame("Right", _fp_held_local())
	else:
		var local := _held_from.interpolate_with(_held_to, _held_mix)
		_held.global_transform = _grip_frame() * local
	for under in _held_rest:
		if is_instance_valid(under):
			(under as Node3D).global_transform = _held.global_transform * Transform3D(_held_rest[under])


func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	return {
		"p": Vector3(a["p"]).lerp(Vector3(b["p"]), w),
		"len": _nlerp(a["len"], b["len"], w),
		"palm": _nlerp(a["palm"], b["palm"], w),
		"pole": _nlerp(a["pole"], b["pole"], w),
		"contact": bool(b.get("contact", false)),
		"plant": bool(b.get("plant", false)),
		"wrist": bool(b.get("wrist", false)),
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


func _study_head() -> void:
	# The head and neck as the mesh has them, snout, jaw, horns and ears
	# included: one skin point per HEAD_CELL cube, kept in the space of the
	# bone it moves with (the head's tip bones move with the head).
	var group := {}
	for names in [["Head", "headfront", "head_end"], ["neck"]]:
		var owner := _skel.find_bone(names[0])
		if owner < 0:
			continue
		for bone_name in names:
			var idx := _skel.find_bone(bone_name)
			if idx >= 0:
				group[idx] = owner
	if group.is_empty():
		return
	var cell := HEAD_CELL / maxf(_unit, 0.00001)
	var cells := {}
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var binds := {}
		for owner in group.values():
			binds[owner] = _skel.get_bone_global_rest(owner).affine_inverse()
		var bone_of := {}
		if mi.skin != null:
			for b in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(b)
				if bone < 0:
					bone = _skel.find_bone(mi.skin.get_bind_name(b))
				bone_of[b] = bone
				if binds.has(bone):
					binds[bone] = mi.skin.get_bind_pose(b)
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
				var bone_idx := int(bone_of.get(best, best))
				if not group.has(bone_idx):
					continue
				var owner: int = group[bone_idx]
				var p: Vector3 = Transform3D(binds[owner]) * verts[v]
				var key := Vector4i(owner, floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
				if not cells.has(key):
					cells[key] = p
	_head_parts.clear()
	var owners := {}
	for owner in group.values():
		owners[owner] = true
	for owner in owners:
		var pts := PackedVector3Array()
		for key: Vector4i in cells:
			if key.x == owner:
				pts.append(cells[key])
		_head_parts.append({"bone": owner, "pts": pts})


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
