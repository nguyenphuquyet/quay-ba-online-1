class_name QBOPlayer
extends CharacterBody3D
## Player controller — first/third person, mobile joystick, tương tác, đồng bộ mạng.
## Client gửi trạng thái 15Hz; server kiểm tra tốc độ (xem Net).

const INTERACT_DISTANCE := 4.2
const GRAVITY := 9.8
const MOUSE_SENS := 0.0023

# Camera góc nhìn thứ ba kiểu GTA V: quỹ đạo quanh đầu, lệch vai phải,
# kéo gần khi vướng vật cản và bám có độ trễ nhẹ.
const CAM_DISTANCE := 3.25
const CAM_SHOULDER := 0.58
const CAM_PIVOT_HEIGHT := 1.62
const CAM_MIN_DISTANCE := 0.55
const CAM_SMOOTH := 20.0
const CAM_FOV := 68.0
const CAM_SPRINT_FOV := 74.0
const PITCH_MIN := -1.15
const PITCH_MAX := 0.85

var player_id := 1
var is_local_player := false
var display_name := "Người chơi"
var world: Node3D
var initial_yaw := PI
var avatar_style := 0

var third_person := true
var seated := false
var emote := ""

var camera: Camera3D
var rig: QBOCharacterRig

var _yaw := PI
var _pitch := -0.1
var _move_input := Vector2.ZERO
var _touch_move := Vector2.ZERO
var _touch_look := Vector2.ZERO
var _sprint_toggle := false
var _walk_phase := 0.0
var _anim := "idle"
var _network_timer := 0.0
var _prompt_timer := 0.0
var _current_prompt := ""
var _emote_timer := 0.0
var _remote_target := Vector3.ZERO
var _remote_yaw := 0.0
var _seated_position := Vector3.ZERO
var _seated_yaw := 0.0
var _controls_enabled := true
var _floor_snap := 0.4
var _cam_distance := CAM_DISTANCE


func _ready() -> void:
	name = "Player_%d" % player_id
	collision_layer = 2
	collision_mask = 1 | 8
	floor_snap_length = 0.35
	up_direction = Vector3.UP
	_yaw = initial_yaw
	rotation.y = _yaw
	_remote_target = global_position
	_remote_yaw = _yaw

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	rig = QBOCharacterRig.new()
	rig.name = "Rig"
	rig.build(avatar_style, display_name if not is_local_player else "")
	add_child(rig)
	rig.animate("idle", 0.0, 0.0)

	if is_local_player:
		# Đèn fill nhỏ để avatar đọc được ngay cả ở góc tối của club.
		var fill_light := OmniLight3D.new()
		fill_light.name = "PlayerFillLight"
		fill_light.light_color = Color(1.0, 0.84, 0.88)
		fill_light.light_energy = 0.55
		fill_light.omni_range = 4.5
		fill_light.shadow_enabled = false
		fill_light.position = Vector3(0, 1.5, -0.3)
		add_child(fill_light)
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.fov = 74.0
		camera.near = 0.06
		camera.far = 220.0
		camera.current = true
		add_child(camera)
		third_person = SettingsManager.camera_mode != "first"
		_apply_camera_mode()
		if not AppConfig.is_mobile:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		Net.chat_received.connect(_on_chat)
	else:
		set_physics_process(true)


func _exit_tree() -> void:
	if is_local_player and not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _ui_blocks_input():
			return
		_yaw -= event.relative.x * SettingsManager.mouse_sensitivity
		_pitch -= event.relative.y * SettingsManager.mouse_sensitivity * (-1.0 if SettingsManager.invert_y else 1.0)
		_pitch = clampf(_pitch, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("toggle_camera"):
		toggle_camera()
	elif event.is_action_pressed("jump"):
		_jump()
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("sprint"):
		_sprint_toggle = not _sprint_toggle
	elif event.is_action_pressed("dance"):
		play_emote("dance")
	elif event.is_action_pressed("emote"):
		play_emote("drink")


func _ui_blocks_input() -> bool:
	if App.ui == null:
		return false
	return bool(App.ui.call("is_input_blocked"))


func _web_typing() -> bool:
	if App.ui == null or not App.ui.has_method("is_web_typing"):
		return false
	return bool(App.ui.call("is_web_typing"))


func _ui_call(method: String, value: Variant = null) -> void:
	if App.ui == null:
		return
	if value == null:
		App.ui.call(method)
	else:
		App.ui.call(method, value)


func _physics_process(delta: float) -> void:
	if not is_local_player:
		_interpolate_remote(delta)
		return
	if seated:
		velocity = Vector3.ZERO
		global_position = _seated_position
		rotation.y = _seated_yaw
		_yaw = _seated_yaw
		_update_camera(delta)
		_animate(delta, 0.0)
		return

	_move_input = _read_move_input()

	var wish_dir := Vector3(_move_input.x, 0.0, -_move_input.y)
	wish_dir = wish_dir.rotated(Vector3.UP, _yaw)
	var speed := AppConfig.PLAYER_RUN_SPEED if (_sprint_toggle or Input.is_action_pressed("sprint")) else AppConfig.PLAYER_WALK_SPEED
	if AppConfig.is_mobile and _sprint_toggle:
		speed = AppConfig.PLAYER_RUN_SPEED
	var target := wish_dir * speed
	velocity.x = move_toward(velocity.x, target.x, 26.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 26.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.5
	move_and_slide()
	if third_person:
		_update_body_facing(delta)
	else:
		rotation.y = _yaw

	# Touch look áp dụng mỗi frame.
	if _touch_look.length_squared() > 0.0:
		_yaw -= _touch_look.x * 0.004
		_pitch = clampf(_pitch - _touch_look.y * 0.004, PITCH_MIN, PITCH_MAX)
		_touch_look = Vector2.ZERO

	_apply_emote_decay(delta)
	_update_camera(delta)
	_animate(delta, Vector2(velocity.x, velocity.z).length())
	_update_prompt(delta)
	_send_state(delta)


func _process(delta: float) -> void:
	if not is_local_player:
		return
	# Chuột bị nhả khi mở overlay; bắt lại khi đóng (trừ mobile).
	if not AppConfig.is_mobile:
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		var blocked := _ui_blocks_input()
		if captured and blocked:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif not captured and not blocked and not seated:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_body_facing(delta: float) -> void:
	## Thân nhân vật quay về hướng di chuyển (kiểu GTA V) thay vì khóa theo camera.
	var planar := Vector2(velocity.x, velocity.z)
	if planar.length() > 0.3:
		var move_yaw := atan2(-planar.x, -planar.y)
		rotation.y = lerp_angle(rotation.y, move_yaw, 1.0 - exp(-14.0 * delta))


func _update_camera(delta: float, snap := false) -> void:
	if camera == null:
		return
	if third_person:
		var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		# Hướng nhìn suy ra từ yaw/pitch; camera nằm ngược hướng này so với đầu nhân vật.
		var view_dir := (forward * cos(_pitch) + Vector3.UP * sin(_pitch)).normalized()
		var head := global_position + Vector3(0.0, CAM_PIVOT_HEIGHT, 0.0)
		var pivot := head + right * CAM_SHOULDER * 0.6
		var ideal := head + right * CAM_SHOULDER - view_dir * CAM_DISTANCE

		# Không để camera xuyên tường: kéo gần lại nếu có vật cản.
		var target_dist := CAM_DISTANCE
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(head, ideal)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			target_dist = maxf(CAM_MIN_DISTANCE, head.distance_to(hit["position"]) - 0.3)
		if snap or target_dist < _cam_distance:
			_cam_distance = target_dist
		else:
			_cam_distance = lerpf(_cam_distance, target_dist, 1.0 - exp(-5.0 * delta))

		var desired := head + right * CAM_SHOULDER - view_dir * _cam_distance
		desired.y = maxf(desired.y, 0.42)
		if snap:
			camera.global_position = desired
		else:
			camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-CAM_SMOOTH * delta))
		camera.look_at(pivot + view_dir * 6.0, Vector3.UP)
		camera.fov = lerpf(camera.fov, _target_fov(), 1.0 - exp(-5.0 * delta))
	else:
		camera.position = camera.position.lerp(Vector3(0, 1.62, 0), 1.0 - exp(-18.0 * delta))
		camera.rotation = Vector3(_pitch, 0, 0)
		camera.fov = lerpf(camera.fov, 74.0, 1.0 - exp(-5.0 * delta))


func _target_fov() -> float:
	var planar := Vector2(velocity.x, velocity.z).length()
	return CAM_SPRINT_FOV if planar > AppConfig.PLAYER_WALK_SPEED + 0.8 else CAM_FOV


func _animate(delta: float, horizontal_speed: float) -> void:
	var state := "idle"
	if seated:
		state = "sit"
	elif not is_on_floor():
		state = "jump"
	elif _emote_timer > 0.0:
		state = emote
	elif horizontal_speed > 4.6:
		state = "run"
	elif horizontal_speed > 0.15:
		state = "walk"
	_anim = state
	if rig != null:
		rig.animate(state, horizontal_speed, delta)
	if third_person:
		rig.visible = true
	else:
		rig.visible = false


func _apply_emote_decay(delta: float) -> void:
	if _emote_timer > 0.0:
		_emote_timer -= delta
		if _emote_timer <= 0.0:
			emote = ""


func play_emote(emote_name: String) -> void:
	if seated:
		return
	emote = emote_name
	_emote_timer = 6.0
	Net.send_player_state(global_position, rotation.y, emote_name, 0)


func toggle_camera() -> void:
	third_person = not third_person
	SettingsManager.camera_mode = "third" if third_person else "first"
	SettingsManager.save_settings()
	_apply_camera_mode()
	_ui_call("set_camera_mode", third_person)


func _apply_camera_mode() -> void:
	if camera == null:
		return
	if third_person:
		_cam_distance = CAM_DISTANCE
		rig.visible = true
		rig.set_name_visible(false)
		_update_camera(0.016, true)
	else:
		camera.position = Vector3(0, 1.62, 0)
		camera.rotation = Vector3(_pitch, 0, 0)
		camera.fov = 74.0
		rig.visible = false


func _read_move_input() -> Vector2:
	## Bàn phím (WASD/phím mũi tên) + joystick cảm ứng được cộng gộp.
	if not _controls_enabled or _ui_blocks_input() or _web_typing():
		return Vector2.ZERO
	var keyboard := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)
	return (keyboard + _touch_move).limit_length(1.0)


func set_touch_move(value: Vector2) -> void:
	_touch_move = value.limit_length(1.0)


func add_touch_look(delta: Vector2) -> void:
	_touch_look += delta


func set_sprint_toggle(value: bool) -> void:
	_sprint_toggle = value


func _jump() -> void:
	if seated or not is_on_floor():
		return
	velocity.y = AppConfig.PLAYER_JUMP_VELOCITY


func _try_interact() -> void:
	if seated:
		Net.request_interaction("self", "stand", {})
		return
	var target := _find_interactable()
	if target == null:
		return
	Net.request_interaction(target.interact_id, target.action, target.payload)


func _find_interactable() -> QBOInteractable:
	if camera == null:
		return null
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * INTERACT_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider = hit.get("collider")
	if collider is QBOInteractable and collider.enabled:
		return collider
	return null


func _update_prompt(delta: float) -> void:
	_prompt_timer -= delta
	if _prompt_timer > 0.0:
		return
	_prompt_timer = 0.12
	var prompt := ""
	var target := _find_interactable()
	if target != null:
		prompt = target.prompt
	elif seated:
		prompt = "Nhấn E để đứng dậy"
	if prompt != _current_prompt:
		_current_prompt = prompt
		_ui_call("set_interaction_prompt", prompt)


func _send_state(delta: float) -> void:
	_network_timer -= delta
	if _network_timer > 0.0:
		return
	_network_timer = 1.0 / float(AppConfig.NETWORK_TICK_RATE)
	var flags := 1 if seated else 0
	Net.send_player_state(global_position, rotation.y, _anim, flags)


# ------------------------------------------------------------------ remote

func apply_remote_state(state: Dictionary) -> void:
	_remote_target = state.get("position", _remote_target)
	_remote_yaw = float(state.get("yaw", _remote_yaw))
	var anim := str(state.get("animation", "idle"))
	if rig != null and anim != "":
		_anim = anim
	seated = (int(state.get("flags", 0)) & 1) == 1


func _interpolate_remote(delta: float) -> void:
	global_position = global_position.lerp(_remote_target, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_yaw, clampf(delta * 10.0, 0.0, 1.0))
	if rig != null:
		rig.animate(_anim, 0.0, delta)
		rig.set_name_visible(true)


func apply_correction(position: Vector3) -> void:
	global_position = position
	_remote_target = position
	velocity = Vector3.ZERO


func sit_at(position: Vector3, yaw: float) -> void:
	seated = true
	_seated_position = position
	_seated_yaw = yaw
	velocity = Vector3.ZERO
	global_position = position
	rotation.y = yaw
	_yaw = yaw
	_emote_timer = 0.0
	emote = ""
	_ui_call("set_interaction_prompt", "Nhấn E để đứng dậy")


func stand_up() -> void:
	if not seated:
		return
	seated = false
	global_position = _seated_position + Vector3(0, 0.6, 0)
	velocity = Vector3.ZERO


func teleport_to(position: Vector3, yaw: float) -> void:
	global_position = position
	_yaw = yaw
	rotation.y = yaw
	_remote_target = position
	velocity = Vector3.ZERO
	_cam_distance = CAM_DISTANCE
	_update_camera(0.016, true)


func set_controls_enabled(value: bool) -> void:
	_controls_enabled = value
	if not value:
		_move_input = Vector2.ZERO
		_touch_move = Vector2.ZERO


func _on_chat(_id: int, _name: String, _text: String) -> void:
	if not is_local_player:
		return
	# Người chơi khác đang nói: hiển thị bong bóng chat ngắn phía trên đầu họ.
	pass
