extends SceneTree

func _init() -> void:
	var text := TextBank.new()
	text.load_file("res://locale/L10nCatalog.json")
	if not text.set_language("en"):
		_fail("language")
	if text.format_key("game.round %lld %lld", [1, 12]) != "ROUND 1 / 12":
		_fail(text.format_key("game.round %lld %lld", [1, 12]))
	text.set_language("tr")
	if text.format_key("game.round %lld %lld", [1, 12]) != "TUR 1 / 12":
		_fail("turkish round")
	if text.t("ui.quit") != "Çıkış":
		_fail("quit label")

	var king := Match.Card.new()
	king.rank = 12
	king.suit = 0
	var ace := Match.Card.new()
	ace.rank = 0
	ace.suit = 1
	if Match.hand_value([king, ace]) != 21:
		_fail("hand value")
	if ace.red() != true or king.red():
		_fail("color")
	if Match.outcome_for(80) != Match.OUTCOME_CAP or Match.outcome_for(31) != Match.OUTCOME_OVER:
		_fail("high outcome")
	if Match.outcome_for(30) != Match.OUTCOME_EXACT or Match.outcome_for(29) != Match.OUTCOME_UNDER:
		_fail("low outcome")
	if Match.draws(Match.OUTCOME_OVER, 2) != [0, 0, 0, 0]:
		_fail("over draws")
	if Match.draws(Match.OUTCOME_UNDER, 2) != [0, 0, 1, 0]:
		_fail("under draws")
	if Match.draws(Match.OUTCOME_EXACT, 2) != [1, 1, 0, 1]:
		_fail("exact draws")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var low := Match.Card.new()
	low.id = 1
	low.rank = 0
	low.suit = 0
	var high := Match.Card.new()
	high.id = 2
	high.rank = 12
	high.suit = 1
	var hand := [low, high]
	if Match.pick(rng, hand, true, 0, 3, 1).rank != 12:
		_fail("holder pick")
	if Match.pick(rng, hand, false, 30, 0, 1).rank != 12:
		_fail("forced high")
	if Match.pick(rng, hand, false, 0, 0, 1).rank != 12:
		_fail("free high")

	if Match.target_for(4) != Vector2i(30, 80) or Match.target_for(3) != Vector2i(23, 60) or Match.target_for(2) != Vector2i(14, 40):
		_fail("targets")
	if Match.target_for(1) != Vector2i(14, 40) or Match.target_for(0) != Vector2i(30, 80):
		_fail("targets past the last seat")
	if Match.outcome_for(23, 23, 60) != Match.OUTCOME_EXACT or Match.outcome_for(60, 23, 60) != Match.OUTCOME_CAP:
		_fail("three seat outcome")
	if Match.outcome_for(24, 23, 60) != Match.OUTCOME_OVER or Match.outcome_for(30, 14, 40) != Match.OUTCOME_OVER:
		_fail("small table over")
	if Match.draws(Match.OUTCOME_EXACT, 2, [0, 2, 3]) != [1, 0, 0, 1] or Match.draws(Match.OUTCOME_CAP, 0, [0, 3]) != [0, 0, 0, 1]:
		_fail("draws skip empty seats")
	if not Match.beats(Match.ROCK, Match.SCISSORS) or not Match.beats(Match.SCISSORS, Match.PAPER) or not Match.beats(Match.PAPER, Match.ROCK):
		_fail("beats")
	for a in 3:
		if Match.beats(a, a):
			_fail("beats itself")

	var save_path := "user://2540-check.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var game := Match.new()
	game.configure(text, save_path)
	game._rng.seed = 9
	game._hands_rng.seed = 9
	game.new_game()
	if game.count_cards() != 28:
		_fail("deal")
	_sit_out(game, 0)
	if game.phase != Match.PHASE_OVER or game.games_finished != 1 or game.can_resume():
		_fail("game over")
	if game.champion < 0 and not game.players[0].out:
		_fail("sitting ended with nobody out")

	# Many sittings: every throw settles the way the rules say, only the
	# last-placed player can lose a seat, and a smaller table plays to its
	# own targets.
	var outcomes := {}
	var exits_seen := 0
	var champions := 0
	for seed in range(1, 41):
		var run := Match.new()
		run.configure(text, "")
		run._rng.seed = seed
		run._hands_rng.seed = seed
		run._pace.seed = seed
		run.new_game()
		exits_seen += _sit_out(run, seed, outcomes)
		if run.champion >= 0:
			champions += 1
		if run.phase != Match.PHASE_OVER:
			_fail("sitting %d never ended" % seed)
	if exits_seen == 0 or champions == 0:
		_fail("no one ever left")
	for seats in [3, 2]:
		if int(outcomes.get(seats, 0)) == 0:
			_fail("never played with %d seats" % seats)

	# The hand's winner keeps the seat whatever they throw; the last-placed
	# player loses it only by losing the throw.
	var stayed := 0
	var left := 0
	for seed in range(1, 61):
		var duel := Match.new()
		duel.configure(text, "")
		duel._rng.seed = seed
		duel._hands_rng.seed = seed
		duel.new_game()
		var last := 0 if seed % 2 == 0 else 3
		var first := 2 if last == 0 else 0
		duel._open_duel(last, first)
		for _i in 200:
			if duel._settled or duel.phase != Match.PHASE_DUEL:
				break
			if duel.choosing():
				duel.choose_throw(seed % 3)
			else:
				duel.tick(0.25)
		var lost := Match.beats(int(duel.duel_throws[first]), int(duel.duel_throws[last]))
		if duel.players[first].out:
			_fail("winner lost the seat")
		if duel.players[last].out != lost or duel.duel_out != lost:
			_fail("throw %d settled wrong" % seed)
		if lost:
			left += 1
			if duel.players[last].hand.size() != 0 or duel.count_cards() != 28:
				_fail("cards of a leaver")
		else:
			stayed += 1
	if stayed == 0 or left == 0:
		_fail("duel never went both ways")

	var small := Match.new()
	small.configure(text, "")
	small._rng.seed = 4
	small.new_game()
	small.players[1].out = true
	small.exits.append(1)
	small._deal()
	small._start_round(0.0)
	if small.order().has(1) or small.order().size() != 3 or small.limit() != 23 or small.cap() != 60:
		_fail("three seat table")
	if small.players[1].hand.size() != 0 or small.middle().size() != 7 or small.count_cards() != 28:
		_fail("three seat deal")
	if small.hint_text() != "" and small.hint_text().find("30") >= 0:
		_fail("hint still says 30")
	if small._scaled(text.t("game.hint.holder")).find("23") < 0:
		_fail("scaled hint")
	text.set_language("tr")
	if small._scaled("30'in üstüne, 30'i geç, tam 80") != "23'ün üstüne, 23'ü geç, tam 60":
		_fail("turkish endings %s" % small._scaled("30'in üstüne, 30'i geç, tam 80"))

	var other := Match.new()
	other.configure(text, save_path)
	other._rng.seed = 3
	other.new_game()
	for _i in 80:
		if other.table.size() > 0:
			break
		if other.human_turn():
			other.play_card(0)
		else:
			other.tick(2.0)
	if other.table.is_empty():
		_fail("no table card")
	other.quit_match()
	if other.phase != Match.PHASE_MENU or not other.can_resume() or other.count_cards() != 28:
		_fail("quit resume")
	var loaded := Match.new()
	loaded.configure(text, save_path)
	if not loaded.can_resume() or loaded.count_cards() != 28:
		_fail("reload")

	# An empty seat and an owed throw both survive a quit.
	var thinned := Match.new()
	thinned.configure(text, save_path)
	thinned._rng.seed = 5
	thinned.new_game()
	thinned.players[3].out = true
	thinned.players[3].left_after = 1
	thinned.exits.append(3)
	thinned.hand_no = 2
	thinned._deal()
	thinned._start_round(0.0)
	thinned.quit_match()
	var back := Match.new()
	back.configure(text, save_path)
	if not back.can_resume() or not back.players[3].out or back.seated().size() != 3 or back.count_cards() != 28:
		_fail("reload empty seat")
	back.resume()
	if back.phase != Match.PHASE_PLAYING or back.order().has(3) or back.limit() != 23 or back.hand_no != 2:
		_fail("resume empty seat")
	back._finish_hand()
	var owed := [back.duel_loser, back.duel_winner]
	if back.phase != Match.PHASE_DUEL or owed.has(3):
		_fail("duel at three seats")
	back.quit_match()
	var again := Match.new()
	again.configure(text, save_path)
	again.resume()
	if again.phase != Match.PHASE_DUEL or again.duel_loser != owed[0] or again.duel_winner != owed[1]:
		_fail("resume owed throw")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if _failed:
		quit(1)
		return
	print("OK")
	quit(0)


var _failed := false


func _sit_out(game: Match, seed: int, outcomes: Dictionary = {}) -> int:
	# Plays a whole sitting; returns how many walked out.
	var dealt := -1
	var rounds := {}
	var throws := {}
	for i in 400000:
		if game.phase == Match.PHASE_OVER:
			break
		if game.count_cards() != Match.DECK_SIZE:
			_fail("cards drifted")
			break
		var seats := game.seated()
		if game.phase == Match.PHASE_PLAYING and game.hand_no != dealt:
			dealt = game.hand_no
			for player in game.players:
				if player.hand.size() != (0 if player.out else Match.HAND_SIZE):
					_fail("hand %d dealt %d to seat %d" % [game.hand_no, player.hand.size(), player.id])
			if game.middle().size() != Match.DECK_SIZE - seats.size() * Match.HAND_SIZE or game.players[game.holder].out:
				_fail("deal at %d seats" % seats.size())
		var key := game.hand_no * 100 + game.round_no
		if game.phase == Match.PHASE_REVEAL and not rounds.has(key):
			rounds[key] = true
			outcomes[seats.size()] = int(outcomes.get(seats.size(), 0)) + 1
			if game.table.size() != seats.size() or game.outcome != Match.outcome_for(game.table_sum(), game.limit(), game.cap()):
				_fail("round at %d seats" % seats.size())
		if game.phase == Match.PHASE_DUEL and game.duel_stage == Match.DUEL_SHOW and not throws.has(key * 10 + game.duel_ties):
			throws[key * 10 + game.duel_ties] = true
			var loser := game.duel_loser
			var winner := game.duel_winner
			if int(game.standings[0].id) != winner or int(game.standings[game.standings.size() - 1].id) != loser:
				_fail("duel between the wrong seats")
			var a := int(game.duel_throws[loser])
			var b := int(game.duel_throws[winner])
			if game.players[winner].out or (a != b and game.players[loser].out != Match.beats(b, a)) or (a == b and game.players[loser].out):
				_fail("throw settled wrong")
		if game.human_turn():
			var index: int = game.players[0].hand.size() - 1 if game.holder == 0 else 0
			if not game.play_card(index):
				_fail("play rejected")
		elif game.choosing():
			game.choose_throw((i + seed) % 3)
		else:
			game.tick(0.5)
	for seat in game.exits:
		if not game.players[seat].out or game.players[seat].hand.size() != 0:
			_fail("exit %d still holds a seat" % seat)
	if game.seated().size() + game.exits.size() != Match.SEATS:
		_fail("seats and exits disagree")
	return game.exits.size()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	print("FAIL ", message)
