extends Control

const TitleScreen := preload("res://scripts/title_screen.gd")
const TableHud := preload("res://scripts/table_hud.gd")
const HandIcons := preload("res://scripts/hand_icons.gd")
const SAVE_PATH := "user://25-40-save.json"

const SCREEN_MENU := 0
const SCREEN_HOW := 1
const SCREEN_LANG := 2
const SCREEN_PLAY := 3
const SCREEN_PAUSE := 4
const SCREEN_OVER := 5

var text := TextBank.new()
var game: Match
var screen := SCREEN_MENU
var card_index := 0
var queued_play := -1
var turn_token := -1
var how_from := SCREEN_MENU
var last_sig := ""
var sounds: Dictionary = {}
var world: Node3D
var title: Control
var chosen_preset := ""
var port: SubViewport
var _look_held := false
var _debug := false
var _debug_label: Label
var _curtain: ColorRect
var table_hud: Control
var _held_for := 0.0
var hand_icons: Node
var _duel_cue := ""


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	text.load_file("res://locale/L10nCatalog.json")
	game = Match.new()
	game.configure(text, SAVE_PATH)
	theme = _make_theme()
	_add_sound("card", _noise(0.11, 46.0, 0.28, 0.95, 11), -4.0)
	_add_sound("flip", _noise(0.06, 85.0, 0.7, 0.6, 23), -9.0)
	_add_sound("deal", _noise(0.045, 105.0, 0.5, 0.42, 37), -15.0)
	_add_sound("thump", _noise(0.34, 13.0, 0.05, 1.0, 51), 2.0)
	_add_sound("door", _noise(0.42, 10.0, 0.035, 0.95, 67), -3.0)
	_mount_world()
	get_viewport().size_changed.connect(_on_view_resized)
	_rebuild()


func _process(delta: float) -> void:
	# The room holds the match while cards move and while someone walks out.
	var held := game.phase == Match.PHASE_PLAYING or game.phase == Match.PHASE_DUEL
	# Until the croupier has every played card face up, the total waits.
	var turning := game.phase == Match.PHASE_REVEAL and not game.sum_shown
	var wait := world != null and (held or turning) and bool(world.call("busy"))
	# Nothing legitimate keeps the table busy this long (a walk-out takes
	# under ten seconds); if it happens, lay the cards out from the match.
	_held_for = _held_for + delta if wait else 0.0
	if _held_for > 20.0:
		_held_for = 0.0
		world.call("resync", game)
	if not wait:
		game.tick(delta)
	if turning and world != null and not game.sum_shown and bool(world.call("reveal_ready")):
		game.skip_reveal()
		world.call("hurry", false)
	_cue_duel()
	if _curtain != null and world != null and world.has_method("blackout"):
		_curtain.color.a = float(world.call("blackout"))
	if world != null and world.has_method("sync_match"):
		var in_match := screen == SCREEN_PLAY or screen == SCREEN_PAUSE or screen == SCREEN_OVER
		world.call("select_card", card_index if game.human_turn() else -1)
		world.call("sync_match", game, in_match, delta)
	_flush_play()
	_fit_view()
	_sync_title()
	if (screen == SCREEN_PLAY or screen == SCREEN_PAUSE) and game.phase == Match.PHASE_OVER:
		screen = SCREEN_OVER
	elif (screen == SCREEN_PLAY or screen == SCREEN_PAUSE) and game.phase == Match.PHASE_MENU:
		screen = SCREEN_MENU
	if game.human_turn() and game.turn_token() != turn_token:
		turn_token = game.turn_token()
		card_index = game.players[0].hand.size() - 1 if game.holder == 0 else 0
	var sig := _signature()
	if sig != last_sig:
		last_sig = sig
		_rebuild()
	if table_hud != null:
		table_hud.sync(game, screen == SCREEN_PLAY, delta)
	_track_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		var next := DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(next)
		return
	if screen == SCREEN_MENU:
		_input_menu(event)
	elif screen == SCREEN_PLAY:
		_input_play(event)
	else:
		_input_sheet(event)


func _input_menu(event: InputEvent) -> void:
	if title == null:
		return
	if event.is_action_pressed("ui_up"):
		title.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		title.move_focus(1)
	elif event.is_action_pressed("ui_left"):
		title.cycle_pick(-1)
	elif event.is_action_pressed("ui_right"):
		title.cycle_pick(1)
	elif event.is_action_pressed("ui_accept"):
		title.activate_focus()


func _input_sheet(event: InputEvent) -> void:
	# The screens around the game stand on the menu's stage: arrows move
	# along its entries (on the rules they scroll), Enter takes the one in
	# focus and Esc steps back.
	if title == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_menu_activate(_back_id())
	elif event.is_action_pressed("ui_up"):
		if screen == SCREEN_HOW:
			title.scroll(-1)
		else:
			title.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		if screen == SCREEN_HOW:
			title.scroll(1)
		else:
			title.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		title.activate_focus()


func _back_id() -> String:
	match screen:
		SCREEN_PAUSE:
			return "resume"
		SCREEN_OVER:
			return "menu"
	return "back"


func _input_play(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		_open_pause()
		_refresh()
		return
	if game.phase == Match.PHASE_DUEL:
		_input_duel(event)
		return
	var hand_size := 0
	if not game.players.is_empty():
		hand_size = game.players[0].hand.size()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_look_held = false
			return
		if game.phase == Match.PHASE_REVEAL:
			_hurry_reveal()
			_refresh()
			return
		var clicked := _card_at(event.position)
		if clicked >= 0:
			card_index = clicked
			_play(clicked)
			_refresh()
			return
		_look_held = true
		return
	if event is InputEventMouseMotion:
		if _look_held and world != null and world.has_method("add_look"):
			world.call("add_look", event.relative)
			return
		var hovered := _card_at(event.position)
		if hovered >= 0:
			card_index = hovered
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_debug = not _debug
		_track_debug()
		return
	if event is InputEventKey and event.keycode == KEY_C and world != null and world.has_method("set_inspect"):
		world.call("set_inspect", event.pressed)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if world != null and world.has_method("recenter_look"):
			world.call("recenter_look")
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		card_index = wrapi(card_index - 1, 0, maxi(hand_size, 1))
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		card_index = wrapi(card_index + 1, 0, maxi(hand_size, 1))
	elif event.is_action_pressed("ui_accept"):
		if game.phase == Match.PHASE_REVEAL:
			_hurry_reveal()
		else:
			_play(card_index)
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		var digit: int = int(event.keycode) - KEY_1
		if digit >= 0 and digit <= 8 and digit < hand_size:
			card_index = digit
			_play(digit)
			_refresh()


func _input_duel(event: InputEvent) -> void:
	# 1/2/3, or arrows and Enter, or a click on a panel pick a throw; nothing
	# is picked in advance, so every throw is chosen afresh. Otherwise a
	# click or Enter hurries the duel along, and dragging still looks around.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_look_held = event.pressed
		if event.pressed and not game.choosing():
			game.skip_duel()
			_refresh()
		return
	if event is InputEventMouseMotion:
		if _look_held and world != null and world.has_method("add_look"):
			world.call("add_look", event.relative)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var digit: int = int(event.keycode) - KEY_1
		if digit >= 0 and digit <= 2:
			_throw(digit)
			return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		table_hud.move_focus(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		table_hud.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		if game.choosing():
			table_hud.confirm()
		else:
			game.skip_duel()
			_refresh()


func _hurry_reveal() -> void:
	# The croupier works faster; once the cards are up, on to the verdict.
	if world != null and not game.sum_shown and not bool(world.call("reveal_ready")):
		world.call("hurry", true)
		return
	game.skip_reveal()


func _throw(choice: int) -> void:
	if game.choose_throw(choice):
		_on_card_sound("deal")
		table_hud.reset_focus()
	_refresh()


func _cue_duel() -> void:
	# A tap on each word of the chant and a slap when the hands land.
	var cue := ""
	if game.phase == Match.PHASE_DUEL:
		cue = "%d:%d:%d:%d" % [game.hand_no, game.duel_ties, game.duel_stage, game.duel_beat()]
	if cue == _duel_cue:
		return
	_duel_cue = cue
	if game.duel_beat() >= 0:
		_on_card_sound("flip")
	elif game.phase == Match.PHASE_DUEL and game.duel_stage == Match.DUEL_SHOW:
		_on_card_sound("card")


func _track_debug() -> void:
	if _debug_label == null:
		_debug_label = Label.new()
		_debug_label.name = "DebugReadout"
		_debug_label.position = Vector2(16, 78)
		_debug_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78))
		_debug_label.add_theme_font_size_override("font_size", 14)
		add_child(_debug_label)
	_debug_label.visible = _debug and screen == SCREEN_PLAY
	if not _debug_label.visible or world == null:
		return
	var cam := ""
	if world.has_method("camera_debug"):
		cam = str(world.call("camera_debug"))
	var phase := "menu"
	match game.phase:
		Match.PHASE_PLAYING:
			phase = "play"
		Match.PHASE_REVEAL:
			phase = "reveal"
		Match.PHASE_OVER:
			phase = "over"
	var busy := world.has_method("busy") and bool(world.call("busy"))
	_debug_label.text = "phase %s  seat %d  busy %s\n%s\nDrag empty space   C cards   R center" % [
		phase, game.acting(), busy, cam,
	]


func _card_at(point: Vector2) -> int:
	if world == null or not world.has_method("pick_card") or not game.human_turn():
		return -1
	return int(world.call("pick_card", point))


func _play(index: int) -> void:
	if not game.human_turn():
		return
	if world != null and bool(world.call("busy")):
		queued_play = index
		return
	queued_play = -1
	game.play_card(index)


func _flush_play() -> void:
	if queued_play < 0:
		return
	if not game.human_turn() or queued_play >= game.players[0].hand.size():
		queued_play = -1
	elif world == null or not bool(world.call("busy")):
		var index := queued_play
		queued_play = -1
		game.play_card(index)


func _signature() -> String:
	return "%d|%d|%d|%d|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%s" % [
		screen, game.phase, game.round_no, game.table.size(),
		game.sum_shown, game.paused, text.lang, int(game.sound_on),
		game.acting(), game.holder, game.hand_no, game.duel_stage,
		game.duel_beat(), game.duel_throws.size(), 0, game.choosing(),
	]


func _refresh() -> void:
	last_sig = ""


func _mount_world() -> void:
	var view := SubViewportContainer.new()
	view.name = "WorldView"
	view.set_anchors_preset(PRESET_FULL_RECT)
	view.mouse_filter = MOUSE_FILTER_IGNORE
	view.stretch = true
	add_child(view)
	port = SubViewport.new()
	port.name = "View"
	port.size = Vector2i(1280, 800)
	port.own_world_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.handle_input_locally = false
	view.add_child(port)
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.set_anchors_preset(PRESET_FULL_RECT)
	_curtain.mouse_filter = MOUSE_FILTER_IGNORE
	_curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_curtain)
	var packed: PackedScene = load("res://scenes/room_preview.tscn")
	world = packed.instantiate() as Node3D
	world.set("play_mode", true)
	port.add_child(world)
	if world.has_signal("card_sound"):
		world.connect("card_sound", _on_card_sound)
	if world.has_method("player_preset"):
		chosen_preset = str(world.call("player_preset"))
	title = TitleScreen.new()
	title.name = "Title"
	add_child(title)
	title.activated.connect(_menu_activate)
	title.picked.connect(func(preset: String) -> void: chosen_preset = preset)
	title.sound.connect(_on_card_sound)
	hand_icons = HandIcons.new()
	hand_icons.name = "HandIcons"
	add_child(hand_icons)
	table_hud = TableHud.new()
	table_hud.name = "TableHud"
	add_child(table_hud)
	table_hud.setup(text, hand_icons, world)
	table_hud.chosen.connect(_throw)


func _on_view_resized() -> void:
	_fit_view()
	_refresh()


func _fit_view() -> void:
	if port == null:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if size.x < 2 or size.y < 2 or port.size == size:
		return
	port.size = size
	_refresh()


func _rebuild() -> void:
	match screen:
		SCREEN_MENU:
			_build_menu()
		SCREEN_HOW, SCREEN_LANG, SCREEN_PAUSE, SCREEN_OVER:
			_build_sheet()


func _sync_title() -> void:
	if title == null:
		return
	var mode := 0
	if screen == SCREEN_MENU:
		mode = 2
	elif screen != SCREEN_PLAY:
		mode = 1
	title.set_mode(mode)


func _build_menu() -> void:
	if title == null:
		return
	var resume: bool = game.can_resume()
	var entries: Array = []
	if resume:
		entries.append(["continue", text.t("menu.continue"), true])
	entries.append(["new", text.t("menu.newGame") if resume else text.t("menu.sit"), not resume])
	entries.append(["how", text.t("howto.title"), false])
	entries.append(["lang", text.t("language.title"), false])
	entries.append(["quit", text.t("ui.quit"), false])
	var roster: Array = []
	if world != null and world.has_method("roster"):
		roster = world.call("roster")
	title.configure({
		"screen": "menu",
		"lang": text.lang,
		"entries": entries,
		"tagline": text.t("menu.tagline1") + " " + text.t("menu.tagline2"),
		"record": text.t("menu.record"),
		"stats": text.format_key("menu.stats %lld %lld", [game.games_finished, game.games_won]),
		"cast": text.t("menu.cast"),
		"legend": text.t("ui.legend"),
		"roster": roster,
		"picked": chosen_preset,
	})


func _menu_activate(id: String) -> void:
	match id:
		"continue":
			_seat_player()
			game.resume()
			_apply_seat_names()
			_warm_icons()
			screen = SCREEN_PLAY
			card_index = 0
			turn_token = -1
		"new":
			_seat_player()
			_reseat()
			game.new_game()
			_apply_seat_names()
			_warm_icons()
			screen = SCREEN_PLAY
			card_index = 0
			turn_token = -1
		"how":
			how_from = SCREEN_MENU
			screen = SCREEN_HOW
		"lang":
			screen = SCREEN_LANG
		"quit":
			get_tree().quit()
		"back":
			screen = how_from if screen == SCREEN_HOW else SCREEN_MENU
		"resume":
			_resume()
		"pause_how":
			how_from = SCREEN_PAUSE
			screen = SCREEN_HOW
		"sound":
			game.set_sound(not game.sound_on)
		"quit_match":
			game.quit_match()
			screen = SCREEN_OVER if game.phase == Match.PHASE_OVER else SCREEN_MENU
		"again":
			_reseat()
			game.new_game()
			_apply_seat_names()
			_warm_icons()
			screen = SCREEN_PLAY
			card_index = 0
			turn_token = -1
		"menu":
			game.return_to_menu()
			screen = SCREEN_MENU
		_:
			if id.begins_with("lang:"):
				text.set_language(id.substr(5))
				game._save()
				screen = SCREEN_MENU
	_refresh()


func _seat_player() -> void:
	if world == null or chosen_preset == "" or not world.has_method("set_player"):
		return
	if str(world.call("player_preset")) != chosen_preset:
		world.call("set_player", chosen_preset)


func _reseat() -> void:
	# Whoever walked out last sitting comes back for a new one.
	if world != null and world.has_method("reset_seats"):
		world.call("reset_seats")


func _warm_icons() -> void:
	# Each player's hand making the three throws, drawn ahead of any duel.
	if hand_icons == null or world == null or not world.has_method("seat_preset"):
		return
	for id in Match.SEATS:
		hand_icons.icons(str(world.call("seat_preset", id)))


func _apply_seat_names() -> void:
	if world == null or not world.has_method("seat_names") or game.players.size() != 4:
		return
	var names: Array = world.call("seat_names")
	for i in mini(4, names.size()):
		game.players[i].player_name = str(names[i])


func _build_sheet() -> void:
	# The rules, the languages, the pause and the end of a sitting, all on
	# the menu's own stage (title_screen.gd): the same art, logo, type and
	# entries, the players at the table dealt as its character cards.
	if title == null:
		return
	var data := {
		"lang": text.lang,
		"rtl": text.rtl(),
		"legend": text.t("ui.legend"),
	}
	match screen:
		SCREEN_HOW:
			var rules: Array = []
			for i in range(1, 9):
				rules.append(text.t("rules.%d" % i))
			data["screen"] = "how"
			data["tagline"] = text.t("howto.title")
			data["rules"] = rules
			data["entries"] = [["back", text.t("game.back"), true]]
		SCREEN_LANG:
			var entries: Array = []
			for pair in TextBank.LANGUAGES:
				entries.append(["lang:" + str(pair[0]), str(pair[1]), false, pair[0] == text.lang, true])
			entries.append(["back", text.t("game.back"), false, false, true])
			data["screen"] = "lang"
			data["focus"] = maxi(0, TextBank.LANGUAGES.map(func(pair: Array) -> String: return str(pair[0])).find(text.lang))
			data["tagline"] = text.t("language.title")
			data["record"] = text.t("language.hint")
			data["entries"] = entries
		SCREEN_PAUSE:
			var sound := text.t("ui.on") if game.sound_on else text.t("ui.off")
			data["screen"] = "pause"
			data["tagline"] = text.t("pause.title")
			data["record"] = text.format_key("game.hand %lld", [game.hand_no]) + "  ·  " + text.format_key("game.round %lld %lld", [game.round_no, Match.ROUNDS])
			data["entries"] = [
				["resume", text.t("pause.continue"), true],
				["pause_how", text.t("howto.title"), false],
				["sound", text.t("settings.sound") + "  ·  " + sound, false],
				["quit_match", text.t("pause.quit"), false],
			]
			data["cast"] = text.t("pause.table")
			data["roster"] = _table_cards()
		SCREEN_OVER:
			data["screen"] = "over"
			data["tagline"] = _verdict()
			data["record"] = text.format_key("over.hands %lld", [game.hand_no])
			data["entries"] = [["again", text.t("over.newGame"), true], ["menu", text.t("over.menu"), false]]
			data["cast"] = text.t("over.standings")
			data["roster"] = _standing_cards()
	title.configure(data)


func _table_cards() -> Array:
	# Everyone still seated, with the cards they hold; the holder crowned.
	var out: Array = []
	for player in game.players:
		if player.out:
			continue
		out.append({
			"id": _portrait(player.id),
			"name": player.player_name,
			"note": text.format_key("hud.cards %lld", [player.hand.size()]),
			"crowned": player.id == game.holder,
			"pickable": false,
		})
	return out


func _standing_cards() -> Array:
	# The final standings, best first, with score or when they left; the
	# last one at the table crowned.
	var out: Array = []
	for i in game.standings.size():
		var row: Dictionary = game.standings[i]
		var left := int(row.get("left_after", 0))
		out.append({
			"id": _portrait(int(row.id)),
			"name": str(row.name),
			"rank": i + 1,
			"note": text.format_key("hud.points %lld", [int(row.score)]) if left == 0 else text.format_key("over.leftAt %lld", [left]),
			"crowned": i == 0 and game.champion >= 0,
			"pickable": false,
		})
	return out


func _portrait(seat: int) -> String:
	if world != null and world.has_method("seat_preset"):
		return str(world.call("seat_preset", seat))
	return chosen_preset


func _verdict() -> String:
	if game.players.size() == Match.SEATS and game.players[0].out:
		return text.t("over.youLeft")
	if game.champion == 0:
		return text.t("over.youLast")
	if game.champion > 0:
		return text.format_key("over.last %@", [game.players[game.champion].player_name])
	return text.t("over.done")


func _open_pause() -> void:
	if game.phase != Match.PHASE_PLAYING and game.phase != Match.PHASE_REVEAL and game.phase != Match.PHASE_DUEL:
		return
	game.set_paused(true)
	screen = SCREEN_PAUSE


func _resume() -> void:
	game.set_paused(false)
	screen = SCREEN_PLAY


func _make_theme() -> Theme:
	var made := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"SF Pro Text", "Helvetica Neue", "PingFang SC", "Hiragino Sans",
		"Geeza Pro", "Kohinoor Devanagari", "Noto Sans Arabic", "Noto Sans Devanagari",
	])
	made.default_font = font
	made.default_font_size = 20
	return made


func _add_sound(kind: String, stream: AudioStreamWAV, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_polyphony = 4
	add_child(player)
	sounds[kind] = player


func _on_card_sound(kind: String) -> void:
	if not game.sound_on or not sounds.has(kind):
		return
	var player: AudioStreamPlayer = sounds[kind]
	player.pitch_scale = randf_range(0.88, 1.12)
	player.play()


func _noise(seconds: float, decay: float, smooth: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var body := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var env := exp(-t * decay) * minf(1.0, t / 0.0015)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), smooth)
		body = lerpf(body, low, 0.35)
		var sample := clampf((low * 0.6 + body * 0.8) * env * gain, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
