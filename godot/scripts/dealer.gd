extends Node3D

# The croupier: the rigged crow standing at the table edge with a palette,
# the long paddle croupiers move cards with. Every card that moves on the
# felt after the players throw goes through here: turning the played cards
# over, sliding drawn cards to whoever draws them and the rest onto the
# pile, one card at a time; at a new hand the left wing deals.
#
# Actions run one after another. Each moves the paddle blade (or, dealing,
# the left hand) along eased legs and carries its card with it; `done` is
# called when the card has arrived.

signal sound(kind: String)

const HEIGHT_FIT := 0.94
# Palette: handle length, blade size (width across the handle, thickness,
# depth along it), how high a lifted blade rides over the cloth.
const PADDLE := 0.86
const BLADE := Vector3(0.15, 0.005, 0.06)
const HOVER := 0.05
# Where along the wing-hand the paddle is held, from the wrist.
const GRIP_AT := 0.55
const CARD := Vector2(0.096, 0.134)
# A card pushed onto the pile is flicked up over this last stretch of its
# way instead of being shoved into the pile's side. Seconds for the blade to
# come down behind a card and to lift off it again.
const HOP_SPAN := 0.22
const REACH := 0.2
const LIFT_OFF := 0.08

var camera: Camera3D
var look_point := Vector3.ZERO
var hurry := 1.0

var _skel: Skeleton3D
var _rest: Dictionary = {}
var _lateral: Dictionary = {}
var _upright: Dictionary = {}
var _upper: Dictionary = {}
var _fore: Dictionary = {}
var _hand_len := 0.25
var _center := Vector3.ZERO
var _felt := 0.713
var _home := Transform3D.IDENTITY
var _paddle: Node3D
var _blade := Vector3.ZERO
var _blade_goal := Vector3.ZERO
var _left := Vector3.ZERO
var _left_goal := Vector3.ZERO
var _lean := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _time := 0.0
var _queue: Array = []
var _act: Dictionary = {}


func setup(table: Dictionary) -> void:
	_center = table.get("center", Vector3.ZERO)
	_felt = float(table.get("felt_top", 0.713))
	scale = Vector3.ONE * HEIGHT_FIT
	_skel = find_child("Skeleton3D", true, false) as Skeleton3D
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		player.active = false
	for i in _skel.get_bone_count():
		_rest[i] = _skel.get_bone_pose_rotation(i)
	_skel.force_update_all_bone_transforms()
	for bone in ["Spine02", "Spine01", "Spine", "neck", "Head"]:
		var idx := _skel.find_bone(bone)
		_lateral[bone] = _local_axis(idx, global_transform.basis.x)
		_upright[bone] = _local_axis(idx, global_transform.basis.y)
	for side in ["Left", "Right"]:
		_upper[side] = _bone(side + "Arm").distance_to(_bone(side + "ForeArm"))
		_fore[side] = _bone(side + "ForeArm").distance_to(_bone(side + "Hand"))
	# The wing-hand has no tip bone; it runs about 0.7 of the forearm.
	_hand_len = float(_fore["Right"]) * 0.7
	_home = global_transform
	_matte()
	_paddle = _make_paddle()
	add_child(_paddle)
	_blade = _rest_blade()
	_blade_goal = _blade
	_left = _rest_left()
	_left_goal = _left
	look_point = _center + Vector3.UP * _felt


func busy() -> bool:
	return not _act.is_empty() or not _queue.is_empty()


func tray() -> Vector3:
	# Felt in front of the croupier where the deck sits and the pile grows.
	var f := _forward()
	return Vector3(global_position.x, _felt, global_position.z) + f * 0.5


# Cards are Node3D; spots are Transform3D on the felt.
func slide(card: Node3D, path: Array, spot: Transform3D, done := Callable(), hop := 0.0) -> void:
	# Pushes the card along the felt through the points in `path` to `spot`;
	# with `hop` it is flicked that high onto the pile at the end.
	var length := 0.0
	var last := card.global_position
	for point in path:
		length += _flat(Vector3(point) - last).length()
		last = point
	_queue.append({"kind": "slide", "cards": [card], "spots": [spot], "path": path, "hop": hop, "done": done, "time": REACH + 0.14 + length * 0.55 + LIFT_OFF})


func flip(card: Node3D, spot: Transform3D, done := Callable()) -> void:
	# Turns the card over where it lies. A card whose top edge has to end
	# up the other way round goes over end to end, otherwise side to side.
	_queue.append({"kind": "flip", "cards": [card], "spots": [spot], "done": done, "time": 0.5})


func deal(card: Node3D, toward: Vector3, release: Callable) -> void:
	_queue.append({"kind": "deal", "cards": [card], "toward": toward, "done": release, "time": 0.15})


func finish_all() -> void:
	# Lands every queued card where it was going; used when a hand is cleared.
	if not _act.is_empty():
		_land(_act)
	for act in _queue:
		_land(act)
	_queue.clear()
	_act = {}


func _land(act: Dictionary) -> void:
	# Once only: by the time the blade has lifted off, whoever the card went
	# to may already have it in hand.
	if act.get("finished", false):
		return
	act["finished"] = true
	var done: Callable = act["done"]
	if str(act["kind"]) == "deal":
		if done.is_valid() and not act.get("released", false):
			done.call()
		return
	var cards: Array = act["cards"]
	var spots: Array = act["spots"]
	for i in cards.size():
		if is_instance_valid(cards[i]):
			cards[i].global_transform = spots[i]
	if done.is_valid():
		done.call()


func _process(delta: float) -> void:
	if _skel == null:
		return
	_time += delta
	_advance(delta * hurry)
	_pose(delta)


func _advance(delta: float) -> void:
	if _act.is_empty() and not _queue.is_empty():
		_act = _queue.pop_front()
		_act["t"] = 0.0
		_start(_act)
	if _act.is_empty():
		_blade_goal = _rest_blade()
		_left_goal = _rest_left()
		_blade = _blade.lerp(_blade_goal, _rate(4.0, delta))
		_left = _left.lerp(_left_goal, _rate(5.0, delta))
		return
	_act["t"] = float(_act["t"]) + delta
	match str(_act["kind"]):
		"slide":
			_run_slide(_act)
		"flip":
			_run_flip(_act)
		"deal":
			_run_deal(_act)
	_left = _left.lerp(_left_goal, _rate(9.0, delta))


func _start(act: Dictionary) -> void:
	act["blade0"] = _blade
	act["left0"] = _left
	var cards: Array = act["cards"]
	var starts: Array = []
	for card in cards:
		starts.append(card.global_transform if is_instance_valid(card) else Transform3D.IDENTITY)
	act["starts"] = starts
	if str(act["kind"]) == "slide":
		# The route on the felt from where the card lies now, with the
		# distance along it to each corner.
		var line: Array = [Transform3D(starts[0]).origin]
		for point in act["path"]:
			line.append(point)
		var marks: Array = [0.0]
		for i in range(1, line.size()):
			marks.append(float(marks[i - 1]) + _flat(Vector3(line[i]) - Vector3(line[i - 1])).length())
		act["line"] = line
		act["marks"] = marks


func _run_slide(act: Dictionary) -> void:
	# Blade over to the card's trailing edge and down, the card rides ahead
	# of it along its route with the blade turning at each corner, then the
	# blade lifts off.
	var card: Node3D = act["cards"][0]
	var start: Transform3D = act["starts"][0]
	var spot: Transform3D = act["spots"][0]
	var marks: Array = act["marks"]
	var total: float = marks[marks.size() - 1]
	var time: float = act["time"]
	var t := float(act["t"]) / time
	var reach := REACH / time
	var push := 1.0 - LIFT_OFF / time
	if t < reach:
		var u := _ease(t / reach)
		var behind := _behind(act, start, 0.0)
		var from := Vector3(act["blade0"])
		_blade = from.lerp(behind, u)
		# Over at hovering height, down onto the cloth only at the end.
		_blade.y = lerpf(from.y, _felt + HOVER, minf(u * 1.6, 1.0)) - (HOVER - 0.004) * _ease((u - 0.7) / 0.3)
	elif t < push:
		var u := _ease((t - reach) / (push - reach))
		var along := u * total
		var at := _along(act, along)
		var basis := Basis(start.basis.get_rotation_quaternion().slerp(spot.basis.get_rotation_quaternion(), u))
		var y := lerpf(start.origin.y, spot.origin.y, u)
		var hop := float(act["hop"])
		if hop > 0.0:
			var s := clampf((along - (total - HOP_SPAN)) / HOP_SPAN, 0.0, 1.0)
			y = lerpf(start.origin.y, spot.origin.y, s) + hop * sin(PI * s)
		var xf := Transform3D(basis, Vector3(at.x, y, at.z))
		if u >= 1.0:
			xf = spot
		if is_instance_valid(card):
			card.global_transform = xf
		_blade = _behind(act, xf, along)
		if not act.get("noise", false):
			act["noise"] = true
			sound.emit("deal")
	else:
		var u := _ease((t - push) / (1.0 - push))
		_blade = _behind(act, spot, total) + Vector3.UP * (HOVER - 0.004) * u
		_land(act)
	look_point = _blade
	_lean_for(_blade)
	if t >= 1.0:
		_land(act)
		_act = {}


func _along(act: Dictionary, distance: float) -> Vector3:
	# The point that far along the act's route.
	var line: Array = act["line"]
	var marks: Array = act["marks"]
	for i in range(1, line.size()):
		var a := float(marks[i - 1])
		var b := float(marks[i])
		if distance <= b or i == line.size() - 1:
			var u := clampf((distance - a) / maxf(b - a, 0.0001), 0.0, 1.0)
			return Vector3(line[i - 1]).lerp(Vector3(line[i]), u)
	return Vector3(line[line.size() - 1])


func _behind(act: Dictionary, xf: Transform3D, distance: float) -> Vector3:
	# Blade on the cloth just off the card's trailing edge, square to the
	# way it is going there; corners are rounded off over a few centimetres.
	var total: float = act["marks"][act["marks"].size() - 1]
	var way := _flat(_along(act, minf(distance + 0.04, total)) - _along(act, maxf(distance - 0.04, 0.0)))
	if way.length() < 0.001:
		way = _flat(_along(act, total) - _along(act, 0.0))
	var dir := way.normalized() if way.length() > 0.001 else -_forward()
	var reach := absf(dir.dot(xf.basis.x.normalized())) * CARD.x * 0.5 + absf(dir.dot(xf.basis.y.normalized())) * CARD.y * 0.5
	var at := xf.origin - dir * (reach + 0.025)
	return Vector3(at.x, _felt + 0.004, at.z)


func _run_flip(act: Dictionary) -> void:
	# Blade edge under the card's edge nearer the croupier, a flick, and the
	# card turns over in a short hop to land face up where it lay.
	var card: Node3D = act["cards"][0]
	var start: Transform3D = act["starts"][0]
	var spot: Transform3D = act["spots"][0]
	var time: float = act["time"]
	var t := float(act["t"]) / time
	var end_over := spot.basis.y.dot(start.basis.y) < 0.0
	var axis := (start.basis.x if end_over else start.basis.y).normalized()
	var across := _flat(start.basis.y if end_over else start.basis.x).normalized()
	var half := (CARD.y if end_over else CARD.x) * 0.5
	if across.dot(_flat(global_position - start.origin)) < 0.0:
		across = -across
	var near := start.origin + across * (half + 0.03)
	near.y = _felt
	# Turn the way that lifts the blade's edge first.
	var turn := PI if axis.cross(across).y > 0.0 else -PI
	if t < 0.4:
		var u := _ease(t / 0.4)
		_blade = Vector3(act["blade0"]).lerp(near + Vector3.UP * 0.004, u)
		_blade.y = lerpf(float(Vector3(act["blade0"]).y), _felt + 0.004, u)
	else:
		var u := clampf((t - 0.4) / 0.6, 0.0, 1.0)
		_blade = near + Vector3.UP * (0.004 + 0.07 * sin(PI * minf(u * 1.6, 1.0)))
		if is_instance_valid(card):
			var e := _ease(u)
			var turned := Basis(axis, turn * e) * start.basis
			var hop := Vector3.UP * (0.07 * 4.0 * e * (1.0 - e))
			var basis := turned.orthonormalized()
			if e >= 1.0:
				basis = spot.basis
			card.global_transform = Transform3D(basis, start.origin.lerp(spot.origin, e) + hop)
			if not act.get("noise", false) and u > 0.05:
				act["noise"] = true
				sound.emit("flip")
	look_point = start.origin
	_lean_for(start.origin)
	if t >= 1.0:
		_land(act)
		_act = {}


func _run_deal(act: Dictionary) -> void:
	# Left wing over the deck, then a flick toward the seat; the card leaves
	# at the flick and the table flies it to the player.
	var time: float = act["time"]
	var t := float(act["t"]) / time
	var deck := tray() + Vector3.UP * 0.06
	var toward: Vector3 = act["toward"]
	var aim := Vector3(toward.x - deck.x, 0.0, toward.z - deck.z).normalized()
	if t < 0.45:
		_left_goal = deck
	else:
		_left_goal = deck + aim * 0.16 + Vector3.UP * 0.03
		if not act.get("released", false):
			act["released"] = true
			var done: Callable = act["done"]
			if done.is_valid():
				done.call()
	look_point = toward
	_lean_for(deck)
	if t >= 1.0:
		_act = {}


func _pose(delta: float) -> void:
	for i in _rest:
		_skel.set_bone_pose_rotation(i, _rest[i])
	_skel.force_update_all_bone_transforms()
	var breath := sin(_time * 1.3) * 0.02
	var goal_lean := float(_act.get("lean", 0.0)) if not _act.is_empty() else 0.04
	_lean = lerpf(_lean, goal_lean, _rate(3.5, delta))
	_turn("Spine02", _lean * 0.45 + breath * 0.3, 0.0)
	_turn("Spine01", _lean * 0.35 + breath * 0.5, 0.0)
	_turn("Spine", _lean * 0.25 + breath, 0.0)
	var aim := _look_angles(look_point)
	_head_yaw = lerpf(_head_yaw, aim.x, _rate(5.0, delta))
	_head_pitch = lerpf(_head_pitch, aim.y, _rate(5.0, delta))
	_turn("neck", -_head_pitch * 0.35, _head_yaw * 0.4)
	_turn("Head", -_head_pitch * 0.65, _head_yaw * 0.6)
	_skel.force_update_all_bone_transforms()
	_hold_paddle()
	var f := _forward()
	var out_left := Vector3.UP.cross(f).normalized()
	_reach("Left", _left, (Vector3.DOWN * 0.6 + out_left * 0.5 - f * 0.4).normalized())
	_point_hand("Left", (_left - _bone("LeftForeArm")).normalized())


func _hold_paddle() -> void:
	# The grip sits on the line from the blade toward a comfortable spot in
	# front of the right shoulder, a paddle's length out at most; nearer
	# work steepens the handle and slides the grip up it.
	var f := _forward()
	var right := f.cross(Vector3.UP).normalized()
	var shoulder := _bone("RightArm")
	var comfort := shoulder + f * 0.32 + right * 0.06 + Vector3.DOWN * 0.3
	var blade := _blade
	blade.y = maxf(blade.y, _felt + 0.003)
	var back := comfort - blade
	var grip := blade + back.normalized() * minf(PADDLE, back.length())
	var along := (blade - grip).normalized()
	var wrist := grip - along * (_hand_len * GRIP_AT)
	_reach("Right", wrist, (Vector3.DOWN * 0.7 + right * 0.6 - f * 0.2).normalized())
	_point_hand("Right", along)
	# The blade is where the cards are; the handle runs from it through the
	# hand as it is really posed, its end past the hand when held short.
	var held := _bone("RightHand") + along * (_hand_len * GRIP_AT)
	var reach_dir := (blade - held).normalized()
	var side := reach_dir.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = right
	var up := side.cross(reach_dir).normalized()
	_paddle.global_transform = Transform3D(Basis(side, up, -reach_dir), blade - reach_dir * PADDLE)
	var blade_node := _paddle.get_node("Blade") as Node3D
	blade_node.global_transform = Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), blade)


func _lean_for(point: Vector3) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	_act["lean"] = clampf((flat.length() - 0.55) / 0.7, 0.0, 1.0) * 0.5


func _rest_blade() -> Vector3:
	return tray() + _forward() * 0.06 + Vector3.UP * (HOVER + 0.04)


func _rest_left() -> Vector3:
	var f := _forward()
	var l := Vector3.UP.cross(f).normalized()
	return Vector3(global_position.x, _felt + 0.03, global_position.z) + f * 0.3 + l * 0.22


func _forward() -> Vector3:
	var f := global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _look_angles(point: Vector3) -> Vector2:
	var f := _forward()
	var l := Vector3.UP.cross(f).normalized()
	var head := _bone("Head")
	var to := point - head
	var yaw := atan2(to.dot(l), to.dot(f))
	var pitch := atan2(to.y, maxf(Vector2(to.dot(f), to.dot(l)).length(), 0.01))
	return Vector2(clampf(yaw, -1.1, 1.1), clampf(pitch, -0.9, 0.4))


func _turn(bone: String, nod: float, yaw: float) -> void:
	var idx := _skel.find_bone(bone)
	if idx < 0:
		return
	var extra := Quaternion.IDENTITY
	if absf(nod) > 0.0001:
		extra = extra * Quaternion(_lateral[bone], nod)
	if absf(yaw) > 0.0001:
		extra = extra * Quaternion(_upright[bone], yaw)
	_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx) * extra)


func _reach(side: String, wrist: Vector3, pole: Vector3) -> void:
	var shoulder := _bone(side + "Arm")
	var a: float = _upper[side]
	var b: float = _fore[side]
	var to := wrist - shoulder
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else _forward()
	var d := clampf(dist, absf(a - b) + 0.01, a + b - 0.003)
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * dir.y
	bend = bend.normalized()
	var elbow := shoulder + dir * (a * cos_a) + bend * (a * sin_a)
	_aim(side + "Arm", elbow - shoulder)
	_aim(side + "ForeArm", shoulder + dir * d - _bone(side + "ForeArm"))


func _point_hand(side: String, dir: Vector3) -> void:
	_aim(side + "Hand", dir)


func _aim(bone: String, world_dir: Vector3) -> void:
	var idx := _skel.find_bone(bone)
	if idx < 0 or world_dir.length() < 0.001:
		return
	_skel.force_update_all_bone_transforms()
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	var local: Vector3 = global.basis.orthonormalized().inverse() * (skel_basis.inverse() * world_dir.normalized())
	if local.length() < 0.001:
		return
	var a := Vector3.UP
	var b := local.normalized()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	var extra := Quaternion.IDENTITY
	if dot < -0.9999:
		extra = Quaternion(Vector3.RIGHT, PI)
	elif dot < 0.99999999:
		var c := a.cross(b)
		extra = Quaternion(c.x, c.y, c.z, 1.0 + dot).normalized()
	_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx) * extra)
	_skel.force_update_all_bone_transforms()


func _local_axis(idx: int, world_axis: Vector3) -> Vector3:
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	return (global.basis.orthonormalized().inverse() * (skel_basis.inverse() * world_axis)).normalized()


func _bone(name: String) -> Vector3:
	var idx := _skel.find_bone(name)
	if idx < 0:
		return global_position
	return _skel.global_transform * _skel.get_bone_global_pose(idx).origin


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _ease(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _rate(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _matte() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var mat := source.duplicate() as StandardMaterial3D
			mat.metallic = 0.0
			mat.metallic_specular = 0.22
			if mat.roughness_texture == null:
				mat.roughness = 0.8
			mesh.set_surface_override_material(surface, mat)


func _make_paddle() -> Node3D:
	# Turned walnut handle with a brass ferrule, and a thin flat blade.
	var root := Node3D.new()
	root.name = "Paddle"
	root.top_level = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.17, 0.08)
	wood.roughness = 0.42
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.56, 0.26)
	brass.metallic = 0.85
	brass.roughness = 0.32
	var handle := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.0075
	rod.bottom_radius = 0.0095
	rod.height = PADDLE
	rod.radial_segments = 12
	rod.material = wood
	handle.mesh = rod
	handle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	handle.position = Vector3(0.0, 0.0, -PADDLE * 0.5)
	root.add_child(handle)
	var ferrule := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.0105
	ring.bottom_radius = 0.0105
	ring.height = 0.03
	ring.radial_segments = 12
	ring.material = brass
	ferrule.mesh = ring
	ferrule.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ferrule.position = Vector3(0.0, 0.0, -PADDLE + 0.03)
	root.add_child(ferrule)
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	blade.top_level = true
	var board := BoxMesh.new()
	board.size = BLADE
	var blade_wood := wood.duplicate() as StandardMaterial3D
	blade_wood.albedo_color = Color(0.36, 0.21, 0.1)
	board.material = blade_wood
	blade.mesh = board
	root.add_child(blade)
	return root
