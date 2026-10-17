class_name Match
extends RefCounted

const LIMIT := 30
const CAP := 80
const SEATS := 4
# Limit and cap by how many players are still seated. With fewer cards a
# round, 30 would leave the holder short nearly every time and 80 could never
# be reached; these keep the four-seat mix of outcomes on a total the cards
# can actually hit, and the cap stays "every card a King".
const TARGETS := {4: Vector2i(LIMIT, CAP), 3: Vector2i(23, 60), 2: Vector2i(14, 40)}
const ROUNDS := 8
const HAND_SIZE := 7
const DECK_SIZE := 28
const PENALTY_PER_CARD := 4
const THINK := {1: Vector2(1.9, 3.6), 2: Vector2(1.45, 2.7), 3: Vector2(1.25, 2.9)}
const SUM_DELAY := 1.70
const HOLD_DELAY := 2.90
const FLIP_STEP := 0.36
const REVEAL_LEAD := 1.3
const ROUND_LEAD := 1.9
const DEAL_LEAD := 3.6
# After each hand the last-placed player throws rock-paper-scissors against
# the winner: the hand's result on show, three beats of the chant before both
# hands come down, the throws on show, and a pause after (the room holds the
# match while a loser walks out).
const DUEL_LEAD := 3.4
const CHANT_BEAT := 0.5
const SHOW_HOLD := 2.4
const TIE_HOLD := 1.6
const AFTER_HOLD := 1.4

const PHASE_MENU := 0
const PHASE_PLAYING := 1
const PHASE_REVEAL := 2
const PHASE_OVER := 3
const PHASE_DUEL := 4

const DUEL_INTRO := 0
const DUEL_CHOOSE := 1
const DUEL_CHANT := 2
const DUEL_SHOW := 3
const DUEL_AFTER := 4

const ROCK := 0
const PAPER := 1
const SCISSORS := 2
const THROW_KEYS := ["rps.rock", "rps.paper", "rps.scissors"]

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
var hand_no := 1
var exits: Array = []
var champion := -1
var duel_loser := -1
var duel_winner := -1
var duel_stage := DUEL_INTRO
var duel_age := 0.0
var duel_throws: Dictionary = {}
var duel_out := false
var duel_ties := 0

var _middle: Array = []
var _rng := RandomNumberGenerator.new()
var _pace := RandomNumberGenerator.new()
# Throws come from their own generator, drawn afresh for every throw, so a
# tie never carries anyone's pick into the next one.
var _hands_rng := RandomNumberGenerator.new()
var _timer := 0.0
var _stage := STAGE_IDLE
var _status := STATUS_NONE
var _status_name := ""
var _recorded := false
var _can_resume := false
var _applied := false
var _next_id := 0
var _pick := -1
var _settled := false
# What a resumed match picks up with: "" mid-hand, "duel" when the throw is
# still owed, "next" when it was thrown and the next hand is due.
var _pending := ""
var save_path := ""


class Card extends RefCounted:
	var id: int
	var rank: int
	var suit: int

	func value() -> int:
		match rank:
			0:
				return 1
			2:
				return 3
			4:
				return 5
			6:
				return 7
			8:
				return 9
			10:
				return 15
			12:
				return 20
			_:
				return rank + 1

	func red() -> bool:
		return suit == 1 or suit == 2

	func label() -> String:
		match rank:
			0:
				return "A"
			2:
				return "3"
			4:
				return "5"
			6:
				return "7"
			8:
				return "9"
			10:
				return "J"
			12:
				return "K"
			_:
				return str(rank)

	func symbol() -> String:
		return ["♠", "♥", "♦", "♣"][suit]


class Player extends RefCounted:
	var id: int
	var player_name: String
	var human: bool
	var hand: Array = []
	var out := false
	var left_after := 0

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


static func outcome_for(total: int, limit := LIMIT, cap := CAP) -> int:
	if total == cap:
		return OUTCOME_CAP
	if total > limit:
		return OUTCOME_OVER
	if total == limit:
		return OUTCOME_EXACT
	return OUTCOME_UNDER


static func target_for(seats: int) -> Vector2i:
	# With no match laid out there is no smaller table; a table down to its
	# last player keeps the two-seat pair until the sitting closes.
	if seats <= 0:
		return TARGETS[SEATS]
	return TARGETS.get(clampi(seats, 2, SEATS), TARGETS[SEATS])


static func draws(result: int, holder_id: int, seats: Array = [0, 1, 2, 3]) -> Array:
	var plan := [0, 0, 0, 0]
	if result == OUTCOME_EXACT or result == OUTCOME_CAP:
		for i in seats:
			if i != holder_id:
				plan[i] = 1
	elif result == OUTCOME_UNDER:
		plan[holder_id] = 1
	return plan


static func beats(a: int, b: int) -> bool:
	return (a - b + 3) % 3 == 1


static func pick(rng: RandomNumberGenerator, hand: Array, is_holder: bool, running: int, after: int, round_n: int, limit := LIMIT) -> Card:
	var low: Card = hand[0]
	var high: Card = hand[0]
	for card in hand:
		if card.value() < low.value():
			low = card
		if card.value() >= high.value():
			high = card
	if is_holder:
		return high
	if running + low.value() + after > limit:
		return high
	if running + high.value() + after * 20 <= limit:
		return high
	if rng.randf() < 0.18 + float(round_n) * 0.06:
		return high
	return low


func _init() -> void:
	_rng.randomize()
	_pace.randomize()
	_hands_rng.randomize()


func configure(bank: TextBank, path: String) -> void:
	text = bank
	save_path = path
	load_save()


func new_game() -> void:
	paused = false
	_recorded = false
	_applied = false
	var names := [text.t("common.player"), "Sis", "Kaya", "Karaca"]
	players = []
	for i in SEATS:
		var player := Player.new()
		player.id = i
		player.player_name = names[i]
		player.human = i == 0
		players.append(player)
	hand_no = 1
	exits = []
	champion = -1
	_clear_duel()
	_deal()
	_start_round(DEAL_LEAD)


func can_resume() -> bool:
	return _can_resume and players.size() == SEATS and round_no >= 1 and round_no <= ROUNDS and phase != PHASE_OVER


func resume() -> void:
	if not can_resume():
		return
	_recorded = false
	match _pending:
		"duel":
			_open_duel(duel_loser, duel_winner)
		"next":
			_next_hand()
		_:
			_start_round(0.6)


func return_to_menu() -> void:
	paused = false
	phase = PHASE_MENU
	_can_resume = false
	players = []
	table = []
	_middle = []
	standings = []
	exits = []
	champion = -1
	_clear_duel()
	_recorded = false
	has_outcome = false
	sum_shown = false
	_save()


func set_paused(value: bool) -> void:
	if phase != PHASE_PLAYING and phase != PHASE_REVEAL and phase != PHASE_DUEL:
		return
	paused = value


func set_sound(on: bool) -> void:
	sound_on = on
	_save()


func quit_match() -> void:
	paused = false
	if phase == PHASE_REVEAL:
		_finish_reveal()
	elif phase == PHASE_PLAYING:
		for played in table:
			if played.by >= 0 and played.by < players.size():
				players[played.by].hand.append(played.card)
		if players.size() > 0:
			_sort_hand(players[0].hand)
		table = []
		has_outcome = false
		sum_shown = false
	elif phase != PHASE_DUEL:
		phase = PHASE_MENU
		return
	if phase == PHASE_DUEL and _settled and _decided():
		_close_session()
	if phase == PHASE_OVER:
		return
	phase = PHASE_MENU
	_can_resume = players.size() == SEATS
	_save()


func tick(dt: float) -> void:
	if dt <= 0.0 or paused:
		return
	if phase == PHASE_PLAYING:
		_tick_playing(dt)
	elif phase == PHASE_REVEAL:
		_tick_reveal(dt)
	elif phase == PHASE_DUEL:
		_tick_duel(dt)


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
	if phase != PHASE_PLAYING or paused or players.is_empty() or not players[0].human or players[0].out:
		return false
	var seats := order()
	if table.size() >= seats.size():
		return false
	return seats[table.size()] == 0


func acting() -> int:
	if phase != PHASE_PLAYING or paused or players.size() < SEATS:
		return -1
	var seats := order()
	if table.size() >= seats.size():
		return -1
	return seats[table.size()]


func order() -> Array:
	var seats := []
	for i in SEATS:
		var seat := (holder + i) % SEATS
		if seat < players.size() and not players[seat].out:
			seats.append(seat)
	return seats


func seated() -> Array:
	var seats := []
	for player in players:
		if not player.out:
			seats.append(player.id)
	return seats


func limit() -> int:
	return target_for(seated().size()).x


func cap() -> int:
	return target_for(seated().size()).y


func table_sum() -> int:
	var total := 0
	for played in table:
		total += played.card.value()
	return total


func turn_token() -> int:
	return hand_no * 1000 + round_no * 10 + table.size()


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
			return _scaled(text.t("feed.exact"))
		STATUS_CAP:
			return _scaled(text.t("feed.cap"))
		STATUS_UNDER:
			return text.format_key("feed.under %@", [_status_name])
	return ""


func verdict_text() -> String:
	if not sum_shown or not has_outcome or holder < 0 or holder >= players.size():
		return ""
	var who: String = players[holder].player_name.to_upper()
	match outcome:
		OUTCOME_OVER:
			return _scaled(text.format_key("verdict.over %@", [who]))
		OUTCOME_EXACT:
			return _scaled(text.format_key("verdict.exact %@", [who]))
		OUTCOME_CAP:
			return _scaled(text.format_key("verdict.cap %@", [who]))
	return text.format_key("verdict.under %@", [who])


func hint_text() -> String:
	if not human_turn():
		return ""
	if holder == 0:
		return _scaled(text.t("game.hint.holder"))
	return _scaled(text.t("game.hint.other"))


func _scaled(line: String) -> String:
	# The catalog spells out the four-seat 30 and 80 in every language; a
	# smaller table plays to its own pair.
	var goal := target_for(seated().size())
	if goal == TARGETS[SEATS]:
		return line
	line = line.replace(str(CAP), str(goal.y)).replace(str(LIMIT), str(goal.x))
	if text != null and text.lang == "tr":
		# Turkish case endings follow the last vowel of the spoken number.
		for number in [goal.x, goal.y]:
			var vowel := _tr_vowel(number)
			for old in ["ı", "i", "u", "ü"]:
				line = line.replace("%d'%s" % [number, old], "%d'%s" % [number, vowel])
	return line


static func _tr_vowel(number: int) -> String:
	var units := ["", "i", "i", "ü", "ü", "i", "ı", "i", "i", "u"]
	var tens := ["ü", "u", "i", "u", "ı", "i", "ı", "i", "i", "ı"]
	if number % 10 != 0:
		return units[number % 10]
	return tens[(number / 10) % 10]


func human_dueling() -> bool:
	return phase == PHASE_DUEL and (duel_loser == 0 or duel_winner == 0)


func choosing() -> bool:
	return human_dueling() and not paused and (duel_stage == DUEL_INTRO or duel_stage == DUEL_CHOOSE)


func duel_beat() -> int:
	# Chant word on show: 0 rock, 1 paper, 2 scissors.
	if phase != PHASE_DUEL or duel_stage != DUEL_CHANT:
		return -1
	return clampi(int(duel_age / CHANT_BEAT), 0, 2)


func throw_name(choice: int) -> String:
	if choice < ROCK or choice > SCISSORS:
		return ""
	return text.t(THROW_KEYS[choice])


func duel_heading() -> String:
	if phase != PHASE_DUEL or duel_loser < 0 or duel_winner < 0:
		return ""
	var loser: String = players[duel_loser].player_name
	var winner: String = players[duel_winner].player_name
	match duel_stage:
		DUEL_INTRO, DUEL_CHOOSE:
			if duel_ties > 0:
				return text.t("duel.again")
			return text.format_key("duel.handOver %@ %@", [winner, loser])
		DUEL_CHANT:
			var word := throw_name(duel_beat())
			return word + ("!" if duel_beat() == SCISSORS else "…")
		DUEL_SHOW:
			if not _settled:
				return text.t("duel.tie")
			if duel_out:
				return text.t("duel.youLost") if duel_loser == 0 else text.format_key("duel.lost %@", [loser])
			return text.t("duel.youStay") if duel_loser == 0 else text.format_key("duel.stays %@", [loser])
		DUEL_AFTER:
			if duel_out:
				return text.t("duel.youLeave") if duel_loser == 0 else text.format_key("duel.leaves %@", [loser])
			return text.t("duel.youStay") if duel_loser == 0 else text.format_key("duel.stays %@", [loser])
	return ""


func duel_detail() -> String:
	if phase != PHASE_DUEL or duel_loser < 0 or duel_winner < 0:
		return ""
	var loser: String = players[duel_loser].player_name
	var winner: String = players[duel_winner].player_name
	match duel_stage:
		DUEL_INTRO, DUEL_CHOOSE:
			if duel_loser == 0:
				return text.format_key("duel.youLast %@", [winner])
			if duel_winner == 0:
				return text.format_key("duel.youFirst %@", [loser])
			return text.format_key("duel.stakes %@ %@", [loser, winner])
		DUEL_SHOW, DUEL_AFTER:
			if duel_throws.size() == 2:
				return "%s · %s     %s · %s" % [
					loser, throw_name(int(duel_throws[duel_loser])),
					winner, throw_name(int(duel_throws[duel_winner])),
				]
	return ""


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
	var seats := order()
	if players.size() < SEATS or table.size() >= seats.size():
		return
	var seat: int = seats[table.size()]
	if players[seat].hand.is_empty():
		_finish_hand()
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
		_finish_hand()
		return
	var after := order().size() - 1 - table.size()
	var card := pick(_rng, hand, seat == holder, table_sum(), after, round_no, limit())
	_place(seat, card)


func _place(seat: int, card: Card) -> void:
	players[seat].hand = _without_card(players[seat].hand, card.id)
	var played := Played.new()
	played.card = card
	played.by = seat
	table.append(played)
	if table.size() >= order().size():
		_begin_reveal()
		return
	_arm_turn()


func _begin_reveal() -> void:
	phase = PHASE_REVEAL
	outcome = outcome_for(table_sum(), limit(), cap())
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
		_finish_hand()
		return
	round_no += 1
	_start_round(ROUND_LEAD)


func _apply_round() -> void:
	if _applied:
		return
	_applied = true
	if not has_outcome:
		outcome = outcome_for(table_sum(), limit(), cap())
		has_outcome = true
	var pile: Array = []
	for played in table:
		pile.append(played.card)
	_shuffle(pile)
	pile.append_array(_middle)
	var plan := draws(outcome, holder, seated())
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
	holder = _next_seat(holder)
	table = []
	has_outcome = false
	sum_shown = false


func _next_seat(seat: int) -> int:
	for step in range(1, SEATS + 1):
		var next := (seat + step) % SEATS
		if not players[next].out:
			return next
	return seat


func _deal() -> void:
	var deck := _new_deck()
	var seats := seated()
	for player in players:
		player.hand = []
	for k in seats.size():
		players[seats[k]].hand = deck.slice(k * HAND_SIZE, k * HAND_SIZE + HAND_SIZE)
	_sort_hand(players[0].hand)
	_middle = deck.slice(seats.size() * HAND_SIZE)
	holder = seats[_rng.randi_range(0, seats.size() - 1)]
	round_no = 1
	standings = []
	table = []


func _finish_hand() -> void:
	if phase == PHASE_DUEL or phase == PHASE_OVER:
		return
	for played in table:
		_middle.append(played.card)
	table = []
	paused = false
	has_outcome = false
	sum_shown = false
	standings = _make_standings()
	if standings.size() < 2:
		_close_session()
		return
	_open_duel(int(standings[standings.size() - 1].id), int(standings[0].id))
	_save()


func _open_duel(loser: int, winner: int) -> void:
	phase = PHASE_DUEL
	duel_loser = loser
	duel_winner = winner
	duel_throws = {}
	duel_out = false
	duel_ties = 0
	_pick = -1
	_settled = false
	_pending = "duel"
	_can_resume = true
	_status = STATUS_NONE
	if standings.is_empty():
		standings = _make_standings()
	_duel_stage(DUEL_INTRO, DUEL_LEAD)


func _clear_duel() -> void:
	duel_loser = -1
	duel_winner = -1
	duel_stage = DUEL_INTRO
	duel_age = 0.0
	duel_throws = {}
	duel_out = false
	duel_ties = 0
	_pick = -1
	_settled = false
	_pending = ""


func _duel_stage(stage: int, wait: float) -> void:
	duel_stage = stage
	duel_age = 0.0
	_timer = wait


func _tick_duel(dt: float) -> void:
	duel_age += dt
	if duel_stage == DUEL_CHOOSE:
		return
	_timer -= dt
	if _timer > 0.0:
		return
	match duel_stage:
		DUEL_INTRO:
			_duel_ready()
		DUEL_CHANT:
			_throw()
		DUEL_SHOW:
			if _settled:
				_duel_stage(DUEL_AFTER, AFTER_HOLD)
			else:
				duel_throws = {}
				_duel_ready()
		DUEL_AFTER:
			_close_duel()


func choose_throw(choice: int) -> bool:
	if not choosing() or choice < ROCK or choice > SCISSORS:
		return false
	_pick = choice
	_duel_stage(DUEL_CHANT, CHANT_BEAT * 3.0)
	return true


func skip_duel() -> void:
	if phase != PHASE_DUEL or paused:
		return
	if duel_stage == DUEL_INTRO:
		_duel_ready()
	elif duel_stage == DUEL_SHOW or (duel_stage == DUEL_AFTER and not duel_out):
		_timer = 0.0
		_tick_duel(0.001)


func _duel_ready() -> void:
	if human_dueling() and _pick < 0:
		_duel_stage(DUEL_CHOOSE, 0.0)
	else:
		_duel_stage(DUEL_CHANT, CHANT_BEAT * 3.0)


func _throw() -> void:
	# The seated player's pick is never read for the other hand.
	var thrown := {}
	for seat in [duel_loser, duel_winner]:
		thrown[seat] = _pick if seat == 0 and _pick >= 0 else _hands_rng.randi_range(ROCK, SCISSORS)
	_pick = -1
	duel_throws = thrown
	if int(thrown[duel_loser]) == int(thrown[duel_winner]):
		duel_ties += 1
		_duel_stage(DUEL_SHOW, TIE_HOLD)
		return
	_settle(beats(int(thrown[duel_winner]), int(thrown[duel_loser])))
	_duel_stage(DUEL_SHOW, SHOW_HOLD)


func _settle(loser_out: bool) -> void:
	# Only the last-placed player has anything at stake; the winner of the
	# hand keeps the seat whatever they throw.
	_settled = true
	duel_out = loser_out
	if loser_out:
		var gone: Player = players[duel_loser]
		gone.out = true
		gone.left_after = hand_no
		_middle.append_array(gone.hand)
		gone.hand = []
		exits.append(duel_loser)
	if _decided():
		_pending = ""
		_can_resume = false
		_record()
	else:
		_pending = "next"
	_save()


func _decided() -> bool:
	return players.is_empty() or players[0].out or seated().size() <= 1


func _close_duel() -> void:
	if _decided():
		_close_session()
		return
	_next_hand()


func _next_hand() -> void:
	hand_no += 1
	_clear_duel()
	_deal()
	_start_round(DEAL_LEAD)


func _close_session() -> void:
	if phase == PHASE_OVER:
		return
	phase = PHASE_OVER
	paused = false
	_can_resume = false
	_record()
	standings = _final_standings()
	_save()


func _record() -> void:
	if _recorded:
		return
	_recorded = true
	var seats := seated()
	champion = seats[0] if seats.size() == 1 else -1
	games_finished += 1
	if champion == 0:
		games_won += 1


func _final_standings() -> Array:
	# Whoever is still seated, by the last hand, then the ones who walked
	# out, latest first.
	var rows := _make_standings()
	for i in range(exits.size() - 1, -1, -1):
		var player: Player = players[int(exits[i])]
		rows.append({
			"id": player.id,
			"name": player.player_name,
			"cards": 0,
			"value": 0,
			"penalty": 0,
			"score": 0,
			"left_after": player.left_after,
		})
	return rows


func _make_standings() -> Array:
	var rows: Array = []
	for player in players:
		if player.out:
			continue
		rows.append({
			"id": player.id,
			"name": player.player_name,
			"cards": player.hand.size(),
			"value": hand_value(player.hand),
			"penalty": player.penalty(),
			"score": player.score(),
			"left_after": 0,
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
	for rank in [0, 2, 4, 6, 8, 10, 12]:
		for suit in 4:
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
		"version": 2,
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
	if phase == PHASE_OVER or players.size() != SEATS or round_no < 1 or round_no > ROUNDS or _decided():
		return {}
	var hands: Array = []
	var out: Array = []
	for player in players:
		var copy: Array = []
		for card in player.hand:
			copy.append(card)
		hands.append(copy)
		out.append(player.left_after if player.out else 0)
	if table.size() > 0 and not _applied:
		for played in table:
			hands[played.by].append(played.card)
		_sort_hand(hands[0])
	var snap := {
		"round": round_no,
		"holder": holder,
		"names": [players[0].player_name, players[1].player_name, players[2].player_name, players[3].player_name],
		"hands": _encode_cards(hands),
		"middle": _encode_list(_middle if table.is_empty() or _applied else _middle),
		"hand": hand_no,
		"out": out,
		"exits": exits.duplicate(),
		"pending": _pending,
	}
	if _pending == "duel":
		snap["duel"] = [duel_loser, duel_winner]
	return snap


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
	if total != DECK_SIZE:
		return false
	# Saves from before seats could empty have none of these.
	var out = file.get("out", [0, 0, 0, 0])
	var pending := str(file.get("pending", ""))
	var duel = file.get("duel", [])
	if not out is Array or out.size() != SEATS or int(out[0]) != 0 or not pending in ["", "duel", "next"]:
		return false
	var left := 0
	for i in SEATS:
		if int(out[i]) > 0:
			left += 1
			if not restored[i].is_empty() or holder_n == i:
				return false
	if left > SEATS - 2:
		return false
	if pending == "duel":
		if not duel is Array or duel.size() != 2:
			return false
		for seat in duel:
			if int(seat) < 0 or int(seat) >= SEATS or int(out[int(seat)]) > 0:
				return false
		if int(duel[0]) == int(duel[1]):
			return false
	var names = file.get("names", [])
	var defaults := [text.t("common.player"), "Sis", "Kaya", "Karaca"]
	players = []
	for i in SEATS:
		var player := Player.new()
		player.id = i
		player.human = i == 0
		player.player_name = defaults[i]
		if names is Array and names.size() == SEATS and str(names[i]) != "":
			player.player_name = str(names[i])
		if i > 0 and player.player_name in ["Kemal", "Nur", "Sabri"]:
			player.player_name = defaults[i]
		player.hand = restored[i]
		player.out = int(out[i]) > 0
		player.left_after = int(out[i])
		players.append(player)
	_sort_hand(players[0].hand)
	_middle = middle
	holder = holder_n
	round_no = round_n
	hand_no = maxi(1, int(file.get("hand", 1)))
	exits = []
	var order_out = file.get("exits", [])
	if order_out is Array:
		for seat in order_out:
			if int(seat) > 0 and int(seat) < SEATS and players[int(seat)].out and not exits.has(int(seat)):
				exits.append(int(seat))
	for player in players:
		if player.out and not exits.has(player.id):
			exits.append(player.id)
	champion = -1
	standings = []
	_clear_duel()
	_pending = pending
	if pending == "duel":
		duel_loser = int(duel[0])
		duel_winner = int(duel[1])
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
