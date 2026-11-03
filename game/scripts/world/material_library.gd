class_name QBOMaterials
extends RefCounted
## Kho vật liệu PBR dùng chung cho toàn nightclub.
## Tất cả material được cache theo khóa để giảm số lần cấp phát.

static var _cache: Dictionary = {}


static func _textured(key: String, texture_set: Dictionary, metallic: float, roughness: float, uv := Vector3(2, 2, 1)) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture_set.get("albedo")
	var rough_tex = texture_set.get("roughness")
	if rough_tex != null:
		mat.roughness_texture = rough_tex
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	mat.metallic = metallic
	mat.roughness = roughness
	mat.uv1_scale = uv
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


static func marble_dark() -> StandardMaterial3D:
	# Giữ bóng vừa phải: bề mặt quá nhẵn (roughness thấp) khiến SSR kéo vệt
	# đèn màu thành mảng lớn trên sàn, trông như lỗi đồ họa.
	return _textured("marble_dark", QBOTextures.marble(true), 0.04, 0.42, Vector3(6, 6, 1))


static func marble_light() -> StandardMaterial3D:
	return _textured("marble_light", QBOTextures.marble(false), 0.04, 0.3, Vector3(4, 4, 1))


static func wall_panel() -> StandardMaterial3D:
	return _textured("wall_panel", QBOTextures.panels(), 0.2, 0.5, Vector3(8, 3, 1))


static func wood_dark() -> StandardMaterial3D:
	return _textured("wood_dark", QBOTextures.wood(), 0.05, 0.34, Vector3(1.5, 1.5, 1))


static func carpet() -> StandardMaterial3D:
	return _textured("carpet", QBOTextures.carpet(), 0.0, 0.95, Vector3(8, 8, 1))


static func brushed_metal() -> StandardMaterial3D:
	return _textured("brushed_metal", QBOTextures.brushed_metal(), 0.92, 0.3, Vector3(1, 1, 1))


static func _simple(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	_cache[key] = mat
	return mat


static func gold() -> StandardMaterial3D:
	return _simple("gold", Color(0.86, 0.68, 0.36), 0.95, 0.22)


static func champagne() -> StandardMaterial3D:
	return _simple("champagne", Color(0.78, 0.63, 0.4), 0.85, 0.28)


static func black_gloss() -> StandardMaterial3D:
	# Sàn nhảy vẫn bóng nhưng bớt đặc tính gương để tránh vệt phản chiếu dài.
	return _simple("black_gloss", Color(0.06, 0.055, 0.07), 0.22, 0.34)


static func matte_black() -> StandardMaterial3D:
	return _simple("matte_black", Color(0.09, 0.085, 0.1), 0.1, 0.72)


static func ceiling_panel() -> StandardMaterial3D:
	return _simple("ceiling_panel", Color(0.21, 0.19, 0.205), 0.25, 0.55)


static func leather(color: Color) -> StandardMaterial3D:
	var key := "leather_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.42
	mat.metallic = 0.0
	mat.metallic_specular = 0.55
	mat.rim_enabled = true
	mat.rim = 0.18
	mat.rim_tint = 0.6
	_cache[key] = mat
	return mat


static func glass(tint := Color(0.68, 0.82, 1.0, 0.16)) -> StandardMaterial3D:
	var key := "glass_" + tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.25
	mat.roughness = 0.04
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.rim_enabled = true
	mat.rim = 0.4
	_cache[key] = mat
	return mat


static func led(color: Color, energy := 2.6) -> StandardMaterial3D:
	var key := "led_%s_%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.35
	mat.metallic = 0.0
	_cache[key] = mat
	return mat


## Material riêng (không cache) để có thể đổi màu emission cho LED động.
static func led_dynamic(color: Color, energy := 2.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.3
	return mat


static func screen() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.025)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.3, 0.4)
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.25
	mat.metallic = 0.1
	return mat


static func mirror() -> StandardMaterial3D:
	return _simple("mirror", Color(0.72, 0.75, 0.8), 1.0, 0.04)


static func skin(tone: Color) -> StandardMaterial3D:
	return _simple("skin_" + tone.to_html(), tone, 0.0, 0.55)


static func fabric(color: Color) -> StandardMaterial3D:
	return _simple("fabric_" + color.to_html(), color, 0.0, 0.85)
