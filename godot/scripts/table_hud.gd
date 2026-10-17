extends Control

# Everything on screen over the table while a match is on: how far the hand
# has come, whose turn it is, nameplates over the opponents and the seated
# player's own count, the running total as the croupier turns the cards,
# the verdict, short alerts at the moments that matter, and the
# rock-paper-scissors duel with its choice panels.
#
# Opponents' points stay hidden until a hand ends; their card counts are
# public and shown throughout.

signal chosen(throw: int)

const TitleScreen := preload("res://scripts/title_screen.gd")
const DISPLAY := preload("res://assets/fonts/PlayfairDisplay.ttf")
const SANS := preload("res://assets/fonts/JosefinSans.ttf")

const GOLD := Color("DDB665")
const GOLD_HI := Color("F0DA9E")
const IVORY := Color("F3ECDA")
const IVORY_DIM := Color(0.95, 0.93, 0.86, 0.72)
const INK := Color("1B1712")
const PANEL := Color(0.05, 0.038, 0.028, 0.84)
const RED := Color("D2563E")
const GREEN := Color("86C46F")
const VIOLET := Color("C69CF0")
# Least room between two card labels under the revealed row.
const TAG_GAP := 6.0

var text: TextBank
var icons: Node
var world: Node3D
var focus := -1

var _game: Match
var _faces: Array = []
var _head: FontVariation
var _label: FontVariation
var _number: FontVariation
var _sig := ""
var _names: Control
var _static: Control
var _live: Control
var _plates: Dictionary = {}
var _cards: Array = []
var _gauge: Gauge
var _shown_total := 0.0
var _ribbon: Control
var _ribbon_age := -1.0
var _alert: Control
var _alert_age := -1.0
var _last: Dictionary = {}
var _clock := 0.0
var _choices: Array = []


func setup(bank: TextBank, hand_icons: Node, room: Node3D) -> void:
	text = bank
	icons = hand_icons
	world = room
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_head = _face(DISPLAY, 700, 1)
	_number = _face(DISPLAY, 800, 0)
	_label = _face(SANS, 600, 2)
	# Nameplates sit under every panel, so a head drifting up behind the
	# total or the progress never covers them.
	_names = _layer("Names")
	_static = _layer("Static")
	_live = _layer("Live")
	_gauge = Gauge.new()
	_gauge.visible = false
	_live.add_child(_gauge)
	if icons != null and icons.has_signal("rendered"):
		icons.connect("rendered", func(_preset: String) -> void: _sig = "")


func sync(game: Match, active: bool, delta: float) -> void:
	_game = game
	_clock += delta
	visible = active and game.players.size() == Match.SEATS
	if not visible:
		_sig = ""
		_last.clear()
		return
	_sync_faces()
	_events(delta)
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	_animate(delta)


func move_focus(step: int) -> void:
	focus = wrapi(focus + step, 0, 3) if focus >= 0 else (0 if step > 0 else 2)
	_sig = ""


func confirm() -> bool:
	if focus < 0:
		return false
	chosen.emit(focus)
	return true


func reset_focus() -> void:
	focus = -1
	_sig = ""


# --- what changed since last frame -------------------------------------------------

func _events(delta: float) -> void:
	var g := _game
	var now := {
		"hand": g.hand_no,
		"round": g.round_no,
		"phase": g.phase,
		"sum": g.sum_shown,
		"turn": g.human_turn(),
		"holder": g.holder,
	}
	if not _last.is_empty():
		var new_round: bool = now["round"] != _last["round"] or now["hand"] != _last["hand"]
		if new_round and g.phase == Match.PHASE_PLAYING:
			if g.round_no == Match.ROUNDS:
				_flash(_t("hud.lastRound"), _t("hud.lastRoundSub"), RED)
			elif g.holder == 0:
				_flash(_t("hud.youHold"), _scaled_hint(true), GOLD_HI)
		if now["sum"] and not _last["sum"]:
			_verdict_ribbon()
	_last = now
	if _ribbon_age >= 0.0:
		_ribbon_age += delta
	if _alert_age >= 0.0:
		_alert_age += delta


func _signature() -> String:
	var g := _game
	var counts := []
	for player in g.players:
		counts.append(player.hand.size())
	return "%d|%d|%d|%d|%s|%d|%d|%d|%d|%s|%s|%d|%s|%s|%d|%s" % [
		g.phase, g.hand_no, g.round_no, g.holder, g.human_turn(), g.acting(), g.duel_stage,
		g.duel_beat(), g.duel_throws.size(), g.choosing(), counts, focus, text.lang, g.paused,
		g.seated().size(), _my_turn(),
	]


func _my_turn() -> bool:
	# The seated player's turn, once the table is still: not while the
	# croupier is still dealing or a card is still in the air.
	return _game.human_turn() and not (world != null and bool(world.call("busy")))


# --- rebuilt parts -------------------------------------------------------------------

func _rebuild() -> void:
	for child in _static.get_children():
		child.queue_free()
	_choices.clear()
	var size := get_viewport_rect().size
	_progress(size)
	if _game.phase == Match.PHASE_DUEL:
		_duel(size)
		return
	_status(size)
	_own_plate(size)


func _progress(size: Vector2) -> void:
	var g := _game
	var right := size.x - 30.0
	var hand := _text(_static, TitleScreen.upper(text.format_key("game.hand %lld", [g.hand_no]), text.lang), _label, 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	hand.position = Vector2(right - 300.0, 18.0)
	hand.size = Vector2(300, 20)
	# One pip a round: played ones filled, this one ringed, the rest faint.
	var pips := Pips.new()
	pips.round_no = g.round_no
	pips.total = Match.ROUNDS
	pips.position = Vector2(right - 8.0 * 22.0, 44.0)
	pips.size = Vector2(8.0 * 22.0, 22.0)
	_static.add_child(pips)
	var round_text := text.format_key("game.round %lld %lld", [g.round_no, Match.ROUNDS])
	var line := _text(_static, round_text, _label, 13, IVORY_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	line.position = Vector2(right - 300.0, 70.0)
	line.size = Vector2(300, 18)
	var y := 94.0
	if g.round_no == Match.ROUNDS and g.phase != Match.PHASE_DUEL:
		var last := _chip(_static, TitleScreen.upper(_t("hud.lastRound"), text.lang), RED, IVORY)
		last.position = Vector2(right - last.size.x, y)
		y += 30.0
	var goal := text.format_key("hud.target %lld %lld", [g.limit(), g.cap()])
	var seats := g.seated().size()
	if seats < Match.SEATS:
		goal = text.format_key("game.table %lld %lld %lld", [seats, g.limit(), g.cap()])
	var chip := _chip(_static, goal, Color(0.0, 0.0, 0.0, 0.5), GOLD_HI)
	chip.position = Vector2(right - chip.size.x, y)


func _status(size: Vector2) -> void:
	var g := _game
	var line := g.status_text()
	if line == "":
		return
	var mine := _my_turn()
	var box := _panel(_static, Rect2(22, 14, 470, 64 if g.hint_text() != "" else 40), 0.62, GOLD_HI if mine else Color(GOLD, 0.45), 2 if mine else 1)
	var dot := ColorRect.new()
	dot.color = GOLD_HI if g.human_turn() else IVORY_DIM
	dot.size = Vector2(8, 8)
	dot.position = Vector2(14, 16)
	box.add_child(dot)
	var top := _text(box, line, _label, 17, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	top.position = Vector2(30, 8)
	top.size = Vector2(430, 24)
	if g.hint_text() != "":
		var hint := _text(box, g.hint_text(), _label, 14, GOLD_HI, HORIZONTAL_ALIGNMENT_LEFT)
		hint.position = Vector2(30, 36)
		hint.size = Vector2(430, 22)
	if mine:
		# Beside the hand, over the open felt right of it, where the eye
		# already is but clear of every card.
		var banner := _text(_static, TitleScreen.upper(_t("hud.yourTurn"), text.lang), _head, 30, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
		banner.position = Vector2(size.x * 0.68 - 170.0, size.y * 0.755)
		banner.size = Vector2(340, 40)
		banner.name = "TurnBanner"


func _own_plate(size: Vector2) -> void:
	var g := _game
	var me: Match.Player = g.players[0]
	if me.out:
		return
	var box := _panel(_static, Rect2(22, size.y - 88, 250, 66), 0.66)
	var name := _text(box, TitleScreen.upper(me.player_name, text.lang), _label, 14, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	name.position = Vector2(14, 8)
	name.size = Vector2(150, 18)
	if g.holder == 0 and g.phase != Match.PHASE_DUEL:
		var token := HolderBadge.new()
		token.size = Vector2(24, 24)
		token.position = Vector2(250 - 34, 6)
		box.add_child(token)
		var role := _text(box, TitleScreen.upper(_t("hud.holder"), text.lang), _label, 11, GOLD_HI, HORIZONTAL_ALIGNMENT_RIGHT)
		role.position = Vector2(92, 10)
		role.size = Vector2(120, 16)
	var cards := _text(box, text.format_key("hud.cards %lld", [me.hand.size()]), _number, 22, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	cards.position = Vector2(14, 28)
	cards.size = Vector2(110, 30)
	var points := _text(box, text.format_key("hud.points %lld", [me.score()]), _label, 15, IVORY_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	points.position = Vector2(110, 36)
	points.size = Vector2(126, 22)


# --- duel ----------------------------------------------------------------------------

func _duel(size: Vector2) -> void:
	var g := _game
	var mid := size.x * 0.5
	var title := _text(_static, TitleScreen.upper(_t("duel.title"), text.lang), _label, 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(mid - 400, 14)
	title.size = Vector2(800, 20)
	var big := 52 if g.duel_stage == Match.DUEL_CHANT else 32
	var heading := _text(_static, g.duel_heading(), _head, big, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	heading.position = Vector2(mid - 560, 38)
	heading.size = Vector2(1120, big + 16)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var detail := g.duel_detail()
	if detail != "" and g.duel_stage != Match.DUEL_SHOW and g.duel_stage != Match.DUEL_AFTER:
		var line := _text(_static, detail, _label, 17, IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		line.position = Vector2(mid - 290, 46 + big)
		line.size = Vector2(580, 56)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if (g.duel_stage == Match.DUEL_INTRO or g.duel_stage == Match.DUEL_CHOOSE) and g.duel_ties == 0:
		_standings(Vector2(size.x - 330, 150))
	if g.duel_stage == Match.DUEL_SHOW or (g.duel_stage == Match.DUEL_AFTER and not g.duel_out):
		_throws(size)
	if g.choosing():
		_choice_panels(size)


func _standings(at: Vector2) -> void:
	# The hand's final count, now that the hand is over: who won, who goes to
	# the throw.
	var rows := _game.standings
	var box := _panel(_static, Rect2(at.x, at.y, 300, 44 + rows.size() * 34), 0.8)
	var head := _text(box, TitleScreen.upper(_t("hud.handResult"), text.lang), _label, 13, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	head.position = Vector2(14, 10)
	head.size = Vector2(270, 18)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var first := i == 0
		var last := i == rows.size() - 1
		var fill := ColorRect.new()
		fill.position = Vector2(8, 36 + i * 34)
		fill.size = Vector2(284, 30)
		fill.color = Color(GOLD, 0.28) if first else (Color(RED, 0.32) if last else Color(1, 1, 1, 0.04))
		box.add_child(fill)
		var name := _text(box, "%d  %s" % [i + 1, row.name], _label, 15, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
		name.position = Vector2(16, 40 + i * 34)
		name.size = Vector2(150, 22)
		var detail := _text(box, text.format_key("hud.rowScore %lld %lld", [int(row.cards), int(row.score)]), _label, 14, GOLD_HI if first else (Color(1.0, 0.8, 0.74) if last else IVORY_DIM), HORIZONTAL_ALIGNMENT_RIGHT)
		detail.position = Vector2(130, 41 + i * 34)
		detail.size = Vector2(150, 22)


func _throws(size: Vector2) -> void:
	# Both throws side by side, the one that won lit.
	var g := _game
	if g.duel_throws.size() < 2:
		return
	var seats := [g.duel_loser, g.duel_winner]
	var winner := -1
	var a := int(g.duel_throws[g.duel_loser])
	var b := int(g.duel_throws[g.duel_winner])
	if Match.beats(a, b):
		winner = g.duel_loser
	elif Match.beats(b, a):
		winner = g.duel_winner
	var mid := size.x * 0.5
	for k in 2:
		var seat: int = seats[k]
		var throw := int(g.duel_throws[seat])
		var rect := Rect2(mid - 250 + k * 280, size.y - 330, 220, 230)
		var lit := seat == winner
		var box := _panel(_static, rect, 0.82, GOLD_HI if lit else Color(GOLD, 0.35), 3 if lit else 1)
		var art := _icon(throw, seat)
		if art != null:
			var pic := TextureRect.new()
			pic.texture = art
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.position = Vector2(20, 10)
			pic.size = Vector2(180, 150)
			pic.modulate = Color.WHITE if lit or winner < 0 else Color(0.6, 0.6, 0.6)
			box.add_child(pic)
		var what := _text(box, TitleScreen.upper(g.throw_name(throw), text.lang), _head, 26, GOLD_HI if lit else IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		what.position = Vector2(0, 160)
		what.size = Vector2(220, 34)
		var who := _text(box, g.players[seat].player_name, _label, 15, IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		who.position = Vector2(0, 196)
		who.size = Vector2(220, 22)
	var versus := _text(_static, "VS", _head, 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	versus.position = Vector2(mid - 30 - 25, size.y - 230)
	versus.size = Vector2(110, 40)


func _choice_panels(size: Vector2) -> void:
	# Three large panels: the player's own hand making the throw, its name
	# under it, the key in the corner.
	var mid := size.x * 0.5
	var width := 220.0
	var gap := 30.0
	var left := mid - (width * 3.0 + gap * 2.0) * 0.5
	var top := size.y - 330.0
	var prompt := _text(_static, _t("duel.pick"), _label, 17, IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.position = Vector2(mid - 300, top - 34)
	prompt.size = Vector2(600, 24)
	for i in 3:
		var lit := i == focus
		var button := Button.new()
		button.position = Vector2(left + i * (width + gap), top)
		button.size = Vector2(width, 262)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.text = TitleScreen.upper(_game.throw_name(i), text.lang)
		button.icon = _icon(i, 0)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_override("font", _head)
		button.add_theme_font_size_override("font_size", 26)
		for state in ["normal", "hover", "pressed"]:
			var on: bool = lit or state != "normal"
			button.add_theme_stylebox_override(state, _box(Color(0.07, 0.05, 0.035, 0.9) if not on else Color(0.16, 0.11, 0.06, 0.94), GOLD_HI if on else Color(GOLD, 0.5), 3 if on else 1, 10))
		button.add_theme_color_override("font_color", GOLD_HI if lit else IVORY)
		button.add_theme_color_override("font_hover_color", GOLD_HI)
		button.add_theme_color_override("font_pressed_color", GOLD_HI)
		button.add_theme_constant_override("h_separation", 0)
		button.pressed.connect(func() -> void: chosen.emit(i))
		button.mouse_entered.connect(func() -> void:
			if focus != i:
				focus = i
				_sig = ""
		)
		_static.add_child(button)
		var key := _chip(button, str(i + 1), GOLD if lit else Color(0, 0, 0, 0.55), INK if lit else GOLD_HI)
		key.position = Vector2(10, 10)
		_choices.append(button)


func _icon(throw: int, seat: int) -> Texture2D:
	if icons == null or world == null or not world.has_method("seat_preset"):
		return null
	var set: Array = icons.icons(str(world.call("seat_preset", seat)))
	return set[throw] if throw < set.size() else null


# --- every frame ---------------------------------------------------------------------

func _animate(delta: float) -> void:
	_nameplates()
	_reveal(delta)
	_ribbon_step()
	_alert_step()
	var banner := _static.get_node_or_null("TurnBanner") as Label
	if banner != null:
		banner.modulate.a = 0.72 + 0.28 * sin(_clock * 4.0)


func _nameplates() -> void:
	# Over each opponent's head: name, cards held, the holder's token, a lit
	# rim on whoever is to play, and the throw during a duel.
	var g := _game
	for id in [1, 2, 3]:
		var pos := Vector2(-1, -1)
		if world != null and world.has_method("seat_screen_pos"):
			pos = world.call("seat_screen_pos", id)
		var plate: Control = _plates.get(id)
		if plate == null:
			plate = _make_plate()
			_plates[id] = plate
			_names.add_child(plate)
		var player: Match.Player = g.players[id]
		plate.visible = pos.x >= 0.0 and not player.out
		if not plate.visible:
			continue
		var acting: bool = g.acting() == id
		var name: Label = plate.get_node("Name")
		var count: Label = plate.get_node("Count")
		var token: Control = plate.get_node("Token")
		var role: Label = plate.get_node("Role")
		var extra: Label = plate.get_node("Extra")
		name.text = player.player_name
		var cards := int(world.call("fan_count", id)) if world.has_method("fan_count") else player.hand.size()
		count.text = str(cards)
		token.visible = g.holder == id and g.phase != Match.PHASE_DUEL
		role.visible = token.visible
		role.text = TitleScreen.upper(_t("hud.holder"), text.lang)
		extra.text = ""
		if g.phase == Match.PHASE_DUEL and g.duel_throws.has(id):
			extra.text = TitleScreen.upper(g.throw_name(int(g.duel_throws[id])), text.lang)
		var style := plate.get_theme_stylebox("panel") as StyleBoxFlat
		var glow := 0.5 + 0.5 * sin(_clock * 5.0)
		style.border_color = GOLD_HI.lerp(GOLD, glow) if acting else Color(GOLD, 0.3)
		style.set_border_width_all(2 if acting else 1)
		plate.size = Vector2(maxf(132.0, name.get_minimum_size().x + 70.0), 30)
		plate.position = Vector2(pos.x - plate.size.x * 0.5, pos.y - 6.0)
		extra.position = Vector2(0, 32)
		extra.size = Vector2(plate.size.x, 22)
		count.position = Vector2(plate.size.x - 44, 4)
		token.position = Vector2(-30, 2)
		role.position = Vector2(0, -17)
		role.size = Vector2(plate.size.x, 16)


func _make_plate() -> Panel:
	var plate := Panel.new()
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _box(Color(0.04, 0.03, 0.022, 0.72), Color(GOLD, 0.3), 1, 15))
	var name := _text(plate, "", _label, 14, IVORY, HORIZONTAL_ALIGNMENT_LEFT)
	name.name = "Name"
	name.position = Vector2(14, 5)
	name.size = Vector2(120, 20)
	var count := _text(plate, "", _number, 15, GOLD_HI, HORIZONTAL_ALIGNMENT_RIGHT)
	count.name = "Count"
	count.size = Vector2(22, 20)
	var card := ColorRect.new()
	card.name = "CardGlyph"
	card.color = Color(IVORY, 0.85)
	card.size = Vector2(10, 14)
	card.position = Vector2(-14, 3)
	count.add_child(card)
	var token := HolderBadge.new()
	token.name = "Token"
	token.size = Vector2(26, 26)
	plate.add_child(token)
	var role := _text(plate, "", _label, 11, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	role.name = "Role"
	var extra := _text(plate, "", _head, 17, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	extra.name = "Extra"
	return plate


func _reveal(delta: float) -> void:
	# The total counts up as the croupier turns each card; once a card is in
	# the row, a label under it names who played it and what it is worth.
	var g := _game
	var showing := g.phase == Match.PHASE_REVEAL and world != null and world.has_method("revealed")
	var list: Array = world.call("revealed") if showing else []
	while _cards.size() < list.size():
		var tag := _make_tag()
		_live.add_child(tag)
		_cards.append(tag)
	var total := 0
	var parts: Array = []
	var shown: Array = []
	for i in _cards.size():
		var tag: Control = _cards[i]
		if i >= list.size():
			tag.visible = false
			continue
		var info: Dictionary = list[i]
		var up := bool(info["up"])
		var at: Vector2 = info["screen"]
		tag.visible = bool(info.get("lined", up)) and at.x >= 0.0
		if up:
			total += int(info["value"])
			parts.append(int(info["value"]))
		if tag.visible:
			var by := int(info["by"])
			_fill_tag(tag, g.players[by].player_name if by > 0 else _t("hud.you"), str(int(info["value"])))
			tag.position = at - Vector2(tag.size.x * 0.5, -2.0)
			shown.append(tag)
	_spread(shown)
	var on := showing and not list.is_empty() and (parts.size() > 0 or g.sum_shown)
	_gauge.visible = on
	if not on:
		_shown_total = 0.0
		return
	_shown_total = move_toward(_shown_total, float(total), delta * 40.0)
	_gauge.total = _shown_total
	_gauge.target = total
	_gauge.parts = parts
	_gauge.limit = g.limit()
	_gauge.cap = g.cap()
	_gauge.settled = g.sum_shown
	_gauge.caption = TitleScreen.upper(_t("game.tableTotal"), text.lang)
	_gauge.need = text.format_key("hud.need %lld", [g.limit()])
	_gauge.number_font = _number
	_gauge.label_font = _label
	var size := get_viewport_rect().size
	_gauge.size = Vector2(560, 112)
	_gauge.position = Vector2(size.x * 0.5 - 280, 12)
	_gauge.queue_redraw()


func _make_tag() -> Control:
	var tag := Panel.new()
	tag.mouse_filter = MOUSE_FILTER_IGNORE
	tag.size = Vector2(56, 44)
	tag.add_theme_stylebox_override("panel", _box(Color(0.04, 0.03, 0.022, 0.8), Color(GOLD, 0.45), 1, 8))
	var value := _text(tag, "", _number, 20, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	value.name = "Value"
	value.position = Vector2(0, 1)
	value.size = Vector2(56, 24)
	var who := _text(tag, "", _label, 12, IVORY_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	who.name = "Who"
	who.position = Vector2(0, 24)
	who.size = Vector2(56, 18)
	return tag


func _fill_tag(tag: Control, who: String, value: String) -> void:
	# Only as wide as its words, so the labels of neighbouring cards fit
	# side by side.
	var name_label := tag.get_node("Who") as Label
	var value_label := tag.get_node("Value") as Label
	if name_label.text == who and value_label.text == value:
		return
	name_label.text = who
	value_label.text = value
	var wide := maxf(_label.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, _number.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
	wide = maxf(wide + 18.0, 46.0)
	tag.size.x = wide
	name_label.size.x = wide
	value_label.size.x = wide


func _spread(tags: Array) -> void:
	# Labels on one line never overlap: two that would are pushed apart
	# evenly, so the group stays centred under its cards.
	tags.sort_custom(func(a: Control, b: Control) -> bool: return a.position.x < b.position.x)
	for _pass in 8:
		var moved := false
		for k in range(1, tags.size()):
			var a: Control = tags[k - 1]
			var b: Control = tags[k]
			var overlap := a.position.x + a.size.x + TAG_GAP - b.position.x
			if overlap > 0.5 and absf(a.position.y - b.position.y) < a.size.y:
				a.position.x -= overlap * 0.5
				b.position.x += overlap * 0.5
				moved = true
		if not moved:
			return


func _verdict_ribbon() -> void:
	# The outcome, coloured by what it means, and who draws.
	var g := _game
	if _ribbon != null:
		_ribbon.queue_free()
	var head := ""
	var tone := GREEN
	match g.outcome:
		Match.OUTCOME_OVER:
			head = text.format_key("hud.cleared %lld", [g.limit()])
		Match.OUTCOME_EXACT:
			head = text.format_key("hud.exact %lld", [g.limit()])
			tone = GOLD_HI
		Match.OUTCOME_CAP:
			head = text.format_key("hud.exact %lld", [g.cap()])
			tone = VIOLET
		_:
			head = _t("hud.short")
			tone = RED
	var size := get_viewport_rect().size
	_ribbon = _panel(_live, Rect2(size.x * 0.5 - 330, 132, 660, 74), 0.88, tone, 2)
	var big := _text(_ribbon, TitleScreen.upper(head, text.lang), _head, 30, tone, HORIZONTAL_ALIGNMENT_CENTER)
	big.position = Vector2(0, 4)
	big.size = Vector2(660, 40)
	var line := _text(_ribbon, _who_draws(), _label, 15, IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	line.position = Vector2(0, 44)
	line.size = Vector2(660, 22)
	_ribbon.pivot_offset = _ribbon.size * 0.5
	_ribbon_age = 0.0
	if _human_draws():
		_flash(_t("hud.youDraw"), "", RED)


func _who_draws() -> String:
	var g := _game
	var who: String = g.players[g.holder].player_name
	var mine := g.holder == 0
	match g.outcome:
		Match.OUTCOME_OVER:
			return _t("hud.noDrawYou") if mine else text.format_key("hud.noDraw %@", [who])
		Match.OUTCOME_UNDER:
			return _t("hud.holderDrawsYou") if mine else text.format_key("hud.holderDraws %@", [who])
	return _t("hud.othersDrawYou") if mine else text.format_key("hud.othersDraw %@", [who])


func _human_draws() -> bool:
	var g := _game
	if g.players[0].out:
		return false
	match g.outcome:
		Match.OUTCOME_UNDER:
			return g.holder == 0
		Match.OUTCOME_EXACT, Match.OUTCOME_CAP:
			return g.holder != 0
	return false


func _ribbon_step() -> void:
	if _ribbon == null:
		return
	var g := _game
	if g.phase != Match.PHASE_REVEAL:
		_ribbon.queue_free()
		_ribbon = null
		_ribbon_age = -1.0
		return
	var u := clampf(_ribbon_age / 0.25, 0.0, 1.0)
	_ribbon.scale = Vector2.ONE * lerpf(0.85, 1.0, _ease_out(u))
	_ribbon.modulate.a = u


func _flash(head: String, sub: String, tone: Color) -> void:
	if _alert != null:
		_alert.queue_free()
	var size := get_viewport_rect().size
	_alert = Control.new()
	_alert.mouse_filter = MOUSE_FILTER_IGNORE
	_alert.size = Vector2(720, 120)
	_alert.position = Vector2(size.x * 0.5 - 360, size.y * 0.38 - 60)
	_alert.pivot_offset = _alert.size * 0.5
	_live.add_child(_alert)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.5)
	band.size = Vector2(720, 120 if sub != "" else 84)
	_alert.add_child(band)
	var big := _text(_alert, TitleScreen.upper(head, text.lang), _head, 46, tone, HORIZONTAL_ALIGNMENT_CENTER)
	big.position = Vector2(0, 10)
	big.size = Vector2(720, 60)
	if sub != "":
		var line := _text(_alert, sub, _label, 17, IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		line.position = Vector2(0, 78)
		line.size = Vector2(720, 26)
	_alert_age = 0.0


func _alert_step() -> void:
	if _alert == null:
		return
	var t := _alert_age
	var grow := _ease_out(clampf(t / 0.22, 0.0, 1.0))
	_alert.scale = Vector2.ONE * lerpf(1.25, 1.0, grow)
	_alert.modulate.a = grow * (1.0 - clampf((t - 1.7) / 0.5, 0.0, 1.0))
	if t > 2.2:
		_alert.queue_free()
		_alert = null
		_alert_age = -1.0


# --- helpers -------------------------------------------------------------------------

func _scaled_hint(holder: bool) -> String:
	var line := _t("game.hint.holder" if holder else "game.hint.other")
	return _game._scaled(line)


func _t(key: String) -> String:
	return text.t(key)


func _layer(name: String) -> Control:
	var layer := Control.new()
	layer.name = name
	layer.set_anchors_preset(PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _text(parent: Node, value: String, face: Font, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 4)
	parent.add_child(label)
	return label


func _chip(parent: Node, value: String, fill: Color, ink: Color) -> Panel:
	var chip := Panel.new()
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _box(fill, Color(GOLD, 0.6), 1, 11))
	parent.add_child(chip)
	var label := _text(chip, value, _label, 13, ink, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var width := label.get_minimum_size().x + 22.0
	chip.size = Vector2(maxf(width, 24.0), 22)
	label.position = Vector2.ZERO
	label.size = chip.size
	return chip


func _panel(parent: Node, rect: Rect2, alpha: float, border := Color(GOLD, 0.45), width := 1) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _box(Color(PANEL, alpha), border, width, 8))
	parent.add_child(panel)
	return panel


func _box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 10
	box.anti_aliasing = true
	return box


func _face(base: Font, weight: int, spacing: int) -> FontVariation:
	var face := FontVariation.new()
	face.base_font = base
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	face.spacing_glyph = spacing
	face.fallbacks = TitleScreen.fallback_chain(text.lang if text != null else "en")
	_faces.append(face)
	return face


func _sync_faces() -> void:
	var chain := TitleScreen.fallback_chain(text.lang)
	for face in _faces:
		if face.fallbacks != chain:
			face.fallbacks = chain


func _ease_out(u: float) -> float:
	return 1.0 - pow(1.0 - u, 3.0)


class Pips extends Control:
	var round_no := 1
	var total := 8

	func _draw() -> void:
		for i in total:
			var c := Vector2(i * 22.0 + 11.0, 11.0)
			var n := i + 1
			if n < round_no:
				draw_circle(c, 6.0, Color("DDB665"))
			elif n == round_no:
				draw_circle(c, 7.5, Color("F0DA9E"))
				draw_arc(c, 10.0, 0.0, TAU, 24, Color("F0DA9E", 0.5), 1.5, true)
			else:
				draw_arc(c, 6.0, 0.0, TAU, 24, Color(0.95, 0.93, 0.86, 0.4), 1.5, true)


class Gauge extends Control:
	# The table total against the target: a big number, then a bar marked at
	# the limit and the cap, filled card by card.
	var total := 0.0
	var caption := ""
	var need := ""
	var number_font: Font
	var label_font: Font
	var target := 0
	var parts: Array = []
	var limit := 30
	var cap := 80
	var settled := false

	func _draw() -> void:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.04, 0.03, 0.022, 0.86)
		bg.border_color = Color("DDB665", 0.5)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(10)
		bg.shadow_color = Color(0, 0, 0, 0.5)
		bg.shadow_size = 12
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		if number_font == null or label_font == null:
			return
		var shown := int(round(total))
		var tone := _tone(shown)
		draw_string(label_font, Vector2(18, 26), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("DDB665"))
		draw_string(number_font, Vector2(18, 76), str(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 50, tone)
		var bar := Rect2(118, 54, size.x - 140, 18)
		var top := float(cap) + 8.0
		draw_rect(bar, Color(1, 1, 1, 0.07))
		var x := bar.position.x
		for i in parts.size():
			var w: float = bar.size.x * float(parts[i]) / top
			var shade := tone if i % 2 == 0 else tone.darkened(0.25)
			var seg := Rect2(x, bar.position.y, minf(w, bar.end.x - x), bar.size.y)
			draw_rect(seg, Color(shade, 0.9))
			x += w
		for mark in [limit, cap]:
			var mx: float = bar.position.x + bar.size.x * float(mark) / top
			draw_line(Vector2(mx, bar.position.y - 8), Vector2(mx, bar.end.y + 8), Color("F3ECDA"), 2.0)
			draw_string(label_font, Vector2(mx - 14, bar.position.y - 12), str(mark), HORIZONTAL_ALIGNMENT_CENTER, 28, 13, Color("F3ECDA"))
		draw_string(label_font, Vector2(118, 98), need, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.93, 0.86, 0.7))

	func _tone(value: int) -> Color:
		if value == cap:
			return Color("C69CF0")
		if value > limit:
			return Color("86C46F")
		if value == limit:
			return Color("F0DA9E")
		return Color("D2563E") if settled else Color("F3ECDA")


class HolderBadge extends Control:
	# The holder's button as the table shows it: an ivory disc, a gold rim
	# and the gold crown.
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c + Vector2(0.0, 1.5), r, Color(0.0, 0.0, 0.0, 0.45), true, -1.0, true)
		draw_circle(c, r, Color(0.94, 0.9, 0.81), true, -1.0, true)
		draw_arc(c, r - 1.2, 0.0, TAU, 40, Color(0.78, 0.6, 0.28), 2.0, true)
		var at := c + Vector2(0.0, r * 0.08)
		draw_colored_polygon(TitleScreen.Crown.points(at, r * 1.15), Color(0.83, 0.64, 0.29))
		draw_polyline(TitleScreen.Crown.outline(at, r * 1.15), Color(0.42, 0.27, 0.08), 1.0, true)
		for jewel in TitleScreen.Crown.jewels(at, r * 1.15):
			draw_circle(jewel, maxf(r * 0.12, 1.2), Color(0.66, 0.12, 0.09), true, -1.0, true)
