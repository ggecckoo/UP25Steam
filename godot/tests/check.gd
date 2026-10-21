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
	if Match.hand_value([king, ace]) != 11:
		_fail("hand value")
	for rank in 13:
		var want := 1 if rank == 0 else mini(rank + 1, 10)
		if Match.rank_value(rank) != want:
			_fail("rank %d counts %d" % [rank, Match.rank_value(rank)])
	if ace.red() != true or king.red():
		_fail("color")
	if Match.outcome_for(40) != Match.OUTCOME_CAP or Match.outcome_for(26) != Match.OUTCOME_OVER or Match.outcome_for(39) != Match.OUTCOME_OVER:
		_fail("high outcome")
	if Match.outcome_for(25) != Match.OUTCOME_EXACT or Match.outcome_for(24) != Match.OUTCOME_UNDER:
		_fail("low outcome")
	if Match.draws(Match.OUTCOME_OVER, 2) != [0, 0, 0, 0]:
		_fail("over draws")
	if Match.draws(Match.OUTCOME_UNDER, 2) != [0, 0, 2, 0]:
		_fail("under draws")
	if Match.rounds_for(4) != 8 or Match.rounds_for(3) != 6 or Match.rounds_for(2) != 4:
		_fail("rounds by seats")
	if Match.hand_for(4) != 9 or Match.hand_for(3) != 7 or Match.hand_for(2) != 5:
		_fail("hand by seats")
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
	var tens: Array = []
	var nines: Array = []
	var fives: Array = []
	var aces: Array = []
	for _i in 30:
		tens.append(10)
		nines.append(9)
		fives.append(5)
		aces.append(1)
	# The holder plays high; a bot that cannot sink the holder sheds its
	# king, unless the king would make exactly 40; one that can sink, and
	# would otherwise make exactly 25, sinks with its ace; with nothing to
	# lose either way it sheds the king.
	if Match.pick(rng, hand, true, tens, 0, false, 3).rank != 12:
		_fail("holder pick")
	if Match.pick(rng, hand, false, nines, 1, true, 2).rank != 12:
		_fail("forced high")
	if Match.pick(rng, hand, false, tens, 1, true, 2).rank != 0:
		_fail("shed into exactly 40")
	if Match.pick(rng, hand, false, fives, 3, true, 0).rank != 0:
		_fail("sink rather than make 25")
	if Match.pick(rng, hand, false, aces, 3, true, 0).rank != 12:
		_fail("free high")

	if Match.target_for(4) != Vector2i(25, 40) or Match.target_for(3) != Vector2i(18, 30) or Match.target_for(2) != Vector2i(12, 0):
		_fail("targets")
	if Match.target_for(1) != Vector2i(12, 0) or Match.target_for(0) != Vector2i(25, 40):
		_fail("targets past the last seat")
	if Match.outcome_for(18, 18, 30) != Match.OUTCOME_EXACT or Match.outcome_for(30, 18, 30) != Match.OUTCOME_CAP:
		_fail("three seat outcome")
	if Match.outcome_for(19, 18, 30) != Match.OUTCOME_OVER or Match.outcome_for(20, 12, 0) != Match.OUTCOME_OVER or Match.outcome_for(0, 12, 0) != Match.OUTCOME_UNDER:
		_fail("small table over")
	if Match.outcome_for(12, 12, 0) != Match.OUTCOME_EXACT:
		_fail("two seat exact")
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
	if game.count_cards() != 52 or game.stock().size() != 52 - 4 * 9 or not game.discard().is_empty():
		_fail("deal")
	if game.rounds() != 8:
		_fail("four seat rounds")
	_check_draws(text)
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
	# With a limit on throws no sitting runs on: every hand ends in one throw
	# or one forfeit, each seat has DUEL_LIVES throws and three seats can go.
	for seed in range(41, 141):
		var run := Match.new()
		run.configure(text, "")
		run._rng.seed = seed
		run._hands_rng.seed = seed
		run._pace.seed = seed
		run.new_game()
		_sit_out(run, seed)
		if run.hand_no > Match.SEATS * Match.DUEL_LIVES + Match.SEATS - 1:
			_fail("sitting %d ran %d hands" % [seed, run.hand_no])
		for player in run.players:
			if player.duels > Match.DUEL_LIVES:
				_fail("seat %d threw %d times" % [player.id, player.duels])

	# Coming last uses a throw; with none left the seat goes without one.
	var spent := Match.new()
	spent.configure(text, "")
	spent._rng.seed = 7
	spent._hands_rng.seed = 7
	spent.new_game()
	_load_last(spent, 2)
	spent._finish_hand()
	if spent.duel_loser != 2 or spent.duel_forfeit or spent.players[2].duels != 1 or spent.players[2].throws_left() != Match.DUEL_LIVES - 1:
		_fail("first throw not counted")
	spent._clear_duel()
	spent.phase = Match.PHASE_PLAYING
	spent.players[2].duels = Match.DUEL_LIVES
	spent._finish_hand()
	if spent.duel_loser != 2 or not spent.duel_forfeit or spent.choosing() or spent.players[2].duels != Match.DUEL_LIVES:
		_fail("forfeit not opened")
	if spent.duel_heading().find(spent.players[2].player_name) < 0:
		_fail("forfeit heading %s" % spent.duel_heading())
	for _i in 40:
		if spent._settled:
			break
		spent.tick(0.5)
	if not spent.players[2].out or not spent.duel_out or spent.duel_throws.size() != 0 or spent.count_cards() != Match.DECK_SIZE:
		_fail("forfeit did not take the seat")
	# A human with no throws left is out too, without being asked to throw.
	var you := Match.new()
	you.configure(text, "")
	you._rng.seed = 8
	you.new_game()
	_load_last(you, 0)
	you.players[0].duels = Match.DUEL_LIVES
	you._finish_hand()
	if you.duel_loser != 0 or not you.duel_forfeit or you.choosing():
		_fail("human forfeit")
	you.skip_duel()
	if not you.players[0].out or you.phase == Match.PHASE_DUEL and you.duel_stage != Match.DUEL_AFTER:
		_fail("human forfeit skip")
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
			if duel.players[last].hand.size() != 0 or duel.count_cards() != Match.DECK_SIZE:
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
	if small.order().has(1) or small.order().size() != 3 or small.limit() != 18 or small.cap() != 30 or small.rounds() != 6:
		_fail("three seat table")
	if small.players[1].hand.size() != 0 or small.players[0].hand.size() != 7 or small.stock().size() != 52 - 21 or small.count_cards() != Match.DECK_SIZE:
		_fail("three seat deal")
	if small.hint_text() != "" and small.hint_text().find("25") >= 0:
		_fail("hint still says 25")
	if small._scaled(text.t("game.hint.holder")).find("18") < 0:
		_fail("scaled hint")
	text.set_language("tr")
	if small._scaled("25'in üstüne, 25'i geç, tam 40") != "18'in üstüne, 18'i geç, tam 30":
		_fail("turkish endings %s" % small._scaled("25'in üstüne, 25'i geç, tam 40"))
	small.players[2].out = true
	small.exits.append(2)
	small._deal()
	if small.limit() != 12 or small.cap() != 0 or small.rounds() != 4 or small.players[0].hand.size() != 5:
		_fail("two seat table")
	if small._scaled("25'in üstüne, 25'i geç") != "12'nin üstüne, 12'yi geç":
		_fail("turkish endings at two %s" % small._scaled("25'in üstüne, 25'i geç"))

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
	if other.phase != Match.PHASE_MENU or not other.can_resume() or other.count_cards() != Match.DECK_SIZE:
		_fail("quit resume")
	var loaded := Match.new()
	loaded.configure(text, save_path)
	if not loaded.can_resume() or loaded.count_cards() != Match.DECK_SIZE or loaded.stock().size() != other.stock().size():
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
	if not back.can_resume() or not back.players[3].out or back.seated().size() != 3 or back.count_cards() != Match.DECK_SIZE:
		_fail("reload empty seat")
	back.resume()
	if back.phase != Match.PHASE_PLAYING or back.order().has(3) or back.limit() != 18 or back.hand_no != 2:
		_fail("resume empty seat")
	back.players[1].duels = 1
	back._finish_hand()
	var owed := [back.duel_loser, back.duel_winner]
	var used := []
	for player in back.players:
		used.append(player.duels)
	if back.phase != Match.PHASE_DUEL or owed.has(3):
		_fail("duel at three seats")
	back.quit_match()
	var again := Match.new()
	again.configure(text, save_path)
	again.resume()
	if again.phase != Match.PHASE_DUEL or again.duel_loser != owed[0] or again.duel_winner != owed[1]:
		_fail("resume owed throw")
	for player in again.players:
		if player.duels != int(used[player.id]):
			_fail("resume lost the throws used: %s" % [used])
	# A forfeit owed when the game was left is still a forfeit.
	again.players[again.duel_loser].duels = Match.DUEL_LIVES
	again.duel_forfeit = true
	again.quit_match()
	var forfeit_back := Match.new()
	forfeit_back.configure(text, save_path)
	forfeit_back.resume()
	if not forfeit_back.duel_forfeit or forfeit_back.choosing():
		_fail("resume forfeit")
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
				if player.hand.size() != (0 if player.out else Match.hand_for(seats.size())):
					_fail("hand %d dealt %d to seat %d" % [game.hand_no, player.hand.size(), player.id])
			if game.stock().size() != Match.DECK_SIZE - seats.size() * Match.hand_for(seats.size()) or not game.discard().is_empty() or game.players[game.holder].out:
				_fail("deal at %d seats" % seats.size())
		if (game.phase == Match.PHASE_PLAYING or game.phase == Match.PHASE_REVEAL) and game.round_no > game.rounds():
			_fail("round %d of %d" % [game.round_no, game.rounds()])
		if game.phase == Match.PHASE_DUEL:
			for player in game.players:
				if not player.out and player.hand.is_empty():
					_fail("seat %d played its hand out" % player.id)
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


func _check_draws(text: TextBank) -> void:
	# Drawn cards come off the top of the croupier's deck; the round's cards
	# are played out onto the pile; a deck that runs short has the pile
	# shuffled back in first. No card is ever lost or doubled.
	var game := Match.new()
	game.configure(text, "")
	game._rng.seed = 21
	game.new_game()
	game.holder = 1
	for seat in game.order():
		game.table.append(_played(game.players[seat].hand.pop_back(), seat))
	var row: Array = []
	for played in game.table:
		row.append(played.card.id)
	var top: Array = [game.stock()[game.stock().size() - 1].id, game.stock()[game.stock().size() - 2].id]
	game.outcome = Match.OUTCOME_UNDER
	game.has_outcome = true
	game._apply_round()
	var got: Array = []
	for card in game.players[1].hand:
		got.append(card.id)
	if not got.has(top[0]) or not got.has(top[1]) or game.players[1].hand.size() != 10:
		_fail("under did not draw the deck's top two")
	for id in row:
		if not _ids(game.discard()).has(id):
			_fail("round card %d not on the pile" % id)
	if game.count_cards() != Match.DECK_SIZE:
		_fail("cards lost drawing")
	# Down to one card: the pile goes back in before three draw.
	while game.stock().size() > 1:
		game.discard().append(game.stock().pop_back())
	var holder := game.holder
	for seat in game.order():
		game.table.append(_played(game.players[seat].hand.pop_back(), seat))
	var before := {}
	for player in game.players:
		before[player.id] = player.hand.size()
	game.outcome = Match.OUTCOME_EXACT
	game.has_outcome = true
	game._applied = false
	game._apply_round()
	for player in game.players:
		var want: int = before[player.id] + (0 if player.id == holder else 1)
		if player.hand.size() != want:
			_fail("refill draw for seat %d" % player.id)
	if not game.discard().is_empty() or game.count_cards() != Match.DECK_SIZE:
		_fail("refill left %d on the pile" % game.discard().size())
	var seen := {}
	for card in game.middle():
		seen[card.id] = true
	for player in game.players:
		for card in player.hand:
			if seen.has(card.id):
				_fail("card %d twice" % card.id)
			seen[card.id] = true
	# A bot sees no face-down card: what it weighs is every card but its own
	# hand and the pile.
	var unseen: Array = game._unseen_by(2)
	if unseen.size() != Match.DECK_SIZE - game.players[2].hand.size() - game.discard().size():
		_fail("bot sees %d cards" % (Match.DECK_SIZE - unseen.size()))


func _played(card: Match.Card, by: int) -> Match.Played:
	var played := Match.Played.new()
	played.card = card
	played.by = by
	return played


func _ids(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		out.append(card.id)
	return out


func _load_last(game: Match, seat: int) -> void:
	# Hands most of everyone else's cards to `seat`, so it comes last.
	for player in game.players:
		if player.id == seat or player.out:
			continue
		while player.hand.size() > 2:
			game.players[seat].hand.append(player.hand.pop_back())


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	print("FAIL ", message)
