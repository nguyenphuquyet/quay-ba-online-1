extends Control

var ui: CanvasLayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := QBOTheme.vbox(14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	var brand := QBOTheme.title("QUẨY BAR ONLINE", 64)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(brand)
	var sub := QBOTheme.label("THE CHROME LOTUS  •  NIGHTCLUB ONLINE", 16, QBOTheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(320, 6)
	progress.show_percentage = false
	progress.value = 35
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = QBOTheme.GOLD
	fill.set_corner_radius_all(3)
	progress.add_theme_stylebox_override("background", bg)
	progress.add_theme_stylebox_override("fill", fill)
	box.add_child(progress)
	var loading := QBOTheme.muted("Đang kết nối câu lạc bộ…", 14)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(loading)
