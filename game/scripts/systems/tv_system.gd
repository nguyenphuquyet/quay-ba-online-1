class_name QBOTVSystem
extends Node3D
## Sân khấu có hai màn hình:
##   • TV chính giữa (20:9)  — visualizer/branding động, không tương tác.
##   • TV phụ bên phải (16:9) — màn web thật, render bởi Chromium headless qua
##     CDP (xem QBOWebRenderer), bấm/cuộn chuột trực tiếp trên màn hình.
##
## Trạng thái TV (URL, play, pause, thời gian, âm lượng) đồng bộ qua server.
## Khi máy không có trình duyệt để render, TV phụ hiển thị trạng thái trung thực
## (URL + lý do), không giả lập nội dung.

var world: Nightclub
## Viewport của màn web (TV phụ + bản sao trên máy tính trong bar).
var viewport: SubViewport
## Viewport của TV chính (visualizer).
var visual_viewport: SubViewport
var visualizer: Control

var screen_root: Control
var title_label: Label
var url_label: Label
var status_label: Label
var provider_label: Label
var progress_label: Label
var video: VideoStreamPlayer
var provider: QBOBrowserProvider
var renderer: QBOWebRenderer

var current_state: Dictionary = {}
var _download: HTTPRequest
var _elapsed := 0.0
## Cho phép test tắt trang YouTube mặc định để tự điều khiển màn web.
var auto_home := true

var _idle_layer: Control
var _web_layer: Control
var _web_page: TextureRect
var _web_loading: Label
var _web_cursor: Control
var _web_focus_badge: Label
var _web_mode := false
## true khi người chơi đang gõ bàn phím vào trang web trên TV phụ.
var _web_focus := false
var _applied_signature := ""
var _move_check := 0.0
var _last_move_px := Vector2(-10000, -10000)
var _visual_check := 0.0
var _hud_check := 0.0

## Độ phân giải trang web render trên TV phụ. 1280x720 đủ nét cho TV trong club
## và giảm mạnh chi phí giải mã JPEG mỗi frame so với 1920x1080.
const SCREEN_SIZE := Vector2i(1280, 720)
## Độ phân giải TV chính (tỉ lệ 20:9, khớp MAIN_TV_SIZE).
const VISUAL_SIZE := Vector2i(1280, 576)
## Trang mặc định của màn web: YouTube.
## Trang chờ của TV phụ: không mở cả website YouTube nữa, chỉ hướng dẫn dán
## link video. Việc phát dùng iframe nhúng chính thức của YouTube.
const HOME_HTML := """<!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;background:radial-gradient(circle at 50% 35%,#1b0a26,#05040a 70%);
color:#eaf7ff;font-family:'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center}
.card{text-align:center;max-width:76vw}
.logo{font-size:58px;letter-spacing:12px;color:#ffd77a;font-weight:700}
.sub{margin-top:6px;font-size:20px;letter-spacing:7px;color:#35f0ff}
.hint{margin-top:38px;font-size:26px;line-height:1.65;color:#cfd8e3}
.small{margin-top:20px;font-size:15px;color:#8fa3b8}
</style></head><body><div class="card">
<div class="logo">LOTUS TV</div>
<div class="sub">THE CHROME LOTUS</div>
<div class="hint">Dán link video YouTube ở máy tính trong bar<br>rồi bấm <b>Phát video</b>.</div>
<div class="small">Video phát bằng trình nhúng chính thức của YouTube.</div>
</div></body></html>"""


class Visualizer:
	extends Control

	var phase := 0.0
	var track := "Chrome Lotus (QBO Original Demo)"
	var clock := ""

	func _process(delta: float) -> void:
		phase += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0 or h < 4.0:
			return
		var font := ThemeDB.fallback_font
		# Nền gradient tím → đen.
		var bands := 64
		for i in bands:
			var t := float(i) / float(bands)
			var c := Color(0.09, 0.02, 0.14).lerp(Color(0.015, 0.01, 0.04), t)
			draw_rect(Rect2(0.0, h * t, w, h / float(bands) + 1.0), c)
		# Quầng sáng chuyển động.
		for k in 3:
			var cx := w * (0.5 + 0.34 * sin(phase * 0.23 + float(k) * 2.1))
			var cy := h * (0.42 + 0.18 * cos(phase * 0.31 + float(k) * 1.7))
			var radius := h * (0.36 + 0.05 * sin(phase * 0.5 + float(k)))
			draw_circle(Vector2(cx, cy), radius, Color(0.85, 0.12, 0.42, 0.05))
		# Vòng spectrum quanh tâm.
		var center := Vector2(w * 0.5, h * 0.46)
		var spokes := 84
		for i in spokes:
			var angle := TAU * float(i) / float(spokes) - PI * 0.5
			var wave := absf(sin(phase * 2.1 + float(i) * 0.35))
			var wave2 := absf(sin(phase * 1.3 + float(i) * 0.13))
			var length := h * (0.045 + 0.10 * wave * wave2)
			var inner := h * 0.245
			var from := center + Vector2(cos(angle), sin(angle)) * inner
			var to := center + Vector2(cos(angle), sin(angle)) * (inner + length)
			var mix := float(i) / float(spokes)
			var col := Color(1.0, 0.28, 0.55).lerp(Color(0.35, 0.8, 1.0), mix)
			col.a = 0.55
			draw_line(from, to, col, 3.0, true)
		# Vòng tròn chrome.
		for i in range(4):
			var radius := h * (0.19 + 0.018 * float(i)) + sin(phase * 1.2 - float(i) * 0.8) * 5.0
			draw_arc(center, radius, 0.0, TAU, 128, Color(1.0, 0.62, 0.32, 0.16 - float(i) * 0.028), 2.0, true)
		# Chữ thương hiệu.
		draw_string(font, Vector2(0, center.y + h * 0.045), "THE CHROME LOTUS", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.135), Color(1.0, 0.95, 0.9, 0.94))
		draw_string(font, Vector2(0, center.y + h * 0.115), "Q U Ẩ Y   B A R   O N L I N E", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.038), Color(1.0, 0.66, 0.32, 0.9))
		# Ghi công nhà phát triển trên màn LED lớn.
		draw_string(font, Vector2(0, center.y + h * 0.176), "NHÀ PHÁT TRIỂN:  NGUYỄN PHÚ QUYẾT", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.044), Color(1.0, 0.82, 0.5, 0.84))
		# EQ bars đáy màn hình.
		var bars := 56
		var gap := 5.0
		var bar_w := (w - 90.0 - gap * float(bars - 1)) / float(bars)
		for i in bars:
			var level := 0.12 + 0.88 * absf(sin(phase * (1.6 + float(i % 5) * 0.19) + float(i) * 0.42))
			var bh := h * 0.105 * clampf(level, 0.05, 1.0)
			var col := Color(1.0, 0.25, 0.5).lerp(Color(0.3, 0.8, 1.0), float(i) / float(bars))
			col.a = 0.75
			draw_rect(Rect2(45.0 + float(i) * (bar_w + gap), h - 34.0 - bh, bar_w, bh), col)
		# Nhãn LIVE + đồng hồ.
		draw_circle(Vector2(52.0, 46.0), 7.0, Color(1.0, 0.25, 0.35))
		draw_string(font, Vector2(66.0, 55.0), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.040), Color(1.0, 0.4, 0.5))
		draw_string(font, Vector2(0, 55.0), clock, HORIZONTAL_ALIGNMENT_RIGHT, w - 52.0, int(h * 0.040), Color(0.85, 0.9, 1.0, 0.85))
		# Now playing (dưới nhãn LIVE, không đè lên EQ bars).
		draw_string(font, Vector2(52.0, 108.0), "NOW PLAYING  ·  " + track, HORIZONTAL_ALIGNMENT_LEFT, w - 104.0, int(h * 0.036), Color(0.92, 0.9, 0.98, 0.85))
		# Scanlines nhẹ.
		var y := 0.0
		while y < h:
			draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.05), 1.0)
			y += 4.0


class EqBars:
	extends Control
	var phase := 0.0

	func _process(delta: float) -> void:
		phase += delta * 2.2
		queue_redraw()

	func _draw() -> void:
		var bars := 24
		var gap := 6.0
		var bar_w := (size.x - gap * float(bars - 1)) / float(bars)
		for i in bars:
			var speed := 1.0 + float(i % 4) * 0.22
			var level := 0.16 + 0.84 * absf(sin(phase * speed + float(i) * 0.5))
			level = clampf(level, 0.08, 1.0)
			var h := size.y * level
			var c := Color(1.0, 0.25, 0.5).lerp(Color(0.25, 0.75, 1.0), float(i) / float(bars))
			draw_rect(Rect2(float(i) * (bar_w + gap), size.y - h, bar_w, h), c, true)


class CursorDot:
	extends Control

	func _draw() -> void:
		draw_circle(Vector2(15, 15), 10.0, Color(1, 1, 1, 0.72))
		draw_arc(Vector2(15, 15), 15.0, 0.0, TAU, 32, Color(1.0, 0.32, 0.52, 0.95), 2.5)


func _ready() -> void:
	name = "TVSystem"
	provider = QBOBrowserFactory.create()
	_build_visual_viewport()
	_build_web_viewport()
	_create_renderer()
	_build_screen_ui()
	_build_visual_ui()
	_apply_materials()
	_apply_idle()
	Net.tv_input_received.connect(_on_remote_input)
	if renderer != null:
		_load_default_home()


func _load_default_home() -> void:
	## Trang chờ hướng dẫn dán link (không tải sẵn cả YouTube), trừ khi phòng đã
	## có trạng thái TV riêng.
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree() or world == null:
		return
	if not auto_home:
		return
	if not current_state.is_empty():
		return
	if not _web_mode:
		_show_web("data:text/html;charset=utf-8," + HOME_HTML.uri_encode(), "LOTUS TV")


func _create_renderer() -> void:
	if AppConfig.is_dedicated or DisplayServer.get_name() == "headless":
		return
	renderer = QBOWebRenderer.new()
	add_child(renderer)
	renderer.texture_ready.connect(_on_web_texture)
	renderer.page_loaded.connect(_on_web_page_loaded)
	renderer.failed.connect(_on_web_failed)
	renderer.started.connect(_on_web_started)


# ------------------------------------------------------------------ viewports

func _build_visual_viewport() -> void:
	visual_viewport = SubViewport.new()
	visual_viewport.size = VISUAL_SIZE
	# Visualizer chỉ cần ~30 fps; cập nhật từng khung khi tv_system tới nhịp.
	visual_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	visual_viewport.disable_3d = true
	visual_viewport.transparent_bg = false
	add_child(visual_viewport)


func _build_web_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = SCREEN_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)


func _apply_materials() -> void:
	if world == null:
		return
	var visual_texture := visual_viewport.get_texture()
	var visual_material := StandardMaterial3D.new()
	visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual_material.albedo_texture = visual_texture
	# Hạ nhẹ độ sáng để màn hình không bị cháy trắng dưới glow của club.
	visual_material.albedo_color = Color(0.92, 0.92, 0.94)
	visual_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	world.stage_screen_material = visual_material
	if world.stage_screen != null:
		world.stage_screen.material_override = visual_material

	var web_texture := viewport.get_texture()
	var web_material := StandardMaterial3D.new()
	web_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	web_material.albedo_texture = web_texture
	web_material.albedo_color = Color(0.82, 0.82, 0.85)
	web_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	world.web_screen_material = web_material
	if world.stage_web_screen != null:
		world.stage_web_screen.material_override = web_material


# ------------------------------------------------------------------ web screen UI

func _build_screen_ui() -> void:
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(screen_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.008, 0.03)
	screen_root.add_child(bg)

	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.34, 0.03, 0.17, 0.95))
	gradient.set_color(1, Color(0.02, 0.03, 0.1, 0.95))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.9)
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	screen_root.add_child(glow)

	_build_idle_layer()
	_build_web_layer()

	progress_label = Label.new()
	progress_label.text = ""
	progress_label.position = Vector2(1700, 1020)
	progress_label.size = Vector2(180, 40)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.add_theme_font_size_override("font_size", 26)
	progress_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	screen_root.add_child(progress_label)

	video = VideoStreamPlayer.new()
	video.position = Vector2.ZERO
	video.size = Vector2(SCREEN_SIZE.x, SCREEN_SIZE.y)
	video.expand = true
	video.visible = false
	screen_root.add_child(video)


func _build_visual_ui() -> void:
	var vis := Visualizer.new()
	vis.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual_viewport.add_child(vis)
	visualizer = vis


func _build_idle_layer() -> void:
	_idle_layer = Control.new()
	_idle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(_idle_layer)

	var accent := ColorRect.new()
	accent.color = Color(1.0, 0.32, 0.52)
	accent.position = Vector2(0, 1072)
	accent.size = Vector2(1920, 8)
	_idle_layer.add_child(accent)

	var frame := VBoxContainer.new()
	frame.position = Vector2(96, 300)
	frame.size = Vector2(1100, 460)
	frame.add_theme_constant_override("separation", 14)
	_idle_layer.add_child(frame)

	var brand := Label.new()
	brand.text = "QUẨY BAR ONLINE  •  THE CHROME LOTUS"
	brand.add_theme_font_size_override("font_size", 30)
	brand.add_theme_color_override("font_color", Color(1.0, 0.66, 0.32))
	frame.add_child(brand)

	title_label = Label.new()
	title_label.text = "The Chrome Lotus"
	title_label.add_theme_font_size_override("font_size", 96)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.9))
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size = Vector2(1100, 120)
	frame.add_child(title_label)

	status_label = Label.new()
	status_label.text = "Chưa có nội dung được chia sẻ."
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.92))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(1100, 110)
	frame.add_child(status_label)

	url_label = Label.new()
	url_label.text = ""
	url_label.add_theme_font_size_override("font_size", 28)
	url_label.add_theme_color_override("font_color", Color(0.5, 0.82, 1.0))
	url_label.clip_text = true
	url_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	url_label.custom_minimum_size = Vector2(1100, 36)
	frame.add_child(url_label)

	provider_label = Label.new()
	provider_label.text = ""
	provider_label.add_theme_font_size_override("font_size", 24)
	provider_label.add_theme_color_override("font_color", Color(0.58, 0.58, 0.7))
	provider_label.clip_text = true
	provider_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	provider_label.custom_minimum_size = Vector2(1100, 30)
	frame.add_child(provider_label)

	var eq := EqBars.new()
	eq.position = Vector2(1250, 320)
	eq.size = Vector2(520, 360)
	_idle_layer.add_child(eq)

	var live := Label.new()
	live.text = "● LIVE"
	live.position = Vector2(1740, 60)
	live.add_theme_font_size_override("font_size", 30)
	live.add_theme_color_override("font_color", Color(1.0, 0.3, 0.4))
	_idle_layer.add_child(live)


func _build_web_layer() -> void:
	_web_layer = Control.new()
	_web_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_web_layer.visible = false
	screen_root.add_child(_web_layer)

	var page_bg := ColorRect.new()
	page_bg.color = Color(0.04, 0.043, 0.055)
	page_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_web_layer.add_child(page_bg)

	_web_page = TextureRect.new()
	_web_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_web_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_web_page.stretch_mode = TextureRect.STRETCH_SCALE
	_web_layer.add_child(_web_page)

	_web_loading = Label.new()
	_web_loading.text = "Đang tải trang…"
	_web_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_web_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_web_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_web_loading.add_theme_font_size_override("font_size", 44)
	_web_loading.add_theme_color_override("font_color", Color(0.78, 0.76, 0.88))
	_web_layer.add_child(_web_loading)

	_web_cursor = CursorDot.new()
	_web_cursor.size = Vector2(30, 30)
	_web_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_web_cursor.visible = false
	_web_layer.add_child(_web_cursor)

	# Nhắc rằng bàn phím đang gửi vào trang web (ESC để thoát).
	_web_focus_badge = Label.new()
	_web_focus_badge.text = "ĐANG GÕ VÀO TRANG  ·  ESC để thoát"
	_web_focus_badge.position = Vector2(560, 18)
	_web_focus_badge.size = Vector2(800, 46)
	_web_focus_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_web_focus_badge.add_theme_font_size_override("font_size", 26)
	_web_focus_badge.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	_web_focus_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_web_focus_badge.add_theme_constant_override("shadow_offset_x", 2)
	_web_focus_badge.add_theme_constant_override("shadow_offset_y", 2)
	_web_focus_badge.visible = false
	_web_layer.add_child(_web_focus_badge)


func _apply_idle() -> void:
	current_state = {}
	_applied_signature = ""
	_set_web_mode(false)
	if title_label != null:
		title_label.text = "The Chrome Lotus"
		url_label.text = "Đêm nay • Sàn nhảy tầng chính • DJ booth mở"
		status_label.text = "Chia sẻ nội dung từ máy tính trong bar để hiển thị tại đây."
		provider_label.text = ""
		progress_label.text = ""


func apply_state(state: Dictionary) -> void:
	current_state = state.duplicate(true)
	var title := str(state.get("title", ""))
	var url := str(state.get("url", ""))
	var playing := bool(state.get("playing", false))
	var status := str(state.get("status", ""))
	var provider_status := str(state.get("provider", ""))
	var kind := str(state.get("kind", "web"))
	var position := float(state.get("position", 0.0))
	# Video YouTube phát bằng iframe nhúng; `url` vẫn giữ link gốc để hiển thị.
	var render_url := str(state.get("embed_url", ""))
	if kind == "youtube" and renderer != null:
		var local_page: String = renderer.player_page_url(str(state.get("video_id", "")))
		if local_page != "":
			render_url = local_page
	if render_url == "":
		render_url = url
	if title_label == null:
		return
	var signature := "%s|%s|%s|%s" % [render_url, kind, str(state.get("updated_at", "")), str(playing)]
	if kind == "web" or kind == "youtube":
		if _can_render_web() and render_url != "":
			if signature != _applied_signature or not _web_mode:
				_applied_signature = signature
				_show_web(render_url, title)
			return
	_set_web_mode(false)
	title_label.text = title if title != "" else (url if url != "" else "TV sân khấu")
	url_label.text = url
	status_label.text = status if status != "" else ("Đang phát" if playing else "Đã dừng")
	provider_label.text = provider_status
	progress_label.text = _format_time(position) if kind == "video" and playing else ""
	if kind == "video" and url != "" and provider_status.begins_with("Sẵn sàng"):
		_play_video(url, position, playing)
	else:
		if video.visible:
			video.stop()
			video.visible = false


# ------------------------------------------------------------------ web layer

func _can_render_web() -> bool:
	return renderer != null and renderer.available


func web_backend_name() -> String:
	if _can_render_web():
		return "Chromium headless (CDP)"
	return ""


func _show_web(url: String, title: String) -> void:
	if video.visible:
		video.stop()
		video.visible = false
	_set_web_mode(true)
	_web_loading.text = "Đang tải trang…"
	_web_loading.visible = true
	if title != "":
		_web_loading.tooltip_text = title
	if not renderer.running:
		if not renderer.start(SCREEN_SIZE):
			return
	renderer.navigate(url)


func _on_web_started() -> void:
	if _web_mode:
		_web_loading.text = "Đang tải trang…"


func _on_web_texture(texture: Texture2D) -> void:
	if _web_page == null:
		return
	_web_page.texture = texture
	_web_loading.visible = false


func _on_web_page_loaded(_title: String, _url: String) -> void:
	pass


func _on_web_failed(reason: String) -> void:
	if _web_mode:
		_web_loading.text = reason
		_web_loading.visible = true
	else:
		status_label.text = reason


func _set_web_mode(enabled: bool) -> void:
	_web_mode = enabled
	if _idle_layer != null:
		_idle_layer.visible = not enabled
	if _web_layer != null:
		_web_layer.visible = enabled
	if not enabled and _web_cursor != null:
		_web_cursor.visible = false


# ------------------------------------------------------------------ shared web surface

func web_available() -> bool:
	return renderer != null and renderer.available


func is_web_active() -> bool:
	return _web_mode and renderer != null and renderer.texture != null


## Texture dùng chung: TV phụ và máy tính trong bar hiển thị cùng một trang.
func shared_texture() -> Texture2D:
	if renderer == null:
		return null
	return renderer.texture


func shared_url() -> String:
	if not current_state.is_empty():
		return str(current_state.get("url", ""))
	return renderer.current_url if renderer != null else ""


## Mở một URL trên màn web và đồng bộ trạng thái cho cả phòng.
func show_shared(url: String, title := "") -> Dictionary:
	var check := QBOUrlGuard.validate(url)
	if not check["ok"]:
		return {"ok": false, "reason": str(check["reason"])}
	return publish(str(check["url"]), title, true)


func move_page(pixel: Vector2) -> void:
	## Hover chuột trên trang (hiện thanh điều khiển YouTube, tooltip…). Không
	## broadcast qua mạng để tránh spam mỗi frame.
	if renderer == null or not renderer.available:
		return
	renderer.mouse_move(
		clampf(pixel.x, 0.0, float(SCREEN_SIZE.x - 1)),
		clampf(pixel.y, 0.0, float(SCREEN_SIZE.y - 1))
	)


func click_page(pixel: Vector2, broadcast := true) -> void:
	if renderer == null or not renderer.available:
		return
	var page_pixel := Vector2(
		clampf(pixel.x, 0.0, float(SCREEN_SIZE.x - 1)),
		clampf(pixel.y, 0.0, float(SCREEN_SIZE.y - 1))
	)
	renderer.mouse_click(page_pixel.x, page_pixel.y)
	if broadcast:
		Net.send_tv_input({"type": "click", "x": page_pixel.x, "y": page_pixel.y})


func wheel_page(pixel: Vector2, delta: float, broadcast := true) -> void:
	if renderer == null or not renderer.available:
		return
	var page_pixel := Vector2(
		clampf(pixel.x, 0.0, float(SCREEN_SIZE.x - 1)),
		clampf(pixel.y, 0.0, float(SCREEN_SIZE.y - 1))
	)
	renderer.mouse_wheel(page_pixel.x, page_pixel.y, delta)
	if broadcast:
		Net.send_tv_input({"type": "wheel", "x": page_pixel.x, "y": page_pixel.y, "delta": delta})


func _on_remote_input(payload: Dictionary) -> void:
	match str(payload.get("type", "")):
		"click":
			click_page(Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0))), false)
		"wheel":
			wheel_page(Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0))), float(payload.get("delta", 0.0)), false)
		"key":
			if renderer != null:
				renderer.dispatch_key(payload)


# ------------------------------------------------------------------ keyboard focus

## Bật chế độ gõ bàn phím vào trang: WASD không di chuyển nhân vật nữa.
func focus_web() -> void:
	if _web_focus:
		return
	_web_focus = true
	if _web_focus_badge != null:
		_web_focus_badge.visible = true
	if App.ui != null and App.ui.has_method("set_web_typing"):
		App.ui.call("set_web_typing", true)


func blur_web() -> void:
	if not _web_focus:
		return
	_web_focus = false
	if _web_focus_badge != null:
		_web_focus_badge.visible = false
	if App.ui != null and App.ui.has_method("set_web_typing"):
		App.ui.call("set_web_typing", false)


func is_web_focused() -> bool:
	return _web_focus


## Gửi một phím tới trang web và đồng bộ cho cả phòng.
func key_page(event: InputEventKey, pressed: bool) -> void:
	if renderer == null or not renderer.available:
		return
	var payload := QBOWebRenderer.key_payload(event, pressed)
	renderer.dispatch_key(payload)
	Net.send_tv_input(payload)


## Chặn phím trước khi HUD/nhân vật nhận, để gõ được vào trang.
func _input(event: InputEvent) -> void:
	if not _web_focus or not _web_mode:
		return
	if not (event is InputEventKey):
		return
	if App.ui != null and bool(App.ui.call("is_overlay_open")):
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE and key_event.pressed:
		blur_web()
	key_page(key_event, key_event.pressed)
	get_viewport().set_input_as_handled()


## Toạ độ pixel trên màn web tại một điểm trên cửa sổ game.
## Trả Vector2(-1, -1) nếu tia không cắt TV phụ.
func screen_pixel_at(window_pos: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null or world == null or world.stage_web_screen == null:
		return Vector2(-1, -1)
	var origin: Vector3
	var direction: Vector3
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		origin = camera.project_ray_origin(window_pos)
		direction = camera.project_ray_normal(window_pos)
	else:
		origin = camera.global_position
		direction = -camera.global_transform.basis.z
	# Đưa tia vào không gian local của TV phụ (TV có thể nghiêng).
	var xform := world.stage_web_screen.global_transform
	var inv := xform.affine_inverse()
	var local_origin := inv * origin
	var local_dir := (inv.basis * direction).normalized()
	if absf(local_dir.z) < 0.0001:
		return Vector2(-1, -1)
	var t := -local_origin.z / local_dir.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var hit := local_origin + local_dir * t
	var half := Nightclub.SIDE_TV_SIZE * 0.5
	if absf(hit.x) > half.x or absf(hit.y) > half.y:
		return Vector2(-1, -1)
	if origin.distance_to(xform * hit) > 70.0:
		return Vector2(-1, -1)
	var u := hit.x / Nightclub.SIDE_TV_SIZE.x + 0.5
	var v := 0.5 - hit.y / Nightclub.SIDE_TV_SIZE.y
	return Vector2(u * float(SCREEN_SIZE.x), v * float(SCREEN_SIZE.y))


func _unhandled_input(event: InputEvent) -> void:
	if not _web_mode or renderer == null:
		return
	if App.ui != null and bool(App.ui.call("is_input_blocked")):
		return
	if event is InputEventMouseButton and event.pressed:
		# Khi chuột đang hiện (menu/PC), bấm đúng vị trí con trỏ; khi khoá chuột
		# (gameplay FPS) thì bắn tia từ tâm màn hình theo tâm ngắm.
		var pixel := _aim_pixel(event.position)
		if pixel.x < 0.0:
			# Bấm ra ngoài màn web: thoát chế độ gõ.
			if event.button_index == MOUSE_BUTTON_LEFT:
				blur_web()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			focus_web()
			click_page(pixel)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel_page(pixel, -120.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_page(pixel, 120.0)
			get_viewport().set_input_as_handled()


func _aim_pixel(at := Vector2.INF) -> Vector2:
	# Chuột khoá: tâm ngắm luôn ở giữa khung hình. Chuột hiện: dùng đúng vị trí
	# con trỏ để bấm trúng chỗ người chơi đang chỉ.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		var pos := at
		if pos == Vector2.INF:
			pos = get_viewport().get_mouse_position()
		return screen_pixel_at(pos)
	return screen_pixel_at(get_viewport().get_visible_rect().size * 0.5)


func _update_web_cursor(delta: float) -> void:
	if _web_cursor == null:
		return
	if not _web_mode or renderer == null:
		_web_cursor.visible = false
		_last_move_px = Vector2(-10000, -10000)
		return
	_move_check -= delta
	# Cập nhật mỗi frame, không hạ tần số: con trỏ vẽ trên TV phải bám sát tâm
	# ngắm, nếu trễ sẽ khiến người chơi bấm lệch.
	var pixel := _aim_pixel()
	if pixel.x < 0.0:
		_web_cursor.visible = false
		_last_move_px = Vector2(-10000, -10000)
		return
	_web_cursor.visible = true
	_web_cursor.position = pixel - Vector2(15, 15)
	# Gửi hover thưa (12.5 Hz) để trang hiện thanh điều khiển/nút bấm đúng chỗ.
	if _move_check <= 0.0 and pixel.distance_to(_last_move_px) > 1.0:
		_move_check = 0.08
		_last_move_px = pixel
		renderer.mouse_move(pixel.x, pixel.y)


func _update_visual_hud(delta: float) -> void:
	if visualizer == null:
		return
	_hud_check -= delta
	if _hud_check > 0.0:
		return
	_hud_check = 0.5
	visualizer.clock = Time.get_time_string_from_system().substr(0, 5)
	var dj: Node = App.world.dj if App.world != null else null
	if dj != null:
		var title_value = dj.get("current_title")
		if title_value != null and str(title_value) != "":
			visualizer.track = str(title_value)


func _play_video(url: String, position: float, playing: bool) -> void:
	video.visible = true
	if video.stream == null:
		_download_video(url, position)
	if not playing:
		video.paused = true
		return
	video.paused = false


func _download_video(url: String, position: float) -> void:
	if _download != null:
		_download.queue_free()
	_download = HTTPRequest.new()
	_download.timeout = 25.0
	add_child(_download)
	var err := _download.request(url)
	if err != OK:
		status_label.text = "Không tải được video .ogv."
		return
	var res: Array = await _download.request_completed
	var code: int = res[1]
	var bytes: PackedByteArray = res[3]
	if code < 200 or code >= 300 or bytes.is_empty():
		video.visible = false
		status_label.text = "Video không tải được (HTTP %d)." % code
		return
	var path := "user://tv_stream_%d.ogv" % Time.get_ticks_msec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
	# Theora là định dạng video duy nhất Godot phát native; MP4 cần plugin/WebView.
	var stream := VideoStreamTheora.new()
	stream.file = path
	video.stream = stream
	video.play()
	if position > 0.1:
		video.stream_position = position


static func youtube_embed_url(video_id: String) -> String:
	return "https://www.youtube.com/embed/%s?autoplay=1&rel=0&modestbranding=1&playsinline=1&origin=https%%3A%%2F%%2Fwww.youtube.com" % video_id


func play_youtube(url_input: String, title := "") -> Dictionary:
	## Phát một video YouTube bằng iframe nhúng chính thức. Người chơi chỉ cần
	## dán link, không phải thao tác trên cả trang web.
	var video_id := QBOUrlGuard.youtube_video_id(url_input)
	if video_id == "":
		return {"ok": false, "reason": "Link YouTube không hợp lệ. Dán link dạng youtube.com/watch?v=… hoặc youtu.be/…"}
	if not _can_render_web():
		return {"ok": false, "reason": "Máy này chưa có trình duyệt nhúng để phát video."}
	var watch_url := "https://www.youtube.com/watch?v=" + video_id
	var state := {
		"url": watch_url,
		"embed_url": youtube_embed_url(video_id),
		"title": title if title != "" else "YouTube",
		"playing": true,
		"position": 0.0,
		"volume": float(current_state.get("volume", 1.0)),
		"kind": "youtube",
		"video_id": video_id,
		"status": "Đang phát video YouTube (nhúng).",
		"provider": "Sẵn sàng — %s" % web_backend_name(),
		"by": GameState.display_name(),
		"updated_at": Time.get_unix_time_from_system(),
	}
	Net.send_tv(state)
	return {
		"ok": true, "state": state, "kind": "youtube", "embedded": true,
		"video_id": video_id, "status": str(state["status"]),
	}


func publish(url_input: String, title := "", playing := true) -> Dictionary:
	var check := QBOUrlGuard.validate(url_input)
	if not check["ok"]:
		return {"ok": false, "reason": str(check["reason"])}
	var capability := provider.capability()
	var web_backend := web_backend_name()
	var embedded := bool(capability.get("embedded", false)) or web_backend != ""
	var status := ""
	var provider_text := ""
	var kind := str(check["kind"])
	var url := str(check["url"])
	if kind == "youtube":
		var video_id := QBOUrlGuard.youtube_video_id(url)
		if video_id != "":
			return play_youtube(url, title)
		if embedded:
			status = "Đang mở YouTube trên màn web sân khấu qua trình duyệt nhúng."
			provider_text = "Sẵn sàng — %s" % (web_backend if web_backend != "" else provider.provider_name())
		else:
			status = "Đã đồng bộ URL YouTube. Chưa thể phát trên màn hình này vì chưa có trình duyệt nhúng — mở bằng trình duyệt để xem."
			provider_text = "Không nhúng được — %s" % str(capability.get("reason", ""))
	elif kind == "video":
		status = "Đang tải video Theora (.ogv)…" if embedded else "Video .ogv: cần xác nhận và tải trực tiếp."
		provider_text = "Sẵn sàng — phát native VideoStreamPlayer" if embedded else str(capability.get("reason", ""))
	elif kind == "audio":
		status = "URL là tệp âm thanh — hãy dùng bảng DJ thay vì màn hình TV."
		provider_text = ""
	elif kind == "web":
		if embedded:
			status = "Đang hiển thị trang web trên màn web sân khấu."
			provider_text = "Sẵn sàng — %s" % (web_backend if web_backend != "" else provider.provider_name())
		else:
			status = "Đã đồng bộ URL. Chưa có trình duyệt nhúng trên thiết bị này."
			provider_text = "Không nhúng được — %s" % str(capability.get("reason", ""))
	var state := {
		"url": url,
		"title": title if title != "" else str(check["host"]),
		"playing": playing,
		"position": 0.0,
		"volume": float(current_state.get("volume", 1.0)),
		"kind": kind,
		"status": status,
		"provider": provider_text,
		"by": GameState.display_name(),
		"updated_at": Time.get_unix_time_from_system(),
	}
	Net.send_tv(state)
	return {"ok": true, "state": state, "kind": kind, "embedded": embedded, "status": status}


func set_playing(value: bool) -> void:
	if current_state.is_empty():
		return
	var state := current_state.duplicate(true)
	state["playing"] = value
	state["position"] = _elapsed
	Net.send_tv(state)


func set_volume(value: float) -> void:
	var state := current_state.duplicate(true)
	state["volume"] = clampf(value, 0.0, 1.0)
	Net.send_tv(state)


func _process(delta: float) -> void:
	_update_web_cursor(delta)
	_update_visual_hud(delta)
	# Visualizer ở ~30 fps thay vì mỗi frame: viewport 2D vẽ nhiều hình, hạ nhịp
	# không thấy khác biệt nhưng tiết kiệm đáng kể trên GPU yếu.
	_visual_check -= delta
	if _visual_check <= 0.0 and visual_viewport != null:
		_visual_check = 0.033
		visual_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Mở bảng điều khiển (máy tính/DJ) thì nhả focus bàn phím của TV.
	if _web_focus and App.ui != null and bool(App.ui.call("is_overlay_open")):
		blur_web()
	if bool(current_state.get("playing", false)) and str(current_state.get("kind", "")) == "video":
		_elapsed += delta
		if progress_label != null:
			progress_label.text = _format_time(_elapsed)


func _exit_tree() -> void:
	if renderer != null:
		renderer.stop_browser()


func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func capability() -> Dictionary:
	var cap := provider.capability().duplicate()
	if _can_render_web():
		cap["embedded"] = true
		cap["reason"] = ""
	return cap
