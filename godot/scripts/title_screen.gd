extends Control

signal activated(id: String)
signal picked(preset: String)
signal sound(kind: String)

const KEY_ART := preload("res://assets/ui/title_keyart.jpg")
const DISPLAY := preload("res://assets/fonts/PlayfairDisplay.ttf")
const ITALIC := preload("res://assets/fonts/PlayfairDisplay-Italic.ttf")
const SANS := preload("res://assets/fonts/JosefinSans.ttf")
const PORTRAIT := "res://assets/ui/cast/%s.jpg"

const ART_SIZE := Vector2(1280.0, 720.0)
const ART_ALIGN := Vector2(0.6, 0.25)
const ART_PIVOT := Vector2(0.64, 0.42)
const LAMP := Vector2(0.708, 0.118)
const TEA := [
	[Vector2(0.576, 0.743), Vector2(50.0, 124.0)],
	[Vector2(0.759, 0.614), Vector2(34.0, 90.0)],
]
const LEFT := 76.0
const INTRO := 2.8
const LOGO_SIZE := 118
# Moving between the menu and the screens around it keeps the art and the
# logo; only the words and cards come in again, from this far into the intro.
const REENTRY := 0.95

const GOLD := Color("DDB665")
const IVORY := Color("F3ECDA")

const NOISE := """
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}
"""

const ART_SHADER := """shader_type canvas_item;
uniform float blur = 0.0;
uniform float dim = 0.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec3 c = textureLod(TEXTURE, UV, blur).rgb;
	COLOR = vec4(c * (1.0 - dim), 1.0) * tint;
}
"""

const BEAM_SHADER := """shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color = vec4(1.0, 0.74, 0.42, 1.0);
uniform float strength = 0.12;
%s
void fragment() {
	float spread = mix(0.06, 0.5, UV.y);
	float across = abs(UV.x - 0.5) / spread;
	float cone = (1.0 - smoothstep(0.2, 1.0, across)) * smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.5, 1.0, UV.y));
	float t = TIME * 0.05;
	float n = fbm(vec2(UV.x * 3.2 + t, UV.y * 2.2 - t * 1.4));
	float m = fbm(vec2(UV.x * 6.0 - t * 1.3, UV.y * 4.0 + t));
	float haze = smoothstep(0.3, 0.9, n * 0.7 + m * 0.5);
	COLOR = vec4(tint.rgb * cone * (0.2 + 0.8 * haze) * strength, 1.0);
}
"""

const STEAM_SHADER := """shader_type canvas_item;
render_mode blend_add;
uniform float seed = 0.0;
uniform float strength = 0.2;
%s
void fragment() {
	float rise = 1.0 - UV.y;
	float t = TIME * 0.3 + seed * 7.0;
	float sway = (fbm(vec2(rise * 2.2 - t, seed * 3.1)) - 0.5) * 0.8 * rise;
	float x = UV.x - 0.5 - sway;
	float width = mix(0.08, 0.32, rise);
	float body = 1.0 - smoothstep(width * 0.25, width, abs(x));
	float wisps = fbm(vec2(x * 5.0 + seed * 11.0, rise * 3.4 - t * 1.8));
	float fade = smoothstep(0.0, 0.12, rise) * (1.0 - smoothstep(0.4, 1.0, rise));
	float a = body * smoothstep(0.36, 0.78, wisps) * fade * strength;
	COLOR = vec4(vec3(1.0, 0.94, 0.86) * a, 1.0);
}
"""

const SCRIM_SHADER := """shader_type canvas_item;
uniform vec2 view = vec2(1280.0, 800.0);
uniform float left = 0.82;
uniform float reach = 700.0;
uniform float ground = 0.7;
uniform float vignette = 0.6;
uniform float dim = 0.0;
uniform vec4 shade : source_color = vec4(0.025, 0.016, 0.01, 1.0);
void fragment() {
	vec2 px = UV * view;
	float l = left * pow(1.0 - smoothstep(0.0, reach, px.x), 1.35);
	float g = ground * smoothstep(view.y - 320.0, view.y, px.y) * (1.0 - smoothstep(0.0, reach * 1.2, px.x));
	vec2 c = (UV - 0.5) * vec2(view.x / view.y, 1.0);
	float v = vignette * smoothstep(0.45, 1.1, length(c));
	float a = 1.0 - (1.0 - l) * (1.0 - g) * (1.0 - v) * (1.0 - dim);
	COLOR = vec4(shade.rgb, clamp(a, 0.0, 0.96));
}
"""

const GRAIN_SHADER := """shader_type canvas_item;
uniform float amount = 0.04;
float grain(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	float frame = floor(TIME * 20.0);
	float n = grain(floor(FRAGCOORD.xy / 1.5) + vec2(frame * 17.3, frame * 5.9));
	COLOR = vec4(vec3(n), amount);
}
"""

const GOLD_SHADER := """shader_type canvas_item;
uniform vec4 top : source_color = vec4(0.99, 0.94, 0.78, 1.0);
uniform vec4 mid : source_color = vec4(0.87, 0.7, 0.36, 1.0);
uniform vec4 low : source_color = vec4(0.52, 0.35, 0.13, 1.0);
uniform float y0 = 0.0;
uniform float y1 = 100.0;
uniform float offset_x = 0.0;
uniform float shine = -1000.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec4 c = COLOR;
	float fill = step(0.6, c.r) * step(0.6, c.g);
	float t = clamp((local.y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
	vec3 g = t < 0.45 ? mix(top.rgb, mid.rgb, t / 0.45) : mix(mid.rgb, low.rgb, (t - 0.45) / 0.55);
	g += vec3(0.2, 0.16, 0.08) * (1.0 - smoothstep(0.0, 0.04, abs(t - 0.3)));
	float sweep = 1.0 - smoothstep(0.0, 22.0, abs(local.x + offset_x + local.y * 0.45 - shine));
	g = mix(g, vec3(1.0, 0.97, 0.88), sweep * 0.6);
	c.rgb = mix(c.rgb, g, fill);
	COLOR = c;
}
"""

const CARD_SHADER := """shader_type canvas_item;
uniform vec2 card_px = vec2(104.0, 146.0);
uniform float margin_px = 18.0;
uniform float radius_px = 8.0;
uniform float border_px = 4.0;
uniform float picked = 0.0;
uniform float hover = 0.0;
uniform sampler2D portrait : source_color, filter_linear_mipmap;
float box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}
void fragment() {
	vec2 total = card_px + vec2(margin_px * 2.0);
	vec2 px = UV * total - total * 0.5;
	float d = box(px, card_px * 0.5, radius_px);
	float body = 1.0 - smoothstep(-0.8, 0.8, d);
	float ds = box(px - vec2(0.0, 6.0), card_px * 0.5, radius_px);
	vec4 shadow = vec4(0.0, 0.0, 0.0, 0.6 * exp(-max(ds, 0.0) / 6.0));
	float lit = clamp(picked + hover * 0.4, 0.0, 1.0);
	vec4 glow = vec4(1.0, 0.8, 0.42, lit * 0.9 * exp(-max(d, 0.0) / 7.0) * step(0.0, d));
	vec2 inner_half = card_px * 0.5 - vec2(border_px);
	float di = box(px, inner_half, max(radius_px - border_px, 1.5));
	float inner = 1.0 - smoothstep(-0.8, 0.8, di);
	vec2 puv = (px + inner_half) / (inner_half * 2.0);
	vec2 face = (puv - vec2(0.5, 0.36)) / (1.0 + 0.06 * hover) + vec2(0.5, 0.36);
	vec3 photo = texture(portrait, clamp(face, 0.0, 1.0)).rgb;
	photo *= 1.0 - 0.8 * smoothstep(0.58, 1.0, puv.y);
	photo *= mix(0.72, 1.0, clamp(max(picked, hover), 0.0, 1.0));
	vec3 stock = mix(vec3(0.9, 0.86, 0.77), vec3(0.95, 0.78, 0.42), picked);
	float hair = (1.0 - smoothstep(0.0, 1.1, abs(di + 3.0))) * inner;
	vec3 col = mix(stock, photo, inner);
	col = mix(col, mix(vec3(0.78, 0.6, 0.28), vec3(1.0, 0.88, 0.55), picked), hair * 0.85);
	COLOR = over(vec4(col, body), over(glow, shadow));
}
"""

var _faces: Array[FontVariation] = []
var _stage: Control
var _art: TextureRect
var _art_mat: ShaderMaterial
var _glow: TextureRect
var _core: TextureRect
var _scrim_mat: ShaderMaterial
var _fade: ColorRect
var _front: Control
var _logo_glow: TextureRect
var _logo: Logo
var _logo_top := 60.0
var _tagline: Label
var _record: Label
var _stats: Label
var _rules: RulesPanel
var _menu: Control
var _entries: Array = []
var _cast_label: Label
var _cast_rule: ColorRect
var _fan: Control
var _cards: Array = []
var _legend: Label
var _entry_face: FontVariation
var _primary_face: FontVariation
var _card_face: FontVariation
var _note_face: FontVariation
var _card_shader: Shader
var _mode := 2
var _shown := 1.0
var _sub := 0.0
var _intro := 0.0
var _opening := 0.0
var _opened := false
var _screen := "menu"
var _rtl := false
var _clock := 0.0
var _focus := 0
var _picked := ""
var _hover_card: Control = null
var _parallax := Vector2.ZERO
var _config := ""
var _lang := "en"
var _hints := PackedStringArray()
var _dealt: Dictionary = {}


static var _chains: Dictionary = {}


static func upper(value: String, lang: String) -> String:
	if lang == "tr":
		value = value.replace("i", "İ")
	return value.to_upper()


# A SystemFont resolves to one family, and the OS cascade is looked up from the
# primary font's name, which macOS doesn't know for bundled fonts. Every script
# therefore needs its own explicit fallback. PingFang can't be loaded by FreeType
# on current macOS, and STHeiti/Songti lookups block on an asset download.
static func fallback_chain(lang: String) -> Array:
	var key := "ja" if lang == "ja" else "any"
	if _chains.has(key):
		return _chains[key]
	var han := [
		["Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC"],
		["Hiragino Sans", "Yu Gothic", "Noto Sans CJK JP"],
	]
	if key == "ja":
		han.reverse()
	var chain: Array = []
	for names in [["SF Pro Text", "Helvetica Neue", "Segoe UI", "Noto Sans"]] + han + [
		["Geeza Pro", "Segoe UI", "Noto Sans Arabic"],
		["Kohinoor Devanagari", "Nirmala UI", "Noto Sans Devanagari"],
	]:
		var font := SystemFont.new()
		font.font_weight = 500
		font.font_names = PackedStringArray(names)
		chain.append(font)
	_chains[key] = chain
	return chain


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_card_shader = _shader(CARD_SHADER)
	_entry_face = _face(DISPLAY, 500, 3)
	_primary_face = _face(DISPLAY, 700, 4)
	_card_face = _face(DISPLAY, 600, 1)
	_note_face = _face(SANS, 600, 2)
	_build_stage()
	_build_scrim()
	_build_front()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_fade)
	resized.connect(_layout)
	_layout()


func configure(data: Dictionary) -> void:
	var key := JSON.stringify(data)
	if key == _config:
		return
	_config = key
	var lang := str(data.get("lang", "en"))
	if fallback_chain(lang) != fallback_chain(_lang):
		for face in _faces:
			face.fallbacks = fallback_chain(lang)
	_lang = lang
	# The menu and every screen around the game share this one stage: the
	# same art, logo and type, words under the logo, entries below them, a
	# fan of character cards at the foot and, for the rules, a column of
	# text beside them.
	var screen := str(data.get("screen", "menu"))
	if screen != _screen:
		_screen = screen
		_intro = minf(_intro, REENTRY)
		_focus = int(data.get("focus", 0))
		_dealt.clear()
		_hover_card = null
	_rtl = bool(data.get("rtl", false))
	_tagline.text = str(data.get("tagline", ""))
	# A sitting's outcome is the headline of its screen.
	_tagline.add_theme_font_size_override("font_size", 34 if _screen == "over" else 23)
	_record.text = upper(str(data.get("record", "")), _lang)
	_stats.text = upper(str(data.get("stats", "")), _lang)
	_cast_label.text = upper(str(data.get("cast", "")), _lang)
	_rules.set_lines(data.get("rules", []), _rtl)
	_hints = PackedStringArray()
	for hint in str(data.get("legend", "")).split("    ", false):
		if not hint.strip_edges().begins_with("1–9"):
			_hints.append(hint.strip_edges())
	_set_entries(data.get("entries", []))
	_set_cards(data.get("roster", []), str(data.get("picked", "")))
	_layout()


func set_mode(mode: int) -> void:
	# 0 hidden (at the table), 1 a screen around the game, the art held
	# further back, 2 the menu.
	if mode == _mode:
		return
	if _mode == 0 and _shown <= 0.0 and mode > 0:
		# The whole opening plays once, when the game starts; coming back
		# from the table only the words and cards come in again.
		_intro = REENTRY if _opened else 0.0
		_opening = INTRO if _opened else 0.0
		_focus = 0
		_dealt.clear()
		_hover_card = null
	_mode = mode


func scroll(step: int) -> void:
	_rules.scroll(step)


func picked_preset() -> String:
	return _picked


func move_focus(step: int) -> void:
	if _entries.is_empty():
		return
	_skip()
	_focus = wrapi(_focus + step, 0, _entries.size())
	sound.emit("deal")


func activate_focus() -> void:
	if _entries.is_empty():
		return
	_skip()
	var entry: MenuEntry = _entries[clampi(_focus, 0, _entries.size() - 1)]
	_choose(entry)


func cycle_pick(step: int) -> void:
	if _cards.is_empty():
		return
	_skip()
	var at := 0
	for i in _cards.size():
		if _cards[i].preset == _picked:
			at = i
	var card: CastCard = _cards[wrapi(at + step, 0, _cards.size())]
	_pick(card)


func _process(delta: float) -> void:
	var step := minf(delta, 0.05)
	_clock += step
	if _intro < INTRO:
		_intro += step
	if _opening < INTRO:
		_opening += step
	else:
		_opened = true
	var goal := 1.0 if _mode > 0 else 0.0
	if _shown < goal:
		_shown = minf(goal, _shown + step / 0.35)
	elif _shown > goal:
		_shown = maxf(goal, _shown - step / 0.6)
	modulate.a = smoothstep(0.0, 1.0, _shown)
	visible = _shown > 0.0
	if not visible:
		return
	_sub = lerpf(_sub, 1.0 if _mode == 1 else 0.0, 1.0 - exp(-step * 8.0))
	_step_stage(step)
	_step_front(step)


func _input(event: InputEvent) -> void:
	if _mode == 0 or _intro >= INTRO:
		return
	var press: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if press:
		_skip()


func _skip() -> void:
	if _intro >= INTRO:
		return
	_intro = INTRO
	_opening = INTRO
	for j in _cards.size():
		_dealt[j] = true


func _phase(start: float, length: float, clock := -1.0) -> float:
	var t := _intro if clock < 0.0 else clock
	return smoothstep(0.0, 1.0, clampf((t - start) / length, 0.0, 1.0))


func _step_stage(step: float) -> void:
	var view := size
	if view.x < 2.0 or view.y < 2.0:
		return
	var cover := maxf(view.x / ART_SIZE.x, view.y / ART_SIZE.y)
	var base := -(ART_SIZE * cover - view) * ART_ALIGN
	var pivot := base + ART_PIVOT * ART_SIZE * cover
	var settle := 1.0 - pow(1.0 - clampf(_opening / 2.6, 0.0, 1.0), 3.0)
	var breathe := 0.5 - 0.5 * cos(TAU * _clock / 46.0)
	var zoom := lerpf(1.09, 1.012, settle) + 0.03 * breathe
	var mouse := get_local_mouse_position() / view - Vector2(0.5, 0.5)
	mouse = mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_parallax = _parallax.lerp(mouse * Vector2(-14.0, -9.0), 1.0 - exp(-step * 3.0))
	var scale_now := cover * zoom
	var origin := pivot - ART_PIVOT * ART_SIZE * scale_now + _parallax
	origin.x = clampf(origin.x, view.x - ART_SIZE.x * scale_now, 0.0)
	origin.y = clampf(origin.y, view.y - ART_SIZE.y * scale_now, 0.0)
	_stage.position = origin
	_stage.scale = Vector2(scale_now, scale_now)
	var flicker := 0.93 + 0.04 * sin(_clock * 2.1) + 0.03 * sin(_clock * 6.7 + 1.3) * sin(_clock * 0.9)
	_glow.modulate.a = 0.42 * flicker
	_core.modulate.a = 0.55 * flicker
	var lamp := 0.975 + 0.025 * flicker
	_art.modulate = Color(lamp, lamp, lamp)
	_art_mat.set_shader_parameter("blur", 2.2 * _sub)
	_art_mat.set_shader_parameter("dim", 0.3 * _sub)
	_scrim_mat.set_shader_parameter("dim", 0.34 * _sub)
	_fade.color.a = 1.0 - smoothstep(0.0, 1.0, clampf(_opening / 1.2, 0.0, 1.0))


func _step_front(step: float) -> void:
	var logo_in := _phase(0.35, 0.9, _opening)
	_logo.reveal = logo_in
	_logo.rule = _phase(0.8, 0.8, _opening)
	_logo.position.y = _logo_top + (1.0 - logo_in) * 14.0
	_logo.modulate.a = logo_in
	_logo.set_shine(_shine())
	_logo.queue_redraw()
	_logo_glow.modulate.a = logo_in * (0.82 + 0.18 * sin(_clock * 0.8))
	_tagline.modulate.a = _phase(1.0, 0.6)
	_record.modulate.a = _phase(1.1, 0.6)
	_stats.modulate.a = _record.modulate.a
	_rules.step(_intro - 1.15, step)
	for i in _entries.size():
		var entry: MenuEntry = _entries[i]
		entry.appear = _phase(1.1 + 0.08 * float(i), 0.5)
		entry.hot = i == _focus
		entry.step(step)
	_cast_label.modulate.a = _phase(1.35, 0.5)
	_cast_rule.modulate.a = _cast_label.modulate.a
	_cast_rule.visible = _cast_label.text != "" and not _cards.is_empty()
	for j in _cards.size():
		var card: CastCard = _cards[j]
		var start := 1.4 + 0.08 * float(j)
		card.appear = clampf((_intro - start) / 0.55, 0.0, 1.0)
		if _intro >= start and not _dealt.has(j):
			_dealt[j] = true
			sound.emit("deal")
		card.picked = card.crowned if not card.pickable else card.preset == _picked
		card.hot = card == _hover_card
		card.step(step)
	_legend.modulate.a = _phase(2.1, 0.6)


func _shine() -> float:
	var local := fmod(_clock - 1.6, 9.0)
	if _clock < 1.6 or local > 1.2:
		return -1.0
	return local / 1.2


func _layout() -> void:
	var view := size
	if view.x < 2.0 or view.y < 2.0 or _scrim_mat == null:
		return
	_scrim_mat.set_shader_parameter("view", view)
	_logo_top = clampf(view.y * 0.075, 40.0, 96.0)
	_logo.position = Vector2(LEFT, _logo_top)
	_logo_glow.size = Vector2(_logo.size.x + 320.0, _logo.size.y + 200.0)
	_logo_glow.position = Vector2(LEFT, _logo_top) + _logo.size * 0.5 - _logo_glow.size * 0.5
	var y := _logo_top + _logo.size.y + 8.0
	_tagline.position = Vector2(LEFT, y)
	y += 36.0 if _screen != "over" else 52.0
	# The record reads as a caption and its figures: "your record — 21 games".
	_record.position = Vector2(LEFT + 1.0, y)
	var record_w := _record.get_minimum_size().x if _record.text != "" else 0.0
	_stats.position = Vector2(LEFT + 1.0 + record_w + (14.0 if record_w > 0.0 else 0.0), y)
	y += 46.0
	for entry in _entries:
		entry.position = Vector2(LEFT - 36.0, y)
		entry.size = Vector2(480.0, entry.height())
		y += entry.height()
	# Cards with a line under them stand a little higher to make room for it.
	var noted := false
	for card in _cards:
		noted = noted or card.has_note()
	var fan_bottom := view.y - (62.0 if noted else 22.0)
	var radius := 1300.0
	var spread := (CastCard.CARD.x - 8.0) / radius
	var count := _cards.size()
	var center_x := LEFT - 12.0 + CastCard.CARD.x * 0.5 + radius * sin(spread * float(count - 1) * 0.5)
	for i in count:
		var card: CastCard = _cards[i]
		var angle := (float(i) - float(count - 1) * 0.5) * spread
		card.base_angle = angle
		card.base_pos = Vector2(center_x, fan_bottom + radius) + Vector2(sin(angle), -cos(angle)) * radius
		card.deal_from = Vector2(center_x, view.y + 200.0)
	var caption_y := fan_bottom - CastCard.CARD.y - 64.0
	_cast_label.position = Vector2(LEFT, caption_y)
	var caption_w := _cast_label.get_minimum_size().x
	_cast_rule.position = Vector2(LEFT + caption_w + 14.0, caption_y + 8.0)
	_cast_rule.size = Vector2(maxf(430.0 - caption_w - 14.0, 0.0), 1.0)
	var fan_right := 0.0
	for card in _cards:
		fan_right = maxf(fan_right, card.base_pos.x + CastCard.CARD.x * 0.5 + 16.0)
	# The rules stand in a column right of the menu, down to the legend.
	_rules.position = Vector2(maxf(LEFT + 400.0, view.x * 0.36), _logo_top + 4.0)
	_rules.size = Vector2(maxf(view.x - _rules.position.x - 60.0, 200.0), maxf(view.y - _rules.position.y - 84.0, 200.0))
	_fit_legend(view.x - 34.0 - fan_right - 40.0)
	_legend.reset_size()
	_legend.position = Vector2(view.x - 34.0 - _legend.size.x, view.y - 18.0 - _legend.size.y)


func _fit_legend(room: float) -> void:
	var gap := "   ·   "
	var line := gap.join(_hints)
	var face := _legend.get_theme_font("font")
	var font_size := _legend.get_theme_font_size("font_size")
	if _hints.size() < 2 or face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
		_legend.text = line
		return
	var half := ceili(_hints.size() / 2.0)
	_legend.text = gap.join(_hints.slice(0, half)) + "\n" + gap.join(_hints.slice(half))


func _set_entries(list: Array) -> void:
	# Each item: id, caption, primary; optionally marked (the current choice
	# in a list, such as the language) and compact (a long list).
	var same := list.size() == _entries.size()
	if same:
		for i in list.size():
			var item: Array = list[i]
			var entry: MenuEntry = _entries[i]
			if entry.id != str(item[0]) or entry.caption != upper(str(item[1]), _lang) or entry.primary != bool(item[2]):
				same = false
			elif entry.marked != (item.size() > 3 and bool(item[3])) or entry.compact != (item.size() > 4 and bool(item[4])):
				same = false
	if same:
		return
	for entry in _entries:
		entry.queue_free()
	_entries.clear()
	for i in list.size():
		var item: Array = list[i]
		var primary := bool(item[2])
		var entry := MenuEntry.new()
		entry.marked = item.size() > 3 and bool(item[3])
		entry.compact = item.size() > 4 and bool(item[4])
		entry.setup(str(item[0]), upper(str(item[1]), _lang), primary, i % 4, _primary_face if primary else _entry_face)
		entry.hovered.connect(_on_entry_hovered)
		entry.chosen.connect(_choose)
		_menu.add_child(entry)
		_entries.append(entry)
	_focus = clampi(_focus, 0, maxi(_entries.size() - 1, 0))


func _set_cards(roster: Array, current: String) -> void:
	# The menu's cards are the cast to sit as; on the other screens they are
	# the players at the table, each with a line under it (cards held, or
	# score and place), the first place crowned.
	var ids: Array = []
	for item in roster:
		ids.append(str(item["id"]))
	var have: Array = []
	for card in _cards:
		have.append(card.preset)
	if ids != have:
		for card in _cards:
			card.queue_free()
		_cards.clear()
		_hover_card = null
		for item in roster:
			var preset := str(item["id"])
			var texture := load(PORTRAIT % preset) as Texture2D
			var card := CastCard.new()
			card.setup(preset, str(item["name"]), texture, _card_face, _card_shader)
			card.hovered.connect(_on_card_hovered)
			card.chosen.connect(_pick)
			_fan.add_child(card)
			_cards.append(card)
	for i in roster.size():
		var item: Dictionary = roster[i]
		var card: CastCard = _cards[i]
		card.set_title(str(item["name"]))
		card.set_note(upper(str(item.get("note", "")), _lang), _note_face)
		card.rank = int(item.get("rank", 0))
		card.crowned = bool(item.get("crowned", false))
		card.set_pickable(bool(item.get("pickable", true)))
	if current != "":
		_picked = current
	elif _picked == "" and not ids.is_empty():
		_picked = str(ids[0])


func _on_entry_hovered(entry: MenuEntry) -> void:
	var at := _entries.find(entry)
	if at < 0 or at == _focus:
		return
	_focus = at
	sound.emit("deal")


func _choose(entry: MenuEntry) -> void:
	var at := _entries.find(entry)
	if at < 0:
		return
	_focus = at
	entry.flash()
	sound.emit("card")
	activated.emit(entry.id)


func _on_card_hovered(card: CastCard, on: bool) -> void:
	if on:
		if _hover_card != card:
			sound.emit("deal")
		_hover_card = card
	elif _hover_card == card:
		_hover_card = null
	_order_fan.call_deferred()


func _order_fan() -> void:
	for i in _cards.size():
		_fan.move_child(_cards[i], i)
	if _hover_card != null and is_instance_valid(_hover_card):
		_fan.move_child(_hover_card, -1)


func _pick(card: CastCard) -> void:
	if not card.pickable or card.preset == _picked:
		return
	_picked = card.preset
	sound.emit("flip")
	picked.emit(_picked)


func _build_stage() -> void:
	_stage = Control.new()
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.size = ART_SIZE
	add_child(_stage)
	_art = TextureRect.new()
	_art.texture = KEY_ART
	_art.size = ART_SIZE
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = _shader(ART_SHADER)
	_art.material = _art_mat
	_stage.add_child(_art)
	var lamp := LAMP * ART_SIZE
	var beam := ColorRect.new()
	beam.size = Vector2(640.0, 560.0)
	beam.position = lamp + Vector2(-320.0, 2.0)
	beam.mouse_filter = MOUSE_FILTER_IGNORE
	beam.material = _material(BEAM_SHADER % NOISE)
	_stage.add_child(beam)
	_glow = _light(lamp + Vector2(0.0, 8.0), 360.0, Color(1.0, 0.72, 0.4))
	_core = _light(lamp + Vector2(0.0, 2.0), 92.0, Color(1.0, 0.88, 0.62))
	for i in TEA.size():
		var spot: Vector2 = TEA[i][0] * ART_SIZE
		var area: Vector2 = TEA[i][1]
		var steam := ColorRect.new()
		steam.size = area
		steam.position = spot - Vector2(area.x * 0.5, area.y)
		steam.mouse_filter = MOUSE_FILTER_IGNORE
		var mat := _material(STEAM_SHADER % NOISE)
		mat.set_shader_parameter("seed", float(i) * 3.7 + 1.3)
		steam.material = mat
		_stage.add_child(steam)


func _build_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_scrim_mat = _material(SCRIM_SHADER)
	scrim.material = _scrim_mat
	add_child(scrim)
	var grain := ColorRect.new()
	grain.set_anchors_preset(PRESET_FULL_RECT)
	grain.mouse_filter = MOUSE_FILTER_IGNORE
	grain.material = _material(GRAIN_SHADER)
	add_child(grain)


func _build_front() -> void:
	_front = Control.new()
	_front.set_anchors_preset(PRESET_FULL_RECT)
	_front.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_front)
	_logo_glow = TextureRect.new()
	_logo_glow.texture = _radial(128, [Color(1.0, 0.76, 0.4, 0.34), Color(1.0, 0.7, 0.35, 0.1), Color(1.0, 0.7, 0.35, 0.0)], [0.0, 0.45, 1.0])
	_logo_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_logo_glow.mouse_filter = MOUSE_FILTER_IGNORE
	_logo_glow.material = _additive()
	_front.add_child(_logo_glow)
	_logo = Logo.new()
	_logo.setup(_face(DISPLAY, 600, 2, {"lnum": 1}), LOGO_SIZE, _shader(GOLD_SHADER))
	_front.add_child(_logo)
	_tagline = _text(_face(ITALIC, 400, 0), 23, Color(IVORY, 0.92))
	_record = _text(_face(SANS, 600, 3), 13, Color(IVORY, 0.62))
	_stats = _text(_face(SANS, 700, 3), 13, Color(GOLD, 0.95))
	_rules = RulesPanel.new()
	_rules.setup(_face(DISPLAY, 600, 0, {"lnum": 1}), _face(SANS, 500, 0))
	_front.add_child(_rules)
	_menu = Control.new()
	_menu.mouse_filter = MOUSE_FILTER_IGNORE
	_front.add_child(_menu)
	_cast_label = _text(_face(SANS, 700, 4), 13, GOLD)
	_cast_rule = ColorRect.new()
	_cast_rule.color = Color(GOLD, 0.4)
	_cast_rule.mouse_filter = MOUSE_FILTER_IGNORE
	_front.add_child(_cast_rule)
	_fan = Control.new()
	_fan.mouse_filter = MOUSE_FILTER_IGNORE
	_front.add_child(_fan)
	_legend = _text(_face(SANS, 500, 2), 13, Color(IVORY, 0.66))
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _text(face: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 5)
	_front.add_child(label)
	return label


func _face(base: Font, weight: int, spacing: int, features := {}) -> FontVariation:
	var face := FontVariation.new()
	var server := TextServerManager.get_primary_interface()
	face.base_font = base
	face.variation_opentype = {server.name_to_tag("wght"): weight}
	face.spacing_glyph = spacing
	if not features.is_empty():
		var tags := {}
		for feature in features:
			tags[server.name_to_tag(feature)] = features[feature]
		face.opentype_features = tags
	face.fallbacks = fallback_chain(_lang)
	_faces.append(face)
	return face


func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


func _material(code: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(code)
	return mat


func _additive() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func _radial(px: int, colors: Array, offsets: Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = px
	texture.height = px
	return texture


func _light(at: Vector2, diameter: float, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _radial(128, [Color(color, 1.0), Color(color, 0.3), Color(color, 0.0)], [0.0, 0.32, 1.0])
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(diameter, diameter)
	rect.position = at - rect.size * 0.5
	rect.mouse_filter = MOUSE_FILTER_IGNORE
	rect.material = _additive()
	_stage.add_child(rect)
	return rect


class Logo extends Control:
	var reveal := 0.0
	var rule := 0.0
	var _labels: Array = []
	var _font_size := 118
	var _cap := 0.0
	var _top := 20.0
	var _dash := Vector2.ZERO
	var _width := 0.0

	func setup(face: Font, font_size: int, shader: Shader) -> void:
		_font_size = font_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ascent := face.get_ascent(font_size)
		_cap = float(font_size) * 0.722
		var gap := float(font_size) * 0.085
		var bar := float(font_size) * 0.32
		var left_w := face.get_string_size("30", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var right_w := face.get_string_size("80", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_y := _top - (ascent - _cap)
		_dash = Vector2(left_w + gap, bar)
		var right_x := left_w + gap * 2.0 + bar
		_labels.append(_digits("30", face, shader, Vector2(0.0, label_y), ascent))
		_labels.append(_digits("80", face, shader, Vector2(right_x, label_y), ascent))
		_width = right_x + right_w
		size = Vector2(_width, _top * 2.0 + _cap)

	func set_shine(progress: float) -> void:
		var at := -1000.0 if progress < 0.0 else lerpf(-90.0, _width + 120.0, progress)
		for label in _labels:
			(label.material as ShaderMaterial).set_shader_parameter("shine", at)

	func _digits(value: String, face: Font, shader: Shader, at: Vector2, ascent: float) -> Label:
		var label := Label.new()
		label.text = value
		label.position = at
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", face)
		label.add_theme_font_size_override("font_size", _font_size)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.14, 0.08, 0.03))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 6)
		label.add_theme_constant_override("shadow_outline_size", 9)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("y0", ascent - _cap)
		mat.set_shader_parameter("y1", ascent)
		mat.set_shader_parameter("offset_x", at.x)
		label.material = mat
		add_child(label)
		return label

	func _draw() -> void:
		var mid := _top + _cap * 0.5
		var thick := float(_font_size) * 0.075
		var x0 := _dash.x
		var x1 := _dash.x + _dash.y
		var bar := PackedVector2Array([
			Vector2(x0, mid - thick * 0.5), Vector2(x1, mid - thick * 0.5),
			Vector2(x1, mid + thick * 0.5), Vector2(x0, mid + thick * 0.5),
		])
		var light := Color(0.99, 0.93, 0.74)
		var deep := Color(0.6, 0.42, 0.16)
		draw_polygon(bar, PackedColorArray([light, light, deep, deep]))
		var edge := bar.duplicate()
		edge.append(bar[0])
		draw_polyline(edge, Color(0.14, 0.08, 0.03), 2.0, true)
		var cx := (x0 + x1) * 0.5
		var d := float(_font_size) * 0.07
		var gem := PackedVector2Array([
			Vector2(cx, mid - d * 1.4), Vector2(cx + d, mid),
			Vector2(cx, mid + d * 1.4), Vector2(cx - d, mid),
		])
		draw_colored_polygon(gem, Color(0.7, 0.17, 0.13))
		var rim := gem.duplicate()
		rim.append(gem[0])
		draw_polyline(rim, Color(0.98, 0.86, 0.55), 1.5, true)
		if rule <= 0.0:
			return
		var center := _width * 0.5
		var span := (_width * 0.5 + 18.0) * rule
		var line := Color(0.87, 0.71, 0.4, 0.6)
		for y in [2.0, _top * 2.0 + _cap - 2.0]:
			draw_line(Vector2(center - span, y), Vector2(center + span, y), line, 1.0, true)
			_tip(Vector2(center - span, y), 3.0, line)
			_tip(Vector2(center + span, y), 3.0, line)
			_tip(Vector2(center, y), 4.5 * rule, Color(0.95, 0.8, 0.48, 0.9))

	func _tip(at: Vector2, r: float, color: Color) -> void:
		if r < 0.75:
			return
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.0, -r), at + Vector2(r, 0.0), at + Vector2(0.0, r), at + Vector2(-r, 0.0),
		]), color)


class MenuEntry extends Control:
	signal hovered(entry: Control)
	signal chosen(entry: Control)

	var id := ""
	var caption := ""
	var primary := false
	var marked := false
	var compact := false
	var suit := 0
	var hot := false
	var appear := 1.0
	var _h := 0.0
	var _flash := 0.0
	var _label: Label

	func setup(entry_id: String, text: String, is_primary: bool, suit_kind: int, face: Font) -> void:
		id = entry_id
		caption = text
		primary = is_primary
		suit = suit_kind
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_label = Label.new()
		_label.text = text
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_override("font", face)
		_label.add_theme_font_size_override("font_size", 30 if primary else (19 if compact else 22))
		_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
		_label.add_theme_constant_override("shadow_offset_y", 2)
		_label.add_theme_constant_override("shadow_outline_size", 8)
		add_child(_label)
		mouse_entered.connect(func() -> void: hovered.emit(self))

	func height() -> float:
		return 62.0 if primary else (40.0 if compact else 48.0)

	func flash() -> void:
		_flash = 1.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(self)
			accept_event()

	func step(delta: float) -> void:
		_h = lerpf(_h, 1.0 if hot else 0.0, 1.0 - exp(-delta * 14.0))
		_flash = maxf(0.0, _flash - delta * 3.0)
		var shown := smoothstep(0.0, 1.0, appear)
		var base := Color(0.87, 0.71, 0.4) if primary or marked else Color(0.95, 0.92, 0.85, 0.78)
		var color := base.lerp(Color(0.97, 0.92, 0.75), _h).lerp(Color.WHITE, _flash * 0.6)
		_label.add_theme_color_override("font_color", color)
		var text_size := _label.get_minimum_size()
		_label.size = text_size
		_label.position = Vector2(36.0 + 12.0 * _h - 30.0 * (1.0 - shown), (size.y - text_size.y) * 0.5)
		modulate.a = shown
		queue_redraw()

	func _draw() -> void:
		# The suit beside the focused entry, and always beside a marked one.
		var lit := maxf(_h, 0.8 if marked else 0.0)
		if lit < 0.01:
			return
		var mid := size.y * 0.5
		var red := suit == 0 or suit == 2
		var tone := Color(0.78, 0.2, 0.16, lit) if red else Color(0.95, 0.88, 0.68, lit)
		_suit(Vector2(13.0 + 5.0 * _h, mid), 7.0 if primary else 6.0, tone)
		if _h < 0.01:
			return
		var x0 := _label.position.x + 1.0
		var width := (_label.size.x - 4.0) * _h
		var y := _label.position.y + _label.size.y + 1.0
		var line := Color(0.87, 0.71, 0.4, 0.75 * _h)
		draw_line(Vector2(x0, y), Vector2(x0 + width, y), line, 1.2, true)
		var end := Vector2(x0 + width + 5.0, y)
		draw_colored_polygon(PackedVector2Array([
			end + Vector2(0.0, -3.0), end + Vector2(3.0, 0.0), end + Vector2(0.0, 3.0), end + Vector2(-3.0, 0.0),
		]), line)

	func _suit(c: Vector2, s: float, color: Color) -> void:
		match suit:
			0:
				_lobe(c + Vector2(-s * 0.47, -s * 0.28), s * 0.52, color)
				_lobe(c + Vector2(s * 0.47, -s * 0.28), s * 0.52, color)
				_tri([c + Vector2(-s * 0.97, -s * 0.12), c + Vector2(s * 0.97, -s * 0.12), c + Vector2(0.0, s * 0.98)], color)
			1:
				_lobe(c + Vector2(-s * 0.47, s * 0.16), s * 0.5, color)
				_lobe(c + Vector2(s * 0.47, s * 0.16), s * 0.5, color)
				_tri([c + Vector2(-s * 0.95, s * 0.04), c + Vector2(s * 0.95, s * 0.04), c + Vector2(0.0, -s * 1.0)], color)
				_tri([c + Vector2(0.0, s * 0.2), c + Vector2(s * 0.34, s * 1.0), c + Vector2(-s * 0.34, s * 1.0)], color)
			2:
				_tri([c + Vector2(0.0, -s), c + Vector2(s * 0.72, 0.0), c + Vector2(0.0, s)], color)
				_tri([c + Vector2(0.0, -s), c + Vector2(-s * 0.72, 0.0), c + Vector2(0.0, s)], color)
			_:
				_lobe(c + Vector2(0.0, -s * 0.48), s * 0.42, color)
				_lobe(c + Vector2(-s * 0.5, s * 0.12), s * 0.42, color)
				_lobe(c + Vector2(s * 0.5, s * 0.12), s * 0.42, color)
				_lobe(c + Vector2(0.0, -s * 0.02), s * 0.3, color)
				_tri([c + Vector2(0.0, 0.0), c + Vector2(s * 0.3, s * 1.0), c + Vector2(-s * 0.3, s * 1.0)], color)

	func _lobe(at: Vector2, r: float, color: Color) -> void:
		draw_circle(at, r, color, true, -1.0, true)

	func _tri(points: Array, color: Color) -> void:
		var poly := PackedVector2Array(points)
		draw_colored_polygon(poly, color)
		var edge := poly.duplicate()
		edge.append(poly[0])
		draw_polyline(edge, color, 1.0, true)


class CastCard extends Control:
	signal hovered(card: Control, on: bool)
	signal chosen(card: Control)

	const CARD := Vector2(100.0, 142.0)
	const EDGE := 18.0

	var preset := ""
	var picked := false
	var hot := false
	var appear := 1.0
	var base_angle := 0.0
	var base_pos := Vector2.ZERO
	var deal_from := Vector2.ZERO
	var rank := 0
	var crowned := false
	var pickable := true
	var _h := 0.0
	var _p := 0.0
	var _mat: ShaderMaterial
	var _name: Label
	var _note: Label
	var _badge: Control

	func setup(id: String, title: String, portrait: Texture2D, face: Font, shader: Shader) -> void:
		preset = id
		size = CARD + Vector2(EDGE, EDGE) * 2.0
		pivot_offset = Vector2(size.x * 0.5, EDGE + CARD.y)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var surface := ColorRect.new()
		surface.size = size
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat = ShaderMaterial.new()
		_mat.shader = shader
		_mat.set_shader_parameter("portrait", portrait)
		_mat.set_shader_parameter("card_px", CARD)
		_mat.set_shader_parameter("margin_px", EDGE)
		surface.material = _mat
		add_child(surface)
		_name = Label.new()
		_name.text = title
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.position = Vector2(EDGE, EDGE + CARD.y - 33.0)
		_name.size = Vector2(CARD.x, 26.0)
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name.add_theme_font_override("font", face)
		_name.add_theme_font_size_override("font_size", 17)
		_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		_name.add_theme_constant_override("shadow_offset_y", 1)
		_name.add_theme_constant_override("shadow_outline_size", 4)
		add_child(_name)
		_badge = Control.new()
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.size = size
		_badge.draw.connect(_draw_badge)
		add_child(_badge)
		mouse_entered.connect(func() -> void: hovered.emit(self, true))
		mouse_exited.connect(func() -> void: hovered.emit(self, false))

	func set_title(title: String) -> void:
		_name.text = title

	func set_note(text: String, face: Font) -> void:
		# A line under the card: cards in hand, or score and place.
		if _note == null:
			_note = Label.new()
			_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_note.add_theme_font_override("font", face)
			_note.add_theme_font_size_override("font_size", 11)
			_note.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
			_note.add_theme_constant_override("shadow_offset_y", 1)
			_note.add_theme_constant_override("shadow_outline_size", 5)
			_note.add_theme_constant_override("line_spacing", -2)
			# Kept to the card's width, two short lines at most, so the
			# notes of neighbouring cards never run into each other.
			_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_note.position = Vector2(EDGE - 2.0, EDGE + CARD.y + 6.0)
			_note.size = Vector2(CARD.x + 4.0, 30.0)
			add_child(_note)
		_note.text = text
		_note.visible = text != ""

	func has_note() -> bool:
		return _note != null and _note.text != ""

	func set_pickable(on: bool) -> void:
		pickable = on
		mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW

	func _draw_badge() -> void:
		# Place in the corner, and the crown over the first.
		if rank > 0:
			var at := Vector2(EDGE + 15.0, EDGE + 15.0)
			_badge.draw_circle(at, 12.0, Color(0.06, 0.04, 0.03, 0.88), true, -1.0, true)
			_badge.draw_arc(at, 12.0, 0.0, TAU, 32, Color(0.87, 0.71, 0.4, 0.95), 1.5, true)
			var face := _name.get_theme_font("font")
			var digit := str(rank)
			var span := face.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			_badge.draw_string(face, at + Vector2(-span.x * 0.5, 5.5), digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.88, 0.6))
		if crowned:
			var top := Vector2(EDGE + CARD.x * 0.5, EDGE - 9.0)
			_badge.draw_colored_polygon(Crown.points(top, 30.0), Color(0.95, 0.78, 0.4))
			_badge.draw_polyline(Crown.outline(top, 30.0), Color(0.3, 0.18, 0.06), 1.4, true)
			for jewel in Crown.jewels(top, 30.0):
				_badge.draw_circle(jewel, 2.4, Color(0.75, 0.18, 0.14), true, -1.0, true)

	func _has_point(point: Vector2) -> bool:
		return Rect2(Vector2(EDGE, EDGE), CARD).has_point(point)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(self)
			accept_event()

	func step(delta: float) -> void:
		var k := 1.0 - exp(-delta * 12.0)
		_h = lerpf(_h, 1.0 if hot else 0.0, k)
		_p = lerpf(_p, 1.0 if picked else 0.0, k)
		var dealt := 1.0 - pow(1.0 - appear, 3.0)
		var raise := maxf(_h, _p)
		var angle := base_angle * (1.0 - 0.55 * raise)
		var up := Vector2(sin(angle), -cos(angle))
		var spot := base_pos + up * (14.0 * _h + 24.0 * _p)
		rotation = lerpf(0.0, angle, dealt)
		position = deal_from.lerp(spot, dealt) - pivot_offset
		scale = Vector2.ONE * (1.0 + 0.045 * _p + 0.025 * _h)
		modulate.a = clampf(appear * 3.0, 0.0, 1.0)
		_mat.set_shader_parameter("picked", _p)
		_mat.set_shader_parameter("hover", _h)
		_name.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85).lerp(Color(1.0, 0.9, 0.62), _p))
		if _note != null:
			_note.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.82).lerp(Color(1.0, 0.86, 0.55), _p))
		_badge.queue_redraw()


class Crown:
	# The holder's crown, as the badge on the table and the screens draws it:
	# a band with three points, a jewel on each, `width` across centred on `at`.
	static func points(at: Vector2, width: float) -> PackedVector2Array:
		var w := width
		var raw := [
			Vector2(-0.5, 0.3), Vector2(-0.5, -0.04), Vector2(-0.56, -0.38), Vector2(-0.24, -0.1),
			Vector2(0.0, -0.46), Vector2(0.24, -0.1), Vector2(0.56, -0.38), Vector2(0.5, -0.04),
			Vector2(0.5, 0.3),
		]
		var out := PackedVector2Array()
		for p in raw:
			out.append(at + Vector2(p) * w)
		return out

	static func outline(at: Vector2, width: float) -> PackedVector2Array:
		var out := points(at, width)
		out.append(out[0])
		return out

	static func jewels(at: Vector2, width: float) -> PackedVector2Array:
		return PackedVector2Array([at + Vector2(-0.56, -0.38) * width, at + Vector2(0.0, -0.46) * width, at + Vector2(0.56, -0.38) * width])


class RulesPanel extends Control:
	# The rules, numbered, in a dark column that scrolls when they run long;
	# each comes in a moment after the one before.
	var _scroll: ScrollContainer
	var _list: VBoxContainer
	var _rows: Array = []
	var _number_face: Font
	var _text_face: Font
	var _key := ""

	func setup(number_face: Font, text_face: Font) -> void:
		_number_face = number_face
		_text_face = text_face
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		var back := Panel.new()
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.035, 0.025, 0.018, 0.86)
		box.border_color = Color(0.87, 0.71, 0.4, 0.3)
		box.set_border_width_all(1)
		box.set_corner_radius_all(10)
		box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
		box.shadow_size = 26
		back.add_theme_stylebox_override("panel", box)
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(back)
		_scroll = ScrollContainer.new()
		_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		_scroll.offset_left = 30.0
		_scroll.offset_top = 26.0
		_scroll.offset_right = -26.0
		_scroll.offset_bottom = -24.0
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		add_child(_scroll)
		_list = VBoxContainer.new()
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_theme_constant_override("separation", 12)
		_scroll.add_child(_list)

	func set_lines(lines: Array, rtl: bool) -> void:
		var key := JSON.stringify([lines, rtl])
		if key == _key:
			return
		_key = key
		for row in _rows:
			row.queue_free()
		_rows.clear()
		visible = not lines.is_empty()
		_scroll.scroll_vertical = 0
		for i in lines.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			var number := Label.new()
			number.text = str(i + 1)
			number.custom_minimum_size = Vector2(30.0, 0.0)
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			number.add_theme_font_override("font", _number_face)
			number.add_theme_font_size_override("font_size", 28)
			number.add_theme_color_override("font_color", Color(0.87, 0.71, 0.4))
			var line := Label.new()
			line.text = str(lines[i])
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if rtl else HORIZONTAL_ALIGNMENT_LEFT
			line.add_theme_font_override("font", _text_face)
			line.add_theme_font_size_override("font_size", 17)
			line.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.92))
			line.add_theme_constant_override("line_spacing", 3)
			if rtl:
				row.add_child(line)
				row.add_child(number)
			else:
				row.add_child(number)
				row.add_child(line)
			_list.add_child(row)
			_rows.append(row)

	func step(since: float, _delta: float) -> void:
		# `since`: seconds since the rules began to come in.
		modulate.a = smoothstep(0.0, 1.0, clampf(since / 0.4, 0.0, 1.0))
		for i in _rows.size():
			(_rows[i] as Control).modulate.a = smoothstep(0.0, 1.0, clampf((since - 0.07 * float(i)) / 0.45, 0.0, 1.0))

	func scroll(step: int) -> void:
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical + step * 64)
