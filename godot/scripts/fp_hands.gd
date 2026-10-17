extends Node3D

# Hands for the seated first-person player. A Meshy paw is one bone, so it can
# neither close a thumb over a fan nor pinch a single card. The player wears
# these instead: a wrist, a thumb and four fingers with three joints each.

const SOURCE := {
	"Left": "res://assets/hands/hand_left.glb",
	"Right": "res://assets/hands/hand_right.glb",
}
const SIDES := ["Left", "Right"]
const DIGITS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
const SHELLS := 16
# Fan grip: front face to back face of the thickest fan, card half
# thickness, finger bone axis to palm-side fur tips, and how far the fan
# leans off the line from the thumb web to the pinch.
const STACK := 0.0103
const CARD_HALF := 0.0011
const FINGER_SKIN := 0.0105
const PALM_FUR := 0.002
const FAN_LEAN := 0.0
# The fan turns about a point just inside the bottom-left card corner, from
# FAN_TURN on the back card to -FAN_TURN on the front one (half the widest
# fan the seated player opens while choosing). The thumb pad rests on the
# front card PAD_AT from that point and the rest of the thumb has to stay
# clear of the stack wherever there is a card.
const PIVOT := Vector2(0.044, 0.063)
const FAN_TURN := 0.49
const CARD_HALF_SIZE := Vector2(0.048, 0.067)
const PAD_AT := Vector2(0.014, 0.015)
const THUMB_SKIN := 0.0085
# A seated opponent's hands: wrist showing between the coat sleeve and the
# hand (hand-model metres), how much shorter their fur is than the player's
# own, so they read as the same coat as the textured body rather than plush
# gloves, and how far the wrist darkens into the shade of the sleeve.
const SEATED_SLEEVE := 0.018
const SEATED_FUR := 0.55
const SEATED_CUFF := 0.5
const COAT_SATURATION := 0.3
const COAT_VALUE := 1.62
# Bone axis to the skin of the index finger, where it hooks over a card.
const INDEX_SIDE := 0.0085
# Thumb pad target on the fan, in left-hand space; toward the thumb web so
# the cards cover the fingers behind them.
const THUMB_AT := Vector2(0.02, 0.078)
# Where along the top edge the "pluck" index hooks, left of the card center:
# the part of a fanned card the cards in front leave uncovered. How far the
# hand pitches toward the card about that edge, and bone axis to skin on the
# fingertip pressing the back of the card.
const PLUCK_AT := 0.024
const PLUCK_TILT := 0.35
const FINGERTIP_SKIN := 0.007
# Thumb angle limits: base flex, sweep, roll, middle joint, last joint.
const THUMB_RANGE := [Vector2(-0.3, 1.7), Vector2(-1.2, 1.4), Vector2(-1.2, 1.4), Vector2(-0.1, 1.2), Vector2(-0.1, 1.2)]
# Radians. Thumb: base flex, sweep across the palm, roll, middle joint, last joint.
# Fingers: spread toward the thumb, knuckle, middle joint, last joint.
const SHAPES := {
	"flat": {
		"Thumb": [0.0, 0.0, 0.0, 0.0, 0.0],
		"Index": [0.0, 0.0, 0.0, 0.0],
		"Middle": [0.0, 0.0, 0.0, 0.0],
		"Ring": [0.0, 0.0, 0.0, 0.0],
		"Pinky": [0.0, 0.0, 0.0, 0.0],
	},
	"relax": {
		"Thumb": [0.18, 0.12, 0.1, 0.18, 0.22],
		"Index": [0.02, 0.22, 0.42, 0.22],
		"Middle": [0.0, 0.28, 0.5, 0.26],
		"Ring": [-0.02, 0.34, 0.58, 0.3],
		"Pinky": [-0.06, 0.4, 0.64, 0.32],
	},
	"fan": {
		"Thumb": [0.6, 0.6, 0.6, 0.15, 0.12],
		"Index": [0.06, 0.2, 0.25, 0.12],
		"Middle": [0.0, 0.22, 0.28, 0.14],
		"Ring": [-0.04, 0.26, 0.32, 0.16],
		"Pinky": [-0.1, 0.3, 0.36, 0.18],
	},
	"ready": {
		"Thumb": [0.3, 0.22, 0.3, 0.2, 0.2],
		"Index": [0.04, 0.3, 0.5, 0.26],
		"Middle": [0.0, 0.38, 0.62, 0.32],
		"Ring": [-0.03, 0.46, 0.72, 0.36],
		"Pinky": [-0.08, 0.54, 0.8, 0.4],
	},
	"pluck": {
		"Thumb": [0.6, 0.6, 0.6, 0.2, 0.2],
		"Index": [0.0, 0.5, 1.35, 0.8],
		"Middle": [-0.02, 0.6, 1.4, 0.85],
		"Ring": [-0.05, 0.95, 1.45, 0.85],
		"Pinky": [-0.1, 1.05, 1.5, 0.9],
	},
	"open": {
		"Thumb": [0.1, 0.0, 0.0, 0.05, 0.05],
		"Index": [0.08, 0.08, 0.12, 0.06],
		"Middle": [0.0, 0.1, 0.14, 0.08],
		"Ring": [-0.07, 0.14, 0.18, 0.1],
		"Pinky": [-0.14, 0.18, 0.22, 0.12],
	},
	# Rock-paper-scissors throws; "rock" is also the fist that hits the table.
	# The thumbs were fitted to lie across the curled fingers without entering them.
	"rock": {
		"Thumb": [0.27, -0.5, -0.65, 0.56, 0.97],
		"Index": [0.0, 1.45, 1.6, 1.0],
		"Middle": [0.0, 1.5, 1.6, 1.0],
		"Ring": [-0.02, 1.5, 1.6, 1.0],
		"Pinky": [-0.05, 1.5, 1.55, 1.0],
	},
	"paper": {
		"Thumb": [0.05, -0.35, 0.0, 0.05, 0.05],
		"Index": [0.1, 0.02, 0.04, 0.02],
		"Middle": [0.0, 0.02, 0.04, 0.02],
		"Ring": [-0.08, 0.04, 0.06, 0.03],
		"Pinky": [-0.18, 0.06, 0.08, 0.04],
	},
	"scissors": {
		"Thumb": [0.63, -0.94, -0.81, 0.58, 0.84],
		"Index": [0.22, 0.0, 0.04, 0.02],
		"Middle": [-0.18, 0.0, 0.04, 0.02],
		"Ring": [-0.02, 1.5, 1.6, 1.0],
		"Pinky": [-0.05, 1.5, 1.55, 1.0],
	},
}
# Fur, pads and claws per preset, read off the art/karakterler/*-eller.png sheets.
const LOOKS := {
	"kaya": {
		"root": Color(0.2, 0.18, 0.14), "tip": Color(0.5, 0.45, 0.36), "under": Color(0.42, 0.38, 0.31),
		"mark": Color(0.1, 0.09, 0.07), "pattern": 0, "pad": Color(0.15, 0.12, 0.1),
		"claw": Color(0.12, 0.1, 0.08), "length": 0.0058, "claw_length": 0.016, "comb": 1.05,
	},
	"sis": {
		"root": Color(0.34, 0.24, 0.15), "tip": Color(0.72, 0.58, 0.42), "under": Color(0.64, 0.55, 0.44),
		"mark": Color(0.14, 0.09, 0.06), "pattern": 1, "pad": Color(0.2, 0.14, 0.13),
		"claw": Color(0.14, 0.11, 0.09), "length": 0.0066, "claw_length": 0.017, "comb": 1.0,
	},
	"kok": {
		"root": Color(0.045, 0.04, 0.035), "tip": Color(0.26, 0.25, 0.23), "under": Color(0.1, 0.09, 0.08),
		"mark": Color(0.03, 0.03, 0.03), "pattern": 0, "pad": Color(0.07, 0.06, 0.06),
		"claw": Color(0.22, 0.18, 0.14), "length": 0.006, "claw_length": 0.026, "comb": 0.95,
	},
	"karaca": {
		"root": Color(0.25, 0.15, 0.08), "tip": Color(0.54, 0.37, 0.23), "under": Color(0.6, 0.48, 0.38),
		"mark": Color(0.82, 0.74, 0.64), "pattern": 3, "pad": Color(0.17, 0.11, 0.09),
		"claw": Color(0.2, 0.13, 0.09), "length": 0.0045, "claw_length": 0.014, "comb": 1.15,
	},
	"sirtlan": {
		"root": Color(0.19, 0.16, 0.12), "tip": Color(0.54, 0.47, 0.37), "under": Color(0.48, 0.42, 0.34),
		"mark": Color(0.09, 0.07, 0.05), "pattern": 2, "pad": Color(0.12, 0.1, 0.09),
		"claw": Color(0.16, 0.12, 0.1), "length": 0.0058, "claw_length": 0.017, "comb": 1.0,
	},
	"dere": {
		"root": Color(0.13, 0.085, 0.05), "tip": Color(0.36, 0.25, 0.15), "under": Color(0.38, 0.29, 0.21),
		"mark": Color(0.08, 0.05, 0.03), "pattern": 0, "pad": Color(0.12, 0.08, 0.07),
		"claw": Color(0.16, 0.11, 0.08), "length": 0.0036, "claw_length": 0.013, "comb": 1.35,
	},
}

var size := 1.0
var _parts := {}
var _frames := {}
var _fan_shape := {}
var _pluck_shape := {}
var _grip_report := ""
var _shells := SHELLS
static var _shaders := {}
# Fan and pluck grips solved once per hand size: every preset shares the
# same hand mesh, so the seated cast can reuse the player's solution.
static var _solved := {}


func setup(preset: String, hand_size: float, cards := true, shells := SHELLS, seated := false, coat := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	# Without `cards` the fan and pluck grips are not solved; a hand that only
	# throws never needs them. `seated` hands belong to an opponent across the
	# table (see SEATED_SLEEVE); `coat`, when opaque, is the fur colour of
	# that opponent's own head, which their hands then wear, keeping the
	# markings and pads of the preset.
	size = hand_size
	_shells = shells
	top_level = true
	global_transform = Transform3D.IDENTITY
	var look: Dictionary = LOOKS.get(preset, LOOKS["kaya"]).duplicate()
	if coat.a > 0.0:
		# Fur on a hand down by the cloth, in the body's shade and the warm
		# room light, reads darker and redder than the same fur lit on the
		# face, so the hands take it greyer and paler.
		var fur := Color.from_hsv(coat.h, coat.s * COAT_SATURATION, minf(coat.v * COAT_VALUE, 0.92))
		look["root"] = _scaled(fur, 0.7)
		look["tip"] = _scaled(fur, 1.12)
		look["under"] = _scaled(fur.lerp(Color(0.86, 0.82, 0.76), 0.25), 1.05)
	look["length"] = float(look["length"]) * (SEATED_FUR if seated else 1.0)
	look["cuff"] = SEATED_CUFF if seated else 0.0
	var skin := _skin_material(look)
	for side in SIDES:
		var root := (load(SOURCE[side]) as PackedScene).instantiate() as Node3D
		root.name = side + "Hand"
		add_child(root)
		var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
		var mesh: MeshInstance3D = null
		for node in root.find_children("*", "MeshInstance3D", true, false):
			mesh = node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = skin
		var bones := {}
		var rest := []
		for i in skel.get_bone_count():
			bones[skel.get_bone_name(i)] = i
			rest.append(skel.get_bone_rest(i).basis.get_rotation_quaternion())
		var part := {"root": root, "skel": skel, "mesh": mesh, "bones": bones, "rest": rest, "angles": SHAPES["flat"].duplicate(true)}
		_parts[side] = part
		part["pads"] = _pads(part)
		_add_claws(part, look)
	var key := snappedf(size, 0.0001)
	if cards and _solved.has(key):
		var known: Dictionary = _solved[key]
		_frames["grip"] = known["grip"]
		_frames["pluck"] = known["pluck"]
		_fan_shape = known["fan"].duplicate(true)
		_pluck_shape = known["pluck_shape"].duplicate(true)
	elif cards:
		_frames["grip"] = _grip_frame()
		_frames["pluck"] = _pluck_frame()
		_solved[key] = {"grip": _frames["grip"], "pluck": _frames["pluck"], "fan": _fan_shape.duplicate(true), "pluck_shape": _pluck_shape.duplicate(true)}
	else:
		_frames["grip"] = Transform3D.IDENTITY
		_frames["pluck"] = Transform3D.IDENTITY
	for side in SIDES:
		shape(side, {"relax": 1.0})
		var part: Dictionary = _parts[side]
		var low := _palm_depth(part, Vector3.FORWARD, Vector2(-0.02, 0.095), 0.05) + 0.002
		for digit in DIGITS:
			var pad: Vector3 = _bone_local(part, digit + "3") * Vector3(part["pads"][digit])
			low = maxf(low, -pad.z + 0.002)
		_frames["lift_" + side] = low


func place(side: String, xf: Transform3D) -> void:
	var root: Node3D = _parts[side]["root"]
	root.global_transform = Transform3D(xf.basis.orthonormalized().scaled(Vector3.ONE * size), xf.origin)


func shape(side: String, mix: Dictionary) -> void:
	var total := 0.0
	for key in mix:
		total += float(mix[key])
	if total <= 0.0001:
		return
	var angles := {}
	for digit in DIGITS:
		var count: int = 5 if digit == "Thumb" else 4
		var out := []
		out.resize(count)
		out.fill(0.0)
		for key in mix:
			var w := float(mix[key]) / total
			var table: Dictionary = SHAPES[key]
			if key == "fan" and side == "Left" and not _fan_shape.is_empty():
				table = _fan_shape
			elif key == "pluck" and side == "Right" and not _pluck_shape.is_empty():
				table = _pluck_shape
			var src: Array = table[digit]
			for i in count:
				out[i] = float(out[i]) + float(src[i]) * w
		angles[digit] = out
	_parts[side]["angles"] = angles
	_apply(side, angles)


func grip() -> Transform3D:
	return _frames["grip"]


func ground_lift(side: String) -> float:
	# Wrist height above a surface the relaxed hand lies on palm down.
	return float(_frames["lift_" + side]) * size


func pluck() -> Transform3D:
	# Card frame, in right-hand space, of a card held in the "pluck" shape.
	return _frames["pluck"]


func world_frame(side: String, local: Transform3D) -> Transform3D:
	var root: Node3D = _parts[side]["root"]
	var xf := root.global_transform
	return Transform3D(xf.basis.orthonormalized() * local.basis, xf * local.origin)


func local_frame(side: String, world: Transform3D) -> Transform3D:
	# Inverse of world_frame().
	var root: Node3D = _parts[side]["root"]
	var xf := root.global_transform
	return Transform3D(xf.basis.orthonormalized().inverse() * world.basis.orthonormalized(), xf.affine_inverse() * world.origin)


func pad_point(side: String, digit: String) -> Vector3:
	var part: Dictionary = _parts[side]
	var skel: Skeleton3D = part["skel"]
	var idx: int = part["bones"][digit + "3"]
	return skel.global_transform * (skel.get_bone_global_pose(idx) * Vector3(part["pads"][digit]))


func _apply(side: String, angles: Dictionary) -> void:
	var part: Dictionary = _parts[side]
	var skel: Skeleton3D = part["skel"]
	var mirror := 1.0 if side == "Right" else -1.0
	for digit in DIGITS:
		var a: Array = angles[digit]
		for j in 3:
			var idx: int = part["bones"][digit + str(j + 1)]
			var q := Quaternion.IDENTITY
			if digit == "Thumb":
				if j == 0:
					q = Quaternion(Vector3.UP, float(a[2]) * mirror) * Quaternion(Vector3.BACK, -float(a[1]) * mirror) * Quaternion(Vector3.RIGHT, -float(a[0]))
				else:
					q = Quaternion(Vector3.RIGHT, -float(a[j + 2]))
			elif j == 0:
				q = Quaternion(Vector3.BACK, float(a[0]) * mirror) * Quaternion(Vector3.RIGHT, -float(a[1]))
			else:
				q = Quaternion(Vector3.RIGHT, -float(a[j + 1]))
			skel.set_bone_pose_rotation(idx, Quaternion(part["rest"][idx]) * q)
	skel.force_update_all_bone_transforms()


func _bone_local(part: Dictionary, bone: String) -> Transform3D:
	var skel: Skeleton3D = part["skel"]
	return skel.get_bone_global_pose(int(part["bones"][bone]))


func _grip_frame() -> Transform3D:
	# Fan pivot in left-hand space, held the way a palm is held up to read
	# it: the cards rest on the palm side of the fingers and the thumb
	# crosses in front to pin them near their bottom-left corners.
	# Card measurements are in meters and the hand is drawn `size` times its
	# modelled size, so they are divided by `size` here.
	var part: Dictionary = _parts["Left"]
	var angles: Dictionary = SHAPES["fan"].duplicate(true)
	_apply("Left", angles)
	var n := Vector3.FORWARD
	var up := Vector3.UP.rotated(n, FAN_LEAN)
	var x := up.cross(n).normalized()
	var stack := STACK / size
	var face := _palm_depth(part, n) + PALM_FUR + 0.0005 + stack
	var over := func(p: Vector3, pad: Vector3) -> bool:
		var pivot := pad - (x * PAD_AT.x + up * PAD_AT.y) / size
		return _over_cards(Vector2((p - pivot).dot(x), (p - pivot).dot(up)) * size)
	_solve_thumb("Left", angles, Vector3(THUMB_AT.x, THUMB_AT.y, 0.0) + n * (face + 0.0004), n, face, over)
	var pad: Vector3 = _bone_local(part, "Thumb3") * Vector3(part["pads"]["Thumb"])
	face = pad.dot(n) - 0.0004
	var limit := face - stack - 0.0005 - FINGER_SKIN
	for digit in DIGITS.slice(1):
		var target: Array = SHAPES["fan"][digit]
		var best := 0.0
		for step in 21:
			var t := 0.1 * step
			angles[digit] = [target[0], target[1] * t, target[2] * t, target[3] * t]
			_apply("Left", angles)
			if _digit_depth(part, digit, n) <= limit:
				best = t
		angles[digit] = [target[0], target[1] * best, target[2] * best, target[3] * best]
	_fan_shape = angles
	_apply("Left", angles)
	var center := pad - (n * (0.0004 + CARD_HALF) + x * PAD_AT.x + up * PAD_AT.y) / size
	return Transform3D(Basis(x, up, n), center)


func _solve_thumb(side: String, angles: Dictionary, target: Vector3, n: Vector3, face: float, over: Callable) -> void:
	# Coordinate descent on the five thumb angles from a few starts: pad on
	# the card face, the rest of the thumb in front of the face wherever
	# `over` says there is card behind it, and no further from the starting
	# pose than needed.
	var start: Array = angles["Thumb"].duplicate()
	var winner: Array = start.duplicate()
	var winner_cost := INF
	for seed in [start, [0.9, 0.9, 0.9, 0.1, 0.05], [0.5, 0.3, 0.4, 0.3, 0.2], [1.2, -0.6, 0.6, 0.2, 0.1], [1.0, -0.3, 1.0, 0.4, 0.3]]:
		var best_angles: Array = seed.duplicate()
		var best := _thumb_cost(side, angles, best_angles, start, target, n, face, over)
		var step := 0.24
		while step > 0.004:
			var moved := false
			for i in 5:
				for sign in [-1.0, 1.0]:
					var trial: Array = best_angles.duplicate()
					trial[i] = clampf(float(trial[i]) + sign * step, THUMB_RANGE[i].x, THUMB_RANGE[i].y)
					var cost := _thumb_cost(side, angles, trial, start, target, n, face, over)
					if cost < best:
						best = cost
						best_angles = trial
						moved = true
			if not moved:
				step *= 0.5
		if best < winner_cost:
			winner_cost = best
			winner = best_angles
	angles["Thumb"] = winner
	_grip_report += "%s thumb %s cost %.2f; " % [side, winner, winner_cost]
	_apply(side, angles)


func _thumb_cost(side: String, angles: Dictionary, trial: Array, start: Array, target: Vector3, n: Vector3, face: float, over: Callable) -> float:
	var part: Dictionary = _parts[side]
	angles["Thumb"] = trial
	_apply(side, angles)
	var thumb := _bone_local(part, "Thumb3")
	var pad: Vector3 = thumb * Vector3(part["pads"]["Thumb"])
	var miss := pad - target
	var off := miss.dot(n)
	var cost := off * off / (0.001 * 0.001) + (miss - n * off).length_squared() / (0.006 * 0.006)
	cost += 3.0 * (1.0 + thumb.basis.z.normalized().dot(-n))
	for j in range(1, 4):
		var a := _bone_local(part, "Thumb%d" % j).origin
		var b := _bone_local(part, "Thumb%d" % (j + 1)).origin
		for k in 5:
			var p := a.lerp(b, k * 0.25)
			if bool(over.call(p, pad)):
				var sink := THUMB_SKIN - (p.dot(n) - face)
				if sink > 0.0:
					cost += sink * sink / (0.0015 * 0.0015)
	for i in 5:
		cost += 0.2 * pow(float(trial[i]) - float(start[i]), 2.0)
	return cost


static func _over_cards(p: Vector2) -> bool:
	# `p` is relative to the fan pivot, in the fan plane.
	for turn in [-FAN_TURN, 0.0, FAN_TURN]:
		var local := p.rotated(-turn) - PIVOT
		if absf(local.x) <= CARD_HALF_SIZE.x and absf(local.y) <= CARD_HALF_SIZE.y:
			return true
	return false


func _palm_depth(part: Dictionary, n: Vector3, rows := Vector2(0.066, 0.095), half_width := 0.03) -> float:
	# How far the palm reaches toward `n` within a band of the rest mesh;
	# by default the band the bottom of the fan rests against.
	var mesh_node: MeshInstance3D = part["mesh"]
	var verts: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var depth := -INF
	for v in verts:
		if absf(v.x) < half_width and v.y > rows.x and v.y < rows.y:
			depth = maxf(depth, v.dot(n))
	return depth


func _digit_depth(part: Dictionary, digit: String, n: Vector3) -> float:
	var depth := -INF
	for j in range(1, 4):
		var a := _bone_local(part, "%s%d" % [digit, j]).origin
		var b := _bone_local(part, "%s%d" % [digit, j + 1]).origin
		for k in 3:
			depth = maxf(depth, a.lerp(b, k * 0.5).dot(n))
	return depth


func _pluck_frame() -> Transform3D:
	# A standing card taken by its top edge: the index hooks over the edge
	# onto the back face, the thumb pad presses the front face, and the rest
	# of the hand stays in front of the card with the wrist below it.
	var part: Dictionary = _parts["Right"]
	var angles: Dictionary = SHAPES["pluck"].duplicate(true)
	_apply("Right", angles)
	var tip := _bone_local(part, "Index3")
	var pad: Vector3 = tip * Vector3(part["pads"]["Index"])
	var n := -tip.basis.z.normalized()
	var knuckle := _bone_local(part, "Index2")
	var edge := knuckle.basis.x.normalized()
	edge = (edge - n * edge.dot(n)).normalized()
	if n.cross(edge).dot(knuckle.origin - pad) < 0.0:
		edge = -edge
	# Pitched toward the card about its edge, so the forearm runs down along
	# the card instead of out at whoever is holding it.
	var tilted := n.rotated(edge, PLUCK_TILT)
	n = tilted if tilted.y > n.y else n.rotated(edge, -PLUCK_TILT)
	var up := n.cross(edge)
	var back := pad.dot(n) + 0.0004
	var tip_end := _bone_local(part, "Index4").origin
	for k in 5:
		back = maxf(back, tip.origin.lerp(tip_end, 0.4 + 0.15 * k).dot(n) + FINGERTIP_SKIN)
	var mid := back + CARD_HALF / size
	var face := back + 2.0 * CARD_HALF / size
	# The edge sits below wherever the hooked finger's skin crosses the card.
	var top := INF
	for k in 21:
		var p := knuckle.origin.lerp(tip.origin, k * 0.05)
		var d := absf(p.dot(n) - mid)
		if d < INDEX_SIDE:
			top = minf(top, (p - pad).dot(up) - sqrt(INDEX_SIDE * INDEX_SIDE - d * d))
	if top == INF:
		top = (tip.origin - pad).dot(up)
	var center := pad + n * (mid - pad.dot(n)) + up * (top - 0.001 - CARD_HALF_SIZE.y / size) + edge * (PLUCK_AT / size)
	var over := func(p: Vector3, _pad: Vector3) -> bool:
		var q := (p - center) * size
		return absf(q.dot(edge)) <= CARD_HALF_SIZE.x and absf(q.dot(up)) <= CARD_HALF_SIZE.y
	_solve_thumb("Right", angles, pad + n * (face - pad.dot(n) + 0.0004) - up * (0.012 / size), n, face, over)
	# The other fingers curl as far as they can without touching the card.
	for digit in ["Middle", "Ring", "Pinky"]:
		var target: Array = SHAPES["pluck"][digit]
		var best := 2.0
		var found := false
		for step in 21:
			var t := 0.1 * step
			angles[digit] = [target[0], target[1] * t, target[2] * t, target[3] * t]
			_apply("Right", angles)
			if _clear_of_card(part, digit, n, mid, over) and (not found or absf(t - 1.0) < absf(best - 1.0)):
				best = t
				found = true
		angles[digit] = [target[0], target[1] * best, target[2] * best, target[3] * best]
		_grip_report += "%s %.1f%s; " % [digit, best, "" if found else " (touches)"]
	_pluck_shape = angles
	_apply("Right", angles)
	return Transform3D(Basis(edge, up, n), center)


func _clear_of_card(part: Dictionary, digit: String, n: Vector3, mid: float, over: Callable) -> bool:
	for j in range(1, 4):
		var a := _bone_local(part, "%s%d" % [digit, j]).origin
		var b := _bone_local(part, "%s%d" % [digit, j + 1]).origin
		for k in 5:
			var p := a.lerp(b, k * 0.25)
			if bool(over.call(p, p)) and absf(p.dot(n) - mid) < FINGER_SKIN + CARD_HALF / size:
				return false
	return true


func _pads(part: Dictionary) -> Dictionary:
	# Palm-side surface point of each fingertip, in that last bone's space.
	var mesh_node: MeshInstance3D = part["mesh"]
	var skel: Skeleton3D = part["skel"]
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin := mesh_node.skin
	var per: int = bones.size() / verts.size()
	var wanted := {}
	for digit in DIGITS:
		wanted[int(part["bones"][digit + "3"])] = digit
	var bind_of := {}
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		if wanted.has(bone):
			bind_of[b] = bone
	var length := {}
	var out := {}
	var low := {}
	for bone in wanted:
		var digit: String = wanted[bone]
		length[bone] = skel.get_bone_rest(int(part["bones"][digit + "4"])).origin.length()
		out[digit] = Vector3(0.0, float(length[bone]) * 0.6, -0.007)
		low[bone] = INF
	for v in verts.size():
		for k in per:
			var b: int = bones[v * per + k]
			if weights[v * per + k] < 0.6 or not bind_of.has(b):
				continue
			var bone: int = bind_of[b]
			var local: Vector3 = skin.get_bind_pose(b) * verts[v]
			if absf(local.y - float(length[bone]) * 0.6) <= 0.003 and local.z < float(low[bone]):
				low[bone] = local.z
				out[wanted[bone]] = local
	return out


func _add_claws(part: Dictionary, look: Dictionary) -> void:
	var skel: Skeleton3D = part["skel"]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.5
	mat.metallic_specular = 0.35
	var base: Color = look["claw"]
	for digit in DIGITS:
		var idx: int = part["bones"][digit + "3"]
		var tip: int = part["bones"][digit + "4"]
		var length := skel.get_bone_rest(tip).origin.length()
		var pad: Vector3 = part["pads"][digit]
		var radius := absf(pad.z)
		var reach := float(look["claw_length"]) * (1.12 if digit == "Thumb" else (0.86 if digit == "Pinky" else 1.0))
		var attach := BoneAttachment3D.new()
		attach.bone_name = skel.get_bone_name(idx)
		skel.add_child(attach)
		var claw := MeshInstance3D.new()
		claw.mesh = _claw_mesh(reach, radius * 0.62, base)
		claw.material_override = mat
		claw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		claw.position = Vector3(0.0, length * 0.8, radius * 0.45)
		claw.rotation = Vector3(-0.3, 0.0, 0.0)
		attach.add_child(claw)


func _claw_mesh(length: float, radius: float, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 9
	var sides := 12
	var points := []
	for r in rings + 1:
		var t := float(r) / float(rings)
		var center := Vector3(0.0, length * t, -length * 0.36 * t * t)
		var ahead := Vector3(0.0, length, -length * 0.72 * t).normalized()
		var side := Vector3.RIGHT
		var up := side.cross(ahead).normalized() * -1.0
		var w := radius * pow(1.0 - t, 0.65)
		var ring := []
		for s in sides:
			var a := TAU * float(s) / float(sides)
			ring.append(center + side * cos(a) * w * 0.72 + up * sin(a) * w)
		points.append(ring)
	for r in rings:
		var t0 := float(r) / float(rings)
		var t1 := float(r + 1) / float(rings)
		var c0 := base_tint(color, t0)
		var c1 := base_tint(color, t1)
		for s in sides:
			var s1 := (s + 1) % sides
			var a: Vector3 = points[r][s]
			var b: Vector3 = points[r][s1]
			var c: Vector3 = points[r + 1][s1]
			var d: Vector3 = points[r + 1][s]
			st.set_color(c0)
			st.add_vertex(a)
			st.set_color(c1)
			st.add_vertex(c)
			st.set_color(c0)
			st.add_vertex(b)
			st.set_color(c0)
			st.add_vertex(a)
			st.set_color(c1)
			st.add_vertex(d)
			st.set_color(c1)
			st.add_vertex(c)
	st.generate_normals()
	return st.commit()


static func _scaled(color: Color, gain: float) -> Color:
	return Color(minf(color.r * gain, 1.0), minf(color.g * gain, 1.0), minf(color.b * gain, 1.0))


static func base_tint(color: Color, t: float) -> Color:
	return color.lerp(color.lightened(0.18), t * t)


func _skin_material(look: Dictionary) -> ShaderMaterial:
	var skin := ShaderMaterial.new()
	skin.shader = _shader(false)
	_feed(skin, look)
	var last := skin
	for i in _shells:
		var shell := ShaderMaterial.new()
		shell.shader = _shader(true)
		_feed(shell, look)
		shell.set_shader_parameter("shell", float(i + 1) / float(_shells))
		shell.render_priority = i + 1
		last.next_pass = shell
		last = shell
	return skin


func _feed(mat: ShaderMaterial, look: Dictionary) -> void:
	mat.set_shader_parameter("root_color", look["root"])
	mat.set_shader_parameter("tip_color", look["tip"])
	mat.set_shader_parameter("under_color", look["under"])
	mat.set_shader_parameter("mark_color", look["mark"])
	mat.set_shader_parameter("pad_color", look["pad"])
	mat.set_shader_parameter("pattern", int(look["pattern"]))
	mat.set_shader_parameter("fur_length", float(look["length"]))
	mat.set_shader_parameter("comb", float(look["comb"]))
	mat.set_shader_parameter("cuff", float(look.get("cuff", 0.0)))
	mat.set_shader_parameter("sleeve_end", -SEATED_SLEEVE)


func _shader(shell: bool) -> Shader:
	# One shader per kind shared by every hand: the duel hands of the seated
	# opponents then draw with programs the player's own hands already built
	# instead of compiling their own the first time they come into view.
	if _shaders.has(shell):
		return _shaders[shell]
	var shader := Shader.new()
	_shaders[shell] = shader
	var mode := "blend_mix, depth_draw_never, cull_back" if shell else "cull_back"
	shader.code = """shader_type spatial;
render_mode %s, diffuse_burley, specular_schlick_ggx;
uniform vec3 root_color : source_color;
uniform vec3 tip_color : source_color;
uniform vec3 under_color : source_color;
uniform vec3 mark_color : source_color;
uniform vec3 pad_color : source_color;
uniform int pattern = 0;
uniform float fur_length = 0.006;
uniform float comb = 0.5;
uniform float shell = 0.0;
uniform float density = 860.0;
uniform float cuff = 0.0;
uniform float sleeve_end = -0.02;
varying vec3 rest;
varying vec4 mask;

// 1 inside the coat sleeve the hand comes out of, easing to 0 a few
// centimetres out along the wrist.
float sleeved(float y) {
	return 1.0 - smoothstep(sleeve_end - 0.012, sleeve_end + 0.03, y);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + hash33(i + o) - f;
				best = min(best, dot(r, r));
			}
		}
	}
	return sqrt(best);
}

vec3 coat(vec3 p, float under) {
	float clump = noise(p * 260.0) * 0.6 + noise(p * 70.0) * 0.4;
	vec3 fur = mix(root_color, tip_color, 0.55 + 0.3 * (clump - 0.5));
	fur = mix(fur, under_color, under);
	float mark = 0.0;
	if (pattern == 1) {
		vec3 sp = p * vec3(95.0, 70.0, 95.0);
		float spot = cells(sp + vec3(noise(p * 300.0)) * 0.35);
		mark = (1.0 - smoothstep(0.16, 0.32, spot)) * step(0.35, hash13(floor(sp))) * 0.85;
		mark *= 1.0 - under;
	} else if (pattern == 2) {
		float wave = sin((p.y + noise(p * 40.0) * 0.012) * 6.2832 * 24.0);
		mark = smoothstep(0.35, 0.75, wave) * (1.0 - smoothstep(0.06, 0.1, p.y)) * (1.0 - under);
	} else if (pattern == 3) {
		mark = 1.0 - smoothstep(-0.026, -0.012, p.y + (noise(p * 120.0) - 0.5) * 0.008);
	}
	return mix(fur, mark_color, mark);
}

// The strand grids are turned off the mesh axes so flat parts of the hand do
// not slice them into contour lines.
const mat3 GUARD = mat3(vec3(0.6486, 0.6821, -0.3376), vec3(-0.5740, 0.7297, 0.3715), vec3(0.4998, -0.0472, 0.8649));
const mat3 DOWN = mat3(vec3(0.4940, 0.2410, -0.8354), vec3(-0.8638, 0.0269, -0.5030), vec3(-0.0988, 0.9701, 0.2215));

// Distance to the strand of this cell, measured in the surface plane so every
// cell the skin passes through grows a whole hair.
float strand(vec3 p, vec3 n, float h, float shortest, float width, out float seed) {
	vec3 cell = floor(p);
	seed = hash13(cell + 17.0);
	float grow = mix(shortest, 1.0, seed);
	if (h > grow) {
		return 0.0;
	}
	vec3 d = p - (cell + 0.5 + (hash33(cell) - 0.5) * 0.3);
	d -= n * dot(d, n);
	float dist = length(d);
	float radius = width * (1.0 - 0.8 * h / grow);
	float aa = max(fwidth(dist), 0.05);
	return 1.0 - smoothstep(radius - aa, radius + aa, dist);
}

void vertex() {
	rest = vec3(UV.x, UV.y, UV2.x) * 0.1;
	mask = COLOR;
	if (shell > 0.0) {
		float len = fur_length * smoothstep(0.15, 0.6, mask.r) * mix(1.0, 0.32, mask.b) * mask.a;
		len *= 1.0 - 0.8 * cuff * sleeved(rest.y);
		VERTEX += NORMAL * (len * shell) + TANGENT * (len * comb * shell * shell);
	}
}

void fragment() {
	float under = mask.b;
	vec3 fur = coat(rest, under) * (1.0 - cuff * sleeved(rest.y));
	vec3 pg = GUARD * rest * density;
	vec3 pd = DOWN * rest * density * 2.3;
	vec3 ng = cross(dFdx(pg), dFdy(pg));
	vec3 nd = cross(dFdx(pd), dFdy(pd));
	ng = length(ng) > 1e-9 ? normalize(ng) : vec3(0.0, 0.0, 1.0);
	nd = length(nd) > 1e-9 ? normalize(nd) : vec3(0.0, 0.0, 1.0);
	if (shell <= 0.0) {
		float pad = smoothstep(0.1, 0.85, mask.g);
		vec3 skin = fur * 0.66;
		ALBEDO = mix(skin, pad_color * (0.82 + 0.36 * noise(rest * 1400.0)), pad);
		ROUGHNESS = mix(0.92, 0.58, pad);
		SPECULAR = mix(0.1, 0.34, pad);
	} else {
		if (mask.r < 0.3) {
			discard;
		}
		float guard_seed;
		float down_seed;
		float guard = strand(pg, ng, shell, 0.6, 0.3, guard_seed);
		float down = strand(pd, nd, shell / 0.55, 0.45, 0.4, down_seed) * 0.9;
		float alpha = max(guard, down);
		if (alpha < 0.03) {
			discard;
		}
		bool top = guard >= down;
		float seed = top ? guard_seed : down_seed;
		float shade = mix(0.66, 1.0, smoothstep(0.0, 0.85, shell));
		vec3 tip = mix(fur, tip_color, (top ? 0.45 : 0.15) * (1.0 - under));
		vec3 color = mix(fur * 0.86, tip, smoothstep(0.2, 1.0, shell));
		ALBEDO = color * shade * (0.92 + 0.16 * seed);
		ALPHA = alpha;
		ROUGHNESS = 0.8;
		SPECULAR = 0.2;
		RIM = 0.3;
		RIM_TINT = 0.6;
	}
}
""" % mode
	return shader
