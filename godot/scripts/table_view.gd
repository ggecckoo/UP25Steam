extends Control

const SLOT_POS := [
	Vector2(458, 448),
	Vector2(582, 428),
	Vector2(706, 428),
	Vector2(830, 448),
]
const SLOT_SIZE := Vector2(74, 104)

var seats: Array = []
var your_turn := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x < 10.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1280, 800))
	_room()
	_table()
	for seat in seats:
		_bust(seat)
	_your_arms()


func _room() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("110D0B"))
	draw_rect(Rect2(0, 0, 1280, 300), Color("1A1411"))
	draw_line(Vector2(0, 292), Vector2(1280, 292), Color("3A2A22"), 8.0)
	for x in [180, 640, 1100]:
		draw_circle(Vector2(x, 78), 46, Color(0.95, 0.72, 0.38, 0.10))
		draw_circle(Vector2(x, 78), 18, Color(0.98, 0.82, 0.5, 0.55))
	draw_circle(Vector2(640, 430), 280, Color(0.85, 0.6, 0.28, 0.08))


func _table() -> void:
	var top := PackedVector2Array([
		Vector2(250, 372), Vector2(1030, 372), Vector2(1188, 648), Vector2(92, 648),
	])
	draw_colored_polygon(top, Color("4A2E1C"))
	var lip := PackedVector2Array([
		Vector2(230, 360), Vector2(1050, 360), Vector2(1210, 392), Vector2(70, 392),
	])
	draw_colored_polygon(lip, Color("6A4328"))
	draw_line(Vector2(300, 560), Vector2(980, 560), Color("C9A44C"), 3.0)
	draw_line(Vector2(612, 548), Vector2(612, 572), Color("F0DA9E"), 3.0)
	draw_line(Vector2(980, 548), Vector2(980, 572), Color("C9A44C"), 3.0)
	for seat in seats:
		var glass := Vector2(seat.pos.x, seat.pos.y + 118 * seat.scale)
		draw_rect(Rect2(glass.x - 8, glass.y, 16, 22), Color("D7E4EA"))
		draw_rect(Rect2(glass.x - 10, glass.y + 16, 20, 6), Color("8A5A34"))


func _bust(seat: Dictionary) -> void:
	var at: Vector2 = seat.pos
	var sc: float = seat.scale
	var bob := sin(Time.get_ticks_msec() / 520.0 + at.x) * 2.2
	if seat.thinking:
		bob += 6.0
	if seat.lit:
		draw_circle(at + Vector2(0, 30), 108 * sc, Color(0.95, 0.75, 0.4, 0.22))
	var shoulder := 78.0 * sc
	var torso := PackedVector2Array([
		at + Vector2(-shoulder, 28 * sc + bob),
		at + Vector2(shoulder, 28 * sc + bob),
		at + Vector2(shoulder * 0.72, 150 * sc + bob),
		at + Vector2(-shoulder * 0.72, 150 * sc + bob),
	])
	draw_colored_polygon(torso, seat.coat)
	draw_rect(Rect2(at.x - 16 * sc, at.y + 18 * sc + bob, 32 * sc, 22 * sc), seat.skin)
	var head := at + Vector2(0, -8 * sc + bob)
	draw_circle(head, 34 * sc, seat.skin)
	if seat.style == "bun":
		draw_circle(head + Vector2(0, -28 * sc), 16 * sc, seat.hair)
		draw_circle(head + Vector2(0, -8 * sc), 30 * sc, seat.hair)
		draw_circle(head + Vector2(0, 4 * sc), 24 * sc, seat.skin)
	elif seat.style == "short":
		draw_circle(head + Vector2(0, -16 * sc), 28 * sc, seat.hair)
		draw_rect(Rect2(head.x - 18 * sc, head.y + 10 * sc, 36 * sc, 5 * sc), Color("5C4030"))
	else:
		draw_arc(head + Vector2(0, -6 * sc), 18 * sc, PI * 1.15, PI * 1.85, 16, Color("E8EEF2"), 2.0)
		draw_circle(head + Vector2(-10 * sc, -2 * sc), 7 * sc, Color("D8E6EE"))
		draw_circle(head + Vector2(10 * sc, -2 * sc), 7 * sc, Color("D8E6EE"))
	draw_circle(head + Vector2(-10 * sc, -2 * sc), 3.2 * sc, Color("1B1712"))
	draw_circle(head + Vector2(10 * sc, -2 * sc), 3.2 * sc, Color("1B1712"))
	if seat.holder:
		var chip := at + Vector2(0, 132 * sc)
		draw_circle(chip, 14, Color("C9A44C"))
		draw_circle(chip, 7, Color("F0DA9E"))


func _your_arms() -> void:
	var left := PackedVector2Array([
		Vector2(0, 690), Vector2(170, 640), Vector2(230, 760), Vector2(0, 800),
	])
	var right := PackedVector2Array([
		Vector2(1280, 690), Vector2(1110, 640), Vector2(1050, 760), Vector2(1280, 800),
	])
	draw_colored_polygon(left, Color("1B2433"))
	draw_colored_polygon(right, Color("1B2433"))
	draw_circle(Vector2(188, 700), 28, Color("C9A07A"))
	draw_circle(Vector2(1092, 700), 28, Color("C9A07A"))
	if your_turn:
		draw_circle(Vector2(188, 700), 34, Color(0.95, 0.8, 0.45, 0.25))
		draw_circle(Vector2(1092, 700), 34, Color(0.95, 0.8, 0.45, 0.25))
