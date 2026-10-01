extends Node

const CELL := Vector2i(180, 252)
const COLUMNS := 14
const ROWS := 4
const PAD := 5.0
const SIZE := Vector2(0.096, 0.134)

var material: StandardMaterial3D
var edge_material: StandardMaterial3D
var atlas_ready := false
var _meshes: Dictionary = {}
var _port: SubViewport


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.roughness = 0.52
	material.metallic_specular = 0.32
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.albedo_color = Color("F7F2E4")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	edge_material = StandardMaterial3D.new()
	edge_material.albedo_color = Color("E6DCC4")
	edge_material.roughness = 0.74
	edge_material.metallic = 0.0
	_port = SubViewport.new()
	_port.size = Vector2i(CELL.x * COLUMNS, CELL.y * ROWS)
	_port.transparent_bg = true
	_port.disable_3d = true
	_port.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Painter.new()
	painter.cell = CELL
	painter.pad = PAD
	painter.size = Vector2(_port.size)
	_port.add_child(painter)
	add_child(_port)
	_bake()


func _bake() -> void:
	for _i in 2:
		await RenderingServer.frame_post_draw
	if _port == null:
		return
	var image := _port.get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	material.albedo_color = Color.WHITE
	material.albedo_texture = ImageTexture.create_from_image(image)
	atlas_ready = true
	_port.queue_free()
	_port = null


func make_card(card) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(int(card.rank), int(card.suit))
	node.name = "Card%d" % int(card.id)
	node.set_meta("card_id", int(card.id))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


func _mesh(rank: int, suit: int) -> ArrayMesh:
	var key := rank * 4 + suit
	if _meshes.has(key):
		return _meshes[key]
	var face := _uv(rank, suit)
	var back := _uv(13, 0)
	var w := SIZE.x * 0.5
	var h := SIZE.y * 0.5
	var e := 0.0011
	var verts := PackedVector3Array([
		Vector3(-w, h, e), Vector3(w, h, e), Vector3(w, -h, e), Vector3(-w, -h, e),
		Vector3(w, h, -e), Vector3(-w, h, -e), Vector3(-w, -h, -e), Vector3(w, -h, -e),
	])
	var normals := PackedVector3Array()
	for _i in 4:
		normals.append(Vector3.BACK)
	for _i in 4:
		normals.append(Vector3.FORWARD)
	var uvs := PackedVector2Array([
		face.position, Vector2(face.end.x, face.position.y), face.end, Vector2(face.position.x, face.end.y),
		back.position, Vector2(back.end.x, back.position.y), back.end, Vector2(back.position.x, back.end.y),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var edge_verts := PackedVector3Array([
		Vector3(-w, h, e), Vector3(w, h, e), Vector3(w, h, -e), Vector3(-w, h, -e),
		Vector3(-w, -h, -e), Vector3(w, -h, -e), Vector3(w, -h, e), Vector3(-w, -h, e),
		Vector3(-w, h, e), Vector3(-w, h, -e), Vector3(-w, -h, -e), Vector3(-w, -h, e),
		Vector3(w, h, -e), Vector3(w, h, e), Vector3(w, -h, e), Vector3(w, -h, -e),
	])
	var edge_norm := PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
		Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
		Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT,
	])
	var edge := []
	edge.resize(Mesh.ARRAY_MAX)
	edge[Mesh.ARRAY_VERTEX] = edge_verts
	edge[Mesh.ARRAY_NORMAL] = edge_norm
	edge[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 5, 6, 4, 6, 7,
		8, 9, 10, 8, 10, 11,
		12, 13, 14, 12, 14, 15,
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, edge)
	mesh.surface_set_material(1, edge_material)
	_meshes[key] = mesh
	return mesh


func _uv(col: int, row: int) -> Rect2:
	var atlas := Vector2(CELL.x * COLUMNS, CELL.y * ROWS)
	var origin := Vector2(col * CELL.x, row * CELL.y) + Vector2.ONE * PAD
	return Rect2(origin / atlas, (Vector2(CELL) - Vector2.ONE * PAD * 2.0) / atlas)


class Painter extends Control:
	const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	const IVORY := Color("F7F2E4")
	const PAPER := Color("F2EBDA")
	const EDGE := Color(0.72, 0.66, 0.55)
	const INK := Color("1B1712")
	const LAC := Color("B3302B")
	const BRASS := Color("C9A44C")
	const BACK := Color("6E1B1A")

	var cell := Vector2i(180, 252)
	var pad := 5.0
	var serif := SystemFont.new()

	func _init() -> void:
		serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Palatino", "Book Antiqua", "DejaVu Serif", "Liberation Serif"])
		serif.font_weight = 700

	func _draw() -> void:
		for suit in 4:
			for rank in 13:
				_face(_rect(rank, suit), rank, suit)
		_back(_rect(13, 0))

	func _rect(col: int, row: int) -> Rect2:
		var origin := Vector2(col * cell.x, row * cell.y) + Vector2.ONE * pad
		return Rect2(origin, Vector2(cell) - Vector2.ONE * pad * 2.0)

	func _sheet(rect: Rect2, fill: Color, edge: Color, radius: int, width: int) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = edge
		box.set_border_width_all(width)
		box.set_corner_radius_all(radius)
		box.anti_aliasing = true
		draw_style_box(box, rect)

	func _text(center: Vector2, value: String, size: int, color: Color) -> void:
		var span := serif.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var lift := (serif.get_ascent(size) - serif.get_descent(size)) * 0.5
		draw_string(serif, center + Vector2(-span.x * 0.5, lift), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

	func _face(rect: Rect2, rank: int, suit: int) -> void:
		var ink := LAC if suit == 1 or suit == 2 else INK
		var label: String = RANKS[rank]
		var wide := label.length() > 1
		_sheet(rect, IVORY, EDGE, 14, 2)
		_index(rect.position + Vector2(25, 32), label, wide, suit, ink)
		draw_set_transform(rect.end, PI, Vector2.ONE)
		_index(Vector2(25, 32), label, wide, suit, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var mid := rect.get_center()
		_text(mid + Vector2(0, -22), label, 86 if wide else 106, ink)
		_suit(suit, mid + Vector2(0, 60), 58.0, ink)

	func _index(at: Vector2, label: String, wide: bool, suit: int, ink: Color) -> void:
		_text(at, label, 32 if wide else 40, ink)
		_suit(suit, at + Vector2(0, 38), 28.0, ink)

	func _back(rect: Rect2) -> void:
		_sheet(rect, PAPER, EDGE, 14, 2)
		var inner := rect.grow(-11.0)
		_sheet(inner, BACK, BRASS, 9, 3)
		var step := 20.0
		var row := 0
		var y := inner.position.y + 16.0
		while y < inner.end.y - 12.0:
			var x := inner.position.x + 16.0 + (step * 0.5 if row % 2 == 1 else 0.0)
			while x < inner.end.x - 12.0:
				_lozenge(Vector2(x, y), 6.5, Color(0.79, 0.64, 0.30, 0.55))
				x += step
			y += step * 0.75
			row += 1
		var mid := inner.get_center()
		draw_circle(mid, 33.0, BACK.darkened(0.25))
		draw_arc(mid, 33.0, 0.0, TAU, 64, BRASS, 3.0, true)
		_text(mid, "25", 34, BRASS)

	func _lozenge(c: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0), c + Vector2(0, -r)])
		draw_polyline(pts, color, 1.4, true)

	func _suit(suit: int, c: Vector2, s: float, color: Color) -> void:
		match suit:
			0:
				_spade(c, s, color)
			1:
				_heart(c, s, color)
			2:
				_diamond(c, s, color)
			_:
				_club(c, s, color)

	func _heart(c: Vector2, s: float, color: Color) -> void:
		var r := s * 0.27
		draw_circle(c + Vector2(-r * 0.92, -s * 0.12), r, color)
		draw_circle(c + Vector2(r * 0.92, -s * 0.12), r, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.86, -s * 0.05), c + Vector2(r * 1.86, -s * 0.05), c + Vector2(0, s * 0.5)]), color)

	func _spade(c: Vector2, s: float, color: Color) -> void:
		var r := s * 0.25
		draw_circle(c + Vector2(-r * 0.95, s * 0.08), r, color)
		draw_circle(c + Vector2(r * 0.95, s * 0.08), r, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.9, s * 0.02), c + Vector2(0, -s * 0.48), c + Vector2(r * 1.9, s * 0.02)]), color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.04, s * 0.12), c + Vector2(s * 0.04, s * 0.12), c + Vector2(s * 0.15, s * 0.48), c + Vector2(-s * 0.15, s * 0.48)]), color)

	func _diamond(c: Vector2, s: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.5), c + Vector2(s * 0.36, 0), c + Vector2(0, s * 0.5), c + Vector2(-s * 0.36, 0)]), color)

	func _club(c: Vector2, s: float, color: Color) -> void:
		var r := s * 0.2
		draw_circle(c + Vector2(0, -s * 0.24), r, color)
		draw_circle(c + Vector2(-s * 0.22, s * 0.05), r, color)
		draw_circle(c + Vector2(s * 0.22, s * 0.05), r, color)
		draw_circle(c + Vector2(0, -s * 0.03), r * 0.75, color)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.035, s * 0.02), c + Vector2(s * 0.035, s * 0.02), c + Vector2(s * 0.15, s * 0.48), c + Vector2(-s * 0.15, s * 0.48)]), color)
