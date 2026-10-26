# godot --headless --path . --script res://tools/generate_directional_animations.gd
# Produit des clips éditables à partir des cycles avant déjà adaptés au nain.
extends SceneTree

const MODEL = preload("res://Assets/Dwarf Character Dummy/Models/DwarfM@Dummy_HeadSeparated.fbx")
const SOURCE = preload("res://Assets/Animations/UAL1_Standard.glb")
const OUTPUT := "res://Assets/Animations/dwarf_directional.tres"
const FPS := 30.0
const LEGS := ["Left", "Right"]

var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D


func _initialize() -> void:
	generate.call_deferred()


func generate() -> void:
	model = MODEL.instantiate()
	root.add_child(model)
	player = AnimationPlayer.new()
	model.add_child(player)
	player.add_animation_library("Source", SOURCE)
	skeleton = model.get_node("Rig/GeneralSkeleton")
	var library := AnimationLibrary.new()
	for settings in [["Sprint", "Run", 0.35, 0.55], ["Crouch_Fwd", "Crouch", 0.7, 0.8]]:
		var source: Animation = SOURCE.get_animation(settings[0])
		library.add_animation(settings[1] + "_Backward", bake(source, settings[0], 0, true, 1.0, 1.0))
		# Le modèle regarde +Z (il est tourné de 180° dans player.tscn).
		library.add_animation(settings[1] + "_Left", bake(source, settings[0], PI / 2.0, false, settings[2], settings[3]))
		library.add_animation(settings[1] + "_Right", bake(source, settings[0], -PI / 2.0, false, settings[2], settings[3]))
	library.set_meta("source", "UAL1_Standard: Sprint, Crouch_Fwd")
	library.set_meta("generator", "res://tools/generate_directional_animations.gd")
	var error := ResourceSaver.save(library, OUTPUT)
	if error != OK:
		push_error("Impossible d'enregistrer les animations : " + error_string(error))
	else:
		print("Generated ", library.get_animation_list(), " -> ", OUTPUT)
	model.queue_free()
	await process_frame
	quit(0 if error == OK else 1)


func sample_pose(source_name: String, time: float) -> void:
	player.play("Source/" + source_name)
	player.seek(time, true)
	skeleton.force_update_all_bone_transforms()


func bake(source: Animation, source_name: String, yaw: float, reverse: bool, stride: float, lift: float) -> Animation:
	var frames := int(ceil(source.length * FPS))
	var centers: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var lowest: Array[float] = [INF, INF]
	if not is_zero_approx(yaw):
		for frame in range(frames):
			sample_pose(source_name, source.length * frame / frames)
			for side in range(2):
				var foot := skeleton.get_bone_global_pose(skeleton.find_bone(LEGS[side] + "Foot")).origin
				centers[side] += foot / frames
				lowest[side] = minf(lowest[side], foot.y)
	var result := Animation.new()
	result.length = source.length
	result.loop_mode = Animation.LOOP_LINEAR
	for track in range(source.get_track_count()):
		result.add_track(source.track_get_type(track))
		result.track_set_path(track, source.track_get_path(track))
		result.track_set_interpolation_type(track, source.track_get_interpolation_type(track))
		result.track_set_enabled(track, source.track_is_enabled(track))
	for frame in range(frames + 1):
		var time := source.length * frame / frames
		var source_time := fposmod(-time if reverse else time, source.length)
		if not is_zero_approx(yaw):
			sample_pose(source_name, source_time)
			for side in range(2):
				var foot := skeleton.get_bone_global_pose(skeleton.find_bone(LEGS[side] + "Foot")).origin
				var offset := foot - centers[side]
				var target := centers[side] + Basis(Vector3.UP, yaw) * Vector3(offset.x, 0, offset.z * stride)
				target.y = lowest[side] + (foot.y - lowest[side]) * lift
				# Conserver un peu d'écartement pour éviter le croisement des pieds.
				target.x += 0.065 if side == 0 else -0.065
				solve_leg(LEGS[side], target)
		for track in range(source.get_track_count()):
			var value: Variant
			match source.track_get_type(track):
				Animation.TYPE_POSITION_3D:
					value = source.position_track_interpolate(track, source_time)
				Animation.TYPE_ROTATION_3D:
					value = source.rotation_track_interpolate(track, source_time)
					var bone_name := str(source.track_get_path(track).get_subname(0))
					if not is_zero_approx(yaw) and bone_name in ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
						value = skeleton.get_bone_pose_rotation(skeleton.find_bone(bone_name))
				Animation.TYPE_SCALE_3D:
					value = source.scale_track_interpolate(track, source_time)
				_:
					assert(false, "Type de piste non pris en charge")
			result.track_insert_key(track, time, value)
	# Les bibliothèques humanoïdes contiennent aussi des os absents du nain.
	for track in range(result.get_track_count() - 1, -1, -1):
		var bone_name := str(result.track_get_path(track).get_subname(0))
		if skeleton.find_bone(bone_name) == -1:
			result.remove_track(track)
	return result


# IK à deux segments : déplacer le pied latéralement tout en gardant le buste
# face au regard et le genou orienté vers l'avant. Aucun IK n'est exécuté en jeu.
func solve_leg(side: String, target: Vector3) -> void:
	var thigh := skeleton.find_bone(side + "UpperLeg")
	var shin := skeleton.find_bone(side + "LowerLeg")
	var foot := skeleton.find_bone(side + "Foot")
	var hip_pose := skeleton.get_bone_global_pose(thigh)
	var knee_pose := skeleton.get_bone_global_pose(shin)
	var foot_pose := skeleton.get_bone_global_pose(foot)
	var upper_length := hip_pose.origin.distance_to(knee_pose.origin)
	var lower_length := knee_pose.origin.distance_to(foot_pose.origin)
	var direction := (target - hip_pose.origin).normalized()
	var distance := clampf(hip_pose.origin.distance_to(target), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	target = hip_pose.origin + direction * distance
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var pole := Vector3(0.15 if side == "Left" else -0.15, 0, 1)
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var knee_target := hip_pose.origin + direction * along + bend * height
	var thigh_delta := Quaternion((knee_pose.origin - hip_pose.origin).normalized(), (knee_target - hip_pose.origin).normalized())
	set_global_rotation(thigh, thigh_delta * hip_pose.basis.get_rotation_quaternion())
	knee_pose = skeleton.get_bone_global_pose(shin)
	var current_foot := skeleton.get_bone_global_pose(foot).origin
	var shin_delta := Quaternion((current_foot - knee_pose.origin).normalized(), (target - knee_pose.origin).normalized())
	set_global_rotation(shin, shin_delta * knee_pose.basis.get_rotation_quaternion())
	set_global_rotation(foot, foot_pose.basis.get_rotation_quaternion())


func set_global_rotation(bone: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * rotation).normalized())
	skeleton.force_update_all_bone_transforms()
