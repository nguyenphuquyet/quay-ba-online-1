class_name QBOCharacterRig
extends Node3D
## Nhân vật procedural có rig tay/chân thật, animation bằng code.
## Màu trang phục thay đổi theo hồ sơ người chơi (avatar style 0..4).

const JACKETS := [
	Color(0.13, 0.05, 0.09),
	Color(0.06, 0.09, 0.16),
	Color(0.1, 0.1, 0.11),
	Color(0.24, 0.06, 0.16),
	Color(0.09, 0.14, 0.12),
]
const SKIN_TONES := [
	Color(0.87, 0.71, 0.58),
	Color(0.75, 0.58, 0.44),
	Color(0.58, 0.41, 0.3),
	Color(0.4, 0.27, 0.2),
]

var style := 0
var anim_state := "idle"
var anim_speed := 0.0
var time := 0.0
var name_label: Label3D

## Model GLB (Sketchfab/CC) — nếu có file thì dùng thay cho nhân vật procedural.
const MODEL_PATHS := [
	"res://assets/models/characters/player.glb",
	"res://assets/models/characters/player.gltf",
	"res://assets/models/characters/anime_girl.glb",
	"res://assets/models/characters/anime_girl.gltf",
]
const MODEL_TARGET_HEIGHT := 1.78
const MODEL_YAW := PI
const STATE_CLIP_KEYS := {
	"idle": ["idle", "breath", "stand", "rest"],
	"walk": ["walk"],
	"run": ["run", "sprint", "jog"],
	"jump": ["jump", "fall", "air"],
	"sit": ["sit", "chair", "seated"],
	"dance": ["dance", "hip hop", "hiphop", "rumba", "samba", "party", "cycle talking", "walk fast", "talk"],
	"dj": ["dj", "mix", "scratch", "cycle talking", "talk"],
	"drink": ["drink", "sip", "toast", "cycle talking", "talk"],
	"computer": ["type", "typing", "keyboard", "computer", "use", "click", "inspect ground"],
}

var _glb := false
var _model_pivot: Node3D
var _anim: AnimationPlayer
var _clips := {}
var _current_clip := ""

var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _hair: MeshInstance3D
var _accessory: MeshInstance3D


func build(avatar_style: int, display_name: String) -> void:
	style = clampi(avatar_style, 0, JACKETS.size() - 1)
	if not _build_glb():
		_build_body()
	if display_name != "":
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.font_size = 44
		name_label.pixel_size = 0.0038
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.modulate = Color(1, 0.94, 0.82)
		name_label.outline_size = 10
		name_label.outline_modulate = Color(0, 0, 0, 0.9)
		name_label.position = Vector3(0, 2.05, 0)
		name_label.no_depth_test = false
		add_child(name_label)


func set_name_visible(visible_state: bool) -> void:
	if name_label != null:
		name_label.visible = visible_state


func _build_glb() -> bool:
	for path in MODEL_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("[RIG] Không nạp được " + path)
			continue
		var model := packed.instantiate() as Node3D
		if model == null:
			continue
		_model_pivot = Node3D.new()
		_model_pivot.name = "ModelPivot"
		_model_pivot.rotation.y = MODEL_YAW
		add_child(_model_pivot)
		_model_pivot.add_child(model)
		_anim = null
		for node in model.find_children("*", "AnimationPlayer", true, false):
			_anim = node as AnimationPlayer
			if _anim != null:
				break
		_collect_clips()
		if _anim == null or _clips.is_empty() or not _fit_model(model):
			printerr("[RIG] Model thiếu animation/khung xương, dùng rig procedural: " + path)
			_model_pivot.queue_free()
			_model_pivot = null
			_anim = null
			_clips.clear()
			continue
		_glb = true
		return true
	return false


func _build_body() -> void:
	var skin := QBOMaterials.skin(SKIN_TONES[style % SKIN_TONES.size()])
	var jacket := QBOMaterials.leather(JACKETS[style])
	var shirt := QBOMaterials.fabric(Color(0.9, 0.87, 0.8))
	var pants := QBOMaterials.fabric(Color(0.07, 0.065, 0.08))
	var shoes := QBOMaterials.leather(Color(0.03, 0.03, 0.035))
	var gold := QBOMaterials.gold()

	_root = Node3D.new()
	add_child(_root)

	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.92, 0)
	_root.add_child(_hips)
	_part(_hips, "Hips", Vector3(0, 0, 0), Vector3(0.34, 0.22, 0.24), pants)

	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.11, 0)
	_hips.add_child(_torso)
	_part(_torso, "Torso", Vector3(0, 0.28, 0), Vector3(0.42, 0.52, 0.26), jacket)
	_part(_torso, "Shirt", Vector3(0, 0.3, -0.125), Vector3(0.2, 0.42, 0.04), shirt)
	_part(_torso, "Chain", Vector3(0, 0.44, -0.14), Vector3(0.16, 0.03, 0.02), gold)
	_part(_torso, "Belt", Vector3(0, 0.04, 0), Vector3(0.36, 0.06, 0.25), gold)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.58, 0)
	_torso.add_child(_head)
	_ball(_head, "Neck", Vector3(0, 0.03, 0), 0.07, skin)
	_ball(_head, "Head", Vector3(0, 0.17, 0), 0.125, skin)
	# Mắt.
	for side in [-1, 1]:
		_part(_head, "Eye_%d" % side, Vector3(side * 0.045, 0.19, -0.108), Vector3(0.035, 0.02, 0.02), QBOMaterials.matte_black())
	_part(_head, "Mouth", Vector3(0, 0.12, -0.115), Vector3(0.055, 0.012, 0.02), QBOMaterials.fabric(Color(0.35, 0.12, 0.14)))
	_hair = _ball(_head, "Hair", Vector3(0, 0.235, 0.015), 0.135, QBOMaterials.fabric(Color(0.045, 0.035, 0.03)))
	_hair.scale = Vector3(1.02, 0.72, 1.02)
	# Trang sức.
	_accessory = _part(_head, "Earring", Vector3(0.12, 0.13, 0), Vector3(0.02, 0.04, 0.02), gold)

	# Tay.
	for side in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder_%d" % side
		shoulder.position = Vector3(side * 0.255, 0.48, 0)
		_torso.add_child(shoulder)
		_part(shoulder, "UpperArm", Vector3(0, -0.16, 0), Vector3(0.11, 0.32, 0.12), jacket)
		var elbow := Node3D.new()
		elbow.name = "Elbow_%d" % side
		elbow.position = Vector3(0, -0.32, 0)
		shoulder.add_child(elbow)
		_part(elbow, "Forearm", Vector3(0, -0.14, 0), Vector3(0.095, 0.28, 0.1), shirt)
		_ball(elbow, "Hand", Vector3(0, -0.29, 0), 0.06, skin)
		if side < 0:
			_arm_l = shoulder
			_elbow_l = elbow
		else:
			_arm_r = shoulder
			_elbow_r = elbow

	# Chân.
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.name = "Hip_%d" % side
		hip.position = Vector3(side * 0.105, -0.1, 0)
		_hips.add_child(hip)
		_part(hip, "Thigh", Vector3(0, -0.2, 0), Vector3(0.15, 0.4, 0.17), pants)
		var knee := Node3D.new()
		knee.name = "Knee_%d" % side
		knee.position = Vector3(0, -0.4, 0)
		hip.add_child(knee)
		_part(knee, "Shin", Vector3(0, -0.19, 0), Vector3(0.13, 0.38, 0.15), pants)
		_part(knee, "Shoe", Vector3(0, -0.39, -0.04), Vector3(0.14, 0.08, 0.26), shoes)
		if side < 0:
			_leg_l = hip
			_knee_l = knee
		else:
			_leg_r = hip
			_knee_r = knee


func _part(parent: Node3D, node_name: String, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = position
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, node_name: String, position: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = material
	mi.position = position
	parent.add_child(mi)
	return mi


func _fit_model(model: Node3D) -> bool:
	var box := _model_bounds(model)
	if box.size.y < 0.001:
		return false
	var s := MODEL_TARGET_HEIGHT / box.size.y
	var center := box.get_center()
	var holder := Node3D.new()
	holder.name = "ModelHolder"
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(-center.x * s, -box.position.y * s, -center.z * s)
	_model_pivot.add_child(holder)
	model.reparent(holder, false)
	return true


func _model_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := _relative_transform(mi, root)
		var box: AABB = xf * mi.get_aabb()
		result = box if not found else result.merge(box)
		found = true
	return result


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	# Không dùng global_transform: rig được build trước khi vào scene tree.
	var xf := Transform3D()
	var current: Node = node
	while current != null:
		if current is Node3D:
			xf = (current as Node3D).transform * xf
		if current == root:
			break
		current = current.get_parent()
	return xf


func _norm_anim(name: String) -> String:
	return name.to_lower().replace("|", " ").replace("_", " ").replace("-", " ").replace(".", " ")


func _collect_clips() -> void:
	_clips.clear()
	if _anim == null:
		return
	for lib_name in _anim.get_animation_library_list():
		var lib := _anim.get_animation_library(lib_name)
		if lib == null:
			continue
		for anim_name in lib.get_animation_list():
			var full: String = anim_name if String(lib_name).is_empty() else "%s/%s" % [lib_name, anim_name]
			_clips[full] = _norm_anim(anim_name)
	for anim_name in _anim.get_animation_list():
		if not _clips.has(anim_name):
			_clips[anim_name] = _norm_anim(anim_name)


func _pick_clip(state: String) -> String:
	var keys: Array = STATE_CLIP_KEYS.get(state, STATE_CLIP_KEYS["idle"])
	for key in keys:
		var kw := str(key)
		var best := ""
		var best_score := 1 << 24
		for clip_name in _clips:
			var n := str(_clips[clip_name])
			if n.find(kw) < 0:
				continue
			# Tên càng sát từ khóa càng ưu tiên (tránh "run" dính "runningjump").
			var score := n.length() - kw.length()
			if score < best_score or (score == best_score and (best == "" or str(clip_name) < best)):
				best_score = score
				best = str(clip_name)
		if best != "":
			return best
	return ""


func _animate_model(state: String, speed: float) -> void:
	if _anim == null:
		return
	var clip := _pick_clip(state)
	if clip == "":
		clip = _pick_clip("idle")
	if clip == "":
		return
	if clip != _current_clip:
		_current_clip = clip
		_anim.play(clip, 0.18)
	elif not _anim.is_playing():
		_anim.play(clip)
	var rate := 1.0
	match state:
		"walk":
			rate = clampf(speed / 2.2, 0.6, 1.6)
		"run":
			rate = clampf(speed / 5.6, 0.75, 1.55)
		"dance":
			rate = 1.25
		"dj":
			rate = 1.1
	_anim.speed_scale = rate
	# Emote không có clip riêng: thêm nhún/lắc nhẹ ở root cho có sức sống.
	var bob := 0.0
	var sway := 0.0
	match state:
		"dance":
			bob = absf(sin(time * 8.0)) * 0.05
			sway = sin(time * 4.0) * 0.22
		"dj":
			bob = absf(sin(time * 4.0)) * 0.02
			sway = sin(time * 2.0) * 0.08
	_model_pivot.position.y = lerpf(_model_pivot.position.y, bob, 0.2)
	_model_pivot.rotation.y = lerpf(_model_pivot.rotation.y, MODEL_YAW + sway, 0.15)


func animate(state: String, speed: float, delta: float) -> void:
	time += delta * (1.0 + speed * 0.15)
	anim_state = state
	anim_speed = speed
	if _glb:
		_animate_model(state, speed)
		return
	if _arm_l == null:
		return
	# Mặc định trả về tư thế nghỉ để animation nào cũng bắt đầu sạch.
	var t := time
	match state:
		"walk", "run":
			var intensity := 0.55 if state == "walk" else 1.0
			var stride := sin(t * (7.0 if state == "walk" else 10.5)) * intensity
			_leg_l.rotation.x = stride * 0.7
			_leg_r.rotation.x = -stride * 0.7
			_knee_l.rotation.x = maxf(0.0, -stride) * 1.0
			_knee_r.rotation.x = maxf(0.0, stride) * 1.0
			_arm_l.rotation.x = -stride * 0.75
			_arm_r.rotation.x = stride * 0.75
			_arm_l.rotation.z = 0.06
			_arm_r.rotation.z = -0.06
			_elbow_l.rotation.x = 0.35
			_elbow_r.rotation.x = 0.35
			_hips.position.y = 0.92 + absf(sin(t * (7.0 if state == "walk" else 10.5))) * 0.035
			_torso.rotation.x = 0.05 if state == "run" else 0.02
		"jump":
			_leg_l.rotation.x = -0.55
			_leg_r.rotation.x = -0.25
			_knee_l.rotation.x = 0.9
			_knee_r.rotation.x = 0.5
			_arm_l.rotation.x = -1.6
			_arm_r.rotation.x = -1.6
			_arm_l.rotation.z = 0.3
			_arm_r.rotation.z = -0.3
			_hips.position.y = 0.92
			_torso.rotation.x = 0.0
		"sit":
			_hips.position.y = 0.55
			_leg_l.rotation.x = 1.45
			_leg_r.rotation.x = 1.45
			_knee_l.rotation.x = -1.4
			_knee_r.rotation.x = -1.4
			_arm_l.rotation.x = 0.5
			_arm_r.rotation.x = 0.5
			_elbow_l.rotation.x = 0.6
			_elbow_r.rotation.x = 0.6
			_torso.rotation.x = -0.05
		"dance":
			var beat := sin(t * 8.0)
			_hips.position.y = 0.92 + absf(beat) * 0.05
			_hips.rotation.z = beat * 0.12
			_torso.rotation.z = -beat * 0.1
			_torso.rotation.y = sin(t * 4.0) * 0.18
			_arm_l.rotation.x = -2.2 + beat * 0.5
			_arm_r.rotation.x = -2.0 - beat * 0.5
			_arm_l.rotation.z = 0.5
			_arm_r.rotation.z = -0.5
			_elbow_l.rotation.x = 0.7 + beat * 0.3
			_elbow_r.rotation.x = 0.9 - beat * 0.3
			_leg_l.rotation.x = 0.1
			_leg_r.rotation.x = -0.1
			_knee_l.rotation.x = 0.15 + absf(beat) * 0.25
			_knee_r.rotation.x = 0.15
		"dj":
			var pulse := sin(t * 7.0)
			_arm_l.rotation.x = -1.5 + pulse * 0.25
			_arm_r.rotation.x = -1.4 - pulse * 0.25
			_arm_l.rotation.z = 0.55
			_arm_r.rotation.z = -0.55
			_elbow_l.rotation.x = 0.9
			_elbow_r.rotation.x = 0.9
			_head.rotation.x = pulse * 0.15
			_hips.position.y = 0.92 + absf(pulse) * 0.03
			_leg_l.rotation.x = 0.1
			_leg_r.rotation.x = -0.1
			_knee_l.rotation.x = 0.1
			_knee_r.rotation.x = 0.1
			_torso.rotation.y = pulse * 0.12
		"drink":
			_arm_r.rotation.x = -1.3
			_arm_r.rotation.z = -0.3
			_elbow_r.rotation.x = 1.9
			_head.rotation.x = -0.15
			_arm_l.rotation.x = 0.15
			_leg_l.rotation.x = 0.0
			_leg_r.rotation.x = 0.0
			_knee_l.rotation.x = 0.05
			_knee_r.rotation.x = 0.05
		"computer":
			_arm_l.rotation.x = -1.15
			_arm_r.rotation.x = -1.15
			_elbow_l.rotation.x = 0.5
			_elbow_r.rotation.x = 0.5
			_torso.rotation.x = 0.15
			_head.rotation.x = 0.2
			_leg_l.rotation.x = -0.35
			_leg_r.rotation.x = -0.35
			_knee_l.rotation.x = 0.55
			_knee_r.rotation.x = 0.55
			_hips.position.y = 0.78
		_:
			var breathe := sin(t * 1.8) * 0.02
			_hips.position.y = 0.92 + breathe * 0.4
			_torso.rotation.x = breathe
			_torso.rotation.y = 0.0
			_torso.rotation.z = 0.0
			_hips.rotation.z = 0.0
			_head.rotation.x = breathe * 0.6
			_arm_l.rotation.x = 0.06 + sin(t * 1.4) * 0.05
			_arm_r.rotation.x = -0.06 - sin(t * 1.4) * 0.05
			_arm_l.rotation.z = 0.1
			_arm_r.rotation.z = -0.1
			_elbow_l.rotation.x = 0.18
			_elbow_r.rotation.x = 0.18
			_leg_l.rotation.x = 0.0
			_leg_r.rotation.x = 0.0
			_knee_l.rotation.x = 0.04
			_knee_r.rotation.x = 0.04

	# Reset các khớp không dùng mỗi frame (tránh dính animation cũ).
	if not (state in ["dance", "dj"]):
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, 0.15)
