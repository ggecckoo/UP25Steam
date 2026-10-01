extends Node3D

signal sound(kind: String)

const CardArt := preload("res://scripts/card_art.gd")
const SPOT := 0.10
const PICKUP := 0.58
const TOKEN := 0.43
const DEAL_STEP := 0.08
const STACK := 0.00055
const LIFT := 0.0012

var _art: Node
var _actors: Dictionary = {}
var _dirs: Dictionary = {}
var _camera: Camera3D
var _camera_home := Transform3D.IDENTITY
var _felt := 0.713
var _game: Match
var _nodes: Dictionary = {}
var _moves: Dictionary = {}
var _entries: Array = []
var _pile: Array = []
var _jobs: Array = []
var _dealing: Array = []
var _deal_clock := 0.0
var _incoming: Dictionary = {}
var _token: Node3D
var _token_angle := 0.0
var _token_holder := -1
var _glances: Dictionary = {}
var _peeks: Dictionary = {}
var _clock := 0.0
var _lean := 0.0
var _selected := -1
var _rng := RandomNumberGenerator.new()


func setup(actors: Dictionary, dirs: Dictionary, camera: Camera3D, felt_top: float) -> void:
	_actors = actors
	_dirs = dirs
	_camera = camera
	_camera_home = camera.global_transform
	_felt = felt_top
	_rng.randomize()
	_art = CardArt.new()
	add_child(_art)
	_token = _make_token()
	_token.visible = false
	add_child(_token)


func sync(game: Match, in_match: bool, delta: float) -> void:
	_game = game
	_clock += delta
	_step_moves(delta)
	_step_jobs()
	if _art == null or not _art.atlas_ready:
		return
	if not in_match or game.players.size() < 4:
		if not _nodes.is_empty():
			_clear()
		for id in _actors:
			_actors[id].driven = id == 0
			_actors[id].thinking = false
			_actors[id].watching = false
		_token.visible = false
		_lean_camera(false, delta)
		return
	for id in _actors:
		_actors[id].driven = true
	if _stale(game):
		_rebuild(game)
	_step_deal(delta)
	_follow_table(game)
	_follow_reveal(game)
	_reconcile(game)
	_place_token(game, delta)
	_select(game)
	_attention(game)
	_lean_camera(game.phase == Match.PHASE_REVEAL, delta)


func select(index: int) -> void:
	_selected = index


func pick(point: Vector2) -> int:
	if _game == null or not _actors.has(0) or _game.players.is_empty():
		return -1
	var node: Node3D = _actors[0].pick(_camera, point)
	if node == null:
		return -1
	var id := int(node.get_meta("card_id", -1))
	var hand: Array = _game.players[0].hand
	for i in hand.size():
		if int(hand[i].id) == id:
			return i
	return -1


func fan_count(id: int) -> int:
	if not _actors.has(id):
		return 0
	return _actors[id].fan.size()


func busy() -> bool:
	if _art == null or not _art.atlas_ready:
		return true
	if not _dealing.is_empty() or not _jobs.is_empty() or not _incoming.is_empty():
		return true
	for entry in _entries:
		if entry["state"] == "held" or entry["state"] == "flying":
			return true
	for actor in _actors.values():
		if actor.busy():
			return true
	return false


func _stale(game: Match) -> bool:
	var count := 0
	for player in game.players:
		for card in player.hand:
			if not _nodes.has(int(card.id)):
				return true
			count += 1
	for played in game.table:
		if not _nodes.has(int(played.card.id)):
			return true
		count += 1
	for card in game.middle():
		if not _nodes.has(int(card.id)):
			return true
		count += 1
	return count != _nodes.size()


func _clear() -> void:
	for node in _nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	_moves.clear()
	_entries.clear()
	_pile.clear()
	_jobs.clear()
	_dealing.clear()
	_glances.clear()
	_incoming.clear()
	_token_holder = -1
	for actor in _actors.values():
		actor.clear_fan()


func _rebuild(game: Match) -> void:
	_clear()
	var fresh := game.round_no == 1 and game.table.is_empty() and game.middle().is_empty()
	for player in game.players:
		if player.hand.size() != Match.HAND_SIZE:
			fresh = false
	if fresh:
		_lay_deck(game)
		return
	for player in game.players:
		var actor: Node3D = _actors[player.id]
		for card in player.hand:
			var node := _make(card)
			node.global_transform = actor.fan_frame()
			actor.add_to_fan(node)
	for i in game.table.size():
		var played: Match.Played = game.table[i]
		var node := _make(played.card)
		var entry := _entry(played, node)
		node.global_transform = entry["spot"]
		entry["state"] = "landed"
		_entries.append(entry)
	for card in game.middle():
		var node := _make(card)
		node.global_transform = _pile_slot(_pile.size())
		_pile.append(node)


func _lay_deck(game: Match) -> void:
	var order: Array = []
	var seats := game.order()
	seats.push_back(seats.pop_front())
	for k in Match.HAND_SIZE:
		for seat in seats:
			order.append({"card": game.players[seat].hand[k], "seat": seat})
	for i in order.size():
		var node := _make(order[i]["card"])
		var yaw := _rng.randf_range(-0.025, 0.025)
		var pos := Vector3(0.0, _felt + LIFT + STACK * float(order.size() - 1 - i), 0.0)
		node.global_transform = Transform3D(_face_down(Vector3.FORWARD.rotated(Vector3.UP, yaw)), pos)
		_dealing.append({"node": node, "seat": order[i]["seat"]})
	_deal_clock = -0.4


func _make(card) -> Node3D:
	var node: Node3D = _art.make_card(card)
	add_child(node)
	_nodes[int(card.id)] = node
	return node


func _step_deal(delta: float) -> void:
	if _dealing.is_empty():
		return
	_deal_clock += delta
	while not _dealing.is_empty() and _deal_clock >= DEAL_STEP:
		_deal_clock -= DEAL_STEP
		var item: Dictionary = _dealing.pop_front()
		var node: Node3D = item["node"]
		var actor: Node3D = _actors[int(item["seat"])]
		_incoming[node] = true
		sound.emit("deal")
		_move(node, actor.fan_frame(), 0.32, 0.07, func():
			actor.add_to_fan(node)
			_incoming.erase(node)
		)


func _entry(played: Match.Played, node: Node3D) -> Dictionary:
	var dir: Vector3 = _dirs[played.by]
	var side := Vector3.UP.cross(dir)
	var pos := dir * (SPOT + _rng.randf_range(-0.025, 0.03)) + side * _rng.randf_range(-0.045, 0.045)
	pos += Vector3(_rng.randf_range(-0.018, 0.018), 0.0, _rng.randf_range(-0.018, 0.018))
	pos.y = _felt + LIFT
	var top := (-dir).rotated(Vector3.UP, _rng.randf_range(-0.55, 0.55))
	return {
		"id": int(played.card.id),
		"by": played.by,
		"node": node,
		"spot": Transform3D(_face_down(top), pos),
		"spin": _rng.randf_range(-0.45, 0.45),
		"state": "held",
	}


func _follow_table(game: Match) -> void:
	if game.table.size() < _entries.size():
		_sweep(game)
	if _throwing():
		return
	for i in range(_entries.size(), game.table.size()):
		var played: Match.Played = game.table[i]
		var node: Node3D = _nodes.get(int(played.card.id))
		if node == null:
			continue
		var entry := _entry(played, node)
		_entries.append(entry)
		_pile.erase(node)
		_incoming.erase(node)
		_cancel_jobs(node)
		var actor: Node3D = _actors[played.by]
		for other in _actors.values():
			if other != actor:
				other.remove_from_fan(node)
		if actor.fan.has(node):
			actor.throw_card(node, Transform3D(entry["spot"]).origin, func(_card): _launch(entry))
		else:
			actor.cancel(node)
			_launch(entry)
		break


func _launch(entry: Dictionary) -> void:
	var node: Node3D = entry["node"]
	var spot: Transform3D = entry["spot"]
	var by: int = entry["by"]
	entry["state"] = "flying"
	var lay := node.global_transform
	lay.origin.y = spot.origin.y
	var drop := clampf(node.global_position.y - spot.origin.y, 0.0, 0.2)
	_move(node, lay, clampf(drop * 1.4, 0.04, 0.14), 0.0, func():
		sound.emit("card")
		_glance_all(by, spot.origin)
		var dist := node.global_position.distance_to(spot.origin)
		_move(node, spot, clampf(dist * 0.85, 0.14, 0.4), 0.0, func(): entry["state"] = "landed", "out3")
	, "out")


func _follow_reveal(game: Match) -> void:
	if game.phase != Match.PHASE_REVEAL:
		return
	for entry in _entries:
		if entry["state"] == "held" or entry["state"] == "flying":
			return
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		if entry["state"] != "landed" or not game.card_face_up(i):
			continue
		entry["state"] = "open"
		var node: Node3D = entry["node"]
		var from := node.global_transform
		var read := node.global_position - _camera_home.origin
		read.y = 0.0
		var top := Vector3(from.basis.y.x, 0.0, from.basis.y.z)
		var yaw := top.signed_angle_to(read, Vector3.UP) if top.length() > 0.01 and read.length() > 0.01 else 0.0
		_flip(node, from.origin + Vector3.UP * 0.0003, yaw + _rng.randf_range(-0.06, 0.06), 0.4, 0.055, Callable())
		sound.emit("flip")


func _sweep(game: Match) -> void:
	var taken := 0
	var dropped := 0
	for entry in _entries:
		var node: Node3D = entry["node"]
		var owner := _owner_of(game, int(entry["id"]))
		if owner >= 0:
			var delay := 0.2 + 0.32 * float(taken) + _rng.randf_range(0.0, 0.1)
			taken += 1
			_incoming[node] = true
			_later(delay, _hand_over.bind(node, owner), node)
		else:
			var slot := _pile.size()
			_pile.append(node)
			var delay := 0.5 + 0.17 * float(dropped) + _rng.randf_range(0.0, 0.07)
			dropped += 1
			_later(delay, _to_pile.bind(node, slot), node)
	_entries.clear()


func _hand_over(node: Node3D, owner: int) -> void:
	if not is_instance_valid(node):
		_incoming.erase(node)
		return
	var dir: Vector3 = _dirs[owner]
	var side := Vector3.UP.cross(dir)
	var pos := dir * PICKUP + side * _rng.randf_range(-0.05, 0.05)
	pos.y = _felt + LIFT
	var up := node.global_transform.basis.z.y > 0.0
	var top := (-dir).rotated(Vector3.UP, _rng.randf_range(-0.2, 0.2))
	var basis := _face_up(top) if up else _face_down(top)
	var actor: Node3D = _actors[owner]
	_move(node, Transform3D(basis, pos), 0.45, 0.0, func():
		actor.take_card(node, -1 if owner == 0 else -2, func(_card): _incoming.erase(node))
	, "out3")
	sound.emit("deal")


func _to_pile(node: Node3D, slot: int) -> void:
	if not is_instance_valid(node):
		return
	var to := _pile_slot(slot)
	if node.global_transform.basis.z.y > 0.0:
		var top := Vector3(node.global_transform.basis.y.x, 0.0, node.global_transform.basis.y.z)
		var want := Vector3(to.basis.y.x, 0.0, to.basis.y.z)
		var yaw := top.signed_angle_to(want, Vector3.UP) if top.length() > 0.01 else 0.0
		_flip(node, to.origin, yaw, 0.46, 0.05, Callable())
	else:
		_move(node, to, 0.4, 0.03, Callable())
	sound.emit("deal")


func _pile_slot(slot: int) -> Transform3D:
	var yaw := _rng.randf_range(-0.14, 0.14)
	var pos := Vector3(_rng.randf_range(-0.01, 0.01), _felt + LIFT + STACK * float(slot), _rng.randf_range(-0.01, 0.01))
	return Transform3D(_face_down(Vector3.FORWARD.rotated(Vector3.UP, yaw)), pos)


func _owner_of(game: Match, id: int) -> int:
	for player in game.players:
		for card in player.hand:
			if int(card.id) == id:
				return player.id
	return -1


func _throwing() -> bool:
	for actor in _actors.values():
		if actor.busy():
			return true
	for entry in _entries:
		if entry["state"] == "held" or entry["state"] == "flying":
			return true
	return not _moves.is_empty()


func _idle() -> bool:
	if not _moves.is_empty() or busy():
		return false
	for actor in _actors.values():
		if actor.busy():
			return false
	return true


func _reconcile(game: Match) -> void:
	if not _idle():
		return
	for player in game.players:
		var actor: Node3D = _actors[player.id]
		var want: Array = []
		for card in player.hand:
			var node: Node3D = _nodes.get(int(card.id))
			if node == null:
				continue
			want.append(node)
			if not actor.fan.has(node):
				_pile.erase(node)
				actor.add_to_fan(node)
		for node in actor.fan.duplicate():
			if not want.has(node):
				actor.remove_from_fan(node)
		if player.id == 0:
			actor.order_fan(want)
	var middle: Array = []
	for card in game.middle():
		var node: Node3D = _nodes.get(int(card.id))
		if node != null:
			middle.append(node)
	for node in _pile.duplicate():
		if not middle.has(node):
			_pile.erase(node)
	for node in middle:
		if not _pile.has(node):
			for actor in _actors.values():
				actor.remove_from_fan(node)
			_move(node, _pile_slot(_pile.size()), 0.4, 0.03, Callable())
			_pile.append(node)


func _select(game: Match) -> void:
	if not _actors.has(0):
		return
	var node: Node3D = null
	var hand: Array = game.players[0].hand
	if game.human_turn() and _selected >= 0 and _selected < hand.size():
		node = _nodes.get(int(hand[_selected].id))
	_actors[0].selected = node


func _attention(game: Match) -> void:
	var acting := game.acting()
	var reveal := game.phase == Match.PHASE_REVEAL
	var over := game.phase == Match.PHASE_OVER
	var center := Vector3(0.0, _felt, 0.0)
	var eye := _camera.global_position
	var winner := -1
	if over and not game.standings.is_empty():
		winner = int(game.standings[0].id)
	var arriving := not _dealing.is_empty()
	for id in _actors:
		var actor: Node3D = _actors[id]
		actor.watching = reveal or over
		if id == 0:
			actor.thinking = game.human_turn() and not busy()
			continue
		actor.thinking = acting == id and not arriving and not busy()
		var wander := Vector3(sin(_clock * 0.37 + float(id) * 2.1), sin(_clock * 0.23 + float(id)) * 0.4, cos(_clock * 0.29 + float(id) * 1.3)) * 0.035
		var target := center + wander
		var glance: Dictionary = _glances.get(id, {})
		if not glance.is_empty() and _clock >= float(glance["from"]) and _clock < float(glance["until"]):
			target = glance["at"]
		elif reveal:
			target = center + wander
		elif over:
			if winner == id or winner == 0:
				target = eye + wander
			elif _actors.has(winner):
				target = _actors[winner].head_point() + wander
		elif arriving:
			target = actor.fan_frame().origin
		elif acting == id:
			target = actor.fan_frame().origin + actor.fan_frame().basis.y * 0.06
		elif _peeking(id) and not actor.fan.is_empty() and acting != id:
			target = actor.fan_frame().origin + actor.fan_frame().basis.y * 0.05
		elif acting == 0:
			target = eye + wander * 0.6
		elif acting > 0 and acting != id and _actors.has(acting):
			target = _actors[acting].head_point() + wander * 0.6
		actor.look_point = target


func _peeking(id: int) -> bool:
	var peek: Dictionary = _peeks.get(id, {})
	if peek.is_empty() or _clock > float(peek["until"]):
		var start := _clock + _rng.randf_range(3.5, 8.0)
		peek = {"from": start, "until": start + _rng.randf_range(0.7, 1.5)}
		_peeks[id] = peek
	return _clock >= float(peek["from"])


func _glance_all(by: int, point: Vector3) -> void:
	for id in _actors:
		if id == by or id == 0:
			continue
		var start := _clock + _rng.randf_range(0.05, 0.25)
		_glances[id] = {"from": start, "until": start + _rng.randf_range(0.7, 1.1), "at": point}


func _place_token(game: Match, delta: float) -> void:
	if not _dirs.has(game.holder):
		return
	_token.visible = true
	var dir_goal: Vector3 = _dirs[game.holder]
	var goal := atan2(dir_goal.x, dir_goal.z)
	if _token_holder < 0:
		_token_angle = goal
	_token_holder = game.holder
	_token_angle += wrapf(goal - _token_angle, -PI, PI) * (1.0 - exp(-2.6 * delta))
	var dir := Vector3(sin(_token_angle), 0.0, cos(_token_angle))
	var right := Vector3.UP.cross(dir)
	_token.global_position = dir * TOKEN + right * 0.14 + Vector3(0.0, _felt, 0.0)
	_token.rotation = Vector3(0.0, _token_angle, 0.0)


func _lean_camera(lean: bool, delta: float) -> void:
	if _camera == null:
		return
	_lean = lerpf(_lean, 1.0 if lean else 0.0, 1.0 - exp(-2.5 * delta))
	var xf := _camera_home
	xf.origin += xf.basis * (Vector3(0.0, -0.02, -0.06) * _lean)
	xf.basis = xf.basis * Basis(Vector3.RIGHT, -0.07 * _lean)
	_camera.global_transform = xf


func _later(delay: float, job: Callable, node: Node3D = null) -> void:
	_jobs.append({"at": _clock + delay, "job": job, "node": node})


func _cancel_jobs(node: Node3D) -> void:
	var keep: Array = []
	for item in _jobs:
		if item["node"] != node:
			keep.append(item)
	_jobs = keep


func _step_jobs() -> void:
	if _jobs.is_empty():
		return
	var due: Array = []
	var keep: Array = []
	for item in _jobs:
		if _clock >= float(item["at"]):
			due.append(item)
		else:
			keep.append(item)
	_jobs = keep
	for item in due:
		var job: Callable = item["job"]
		if job.is_valid():
			job.call()


func _move(node: Node3D, to: Transform3D, time: float, arc: float, done: Callable, curve := "inout") -> void:
	_moves[node] = {"from": node.global_transform, "to": to, "t": 0.0, "time": maxf(time, 0.01), "arc": arc, "done": done, "curve": curve}


func _flip(node: Node3D, to_origin: Vector3, yaw: float, time: float, arc: float, done: Callable) -> void:
	var from := node.global_transform
	var axis := from.basis.y.normalized()
	var to_basis := Basis(Vector3.UP, yaw) * Basis(axis, PI) * from.basis
	_moves[node] = {
		"from": from,
		"to": Transform3D(to_basis.orthonormalized(), to_origin),
		"t": 0.0,
		"time": time,
		"arc": arc,
		"done": done,
		"curve": "inout",
		"axis": axis,
		"yaw": yaw,
	}


func _step_moves(delta: float) -> void:
	if _moves.is_empty():
		return
	for node in _moves.keys():
		if not is_instance_valid(node):
			_moves.erase(node)
			continue
		var m: Dictionary = _moves[node]
		m["t"] = float(m["t"]) + delta
		var u := clampf(float(m["t"]) / float(m["time"]), 0.0, 1.0)
		var e := _curve(u, str(m["curve"]))
		var from: Transform3D = m["from"]
		var to: Transform3D = m["to"]
		var pos := from.origin.lerp(to.origin, e) + Vector3.UP * (float(m["arc"]) * 4.0 * u * (1.0 - u))
		var basis: Basis
		if m.has("axis"):
			basis = Basis(Vector3.UP, float(m["yaw"]) * e) * Basis(Vector3(m["axis"]), PI * e) * from.basis
		else:
			basis = Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), e))
		node.global_transform = Transform3D(basis, pos)
		if u >= 1.0:
			_moves.erase(node)
			node.global_transform = to
			var done: Callable = m["done"]
			if done.is_valid():
				done.call()


func _curve(u: float, kind: String) -> float:
	match kind:
		"out":
			return u * (2.0 - u)
		"out3":
			var r := 1.0 - u
			return 1.0 - r * r * r
	return u * u * (3.0 - 2.0 * u)


func _face_down(top: Vector3) -> Basis:
	var y := Vector3(top.x, 0.0, top.z).normalized()
	return Basis(y.cross(Vector3.DOWN), y, Vector3.DOWN)


func _face_up(top: Vector3) -> Basis:
	var y := Vector3(top.x, 0.0, top.z).normalized()
	return Basis(y.cross(Vector3.UP), y, Vector3.UP)


func _make_token() -> Node3D:
	var root := Node3D.new()
	root.name = "HolderToken"
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.031
	mesh.height = 0.007
	mesh.radial_segments = 40
	mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.58, 0.28)
	brass.metallic = 0.8
	brass.roughness = 0.34
	mesh.material = brass
	disc.mesh = mesh
	disc.position.y = 0.0035
	root.add_child(disc)
	var mark := Label3D.new()
	mark.text = "25"
	mark.font_size = 72
	mark.pixel_size = 0.00042
	mark.outline_size = 0
	mark.modulate = Color(0.2, 0.12, 0.05)
	mark.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	mark.position.y = 0.0074
	root.add_child(mark)
	return root
