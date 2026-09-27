extends Node3D

const ROOM_FIT := 1.16
const SCALE := {
	"kaya": 1.0,
	"sis": 1.0,
	"kok": 1.0,
	"karaca": 1.0,
	"sirtlan": 1.0,
	"dere": 0.97,
}

var _skel: Skeleton3D
var _style := "lead"
var _time := 0.0
var _delta := 0.0
var _body: Dictionary = {}
var _nod: Dictionary = {}
var _yaw_axis: Dictionary = {}
var _table_radius := 0.85
var _surface_y := 0.81
var _shown_yaw := 0.0
var _player_yaw := 0.0
var _use_player_yaw := false
var _override := false
var _upper: Dictionary = {}
var _fore: Dictionary = {}
var _ov_yaw := 0.0
var _ov_reach := 0.0
var _ov_lean := 0.0

func setup(preset: String, style: String, table_radius: float, surface_y: float) -> void:
	_style = style
	_table_radius = table_radius
	_surface_y = surface_y
	var size: float = float(SCALE.get(preset, 1.0)) * ROOM_FIT
	scale = Vector3(size, size, size)
	_skel = find_child("Skeleton3D", true, false) as Skeleton3D
	_stop_clips()
	_cloth()
	_pose_legs()
	_plant_feet()
	_measure_arms()
	_skel.force_update_all_bone_transforms()
	_remember_axes()
	_body = _capture()
	_perform(true)


func set_look_yaw(yaw: float) -> void:
	_use_player_yaw = true
	_player_yaw = clampf(yaw, -1.05, 1.05)


func preview_at(time: float) -> void:
	_override = false
	_time = time
	_perform(true)


func preview_pose(yaw: float, reach: float, lean: float) -> void:
	_override = true
	_ov_yaw = yaw
	_ov_reach = clampf(reach, 0.0, 1.0)
	_ov_lean = lean
	_shown_yaw = yaw
	_perform(true)


func _process(delta: float) -> void:
	_delta = delta
	_time += delta
	_perform(false)


func _perform(snap: bool) -> void:
	if _skel == null:
		return
	var gesture := _gesture()
	var target_yaw: float = float(gesture["yaw"])
	if snap:
		_shown_yaw = target_yaw
	else:
		var blend := 1.0 - exp(-6.0 * maxf(_delta, 0.001))
		_shown_yaw = lerpf(_shown_yaw, target_yaw, blend)
	_restore(_body)
	var lean: float = float(gesture["lean"])
	var reach: float = float(gesture["reach"])
	if reach > 0.0:
		lean = maxf(lean, reach * 0.75)
	var breath := sin(_time * 1.35 + _phase()) * 0.03
	_set_extra("Spine02", breath + lean * 0.14, _shown_yaw * 0.34)
	_set_extra("Spine01", breath * 0.45 + lean * 0.06, _shown_yaw * 0.28)
	_set_extra("neck", 0.0, _shown_yaw * 0.16)
	var head_nod := sin(_time * 0.7 + _phase()) * 0.04 + lean * 0.06 + float(gesture["nod"])
	var head_yaw := sin(_time * 0.42 + _phase()) * 0.05 + _shown_yaw * 0.22
	_set_extra("Head", head_nod, head_yaw)
	_skel.force_update_all_bone_transforms()
	var right := _flat_face(0.0).cross(Vector3.UP).normalized()
	_solve_arm("Left", right, -0.14, 0.0)
	_solve_arm("Right", right, 0.14, reach)
	_skel.force_update_all_bone_transforms()


func _gesture() -> Dictionary:
	if _override:
		return {"yaw": _ov_yaw, "reach": _ov_reach, "lean": _ov_lean, "nod": 0.0}
	var cycle := fmod(_time + _phase(), 18.0)
	var lean := 0.0
	var reach := 0.0
	var yaw := 0.0
	var nod := 0.0
	match _style:
		"lead":
			lean = _pulse(cycle, 4.2, 6.4) * 0.85
			reach = _pulse(cycle, 6.4, 8.6)
			yaw = _pulse(cycle, 11.5, 14.2) * -0.75
		"watch":
			yaw = _pulse(cycle, 2.0, 6.5) * 0.7
			lean = _pulse(cycle, 8.0, 11.0) * 0.55
			nod = _pulse(cycle, 13.0, 15.0) * 0.18
		"settle":
			lean = _pulse(cycle, 1.5, 5.5) * -0.55
			yaw = _pulse(cycle, 7.0, 11.0) * 0.72
			lean += _pulse(cycle, 12.5, 15.5) * 0.4
	if _use_player_yaw:
		yaw = _player_yaw
	return {"yaw": yaw, "reach": reach, "lean": lean, "nod": nod}


func _pulse(cycle: float, start: float, finish: float) -> float:
	if cycle < start or cycle > finish:
		return 0.0
	var span := maxf(finish - start, 0.001)
	var edge := minf(0.4, span * 0.28)
	var u := 1.0
	if cycle < start + edge:
		u = (cycle - start) / edge
	elif cycle > finish - edge:
		u = (finish - cycle) / edge
	return u * u * (3.0 - 2.0 * u)


func _phase() -> float:
	match _style:
		"watch":
			return 2.2
		"settle":
			return 4.6
		_:
			return 0.4


func _measure_arms() -> void:
	for side in ["Left", "Right"]:
		var shoulder := _bone_world(side + "Arm")
		var elbow := _bone_world(side + "ForeArm")
		var hand := _bone_world(side + "Hand")
		_upper[side] = maxf(shoulder.distance_to(elbow), 0.08)
		_fore[side] = maxf(elbow.distance_to(hand), 0.08)


func _solve_arm(side: String, right: Vector3, lateral: float, reach: float) -> void:
	var shoulder := _bone_world(side + "Arm")
	var upper: float = float(_upper.get(side, 0.25))
	var fore: float = float(_fore.get(side, 0.24))
	var flat := Vector2(shoulder.x, shoulder.z)
	var ray := flat.normalized() if flat.length() > 0.05 else Vector2(0.0, 1.0)
	var shoulder_r := flat.length()
	var pull := upper * lerpf(0.62, 0.95, reach)
	var elbow_r := clampf(shoulder_r - pull, 0.36, _table_radius + 0.02)
	var side_offset := Vector2(right.x, right.z) * lateral
	var elbow_xz := ray * elbow_r + side_offset * 0.4
	var elbow := Vector3(elbow_xz.x, _surface_y, elbow_xz.y)
	var hand_r := maxf(elbow_r - fore * 0.9, 0.28)
	var hand_xz := ray * hand_r + side_offset * 0.15
	var hand := Vector3(hand_xz.x, _surface_y, hand_xz.y)
	_aim(side + "Arm", elbow - shoulder)
	_skel.force_update_all_bone_transforms()
	var joint := _bone_world(side + "ForeArm")
	_aim(side + "ForeArm", hand - joint)
	_skel.force_update_all_bone_transforms()
	joint = _bone_world(side + "ForeArm")
	var across := hand - joint
	across.y = minf(across.y, 0.015)
	_aim(side + "Hand", across + Vector3.DOWN * 0.25)
	_skel.force_update_all_bone_transforms()
	if _chain_hits_table(side):
		var lifted := hand
		lifted.y = _surface_y + 0.04
		var clear := Vector2(lifted.x, lifted.z)
		if clear.length() < _table_radius + 0.02:
			clear = ray * (_table_radius + 0.04)
			lifted.x = clear.x
			lifted.z = clear.y
		joint = _bone_world(side + "ForeArm")
		_aim(side + "ForeArm", lifted - joint)


func _chain_hits_table(side: String) -> bool:
	var joints: Array[Vector3] = [
		_bone_world(side + "Arm"),
		_bone_world(side + "ForeArm"),
		_bone_world(side + "Hand"),
	]
	for index in joints.size() - 1:
		for step in 5:
			var point: Vector3 = joints[index].lerp(joints[index + 1], float(step) / 4.0)
			if _inside_wood(point):
				return true
	return false


func _inside_wood(point: Vector3) -> bool:
	if point.y >= _surface_y - 0.012:
		return false
	return Vector2(point.x, point.z).length() < _table_radius - 0.01


func _flat_face(yaw: float) -> Vector3:
	var face := global_transform.basis.z
	face.y = 0.0
	if face.length() < 0.001:
		face = Vector3.FORWARD
	face = face.normalized()
	return Basis(Vector3.UP, yaw) * face


func _pose_legs() -> void:
	var forward := global_transform.basis.z
	var left := global_transform.basis.x
	var down := Vector3.DOWN
	_bend("Spine02", 0.06)
	_bend("Head", 0.08)
	_aim("LeftUpLeg", forward + left * 0.16 + down * 0.28)
	_aim("RightUpLeg", forward - left * 0.16 + down * 0.28)
	_aim("LeftLeg", forward * 0.12 + left * 0.04 + down)
	_aim("RightLeg", forward * 0.12 - left * 0.04 + down)
	_aim("LeftFoot", forward + down * 0.05)
	_aim("RightFoot", forward + down * 0.05)


func _bend(bone_name: String, angle: float) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return
	_skel.force_update_all_bone_transforms()
	var axis := _local_axis(idx, global_transform.basis.x)
	var pose := _skel.get_bone_pose_rotation(idx)
	_skel.set_bone_pose_rotation(idx, pose * Quaternion(axis, angle))


func _aim(bone_name: String, world_dir: Vector3) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0 or world_dir.length() < 0.001:
		return
	_skel.force_update_all_bone_transforms()
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	var local_target: Vector3 = global.basis.inverse() * (skel_basis.inverse() * world_dir.normalized())
	if local_target.length() < 0.001:
		return
	var extra := _quat_from_to(Vector3.UP, local_target.normalized())
	var pose := _skel.get_bone_pose_rotation(idx)
	_skel.set_bone_pose_rotation(idx, pose * extra)


func _remember_axes() -> void:
	for bone_name in ["Spine02", "Spine01", "neck", "Head"]:
		var idx := _skel.find_bone(bone_name)
		if idx < 0:
			continue
		_nod[bone_name] = _local_axis(idx, global_transform.basis.x)
		_yaw_axis[bone_name] = _local_axis(idx, global_transform.basis.y)


func _local_axis(idx: int, world_axis: Vector3) -> Vector3:
	var global := _skel.get_bone_global_pose(idx)
	var skel_basis := _skel.global_transform.basis.orthonormalized()
	return (global.basis.inverse() * (skel_basis.inverse() * world_axis)).normalized()


func _set_extra(bone_name: String, nod: float, yaw: float) -> void:
	var idx := _skel.find_bone(bone_name)
	if idx < 0 or not _body.has(bone_name):
		return
	var extra := Quaternion.IDENTITY
	if absf(nod) > 0.0001 and _nod.has(bone_name):
		extra = extra * Quaternion(_nod[bone_name], nod)
	if absf(yaw) > 0.0001 and _yaw_axis.has(bone_name):
		extra = extra * Quaternion(_yaw_axis[bone_name], yaw)
	var base: Quaternion = _body[bone_name]
	_skel.set_bone_pose_rotation(idx, base * extra)


func _plant_feet() -> void:
	_skel.force_update_all_bone_transforms()
	var lowest := 1000.0
	for bone_name in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
		var point := _bone_world(bone_name)
		if is_inf(point.x):
			continue
		lowest = minf(lowest, point.y)
	if lowest < 100.0:
		position.y -= lowest


func _bone_world(bone_name: String) -> Vector3:
	var idx := _skel.find_bone(bone_name)
	if idx < 0:
		return Vector3(INF, INF, INF)
	return _skel.global_transform * _skel.get_bone_global_pose(idx).origin


func _capture() -> Dictionary:
	var poses := {}
	for i in _skel.get_bone_count():
		poses[_skel.get_bone_name(i)] = _skel.get_bone_pose_rotation(i)
	return poses


func _restore(poses: Dictionary) -> void:
	for bone_name in poses.keys():
		var idx := _skel.find_bone(str(bone_name))
		if idx < 0:
			continue
		var rotation: Quaternion = poses[bone_name]
		_skel.set_bone_pose_rotation(idx, rotation)


func _stop_clips() -> void:
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	player.active = false
	player.stop()


func _cloth() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			mat.metallic = 0.0
			if mat.roughness_texture == null:
				mat.roughness = 0.86
			mat.metallic_specular = 0.18
			mesh.set_surface_override_material(surface, mat)


static func _quat_from_to(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.9995:
		return Quaternion.IDENTITY
	if dot < -0.9995:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length() < 0.001:
			axis = a.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	var cross := a.cross(b)
	return Quaternion(cross.x, cross.y, cross.z, 1.0 + dot).normalized()
