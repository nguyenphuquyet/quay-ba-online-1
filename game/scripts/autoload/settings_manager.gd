extends Node
## SettingsManager — lưu/đọc cài đặt người chơi và áp dụng chất lượng đồ họa.
## Preset được thiết kế cho cả PC (Forward+) và mobile (GL Compatibility).

signal settings_changed()

const SETTINGS_PATH := "user://settings.cfg"

const PRESETS := {
	"low": {
		"scale": 0.72,
		"msaa": Viewport.MSAA_DISABLED,
		"ssaa": Viewport.SCREEN_SPACE_AA_FXAA,
		"shadow": true,
		"shadow_atlas": 1024,
		"glow": false,
		"ssao": false,
		"reflections": false,
		"volumetric": false,
		"max_lights": 8,
		"particles": 0.4,
	},
	"medium": {
		"scale": 0.85,
		"msaa": Viewport.MSAA_2X,
		"ssaa": Viewport.SCREEN_SPACE_AA_FXAA,
		"shadow": true,
		"shadow_atlas": 2048,
		"glow": true,
		"ssao": false,
		"reflections": false,
		"volumetric": false,
		"max_lights": 12,
		"particles": 0.7,
	},
	"high": {
		"scale": 1.0,
		"msaa": Viewport.MSAA_2X,
		"ssaa": Viewport.SCREEN_SPACE_AA_FXAA,
		"shadow": true,
		"shadow_atlas": 4096,
		"glow": true,
		"ssao": true,
		"reflections": true,
		"volumetric": false,
		"max_lights": 20,
		"particles": 1.0,
	},
	"ultra": {
		"scale": 1.0,
		"msaa": Viewport.MSAA_4X,
		"ssaa": Viewport.SCREEN_SPACE_AA_FXAA,
		"shadow": true,
		"shadow_atlas": 4096,
		"glow": true,
		"ssao": true,
		"reflections": true,
		"volumetric": true,
		"max_lights": 28,
		"particles": 1.5,
	},
}

var preset_name := "high"
var master_volume := 0.85
var music_volume := 0.8
var sfx_volume := 0.9
var mouse_sensitivity := 0.0023
var invert_y := false
var fullscreen := false
var show_fps := false
var camera_mode := "third"
var character_style := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	load_settings()
	if not FileAccess.file_exists(SETTINGS_PATH):
		preset_name = AppConfig.suggested_graphics_preset()
	apply_all()


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func preset() -> Dictionary:
	return PRESETS.get(preset_name, PRESETS["high"])


## Số đèn động thực sự được bật. Trên GL Compatibility (GPU yếu/không có
## Vulkan/D3D12) hạ trần xuống 10 đèn — club có hơn 50 đèn nên đây là mức
## ảnh hưởng FPS lớn nhất.
func light_budget() -> int:
	var budget := int(preset().get("max_lights", 20))
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		budget = mini(budget, 10)
	return clampi(budget, 4, 32)


func set_preset(value: String) -> void:
	if PRESETS.has(value):
		preset_name = value
		apply_graphics()
		save_settings()
		settings_changed.emit()


func apply_all() -> void:
	apply_graphics()
	apply_audio()
	apply_window()


func apply_graphics() -> void:
	var p := preset()
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var vp := get_viewport()
	if vp != null:
		var scale := float(p["scale"])
		# GPU OpenGL compatibility vẫn cần khử răng cưa: FXAA/TAA không chạy trên
		# backend này, nên MSAA 2x là lựa chọn rẻ nhất để hết viền răng cưa.
		# Giữ nguyên độ phân giải gốc của preset (không hạ thêm) vì hạ scale mà
		# không có AA còn răng cưa nặng hơn.
		if compat:
			scale = maxf(scale, 0.9)
			vp.msaa_3d = mini(int(p["msaa"]), Viewport.MSAA_2X)
			if vp.msaa_3d == Viewport.MSAA_DISABLED:
				vp.msaa_3d = Viewport.MSAA_2X
		else:
			vp.msaa_3d = int(p["msaa"])
		vp.scaling_3d_scale = scale
		vp.screen_space_aa = int(p["ssaa"])
	var atlas := int(p["shadow_atlas"])
	if compat:
		atlas = mini(atlas, 2048)
	if atlas > 0:
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	var budget := light_budget()
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	# Giới hạn số đèn động có shadow để tránh tụt FPS trên mobile.
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if budget >= 20 else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	)
	settings_changed.emit()


func apply_audio() -> void:
	_set_bus_linear("Master", master_volume)
	_set_bus_linear("Music", music_volume)
	_set_bus_linear("SFX", sfx_volume)


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func apply_window() -> void:
	if OS.has_feature("web") or AppConfig.is_mobile:
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset_name)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "camera_mode", camera_mode)
	cfg.set_value("window", "fullscreen", fullscreen)
	cfg.set_value("hud", "show_fps", show_fps)
	cfg.set_value("profile", "character_style", character_style)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	preset_name = str(cfg.get_value("graphics", "preset", preset_name))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	mouse_sensitivity = float(cfg.get_value("input", "sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	camera_mode = str(cfg.get_value("input", "camera_mode", camera_mode))
	fullscreen = bool(cfg.get_value("window", "fullscreen", fullscreen))
	show_fps = bool(cfg.get_value("hud", "show_fps", show_fps))
	character_style = int(cfg.get_value("profile", "character_style", character_style))
