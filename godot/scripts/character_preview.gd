extends Node3D

const NAMES := ["kaya", "sis", "kok", "karaca", "sirtlan", "dere"]
const SCALE := {
	"kaya": 1.0,
	"sis": 1.0,
	"kok": 1.0,
	"karaca": 1.0,
	"sirtlan": 1.0,
	"dere": 0.97,
}

var _models: Array[Node3D] = []
var _portraits: Array[Sprite3D] = []
var _layout: Dictionary = {}
var _index := 0


func _ready() -> void:
	for preset in NAMES:
		var packed: PackedScene = load("res://assets/characters/%s.glb" % preset)
		var model := packed.instantiate() as Node3D
		model.visible = false
		add_child(model)
		_cloth(model)
		_models.append(model)
		_layout[preset] = _fit(model, preset)
		var portrait := Sprite3D.new()
		var file := FileAccess.open("res://assets/characters/ref/%s-portre.png" % preset, FileAccess.READ)
		if file != null:
			var image := Image.new()
			if image.load_jpg_from_buffer(file.get_buffer(file.get_length())) == OK:
				portrait.texture = ImageTexture.create_from_image(image)
		portrait.pixel_size = 0.00092
		portrait.position = Vector3(-1.05, 1.12, 0.2)
		portrait.shaded = true
		portrait.visible = false
		add_child(portrait)
		_portraits.append(portrait)
	_show(0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_RIGHT or key.keycode == KEY_D:
		_show((_index + 1) % NAMES.size())
		return
	if key.keycode == KEY_LEFT or key.keycode == KEY_A:
		_show((_index - 1 + NAMES.size()) % NAMES.size())
		return
	var clip := ""
	match key.keycode:
		KEY_1:
			clip = "SitIdle"
		KEY_2:
			clip = "PlayCard"
		KEY_3:
			clip = "LeanIn"
		KEY_4:
			clip = "LeanBack"
		KEY_5:
			clip = "WatchLeft"
		KEY_6:
			clip = "WatchRight"
	if clip != "":
		_play(_models[_index], clip)


func _show(index: int) -> void:
	_index = index
	for i in NAMES.size():
		_models[i].visible = i == index
		_portraits[i].visible = i == index
	var preset: String = NAMES[index]
	var layout: Dictionary = _layout[preset]
	var center_x: float = layout["center_x"]
	var table_top: float = layout["table_top"]
	var front: float = layout["front"]
	var felt_mesh: BoxMesh = $Felt.mesh as BoxMesh
	var wood_mesh: BoxMesh = $Wood.mesh as BoxMesh
	var felt_z: float = front + 0.045 + felt_mesh.size.z * 0.5
	var wood_back: float = front + 0.02
	$Felt.position = Vector3(center_x, table_top - felt_mesh.size.y * 0.5, felt_z)
	$Wood.position = Vector3(center_x, table_top - felt_mesh.size.y - wood_mesh.size.y * 0.5, wood_back + wood_mesh.size.z * 0.5)
	$Caption.position = Vector3(center_x, float(layout["head_y"]) + 0.08, 0.0)
	$Caption.text = preset
	var look_y: float = clampf(float(layout["head_y"]) * 0.62, 0.72, 1.02)
	$Camera3D.look_at(Vector3(center_x * 0.28, look_y, 0.02))
	_play(_models[index], "SitIdle")


func _fit(model: Node3D, preset: String) -> Dictionary:
	model.position = Vector3(0.42, 0.0, 0.0)
	var s: float = float(SCALE[preset])
	model.scale = Vector3(s, s, s)
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel != null:
		return _fit_skeleton(model, skel)
	return _fit_mesh(model)


func _fit_skeleton(model: Node3D, skel: Skeleton3D) -> Dictionary:
	var foot_y := _lowest(skel, ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"])
	if foot_y < 100.0:
		model.position.y -= foot_y
	var hips := _bone_pos(skel, "Hips")
	if not is_inf(hips.x):
		model.position.x += 0.42 - hips.x
	var table_top := _lowest(skel, ["LeftHand", "RightHand"]) - 0.09
	var front := _forward_below(skel, table_top + 0.02)
	var crown := _bone_pos(skel, "head_end")
	if is_inf(crown.x):
		crown = _bone_pos(skel, "Head")
	hips = _bone_pos(skel, "Hips")
	return {
		"center_x": hips.x,
		"table_top": table_top,
		"front": front,
		"head_y": crown.y,
	}


func _fit_mesh(model: Node3D) -> Dictionary:
	var box := _world_aabb(model)
	if box.size.y < 0.05:
		return {"center_x": 0.42, "table_top": 0.62, "front": 0.2, "head_y": 1.4}
	model.position.y -= box.position.y
	box = _world_aabb(model)
	var center_x := box.position.x + box.size.x * 0.5
	model.position.x += 0.42 - center_x
	box = _world_aabb(model)
	var height := box.size.y
	var table_top := box.position.y + height * 0.40
	var head_room := box.position.y + height - 0.30
	if table_top > head_room:
		table_top = head_room
	return {
		"center_x": box.position.x + box.size.x * 0.5,
		"table_top": table_top,
		"front": box.position.z + box.size.z * 0.58,
		"head_y": box.position.y + height,
	}


func _bone_pos(skel: Skeleton3D, bone_name: String) -> Vector3:
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		return Vector3(INF, INF, INF)
	return skel.global_transform * skel.get_bone_global_pose(idx).origin


func _lowest(skel: Skeleton3D, names: Array) -> float:
	var lowest := 1000.0
	for bone_name in names:
		var point := _bone_pos(skel, str(bone_name))
		if is_inf(point.x):
			continue
		lowest = minf(lowest, point.y)
	return lowest


func _forward_below(skel: Skeleton3D, limit_y: float) -> float:
	var front := -1000.0
	for i in skel.get_bone_count():
		var point: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		if point.y <= limit_y:
			front = maxf(front, point.z)
	if front < -100.0:
		front = 0.2
	return front


func _world_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var piece: AABB = mesh.global_transform * mesh.get_aabb()
		if not found:
			merged = piece
			found = true
		else:
			merged = merged.merge(piece)
	return merged


func _cloth(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var source: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
		if source == null:
			continue
		var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		mat.metallic = 0.0
		if mat.roughness_texture == null:
			mat.roughness = 0.86
		mat.metallic_specular = 0.18
		mesh.set_surface_override_material(0, mat)


func _play(model: Node3D, clip: String) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(clip):
		return
	var anim := player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR if clip == "SitIdle" else Animation.LOOP_NONE
	player.play(clip)
