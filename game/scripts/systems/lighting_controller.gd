class_name QBOLightingController
extends Node3D
## Lighting Controller — preset đèn club, đồng bộ qua Net, phản ứng theo beat.
## Tối ưu: chỉ một số đèn có shadow, LED dùng emission thay vì thêm realtime light.

const PRESETS := {
	"chill": {
		"label": "Chill",
		"colors": [Color(1.0, 0.66, 0.4), Color(0.85, 0.5, 0.65), Color(0.5, 0.4, 0.8)],
		"energy": 1.15,
		"speed": 0.25,
		"strobe": false,
		"beat": false,
		"led": Color(1.0, 0.62, 0.42),
	},
	"lounge": {
		"label": "Lounge",
		"colors": [Color(0.95, 0.75, 0.45), Color(0.75, 0.55, 0.8), Color(0.4, 0.3, 0.6)],
		"energy": 1.0,
		"speed": 0.4,
		"strobe": false,
		"beat": false,
		"led": Color(0.95, 0.72, 0.42),
	},
	"party": {
		"label": "Party",
		"colors": [Color(1.0, 0.14, 0.45), Color(0.2, 0.7, 1.0), Color(0.75, 0.3, 1.0)],
		"energy": 2.4,
		"speed": 1.1,
		"strobe": false,
		"beat": true,
		"led": Color(1.0, 0.2, 0.5),
	},
	"edm": {
		"label": "EDM",
		"colors": [Color(0.15, 0.8, 1.0), Color(1.0, 0.2, 0.6), Color(1.0, 1.0, 1.0)],
		"energy": 3.2,
		"speed": 2.2,
		"strobe": true,
		"beat": true,
		"led": Color(0.2, 0.8, 1.0),
	},
	"cyberpunk": {
		"label": "Cyberpunk",
		"colors": [Color(0.1, 0.95, 0.85), Color(0.7, 0.2, 1.0), Color(1.0, 0.1, 0.7)],
		"energy": 2.5,
		"speed": 1.4,
		"strobe": false,
		"beat": true,
		"led": Color(0.3, 0.9, 1.0),
	},
	"chinese_neon": {
		"label": "Chinese Neon",
		"colors": [Color(1.0, 0.1, 0.18), Color(1.0, 0.72, 0.25), Color(0.95, 0.35, 0.1)],
		"energy": 2.7,
		"speed": 1.0,
		"strobe": false,
		"beat": true,
		"led": Color(1.0, 0.28, 0.2),
	},
	"vip": {
		"label": "VIP",
		"colors": [Color(1.0, 0.8, 0.5), Color(0.9, 0.6, 0.9), Color(0.9, 0.9, 0.6)],
		"energy": 1.6,
		"speed": 0.5,
		"strobe": false,
		"beat": false,
		"led": Color(1.0, 0.8, 0.5),
	},
	"blackout": {
		"label": "Blackout",
		"colors": [Color(0.02, 0.02, 0.03), Color(0.02, 0.02, 0.03), Color(0.02, 0.02, 0.03)],
		"energy": 0.0,
		"speed": 0.0,
		"strobe": false,
		"beat": false,
		"led": Color(0.01, 0.01, 0.01),
	},
}

const STORAGE_KEY := "qbo_lighting_preset"

var current_preset := "party"
var intensity := 1.0
var speed := 1.0
var beat_enabled := true

var _groups := {"moving_head": [], "wash": [], "ceiling": [], "accent": []}
var _leds: Array = []
var _lasers: Array = []
var _time := 0.0
var _beat_energy := 0.0
var _strobe_phase := 0.0
var _target_colors: Array = []
var _target_energy := 1.0
var _update_accum := 0.0


func _ready() -> void:
	name = "LightingController"
	_target_colors = PRESETS["party"]["colors"]


func register_light(kind: String, node: Node3D) -> void:
	if not _groups.has(kind):
		_groups[kind] = []
	var light := _resolve_light(node)
	if light == null:
		_groups[kind].append(node)
		return
	_groups[kind].append(node)
	var base_color: Color = light.light_color
	var base_energy: float = light.light_energy
	node.set_meta("base_color", base_color)
	node.set_meta("base_energy", base_energy)
	node.set_meta("phase", randf() * TAU)


func _resolve_light(node: Node) -> Light3D:
	if node is Light3D:
		return node
	for child in node.get_children():
		if child is Light3D:
			return child
		var nested := _resolve_light(child)
		if nested != null:
			return nested
	return null


func register_led(mesh: MeshInstance3D, color: Color) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = QBOMaterials.led_dynamic(color)
		mesh.material_override = mat
	else:
		mat = mat.duplicate()
		mesh.material_override = mat
	_leds.append({"mesh": mesh, "mat": mat, "base": color, "phase": randf() * TAU})


## Đăng ký một cụm laser sân khấu. `beams` là các cặp {mesh, mat} dùng
## ShaderMaterial laser_beam.gdshader; `spot` là đèn hắt sàn đi kèm.
func register_laser(pivot: Node3D, beams: Array, spot: Light3D = null, base_yaw := 0.0, dots: Array = []) -> void:
	var phase := randf() * TAU
	pivot.set_meta("phase", phase)
	_lasers.append({
		"pivot": pivot,
		"beams": beams,
		"spot": spot,
		"phase": phase,
		"base_yaw": base_yaw,
		"dots": dots,
	})
	if spot != null:
		spot.set_meta("base_energy", spot.light_energy)
		spot.set_meta("base_color", spot.light_color)


func laser_count() -> int:
	return _lasers.size()


func apply_preset(preset: String, intensity_value := 1.0, speed_value := 1.0) -> void:
	if not PRESETS.has(preset):
		preset = "party"
	current_preset = preset
	intensity = clampf(intensity_value, 0.0, 2.5)
	speed = clampf(speed_value, 0.0, 3.0)
	var data: Dictionary = PRESETS[preset]
	_target_colors = data["colors"]
	_target_energy = float(data["energy"]) * intensity
	beat_enabled = bool(data["beat"])
	_apply_leds_color(data["led"])


func apply_state(state: Dictionary) -> void:
	var preset := str(state.get("preset", current_preset))
	var intensity_value := float(state.get("intensity", 1.0))
	var speed_value := float(state.get("speed", 1.0))
	apply_preset(preset, intensity_value, speed_value)


func build_state() -> Dictionary:
	return {"preset": current_preset, "intensity": intensity, "speed": speed}


func set_beat_sync(value: bool) -> void:
	beat_enabled = value


func beat(strength := 1.0) -> void:
	_beat_energy = minf(1.6, _beat_energy + strength * 0.8)


func _process(delta: float) -> void:
	_time += delta * speed
	_beat_energy = maxf(0.0, _beat_energy - delta * 2.6)
	_update_accum += delta
	var data: Dictionary = PRESETS.get(current_preset, PRESETS["party"])
	var strobe := bool(data.get("strobe", false))
	_strobe_phase += delta * 12.0
	var pulse := 1.0 + (_beat_energy * 0.55 if beat_enabled else 0.0)
	if strobe and _beat_energy > 0.4:
		pulse += 0.6

	# Chỉ cập nhật đèn mỗi frame thứ 2 để giảm chi phí trên mobile.
	if _update_accum < 0.016:
		return
	_update_accum = 0.0

	var index := 0
	for kind in ["moving_head", "wash", "ceiling", "accent"]:
		for node in _groups.get(kind, []):
			var light := _resolve_light(node)
			if light == null:
				continue
			var colors: Array = _target_colors
			var color: Color = colors[index % colors.size()]
			var phase := float(node.get_meta("phase", 0.0))
			var base_energy := float(node.get_meta("base_energy", light.light_energy))
			var wobble := 0.85 + 0.15 * sin(_time * 2.0 + phase)
			light.light_color = light.light_color.lerp(color, 0.08)
			light.light_energy = lerpf(light.light_energy, base_energy * _target_energy * 0.62 * wobble * pulse, 0.12)
			light.visible = _target_energy > 0.001 or light.light_energy > 0.01
			if kind == "moving_head":
				node.rotation.y = sin(_time * 0.9 + phase) * 1.1
				node.rotation.z = sin(_time * 0.6 + phase * 1.7) * 0.35
			index += 1

	# Laser sân khấu: quét qua lại, đổi màu theo preset và nhấp theo beat.
	var active := _target_energy > 0.001
	var laser_index := 0
	for entry in _lasers:
		var pivot: Node3D = entry["pivot"]
		if not is_instance_valid(pivot):
			continue
		var phase := float(entry["phase"])
		# Quả cầu xoay đều để chùm tia và vòng đốm màu quét quanh sàn.
		pivot.rotation.y = float(entry["base_yaw"]) + _time * 0.3 + phase
		pivot.rotation.x = 0.0
		var beams: Array = entry["beams"]
		for k in beams.size():
			var beam: Dictionary = beams[k]
			var mat: ShaderMaterial = beam["mat"]
			if mat == null:
				continue
			var color: Color = _target_colors[(laser_index + k) % _target_colors.size()]
			var current: Color = mat.get_shader_parameter("beam_color")
			mat.set_shader_parameter("beam_color", current.lerp(color, 0.10))
			var target_intensity := (0.45 + _beat_energy * 0.6) if active else 0.0
			# Preset có strobe: nháy tia theo pha để giống laser club.
			if active and bool(data.get("strobe", false)) and _beat_energy > 0.4 and sin(_strobe_phase) < 0.0:
				target_intensity *= 0.2
			var current_intensity := float(mat.get_shader_parameter("intensity"))
			mat.set_shader_parameter("intensity", lerpf(current_intensity, target_intensity, 0.18))
			(beam["mesh"] as MeshInstance3D).visible = active
			# Vệt sáng trên sàn bám theo đầu tia khi cụm laser quét.
			var pool: MeshInstance3D = beam.get("pool")
			if pool != null and is_instance_valid(pool):
				pool.visible = active
				if active:
					var aim: Vector3 = beam.get("aim", Vector3.DOWN)
					var dir := (pivot.global_transform.basis * aim).normalized()
					var origin := pivot.global_position
					var down := maxf(0.05, -dir.y)
					var hit := origin + dir * ((origin.y - 0.06) / down)
					if hit.z < 0.0:
						hit = origin + dir * ((origin.y - 1.03) / down)
					pool.global_position = Vector3(hit.x, hit.y + 0.04, hit.z)
					var pool_mat: ShaderMaterial = beam.get("pool_mat")
					if pool_mat != null:
						var pool_color: Color = pool_mat.get_shader_parameter("glow_color")
						pool_mat.set_shader_parameter("glow_color", pool_color.lerp(color, 0.10))
						var pool_current := float(pool_mat.get_shader_parameter("intensity"))
						var pool_base := float(beam.get("pool_base", 1.2))
						pool_mat.set_shader_parameter("intensity", lerpf(pool_current, pool_base * (1.0 + _beat_energy * 0.7), 0.18))
		var dots: Array = entry.get("dots", [])
		for d in dots:
			if is_instance_valid(d):
				d.visible = active
		var spot: Light3D = entry["spot"]
		if spot != null and is_instance_valid(spot):
			# Giữ vũng sáng sàn hơi trắng để các đốm màu vẫn nổi.
			var spot_color: Color = _target_colors[laser_index % _target_colors.size()].lerp(Color(1, 1, 1), 0.55)
			spot.light_color = spot.light_color.lerp(spot_color, 0.08)
			var base_energy := float(spot.get_meta("base_energy", 1.0))
			var spot_target := base_energy * (1.0 + _beat_energy * 0.4) if active else 0.0
			spot.light_energy = lerpf(spot.light_energy, spot_target, 0.12)
		laser_index += 1

	# LED strips: đổi màu + nhấp theo beat.
	var led_index := 0
	for entry in _leds:
		var mat: StandardMaterial3D = entry["mat"]
		if mat == null:
			continue
		var base: Color = entry["base"]
		var target: Color = base.lerp(Color(1, 1, 1), _beat_energy * 0.35)
		if not beat_enabled:
			target = base
		mat.emission = mat.emission.lerp(target, 0.12)
		mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, (1.4 if _target_energy > 0.01 else 0.0) * (1.0 + _beat_energy * 1.2), 0.15)
		led_index += 1


func _apply_leds_color(color: Color) -> void:
	for entry in _leds:
		entry["base"] = color
