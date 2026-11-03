class_name QBOTheme
extends RefCounted
## Design system của QUẨY BAR ONLINE.
##
## Giao diện dùng bộ asset **Game Menu Kit Lite** (MIT) làm nền tảng thị giác:
## font Orbitron/Rajdhani, bảng màu neon cyan–magenta, panel tối viền phát sáng.
## Các màn hình không phải main menu vẫn dựng bằng code nhưng lấy đúng palette,
## font và kiểu button/panel của kit để cả game đồng bộ một ngôn ngữ thiết kế.

# Bảng màu neon của Game Menu Kit Lite (Neon style).
const BG := Color("05030d")
const PANEL := Color(0.063, 0.043, 0.149, 0.95)
const PANEL_ALT := Color(0.027, 0.016, 0.071, 0.96)
const STROKE := Color(0.208, 0.941, 1.0, 0.28)
const ACCENT := Color("35f0ff")
const ACCENT_2 := Color("ff3fb4")
## Giữ tên cũ để các màn hình đang dùng không phải sửa: GOLD giờ là cyan của kit.
const GOLD := Color("35f0ff")
const GOLD_BRIGHT := Color("9df9ff")
const NEON := Color("ff3fb4")
const CYAN := Color("35f0ff")
const PURPLE := Color("b06bff")
const TEXT := Color("e8f7ff")
const MUTED := Color("8a9cc2")
const DANGER := Color("ff5470")
const SUCCESS := Color("5ef2c0")

const KIT_FONTS := "res://addons/game_menu_kit/fonts/"
const ORBITRON_PATH := KIT_FONTS + "Orbitron-Variable.ttf"
const RAJDHANI_PATH := KIT_FONTS + "Rajdhani-SemiBold.ttf"
const RAJDHANI_BOLD_PATH := KIT_FONTS + "Rajdhani-Bold.ttf"

static var _theme: Theme
static var _font: Font
static var _bold_font: Font
static var _title_font: Font


# ------------------------------------------------------------------ fonts

static func _fallback_font() -> Font:
	# Rajdhani/Orbitron không phủ hết dấu tiếng Việt; font hệ điều hành bù glyph thiếu.
	var system := SystemFont.new()
	system.font_names = PackedStringArray([
		"Segoe UI", "Noto Sans", "Roboto", "Helvetica Neue", "Arial", "Microsoft YaHei",
	])
	system.font_weight = 500
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return system


static func _load_font(path: String, weight := 0, spacing := 0) -> Font:
	var base: FontFile = load(path)
	if base == null:
		return _fallback_font()
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [_fallback_font()]
	if weight > 0:
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		variation.variation_opentype = {tag: weight}
	variation.spacing_glyph = spacing
	return variation


static func font() -> Font:
	if _font == null:
		_font = _load_font(RAJDHANI_PATH)
	return _font


static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = _load_font(RAJDHANI_BOLD_PATH)
	return _bold_font


static func title_font() -> Font:
	if _title_font == null:
		# Orbitron là variable font: lấy weight 800 cho tiêu đề dày, phát sáng.
		_title_font = _load_font(ORBITRON_PATH, 800, 2)
	return _title_font


# ------------------------------------------------------------------ theme

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16

	# Button — panel tối, viền cyan, thanh nhấn bên trái như menu kit.
	t.set_stylebox("normal", "Button", _neon_button_style(Color(0.025, 0.02, 0.07, 0.82), Color(ACCENT, 0.35)))
	t.set_stylebox("hover", "Button", _neon_button_style(Color(ACCENT, 0.14), ACCENT))
	t.set_stylebox("pressed", "Button", _neon_button_style(Color(ACCENT, 0.28), Color.WHITE))
	t.set_stylebox("focus", "Button", _outline_style())
	t.set_stylebox("disabled", "Button", _neon_button_style(Color(0.03, 0.03, 0.06, 0.5), Color(1, 1, 1, 0.08)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.68))
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 17)
	t.set_constant("outline_size", "Button", 0)

	# LineEdit.
	t.set_stylebox("normal", "LineEdit", _input_style())
	t.set_stylebox("focus", "LineEdit", _input_style(ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.6, 0.75))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT_2, 0.35))
	t.set_font("font", "LineEdit", font())
	t.set_font_size("font_size", "LineEdit", 17)
	t.set_constant("minimum_character_width", "LineEdit", 4)

	# Labels.
	t.set_color("font_color", "Label", TEXT)
	t.set_font("font", "Label", font())
	t.set_font_size("font_size", "Label", 16)

	# Panels.
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PopupPanel", panel_style(PANEL_ALT, 3))

	# CheckBox / Slider / OptionButton.
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", ACCENT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_font("font", "CheckBox", font())
	t.set_stylebox("normal", "HSlider", _slider_bg())
	t.set_stylebox("grabber_area", "HSlider", _slider_fill())
	t.set_stylebox("grabber_area_highlight", "HSlider", _slider_fill(true))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_font("font", "OptionButton", bold_font())
	t.set_stylebox("normal", "OptionButton", _neon_button_style(Color(0.025, 0.02, 0.07, 0.82), Color(ACCENT, 0.35)))
	t.set_stylebox("hover", "OptionButton", _neon_button_style(Color(ACCENT, 0.14), ACCENT))
	t.set_stylebox("pressed", "OptionButton", _neon_button_style(Color(ACCENT, 0.28), Color.WHITE))
	t.set_font_size("font_size", "OptionButton", 16)

	t.set_stylebox("panel", "TooltipPanel", panel_style(PANEL_ALT, 3))
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_stylebox("scroll", "VScrollBar", _scrollbar_style())
	t.set_stylebox("grabber", "VScrollBar", _scrollbar_grabber())
	t.set_stylebox("grabber_highlight", "VScrollBar", _scrollbar_grabber(true))
	t.set_stylebox("grabber_pressed", "VScrollBar", _scrollbar_grabber(true))

	_theme = t
	return t


static func _neon_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	# Viền trái dày hơn = thanh nhấn neon đặc trưng của menu kit.
	style.border_width_left = 3
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 22
	style.content_margin_right = 20
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	style.shadow_color = Color(ACCENT, 0.10)
	style.shadow_size = 8
	return style


static func _outline_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ACCENT, 0.06)
	style.border_color = Color(ACCENT, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(ACCENT, 0.28)
	style.shadow_size = 10
	return style


static func _input_style(border := Color(ACCENT, 0.28)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.018, 0.06, 0.92)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style


static func panel_style(bg := PANEL, radius := 4, border := STROKE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	style.shadow_color = Color(ACCENT, 0.10)
	style.shadow_size = 18
	return style


static func _slider_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.12)
	style.set_corner_radius_all(2)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


static func _slider_fill(highlight := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT if not highlight else GOLD_BRIGHT
	style.set_corner_radius_all(2)
	return style


static func _scrollbar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.03)
	style.set_corner_radius_all(2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	return style


static func _scrollbar_grabber(highlight := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ACCENT, 0.7 if highlight else 0.4)
	style.set_corner_radius_all(2)
	style.content_margin_left = 4
	style.content_margin_right = 4
	return style


# ------------------------------------------------------------------ builders

static func panel(padding := 24) -> PanelContainer:
	var node := PanelContainer.new()
	var style := panel_style()
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	node.add_theme_stylebox_override("panel", style)
	return node


static func label(text: String, size := 16, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func title(text: String, size := 40) -> Label:
	var node := label(text, size, Color.WHITE)
	node.add_theme_font_override("font", title_font())
	node.add_theme_color_override("font_shadow_color", Color(ACCENT, 0.35))
	node.add_theme_constant_override("shadow_offset_x", 0)
	node.add_theme_constant_override("shadow_offset_y", 0)
	node.add_theme_constant_override("shadow_outline_size", 10)
	return node


static func muted(text: String, size := 14) -> Label:
	return label(text, size, MUTED)


static func section(text: String) -> Label:
	var node := label(text.to_upper(), 13, ACCENT)
	node.add_theme_font_override("font", bold_font())
	node.add_theme_constant_override("outline_size", 0)
	return node


static func button(text: String, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_override("font", bold_font())
	node.focus_mode = Control.FOCUS_ALL
	if primary:
		var normal := _neon_button_style(Color(ACCENT, 0.16), ACCENT)
		var hover := _neon_button_style(Color(ACCENT, 0.3), Color.WHITE)
		node.add_theme_stylebox_override("normal", normal)
		node.add_theme_stylebox_override("hover", hover)
		node.add_theme_stylebox_override("pressed", hover)
		node.add_theme_color_override("font_color", Color.WHITE)
		node.add_theme_color_override("font_hover_color", Color.WHITE)
	return node


## Nút lớn kiểu menu kit (bevel, gạch nhấn, hiệu ứng focus). Dùng cho main menu.
static func menu_button(text: String, sub := "") -> MenuKitMenuButton:
	var node := MenuKitMenuButton.new(text)
	node.sub_text = sub
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func line_edit(placeholder: String, secret := false, max_length := 64) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.secret = secret
	node.max_length = max_length
	node.add_theme_font_override("font", font())
	node.custom_minimum_size = Vector2(0, 46)
	return node


static func field(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(section(label_text))
	box.add_child(control)
	return box


static func hsep(height := 8) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func vbox(separation := 12) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation := 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func margins(px := 48) -> MarginContainer:
	var node := MarginContainer.new()
	node.add_theme_constant_override("margin_left", px)
	node.add_theme_constant_override("margin_right", px)
	node.add_theme_constant_override("margin_top", px)
	node.add_theme_constant_override("margin_bottom", px)
	return node


static func swatch(color: Color, size := 26) -> Panel:
	var node := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.border_color = Color(1, 1, 1, 0.25)
	style.set_border_width_all(1)
	node.add_theme_stylebox_override("panel", style)
	node.custom_minimum_size = Vector2(size, size)
	return node
