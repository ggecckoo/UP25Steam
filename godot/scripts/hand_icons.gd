extends Node

# Pictures of the seated player's own fingered hand making each throw, for the
# rock-paper-scissors choice panels. Rendered once per character off screen
# and kept as plain textures.

signal rendered(preset: String)

const FPHands := preload("res://scripts/fp_hands.gd")
const SHAPES := ["rock", "paper", "scissors"]
const SIZE := Vector2i(320, 320)

var _cache := {}
var _queue: Array = []
var _busy := false


func icons(preset: String) -> Array:
	# Three textures in throw order, or empty while they are being drawn.
	if _cache.has(preset):
		return _cache[preset]
	if not _queue.has(preset):
		_queue.append(preset)
	if not _busy:
		_render_next()
	return []


func _render_next() -> void:
	if _queue.is_empty():
		return
	_busy = true
	var preset: String = _queue.pop_front()
	var port := SubViewport.new()
	port.size = SIZE
	port.transparent_bg = true
	port.own_world_3d = true
	port.msaa_3d = Viewport.MSAA_4X
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(port)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.66, 0.56)
	env.environment.ambient_light_energy = 1.3
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	port.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 3.4
	key.rotation = Vector3(-0.55, 0.65, 0.0)
	port.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.72, 1.0)
	rim.light_energy = 2.6
	rim.rotation = Vector3(-0.2, PI - 0.6, 0.0)
	port.add_child(rim)
	var front := DirectionalLight3D.new()
	front.light_color = Color(1.0, 0.9, 0.78)
	front.light_energy = 1.6
	front.rotation = Vector3(-0.15, 0.25, 0.0)
	port.add_child(front)
	var cam := Camera3D.new()
	cam.fov = 32.0
	port.add_child(cam)
	cam.global_position = Vector3(0.11, 0.13, 0.4)
	cam.look_at(Vector3(0.0, 0.1, 0.0))
	var hands := FPHands.new()
	port.add_child(hands)
	hands.setup(preset, 1.0, false)
	(hands.get_node("LeftHand") as Node3D).visible = false
	var out: Array = []
	for shape in SHAPES:
		# Fingers up and the back of the hand to the viewer, the way the
		# player sees their own hand come down at the table.
		hands.place("Right", Transform3D(Basis(Vector3.UP, 0.25), Vector3.ZERO))
		hands.shape("Right", {shape: 1.0})
		for _i in 3:
			await RenderingServer.frame_post_draw
		var image := port.get_texture().get_image()
		out.append(ImageTexture.create_from_image(image))
	_cache[preset] = out
	port.queue_free()
	_busy = false
	rendered.emit(preset)
	_render_next()
