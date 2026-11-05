class_name Nightclub
extends Node3D
## Nightclub "The Chrome Lotus" — dựng hoàn toàn bằng procedural mesh + PBR material.
## Một instance duy nhất cho mỗi phòng (server & client dựng cùng layout,
## nhờ vậy interact_id và vị trí luôn khớp giữa các máy).

const SPAWN_POSITION := Vector3(0.0, 1.2, 22.0)
const MAIN_CEIL := 13.5
const LOBBY_CEIL := 6.2
const BACK_CEIL := 4.2
const BALCONY_Y := 5.0
const LASER_SHADER := preload("res://shaders/laser_beam.gdshader")
const FLOOR_GLOW_SHADER := preload("res://shaders/floor_glow.gdshader")
const CRYSTAL_BALL_SHADER := preload("res://shaders/crystal_ball.gdshader")
## Mặt sàn nhảy (box cao 0.06) và mặt bục sân khấu (cao 1.0).
const DANCE_FLOOR_Y := 0.06
const STAGE_FLOOR_Y := 1.03

## TV chính giữa sân khấu (nhạc DJ/MP4, tỉ lệ 20:9) và TV nhỏ bên phải (thông tin nhà phát triển).
const MAIN_TV_SIZE := Vector2(14.4, 6.48)
const MAIN_TV_CENTER := Vector3(0.0, 5.55, -6.05)
const SIDE_TV_SIZE := Vector2(5.4, 3.04)
const SIDE_TV_CENTER := Vector3(10.5, 5.5, -5.2)
const SIDE_TV_YAW := -16.0

var room_info: Dictionary = {}
var server_mode := false
var players: Dictionary = {}
var interactables: Dictionary = {}

var lighting: Node3D
var dj: Node3D
var tv: Node3D
var environment_node: WorldEnvironment

var stage_screen: MeshInstance3D
var stage_screen_material: StandardMaterial3D
var stage_side_screen: MeshInstance3D
var side_screen_material: StandardMaterial3D
var lobby_emitters: Array = []
var tv_screens: Array = []
var _pending_lights: Array = []
var _pending_leds: Array = []
var _pending_lasers: Array = []
## Đèn động do sân khấu tạo ra; bật/tắt theo khoảng cách để giữ FPS.
var _managed_lights: Array = []
var _light_budget_check := 0.0


func _ready() -> void:
	name = "Nightclub"
	_build_environment()
	_build_shell()
	_build_lobby()
	_build_main_hall()
	_build_dance_floor()
	_build_stage()
	_build_bar()
	_build_vip_lounge()
	_build_lounge_seating()
	_build_balcony()
	_build_corridor_and_backrooms()
	_build_computer_desk()
	_build_decor()
	_init_systems()
	_connect_net()
	_apply_light_budget()
	if not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	_light_budget_check = 0.0


func _process(delta: float) -> void:
	# Chỉ giữ N đèn gần camera nhất hoạt động. Club có hơn 50 đèn, bật hết là
	# nguyên nhân chính khiến FPS tụt trên GPU yếu.
	if server_mode or _managed_lights.is_empty():
		return
	_light_budget_check -= delta
	if _light_budget_check > 0.0:
		return
	_light_budget_check = 0.4
	_apply_light_budget()


func _apply_light_budget() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.global_position
	var budget := SettingsManager.light_budget()
	var sorted := _managed_lights.duplicate()
	sorted.sort_custom(func(a, b):
		var la: Light3D = a["node"]
		var lb: Light3D = b["node"]
		return la.global_position.distance_squared_to(origin) < lb.global_position.distance_squared_to(origin)
	)
	var shadow_budget := 2 if budget >= 8 else 1
	var shadow_used := 0
	for i in sorted.size():
		var entry: Dictionary = sorted[i]
		var light: Light3D = entry["node"]
		if not is_instance_valid(light):
			continue
		var enabled := i < budget
		light.visible = enabled
		# Chỉ 1-2 đèn gần nhất được đổ bóng; shadow map là phần tốn kém nhất.
		var wants_shadow := enabled and bool(entry["shadow"]) and shadow_used < shadow_budget
		light.shadow_enabled = wants_shadow
		if wants_shadow:
			shadow_used += 1


# ------------------------------------------------------------------ environment

func _build_environment() -> void:
	environment_node = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.018, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.48, 0.62)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = bool(SettingsManager.preset().get("glow", true))
	env.glow_intensity = 0.85
	env.glow_bloom = 0.22
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = bool(SettingsManager.preset().get("ssao", true))
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssr_enabled = bool(SettingsManager.preset().get("reflections", true))
	env.ssr_max_steps = 48
	env.volumetric_fog_enabled = bool(SettingsManager.preset().get("volumetric", false))
	env.volumetric_fog_density = 0.015
	env.volumetric_fog_albedo = Color(0.5, 0.35, 0.55)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	environment_node.environment = env
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "MoonFill"
	sun.light_color = Color(0.6, 0.68, 1.0)
	sun.light_energy = 0.45
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = false
	add_child(sun)


# ------------------------------------------------------------------ build helpers

func _box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, material: Material, collide := true, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = center
	mi.rotation.y = rot_y
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.name = "Col"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mi.add_child(body)
	return mi


func _cyl(parent: Node3D, node_name: String, center: Vector3, radius: float, height: float, material: Material, collide := false, segments := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = material
	mi.position = center
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		body.add_child(shape)
		mi.add_child(body)
	return mi


func _sphere(parent: Node3D, node_name: String, center: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = material
	mi.position = center
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, center: Vector3, size := 64, color := Color(0.95, 0.86, 0.66), rot_y := 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = center
	label.rotation.y = rot_y
	label.no_depth_test = false
	parent.add_child(label)
	return label


func _add_interactable(id: String, prompt: String, action: String, position: Vector3, data: Dictionary = {}, size := Vector3(1.4, 1.8, 1.4)) -> QBOInteractable:
	var area := QBOInteractable.new()
	area.configure(id, prompt, action, data, size)
	area.position = position
	add_child(area)
	interactables[id] = area
	return area


func _register_light(kind: String, node: Node3D) -> void:
	if lighting != null:
		lighting.register_light(kind, node)
	else:
		_pending_lights.append({"kind": kind, "node": node})


func _add_spot(node_name: String, position: Vector3, color: Color, energy: float, range_m := 18.0, angle := 28.0, shadow := false) -> SpotLight3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = position
	add_child(pivot)
	var light := SpotLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_m
	light.spot_angle = angle
	light.spot_attenuation = 0.9
	light.shadow_enabled = shadow
	light.distance_fade_enabled = true
	light.distance_fade_begin = range_m * 0.6
	light.distance_fade_length = range_m * 0.4
	pivot.add_child(light)
	light.rotation_degrees.x = -90.0
	pivot.set_meta("base_energy", energy)
	_register_light("moving_head" if shadow else "wash", pivot)
	_managed_lights.append({"node": light, "shadow": shadow})
	return light


## Giàn đèn trung tâm kiểu club: quả cầu gương lớn treo trong vòng truss tròn,
## xung quanh là dàn tia laser tỏa 360° (xuống sàn, ngang và hắt lên trần),
## đèn spot gắn trên vòng và hoa văn đốm màu dưới sàn. LightingController
## xoay cả cụm, đổi màu và nhấp theo beat.
func _add_disco_rig(node_name: String, position: Vector3, palette: Array) -> void:
	# Kim loại sáng vừa phải để vòng truss đọc được trong club tối (không dựa
	# vào SSR vì renderer Compatibility không có phản chiếu màn hình).
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.58, 0.64)
	metal.metallic = 0.35
	metal.roughness = 0.4
	var ball_radius := 1.35
	var ring_radius := 5.2
	var ball_color: Color = palette[0] if not palette.is_empty() else Color(1.0, 0.6, 0.8)

	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = position
	add_child(pivot)

	# Thanh treo từ trần xuống + nắp quả cầu.
	var top_local := MAIN_CEIL - position.y
	var rod_h := maxf(0.2, top_local - ball_radius)
	_cyl(pivot, node_name + "_Rod", Vector3(0, ball_radius + rod_h * 0.5, 0), 0.05, rod_h, metal, false, 8)
	_cyl(pivot, node_name + "_Cap", Vector3(0, ball_radius + 0.1, 0), 0.42, 0.2, QBOMaterials.matte_black(), false, 20)
	_sphere(pivot, node_name + "_Ball", Vector3.ZERO, ball_radius, _crystal_material(ball_color.lerp(Color(1, 1, 1), 0.55)))

	# Vòng truss tròn hai tầng + thanh nối dọc.
	for i in range(2):
		var mi := MeshInstance3D.new()
		mi.name = "%s_Truss_%d" % [node_name, i]
		var torus := TorusMesh.new()
		torus.inner_radius = ring_radius - 0.18
		torus.outer_radius = ring_radius + 0.18
		torus.rings = 48
		torus.ring_segments = 12
		mi.mesh = torus
		mi.material_override = metal
		mi.position.y = 0.55 if i == 0 else -0.55
		pivot.add_child(mi)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		_cyl(pivot, "%s_TrussStrut_%d" % [node_name, i], Vector3(cos(a) * ring_radius, 0.0, sin(a) * ring_radius), 0.055, 1.1, metal, false, 6)
	# Nan hoa nối quả cầu với vòng truss.
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var spoke_len := ring_radius - ball_radius - 0.12
		_box(pivot, "%s_Spoke_%d" % [node_name, i], Vector3(cos(a), 0, sin(a)) * (ball_radius + 0.12 + spoke_len * 0.5), Vector3(spoke_len, 0.07, 0.07), metal, false, -a)
	# Vòng LED phát sáng trên truss.
	var led := MeshInstance3D.new()
	led.name = node_name + "_RingLED"
	var led_torus := TorusMesh.new()
	led_torus.inner_radius = ring_radius - 0.035
	led_torus.outer_radius = ring_radius + 0.035
	led_torus.rings = 64
	led_torus.ring_segments = 6
	led.mesh = led_torus
	led.position.y = 0.71
	led.material_override = QBOMaterials.led_dynamic(ball_color, 3.0)
	pivot.add_child(led)
	if lighting != null:
		lighting.register_led(led, ball_color)
	else:
		_pending_leds.append({"node": led, "color": ball_color})

	# Sáu đèn spot gắn trên vòng, hắt xuống quanh sàn nhảy.
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var fixture := Node3D.new()
		fixture.name = "%s_Fixture_%d" % [node_name, i]
		fixture.position = dir * (ring_radius - 0.15) + Vector3(0, 0.35, 0)
		fixture.rotation.y = atan2(-cos(a), -sin(a))
		pivot.add_child(fixture)
		_box(fixture, "Body", Vector3.ZERO, Vector3(0.34, 0.4, 0.5), QBOMaterials.matte_black(), false)
		_box(fixture, "Lens", Vector3(0, -0.12, -0.24), Vector3(0.24, 0.24, 0.06), QBOMaterials.led(ball_color, 2.4), false)
		var spot := SpotLight3D.new()
		spot.name = "Spot"
		spot.position = Vector3(0, -0.12, -0.26)
		spot.rotation_degrees.x = -74.0
		spot.light_color = ball_color.lerp(Color(1, 1, 1), 0.5)
		spot.light_energy = 1.1
		spot.spot_range = 15.0
		spot.spot_angle = 36.0
		spot.spot_attenuation = 1.0
		spot.light_specular = 0.0
		spot.shadow_enabled = false
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 9.0
		spot.distance_fade_length = 5.0
		fixture.add_child(spot)
		_register_light("wash", fixture)
		_managed_lights.append({"node": spot, "shadow": false})

	# Dàn tia laser tỏa 360°: các vòng từ chúc xuống sàn tới hắt lên trần.
	var beam_rings := [
		{"tilt": 16.0, "count": 10},
		{"tilt": 34.0, "count": 12},
		{"tilt": 56.0, "count": 12},
		{"tilt": 78.0, "count": 10},
		{"tilt": 106.0, "count": 8},
		{"tilt": 140.0, "count": 8},
	]
	var beam_entries: Array = []
	var beam_index := 0
	for ring in beam_rings:
		var tilt := deg_to_rad(float(ring["tilt"]))
		var count := int(ring["count"])
		for j in count:
			var yaw := TAU * float(j) / float(count) + (PI / float(count)) * float(beam_index % 2)
			var aim := Vector3(sin(tilt) * sin(yaw), -cos(tilt), sin(tilt) * cos(yaw)).normalized()
			var start := aim * ball_radius
			# Chiều dài tia: dừng ở sàn/trần để không xuyên qua kết cấu.
			var beam_len := 13.0
			if aim.y < -0.05:
				beam_len = minf(beam_len, (position.y + start.y - DANCE_FLOOR_Y) / maxf(0.05, -aim.y))
			elif aim.y > 0.05:
				beam_len = minf(beam_len, (MAIN_CEIL - (position.y + start.y)) / aim.y)
			beam_len = maxf(2.0, beam_len)
			var color: Color = palette[beam_index % palette.size()] if not palette.is_empty() else ball_color

			var mi := MeshInstance3D.new()
			mi.name = "%s_Beam_%d" % [node_name, beam_index]
			var cone := CylinderMesh.new()
			# Đầu gần quả cầu nhỏ, đầu xa loe nhẹ; không nhọn như kim.
			cone.top_radius = 0.18
			cone.bottom_radius = 0.05
			cone.height = beam_len
			cone.radial_segments = 8
			cone.rings = 1
			cone.cap_top = false
			cone.cap_bottom = false
			mi.mesh = cone
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = LASER_SHADER
			mat.set_shader_parameter("beam_color", color)
			mat.set_shader_parameter("intensity", 0.9)
			mat.set_shader_parameter("edge_softness", 1.4)
			mat.set_shader_parameter("opacity", 0.11)
			mi.material_override = mat
			mi.position = start + aim * (beam_len * 0.5)
			mi.quaternion = Quaternion(Vector3.UP, aim)
			pivot.add_child(mi)
			beam_entries.append({"mesh": mi, "mat": mat, "aim": aim})
			beam_index += 1

	# Hoa văn đốm màu trên sàn kiểu quả cầu gương.
	var dot_nodes := _add_dot_field(pivot, position, palette, 0.0, 6, 16, 2.0, 12.0, 360.0)

	# Vũng sáng rộng, rất nhẹ để không tạo cục cháy trên sàn.
	var wash := MeshInstance3D.new()
	wash.name = node_name + "_Wash"
	var wash_mesh := PlaneMesh.new()
	wash_mesh.size = Vector2(30.0, 30.0)
	wash.mesh = wash_mesh
	wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wash_mat := ShaderMaterial.new()
	wash_mat.shader = FLOOR_GLOW_SHADER
	wash_mat.set_shader_parameter("glow_color", ball_color.lerp(Color(1, 1, 1), 0.5))
	wash_mat.set_shader_parameter("intensity", 0.07)
	wash_mat.set_shader_parameter("falloff_power", 1.5)
	wash.material_override = wash_mat
	wash.position = Vector3(position.x, DANCE_FLOOR_Y + 0.02, position.z)
	add_child(wash)
	dot_nodes.append(wash)

	_register_laser(pivot, beam_entries, null, 0.0, dot_nodes)


## Material quả cầu pha lê: bề mặt khảm gương nhỏ, phát sáng như đèn disco ball.
func _crystal_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CRYSTAL_BALL_SHADER
	mat.set_shader_parameter("tint", color)
	return mat


## Rải các đốm sáng nhỏ trên sàn theo từng vòng bán kính, giống hoa văn mà
## quả cầu pha lê chiếu xuống. Dùng MultiMesh để gom thành ít draw call.
func _add_dot_field(pivot: Node3D, origin: Vector3, palette: Array, base_yaw: float, ring_count := 5, per_ring := 12, min_radius := 1.4, max_radius := 9.0, arc_deg := 150.0) -> Array:
	var colors: Array = palette if not palette.is_empty() else [Color(1.0, 0.6, 0.8)]
	var total := ring_count * per_ring
	var group_count := colors.size()
	var per_group := int(ceil(float(total) / float(group_count)))
	var nodes: Array = []
	for g in group_count:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = per_group
		var quad := PlaneMesh.new()
		quad.size = Vector2(0.26, 0.26)
		mm.mesh = quad
		# Ẩn các instance dư (nếu tổng đốm không chia hết cho số màu).
		for k in per_group:
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_Dots_%d" % [pivot.name, g]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.position = Vector3(origin.x, 0.0, origin.z)
		var mat := ShaderMaterial.new()
		mat.shader = FLOOR_GLOW_SHADER
		mat.set_shader_parameter("glow_color", colors[g])
		mat.set_shader_parameter("intensity", 1.3)
		mmi.material_override = mat
		add_child(mmi)
		nodes.append(mmi)

	var next_index: Array = []
	next_index.resize(group_count)
	next_index.fill(0)
	var slot := 0
	for ring in ring_count:
		var ring_t := 0.5 if ring_count <= 1 else float(ring) / float(ring_count - 1)
		var radius := lerpf(min_radius, max_radius, ring_t)
		for j in per_ring:
			var angle_deg := 0.0
			if arc_deg >= 359.0:
				# Vòng tròn đủ 360 độ: chia đều, không lặp điểm đầu/cuối.
				angle_deg = -arc_deg * 0.5 + arc_deg * float(j) / float(per_ring)
				angle_deg += (arc_deg / float(per_ring)) * 0.5 * float(ring % 2)
			else:
				var at := 0.5 if per_ring <= 1 else float(j) / float(per_ring - 1)
				angle_deg = lerpf(-arc_deg * 0.5, arc_deg * 0.5, at) + ring * 9.0
			var angle := deg_to_rad(angle_deg) + base_yaw
			var local := Vector3(radius * sin(angle), 0.0, radius * cos(angle))
			var world_x := origin.x + local.x
			var world_z := origin.z + local.z
			var floor_y := STAGE_FLOOR_Y
			if world_z >= 0.0:
				var on_dance := absf(world_x) <= 20.0 and world_z >= 0.8 and world_z <= 12.2
				floor_y = DANCE_FLOOR_Y if on_dance else 0.0
			# Nâng lên 0.045 để đốm không bị chìm/ z-fighting với mặt sàn.
			local.y = floor_y + 0.045
			var g := slot % group_count
			var idx: int = next_index[g]
			var mm: MultiMesh = nodes[g].multimesh
			if idx < mm.instance_count:
				mm.set_instance_transform(idx, Transform3D(Basis(), local))
				next_index[g] = idx + 1
			slot += 1
	return nodes


func _register_laser(pivot: Node3D, beams: Array, spot: Light3D, base_yaw: float, dots: Array = []) -> void:
	if lighting != null and lighting.has_method("register_laser"):
		lighting.register_laser(pivot, beams, spot, base_yaw, dots)
	else:
		_pending_lasers.append({"pivot": pivot, "beams": beams, "spot": spot, "base_yaw": base_yaw, "dots": dots})


func _add_omni(node_name: String, position: Vector3, color: Color, energy: float, range_m := 9.0, shadow := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.1
	light.shadow_enabled = shadow
	add_child(light)
	_register_light("ceiling", light)
	_managed_lights.append({"node": light, "shadow": shadow})
	return light


func _led_strip(position: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var host: Node3D = parent if parent != null else self
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := QBOMaterials.led_dynamic(color)
	mi.material_override = mat
	mi.position = position
	host.add_child(mi)
	if lighting != null:
		lighting.register_led(mi, color)
	else:
		_pending_leds.append({"node": mi, "color": color})
	return mi


# ------------------------------------------------------------------ architecture

func _build_shell() -> void:
	var marble := QBOMaterials.marble_dark()
	var wall_mat := QBOMaterials.wall_panel()
	var ceiling_mat := QBOMaterials.ceiling_panel()

	# Sàn toàn bộ building (3 lớp để chống xuyên qua ở mối nối).
	_box(self, "Floor_Main", Vector3(0, -0.2, -1), Vector3(80.0, 0.4, 54.8), marble)
	_box(self, "Ceiling_MainHall", Vector3(0, MAIN_CEIL + 0.15, 5), Vector3(80.0, 0.3, 22.4), ceiling_mat)
	_box(self, "Ceiling_Lobby", Vector3(0, LOBBY_CEIL + 0.15, 21), Vector3(80.0, 0.3, 10.4), ceiling_mat)
	_box(self, "Ceiling_Back", Vector3(0, BACK_CEIL + 0.15, -19), Vector3(80.0, 0.3, 14.4), ceiling_mat)

	# Tường ngoài.
	_box(self, "Wall_West", Vector3(-40.3, MAIN_CEIL * 0.5, 0), Vector3(0.6, MAIN_CEIL, 52.6), wall_mat)
	_box(self, "Wall_East", Vector3(40.3, MAIN_CEIL * 0.5, 0), Vector3(0.6, MAIN_CEIL, 52.6), wall_mat)
	_box(self, "Wall_North", Vector3(0, MAIN_CEIL * 0.5, -26.3), Vector3(80.0, MAIN_CEIL, 0.6), wall_mat)

	# Mặt tiền phía nam, chừa cửa chính rộng 6m.
	_box(self, "Facade_L", Vector3(-23.0, MAIN_CEIL * 0.5, 26.3), Vector3(34.0, MAIN_CEIL, 0.6), wall_mat)
	_box(self, "Facade_R", Vector3(23.0, MAIN_CEIL * 0.5, 26.3), Vector3(34.0, MAIN_CEIL, 0.6), wall_mat)
	_box(self, "Facade_Header", Vector3(0, 8, 26.3), Vector3(11.4, 4, 0.6), marble)

	# Vách lobby / main hall, chừa cổng vòm 12m.
	_box(self, "LobbyWall_W", Vector3(-23, 4, 16), Vector3(34, 8, 0.5), wall_mat)
	_box(self, "LobbyWall_E", Vector3(23, 4, 16), Vector3(34, 8, 0.5), wall_mat)
	_box(self, "LobbyArch_Header", Vector3(0, 6.4, 16), Vector3(12, 3.2, 0.5), marble)
	# Cổng vòm mạ vàng.
	for side in [-1, 1]:
		_box(self, "ArchGold_%d" % side, Vector3(side * 6.2, 3.2, 16), Vector3(0.35, 6.4, 0.65), QBOMaterials.gold())
	_box(self, "ArchGold_Top", Vector3(0, 6.55, 16), Vector3(12.7, 0.35, 0.65), QBOMaterials.gold())

	# Cột kết cấu trong main hall.
	for x in [-26.0, 26.0]:
		_box(self, "Column_%d" % int(x), Vector3(x, MAIN_CEIL * 0.5, 5), Vector3(1.1, MAIN_CEIL, 1.1), marble)
		_box(self, "ColumnGold_%d" % int(x), Vector3(x, 2.6, 5), Vector3(1.25, 0.14, 1.25), QBOMaterials.gold())
		_box(self, "ColumnGold2_%d" % int(x), Vector3(x, 13.1, 5), Vector3(1.25, 0.14, 1.25), QBOMaterials.gold())

	# Trần coffered + dầm.
	for i in range(5):
		_box(self, "CeilingBeam_%d" % i, Vector3(0, MAIN_CEIL - 0.4, -3 + i * 4.4), Vector3(79, 0.5, 0.45), QBOMaterials.matte_black())
	# LED trần chạy dọc main hall.
	for side in [-1, 1]:
		_led_strip(Vector3(side * 30, MAIN_CEIL - 0.55, 5), Vector3(0.18, 0.08, 20), Color(0.85, 0.55, 1.0))
		_led_strip(Vector3(side * 37, 0.12, 5), Vector3(0.12, 0.1, 20), Color(0.35, 0.7, 1.0))
	# Hào quang trần giữa hall (đọc được kết cấu trần, tránh trần đen tuyệt đối).
	for side in [-1, 1]:
		_led_strip(Vector3(side * 7.5, MAIN_CEIL - 0.62, 5), Vector3(0.14, 0.05, 18), Color(1.0, 0.7, 0.42))
		_led_strip(Vector3(side * 4.5, MAIN_CEIL - 0.62, 5), Vector3(0.1, 0.05, 18), Color(1.0, 0.78, 0.52))
	_add_omni("CeilingCove_W", Vector3(-10, MAIN_CEIL - 0.9, 5), Color(1.0, 0.72, 0.45), 2.2, 20.0)
	_add_omni("CeilingCove_E", Vector3(10, MAIN_CEIL - 0.9, 5), Color(1.0, 0.72, 0.45), 2.2, 20.0)

	# Hào quang trần lobby.
	_box(self, "LobbyCove", Vector3(0, LOBBY_CEIL - 0.5, 21), Vector3(28, 0.25, 8), QBOMaterials.matte_black())
	for i in range(7):
		_led_strip(Vector3(-12 + i * 4, LOBBY_CEIL - 0.62, 21), Vector3(0.1, 0.06, 7.6), Color(1.0, 0.72, 0.42))


func _build_lobby() -> void:
	var marble := QBOMaterials.marble_dark()
	var gold := QBOMaterials.gold()
	var leather := QBOMaterials.leather(Color(0.16, 0.03, 0.06))

	# Thảm đỏ dẫn vào hall.
	_box(self, "LobbyRug", Vector3(0, 0.02, 21), Vector3(7, 0.05, 9), QBOMaterials.carpet(), false)

	# Quầy lễ tân.
	_box(self, "Reception_Base", Vector3(-7, 0.55, 21.6), Vector3(6, 1.1, 1.3), QBOMaterials.wood_dark())
	_box(self, "Reception_Top", Vector3(-7, 1.16, 21.6), Vector3(6.4, 0.12, 1.7), marble)
	_box(self, "Reception_Gold", Vector3(-7, 0.95, 22.24), Vector3(6.2, 0.06, 0.05), gold)
	_label(self, "LỄ TÂN", Vector3(-7, 2.4, 22.3), 42, Color(0.95, 0.82, 0.6), PI)
	_box(self, "ReceptionBackWall", Vector3(-7, 2.0, 24.2), Vector3(9, 4, 0.2), QBOMaterials.wood_dark())
	_label(self, "QUẨY BAR ONLINE", Vector3(-7, 3.3, 24.05), 74, Color(0.98, 0.85, 0.62), PI)
	_led_strip(Vector3(-7, 2.7, 24.05), Vector3(8.4, 0.06, 0.06), Color(1.0, 0.45, 0.65))

	# Ghế chờ.
	_sofa(Vector3(-9.5, 0, 18.6), 0.0, leather, 3.0)
	_sofa(Vector3(9.5, 0, 18.6), 0.0, leather, 3.0)
	_table(Vector3(-9.5, 0, 17.2), 1.1, 0.9)
	_table(Vector3(9.5, 0, 17.2), 1.1, 0.9)

	# Cột dây nhung + stanchion.
	for i in range(4):
		_stanchion(Vector3(-4.2 + i * 2.8, 0, 17.0))
		_stanchion(Vector3(-4.2 + i * 2.8, 0, 15.2))

	# Đèn chùm lobby.
	_chandelier(Vector3(0, 4.6, 21), Color(1.0, 0.78, 0.48), 0.6)
	_add_omni("LobbyChandelierLight", Vector3(0, 4.6, 21), Color(1.0, 0.75, 0.5), 3.4, 13.0)
	_add_omni("EntranceFill", Vector3(0, 4.0, 23.5), Color(1.0, 0.72, 0.5), 1.8, 9.0)

	# Thang máy lên ban công.
	_elevator(Vector3(-11.0, 0, 22.0))

	# Cửa kính chính (trang trí, tự mở khi lại gần bằng tương tác).
	_double_glass_door("entrance", Vector3(0, 0, 25.6), 0.0, 6.0)


func _sofa(position: Vector3, rot_y: float, material: Material, width := 2.6) -> void:
	var group := Node3D.new()
	group.position = position
	group.rotation.y = rot_y
	add_child(group)
	_box(group, "Seat", Vector3(0, 0.42, 0), Vector3(width, 0.36, 1.0), material, false)
	_box(group, "Back", Vector3(0, 0.8, -0.44), Vector3(width, 0.85, 0.22), material, false)
	for side in [-1, 1]:
		_box(group, "Arm_%d" % side, Vector3(side * (width * 0.5 - 0.09), 0.66, 0), Vector3(0.18, 0.55, 1.0), material, false)
	_box(group, "Base", Vector3(0, 0.22, 0), Vector3(width - 0.2, 0.2, 0.86), QBOMaterials.gold(), false)
	# Chân sofa.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(group, "Leg", Vector3(sx * (width * 0.42), 0.08, sz * 0.36), Vector3(0.08, 0.16, 0.08), QBOMaterials.gold(), false)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(width, 0.85, 1.0)
	shape.shape = box_shape
	body.add_child(shape)
	body.position = Vector3(0, 0.45, 0)
	group.add_child(body)


func _table(position: Vector3, radius := 1.1, height := 0.95) -> void:
	_cyl(self, "TableBase", position + Vector3(0, 0.06, 0), 0.34, 0.12, QBOMaterials.gold(), true, 16)
	_cyl(self, "TableStem", position + Vector3(0, height * 0.5, 0), 0.08, height, QBOMaterials.gold(), false, 12)
	_cyl(self, "TableTop", position + Vector3(0, height, 0), radius, 0.09, QBOMaterials.marble_light(), true, 28)
	_led_strip(position + Vector3(0, height - 0.08, 0), Vector3(radius * 1.7, 0.03, 0.03), Color(1.0, 0.55, 0.7))


func _chair(position: Vector3, rot_y := 0.0) -> void:
	var group := Node3D.new()
	group.position = position
	group.rotation.y = rot_y
	add_child(group)
	_box(group, "Seat", Vector3(0, 0.47, 0), Vector3(0.46, 0.1, 0.46), QBOMaterials.leather(Color(0.13, 0.05, 0.07)), false)
	_box(group, "Back", Vector3(0, 0.8, -0.2), Vector3(0.46, 0.55, 0.09), QBOMaterials.leather(Color(0.13, 0.05, 0.07)), false)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(group, "Leg", Vector3(sx * 0.18, 0.22, sz * 0.18), Vector3(0.05, 0.45, 0.05), QBOMaterials.gold(), false)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.5, 0.9, 0.5)
	shape.shape = box_shape
	body.add_child(shape)
	body.position = Vector3(0, 0.45, 0)
	group.add_child(body)


func _bar_stool(position: Vector3) -> void:
	_cyl(self, "StoolLeg", position + Vector3(0, 0.36, 0), 0.05, 0.72, QBOMaterials.gold(), false, 12)
	_cyl(self, "StoolFoot", position + Vector3(0, 0.02, 0), 0.24, 0.05, QBOMaterials.gold(), false, 20)
	_cyl(self, "StoolSeat", position + Vector3(0, 0.76, 0), 0.26, 0.1, QBOMaterials.leather(Color(0.5, 0.05, 0.1)), false, 20)
	_led_strip(position + Vector3(0, 0.63, 0), Vector3(0.36, 0.025, 0.36), Color(1.0, 0.4, 0.55))


func _stanchion(position: Vector3) -> void:
	_cyl(self, "StanchionBase", position + Vector3(0, 0.02, 0), 0.2, 0.05, QBOMaterials.gold(), false, 16)
	_cyl(self, "StanchionPole", position + Vector3(0, 0.5, 0), 0.03, 1.0, QBOMaterials.gold(), false, 10)
	_sphere(self, "StanchionTop", position + Vector3(0, 1.02, 0), 0.07, QBOMaterials.gold())


func _chandelier(position: Vector3, color: Color, scale_factor := 1.0) -> void:
	var group := Node3D.new()
	group.position = position
	add_child(group)
	_cyl(group, "ChandelierStem", Vector3(0, 0.6, 0), 0.04, 1.2, QBOMaterials.gold(), false, 8)
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var radius := 0.9 * scale_factor
		var p := Vector3(cos(angle) * radius, sin(angle * 2.0) * 0.18, sin(angle) * radius)
		_sphere(group, "Bulb_%d" % i, p, 0.075 * scale_factor, QBOMaterials.led(color, 4.0))
	_led_strip(position + Vector3(0, 0.0, 0), Vector3(2.2 * scale_factor, 0.04, 0.04), color, group)


# ------------------------------------------------------------------ main hall & dance floor

func _build_main_hall() -> void:
	var gold := QBOMaterials.gold()
	# Viền sàn nhảy.
	_box(self, "DanceFloorTrim", Vector3(0, 0.04, 6.5), Vector3(41.6, 0.08, 12.6), gold, false)
	# Lan can trang trí hai bên sàn nhảy.
	for side in [-1, 1]:
		for i in range(5):
			_cyl(self, "RailPost_%d_%d" % [side, i], Vector3(side * 21.2, 0.55, 1.5 + i * 2.3), 0.04, 1.1, gold, false, 8)
		_box(self, "RailTop_%d" % side, Vector3(side * 21.2, 1.12, 6.5), Vector3(0.07, 0.07, 10), gold, false)
	# Cột mạ vàng lớn hai bên sân khấu.
	for side in [-1, 1]:
		_box(self, "StagePillar_%d" % side, Vector3(side * 23.4, 5.5, -2), Vector3(0.9, 11, 0.9), QBOMaterials.marble_light())
		_led_strip(Vector3(side * 23.4, 5.5, -1.52), Vector3(0.06, 9.0, 0.06), Color(1.0, 0.65, 0.3))

	# Bàn tiệc hai bên sàn nhảy.
	for i in range(3):
		var z := 2.0 + i * 3.0
		for side in [-1, 1]:
			_table(Vector3(side * 28.5, 0, z), 0.9)
			_chair(Vector3(side * 28.5, 0, z + 1.4), PI)
			_chair(Vector3(side * 28.5, 0, z - 1.4), 0.0)

	# Đèn trần chính + moving head.
	for i in range(6):
		var x := -28.0 + i * 11.2
		_add_omni("CeilingWash_%d" % i, Vector3(x, MAIN_CEIL - 0.9, 9.0), Color(0.9, 0.55, 0.75), 2.6, 15.0)
	# Đèn phụ chiếu sàn nhảy để nhân vật luôn đọc được trong ánh sáng club.
	for i in range(4):
		var fill_x := -21.0 + i * 14.0
		_add_omni("DanceWash_%d" % i, Vector3(fill_x, 3.6, 7.5), Color(1.0, 0.62, 0.8), 1.9, 11.0)
	for i in range(4):
		_add_spot("HallSpot_%d" % i, Vector3(-21.0 + i * 14.0, MAIN_CEIL - 1.2, 5.0), Color(1.0, 0.45, 0.7), 3.0, 20.0, 34.0, i < 2)

	# Loa treo tường.
	for side in [-1, 1]:
		for z in [3.0, 11.0]:
			_box(self, "WallSpeaker_%d_%d" % [side, int(z)], Vector3(side * 38.5, 5.5, z), Vector3(1.0, 1.6, 1.0), QBOMaterials.matte_black())
			var cone := _cyl(self, "SpeakerCone_%d_%d" % [side, int(z)], Vector3(side * 37.95, 5.5, z), 0.34, 0.12, QBOMaterials.brushed_metal(), false, 18)
			cone.rotation_degrees.z = 90.0


func _build_dance_floor() -> void:
	var floor_mat := QBOMaterials.black_gloss()
	_box(self, "DanceFloor", Vector3(0, 0.03, 6.5), Vector3(40, 0.06, 11.4), floor_mat, false)
	# Sàn liền mạch, không chia ô vuông; chỉ giữ viền LED quanh sàn.
	# Vòng LED quanh sàn.
	for side in [-1, 1]:
		_led_strip(Vector3(side * 20.2, 0.1, 6.5), Vector3(0.08, 0.08, 11.4), Color(0.25, 0.75, 1.0))
	_led_strip(Vector3(0, 0.1, 12.2), Vector3(40.4, 0.08, 0.08), Color(1.0, 0.3, 0.55))


# ------------------------------------------------------------------ stage

func _build_stage() -> void:
	var stage_mat := QBOMaterials.black_gloss()
	var deck_w := 34.0
	var deck_front := 0.0
	var deck_back := -6.2
	var deck_z := (deck_front + deck_back) * 0.5
	var deck_d := deck_front - deck_back
	# Sân khấu nâng 1m, thu gọn vừa đúng khung TV 16:9.
	_box(self, "Stage", Vector3(0, 0.5, deck_z), Vector3(deck_w, 1.0, deck_d), stage_mat)
	_box(self, "StageTrim", Vector3(0, 1.03, deck_front - 0.02), Vector3(deck_w, 0.08, 0.18), QBOMaterials.gold(), false)
	_led_strip(Vector3(0, 1.02, deck_front - 0.12), Vector3(deck_w - 1.6, 0.06, 0.06), Color(1.0, 0.3, 0.5))
	for side in [-1, 1]:
		_led_strip(Vector3(side * (deck_w * 0.5 - 0.02), 1.02, deck_z), Vector3(0.06, 0.06, deck_d), Color(0.4, 0.6, 1.0))
	# Bậc lên sân khấu.
	_box(self, "StageStep1", Vector3(0, 0.17, 0.55), Vector3(6, 0.34, 0.9), stage_mat)
	_box(self, "StageStep2", Vector3(0, 0.5, 0.15), Vector3(6, 0.34, 0.5), stage_mat)

	# Tường hậu phía sau TV: tấm ốp tối để màn hình "treo" thay vì lơ lửng.
	_box(self, "StageBackdrop", Vector3(0, 6.9, -6.45), Vector3(28.0, 13.2, 0.4), QBOMaterials.wall_panel())
	_box(self, "StageBackdropGold", Vector3(0, 13.2, -6.22), Vector3(28.0, 0.12, 0.3), QBOMaterials.gold(), false)
	_led_strip(Vector3(0, 13.0, -6.2), Vector3(27.0, 0.06, 0.06), Color(0.55, 0.4, 1.0))
	_led_strip(Vector3(0, 1.34, -6.2), Vector3(26.6, 0.05, 0.05), Color(0.4, 0.75, 1.0))
	for side in [-1, 1]:
		_led_strip(Vector3(side * 13.2, 6.9, -6.2), Vector3(0.08, 11.4, 0.08), Color(1.0, 0.3, 0.55) if side < 0 else Color(0.35, 0.7, 1.0))

	# TV dài ở giữa (20:9) — màn hình chính phát nhạc DJ / video MP4.
	stage_screen_material = QBOMaterials.screen()
	var screen := MeshInstance3D.new()
	screen.name = "StageTV"
	# QuadMesh map UV 0..1 toàn mặt phẳng; BoxMesh chia UV theo atlas 3x2 làm crop hình.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(MAIN_TV_SIZE.x, MAIN_TV_SIZE.y)
	screen.mesh = mesh
	screen.material_override = stage_screen_material
	screen.position = MAIN_TV_CENTER
	add_child(screen)
	stage_screen = screen
	# Khung TV: bezel kim loại đen + viền vàng mảnh.
	var tv_half := MAIN_TV_SIZE * 0.5
	_box(self, "TVBezelTop", MAIN_TV_CENTER + Vector3(0, tv_half.y + 0.11, -0.05), Vector3(MAIN_TV_SIZE.x + 0.36, 0.22, 0.42), QBOMaterials.matte_black(), false)
	_box(self, "TVBezelBottom", MAIN_TV_CENTER + Vector3(0, -tv_half.y - 0.11, -0.05), Vector3(MAIN_TV_SIZE.x + 0.36, 0.22, 0.42), QBOMaterials.matte_black(), false)
	_box(self, "TVBezelLeft", MAIN_TV_CENTER + Vector3(-tv_half.x - 0.09, 0, -0.05), Vector3(0.22, MAIN_TV_SIZE.y + 0.18, 0.42), QBOMaterials.matte_black(), false)
	_box(self, "TVBezelRight", MAIN_TV_CENTER + Vector3(tv_half.x + 0.09, 0, -0.05), Vector3(0.22, MAIN_TV_SIZE.y + 0.18, 0.42), QBOMaterials.matte_black(), false)
	_box(self, "TVTrimTop", MAIN_TV_CENTER + Vector3(0, tv_half.y + 0.25, -0.03), Vector3(MAIN_TV_SIZE.x + 0.4, 0.06, 0.4), QBOMaterials.gold(), false)
	_box(self, "TVTrimBottom", MAIN_TV_CENTER + Vector3(0, -tv_half.y - 0.25, -0.03), Vector3(MAIN_TV_SIZE.x + 0.4, 0.06, 0.4), QBOMaterials.gold(), false)
	_led_strip(MAIN_TV_CENTER + Vector3(0, tv_half.y + 0.32, -0.03), Vector3(MAIN_TV_SIZE.x + 0.1, 0.05, 0.05), Color(1.0, 0.35, 0.6))
	_led_strip(MAIN_TV_CENTER + Vector3(0, -tv_half.y - 0.32, -0.03), Vector3(MAIN_TV_SIZE.x + 0.1, 0.05, 0.05), Color(0.4, 0.75, 1.0))
	# Cột LED hai bên TV chính.
	for side in [-1, 1]:
		_box(self, "TVColumn_%d" % side, Vector3(side * (tv_half.x + 0.45), MAIN_TV_CENTER.y, -6.12), Vector3(0.34, MAIN_TV_SIZE.y + 0.9, 0.3), QBOMaterials.wall_panel(), false)
		_led_strip(Vector3(side * (tv_half.x + 0.26), MAIN_TV_CENTER.y, -6.06), Vector3(0.07, MAIN_TV_SIZE.y + 0.6, 0.07), Color(1.0, 0.3, 0.5) if side < 0 else Color(0.35, 0.7, 1.0))

	# TV nhỏ bên phải sân khấu: thông tin nhà phát triển, nghiêng về phía sàn nhảy.
	side_screen_material = QBOMaterials.screen()
	var side_screen := MeshInstance3D.new()
	side_screen.name = "SideTV"
	var side_mesh := QuadMesh.new()
	side_mesh.size = SIDE_TV_SIZE
	side_screen.mesh = side_mesh
	side_screen.material_override = side_screen_material
	side_screen.position = SIDE_TV_CENTER
	side_screen.rotation_degrees.y = SIDE_TV_YAW
	add_child(side_screen)
	stage_side_screen = side_screen
	# Khung TV nhỏ.
	var side_frame := MeshInstance3D.new()
	side_frame.name = "SideTVFrame"
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(SIDE_TV_SIZE.x + 0.34, SIDE_TV_SIZE.y + 0.34, 0.24)
	side_frame.mesh = frame_mesh
	side_frame.material_override = QBOMaterials.matte_black()
	side_frame.position = SIDE_TV_CENTER + Vector3(0, 0, -0.16)
	side_frame.rotation_degrees.y = SIDE_TV_YAW
	add_child(side_frame)
	var side_trim := MeshInstance3D.new()
	side_trim.name = "SideTVTrim"
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(SIDE_TV_SIZE.x + 0.4, 0.05, 0.22)
	side_trim.mesh = trim_mesh
	side_trim.material_override = QBOMaterials.gold()
	side_trim.position = SIDE_TV_CENTER + Vector3(0, SIDE_TV_SIZE.y * 0.5 + 0.2, 0)
	side_trim.rotation_degrees.y = SIDE_TV_YAW
	add_child(side_trim)
	var side_trim_bottom := MeshInstance3D.new()
	side_trim_bottom.name = "SideTVTrimBottom"
	var trim_bottom_mesh := BoxMesh.new()
	trim_bottom_mesh.size = Vector3(SIDE_TV_SIZE.x + 0.4, 0.05, 0.22)
	side_trim_bottom.mesh = trim_bottom_mesh
	side_trim_bottom.material_override = QBOMaterials.gold()
	side_trim_bottom.position = SIDE_TV_CENTER + Vector3(0, -SIDE_TV_SIZE.y * 0.5 - 0.2, 0)
	side_trim_bottom.rotation_degrees.y = SIDE_TV_YAW
	add_child(side_trim_bottom)
	# Giá treo + đèn nhấn cho TV nhỏ.
	_box(self, "SideTVMount", SIDE_TV_CENTER + Vector3(0.5, 0, -0.5), Vector3(0.26, 0.26, 1.0), QBOMaterials.brushed_metal(), false, SIDE_TV_YAW)
	_led_strip(SIDE_TV_CENTER + Vector3(0, SIDE_TV_SIZE.y * 0.5 + 0.26, 0.06), Vector3(SIDE_TV_SIZE.x, 0.04, 0.04), Color(0.4, 0.85, 1.0))
	_add_interactable("stage_screen", "Màn hình sân khấu — mở bảng điều khiển", "tv_control", Vector3(9.1, 1.6, -1.6), {"screen": "stage"}, Vector3(5.0, 3.2, 3.2))

	# Booth DJ — đặt thấp hơn mép dưới TV để không che nội dung.
	_box(self, "DJBooth", Vector3(0, 1.52, -2.2), Vector3(6.4, 1.04, 1.3), QBOMaterials.wood_dark())
	_box(self, "DJBoothTop", Vector3(0, 2.07, -2.2), Vector3(6.8, 0.1, 1.5), QBOMaterials.marble_light())
	_box(self, "DJBoothGold", Vector3(0, 1.2, -1.53), Vector3(6.4, 0.08, 0.06), QBOMaterials.gold(), false)
	_led_strip(Vector3(0, 1.5, -1.52), Vector3(5.6, 0.05, 0.05), Color(0.4, 0.75, 1.0))
	# Deck + mixer.
	for side in [-1, 1]:
		_cyl(self, "Deck_%d" % side, Vector3(side * 1.6, 2.17, -2.2), 0.55, 0.1, QBOMaterials.brushed_metal(), false, 28)
		_cyl(self, "DeckPlatter_%d" % side, Vector3(side * 1.6, 2.24, -2.2), 0.42, 0.03, QBOMaterials.black_gloss(), false, 28)
	_box(self, "Mixer", Vector3(0, 2.21, -2.2), Vector3(1.5, 0.18, 0.7), QBOMaterials.matte_black())
	_led_strip(Vector3(0, 2.31, -2.2), Vector3(1.2, 0.03, 0.05), Color(1.0, 0.65, 0.3))
	_add_interactable("dj_booth", "Sân khấu DJ — mở bảng điều khiển", "dj_mode", Vector3(0, 1.8, -1.2), {}, Vector3(6, 2, 2.2))

	# Loa chính đứng trên sàn sân khấu, hai bên TV.
	for side in [-1, 1]:
		_box(self, "MainSpeaker_%d" % side, Vector3(side * 11.0, 2.2, -4.0), Vector3(1.7, 2.4, 1.6), QBOMaterials.matte_black())
		for k in range(2):
			var cone := _cyl(self, "SpeakCone_%d_%d" % [side, k], Vector3(side * 11.0, 1.65 + k * 1.05, -3.18), 0.5 - k * 0.12, 0.14, QBOMaterials.brushed_metal(), false, 24)
			cone.rotation_degrees.x = 90.0
		_led_strip(Vector3(side * 11.0, 3.45, -4.0), Vector3(1.4, 0.05, 1.4), Color(1.0, 0.3, 0.5))
	# Monitor wedge hướng về DJ.
	for side in [-1, 1]:
		_box(self, "StageMonitor_%d" % side, Vector3(side * 3.6, 1.25, -0.8), Vector3(1.1, 0.5, 0.7), QBOMaterials.matte_black())

	# Quả cầu gương lớn + vòng truss + dàn laser tỏa 360° giữa sàn nhảy.
	var ball_palette := [Color(1.0, 0.25, 0.65), Color(0.25, 0.85, 1.0), Color(0.75, 0.35, 1.0), Color(1.0, 0.95, 0.7), Color(0.3, 1.0, 0.55), Color(1.0, 0.55, 0.15)]
	_add_disco_rig("CenterMirrorBall", Vector3(0.0, 8.6, 6.5), ball_palette)

	# Trống/percussion trang trí bên phải sân khấu.
	_cyl(self, "Drum1", Vector3(13.6, 1.65, -4.4), 0.45, 0.7, QBOMaterials.brushed_metal(), false, 24)
	_cyl(self, "Drum2", Vector3(14.5, 1.65, -4.9), 0.35, 0.6, QBOMaterials.brushed_metal(), false, 24)

	# Ánh sáng hắt màu phía sau TV.
	for i in range(3):
		_add_omni("StageWash_%d" % i, Vector3(-10 + i * 10, 10.6, -4.6), Color(0.7, 0.3, 1.0), 1.6, 10.0)


# ------------------------------------------------------------------ bar

func _build_bar() -> void:
	var wood := QBOMaterials.wood_dark()
	var marble := QBOMaterials.marble_dark()
	var gold := QBOMaterials.gold()

	# Sàn khu bar.
	_box(self, "BarFloor", Vector3(-35, 0.02, 5), Vector3(8, 0.04, 15), QBOMaterials.wood_dark(), false)
	# Quầy bar.
	_box(self, "BarBase", Vector3(-33.2, 0.55, 5.0), Vector3(2.6, 1.1, 13.0), wood)
	_box(self, "BarTop", Vector3(-33.2, 1.13, 5.0), Vector3(3.2, 0.12, 13.4), marble)
	_led_strip(Vector3(-31.88, 0.75, 5.0), Vector3(0.06, 0.06, 12.8), Color(1.0, 0.45, 0.65))
	# Tủ kính sau quầy.
	_box(self, "BackBar", Vector3(-39.0, 2.6, 5.0), Vector3(1.0, 4.2, 13.0), QBOMaterials.wall_panel())
	for row in range(3):
		var y := 1.1 + row * 1.05
		_box(self, "Shelf_%d" % row, Vector3(-38.3, y, 5.0), Vector3(0.8, 0.08, 12.4), gold)
		for i in range(14):
			var z := -0.55 + i * 0.8
			var color := Color(0.35 + row * 0.16, 0.08, 0.1) if (i + row) % 2 == 0 else Color(0.5, 0.4, 0.15)
			_cyl(self, "Bottle_%d_%d" % [row, i], Vector3(-38.28, y + 0.22, z), 0.055, 0.36, QBOMaterials.glass(color), false, 10)
	_led_strip(Vector3(-37.95, 4.5, 5.0), Vector3(0.06, 0.05, 12.4), Color(0.4, 0.75, 1.0))
	_label(self, "CHROME LOTUS BAR", Vector3(-37.9, 4.9, 5.0), 46, Color(0.95, 0.8, 0.55), PI * 0.5)

	# Ghế bar.
	for i in range(8):
		_bar_stool(Vector3(-30.3, 0, -0.8 + i * 1.6))
	# Đèn thả trần.
	for i in range(5):
		var z := -1.0 + i * 3.0
		_cyl(self, "PendantCord_%d" % i, Vector3(-33.2, 3.1, z), 0.015, 2.4, QBOMaterials.matte_black(), false, 6)
		_cyl(self, "PendantShade_%d" % i, Vector3(-33.2, 1.95, z), 0.28, 0.3, QBOMaterials.gold(), false, 18)
		_sphere(self, "PendantBulb_%d" % i, Vector3(-33.2, 1.8, z), 0.08, QBOMaterials.led(Color(1.0, 0.78, 0.5), 3.0))
		_add_omni("BarLight_%d" % i, Vector3(-33.2, 1.8, z), Color(1.0, 0.72, 0.45), 2.0, 7.5)
	# Máy pha chế + ly.
	_cyl(self, "Shaker", Vector3(-32.8, 1.35, 8.5), 0.1, 0.3, QBOMaterials.mirror(), false, 12)
	for i in range(6):
		_cyl(self, "Glass_%d" % i, Vector3(-32.6 + (i % 3) * 0.18, 1.34, 6.5 + (i / 3) * 0.3), 0.05, 0.22, QBOMaterials.glass(), false, 10)

	_add_interactable("bar_counter", "Gọi đồ uống tại quầy bar", "bar", Vector3(-31.7, 1.2, 5.0), {}, Vector3(0.9, 1.6, 12.0))


# ------------------------------------------------------------------ VIP lounge

func _build_vip_lounge() -> void:
	var gold := QBOMaterials.gold()
	var leather := QBOMaterials.leather(Color(0.22, 0.03, 0.07))
	# Bục VIP.
	_box(self, "VIPPlatform", Vector3(35.0, 0.22, 5), Vector3(7.4, 0.44, 13), QBOMaterials.marble_dark())
	_led_strip(Vector3(31.3, 0.3, 5), Vector3(0.06, 0.06, 13), Color(1.0, 0.72, 0.35))
	# Lan can + dây nhung.
	_box(self, "VIPRail", Vector3(31.25, 0.85, 5), Vector3(0.08, 0.08, 12.6), gold, false)
	for i in range(5):
		_cyl(self, "VIPPost_%d" % i, Vector3(31.25, 0.62, -0.5 + i * 2.8), 0.035, 1.2, gold, false, 8)
	# Sofa VIP.
	_sofa(Vector3(36.6, 0.44, 1.6), PI * 0.5, leather, 3.2)
	_sofa(Vector3(36.6, 0.44, 7.0), PI * 0.5, leather, 3.2)
	_table(Vector3(34.4, 0.44, 4.3), 1.0)
	# Bàn VIP + xô champagne.
	_cyl(self, "VIPBucket", Vector3(34.4, 1.65, 4.3), 0.22, 0.3, QBOMaterials.gold(), false, 18)
	_cyl(self, "VIPBottle", Vector3(34.4, 1.95, 4.3), 0.07, 0.4, QBOMaterials.glass(Color(0.6, 0.5, 0.1, 0.4)), false, 10)
	_label(self, "VIP", Vector3(31.0, 2.4, 5.0), 60, Color(1.0, 0.82, 0.5), -PI * 0.5)
	_chandelier(Vector3(35.0, 4.4, 4.6), Color(1.0, 0.78, 0.42), 0.7)
	_add_omni("VIPChandelier", Vector3(35.0, 4.2, 4.6), Color(1.0, 0.72, 0.42), 3.2, 11.0)
	_led_strip(Vector3(38.6, 0.5, 5), Vector3(0.06, 0.85, 12.6), Color(0.9, 0.5, 1.0))
	_add_interactable("vip_sofa", "Ngồi khu VIP", "seat", Vector3(36.0, 0.9, 1.6), {"seat": Vector3(35.9, 0.95, 1.6), "yaw": -PI * 0.5}, Vector3(1.6, 2.0, 3.4))


func _build_lounge_seating() -> void:
	var leather := QBOMaterials.leather(Color(0.09, 0.06, 0.12))
	for side in [-1, 1]:
		var x: float = float(side) * 9.5
		_sofa(Vector3(x, 0, 14.2), PI, leather, 3.6)
		_table(Vector3(x, 0, 12.4), 1.0)
		_chair(Vector3(x - 2.0, 0, 11.2), PI * 0.75)
		_chair(Vector3(x + 2.0, 0, 11.2), -PI * 0.75)
		_add_interactable(
			"lounge_sofa_%d" % side,
			"Ngồi xuống ghế lounge",
			"seat",
			Vector3(x, 0.9, 14.2),
			{"seat": Vector3(x, 0.62, 14.4), "yaw": PI},
			Vector3(3.4, 1.9, 1.4)
		)
		_led_strip(Vector3(x, 0.05, 13.1), Vector3(3.4, 0.04, 0.04), Color(1.0, 0.35, 0.6))


# ------------------------------------------------------------------ balcony

func _build_balcony() -> void:
	var gold := QBOMaterials.gold()
	_box(self, "BalconyFloor", Vector3(0, BALCONY_Y, 14.0), Vector3(56, 0.35, 4.0), QBOMaterials.marble_dark())
	_box(self, "BalconyUnderGlow", Vector3(0, BALCONY_Y - 0.22, 14.0), Vector3(55.6, 0.05, 3.6), QBOMaterials.matte_black(), false)
	_led_strip(Vector3(0, BALCONY_Y - 0.28, 12.05), Vector3(55, 0.08, 0.08), Color(0.35, 0.8, 1.0))
	# Lan can kính.
	for i in range(15):
		var x := -26.6 + i * 3.8
		_box(self, "BalconyGlass_%d" % i, Vector3(x, BALCONY_Y + 0.65, 12.05), Vector3(3.5, 1.2, 0.05), QBOMaterials.glass(Color(0.7, 0.85, 1.0, 0.13)), false)
		_cyl(self, "BalconyPost_%d" % i, Vector3(x - 1.85, BALCONY_Y + 0.65, 12.05), 0.04, 1.35, gold, false, 8)
	_box(self, "BalconyHandrail", Vector3(0, BALCONY_Y + 1.32, 12.05), Vector3(55.5, 0.09, 0.12), gold, false)
	# Bàn ghế trên ban công.
	for i in range(4):
		var x := -18.0 + i * 12.0
		_table(Vector3(x, BALCONY_Y, 14.0), 0.9)
		_chair(Vector3(x - 1.4, BALCONY_Y, 14.0), PI * 0.5)
		_chair(Vector3(x + 1.4, BALCONY_Y, 14.0), -PI * 0.5)
		_add_omni("BalconyLight_%d" % i, Vector3(x, BALCONY_Y + 3.0, 14.0), Color(1.0, 0.6, 0.75), 1.6, 8.0)
	_add_interactable("balcony_seat", "Ngồi ở ban công", "seat", Vector3(0, BALCONY_Y + 0.9, 14.0), {"seat": Vector3(0, BALCONY_Y + 0.6, 14.4), "yaw": PI}, Vector3(1.6, 2.0, 1.8))


# ------------------------------------------------------------------ corridor & back rooms

func _build_corridor_and_backrooms() -> void:
	var wall := QBOMaterials.wall_panel()
	var marble := QBOMaterials.marble_dark()
	var gold := QBOMaterials.gold()

	# Hành lang sau sân khấu, nối hai bên.
	_box(self, "CorridorWall", Vector3(0, 2, -12), Vector3(80, 4, 0.4), wall)
	# Cửa phục vụ xuyên qua vách sân khấu (hai bên màn LED).
	for side in [-1, 1]:
		_door("stage_service_%d" % side, Vector3(side * 21, 0, -6.0), 0.0, 2.0, 2.8)
	# Vách ngăn các phòng sau.
	for x in [-26.0, -2.0, 21.0]:
		_box(self, "BackPartition_%d" % int(x), Vector3(x, 2.2, -19), Vector3(0.4, 4.4, 14), wall)
	# Trần hành lang thấp + đèn.
	for i in range(8):
		_add_omni("CorridorLight_%d" % i, Vector3(-36 + i * 10.3, 3.6, -9), Color(0.9, 0.75, 0.6), 1.6, 8.0)

	# Phòng điều khiển ánh sáng.
	_box(self, "ControlDesk", Vector3(-34, 0.55, -14.2), Vector3(6, 1.1, 1.4), QBOMaterials.matte_black())
	_box(self, "ControlTop", Vector3(-34, 1.14, -14.2), Vector3(6.4, 0.1, 1.7), marble)
	for i in range(8):
		_cyl(self, "Fader_%d" % i, Vector3(-36.2 + i * 0.62, 1.24, -14.4), 0.03, 0.1, gold, false, 8)
	for side in [-1, 1]:
		_box(self, "ControlMonitor_%d" % side, Vector3(-34 + side * 1.5, 1.8, -14.4), Vector3(2.0, 1.2, 0.1), QBOMaterials.screen(), false)
		_led_strip(Vector3(-34 + side * 1.5, 1.85, -14.33), Vector3(1.7, 0.02, 0.02), Color(0.35, 0.8, 1.0))
	_box(self, "ControlWindow", Vector3(-34, 2.6, -12.15), Vector3(10, 2.0, 0.1), QBOMaterials.glass(), false)
	_add_omni("ControlRoomLight", Vector3(-34, 3.4, -17), Color(0.55, 0.7, 1.0), 1.2, 9.0)
	_label(self, "LIGHT CONTROL", Vector3(-34, 3.2, -12.1), 40, Color(0.6, 0.85, 1.0))
	_add_interactable("lighting_console", "Bảng điều khiển ánh sáng", "lighting_mode", Vector3(-34, 1.4, -13.4), {}, Vector3(6, 1.8, 1.2))
	_door("control_room_door", Vector3(-31.5, 0, -12.0), 0.0, 1.8, 2.6)

	# Nhà vệ sinh (2 buồng).
	for room_index in range(2):
		var cx := -19.0 if room_index == 0 else -7.0
		_box(self, "WCBack_%d" % room_index, Vector3(cx, 1.5, -25.8), Vector3(7.6, 3, 0.15), QBOMaterials.marble_light(), false)
		for k in range(3):
			_box(self, "WCStall_%d_%d" % [room_index, k], Vector3(cx - 3.0 + k * 2.4, 1.2, -24.6), Vector3(0.08, 2.4, 2.2), QBOMaterials.glass(Color(0.75, 0.85, 0.95, 0.25)), false)
		_box(self, "WCSink", Vector3(cx, 1.0, -23.5), Vector3(2.2, 0.9, 0.7), QBOMaterials.marble_light())
		_box(self, "WCMirror", Vector3(cx, 2.0, -25.65), Vector3(3.4, 1.6, 0.08), QBOMaterials.mirror(), false)
		_add_omni("WCLight_%d" % room_index, Vector3(cx, 3.0, -23), Color(0.75, 0.85, 1.0), 1.5, 8.0)
		_label(self, "WC %s" % ("A" if room_index == 0 else "B"), Vector3(cx, 3.1, -12.4), 36, Color(0.75, 0.85, 1.0))
		_door("wc_door_%d" % room_index, Vector3(cx + 2.6, 0, -12.0), 0.0, 1.4, 2.4)

	# Phòng VIP riêng.
	_sofa(Vector3(13.5, 0, -17.5), 0.0, QBOMaterials.leather(Color(0.2, 0.03, 0.08)), 3.6)
	_table(Vector3(12.0, 0, -19.0), 1.1)
	_box(self, "PrivateTVFrame", Vector3(11.0, 2.2, -25.7), Vector3(4.6, 2.7, 0.2), QBOMaterials.matte_black(), false)
	_box(self, "PrivateTV", Vector3(11.0, 2.2, -25.55), Vector3(4.2, 2.3, 0.08), QBOMaterials.screen(), false)
	_add_omni("PrivateVIPLight", Vector3(12.0, 3.4, -18.5), Color(1.0, 0.55, 0.6), 2.4, 10.0)
	_chandelier(Vector3(12.0, 3.4, -18.5), Color(1.0, 0.65, 0.4), 0.45)
	_label(self, "VIP ROOM", Vector3(12.0, 3.2, -25.4), 52, Color(1.0, 0.8, 0.5))
	_door("vip_room_door", Vector3(16.0, 0, -12.0), 0.0, 1.8, 2.6)

	# Kho.
	for i in range(6):
		_box(self, "Crate_%d" % i, Vector3(28 + (i % 3) * 2.6, 0.5 + (i / 3) * 0.9, -20 - (i % 2) * 2.0), Vector3(1.6, 1.0, 1.6), QBOMaterials.wood_dark())
	_add_omni("StorageLight", Vector3(31, 3.4, -20), Color(0.8, 0.8, 0.85), 0.7, 8.0)
	_door("storage_door", Vector3(31.0, 0, -12.0), 0.0, 1.8, 2.6)


func _door(id: String, position: Vector3, rot_y: float, width: float, height: float) -> void:
	var group := Node3D.new()
	group.name = "Door_" + id
	group.position = position
	group.rotation.y = rot_y
	add_child(group)
	var panel := _box(group, "Panel", Vector3(width * 0.5, height * 0.5, 0), Vector3(width, height, 0.12), QBOMaterials.wood_dark(), false)
	_box(group, "Handle", Vector3(width - 0.15, height * 0.45, 0.1), Vector3(0.06, 0.24, 0.06), QBOMaterials.gold(), false)
	_box(group, "DoorFrame", Vector3(width * 0.5, height * 0.5, -0.08), Vector3(width + 0.16, height + 0.12, 0.08), QBOMaterials.gold(), false)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(width, height, 0.16)
	shape.shape = box_shape
	body.add_child(shape)
	body.position = Vector3(width * 0.5, height * 0.5, 0)
	group.add_child(body)
	group.set_meta("door_panel", panel)
	interactables[id] = group
	_add_interactable(id + "_trigger", "Mở / đóng cửa", "door", position + Vector3(width * 0.5, 1.0, 0), {"door": id, "open_angle": PI * 0.47}, Vector3(width, 2.2, 1.2))


func _double_glass_door(id: String, position: Vector3, rot_y: float, width: float) -> void:
	var group := Node3D.new()
	group.position = position
	group.rotation.y = rot_y
	add_child(group)
	for side in [-1, 1]:
		var panel := _box(group, "Glass_%d" % side, Vector3(side * width * 0.25, 1.5, 0), Vector3(width * 0.48, 3.0, 0.08), QBOMaterials.glass(), false)
		panel.set_meta("side", side)
		_box(group, "DoorFrame_%d" % side, Vector3(side * width * 0.5, 1.6, 0), Vector3(0.12, 3.2, 0.14), QBOMaterials.gold(), false)
	_box(group, "DoorHeader", Vector3(0, 3.15, 0), Vector3(width + 0.4, 0.16, 0.14), QBOMaterials.gold(), false)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(width, 3.0, 0.12)
	shape.shape = box_shape
	body.add_child(shape)
	body.position = Vector3(0, 1.5, 0)
	group.add_child(body)
	interactables[id] = group
	_add_interactable(id + "_trigger", "Mở cửa kính", "door", position + Vector3(0, 1.2, 0), {"door": id, "open_angle": PI * 0.4}, Vector3(width, 2.4, 1.2))


func _elevator(position: Vector3) -> void:
	var group := Node3D.new()
	group.name = "Elevator"
	group.position = position
	add_child(group)
	_box(group, "Shaft", Vector3(0, 2.6, 0), Vector3(4.0, 5.2, 3.6), QBOMaterials.marble_dark())
	_box(group, "Door", Vector3(0, 1.4, 1.82), Vector3(2.2, 2.8, 0.12), QBOMaterials.glass(), false)
	_box(group, "Frame", Vector3(0, 1.4, 1.86), Vector3(2.5, 3.0, 0.08), QBOMaterials.gold(), false)
	_label(group, "LÊN BAN CÔNG", Vector3(0, 3.0, 1.9), 30, Color(1.0, 0.82, 0.5))
	_led_strip(position + Vector3(0, 3.3, 1.9), Vector3(2.4, 0.05, 0.05), Color(0.4, 0.85, 1.0), group)
	_add_interactable("elevator_lobby", "Thang máy lên ban công VIP", "elevator", position + Vector3(0, 1.2, 2.4), {"destination": Vector3(0, BALCONY_Y + 0.6, 14.4), "yaw": PI}, Vector3(2.6, 2.4, 1.4))
	_add_interactable("elevator_balcony", "Thang máy xuống sảnh", "elevator", Vector3(0, BALCONY_Y + 1.2, 15.8), {"destination": Vector3(-9.0, 0.6, 21.0), "yaw": PI}, Vector3(2.6, 2.4, 1.4))


# ------------------------------------------------------------------ computer / LED desk

func _build_computer_desk() -> void:
	_box(self, "DeskTop", Vector3(21.0, 1.05, 14.0), Vector3(6.4, 0.12, 1.6), QBOMaterials.marble_light())
	_box(self, "DeskBase", Vector3(21.0, 0.5, 14.0), Vector3(6.0, 1.0, 1.3), QBOMaterials.wood_dark())
	_led_strip(Vector3(21.0, 1.15, 13.25), Vector3(5.8, 0.03, 0.03), Color(0.4, 0.8, 1.0))
	for i in range(2):
		var x := 19.4 + i * 3.2
		_box(self, "MonitorStand_%d" % i, Vector3(x, 1.35, 13.9), Vector3(0.35, 0.5, 0.25), QBOMaterials.brushed_metal(), false)
		_box(self, "MonitorFrame_%d" % i, Vector3(x, 1.95, 13.95), Vector3(2.3, 1.4, 0.12), QBOMaterials.matte_black(), false)
		var screen := _box(self, "MonitorScreen_%d" % i, Vector3(x, 1.95, 13.87), Vector3(2.1, 1.22, 0.04), QBOMaterials.screen(), false)
		tv_screens.append(screen)
		_box(self, "Keyboard_%d" % i, Vector3(x, 1.14, 14.2), Vector3(1.3, 0.05, 0.44), QBOMaterials.matte_black(), false)
	_chair(Vector3(21.0, 0, 15.6), 0.0)
	_chair(Vector3(18.4, 0, 15.6), 0.0)
	_add_omni("DeskLight", Vector3(21.0, 3.0, 14.0), Color(0.5, 0.75, 1.0), 2.1, 8.0)
	_add_interactable("computer_main", "Sử dụng máy tính trong bar", "computer_open", Vector3(21.0, 1.4, 14.9), {}, Vector3(5.4, 2.2, 1.6))
	_label(self, "LOTUS NET — KHU MÁY TÍNH", Vector3(21.0, 3.0, 13.8), 34, Color(0.65, 0.85, 1.0), PI)


# ------------------------------------------------------------------ decor

func _plant(position: Vector3) -> void:
	_cyl(self, "PlantPot", position + Vector3(0, 0.3, 0), 0.32, 0.6, QBOMaterials.marble_light(), true, 16)
	for i in range(5):
		var angle := TAU * float(i) / 5.0
		var leaf := _box(self, "Leaf_%d" % i, position + Vector3(cos(angle) * 0.22, 1.0 + i * 0.12, sin(angle) * 0.22), Vector3(0.12, 0.9 + i * 0.12, 0.12), QBOMaterials.fabric(Color(0.06, 0.2, 0.12)), false)
		leaf.rotation_degrees = Vector3(20.0, rad_to_deg(angle), 0.0)


func _build_decor() -> void:
	for p in [
		Vector3(-13, 0, 22), Vector3(13, 0, 22), Vector3(-30, 0, 13), Vector3(30, 0, 13),
		Vector3(-21, 0, 14.5), Vector3(26, 0, 14.5), Vector3(-12, 0, -9), Vector3(12, 0, -9),
	]:
		_plant(p)
	# Tác phẩm nghệ thuật trên tường (bám sát tường ngoài sau khi mở rộng).
	_box(self, "ArtWall1", Vector3(-39.85, 5.0, -3.0), Vector3(0.1, 4.0, 6.0), QBOMaterials.matte_black(), false)
	_led_strip(Vector3(-39.75, 5.0, -3.0), Vector3(0.04, 3.4, 0.05), Color(1.0, 0.4, 0.6))
	_box(self, "ArtWall2", Vector3(39.85, 5.0, -1.5), Vector3(0.1, 3.2, 5.0), QBOMaterials.matte_black(), false)
	_led_strip(Vector3(39.75, 5.0, -1.5), Vector3(0.04, 2.6, 0.05), Color(0.4, 0.6, 1.0))
	# Bảng hiệu ngoài trời (phía trên cửa vào).
	_label(self, "QUẨY BAR ONLINE", Vector3(0, 9.4, 26.62), 110, Color(1.0, 0.15, 0.45), PI)
	_label(self, "THE CHROME LOTUS • NIGHTCLUB", Vector3(0, 8.6, 26.6), 34, Color(1.0, 0.75, 0.45), PI)


# ------------------------------------------------------------------ systems

func _init_systems() -> void:
	lighting = preload("res://scripts/systems/lighting_controller.gd").new()
	lighting.name = "LightingController"
	add_child(lighting)

	dj = preload("res://scripts/systems/dj_system.gd").new()
	dj.name = "DJSystem"
	dj.world = self
	add_child(dj)

	tv = preload("res://scripts/systems/tv_system.gd").new()
	tv.name = "TVSystem"
	tv.world = self
	add_child(tv)

	for entry in _pending_lights:
		lighting.register_light(str(entry["kind"]), entry["node"])
	for entry in _pending_leds:
		lighting.register_led(entry["node"], entry["color"])
	for entry in _pending_lasers:
		lighting.register_laser(entry["pivot"], entry["beams"], entry["spot"], entry["base_yaw"], entry.get("dots", []))
	_pending_lights.clear()
	_pending_leds.clear()
	_pending_lasers.clear()
	if is_inside_tree():
		lighting.apply_preset(str(room_info.get("lightingPreset", "party")), 1.0, 1.0)


func _connect_net() -> void:
	Net.local_player_ready.connect(_on_local_player_ready)
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.player_state_received.connect(_on_player_state)
	Net.correction_received.connect(_on_correction)
	Net.interaction_received.connect(_on_interaction)
	Net.lighting_received.connect(_on_lighting)
	Net.dj_received.connect(_on_dj)
	Net.tv_received.connect(_on_tv)


func _on_local_player_ready(info: Dictionary) -> void:
	var id := int(info.get("id", Net.local_peer_id))
	# Khi kết nối lại, peer id đổi -> bỏ node local cũ trước khi tạo lại.
	for existing_id in players.keys():
		var node = players[existing_id]
		if node != null and is_instance_valid(node) and node.get("is_local_player") == true and int(existing_id) != id:
			remove_player(int(existing_id))
	add_player(info, true)
	# Người vào phòng sau nhận danh sách người chơi có sẵn trong `cli_welcome`
	# chứ không nhận `cli_player_joined` cho từng người -> phải spawn hết ở đây,
	# nếu không họ sẽ chỉ thấy chính mình.
	_sync_remote_players()


func _sync_remote_players() -> void:
	var self_id := Net.local_peer_id
	for id in Net.players.keys():
		if int(id) == self_id:
			continue
		add_player(Net.players[id], false)


func _on_player_joined(id: int, info: Dictionary) -> void:
	add_player(info, false)


func _on_player_left(id: int) -> void:
	remove_player(id)


func add_player(info: Dictionary, is_local: bool) -> Node3D:
	var id := int(info.get("id", Net.local_peer_id))
	if players.has(id):
		return players[id]
	var player := preload("res://scripts/player/player.gd").new()
	player.name = "Player_%d" % id
	player.player_id = id
	player.is_local_player = is_local
	player.display_name = str(info.get("name", "Người chơi"))
	player.avatar_style = int(info.get("style", SettingsManager.character_style))
	player.world = self
	var spawn: Vector3 = info.get("position", SPAWN_POSITION)
	if spawn == Vector3.ZERO:
		spawn = SPAWN_POSITION
	player.position = spawn + Vector3(0, 0.1, 0)
	player.initial_yaw = float(info.get("yaw", 0.0))
	add_child(player)
	players[id] = player
	return player


func remove_player(id: int) -> void:
	if players.has(id):
		var node: Node = players[id]
		players.erase(id)
		if is_instance_valid(node):
			node.queue_free()


func _on_player_state(id: int, state: Dictionary) -> void:
	if players.has(id):
		var player: Node3D = players[id]
		if player.has_method("apply_remote_state"):
			player.apply_remote_state(state)


func _on_correction(position: Vector3) -> void:
	var local = players.get(Net.local_peer_id)
	if local != null and local.has_method("apply_correction"):
		local.apply_correction(position)


func _on_lighting(state: Dictionary) -> void:
	if lighting != null:
		lighting.apply_state(state)


func _on_dj(action: String, payload: Dictionary) -> void:
	if dj != null:
		dj.handle_remote(action, payload)


func _on_tv(state: Dictionary) -> void:
	if tv != null:
		tv.apply_state(state)


func _on_interaction(sender: int, target: String, action: String, payload: Dictionary) -> void:
	match action:
		"computer_open":
			if sender == Net.local_peer_id and not server_mode:
				App.open_computer()
		"dj_mode":
			if sender == Net.local_peer_id and not server_mode:
				App.open_dj_panel()
		"lighting_mode":
			if sender == Net.local_peer_id and not server_mode:
				App.open_lighting_panel()
		"tv_control":
			if sender == Net.local_peer_id and not server_mode:
				App.open_computer("tv")
		"seat":
			if sender == Net.local_peer_id and not server_mode:
				var local = players.get(Net.local_peer_id)
				if local != null and local.has_method("sit_at"):
					local.sit_at(payload.get("seat", Vector3.ZERO), float(payload.get("yaw", 0.0)))
		"stand":
			if sender == Net.local_peer_id and not server_mode:
				var local = players.get(Net.local_peer_id)
				if local != null and local.has_method("stand_up"):
					local.stand_up()
		"door":
			_toggle_door(str(payload.get("door", "")), float(payload.get("open_angle", PI * 0.45)))
		"elevator":
			if sender == Net.local_peer_id and not server_mode:
				App.toast("Thang máy đang di chuyển…")
				await get_tree().create_timer(1.1).timeout
				var local = players.get(Net.local_peer_id)
				if local != null and local.has_method("teleport_to"):
					local.teleport_to(payload.get("destination", SPAWN_POSITION), float(payload.get("yaw", PI)))
		"bar":
			App.toast("Bartender: “Một ly Lotus Martini nhé!”")
		"tv_state":
			if tv != null:
				tv.apply_state(payload)
		"dj_state":
			if dj != null:
				dj.handle_remote("sync", payload)
		"use":
			pass


func _toggle_door(door_id: String, open_angle: float) -> void:
	if not interactables.has(door_id):
		return
	var door: Node3D = interactables[door_id]
	var is_open := bool(door.get_meta("is_open", false))
	var panel = door.get_meta("door_panel", null)
	door.set_meta("is_open", not is_open)
	var target := open_angle if not is_open else 0.0
	if panel is Node3D:
		var tween := create_tween()
		tween.tween_property(panel, "rotation:y", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func get_spawn_position() -> Vector3:
	return SPAWN_POSITION


func local_player_ref() -> Node3D:
	return players.get(Net.local_peer_id)
