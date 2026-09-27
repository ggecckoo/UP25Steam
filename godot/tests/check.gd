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
	if ace.red() != true or king.red():
		_fail("color")
	if Match.outcome_for(40) != Match.OUTCOME_CAP or Match.outcome_for(26) != Match.OUTCOME_OVER:
		_fail("high outcome")
	if Match.outcome_for(25) != Match.OUTCOME_EXACT or Match.outcome_for(24) != Match.OUTCOME_UNDER:
		_fail("low outcome")
	if Match.draws(Match.OUTCOME_OVER, 2) != [0, 0, 0, 0]:
		_fail("over draws")
	if Match.draws(Match.OUTCOME_UNDER, 2) != [0, 0, 2, 0]:
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
	if Match.pick(rng, hand, false, 25, 0, 1).rank != 12:
		_fail("forced high")
	if Match.pick(rng, hand, false, 0, 0, 1).rank != 12:
		_fail("free high")

	var save_path := "user://2540-check.json"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var game := Match.new()
	game.configure(text, save_path)
	game._rng.seed = 9
	game.new_game()
	if game.count_cards() != 52:
		_fail("deal")
	for _i in 200000:
		if game.phase == Match.PHASE_OVER:
			break
		if game.count_cards() != 52:
			_fail("cards drifted")
		if game.human_turn():
			var index: int = game.players[0].hand.size() - 1 if game.holder == 0 else 0
			if not game.play_card(index):
				_fail("play rejected")
		else:
			game.tick(0.5)
	if game.phase != Match.PHASE_OVER or game.games_finished != 1 or game.can_resume():
		_fail("game over")

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
	if other.phase != Match.PHASE_MENU or not other.can_resume() or other.count_cards() != 52:
		_fail("quit resume")
	var loaded := Match.new()
	loaded.configure(text, save_path)
	if not loaded.can_resume() or loaded.count_cards() != 52:
		_fail("reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("FAIL ", message)
	quit(1)
