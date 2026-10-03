extends Control

const SAVE_PATH := "user://25-40-save.json"

const FELT_LIT := Color("1E6E52")
const PANEL := Color("082C22")
const BRASS := Color("C9A44C")
const BRASS_HI := Color("F0DA9E")
const IVORY := Color("F7F2E4")
const IVORY_DIM := Color(0.97, 0.95, 0.89, 0.75)
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
var queued_play := -1
var turn_token := -1
var how_from := SCREEN_MENU
var last_sig := ""
var buttons: Array = []
var sounds: Dictionary = {}
var world: Node3D
var hud: Control
var port: SubViewport
var _name_labels: Dictionary = {}
var _look_held := false
var _debug := false
var _debug_label: Label


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
	_mount_world()
	get_viewport().size_changed.connect(_on_view_resized)
	_rebuild()


func _process(delta: float) -> void:
	var wait := world != null and game.phase == Match.PHASE_PLAYING and bool(world.call("busy"))
	if not wait:
		game.tick(delta)
	if world != null and world.has_method("sync_match"):
		var in_match := screen == SCREEN_PLAY or screen == SCREEN_PAUSE or screen == SCREEN_OVER
		world.call("select_card", card_index if game.human_turn() else -1)
		world.call("sync_match", game, in_match, delta)
	_flush_play()
	_fit_view()
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
	_track_names()
	_track_debug()


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
		var scroll := hud.get_node_or_null("HowScroll") as ScrollContainer
		if scroll:
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
	elif event.is_action_pressed("ui_down"):
		var scroll := hud.get_node_or_null("HowScroll") as ScrollContainer
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_look_held = event.pressed
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game.phase == Match.PHASE_REVEAL:
			game.skip_reveal()
		else:
			var clicked := _card_at(event.position)
			if clicked >= 0:
				card_index = clicked
				_play(clicked)
		_refresh()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		card_index = wrapi(card_index - 1, 0, maxi(hand_size, 1))
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		card_index = wrapi(card_index + 1, 0, maxi(hand_size, 1))
	elif event.is_action_pressed("ui_accept"):
		if game.phase == Match.PHASE_REVEAL:
			game.skip_reveal()
		else:
			_play(card_index)
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		var digit: int = int(event.keycode) - KEY_1
		if digit >= 0 and digit <= 8 and digit < hand_size:
			card_index = digit
			_play(digit)
			_refresh()


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
	_debug_label.text = "phase %s  seat %d  busy %s\n%s\nRMB look   C cards   R center" % [
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
	return "%d|%d|%d|%d|%s|%s|%s|%d|%d|%d" % [
		screen, game.phase, game.round_no, game.table.size(),
		game.sum_shown, game.paused, text.lang, focus_index,
		game.acting(), game.holder,
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
	var packed: PackedScene = load("res://scenes/room_preview.tscn")
	world = packed.instantiate() as Node3D
	world.set("play_mode", true)
	port.add_child(world)
	if world.has_signal("card_sound"):
		world.connect("card_sound", _on_card_sound)
	hud = Control.new()
	hud.name = "Hud"
	hud.set_anchors_preset(PRESET_FULL_RECT)
	hud.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(hud)


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


func _adopt(node: Node) -> void:
	hud.add_child(node)


func _rebuild() -> void:
	if hud == null:
		return
	for child in hud.get_children():
		child.queue_free()
	buttons = []
	_name_labels.clear()
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
	if screen == SCREEN_HOW or screen == SCREEN_LANG:
		return
	if world == null or not world.has_method("seat_screen_pos"):
		return
	var winner := -1
	if screen == SCREEN_OVER and not game.standings.is_empty():
		winner = int(game.standings[0].id)
	for id in [1, 2, 3]:
		var pos: Vector2 = world.call("seat_screen_pos", id)
		if pos.x < 0.0:
			continue
		var acting: bool = screen == SCREEN_PLAY and game.acting() == id
		var color := BRASS_HI if acting or winner == id else IVORY_DIM
		var label := _label(_caption(id), 18 if acting else 17, pos, color, HORIZONTAL_ALIGNMENT_CENTER)
		_name_labels[id] = label


func _caption(id: int) -> String:
	if game.players.size() != 4 or screen == SCREEN_MENU:
		return str(world.call("seat_caption", id))
	var caption: String = game.players[id].player_name
	var cards := int(world.call("fan_count", id))
	if cards > 0:
		caption += "  ·  %d" % cards
	return caption


func _track_names() -> void:
	if world == null or not world.has_method("seat_screen_pos"):
		return
	for id in _name_labels:
		var label: Label = _name_labels[id]
		if not is_instance_valid(label):
			continue
		var pos: Vector2 = world.call("seat_screen_pos", id)
		if pos.x < 0.0:
			label.visible = false
			continue
		label.visible = true
		label.position = Vector2(pos.x - 400.0, pos.y)
		label.text = _caption(id)
		var acting: bool = screen == SCREEN_PLAY and game.acting() == id
		label.add_theme_color_override("font_color", BRASS_HI if acting else IVORY_DIM)
		label.add_theme_font_size_override("font_size", 18 if acting else 17)


func _build_menu() -> void:
	_shade(Rect2(20, 8, 640, 168), 0.5)
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
	_shade(Rect2(400, y - 18, 480, ids.size() * 56 + 20), 0.66)
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
	_shade(Rect2(56, 92, 1168, 650), 0.96)
	_label(text.t("howto.title"), 36, Vector2(640, 28), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	_back_button()
	var scroll := ScrollContainer.new()
	scroll.name = "HowScroll"
	scroll.position = Vector2(80, 108)
	scroll.size = Vector2(1120, 620)
	_adopt(scroll)
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
	_shade(Rect2(280, 88, 720, 660), 0.96)
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
	var view_size := get_viewport_rect().size
	_label(text.format_key("game.round %lld %lld", [game.round_no, Match.ROUNDS]), 18, Vector2(view_size.x - 28, 16), BRASS_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(game.status_text(), 20, Vector2(36, 16), IVORY, HORIZONTAL_ALIGNMENT_LEFT, 560)
	var hint := game.hint_text()
	if hint != "":
		_label(hint, 16, Vector2(36, 48), IVORY_DIM, HORIZONTAL_ALIGNMENT_LEFT, 560)
	var mid_x := view_size.x * 0.5
	if game.sum_shown:
		_label(text.t("game.tableTotal") + "  " + str(game.table_sum()), 24, Vector2(mid_x, 10), BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	if game.verdict_text() != "":
		_label(game.verdict_text(), 18, Vector2(mid_x, 44), IVORY, HORIZONTAL_ALIGNMENT_CENTER, 640)


func _build_pause() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	_adopt(dim)
	var panel := Panel.new()
	panel.position = Vector2(330, 390)
	panel.size = Vector2(620, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(true))
	_adopt(panel)
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
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_STOP
	_adopt(dim)


func _build_over() -> void:
	_shade(Rect2(300, 360, 680, 410), 0.72)
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
		_adopt(bg)
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
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	_adopt(label)
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
	_adopt(button)
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
	_adopt(button)


func _shade(rect: Rect2, alpha: float) -> void:
	var plate := ColorRect.new()
	plate.position = rect.position
	plate.size = rect.size
	plate.color = Color(0.04, 0.03, 0.02, alpha)
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	_adopt(plate)


func _choose_language(code: String) -> void:
	text.set_language(code)
	game._save()
	screen = SCREEN_MENU
	focus_index = 0
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
