class_name QBOTextures
extends RefCounted
## Sinh texture PBR bằng thuật toán (không phụ thuộc tài nguyên ngoài).
## Mọi texture ở đây là tác phẩm gốc của dự án, xem ASSET_LICENSES.md.

static var _cache: Dictionary = {}


static func marble(dark := true, size := 256) -> Dictionary:
	var key := "marble_%s_%d" % ["dark" if dark else "light", size]
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 7 if dark else 19
	noise.frequency = 0.018
	noise.fractal_octaves = 5
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base := Color(0.115, 0.108, 0.125) if dark else Color(0.58, 0.565, 0.545)
	var vein := Color(0.34, 0.31, 0.3) if dark else Color(0.42, 0.39, 0.35)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y)
			var wave := absf(sin((x * 0.055) + (n * 8.0) + (sin(y * 0.021) * 2.5)))
			var vein_mask := pow(1.0 - wave, 18.0)
			var c := base.lerp(vein, clampf(vein_mask * 1.4, 0.0, 0.9))
			albedo.set_pixel(x, y, c)
			var r := 0.1 + vein_mask * 0.32
			rough.set_pixel(x, y, Color(r, r, r))
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"roughness": ImageTexture.create_from_image(rough),
	}
	_cache[key] = result
	return result


static func wood(size := 256) -> Dictionary:
	var key := "wood_%d" % size
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 33
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y * 0.35)
			var rings := sin((x * 0.28) + n * 9.0)
			var grain := 0.5 + 0.5 * rings
			var c := Color(0.155, 0.1, 0.07).lerp(Color(0.255, 0.175, 0.125), grain)
			c = c.darkened(n * 0.04)
			albedo.set_pixel(x, y, c)
			var r := 0.36 + grain * 0.12
			rough.set_pixel(x, y, Color(r, r, r))
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"roughness": ImageTexture.create_from_image(rough),
	}
	_cache[key] = result
	return result


static func panels(size := 256) -> Dictionary:
	var key := "panels_%d" % size
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 57
	noise.frequency = 0.06
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y)
			var c := Color(0.15, 0.135, 0.145).lerp(Color(0.2, 0.18, 0.19), 0.5 + n * 0.5)
			var groove := float(x % 64)
			if groove < 2.0 or groove > 61.0:
				c = c.darkened(0.55)
			elif groove < 5.0:
				c = c.lightened(0.08)
			albedo.set_pixel(x, y, c)
			var r := 0.48 if groove > 2.0 and groove < 61.0 else 0.72
			rough.set_pixel(x, y, Color(r, r, r))
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"roughness": ImageTexture.create_from_image(rough),
	}
	_cache[key] = result
	return result


static func carpet(size := 128) -> Dictionary:
	var key := "carpet_%d" % size
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 91
	noise.frequency = 0.35
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y)
			var shade := 0.5 + n * 0.5
			var c := Color(0.045, 0.03, 0.038).lerp(Color(0.1, 0.062, 0.078), shade)
			albedo.set_pixel(x, y, c)
			rough.set_pixel(x, y, Color(0.92, 0.92, 0.92))
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"roughness": ImageTexture.create_from_image(rough),
	}
	_cache[key] = result
	return result


static func brushed_metal(size := 128) -> Dictionary:
	var key := "metal_%d" % size
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rough := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x * 6.0, y * 0.35)
			var c := Color(0.36, 0.36, 0.39).lerp(Color(0.62, 0.62, 0.66), 0.5 + n * 0.5)
			albedo.set_pixel(x, y, c)
			var r := 0.18 + absf(n) * 0.22
			rough.set_pixel(x, y, Color(r, r, r))
	var result := {
		"albedo": ImageTexture.create_from_image(albedo),
		"roughness": ImageTexture.create_from_image(rough),
	}
	_cache[key] = result
	return result


static func caustic_light(size := 128) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 404
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n := absf(noise.get_noise_2d(x, y))
			var a := clampf(n * 1.4, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
