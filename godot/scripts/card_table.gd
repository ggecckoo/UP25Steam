extends Node3D

signal sound(kind: String)

const CardArt := preload("res://scripts/card_art.gd")
const TitleScreen := preload("res://scripts/title_screen.gd")
const PICKUP := 0.58
const TOKEN := 0.43
const DEAL_STEP := 0.08
const STACK := 0.00055
const LIFT := 0.0012
# Thrown cards land in a loose square in the middle, each in the corner on
# its thrower's side, about this far out from the middle each way (corners
# as right-of-centre and toward-the-seated-player signs). Once they are
# turned, the croupier lines them up in one row across the middle, square
# to the seated player and this far apart; drawn cards are slid this far
# out toward whoever draws them, inside the croupier's reach.
const SQUARE := 0.092
const CORNERS := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]
const ROW_GAP := 0.16
const HANDED := 0.42
# A new hand is dealt onto the felt this far out toward each player, a pile
# before each of them, which they pick up once the deal is done.
const DEALT := 0.44

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
# The croupier's deck on the tray, bottom card first.
var _stock: Array = []
var _jobs: Array = []
var _dealing: Array = []
var _deal_clock := 0.0
var _incoming: Dictionary = {}
var _token: Node3D
var _token_holder := -1
var _token_hop := 0.0
var _token_moving := false
var _glances: Dictionary = {}
var _peeks: Dictionary = {}
var _clock := 0.0
var _lean := 0.0
var _selected := -1
var _turn_mark: MeshInstance3D
var _turn_angle := 0.0
var _rng := RandomNumberGenerator.new()
var _dealer: Node3D
var _lined := false
var _layout: Dictionary = {}
var _places: Array = []
var _deal_piles: Dictionary = {}
var _deal_left := 0


func setup(actors: Dictionary, dirs: Dictionary, camera: Camera3D, felt_top: float, dealer: Node3D = null) -> void:
	_dealer = dealer
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
	_turn_mark = _make_turn_mark()
	add_child(_turn_mark)


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
		if _turn_mark != null:
			_turn_mark.visible = false
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
	_place_turn(game, delta)
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
	if _dealer != null and _dealer.busy():
		return true
	for entry in _entries:
		if entry["state"] in ["held", "flying", "turning", "open"]:
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
	_stock.clear()
	_jobs.clear()
	_dealing.clear()
	_glances.clear()
	_incoming.clear()
	_token_holder = -1
	_token_moving = false
	_deal_piles.clear()
	_deal_left = 0
	_lined = false
	_layout.clear()
	_places.clear()
	if _dealer != null:
		_dealer.finish_all()
	for actor in _actors.values():
		actor.clear_fan()


func _rebuild(game: Match) -> void:
	_clear()
	var seats := game.seated()
	var size := Match.hand_for(seats.size())
	var fresh := game.phase == Match.PHASE_PLAYING and game.round_no == 1 and game.table.is_empty()
	fresh = fresh and game.discard().is_empty() and game.stock().size() == Match.DECK_SIZE - seats.size() * size
	for player in game.players:
		if player.hand.size() != (0 if player.out else size):
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
	for card in game.stock():
		var node := _make(card)
		node.global_transform = _stock_slot(_stock.size())
		_stock.append(node)
	for card in game.discard():
		var node := _make(card)
		node.global_transform = _pile_slot(_pile.size())
		_pile.append(node)


func _lay_deck(game: Match) -> void:
	var order: Array = []
	var seats := game.order()
	seats.push_back(seats.pop_front())
	for k in Match.hand_for(seats.size()):
		for seat in seats:
			order.append({"card": game.players[seat].hand[k], "seat": seat})
	# The cards no one is dealt stay at the bottom of the deck: once the
	# deal is done they are the croupier's deck to draw from.
	var kept: Array = []
	for card in game.stock():
		kept.append(_make(card))
	var deck := _deck_spot()
	for i in kept.size():
		var node: Node3D = kept[i]
		var yaw := _rng.randf_range(-0.025, 0.025)
		node.global_transform = Transform3D(_face_down(_toward_camera().rotated(Vector3.UP, yaw)), deck + Vector3.UP * (LIFT + STACK * float(i)))
	for i in order.size():
		var node := _make(order[i]["card"])
		var yaw := _rng.randf_range(-0.025, 0.025)
		var pos := deck + Vector3.UP * (LIFT + STACK * float(kept.size() + order.size() - 1 - i))
		node.global_transform = Transform3D(_face_down(_toward_camera().rotated(Vector3.UP, yaw)), pos)
		_dealing.append({"node": node, "seat": order[i]["seat"]})
	_deal_clock = -0.4
	if _dealer == null:
		_stock = kept
		return
	# The croupier takes the deck up and deals it a card at a time, round the
	# table, onto the felt before each player; with the last card down,
	# everyone picks up their own pile.
	var counts := {}
	_deal_piles.clear()
	_deal_left = _dealing.size()
	var deck_nodes: Array = kept.duplicate()
	for i in range(_dealing.size() - 1, -1, -1):
		deck_nodes.append(_dealing[i]["node"])
	for node in kept:
		_incoming[node] = true
	_dealer.take_deck(deck_nodes)
	for item in _dealing:
		var node: Node3D = item["node"]
		var seat := int(item["seat"])
		var k := int(counts.get(seat, 0))
		counts[seat] = k + 1
		var spot := _deal_spot(seat, k)
		_incoming[node] = true
		_dealer.deal(node, spot.origin, _pitch.bind(node, seat, spot))
	var spots: Array = []
	for i in kept.size():
		spots.append(_stock_slot(i))
	_stock = kept
	_dealer.put_deck(spots, func():
		for node in kept:
			_incoming.erase(node)
	)
	_dealing.clear()


func _deal_spot(seat: int, k: int) -> Transform3D:
	# The k-th card dealt to a seat: face down on the felt before the player,
	# top edge toward the middle, on the pile with a little scatter.
	var dir: Vector3 = _dirs[seat]
	var side := Vector3.UP.cross(dir)
	var pos := dir * (DEALT + _rng.randf_range(-0.007, 0.007)) + side * _rng.randf_range(-0.009, 0.009)
	pos.y = _felt + LIFT + STACK * float(k)
	var top := (-dir).rotated(Vector3.UP, _rng.randf_range(-0.13, 0.13))
	return Transform3D(_face_down(top), pos)


func _pitch(node: Node3D, seat: int, spot: Transform3D) -> void:
	# Off the croupier's fingers flat and low, skimming over the cloth and
	# slowing as it settles onto the pile before its player.
	if not is_instance_valid(node):
		_incoming.erase(node)
		_dealt(seat, null)
		return
	sound.emit("deal")
	var way := _flat(spot.origin - node.global_position).length()
	_move(node, spot, clampf(0.14 + way * 0.28, 0.18, 0.42), 0.012, _dealt.bind(seat, node), "out")


func _dealt(seat: int, node: Node3D) -> void:
	if node != null:
		var pile: Array = _deal_piles.get(seat, [])
		pile.append(node)
		_deal_piles[seat] = pile
	_deal_left -= 1
	if _deal_left > 0:
		return
	if _dealer != null:
		_dealer.hurry = 1.0
	# Everyone reaches for their own pile and lifts it into their hand.
	for owner in _deal_piles:
		var cards: Array = _deal_piles[owner]
		if cards.is_empty() or not _actors.has(owner):
			continue
		var actor: Node3D = _actors[owner]
		var top: Node3D = cards[cards.size() - 1]
		actor.take_card(top, -1, func(_card):
			for card in cards:
				_incoming.erase(card)
		, cards.slice(0, cards.size() - 1))
	_deal_piles.clear()


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
	# Each thrown card has its own corner of the round's square, so none
	# lands on another.
	if not _layout.has(played.by):
		_lay_out()
	return {
		"id": int(played.card.id),
		"by": played.by,
		"node": node,
		"spot": _layout.get(played.by, _row_slot(0, 1, false)),
		"state": "held",
	}


func _lay_out() -> void:
	# Where this round's cards land: a loose square in the middle of the
	# felt, each card in its thrower's corner, turned about the way it was
	# thrown, no two touching; and the places in the row the croupier will
	# line them up in. A layout with two cards touching, or that could not
	# be lined up without pushing one across another, is thrown again; the
	# last try has no scatter at all.
	var seats: Array = _game.seated() if _game != null else _dirs.keys()
	var corners := _corners(seats)
	var toward := _toward_camera()
	var right := (-toward).cross(Vector3.UP).normalized()
	var tries := 24
	for attempt in tries:
		var scatter := 0.0 if attempt == tries - 1 else 1.0
		var drift := (right * _rng.randf_range(-0.012, 0.012) + toward * _rng.randf_range(-0.012, 0.012)) * scatter
		var spots := {}
		var turned: Array = []
		for seat in seats:
			var corner: Vector2 = corners.get(seat, Vector2.ZERO)
			var pos := Vector3(0.0, _felt + LIFT, 0.0) + drift
			pos += right * (corner.x * SQUARE + _rng.randf_range(-0.014, 0.014) * scatter)
			pos += toward * (corner.y * SQUARE + _rng.randf_range(-0.014, 0.014) * scatter)
			var top: Vector3 = (-Vector3(_dirs[seat])).rotated(Vector3.UP, _rng.randf_range(-0.26, 0.26) * scatter)
			spots[seat] = Transform3D(_face_down(top), pos)
			turned.append({"entry": {}, "xf": _turned(spots[seat])})
		_layout = spots
		_places = _row_places(seats.size(), scatter)
		if not _crowded(spots.values(), 0.012) and not _plan(turned, _places).is_empty():
			return


func _corners(seats: Array) -> Dictionary:
	# Each seat's corner of the square: the one on its side of the table, no
	# two sharing; of two ways that fit as well, the one where every card
	# lands to its thrower's right, where a right hand tosses it.
	var toward := _toward_camera()
	var right := (-toward).cross(Vector3.UP).normalized()
	var best := {}
	var best_cost := INF
	for order in _permutations(CORNERS.size()):
		var cost := 0.0
		var pick := {}
		for i in mini(seats.size(), CORNERS.size()):
			var corner: Vector2 = CORNERS[order[i]]
			var dir: Vector3 = _dirs[seats[i]]
			var off := wrapf(atan2(corner.x, corner.y) - atan2(dir.dot(right), dir.dot(toward)), -PI, PI)
			cost += off * off - off * 0.001
			pick[seats[i]] = corner
		if cost < best_cost:
			best_cost = cost
			best = pick
	return best


func _permutations(n: int) -> Array:
	# Every ordering of 0 .. n - 1.
	if n <= 0:
		return [[]]
	var out: Array = []
	for rest in _permutations(n - 1):
		for at in range(rest.size() + 1):
			var order: Array = rest.duplicate()
			order.insert(at, n - 1)
			out.append(order)
	return out


func _overlap(a: Transform3D, b: Transform3D, margin: float) -> bool:
	# Whether two cards lying flat come within `margin` of each other, by
	# their outlines seen from above.
	var half := CardArt.SIZE * 0.5
	var ax := Vector2(a.basis.x.x, a.basis.x.z).normalized()
	var ay := Vector2(a.basis.y.x, a.basis.y.z).normalized()
	var bx := Vector2(b.basis.x.x, b.basis.x.z).normalized()
	var by := Vector2(b.basis.y.x, b.basis.y.z).normalized()
	var gap := Vector2(b.origin.x - a.origin.x, b.origin.z - a.origin.z)
	for axis in [ax, ay, bx, by]:
		var reach_a := half.x * absf(ax.dot(axis)) + half.y * absf(ay.dot(axis))
		var reach_b := half.x * absf(bx.dot(axis)) + half.y * absf(by.dot(axis))
		if absf(gap.dot(axis)) > reach_a + reach_b + margin:
			return false
	return true


func _crowded(spots: Array, margin: float) -> bool:
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if _overlap(spots[i], spots[j], margin):
				return true
	return false


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
	# Off the hand in a low arc, turning as it flies, down a few centimetres
	# short of its place and a short skid onto it, so it never slides
	# across a card already lying on the felt.
	var node: Node3D = entry["node"]
	var spot: Transform3D = entry["spot"]
	var by: int = entry["by"]
	entry["state"] = "flying"
	var way := _flat(spot.origin - node.global_position)
	var skid := minf(0.035, way.length() * 0.3)
	var land := spot.origin - (way.normalized() * skid if way.length() > 0.001 else Vector3.ZERO)
	var spin := Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12))
	var air := clampf(0.12 + way.length() * 0.45, 0.14, 0.38)
	_move(node, Transform3D(spin * spot.basis, land), air, 0.035, func():
		sound.emit("card")
		_glance_all(by, spot.origin)
		_move(node, spot, 0.18, 0.0, func(): entry["state"] = "landed", "out3")
	, "out")


func _follow_reveal(game: Match) -> void:
	if game.phase != Match.PHASE_REVEAL:
		return
	for entry in _entries:
		if entry["state"] == "held" or entry["state"] == "flying":
			return
	if _dealer != null:
		_deal_reveal()
		return
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		if entry["state"] != "landed" or not game.card_face_up(i):
			continue
		entry["state"] = "lined"
		var node: Node3D = entry["node"]
		var from := node.global_transform
		var read := node.global_position - _camera_home.origin
		read.y = 0.0
		var top := Vector3(from.basis.y.x, 0.0, from.basis.y.z)
		var yaw := top.signed_angle_to(read, Vector3.UP) if top.length() > 0.01 and read.length() > 0.01 else 0.0
		_flip(node, from.origin + Vector3.UP * 0.0003, yaw + _rng.randf_range(-0.06, 0.06), 0.4, 0.055, Callable())
		sound.emit("flip")


func _deal_reveal() -> void:
	# The croupier turns the played cards over where they lie, in the order
	# they were played, then lines them up in one row to be read across.
	if _lined or _entries.is_empty():
		return
	_lined = true
	var turned: Array = []
	for entry in _entries:
		var node: Node3D = entry["node"]
		var up := _turned(node.global_transform)
		entry["state"] = "turning"
		_dealer.flip(node, up, func(): entry["state"] = "open")
		turned.append({"entry": entry, "xf": up})
	for step in _line_up(turned):
		var entry: Dictionary = step["entry"]
		var to: Transform3D = step["to"]
		_dealer.slide(entry["node"], [to.origin], to, func(): entry["state"] = "lined")


func _line_up(turned: Array) -> Array:
	# The croupier's moves into the row (see _plan), in the places laid out
	# with the round's square.
	var count := turned.size()
	var places := _places if _places.size() == count else _row_places(count)
	var steps := _plan(turned, places)
	if not steps.is_empty():
		return steps
	# No order clears every card (a layout from before a reload): left to
	# right by where they lie.
	var right := (-_toward_camera()).cross(Vector3.UP).normalized()
	var ranks: Array = range(count)
	ranks.sort_custom(func(a: int, b: int) -> bool:
		return Transform3D(turned[a]["xf"]).origin.dot(right) < Transform3D(turned[b]["xf"]).origin.dot(right)
	)
	for i in count:
		steps.append({"entry": turned[ranks[i]]["entry"], "to": places[i]})
	return steps


func _row_places(count: int, scatter := 1.0) -> Array:
	# The row's places, each a touch off true, as a hand lays cards.
	var places: Array = []
	for i in count:
		var place := _row_slot(i, count, true)
		place.basis = Basis(Vector3.UP, _rng.randf_range(-0.025, 0.025) * scatter) * place.basis
		place.origin += Vector3(_rng.randf_range(-0.004, 0.004), 0.0, _rng.randf_range(-0.004, 0.004)) * scatter
		places.append(place)
	return places


func _plan(turned: Array, places: Array) -> Array:
	# Which place in the row each turned card is pushed to, and in what
	# order, so that none is pushed across another: every way of placing
	# them is tried, a card going only once its straight way there is
	# clear, and the shortest total wins. Empty if no way clears them all.
	var count := turned.size()
	var best: Array = []
	var shortest := INF
	for order in _permutations(count):
		var steps := _clear_steps(turned, order, places)
		if steps.is_empty():
			continue
		var length := 0.0
		for i in count:
			length += _flat(Transform3D(places[order[i]]).origin - Transform3D(turned[i]["xf"]).origin).length()
		if length < shortest:
			shortest = length
			best = steps
	return best


func _clear_steps(turned: Array, order: Array, places: Array) -> Array:
	# A move order for one placement, each card going once nothing lies in
	# its way; empty if the cards would block each other.
	var at: Array = []
	for item in turned:
		at.append(item["xf"])
	var waiting: Array = range(turned.size())
	var steps: Array = []
	while not waiting.is_empty():
		var go := -1
		for k in waiting:
			if _way_clear(k, at, places[order[k]]):
				go = k
				break
		if go < 0:
			return []
		steps.append({"entry": turned[go]["entry"], "to": places[order[go]]})
		at[go] = places[order[go]]
		waiting.erase(go)
	return steps


func _way_clear(k: int, at: Array, to: Transform3D) -> bool:
	# Whether card k can be pushed straight to `to`, turning as it goes,
	# without touching any card where it lies now.
	var from: Transform3D = at[k]
	var turn_from := from.basis.get_rotation_quaternion()
	var turn_to := to.basis.get_rotation_quaternion()
	for step in range(1, 13):
		var u := float(step) / 12.0
		var xf := Transform3D(Basis(turn_from.slerp(turn_to, u)), from.origin.lerp(to.origin, u))
		for j in at.size():
			if j != k and _overlap(xf, at[j], 0.006):
				return false
	return true


func _turned(xf: Transform3D) -> Transform3D:
	# Face up where it lies: over side to side if its top edge already points
	# away from the seated player, end to end if it points at them.
	var keep := xf.basis.y.dot(-_toward_camera()) >= 0.0
	var axis := (xf.basis.y if keep else xf.basis.x).normalized()
	return Transform3D((Basis(axis, PI) * xf.basis).orthonormalized(), xf.origin)


func resync(game: Match) -> void:
	# Lays every card where the match says it is, dropping whatever was in
	# flight; a last resort if an animation never reports back.
	_rebuild(game)


func reveal_ready() -> bool:
	if _entries.is_empty():
		return false
	for entry in _entries:
		if entry["state"] != "lined":
			return false
	return true


func revealed() -> Array:
	# What the seated player can read on the felt: each played card in the
	# order played, who played it, whether it is face up and whether it has
	# been lined up in the row, and where it sits on screen.
	var out: Array = []
	for entry in _entries:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue
		var at := node.global_position + _toward_camera() * 0.088
		var on_screen := Vector2(-1, -1)
		if _camera != null and not _camera.is_position_behind(at):
			on_screen = _camera.unproject_position(at)
		var value := 0
		if _game != null:
			for played in _game.table:
				if int(played.card.id) == int(entry["id"]):
					value = played.card.value()
		var state := str(entry["state"])
		out.append({"id": entry["id"], "by": entry["by"], "value": value, "up": state == "open" or state == "lined", "lined": state == "lined", "screen": on_screen})
	return out


func hurry(on: bool) -> void:
	if _dealer != null:
		_dealer.hurry = 3.0 if on else 1.0


func _row_slot(i: int, count: int, up: bool) -> Transform3D:
	var ahead := -_toward_camera()
	var right := ahead.cross(Vector3.UP).normalized()
	var pos := Vector3(0.0, _felt + LIFT, 0.0) + right * ((float(i) - float(count - 1) * 0.5) * ROW_GAP) - ahead * 0.1
	return Transform3D(_face_up(ahead) if up else _face_down(ahead), pos)


func _toward_camera() -> Vector3:
	var flat := Vector3(_camera_home.origin.x, 0.0, _camera_home.origin.z)
	return flat.normalized() if flat.length() > 0.01 else Vector3.BACK


func _deck_spot() -> Vector3:
	if _dealer == null:
		return Vector3(0.0, _felt, 0.0)
	var tray: Vector3 = _dealer.tray()
	return Vector3(tray.x, _felt, tray.z)


func _pile_center() -> Vector3:
	# Beside the deck, along the rim, out of the way of the play.
	if _dealer == null:
		return Vector3(0.0, _felt, 0.0)
	var deck := _deck_spot()
	var along := Vector3.UP.cross(Vector3(deck.x, 0.0, deck.z).normalized())
	return deck + along * 0.17


func _handed_spot(owner: int, node: Node3D) -> Transform3D:
	var dir: Vector3 = _dirs[owner]
	var side := Vector3.UP.cross(dir)
	var pos := dir * HANDED + side * _rng.randf_range(-0.04, 0.04)
	pos.y = _felt + LIFT
	var top := (-dir).rotated(Vector3.UP, _rng.randf_range(-0.15, 0.15))
	return Transform3D(_face_up(top) if node.global_transform.basis.z.y > 0.0 else _face_down(top), pos)


func _sweep(game: Match) -> void:
	_layout.clear()
	_places.clear()
	if _dealer != null:
		_dealer_sweep(game)
		return
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


func _dealer_sweep(game: Match) -> void:
	# The croupier clears the row onto the pile, a card at a time, nearest it
	# first. Whoever draws then gets the croupier's top cards, face down: it
	# takes its deck up, deals them and puts the rest back down. When the deck
	# ran short, the pile is gathered back into it and washed first.
	var piled: Array = []
	for entry in _entries:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			piled.append(node)
	_entries.clear()
	_lined = false
	var want := _nodes_of(game.stock())
	var drawn: Array = []
	var refill := false
	for node in want:
		if not _stock.has(node):
			refill = true
	# Off the top of the deck, in the order they come off it.
	for i in range(_stock.size() - 1, -1, -1):
		var node: Node3D = _stock[i]
		var owner := _owner_of(game, int(node.get_meta("card_id", -1)))
		if owner >= 0:
			drawn.append({"node": node, "owner": owner})
	for node in _pile + piled:
		var owner := _owner_of(game, int(node.get_meta("card_id", -1)))
		if owner >= 0:
			refill = true
			drawn.append({"node": node, "owner": owner})
	if refill:
		_refill_draw(piled, want, drawn)
		return
	var pile := _pile_center()
	piled.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat(a.global_position - pile).length() < _flat(b.global_position - pile).length()
	)
	var base := _pile.size()
	for k in piled.size():
		var node: Node3D = piled[k]
		var to := _pile_slot(base + k, node.global_transform.basis.z.y > 0.0)
		var rise := to.origin.y - node.global_position.y
		_incoming[node] = true
		_dealer.slide(node, _route(node, to.origin), to, func():
			_pile.append(node)
			_incoming.erase(node)
		, 0.012 + 1.2 * maxf(rise, 0.0))
	if drawn.is_empty():
		return
	# The deck as it lies, bottom card first; the drawn cards are its top.
	_deal_off(_stock.duplicate(), want, drawn)


func _refill_draw(piled: Array, want: Array, drawn: Array) -> void:
	# The deck ran short: the round's cards are raked together at the deck's
	# place and turned face down, the pile and what was left of the deck are
	# pushed over onto them, and the lot is washed round on the felt; then
	# the croupier deals off the top as usual.
	var at := _deck_spot()
	var top := _toward_camera()
	var up_spots: Array = []
	var down_spots: Array = []
	for i in piled.size():
		up_spots.append(Transform3D(_face_up(top), at + Vector3.UP * (LIFT + STACK * float(i))))
		down_spots.append(Transform3D(_face_down(top), at + Vector3.UP * (LIFT + STACK * float(piled.size() - 1 - i))))
	var lying: Array = _pile + _stock
	var all: Array = piled + lying
	for node in all:
		_incoming[node] = true
	if not piled.is_empty():
		_dealer.gather(piled, up_spots)
		_dealer.turn(piled, down_spots)
	if not lying.is_empty():
		var spots: Array = []
		for i in lying.size():
			spots.append(Transform3D(_face_down(top), at + Vector3.UP * (LIFT + STACK * float(piled.size() + i))))
		_dealer.push(lying, [at], spots)
	_pile.clear()
	_stock.clear()
	# Washed: the drawn cards end on top in the order they are dealt, the
	# rest under them in the order the deck now has.
	var order: Array = want.duplicate()
	for k in range(drawn.size() - 1, -1, -1):
		order.append(drawn[k]["node"])
	var washed: Array = []
	for i in order.size():
		var yaw := _rng.randf_range(-0.04, 0.04)
		washed.append(Transform3D(_face_down(top.rotated(Vector3.UP, yaw)), at + Vector3.UP * (LIFT + STACK * float(i))))
	_dealer.wash(order, washed)
	_deal_off(order, want, drawn)


func _deal_off(deck: Array, want: Array, drawn: Array) -> void:
	# The croupier takes `deck` (bottom card first) up from the tray, deals
	# each drawn card off its top face down to its drawer, and puts the rest
	# (`want`) back down where the deck lies.
	for node in deck:
		_incoming[node] = true
	_dealer.take_deck(deck)
	for item in drawn:
		var node: Node3D = item["node"]
		var owner: int = item["owner"]
		var dir: Vector3 = _dirs[owner]
		var side := Vector3.UP.cross(dir)
		var pos := dir * HANDED + side * _rng.randf_range(-0.04, 0.04)
		pos.y = _felt + LIFT
		var to := Transform3D(_face_down((-dir).rotated(Vector3.UP, _rng.randf_range(-0.15, 0.15))), pos)
		_dealer.deal(node, to.origin, _hand_drawn.bind(node, owner, to))
	var spots: Array = []
	for i in want.size():
		spots.append(_stock_slot(i))
	_stock = want.duplicate()
	_dealer.put_deck(spots, func():
		for node in want:
			_incoming.erase(node)
	)


func _nodes_of(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		var node: Node3D = _nodes.get(int(card.id))
		if node != null:
			out.append(node)
	return out


func _stock_slot(i: int) -> Transform3D:
	# The i-th card up the croupier's deck on the tray, face down.
	var yaw := _rng.randf_range(-0.02, 0.02)
	var pos := _deck_spot() + Vector3.UP * (LIFT + STACK * float(i))
	return Transform3D(_face_down(_toward_camera().rotated(Vector3.UP, yaw)), pos)


func _hand_drawn(node: Node3D, owner: int, to: Transform3D) -> void:
	# Off the croupier's fingers low over the cloth onto the felt before its
	# drawer, face down; they pick it up into their hand.
	if not is_instance_valid(node):
		_incoming.erase(node)
		return
	sound.emit("deal")
	var way := _flat(to.origin - node.global_position).length()
	_move(node, to, clampf(0.14 + way * 0.28, 0.18, 0.42), 0.012, func():
		var actor: Node3D = _actors[owner]
		actor.take_card(node, -1 if owner == 0 else -2, func(_card): _incoming.erase(node))
	, "out")


func dealing() -> bool:
	# The croupier is dealing a new hand.
	return _deal_left > 0


func _route(node: Node3D, goal: Vector3) -> Array:
	# Out of the row square to it, on the side the card is headed, far
	# enough to clear the cards still lying there; then straight on.
	var from := node.global_position
	var ahead := -_toward_camera()
	var out := ahead if (goal - from).dot(ahead) >= 0.0 else -ahead
	var exit := from + out * (CardArt.SIZE.y + 0.04)
	return [exit, Vector3(goal.x, from.y, goal.z)]


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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


func _pile_slot(slot: int, up := false) -> Transform3D:
	var yaw := _rng.randf_range(-0.14, 0.14)
	var pos := _pile_center() + Vector3(_rng.randf_range(-0.01, 0.01), LIFT + STACK * float(slot), _rng.randf_range(-0.01, 0.01))
	var top := _toward_camera().rotated(Vector3.UP, PI + yaw)
	return Transform3D(_face_up(top) if up else _face_down(top), pos)


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


func _keeps_fan(game: Match, id: int) -> bool:
	# A player who lost the throw holds their cards until the fist lands.
	var actor: Node3D = _actors[id]
	return game.players[id].out and not actor.gone and not actor.punched


func _reconcile(game: Match) -> void:
	if not _idle():
		return
	var kept: Array = []
	for player in game.players:
		if _keeps_fan(game, player.id):
			kept.append_array(_actors[player.id].fan)
	for player in game.players:
		if _keeps_fan(game, player.id):
			continue
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
	# The croupier's deck and the pile, as the match has them.
	var deck := _nodes_of(game.stock())
	if deck != _stock:
		for i in deck.size():
			var node: Node3D = deck[i]
			if i < _stock.size() and _stock[i] == node:
				continue
			for actor in _actors.values():
				actor.remove_from_fan(node)
			_pile.erase(node)
			_move(node, _stock_slot(i), 0.4, 0.03, Callable())
		_stock = deck
	var played := _nodes_of(game.discard())
	for node in _pile.duplicate():
		if not played.has(node):
			_pile.erase(node)
	for node in played:
		if not _pile.has(node) and not kept.has(node):
			for actor in _actors.values():
				actor.remove_from_fan(node)
			_move(node, _pile_slot(_pile.size()), 0.4, 0.03, Callable())
			_pile.append(node)


func hop() -> void:
	# Everything lying on the felt jumps when a fist hits the table.
	for node in _pile:
		if is_instance_valid(node) and not _moves.has(node):
			var to: Transform3D = node.global_transform
			to.basis = Basis(Vector3.UP, _rng.randf_range(-0.05, 0.05)) * to.basis
			_move(node, to, 0.2, _rng.randf_range(0.006, 0.016), Callable(), "out")
	_token_hop = 1.0


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
	if _dealer != null and not _dealer.busy():
		# Between jobs the croupier watches whoever is to play, or the felt.
		var watch := center
		if acting == 0:
			watch = eye
		elif acting > 0 and _actors.has(acting):
			watch = _actors[acting].head_point()
		_dealer.look_point = _dealer.look_point.lerp(watch, 0.08)
	for id in _actors:
		var actor: Node3D = _actors[id]
		if actor.gone or actor.leaving():
			continue
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
	# The holder's button lies on the felt before the holder, off to their
	# right; when the holder changes the croupier pushes it across to the
	# next one, the way a dealer moves the button on at a card room table.
	if not _dirs.has(game.holder):
		return
	_token.visible = true
	_token_hop = maxf(0.0, _token_hop - delta * 4.5)
	if _token_moving:
		return
	var basis := _token_basis()
	var dir: Vector3 = _dirs[game.holder]
	var spot := dir * TOKEN + Vector3.UP.cross(dir) * 0.14 + Vector3(0.0, _felt, 0.0)
	if _token_holder >= 0 and game.holder != _token_holder and _dealer != null:
		_token_holder = game.holder
		_token_moving = true
		_dealer.slide(_token, [spot], Transform3D(basis, spot), func(): _token_moving = false)
		return
	_token_holder = game.holder
	var jump := 0.014 * sin(PI * (1.0 - _token_hop)) if _token_hop > 0.0 else 0.0
	_token.global_transform = Transform3D(basis, spot + Vector3.UP * jump)


func _token_basis() -> Basis:
	# The crown on the button reads upright from the seated player's chair.
	var toward := _toward_camera()
	return Basis(Vector3.UP, atan2(toward.x, toward.z))


func _place_turn(game: Match, delta: float) -> void:
	if _turn_mark == null:
		return
	var seat := game.acting()
	if seat < 0 or not _dirs.has(seat):
		_turn_mark.visible = false
		return
	_turn_mark.visible = true
	var dir: Vector3 = _dirs[seat]
	var goal := atan2(dir.x, dir.z)
	_turn_angle = lerp_angle(_turn_angle, goal, 1.0 - exp(-3.2 * delta))
	var pulse := 0.86 + 0.14 * sin(_clock * TAU / 1.5)
	var out := Vector3(sin(_turn_angle), 0.0, cos(_turn_angle))
	_turn_mark.global_position = out * 0.62 + Vector3(0.0, _felt + 0.008, 0.0)
	_turn_mark.rotation = Vector3(0.0, _turn_angle, 0.0)
	_turn_mark.scale = Vector3(pulse, 1.0, 1.0)


func _make_turn_mark() -> MeshInstance3D:
	var mark := MeshInstance3D.new()
	mark.name = "TurnMark"
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.006, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.84, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.72, 0.48, 0.16)
	mat.emission_energy_multiplier = 0.4
	mat.roughness = 0.42
	mat.metallic = 0.15
	box.material = mat
	mark.mesh = box
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mark


func _lean_camera(lean: bool, delta: float) -> void:
	_lean = lerpf(_lean, 1.0 if lean else 0.0, 1.0 - exp(-2.5 * delta))
	var room := get_parent()
	if room != null and room.has_method("set_reveal"):
		room.call("set_reveal", _lean)
		return
	if _camera == null:
		return
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
	# The holder's button: an ivory puck like a dealer's button, a gold rim
	# and a gold crown inlaid on top, the crown the screen shows beside the
	# holder's name. It takes the cards' light so the lamp does not burn it.
	var root := Node3D.new()
	root.name = "HolderButton"
	var ivory := (_art.edge_material as ShaderMaterial).duplicate() as ShaderMaterial
	ivory.set_shader_parameter("tint", Color(0.93, 0.89, 0.8))
	var puck := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.037
	mesh.bottom_radius = 0.038
	mesh.height = 0.009
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.material = ivory
	puck.mesh = mesh
	puck.position.y = 0.0045
	root.add_child(puck)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.8, 0.66, 0.4)
	gold.metallic = 0.75
	gold.roughness = 0.38
	gold.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0315
	ring.outer_radius = 0.0348
	ring.rings = 48
	ring.ring_segments = 8
	ring.material = gold
	rim.mesh = ring
	rim.scale = Vector3(1.0, 0.3, 1.0)
	rim.position.y = 0.0091
	root.add_child(rim)
	var crown := MeshInstance3D.new()
	crown.mesh = _crown_mesh(0.041, gold)
	crown.position.y = 0.0092
	root.add_child(crown)
	var garnet := StandardMaterial3D.new()
	garnet.albedo_color = Color(0.62, 0.1, 0.08)
	garnet.roughness = 0.3
	for jewel in TitleScreen.Crown.jewels(Vector2(0.0, 0.003), 0.041):
		var stone := MeshInstance3D.new()
		var bead := CylinderMesh.new()
		bead.top_radius = 0.0025
		bead.bottom_radius = 0.0025
		bead.height = 0.0008
		bead.radial_segments = 12
		bead.rings = 1
		bead.material = garnet
		stone.mesh = bead
		stone.position = Vector3(jewel.x, 0.0096, jewel.y)
		root.add_child(stone)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


func _crown_mesh(width: float, mat: Material) -> ArrayMesh:
	# The screen's crown outline, laid flat: its points away from the
	# seated player once the button is turned to face them.
	var outline := TitleScreen.Crown.points(Vector2(0.0, 0.003), width)
	var order := Geometry2D.triangulate_polygon(outline)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in order:
		verts.append(Vector3(outline[i].x, 0.0, outline[i].y))
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh

