extends Control

const TableScene = preload("res://scripts/table_view.gd")
const SAVE_PATH := "user://25-40-save.json"

const FELT := Color("0A3B2E")
const FELT_LIT := Color("1E6E52")
const PANEL := Color("082C22")
const BRASS := Color("C9A44C")
const BRASS_HI := Color("F0DA9E")
const IVORY := Color("F7F2E4")
const IVORY_DIM := Color(0.97, 0.95, 0.89, 0.75)
const LAC := Color("B3302B")
const INK := Color("1B1712")

const SCREEN_MENU := 0
const SCREEN_HOW := 1
const SCREEN_LANG := 2
const SCREEN_PLAY := 3
const SCREEN_PAUSE := 4
const SCREEN_OVER := 5

var text := TextBank.new()
var game: Match
var screen := SCREEN_MENU
var focus_index := 0
var card_index := 0
var turn_token := -1
var how_from := SCREEN_MENU
var last_sig := ""
var heard_table := 0
var heard_phase := 0
var buttons: Array = []
var card_player: AudioStreamPlayer
var reveal_player: AudioStreamPlayer


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	text.load_file("res://locale/L10nCatalog.json")
	game = Match.new()
	game.configure(text, SAVE_PATH)
	theme = _make_theme()
	card_player = AudioStreamPlayer.new()
	reveal_player = AudioStreamPlayer.new()
	card_player.stream = _tone(880.0, 0.07)
	reveal_player.stream = _tone(620.0, 0.16)
	add_child(card_player)
	add_child(reveal_player)
	_rebuild()


func _process(delta: float) -> void:
	game.tick(delta)
	if game.sound_on:
		if game.phase == Match.PHASE_REVEAL and heard_phase != Match.PHASE_REVEAL:
			reveal_player.play()
		elif game.table.size() > heard_table:
			card_player.play()
	heard_phase = game.phase
	heard_table = game.table.size()
	if (screen == SCREEN_PLAY or screen == SCREEN_PAUSE) and game.phase == Match.PHASE_OVER:
		screen = SCREEN_OVER
		focus_index = 0
	elif (screen == SCREEN_PLAY or screen == SCREEN_PAUSE) and game.phase == Match.PHASE_MENU:
		screen = SCREEN_MENU
		focus_index = 0
	if game.human_turn() and game.turn_token() != turn_token:
		turn_token = game.turn_token()
		card_index = game.players[0].hand.size() - 1 if game.holder == 0 else 0
	var sig := _signature()
	if sig != last_sig:
		last_sig = sig
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		var next := DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(next)
		return
	if screen == SCREEN_HOW:
		_input_how(event)
		return
	if screen == SCREEN_PLAY:
		_input_play(event)
		return
	if event.is_action_pressed("ui_cancel"):
		if screen == SCREEN_PAUSE:
			_resume()
		elif screen == SCREEN_LANG:
			screen = SCREEN_MENU
			focus_index = 0
		elif screen == SCREEN_PLAY:
			_open_pause()
		elif screen == SCREEN_OVER:
			_to_menu()
		_refresh()
		return
	if event.is_action_pressed("ui_up"):
		_move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_accept") and not buttons.is_empty():
		buttons[clampi(focus_index, 0, buttons.size() - 1)].emit_signal("pressed")


func _input_how(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		screen = how_from
		focus_index = 0
		_refresh()
	elif event.is_action_pressed("ui_up"):
		var scroll := get_node_or_null("HowScroll") as ScrollContainer
		if scroll:
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
	elif event.is_action_pressed("ui_down"):
		var scroll := get_node_or_null("HowScroll") as ScrollContainer
		if scroll:
			scroll.scroll_vertical += 48


func _input_play(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		_open_pause()
		_refresh()
		return
	var hand_size := 0
	if not game.players.is_empty():
		hand_size = game.players[0].hand.size()
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		card_index = wrapi(card_index - 1, 0, maxi(hand_size, 1))
		_refresh()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		card_index = wrapi(card_index + 1, 0, maxi(hand_size, 1))
		_refresh()
	elif event.is_action_pressed("ui_accept"):
		if game.phase == Match.PHASE_REVEAL:
			game.skip_reveal()
		elif game.human_turn():
			game.play_card(card_index)
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		var digit: int = int(event.keycode) - KEY_1
		if digit >= 0 and digit <= 8 and game.human_turn() and digit < hand_size:
			card_index = digit
			game.play_card(digit)
			_refresh()


func _signature() -> String:
	var flip := 0
	if game.phase == Match.PHASE_REVEAL:
		flip = int(game.reveal_age / Match.FLIP_STEP)
	return "%d|%d|%d|%d|%s|%s|%s|%d|%d|%d|%d|%d" % [
		screen, game.phase, game.round_no, game.table.size(),
		game.sum_shown, game.paused, text.lang, card_index, focus_index, flip,
		game.acting(), game.holder,
	]


func _refresh() -> void:
	last_sig = ""


func _rebuild() -> void:
	for child in get_children():
		if child == card_player or child == reveal_player:
			continue
		child.queue_free()
	buttons = []
	var bg := ColorRect.new()
	bg.color = Color("110D0B")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	_room()
	match screen:
		SCREEN_MENU:
			_build_menu()
		SCREEN_HOW:
			_build_how()
		SCREEN_LANG:
			_build_lang()
		SCREEN_PLAY, SCREEN_PAUSE:
			_build_play()
			if screen == SCREEN_PAUSE:
				_build_pause()
		SCREEN_OVER:
			_build_over()
	if screen == SCREEN_MENU or screen == SCREEN_HOW or screen == SCREEN_LANG:
		_legend()


func _room() -> void:
	var view = TableScene.new()
	view.set_anchors_preset(PRESET_FULL_RECT)
	view.seats = _seat_poses()
	view.your_turn = screen == SCREEN_PLAY and game.human_turn()
	add_child(view)
	for seat in view.seats:
		var caption: String = seat.name
		if int(seat.cards) > 0 and screen != SCREEN_MENU:
			caption += "  ·  %d" % int(seat.cards)
		var y_off: float = 156.0 * float(seat.scale)
		_label(caption, 18, seat.pos + Vector2(0, y_off), BRASS_HI if seat.lit else IVORY, HORIZONTAL_ALIGNMENT_CENTER)


func _seat_poses() -> Array:
	var defs: Array = [
		{"id": 1, "pos": Vector2(250, 228), "scale": 1.02, "coat": Color("1B2433"), "skin": Color("C9A07A"), "hair": Color("E4DCCE"), "style": "short", "fallback": "Kemal"},
		{"id": 2, "pos": Vector2(640, 142), "scale": 0.82, "coat": Color("7A2432"), "skin": Color("E2BC9A"), "hair": Color("1A120E"), "style": "bun", "fallback": "Nur"},
		{"id": 3, "pos": Vector2(1030, 232), "scale": 1.06, "coat": Color("3C4A34"), "skin": Color("A67C52"), "hair": Color("2A2118"), "style": "bald", "fallback": "Sabri"},
	]
	var winner := -1
	if screen == SCREEN_OVER and not game.standings.is_empty():
		winner = int(game.standings[0].id)
	var poses: Array = []
	for item in defs:
		var id: int = item.id
		var known: bool = game.players.size() == 4
		var player_name: String = item.fallback
		var cards := 0
		if known:
			var player: Match.Player = game.players[id]
			player_name = player.player_name
			cards = player.hand.size()
		var thinking := screen == SCREEN_PLAY and game.acting() == id
		poses.append({
			"pos": item.pos,
			"scale": item.scale,
			"coat": item.coat,
			"skin": item.skin,
			"hair": item.hair,
			"style": item.style,
			"name": player_name,
			"cards": cards,
			"lit": thinking or winner == id or (screen == SCREEN_PLAY and game.holder == id),
			"holder": screen == SCREEN_PLAY and game.holder == id,
			"thinking": thinking,
		})
	return poses


func _build_menu() -> void:
	_label(text.t("brand.name"), 42, Vector2(36, 18), BRASS_HI, HORIZONTAL_ALIGNMENT_LEFT)
	_label(text.t("menu.tagline1"), 22, Vector2(36, 68), IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	_label(text.t("menu.tagline2"), 20, Vector2(36, 98), BRASS, HORIZONTAL_ALIGNMENT_LEFT)
	_label(text.format_key("menu.stats %lld %lld", [game.games_finished, game.games_won]), 16, Vector2(36, 132), BRASS, HORIZONTAL_ALIGNMENT_LEFT)
	var ids: Array = []
	if game.can_resume():
		ids.append("continue")
	ids.append("new")
	ids.append("how")
	ids.append("lang")
	ids.append("quit")
	var y := 430.0
	for i in ids.size():
		var id: String = ids[i]
		var caption := ""
		match id:
			"continue":
				caption = text.t("menu.continue")
			"new":
				caption = text.t("menu.newGame") if game.can_resume() else text.t("menu.sit")
			"how":
				caption = text.t("howto.title")
			"lang":
				caption = text.t("language.title")
			"quit":
				caption = text.t("ui.quit")
		_button(caption, Vector2(430, y), Vector2(420, 48), i == 0, i == focus_index, _menu_activate.bind(id))
		y += 56


func _menu_activate(id: String) -> void:
	match id:
		"continue":
			game.resume()
			screen = SCREEN_PLAY
			card_index = 0
			turn_token = -1
		"new":
			game.new_game()
			screen = SCREEN_PLAY
			card_index = 0
			turn_token = -1
		"how":
			how_from = SCREEN_MENU
			screen = SCREEN_HOW
		"lang":
			screen = SCREEN_LANG
			focus_index = 0
		"quit":
			get_tree().quit()
	_refresh()


func _build_how() -> void:
	_veil()
	_label(text.t("howto.title"), 36, Vector2(640, 28), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	_back_button()
	var scroll := ScrollContainer.new()
	scroll.name = "HowScroll"
	scroll.position = Vector2(80, 108)
	scroll.size = Vector2(1120, 620)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1080, 0)
	box.add_theme_constant_override("separation", 18)
	scroll.add_child(box)
	for i in range(1, 7):
		var line := Label.new()
		line.text = "%d.  %s" % [i, text.t("rules.%d" % i)]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(1080, 0)
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", IVORY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if text.rtl() else HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(line)


func _build_lang() -> void:
	_veil()
	_label(text.t("language.title"), 36, Vector2(640, 24), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	_back_button()
	var y := 100.0
	for i in TextBank.LANGUAGES.size():
		var pair: Array = TextBank.LANGUAGES[i]
		var current: bool = pair[0] == text.lang
		_button(pair[1], Vector2(320, y), Vector2(640, 56), current, i == focus_index, _choose_language.bind(pair[0]))
		y += 62


func _build_play() -> void:
	if game.players.size() < 4:
		return
	_label(text.format_key("game.round %lld %lld", [game.round_no, Match.ROUNDS]), 18, Vector2(1100, 18), BRASS_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	var play_order := game.order()
	for i in 4:
		var slot: Vector2 = TableScene.SLOT_POS[i]
		var owner: Match.Player = game.players[play_order[i]]
		_label(owner.player_name, 14, slot + Vector2(TableScene.SLOT_SIZE.x * 0.5, -18), BRASS_HI if play_order[i] == game.holder else IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		if i < game.table.size():
			var played: Match.Played = game.table[i]
			_card_face(played.card, slot, TableScene.SLOT_SIZE, game.card_face_up(i), false)
		elif game.acting() == play_order[i]:
			var empty := ColorRect.new()
			empty.position = slot
			empty.size = TableScene.SLOT_SIZE
			empty.color = Color("C9A44C")
			empty.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(empty)
	if game.sum_shown:
		_label(text.t("game.tableTotal") + "  " + str(game.table_sum()), 18, Vector2(640, 568), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	if game.verdict_text() != "":
		_label(game.verdict_text(), 16, Vector2(640, 592), IVORY, HORIZONTAL_ALIGNMENT_CENTER, 900)
	_label(game.status_text(), 20, Vector2(640, 616), IVORY, HORIZONTAL_ALIGNMENT_CENTER, 800)
	var hint := game.hint_text()
	if hint != "":
		_label(hint, 16, Vector2(640, 644), IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER, 800)
	if screen == SCREEN_PAUSE:
		return
	_hand(game.players[0])


func _hand(me: Match.Player) -> void:
	var n := me.hand.size()
	if n == 0:
		return
	var card_w := 84.0
	var card_h := 118.0
	var left := 250.0
	var span := 760.0
	for i in n:
		var t := 0.0 if n == 1 else float(i) / float(n - 1)
		var x := left + t * span - card_w * 0.5
		var y := 648.0 + absf(t - 0.5) * 34.0
		var selected := i == card_index and game.human_turn()
		if selected:
			y -= 30.0
		var card: Match.Card = me.hand[i]
		var button := _card_face(card, Vector2(x, y), Vector2(card_w, card_h), true, selected, i)
		button.pivot_offset = Vector2(card_w * 0.5, card_h)
		button.rotation_degrees = lerpf(-14.0, 14.0, t)
		button.z_index = 20 if selected else i


func _build_pause() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(330, 390)
	panel.size = Vector2(620, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(true))
	add_child(panel)
	_label(text.t("pause.title"), 32, Vector2(640, 408), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	var sound_state := text.t("ui.on") if game.sound_on else text.t("ui.off")
	var items := [
		[text.t("pause.continue"), "resume"],
		[text.t("howto.title"), "how"],
		[text.t("settings.sound") + "  ·  " + sound_state, "sound"],
		[text.t("pause.quit"), "quit"],
	]
	var y := 456.0
	for i in items.size():
		_button(items[i][0], Vector2(410, y), Vector2(460, 48), i == 0, i == focus_index, _pause_activate.bind(items[i][1]))
		y += 56


func _pause_activate(id: String) -> void:
	match id:
		"resume":
			_resume()
		"how":
			how_from = SCREEN_PAUSE
			screen = SCREEN_HOW
		"sound":
			game.set_sound(not game.sound_on)
		"quit":
			game.quit_match()
			if game.phase == Match.PHASE_OVER:
				screen = SCREEN_OVER
			else:
				screen = SCREEN_MENU
			focus_index = 0
	_refresh()


func _veil() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	add_child(dim)


func _build_over() -> void:
	_label(text.format_key("over.roundsDone %lld", [Match.ROUNDS]), 18, Vector2(640, 390), BRASS, HORIZONTAL_ALIGNMENT_CENTER)
	if not game.standings.is_empty():
		var top: Dictionary = game.standings[0]
		_label(text.format_key("over.won %@", [top.name]), 32, Vector2(640, 418), IVORY, HORIZONTAL_ALIGNMENT_CENTER, 800)
		_label(text.format_key("over.lightest %lld", [top.score]), 18, Vector2(640, 458), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	for i in game.standings.size():
		var row: Dictionary = game.standings[i]
		var bg := ColorRect.new()
		bg.position = Vector2(340, 490 + i * 36)
		bg.size = Vector2(600, 32)
		bg.color = Color("6E5320") if i == 0 else (FELT_LIT if row.id == 0 else Color(0, 0, 0, 0.28))
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bg)
		_label("%d   %s    %s" % [i + 1, row.name, str(row.score)], 18, Vector2(356, bg.position.y + 4), BRASS_HI if i == 0 else IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	_button(text.t("over.newGame"), Vector2(410, 650), Vector2(460, 48), true, focus_index == 0, func ():
		game.new_game()
		screen = SCREEN_PLAY
		turn_token = -1
		_refresh()
	)
	_button(text.t("over.menu"), Vector2(410, 706), Vector2(460, 48), false, focus_index == 1, func ():
		_to_menu()
	)


func _legend() -> void:
	_label(text.t("ui.legend"), 16, Vector2(640, 760), IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER, 1200)


func _label(value: String, size: int, pos: Vector2, color: Color, align: HorizontalAlignment, width := 0.0) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = MOUSE_FILTER_IGNORE
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size = Vector2(width, 80)
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			label.position.x = pos.x - width / 2.0
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			label.position.x = pos.x - width
	else:
		label.size = Vector2(800, 70)
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			label.position.x = pos.x - 400
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			label.position.x = pos.x - 800
	add_child(label)
	return label


func _button(caption: String, pos: Vector2, size: Vector2, primary: bool, focused: bool, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	var font := INK if primary else IVORY
	var fill := BRASS if primary else PANEL
	button.add_theme_stylebox_override("normal", _button_style(fill, focused))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.08), focused))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.08), focused))
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_font_size_override("font_size", 24 if size.y >= 60 else 22)
	button.pressed.connect(action)
	add_child(button)
	buttons.append(button)


func _back_button() -> void:
	var x := 40.0 if text.rtl() else 1060.0
	var button := Button.new()
	button.text = text.t("game.back")
	button.position = Vector2(x, 20)
	button.size = Vector2(180, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _button_style(PANEL, false))
	button.add_theme_color_override("font_color", IVORY)
	button.pressed.connect(func ():
		screen = how_from if screen == SCREEN_HOW else SCREEN_MENU
		focus_index = 0
		_refresh()
	)
	add_child(button)


func _card_face(card: Match.Card, pos: Vector2, size: Vector2, up: bool, selected: bool, hand_index := -1) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	var fill := IVORY if up else FELT
	var border := BRASS_HI if selected else BRASS
	button.add_theme_stylebox_override("normal", _card_style(fill, border, selected))
	button.add_theme_stylebox_override("hover", _card_style(fill, BRASS_HI, selected))
	button.add_theme_stylebox_override("pressed", _card_style(fill, BRASS, selected))
	if up:
		button.text = "%s\n%s" % [card.label(), card.symbol()]
		button.add_theme_color_override("font_color", LAC if card.red() else INK)
		button.add_theme_color_override("font_hover_color", LAC if card.red() else INK)
		button.add_theme_font_size_override("font_size", 22 if size.x >= 74 else 18)
	if hand_index >= 0:
		button.pressed.connect(_play_hand.bind(hand_index))
	elif game.phase == Match.PHASE_REVEAL:
		button.pressed.connect(func ():
			game.skip_reveal()
			_refresh()
		)
	add_child(button)
	return button


func _choose_language(code: String) -> void:
	text.set_language(code)
	game._save()
	screen = SCREEN_MENU
	focus_index = 0
	_refresh()


func _play_hand(index: int) -> void:
	card_index = index
	if game.human_turn():
		game.play_card(index)
	elif game.phase == Match.PHASE_REVEAL:
		game.skip_reveal()
	_refresh()


func _open_pause() -> void:
	if game.phase != Match.PHASE_PLAYING and game.phase != Match.PHASE_REVEAL:
		return
	game.set_paused(true)
	screen = SCREEN_PAUSE
	focus_index = 0


func _resume() -> void:
	game.set_paused(false)
	screen = SCREEN_PLAY


func _to_menu() -> void:
	game.return_to_menu()
	screen = SCREEN_MENU
	focus_index = 0
	_refresh()


func _move_focus(step: int) -> void:
	if buttons.is_empty():
		return
	focus_index = wrapi(focus_index + step, 0, buttons.size())
	_refresh()


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


func _panel_style(lit: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("0C4536")
	box.border_color = BRASS if lit else Color("6E5320")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box


func _button_style(fill: Color, focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = BRASS_HI if focused else BRASS
	box.set_border_width_all(4 if focused else 2)
	box.set_corner_radius_all(4)
	return box


func _card_style(fill: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(4 if selected else 2)
	box.set_corner_radius_all(6)
	return box


func _tone(freq: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var env := 1.0 - float(i) / float(count)
		var sample := int(sin(TAU * freq * float(i) / float(rate)) * 8000.0 * env)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
