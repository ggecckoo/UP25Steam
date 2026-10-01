class_name Match
extends RefCounted

const LIMIT := 25
const CAP := 40
const ROUNDS := 12
const HAND_SIZE := 13
const PENALTY_PER_CARD := 4
const THINK := {1: Vector2(1.9, 3.6), 2: Vector2(1.45, 2.7), 3: Vector2(1.25, 2.9)}
const SUM_DELAY := 1.70
const HOLD_DELAY := 2.90
const FLIP_STEP := 0.36
const REVEAL_LEAD := 1.3
const ROUND_LEAD := 1.9
const DEAL_LEAD := 3.6

const PHASE_MENU := 0
const PHASE_PLAYING := 1
const PHASE_REVEAL := 2
const PHASE_OVER := 3

const OUTCOME_OVER := 0
const OUTCOME_EXACT := 1
const OUTCOME_CAP := 2
const OUTCOME_UNDER := 3

const STAGE_IDLE := 0
const STAGE_WAIT_AI := 1
const STAGE_FLIP := 2
const STAGE_HOLD := 3

const STATUS_NONE := 0
const STATUS_YOU_HOLDER := 1
const STATUS_PLAY := 2
const STATUS_THINKING := 3
const STATUS_REVEALING := 4
const STATUS_OVER := 5
const STATUS_EXACT := 6
const STATUS_CAP := 7
const STATUS_UNDER := 8

var phase := PHASE_MENU
var players: Array = []
var table: Array = []
var holder := 0
var round_no := 1
var outcome := OUTCOME_OVER
var has_outcome := false
var sum_shown := false
var reveal_age := 0.0
var standings: Array = []
var games_finished := 0
var games_won := 0
var sound_on := true
var paused := false
var text: TextBank

var _middle: Array = []
var _rng := RandomNumberGenerator.new()
var _pace := RandomNumberGenerator.new()
var _timer := 0.0
var _stage := STAGE_IDLE
var _status := STATUS_NONE
var _status_name := ""
var _recorded := false
var _can_resume := false
var _applied := false
var _next_id := 0
var save_path := ""


class Card extends RefCounted:
	var id: int
	var rank: int
	var suit: int

	func value() -> int:
		if rank <= 0:
			return 1
		if rank >= 9:
			return 10
		return rank + 1

	func red() -> bool:
		return suit == 1 or suit == 2

	func label() -> String:
		return ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank]

	func symbol() -> String:
		return ["♠", "♥", "♦", "♣"][suit]


class Player extends RefCounted:
	var id: int
	var player_name: String
	var human: bool
	var hand: Array = []

	func penalty() -> int:
		return hand.size() * Match.PENALTY_PER_CARD

	func score() -> int:
		return Match.hand_value(hand) + penalty()


class Played extends RefCounted:
	var card: Card
	var by: int


static func hand_value(hand: Array) -> int:
	var total := 0
	for card in hand:
		total += card.value()
	return total


static func outcome_for(total: int) -> int:
	if total == CAP:
		return OUTCOME_CAP
	if total > LIMIT:
		return OUTCOME_OVER
	if total == LIMIT:
		return OUTCOME_EXACT
	return OUTCOME_UNDER


static func draws(result: int, holder_id: int) -> Array:
	var plan := [0, 0, 0, 0]
	if result == OUTCOME_EXACT or result == OUTCOME_CAP:
		for i in 4:
			if i != holder_id:
				plan[i] = 1
	elif result == OUTCOME_UNDER:
		plan[holder_id] = 2
	return plan


static func pick(rng: RandomNumberGenerator, hand: Array, is_holder: bool, running: int, after: int, round_n: int) -> Card:
	var low: Card = hand[0]
	var high: Card = hand[0]
	for card in hand:
		if card.value() < low.value():
			low = card
		if card.value() >= high.value():
			high = card
	if is_holder:
		return high
	if running + low.value() + after > LIMIT:
		return high
	if running + high.value() + after * 10 <= LIMIT:
		return high
	if rng.randf() < 0.18 + float(round_n) * 0.06:
		return high
	return low


func _init() -> void:
	_rng.randomize()
	_pace.randomize()


func configure(bank: TextBank, path: String) -> void:
	text = bank
	save_path = path
	load_save()


func new_game() -> void:
	paused = false
	_recorded = false
	_applied = false
	var deck := _new_deck()
	var names := [text.t("common.player"), "Sis", "Kaya", "Karaca"]
	players = []
	for i in 4:
		var player := Player.new()
		player.id = i
		player.player_name = names[i]
		player.human = i == 0
		player.hand = deck.slice(i * HAND_SIZE, i * HAND_SIZE + HAND_SIZE)
		players.append(player)
	_sort_hand(players[0].hand)
	_middle = []
	holder = _rng.randi_range(0, 3)
	round_no = 1
	standings = []
	table = []
	_start_round(DEAL_LEAD)


func can_resume() -> bool:
	return _can_resume and players.size() == 4 and round_no >= 1 and round_no <= ROUNDS and phase != PHASE_OVER


func resume() -> void:
	if not can_resume():
		return
	_recorded = false
	_start_round(0.6)


func return_to_menu() -> void:
	paused = false
	phase = PHASE_MENU
	_can_resume = false
	players = []
	table = []
	_middle = []
	standings = []
	_recorded = false
	has_outcome = false
	sum_shown = false
	_save()


func set_paused(value: bool) -> void:
	if phase != PHASE_PLAYING and phase != PHASE_REVEAL:
		return
	paused = value


func set_sound(on: bool) -> void:
	sound_on = on
	_save()


func quit_match() -> void:
	paused = false
	if phase == PHASE_REVEAL:
		_finish_reveal()
		if phase == PHASE_OVER:
			return
		phase = PHASE_MENU
		_can_resume = players.size() == 4
		_save()
	elif phase == PHASE_PLAYING:
		for played in table:
			if played.by >= 0 and played.by < players.size():
				players[played.by].hand.append(played.card)
		if players.size() > 0:
			_sort_hand(players[0].hand)
		table = []
		has_outcome = false
		sum_shown = false
		phase = PHASE_MENU
		_can_resume = players.size() == 4
		_save()
	else:
		phase = PHASE_MENU


func tick(dt: float) -> void:
	if dt <= 0.0 or paused:
		return
	if phase == PHASE_PLAYING:
		_tick_playing(dt)
	elif phase == PHASE_REVEAL:
		_tick_reveal(dt)


func play_card(index: int) -> bool:
	if not human_turn() or index < 0 or index >= players[0].hand.size():
		return false
	_place(0, players[0].hand[index])
	return true


func skip_reveal() -> void:
	if phase != PHASE_REVEAL or paused:
		return
	if not sum_shown:
		_show_sum()
		return
	_finish_reveal()


func human_turn() -> bool:
	if phase != PHASE_PLAYING or paused or table.size() >= 4 or players.is_empty() or not players[0].human:
		return false
	return order()[table.size()] == 0


func acting() -> int:
	if phase != PHASE_PLAYING or paused or table.size() >= 4 or players.size() < 4:
		return -1
	return order()[table.size()]


func order() -> Array:
	var seats := []
	for i in 4:
		seats.append((holder + i) % 4)
	return seats


func table_sum() -> int:
	var total := 0
	for played in table:
		total += played.card.value()
	return total


func turn_token() -> int:
	return round_no * 10 + table.size()


func card_face_up(index: int) -> bool:
	if phase != PHASE_REVEAL:
		return false
	if sum_shown:
		return true
	return reveal_age >= float(index) * FLIP_STEP


func status_text() -> String:
	match _status:
		STATUS_YOU_HOLDER:
			return text.t("feed.youAreHolder")
		STATUS_PLAY:
			return text.t("feed.playCard")
		STATUS_THINKING:
			return text.format_key("feed.thinking %@", [_status_name])
		STATUS_REVEALING:
			return text.t("feed.revealing")
		STATUS_OVER:
			return text.format_key("feed.over %@", [_status_name])
		STATUS_EXACT:
			return text.t("feed.exact")
		STATUS_CAP:
			return text.t("feed.cap")
		STATUS_UNDER:
			return text.format_key("feed.under %@", [_status_name])
	return ""


func verdict_text() -> String:
	if not sum_shown or not has_outcome or holder < 0 or holder >= players.size():
		return ""
	var who: String = players[holder].player_name.to_upper()
	match outcome:
		OUTCOME_OVER:
			return text.format_key("verdict.over %@", [who])
		OUTCOME_EXACT:
			return text.format_key("verdict.exact %@", [who])
		OUTCOME_CAP:
			return text.format_key("verdict.cap %@", [who])
	return text.format_key("verdict.under %@", [who])


func hint_text() -> String:
	if not human_turn():
		return ""
	if holder == 0:
		return text.t("game.hint.holder")
	return text.t("game.hint.other")


func middle() -> Array:
	return _middle


func count_cards() -> int:
	var total := _middle.size() + table.size()
	for player in players:
		total += player.hand.size()
	return total


func _start_round(lead := 0.0) -> void:
	phase = PHASE_PLAYING
	table = []
	has_outcome = false
	sum_shown = false
	reveal_age = 0.0
	_applied = false
	paused = false
	_can_resume = true
	_arm_turn()
	if _stage == STAGE_WAIT_AI:
		_timer += lead
	_save()


func _arm_turn() -> void:
	if players.size() < 4 or table.size() >= 4:
		return
	var seat: int = order()[table.size()]
	if players[seat].hand.is_empty():
		_finish_game()
		return
	if seat == 0:
		_status = STATUS_YOU_HOLDER if holder == 0 else STATUS_PLAY
		_status_name = ""
		_stage = STAGE_IDLE
		return
	_status = STATUS_THINKING
	_status_name = players[seat].player_name
	_stage = STAGE_WAIT_AI
	_timer = _think_time(seat)


func _think_time(seat: int) -> float:
	var span: Vector2 = THINK.get(seat, Vector2(1.2, 2.4))
	var time := _pace.randf_range(span.x, span.y)
	if table.is_empty():
		time += 0.45
	elif table.size() == 3:
		time += 0.25
	if _pace.randf() < 0.18:
		time += _pace.randf_range(0.5, 1.3)
	return time


func _tick_playing(dt: float) -> void:
	if human_turn() or _stage != STAGE_WAIT_AI:
		return
	_timer -= dt
	if _timer > 0.0:
		return
	var seat := acting()
	if seat < 0:
		return
	_play_ai(seat)


func _play_ai(seat: int) -> void:
	var hand: Array = players[seat].hand
	if hand.is_empty():
		_finish_game()
		return
	var card := pick(_rng, hand, seat == holder, table_sum(), 3 - table.size(), round_no)
	_place(seat, card)


func _place(seat: int, card: Card) -> void:
	players[seat].hand = _without_card(players[seat].hand, card.id)
	var played := Played.new()
	played.card = card
	played.by = seat
	table.append(played)
	if table.size() >= 4:
		_begin_reveal()
		return
	_arm_turn()


func _begin_reveal() -> void:
	phase = PHASE_REVEAL
	outcome = outcome_for(table_sum())
	has_outcome = true
	sum_shown = false
	reveal_age = -REVEAL_LEAD
	_stage = STAGE_FLIP
	_timer = SUM_DELAY + REVEAL_LEAD
	_status = STATUS_REVEALING
	_status_name = ""


func _tick_reveal(dt: float) -> void:
	reveal_age += dt
	_timer -= dt
	if _timer > 0.0:
		return
	if _stage == STAGE_FLIP:
		_show_sum()
	elif _stage == STAGE_HOLD:
		_finish_reveal()


func _show_sum() -> void:
	sum_shown = true
	reveal_age = SUM_DELAY
	_stage = STAGE_HOLD
	_timer = HOLD_DELAY
	_set_verdict()


func _set_verdict() -> void:
	if holder >= 0 and holder < players.size():
		_status_name = players[holder].player_name
	match outcome:
		OUTCOME_OVER:
			_status = STATUS_OVER
		OUTCOME_EXACT:
			_status = STATUS_EXACT
		OUTCOME_CAP:
			_status = STATUS_CAP
		_:
			_status = STATUS_UNDER


func _finish_reveal() -> void:
	_apply_round()
	if round_no >= ROUNDS:
		_finish_game()
		return
	round_no += 1
	_start_round(ROUND_LEAD)


func _apply_round() -> void:
	if _applied:
		return
	_applied = true
	if not has_outcome:
		outcome = outcome_for(table_sum())
		has_outcome = true
	var pile: Array = []
	for played in table:
		pile.append(played.card)
	_shuffle(pile)
	pile.append_array(_middle)
	var plan := draws(outcome, holder)
	for seat in order():
		var count: int = plan[seat]
		if count <= 0 or pile.is_empty():
			continue
		count = mini(count, pile.size())
		players[seat].hand.append_array(pile.slice(0, count))
		pile = pile.slice(count)
		if seat == 0:
			_sort_hand(players[seat].hand)
	_middle = pile
	holder = (holder + 1) % 4
	table = []
	has_outcome = false
	sum_shown = false


func _finish_game() -> void:
	if phase == PHASE_OVER:
		return
	for played in table:
		_middle.append(played.card)
	table = []
	phase = PHASE_OVER
	paused = false
	_can_resume = false
	standings = _make_standings()
	if not _recorded:
		_recorded = true
		games_finished += 1
		if standings.size() > 0 and standings[0].id == 0:
			games_won += 1
	_save()


func _make_standings() -> Array:
	var rows: Array = []
	for player in players:
		rows.append({
			"id": player.id,
			"name": player.player_name,
			"cards": player.hand.size(),
			"value": hand_value(player.hand),
			"penalty": player.penalty(),
			"score": player.score(),
		})
	for i in range(1, rows.size()):
		var row = rows[i]
		var j := i
		while j > 0 and _worse(rows[j - 1], row):
			rows[j] = rows[j - 1]
			j -= 1
		rows[j] = row
	return rows


func _worse(a: Dictionary, b: Dictionary) -> bool:
	if a.score != b.score:
		return a.score > b.score
	if a.cards != b.cards:
		return a.cards > b.cards
	return a.id > b.id


func _new_deck() -> Array:
	var deck: Array = []
	for suit in 4:
		for rank in 13:
			deck.append(_mint(rank, suit))
	_shuffle(deck)
	return deck


func _mint(rank: int, suit: int) -> Card:
	_next_id += 1
	var card := Card.new()
	card.id = _next_id
	card.rank = rank
	card.suit = suit
	return card


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


static func _sort_hand(hand: Array) -> void:
	for i in range(1, hand.size()):
		var card: Card = hand[i]
		var j := i
		while j > 0 and _card_less(card, hand[j - 1]):
			hand[j] = hand[j - 1]
			j -= 1
		hand[j] = card


static func _card_less(a: Card, b: Card) -> bool:
	if a.value() != b.value():
		return a.value() < b.value()
	if a.suit != b.suit:
		return a.suit < b.suit
	return a.rank < b.rank


static func _without_card(hand: Array, id: int) -> Array:
	var out: Array = []
	for card in hand:
		if card.id != id:
			out.append(card)
	return out


func _save() -> void:
	if save_path == "":
		return
	var file := {
		"version": 1,
		"gamesFinished": games_finished,
		"gamesWon": games_won,
		"language": text.lang if text != null else "",
		"sound": sound_on,
	}
	var snap := _resume_snapshot()
	if not snap.is_empty():
		file["resume"] = snap
	var path := save_path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return
	handle.store_string(JSON.stringify(file, "  "))


func load_save() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		if text != null:
			text.set_language(text.detect(OS.get_locale()))
		return
	var handle := FileAccess.open(save_path, FileAccess.READ)
	if handle == null:
		return
	var parsed = JSON.parse_string(handle.get_as_text())
	if not parsed is Dictionary:
		return
	games_finished = maxi(0, int(parsed.get("gamesFinished", 0)))
	games_won = clampi(int(parsed.get("gamesWon", 0)), 0, games_finished)
	sound_on = bool(parsed.get("sound", true))
	if text != null:
		var code := str(parsed.get("language", ""))
		if code == "" or not text.set_language(code):
			text.set_language(text.detect(OS.get_locale()))
	if not _restore(parsed.get("resume", null)):
		players = []
		_middle = []
		table = []
		_can_resume = false
		phase = PHASE_MENU


func _resume_snapshot() -> Dictionary:
	if phase == PHASE_OVER or players.size() != 4 or round_no < 1 or round_no > ROUNDS:
		return {}
	var hands: Array = []
	for player in players:
		var copy: Array = []
		for card in player.hand:
			copy.append(card)
		hands.append(copy)
	if table.size() > 0 and not _applied:
		for played in table:
			hands[played.by].append(played.card)
		_sort_hand(hands[0])
	return {
		"round": round_no,
		"holder": holder,
		"names": [players[0].player_name, players[1].player_name, players[2].player_name, players[3].player_name],
		"hands": _encode_cards(hands),
		"middle": _encode_list(_middle if table.is_empty() or _applied else _middle),
	}


func _encode_cards(hands: Array) -> Array:
	var out: Array = []
	for hand in hands:
		out.append(_encode_list(hand))
	return out


func _encode_list(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		out.append({"r": card.rank, "s": card.suit})
	return out


func _restore(file) -> bool:
	if not file is Dictionary:
		return false
	var round_n := int(file.get("round", 0))
	var holder_n := int(file.get("holder", -1))
	var hands = file.get("hands", [])
	if round_n < 1 or round_n > ROUNDS or holder_n < 0 or holder_n > 3 or not hands is Array or hands.size() != 4:
		return false
	var seen := {}
	var restored: Array = []
	var total := 0
	for i in 4:
		var hand: Array = _decode_list(hands[i], seen)
		if hand == null:
			return false
		restored.append(hand)
		total += hand.size()
	var middle: Array = _decode_list(file.get("middle", []), seen)
	if middle == null:
		return false
	total += middle.size()
	if total != 52:
		return false
	var names = file.get("names", [])
	var defaults := [text.t("common.player"), "Sis", "Kaya", "Karaca"]
	players = []
	for i in 4:
		var player := Player.new()
		player.id = i
		player.human = i == 0
		player.player_name = defaults[i]
		if names is Array and names.size() == 4 and str(names[i]) != "":
			player.player_name = str(names[i])
		if i > 0 and player.player_name in ["Kemal", "Nur", "Sabri"]:
			player.player_name = defaults[i]
		player.hand = restored[i]
		players.append(player)
	_sort_hand(players[0].hand)
	_middle = middle
	holder = holder_n
	round_no = round_n
	table = []
	phase = PHASE_MENU
	_can_resume = true
	_applied = false
	has_outcome = false
	sum_shown = false
	return true


func _decode_list(list, seen: Dictionary):
	if not list is Array:
		return null
	var out: Array = []
	for item in list:
		if not item is Dictionary:
			return null
		var rank := int(item.get("r", -1))
		var suit := int(item.get("s", -1))
		if rank < 0 or rank > 12 or suit < 0 or suit > 3:
			return null
		var key := "%d:%d" % [rank, suit]
		if seen.has(key):
			return null
		seen[key] = true
		out.append(_mint(rank, suit))
	return out
