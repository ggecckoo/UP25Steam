extends SceneTree

const NAMES := ["kaya", "sis", "kok", "nida", "kul", "dere"]
const CLIPS := ["SitIdle", "PlayCard", "LeanIn", "LeanBack", "WatchLeft", "WatchRight"]


func _init() -> void:
	for preset in NAMES:
		var packed: PackedScene = load("res://assets/characters/%s.glb" % preset)
		if packed == null:
			push_error("missing " + preset)
			quit(1)
			return
		var model := packed.instantiate()
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skeleton == null or player == null:
			push_error("no rig on " + preset)
			quit(1)
			return
		if skeleton.find_bone("HandR") < 0 or skeleton.find_bone("Head") < 0:
			push_error("bones missing on " + preset)
			quit(1)
			return
		for clip in CLIPS:
			if not player.has_animation(clip):
				push_error(preset + " missing " + clip)
				quit(1)
				return
		model.free()
	if load("res://scenes/character_preview.tscn") == null:
		push_error("preview scene failed")
		quit(1)
		return
	print("OK")
	quit()
