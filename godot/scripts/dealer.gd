extends Node3D

# The croupier: a slim fox in a bottle-green waistcoat, standing at the table
# edge with a palette, the long paddle croupiers move cards with. Every card
# that moves on the felt goes through here.
#
# Its hands are fingered (fp_hands.gd), like the players'. To deal it lays
# the paddle down, leans in over the table edge and takes the deck up into
# its left palm, low over the cloth, face down, thumb across it; the right
# hand takes the top card off from above, the shoulders turn to the seat,
# the wrist cocks back beside the deck and the card is swung out low along
# its way and let go flat, skimming over the felt to its player. When the deal is done the deck goes back
# down and the paddle is taken up again in the right fist: the paddle turns
# the played cards over, lines them up, rakes them together and pushes them on.
#
# Actions run one after another. Each moves the paddle blade or the dealing
# hand along eased legs and carries its cards with it; `done` is called when
# the cards have arrived.

signal sound(kind: String)

const FPHands := preload("res://scripts/fp_hands.gd")
const LOOK := "tilki"
const HEIGHT_FIT := 1.04
# Palette: handle length, blade size (width across the handle, thickness,
# depth along it), how high a lifted blade rides over the cloth.
const PADDLE := 0.8
const BLADE := Vector3(0.15, 0.005, 0.06)
const HOVER := 0.05
const CARD := Vector2(0.096, 0.134)
# A card pushed onto the pile is flicked up over this last stretch of its
# way instead of being shoved into the pile's side. Seconds for the blade to
# come down behind a card and to lift off it again.
const HOP_SPAN := 0.22
const REACH := 0.2
const LIFT_OFF := 0.08
# Where the deck lies, this far in front of the croupier.
const TRAY := 0.36
# One dealt card, seconds into it at normal pace: the right hand to the top
# of the held deck, fingers on the card, the card drawn off with the arm
# cocked, the pitch (the card leaves the fingers at its end), the
# follow-through.
const DEAL_KEYS := [0.13, 0.19, 0.31, 0.4, 0.47]
# Dealing hold: the top of the deck this far out before the croupier and
# above the felt; how far the trunk leans in over it, more for a far seat;
# the wrist's wind-up and snap about the vertical, and how far out along the
# card's way and how low over the cloth the card leaves the fingers.
const DECK_OUT := 0.36
const DECK_HIGH := 0.13
const DEAL_LEAN := Vector2(0.4, 0.52)
const COCK := 0.65
const SNAP := 0.25
const PITCH_OUT := 0.3
const PITCH_LOW := 0.07
# The dealt card is held from above: the pinch's front (thumb) side on its
# back, its face to the cloth.
const ABOVE := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
# Seconds to lay the paddle down and take the deck up, and to put the deck
# down and take the paddle up again.
const TAKE_TIME := 0.8
const PUT_TIME := 0.75
# Wrist showing between the sleeve and a fingered hand, in hand metres.
const SLEEVE := 0.02
# Longest a lean toward far work gets, and how much of a lean bends at the
# hips (the legs turned back as much, so they stay standing) rather than in
# the short spine above them.
const LEAN_MAX := 0.62
const HIP_SHARE := 0.6
# How far the hips sink, knees bending, at the dealing lean (more or less
# with the lean): the arms are short, and only so do the hands get down to
# the cloth.
const DIP := 0.1

var camera: Camera3D
var look_point := Vector3.ZERO
var hurry := 1.0

var _skel: Skeleton3D
var _rest: Dictionary = {}
var _hips := -1
var _hips_at := Vector3.ZERO
var _thigh: Dictionary = {}
var _shin: Dictionary = {}
var _lateral: Dictionary = {}
var _upright: Dictionary = {}
var _upper: Dictionary = {}
var _fore: Dictionary = {}
var _center := Vector3.ZERO
var _felt := 0.713
var _paddle: Node3D
var _blade := Vector3.ZERO
var _blade_goal := Vector3.ZERO
var _hands: FPHands
var _left := Transform3D.IDENTITY
var _left_shape := {"relax": 1.0}
var _right := Transform3D.IDENTITY
var _right_shape := {"rock": 1.0}
# The card between the right hand's thumb and fingers, the deck in the left
# palm (bottom card first) and how far it is up in the dealing hold.
var _held: Node3D = null
var _deck: Array = []
var _deck_grip := 0.0
# 0 the paddle in the right fist, 1 laid down on the felt.
var _paddle_down := 0.0
var _paddle_from := Transform3D.IDENTITY
var _lean := 0.0
var _lean_goal := 0.0
var _twist := 0.0
var _twist_goal := 0.0
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
		player.stop()
	for i in _skel.get_bone_count():
		_rest[i] = _skel.get_bone_pose_rotation(i)
	_skel.force_update_all_bone_transforms()
	_hips = _skel.find_bone("Hips")
	_hips_at = _skel.get_bone_pose_position(_hips)
	for bone in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head"]:
		var idx := _skel.find_bone(bone)
		_lateral[bone] = _local_axis(idx, global_transform.basis.x)
		_upright[bone] = _local_axis(idx, global_transform.basis.y)
	for side in ["Left", "Right"]:
		_thigh[side] = _bone(side + "UpLeg").distance_to(_bone(side + "Leg"))
		_shin[side] = _bone(side + "Leg").distance_to(_bone(side + "Foot"))
		_upper[side] = _bone(side + "Arm").distance_to(_bone(side + "ForeArm"))
		_fore[side] = _bone(side + "ForeArm").distance_to(_bone(side + "Hand"))
	_matte()
	# The model's own hands are fixed paws; fingered ones are worn instead.
	_hands = FPHands.new()
	_hands.name = "Hands"
	add_child(_hands)
	_hands.setup(LOOK, HEIGHT_FIT, true, 8, true, _paw_tone())
	for side in ["Left", "Right"]:
		_shrink(_skel.find_bone(side + "Hand"))
	_paddle = _make_paddle()
	add_child(_paddle)
	_blade = _rest_blade()
	_blade_goal = _blade
	_left = _rest_left()
	look_point = _center + Vector3.UP * _felt


func busy() -> bool:
	return not _act.is_empty() or not _queue.is_empty()


func tray() -> Vector3:
	# Felt in front of the croupier where the deck sits.
	return Vector3(global_position.x, _felt, global_position.z) + _forward() * TRAY


# Cards are Node3D; spots are Transform3D on the felt.
func slide(card: Node3D, path: Array, spot: Transform3D, done := Callable(), hop := 0.0) -> void:
	# Pushes the card along the felt through the points in `path` to `spot`;
	# with `hop` it is flicked that high onto the pile at the end.
	push([card], path, [spot], done, hop)


func push(cards: Array, path: Array, spots: Array, done := Callable(), hop := 0.0) -> void:
	# Pushes cards lying together (one card, or a stack) along the felt
	# through `path`; each lands on its own spot at the end.
	var length := 0.0
	var last: Vector3 = (cards[0] as Node3D).global_position
	for point in path:
		length += _flat(Vector3(point) - last).length()
		last = point
	_queue.append({"kind": "slide", "cards": cards, "spots": spots, "path": path, "hop": hop, "done": done, "time": REACH + 0.14 + length * 0.55 + LIFT_OFF})


func flip(card: Node3D, spot: Transform3D, done := Callable()) -> void:
	# Turns the card over where it lies. A card whose top edge has to end
	# up the other way round goes over end to end, otherwise side to side.
	turn([card], [spot], done)


func turn(cards: Array, spots: Array, done := Callable()) -> void:
	# Turns a card, or a stack lying as one, over where it lies.
	_queue.append({"kind": "flip", "cards": cards, "spots": spots, "done": done, "time": 0.5})


func take_deck(cards: Array) -> void:
	# The paddle laid down and the deck (bottom card first, lying together)
	# taken up into the left palm to deal from.
	_queue.append({"kind": "take", "cards": cards, "spots": [], "done": Callable(), "time": TAKE_TIME})


func deal(card: Node3D, toward: Vector3, release: Callable) -> void:
	# The right hand takes `card` off the top of the held deck and pitches it
	# toward `toward`; `release` is called as it leaves the fingers, for the
	# table to fly it the rest of the way.
	_queue.append({"kind": "deal", "cards": [card], "toward": toward, "done": release, "time": DEAL_KEYS[DEAL_KEYS.size() - 1]})


func put_deck(spots: Array, done := Callable()) -> void:
	# What is left of the deck laid on `spots` (top card last), the left hand
	# back to rest and the paddle taken up again.
	_queue.append({"kind": "put", "cards": [], "spots": spots, "done": done, "time": PUT_TIME})


func gather(cards: Array, spots: Array, done := Callable()) -> void:
	# Rakes cards lying in a row together: the blade comes down beyond the
	# row's far end and pushes along it, each card joining the stack ahead
	# of it, and the stack settles on `spots`.
	if cards.is_empty():
		if done.is_valid():
			done.call()
		return
	_queue.append({"kind": "gather", "cards": cards, "spots": spots, "done": done, "time": 0.0})


func wash(cards: Array, spots: Array, done := Callable()) -> void:
	# Mixes face-down cards: the left hand moves them round on the felt
	# under its palm, crossing over one another, and they come together
	# again on `spots`, in whatever order those give.
	_queue.append({"kind": "wash", "cards": cards, "spots": spots, "done": done, "time": 1.05})


func finish_all() -> void:
	# Lands every queued card where it was going; used when a hand is cleared.
	if not _act.is_empty():
		_land(_act)
	for act in _queue:
		_land(act)
	_queue.clear()
	_act = {}
	_held = null
	_deck.clear()
	_deck_grip = 0.0
	_paddle_down = 0.0


func _land(act: Dictionary) -> void:
	# Once only: by the time the hand has let go, whoever the card went to may
	# already have it in hand.
	if act.get("finished", false):
		return
	act["finished"] = true
	var done: Callable = act["done"]
	match str(act["kind"]):
		"deal":
			if _held == act["cards"][0]:
				_held = null
			_deck.erase(act["cards"][0])
			if done.is_valid() and not act.get("released", false):
				done.call()
			return
		"take":
			_deck = act["cards"].duplicate()
			_deck_grip = 1.0
			_paddle_down = 1.0
			return
		"put":
			var left: Array = act.get("cards", [])
			if left.is_empty():
				left = _deck.duplicate()
			var places: Array = act["spots"]
			for i in mini(left.size(), places.size()):
				if is_instance_valid(left[i]):
					left[i].global_transform = places[i]
			_deck.clear()
			_deck_grip = 0.0
			_paddle_down = 0.0
			if done.is_valid():
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
		_blade = _blade.lerp(_blade_goal, _rate(4.0, delta))
		if _deck.is_empty():
			_left = _left.interpolate_with(_rest_left(), _rate(5.0, delta))
			_left_shape = _shape_toward(_left_shape, "relax", _rate(6.0, delta))
		else:
			_left = _left.interpolate_with(_deck_hand(), _rate(6.0, delta))
			_right = _right.interpolate_with(_ready_right(), _rate(6.0, delta))
			_right_shape = _shape_toward(_right_shape, "relax", _rate(6.0, delta))
		# Holding the deck between cards, it stays leaned in over it.
		_lean_goal = DEAL_LEAN.x if not _deck.is_empty() else 0.06
		_twist_goal = 0.0
		return
	_act["t"] = float(_act["t"]) + delta
	match str(_act["kind"]):
		"slide":
			_run_slide(_act)
		"flip":
			_run_flip(_act)
		"deal":
			_run_deal(_act)
		"take":
			_run_take(_act)
		"put":
			_run_put(_act)
		"gather":
			_run_gather(_act)
		"wash":
			_run_wash(_act)


func _start(act: Dictionary) -> void:
	act["blade0"] = _blade
	act["left0"] = _left
	act["right0"] = _right
	act["shape0"] = _left_shape.duplicate()
	act["rshape0"] = _right_shape.duplicate()
	if str(act["kind"]) == "put":
		act["cards"] = _deck.duplicate()
	var cards: Array = act["cards"]
	var starts: Array = []
	for card in cards:
		starts.append(card.global_transform if is_instance_valid(card) else Transform3D.IDENTITY)
	act["starts"] = starts
	match str(act["kind"]):
		"slide":
			# The route on the felt from where the cards lie now, with the
			# distance along it to each corner.
			var line: Array = [Transform3D(starts[0]).origin]
			for point in act["path"]:
				line.append(point)
			_mark(act, line)
		"gather":
			_plan_gather(act)


func _mark(act: Dictionary, line: Array) -> void:
	var marks: Array = [0.0]
	for i in range(1, line.size()):
		marks.append(float(marks[i - 1]) + _flat(Vector3(line[i]) - Vector3(line[i - 1])).length())
	act["line"] = line
	act["marks"] = marks


# --- the paddle ---------------------------------------------------------------

func _run_slide(act: Dictionary) -> void:
	# Blade over to the trailing edge and down, the cards ride ahead of it
	# along the route with the blade turning at each corner, then the blade
	# lifts off.
	var cards: Array = act["cards"]
	var starts: Array = act["starts"]
	var spots: Array = act["spots"]
	var start: Transform3D = starts[0]
	var spot: Transform3D = spots[0]
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
		var hop := float(act["hop"])
		var lead := Transform3D.IDENTITY
		for i in cards.size():
			var from: Transform3D = starts[i]
			var to: Transform3D = spots[i]
			# The stack keeps its shape on the way; each card settles into
			# its own spot as it arrives.
			var basis := Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), u))
			var offset := from.origin - start.origin
			var y := lerpf(from.origin.y, to.origin.y, u)
			if hop > 0.0:
				var s := clampf((along - (total - HOP_SPAN)) / HOP_SPAN, 0.0, 1.0)
				y = lerpf(from.origin.y, to.origin.y, s) + hop * sin(PI * s)
			var pos := Vector3(at.x, y, at.z) + _flat(offset).lerp(_flat(to.origin - spot.origin), u)
			var xf := Transform3D(basis, pos)
			if u >= 1.0:
				xf = to
			if is_instance_valid(cards[i]):
				cards[i].global_transform = xf
			if i == 0:
				lead = xf
		_blade = _behind(act, lead, along)
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
	# Blade edge under the cards' edge nearer the croupier, a flick, and they
	# turn over in a short hop to land where they lay.
	var cards: Array = act["cards"]
	var starts: Array = act["starts"]
	var spots: Array = act["spots"]
	var start: Transform3D = starts[0]
	var spot: Transform3D = spots[0]
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
	var turn_by := PI if axis.cross(across).y > 0.0 else -PI
	if t < 0.4:
		var u := _ease(t / 0.4)
		_blade = Vector3(act["blade0"]).lerp(near + Vector3.UP * 0.004, u)
		_blade.y = lerpf(float(Vector3(act["blade0"]).y), _felt + 0.004, u)
	else:
		var u := clampf((t - 0.4) / 0.6, 0.0, 1.0)
		_blade = near + Vector3.UP * (0.004 + 0.07 * sin(PI * minf(u * 1.6, 1.0)))
		var e := _ease(u)
		var hop := Vector3.UP * (0.07 * 4.0 * e * (1.0 - e))
		for i in cards.size():
			if not is_instance_valid(cards[i]):
				continue
			var from: Transform3D = starts[i]
			var to: Transform3D = spots[i]
			var turned := (Basis(axis, turn_by * e) * from.basis).orthonormalized()
			if e >= 1.0:
				turned = to.basis
			cards[i].global_transform = Transform3D(turned, from.origin.lerp(to.origin, e) + hop)
		if not act.get("noise", false) and u > 0.05:
			act["noise"] = true
			sound.emit("flip")
	look_point = start.origin
	_lean_for(start.origin)
	if t >= 1.0:
		_land(act)
		_act = {}


func _plan_gather(act: Dictionary) -> void:
	# The rake's route: in line with the row from just beyond its far end,
	# along it past the near end, then over to the stack's place. Each card
	# is picked up where the blade reaches its trailing edge.
	var cards: Array = act["cards"]
	var spots: Array = act["spots"]
	var first: Vector3 = Transform3D(act["starts"][0]).origin
	var last: Vector3 = Transform3D(act["starts"][cards.size() - 1]).origin
	var stack: Vector3 = Transform3D(spots[0]).origin
	var along := _flat(last - first)
	if along.length() < 0.01:
		along = _flat(stack - first)
	along = along.normalized()
	var reach := CARD.x * 0.5 + 0.03
	var line: Array = [first - along * reach, last + along * reach]
	var into := _flat(stack - Vector3(line[1]))
	var stop: Vector3 = stack - into.normalized() * reach if into.length() > 0.12 else Vector3(line[1])
	line.append(stop)
	_mark(act, line)
	var pickup: Array = []
	for i in cards.size():
		var at: Vector3 = Transform3D(act["starts"][i]).origin
		pickup.append(maxf(0.0, (at - Vector3(line[0])).dot(along) - reach))
	act["pickup"] = pickup
	act["settle"] = 0.22
	act["time"] = REACH + 0.1 + float(act["marks"][act["marks"].size() - 1]) * 0.6 + float(act["settle"])


func _run_gather(act: Dictionary) -> void:
	var cards: Array = act["cards"]
	var spots: Array = act["spots"]
	var starts: Array = act["starts"]
	var marks: Array = act["marks"]
	var total: float = marks[marks.size() - 1]
	var time: float = act["time"]
	var settle: float = act["settle"]
	var t := float(act["t"])
	var push_end := time - settle
	var line: Array = act["line"]
	if t < REACH:
		var u := _ease(t / REACH)
		var from := Vector3(act["blade0"])
		var goal := Vector3(line[0])
		_blade = from.lerp(Vector3(goal.x, _felt + 0.004, goal.z), u)
		_blade.y = lerpf(from.y, _felt + HOVER, minf(u * 1.6, 1.0)) - (HOVER - 0.004) * _ease((u - 0.7) / 0.3)
	elif t < push_end:
		var u := _ease((t - REACH) / maxf(push_end - REACH, 0.01))
		var along := u * total
		var at := _along(act, along)
		var ahead := _flat(_along(act, minf(along + 0.04, total)) - _along(act, maxf(along - 0.04, 0.0)))
		var dir := ahead.normalized() if ahead.length() > 0.001 else _flat(Vector3(line[1]) - Vector3(line[0])).normalized()
		_blade = Vector3(at.x, _felt + 0.004, at.z)
		var stacked := 0
		for i in cards.size():
			var card: Node3D = cards[i]
			if not is_instance_valid(card) or along < float(act["pickup"][i]):
				continue
			# Ahead of the blade, long side square to the way it goes, each
			# card a hair above the one gathered before it.
			var start: Transform3D = starts[i]
			var top := Vector3.UP.cross(dir).normalized()
			var flat := Basis(top.cross(Vector3.UP).normalized(), top, Vector3.UP) if start.basis.z.y > 0.0 else Basis(top.cross(Vector3.DOWN).normalized(), top, Vector3.DOWN)
			var catch := clampf((along - float(act["pickup"][i])) / 0.06, 0.0, 1.0)
			var basis := Basis(start.basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), _ease(catch)))
			var pos := at + dir * (CARD.x * 0.5 + 0.026)
			pos.y = _felt + 0.0016 + 0.0007 * float(stacked)
			card.global_transform = Transform3D(basis, pos)
			stacked += 1
		if not act.get("noise", false):
			act["noise"] = true
			sound.emit("deal")
	else:
		# The stack squares up on its place and the blade lifts.
		var u := _ease((t - push_end) / settle)
		var end := Vector3(line[line.size() - 1])
		_blade = Vector3(end.x, _felt + 0.004 + (HOVER - 0.004) * u, end.z)
		if not act.get("lifted", false):
			act["lifted"] = true
			act["held"] = []
			for card in cards:
				act["held"].append(card.global_transform if is_instance_valid(card) else Transform3D.IDENTITY)
		for i in cards.size():
			if is_instance_valid(cards[i]):
				var from: Transform3D = act["held"][i]
				var to: Transform3D = spots[i]
				cards[i].global_transform = Transform3D(Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), u)), from.origin.lerp(to.origin, u))
	look_point = _blade
	_lean_for(_blade)
	if t >= time:
		_land(act)
		_act = {}


# --- the dealing hand -----------------------------------------------------------

func _run_deal(act: Dictionary) -> void:
	# The right hand to the top of the deck in the left palm, the card taken
	# off between thumb and fingers, the arm drawn back with the shoulders
	# turned to the seat, the pitch, the follow-through. The card rides in
	# the right hand from the take to the pitch.
	var card: Node3D = act["cards"][0]
	var t := float(act["t"])
	var k: Array = DEAL_KEYS
	var toward: Vector3 = act["toward"]
	var on_deck := _card_on_deck(card)
	var aim := _flat(toward - on_deck.origin)
	aim = aim.normalized() if aim.length() > 0.01 else _forward()
	var right := _forward().cross(Vector3.UP).normalized()
	# Flat and face down, the held edge trailing behind the card's way. The
	# wind-up turns the card back toward the dealing hand's side, low beside
	# the deck; the swing carries it out along its way, down near the cloth,
	# the wrist snapping through past square as it lets go.
	var thrown := Basis(-Vector3.UP.cross(aim).normalized(), -aim, Vector3.DOWN)
	var slid := Transform3D(on_deck.basis, on_deck.origin + right * (CARD.y * 0.7) + Vector3.UP * 0.012)
	var cocked := Transform3D(Basis(Vector3.UP, -COCK) * thrown, on_deck.origin + right * 0.11 - aim * 0.06 + Vector3.UP * 0.015)
	var snapped := Transform3D(Basis(Vector3.UP, SNAP) * thrown, Vector3.ZERO)
	snapped.origin = _pitch_point(on_deck.origin + right * 0.02, aim, snapped.basis)
	var out := snapped.origin
	var follow := Transform3D(Basis(Vector3.UP, SNAP * 1.6) * thrown, out + aim * 0.08 - Vector3.UP * 0.012)
	var above := Transform3D(on_deck.basis, on_deck.origin + Vector3.UP * 0.035 + right * 0.03)
	var from: Transform3D = act["right0"]
	_left = _deck_hand()
	_left_shape = {"fan": 1.0}
	if t < float(k[0]):
		# To the deck, the fingers opening ready.
		var u := _ease(t / float(k[0]))
		_right = from.interpolate_with(_right_on(above), u)
		_right_shape = _shape_toward(act["rshape0"], "pluck", u)
	elif t < float(k[1]):
		# Down onto the top card; the fingers close on it.
		var u := _ease((t - float(k[0])) / (float(k[1]) - float(k[0])))
		_right = _right_on(above).interpolate_with(_right_on(on_deck), u)
		_right_shape = {"pluck": 1.0}
	elif t < float(k[2]):
		# Off the deck and up, the wrist cocked back.
		_take(card)
		var u := _ease((t - float(k[1])) / (float(k[2]) - float(k[1])))
		var mid := _ease(minf(u * 2.0, 1.0))
		var lift := _right_on(on_deck).interpolate_with(_right_on(slid), mid)
		_right = lift.interpolate_with(_right_on(cocked), _ease(maxf(u * 2.0 - 1.0, 0.0)))
		_right_shape = {"pluck": 1.0}
	elif t < float(k[3]):
		# The swing: out low along the way, gathering speed, the wrist
		# snapping through at the end.
		_take(card)
		var u := (t - float(k[2])) / (float(k[3]) - float(k[2]))
		_right = _right_on(cocked).interpolate_with(_right_on(snapped), u * u)
		_right_shape = {"pluck": 1.0}
	else:
		_release(act)
		var u := _ease((t - float(k[3])) / (float(k[4]) - float(k[3])))
		_right = _right_on(snapped).interpolate_with(_right_on(follow), u)
		_right_shape = _shape_toward({"pluck": 1.0}, "open", u)
	_twist_goal = clampf(_forward().signed_angle_to(_flat(toward - global_position), Vector3.UP) * 0.6, -0.6, 0.6)
	look_point = on_deck.origin if t < float(k[1]) else toward
	var far := clampf((_flat(toward - global_position).length() - 0.9) / 1.2, 0.0, 1.0)
	_act["lean"] = lerpf(DEAL_LEAN.x, DEAL_LEAN.y, far)
	if t >= float(k[4]):
		_release(act)
		_act = {}


func _pitch_point(from: Vector3, aim: Vector3, basis: Basis) -> Vector3:
	# Where the card leaves the fingers: PITCH_OUT along its way and
	# PITCH_LOW over the cloth, or as far out and as low as the arm reaches
	# from where the shoulder is now; out of reach, a hand pulled in toward
	# the shoulder would lift the card and lob it.
	var shoulder := _bone("RightArm")
	var limit := (float(_upper["Right"]) + float(_fore["Right"])) * 0.96
	var at := from
	for rise in 6:
		for k in 7:
			at = from + aim * (PITCH_OUT * float(6 - k) / 6.0)
			at.y = _felt + PITCH_LOW + 0.025 * float(rise)
			var hand := _right_on(Transform3D(basis, at))
			var wrist := hand.origin - hand.basis.y.normalized() * (SLEEVE * float(_hands.size))
			if wrist.distance_to(shoulder) <= limit:
				return at
	return at


func _take(card: Node3D) -> void:
	if _held != card and is_instance_valid(card):
		_held = card
		_deck.erase(card)


func _release(act: Dictionary) -> void:
	if act.get("released", false):
		return
	act["released"] = true
	if _held == act["cards"][0]:
		_held = null
	_deck.erase(act["cards"][0])
	sound.emit("deal")
	var done: Callable = act["done"]
	if done.is_valid():
		done.call()


func _card_on_deck(card: Node3D) -> Transform3D:
	# Where `card` lies in the held deck (or where it lies now, if it is not
	# in it).
	var at := _deck.find(card)
	if at < 0:
		return card.global_transform if is_instance_valid(card) else Transform3D.IDENTITY
	return _deck_card(at)


func _deck_card(index: int) -> Transform3D:
	# The deck lies in the left palm face down, thumb across its back; the
	# top card nearest the thumb.
	var fan := _hands.world_frame("Left", _hands.grip())
	var depth := -0.00055 * float(_deck.size() - 1 - index)
	return fan * Transform3D(Basis(Vector3.UP, PI), Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y, depth))


func _deck_frame() -> Transform3D:
	# Where the top of the held deck is wanted: out over the table edge, low
	# over the cloth, a little to the left, face down, its long edge toward
	# the right hand.
	var f := _forward()
	var l := Vector3.UP.cross(f).normalized()
	var r := -l
	var at := Vector3(global_position.x, _felt + DECK_HIGH, global_position.z) + f * DECK_OUT + l * 0.06
	var basis := Basis(r.cross(Vector3.DOWN).normalized(), r, Vector3.DOWN)
	return Transform3D(Basis(f, -0.12) * basis, at)


func _deck_hand() -> Transform3D:
	# The left hand placed so the top of its deck sits on _deck_frame().
	var top := _deck_frame()
	var local := Transform3D(Basis(Vector3.UP, PI), Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y, 0.0))
	var fan := top * local.affine_inverse()
	return _hand_for(fan, _hands.grip())


func _right_on(card_xf: Transform3D) -> Transform3D:
	# Where the right hand goes to hold a card at `card_xf` in its pinch,
	# from above (see ABOVE).
	return _hand_for(card_xf * Transform3D(ABOVE, Vector3.ZERO), _hands.pluck())


func _ready_right() -> Transform3D:
	# Waiting beside the deck for the next card.
	var top := _deck_frame()
	var r := _forward().cross(Vector3.UP).normalized()
	return _right_on(Transform3D(top.basis, top.origin + r * 0.1 + Vector3.UP * 0.03))


func _hand_for(frame: Transform3D, local: Transform3D) -> Transform3D:
	# Hand placement that lays the hand-space frame `local` onto `frame`.
	var basis := frame.basis.orthonormalized() * local.basis.inverse()
	return Transform3D(basis, frame.origin - basis * (local.origin * float(_hands.size)))


func _run_take(act: Dictionary) -> void:
	# The right hand lays the paddle down beside the deck and lets go; the
	# left reaches the deck, closes on it and lifts it into the dealing hold.
	var cards: Array = act["cards"]
	var t := float(act["t"])
	var time: float = act["time"]
	if not act.has("lying"):
		act["lying"] = []
		for card in cards:
			act["lying"].append(card.global_transform if is_instance_valid(card) else Transform3D.IDENTITY)
		_paddle_from = _paddle.global_transform
	var lying: Array = act["lying"]
	# Paddle down over the first half.
	var down := _ease(t / (time * 0.45))
	_paddle_down = down
	if down < 1.0:
		_right_shape = {"rock": 1.0}
	else:
		var u := _ease((t - time * 0.45) / (time * 0.55))
		_right = Transform3D(_right).interpolate_with(_ready_right(), u)
		_right_shape = _shape_toward({"rock": 1.0}, "relax", u)
	# Left hand: over to the deck, onto it, up with it.
	var top: Transform3D = lying[lying.size() - 1] if not lying.is_empty() else tray_xf()
	var deck_count := cards.size()
	var reach_t := time * 0.4
	var grab_t := time * 0.55
	var on_felt := _hand_for(top * Transform3D(Basis(Vector3.UP, PI), Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y, 0.0)).affine_inverse(), _hands.grip())
	if t < reach_t:
		var u := _ease(t / reach_t)
		_left = Transform3D(act["left0"]).interpolate_with(on_felt, u)
		_left.origin += Vector3.UP * (0.05 * sin(PI * u))
		_left_shape = _shape_toward(act["shape0"], "open", u)
		_act["lean"] = 0.5 * u
	elif t < grab_t:
		_left = on_felt
		_left_shape = _shape_toward({"open": 1.0}, "fan", _ease((t - reach_t) / (grab_t - reach_t)))
		_act["lean"] = 0.5
	else:
		var u := _ease((t - grab_t) / (time - grab_t))
		_left = on_felt.interpolate_with(_deck_hand(), u)
		_left_shape = {"fan": 1.0}
		_act["lean"] = lerpf(0.5, DEAL_LEAN.x, u)
		if _deck.is_empty() and deck_count > 0:
			_deck = cards.duplicate()
	_deck_grip = 1.0 if not _deck.is_empty() else 0.0
	look_point = top.origin
	if t >= time:
		_land(act)
		_act = {}


func _run_put(act: Dictionary) -> void:
	# The left hand lays what is left of the deck down and goes back to rest;
	# the right takes the paddle up again.
	var cards: Array = act["cards"]
	var spots: Array = act["spots"]
	var t := float(act["t"])
	var time: float = act["time"]
	var place_t := time * 0.45
	if not cards.is_empty() and spots.size() >= cards.size():
		var top: Transform3D = spots[cards.size() - 1]
		var on_felt := _hand_for(top * Transform3D(Basis(Vector3.UP, PI), Vector3(FPHands.PIVOT.x, FPHands.PIVOT.y, 0.0)).affine_inverse(), _hands.grip())
		if t < place_t:
			var u := _ease(t / place_t)
			_left = Transform3D(act["left0"]).interpolate_with(on_felt, u)
			_left_shape = {"fan": 1.0}
			_act["lean"] = lerpf(DEAL_LEAN.x, 0.5, u)
		else:
			if not _deck.is_empty():
				for i in cards.size():
					if is_instance_valid(cards[i]):
						cards[i].global_transform = spots[i]
				_deck.clear()
				sound.emit("card")
			var u := _ease((t - place_t) / (time - place_t))
			_left = on_felt.interpolate_with(_rest_left(), u)
			_left_shape = _shape_toward({"fan": 1.0}, "relax", u)
			_act["lean"] = 0.5 * (1.0 - u)
	else:
		_deck.clear()
		var u := _ease(t / time)
		_left = Transform3D(act["left0"]).interpolate_with(_rest_left(), u)
		_left_shape = _shape_toward(act["shape0"], "relax", u)
	# The right hand back to the paddle and up with it.
	var grip_t := time * 0.5
	if t < grip_t:
		_paddle_down = 1.0
		var u := _ease(t / grip_t)
		_right = Transform3D(act["right0"]).interpolate_with(_park_hand(), u)
		_right_shape = _shape_toward(act["rshape0"], "rock", u)
	else:
		_paddle_down = 1.0 - _ease((t - grip_t) / (time - grip_t))
		_right_shape = {"rock": 1.0}
	_deck_grip = 0.0 if _deck.is_empty() else 1.0
	if t >= time:
		_land(act)
		_act = {}


func tray_xf() -> Transform3D:
	var f := _forward()
	return Transform3D(Basis(f.cross(Vector3.DOWN).normalized(), f, Vector3.DOWN), tray())


func _run_wash(act: Dictionary) -> void:
	# The palm moves the cards round in two loops under it; they cross over
	# one another, slowing to rest on their spots.
	var cards: Array = act["cards"]
	var starts: Array = act["starts"]
	var spots: Array = act["spots"]
	var time: float = act["time"]
	var t := clampf(float(act["t"]) / time, 0.0, 1.0)
	var middle := Vector3.ZERO
	for xf in starts:
		middle += Transform3D(xf).origin
	middle /= maxf(float(starts.size()), 1.0)
	var swirl := _ease(t)
	for i in cards.size():
		if not is_instance_valid(cards[i]):
			continue
		var from: Transform3D = starts[i]
		var to: Transform3D = spots[i]
		var angle := TAU * 1.5 * swirl + float(i) * TAU / float(cards.size())
		var radius := 0.07 * sin(PI * t)
		var around := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var pos := from.origin.lerp(to.origin, swirl) + around
		pos.y = _felt + 0.0016 + 0.0009 * float(i) + 0.004 * sin(PI * t)
		var basis := Basis(Vector3.UP, 0.8 * sin(PI * t) * (1.0 if i % 2 == 0 else -1.0)) * Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), swirl))
		cards[i].global_transform = Transform3D(basis.orthonormalized(), pos)
	var palm_at := middle + Vector3(cos(TAU * 1.5 * swirl), 0.0, sin(TAU * 1.5 * swirl)) * 0.05 * sin(PI * t)
	var along := _flat(palm_at - global_position).normalized()
	var flat := Transform3D(Basis(along.cross(Vector3.UP).normalized(), along, Vector3.UP), palm_at + Vector3.UP * (_hands.ground_lift("Left") + 0.006) - along * 0.06)
	_left = Transform3D(act["left0"]).interpolate_with(flat, _ease(minf(t * 4.0, 1.0)))
	_left_shape = _shape_toward(act["shape0"], "flat", _ease(minf(t * 4.0, 1.0)))
	if not act.get("noise", false) and t > 0.1:
		act["noise"] = true
		sound.emit("shuffle")
	look_point = middle
	_lean_for(middle)
	if t >= 1.0:
		_land(act)
		_act = {}


# --- pose ----------------------------------------------------------------------

func _pose(delta: float) -> void:
	for i in _rest:
		_skel.set_bone_pose_rotation(i, _rest[i])
	if _hips >= 0:
		_skel.set_bone_pose_position(_hips, _hips_at)
	_skel.force_update_all_bone_transforms()
	var breath := sin(_time * 1.3) * 0.02
	_lean = lerpf(_lean, float(_act.get("lean", _lean_goal)), _rate(3.5, delta))
	_twist = lerpf(_twist, _twist_goal, _rate(4.0, delta))
	# Feet where they stand; then the hips sink and hinge forward, and the
	# legs bend to keep the feet there.
	var feet := {}
	for side in ["Left", "Right"]:
		feet[side] = [_bone(side + "Foot"), _bone(side + "ToeBase") - _bone(side + "Foot")]
	var dip := DIP * clampf(_lean / DEAL_LEAN.x, 0.0, 1.0)
	if _hips >= 0 and dip > 0.0005:
		var to_local := _skel.global_transform.basis.inverse()
		var parent := _skel.get_bone_parent(_hips)
		if parent >= 0:
			to_local = _skel.get_bone_global_pose(parent).basis.inverse() * to_local
		_skel.set_bone_pose_position(_hips, _hips_at + to_local * Vector3(0.0, -dip, 0.0))
		_skel.force_update_all_bone_transforms()
	_turn("Hips", _lean * HIP_SHARE, 0.0)
	_skel.force_update_all_bone_transforms()
	for side in ["Left", "Right"]:
		_stand_on(side, feet[side][0], feet[side][1])
	_turn("Spine02", _lean * 0.3 + breath * 0.3, _twist * 0.3)
	_turn("Spine01", _lean * 0.26 + breath * 0.5, _twist * 0.35)
	_turn("Spine", _lean * 0.18 + breath, _twist * 0.35)
	var aim := _look_angles(look_point)
	_head_yaw = lerpf(_head_yaw, aim.x, _rate(5.0, delta))
	_head_pitch = lerpf(_head_pitch, aim.y, _rate(5.0, delta))
	_turn("neck", -_head_pitch * 0.35, _head_yaw * 0.4)
	_turn("Head", -_head_pitch * 0.65, _head_yaw * 0.6)
	_skel.force_update_all_bone_transforms()
	_place_right()
	_place_left()
	for i in _deck.size():
		if is_instance_valid(_deck[i]):
			(_deck[i] as Node3D).global_transform = _deck_card(i)
	if _held != null and is_instance_valid(_held):
		_held.global_transform = _hands.world_frame("Right", _hands.pluck()) * Transform3D(ABOVE, Vector3.ZERO)


func _place_left() -> void:
	# The left hand where the act puts it (resting, holding the deck), pulled
	# in if the arm cannot reach, and the arm brought to it.
	var hand := _within_reach("Left", _left)
	_hands.place("Left", hand)
	_hands.shape("Left", _left_shape)
	_arm_to("Left", hand)


func _place_right() -> void:
	# In the paddle's fist, or free (dealing) with the paddle laid down, or
	# on the way between the two.
	var held := _paddle_hold()
	var parked := _parked_paddle()
	if _paddle_down <= 0.0:
		_right = held["hand"]
		_set_paddle(held["paddle"], held["blade"])
	elif _paddle_down >= 1.0:
		_set_paddle(parked, parked * Vector3(0.0, 0.0, PADDLE))
	else:
		# Laying it down or taking it up: paddle and fist travel together.
		var u := _paddle_down
		var paddle := Transform3D(held["paddle"]).interpolate_with(parked, u)
		_set_paddle(paddle, paddle * Vector3(0.0, 0.0, PADDLE))
		var fist: Transform3D = _hands.fist_axis("Right")
		var grip := paddle * Vector3(0.0, 0.0, lerpf(float(held["grip_at"]), PADDLE * 0.12, u))
		var along := paddle.basis.z.normalized()
		var toward_arm := (_bone("RightArm") - grip)
		toward_arm = (toward_arm - along * toward_arm.dot(along)).normalized()
		_right = _hand_for(Transform3D(Basis(toward_arm.cross(along).normalized(), toward_arm, along), grip), fist)
		_right_shape = {"rock": 1.0}
	var hand := _within_reach("Right", _right)
	_hands.place("Right", hand)
	_hands.shape("Right", _right_shape)
	_arm_to("Right", hand)


func _parked_paddle() -> Transform3D:
	# Lying on the felt beside the deck, the blade out toward the middle and
	# the handle end at the table's edge by the right hand.
	var f := _forward()
	var r := f.cross(Vector3.UP).normalized()
	var end := Vector3(global_position.x, _felt + 0.011, global_position.z) + f * 0.2 + r * 0.22
	var tip := Vector3(global_position.x, _felt + 0.011, global_position.z) + f * 0.92 + r * 0.32
	var along := (tip - end).normalized()
	var side := along.cross(Vector3.UP).normalized()
	return Transform3D(Basis(side, side.cross(along).normalized() * -1.0, along).orthonormalized(), end)


func _park_hand() -> Transform3D:
	# The right fist closed on the handle of the parked paddle.
	var parked := _parked_paddle()
	var grip := parked * Vector3(0.0, 0.0, PADDLE * 0.12)
	var along := parked.basis.z.normalized()
	var toward_arm := (_bone("RightArm") - grip)
	toward_arm = (toward_arm - along * toward_arm.dot(along)).normalized()
	return _hand_for(Transform3D(Basis(toward_arm.cross(along).normalized(), toward_arm, along), grip), _hands.fist_axis("Right"))


func _set_paddle(paddle: Transform3D, blade: Vector3) -> void:
	_paddle.global_transform = paddle
	var along := paddle.basis.z.normalized()
	var side := along.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = paddle.basis.x
	var blade_node := _paddle.get_node("Blade") as Node3D
	blade_node.global_transform = Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), blade)


func _paddle_hold() -> Dictionary:
	# The handle runs from the blade back toward a comfortable spot in front
	# of the right shoulder; the fist closes on it as far down it as the arm
	# reaches, so near work slides the grip up the handle.
	var f := _forward()
	var right := f.cross(Vector3.UP).normalized()
	var shoulder := _bone("RightArm")
	var comfort := shoulder + f * 0.24 + right * 0.08 + Vector3.DOWN * 0.38
	var blade := _blade
	blade.y = maxf(blade.y, _felt + 0.003)
	var back := comfort - blade
	var along := -back.normalized()
	var limit := (float(_upper["Right"]) + float(_fore["Right"])) * 0.97
	var reach := minf(PADDLE - 0.06, back.length())
	var grip := blade + back.normalized() * reach
	# Slide the grip down the handle until the arm reaches it.
	for _i in 12:
		var wrist_guess := grip - Vector3.UP * 0.05 + right * 0.03
		if wrist_guess.distance_to(shoulder) <= limit + float(_hands.size) * 0.09:
			break
		grip = grip.lerp(blade, 0.08)
	# The fist: the handle through it, knuckles up and out, the wrist behind.
	var fist: Transform3D = _hands.fist_axis("Right")
	var toward_arm := (shoulder - grip)
	toward_arm = (toward_arm - along * toward_arm.dot(along)).normalized()
	var want := Basis(toward_arm.cross(along).normalized(), toward_arm, along)
	var hand := _hand_for(Transform3D(want, grip), fist)
	# The paddle: from the blade back through the fist and on.
	var side := along.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = right
	var up := side.cross(-along).normalized()
	return {"hand": hand, "paddle": Transform3D(Basis(side, up, along), blade - along * PADDLE), "blade": blade, "grip_at": PADDLE - grip.distance_to(blade)}


func _within_reach(side: String, hand: Transform3D) -> Transform3D:
	# Pull a hand in along the arm if the sleeve could not reach its wrist.
	var shoulder := _bone(side + "Arm")
	var wrist := hand.origin - hand.basis.y.normalized() * (SLEEVE * float(_hands.size))
	var limit := (float(_upper[side]) + float(_fore[side])) * 0.98
	var span := wrist - shoulder
	if span.length() <= limit:
		return hand
	return Transform3D(hand.basis, hand.origin - span.normalized() * (span.length() - limit))


func _arm_to(side: String, hand: Transform3D) -> void:
	# The sleeve over the hand's wrist, the elbow bending out and down.
	var back := -hand.basis.y.normalized()
	var wrist := hand.origin + back * (SLEEVE * float(_hands.size))
	var f := _forward()
	var outward := f.cross(Vector3.UP).normalized() * (1.0 if side == "Right" else -1.0)
	var pole := (Vector3.DOWN * 0.6 + outward * 0.6 - f * 0.25).normalized()
	_reach(side, wrist, pole)


func _lean_for(point: Vector3) -> void:
	# Leaning in toward far work, so the hands reach it.
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	_act["lean"] = clampf((flat.length() - 0.42) / 0.7, 0.0, 1.0) * LEAN_MAX


func _rest_blade() -> Vector3:
	# Resting on the cloth out to the right of the deck, the handle running
	# back up to the fist at the hip.
	var f := _forward()
	var right := f.cross(Vector3.UP).normalized()
	return tray() + f * 0.22 + right * 0.16 + Vector3.UP * 0.004


func _rest_left() -> Transform3D:
	# Resting on the cloth beside the deck, palm down, fingers to the middle.
	var f := _forward()
	var l := Vector3.UP.cross(f).normalized()
	var at := Vector3(global_position.x, _felt, global_position.z) + f * (TRAY - 0.16) + l * 0.2
	var along := (f * 0.9 - l * 0.3).normalized()
	at.y = _felt + _hands.ground_lift("Left") + 0.004
	return Transform3D(Basis(along.cross(Vector3.UP).normalized(), along, Vector3.UP), at)


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


func _stand_on(side: String, foot: Vector3, toe: Vector3) -> void:
	# Two-bone leg to `foot`, the knee forward; the foot kept pointing along
	# `toe`, flat on the floor as it stood.
	var hip := _bone(side + "UpLeg")
	var a: float = _thigh[side]
	var b: float = _shin[side]
	var to := foot - hip
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.DOWN
	var d := clampf(dist, absf(a - b) + 0.01, a + b - 0.002)
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pole := _forward()
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		return
	bend = bend.normalized()
	var knee := hip + dir * (a * cos_a) + bend * (a * sin_a)
	_aim(side + "UpLeg", knee - hip)
	_aim(side + "Leg", foot - _bone(side + "Leg"))
	_aim(side + "Foot", toe)


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


func _shrink(idx: int) -> void:
	if idx < 0:
		return
	_skel.set_bone_pose_scale(idx, Vector3.ONE * 0.001)
	for child in _skel.get_bone_children(idx):
		_shrink(int(child))


func _shape_toward(mix: Dictionary, key: String, w: float) -> Dictionary:
	var out := {}
	for name in mix:
		var keep := float(mix[name]) * (1.0 - w)
		if keep > 0.002:
			out[name] = keep
	out[key] = float(out.get(key, 0.0)) + w
	return out


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _ease(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _rate(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _paw_tone() -> Color:
	# Fur colour at the model's own wrists, which the fingered hands wear.
	var want := {}
	for bone in ["LeftHand", "RightHand", "LeftForeArm", "RightForeArm"]:
		var idx := _skel.find_bone(bone)
		if idx >= 0:
			want[idx] = bone.ends_with("Hand")
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
				if best < 0 or not want.has(int(binds.get(best, best))) or not want[int(binds.get(best, best))]:
					continue
				var uv: Vector2 = uvs[v]
				var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * size.x), 0, int(size.x) - 1), clampi(int(fposmod(uv.y, 1.0) * size.y), 0, int(size.y) - 1))
				samples.append(image.get_pixelv(px) * mat.albedo_color)
	if samples.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
	samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	var tone: Color = samples[samples.size() / 2]
	tone.a = 1.0
	return tone


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
	handle.position = Vector3(0.0, 0.0, PADDLE * 0.5)
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
	ferrule.position = Vector3(0.0, 0.0, PADDLE - 0.03)
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
