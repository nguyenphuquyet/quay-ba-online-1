class_name QBOVirtualJoystick
extends Control
## Joystick ảo "nổi" cho mobile: chạm bất kỳ đâu trong vùng di chuyển là cần
## điều khiển xuất hiện tại đúng ngón tay, kéo để di chuyển, nhả để dừng.
## Không còn cố định một chỗ nên không cần nhìn xuống màn hình để bấm.

signal moved(value: Vector2)

const BASE_RADIUS := 66.0
const KNOB_RADIUS := 27.0
const EDGE_PADDING := 12.0
# Vùng chết nhỏ để ngón tay hơi rung không làm nhân vật trôi.
const DEAD_ZONE := 0.12

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _active := false
var _hint := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_update_hint)
	_update_hint()


func _update_hint() -> void:
	# Gợi ý mờ ở góc dưới trái để người chơi biết vùng chạm.
	_hint = Vector2(BASE_RADIUS + 40.0, size.y - BASE_RADIUS - 40.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_begin(touch.index, touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_drag(drag.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _touch_index == -1:
				_begin(0, mb.position)
			elif not mb.pressed and _touch_index == 0:
				_end()
	elif event is InputEventMouseMotion and _touch_index == 0:
		_update_drag((event as InputEventMouseMotion).position)


func _begin(index: int, position: Vector2) -> void:
	_touch_index = index
	var limit_min := Vector2(BASE_RADIUS + EDGE_PADDING, BASE_RADIUS + EDGE_PADDING)
	var limit_max := size - limit_min
	_origin = position.clamp(limit_min, limit_max)
	_knob = Vector2.ZERO
	_active = true
	moved.emit(Vector2.ZERO)
	queue_redraw()


func _update_drag(position: Vector2) -> void:
	var delta := position - _origin
	var length := delta.length()
	if length > BASE_RADIUS:
		delta = delta / length * BASE_RADIUS
		length = BASE_RADIUS
	_knob = delta
	var value := Vector2(delta.x, -delta.y) / BASE_RADIUS
	var magnitude := length / BASE_RADIUS
	if magnitude < DEAD_ZONE:
		value = Vector2.ZERO
	else:
		value = value.normalized() * ((magnitude - DEAD_ZONE) / (1.0 - DEAD_ZONE))
	moved.emit(value)
	queue_redraw()


func _end() -> void:
	_touch_index = -1
	_knob = Vector2.ZERO
	_active = false
	moved.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	if _active:
		draw_circle(_origin, BASE_RADIUS + 10.0, Color(0.03, 0.02, 0.05, 0.34))
		draw_arc(_origin, BASE_RADIUS + 10.0, 0.0, TAU, 48, Color(1, 1, 1, 0.20), 2.0)
		draw_circle(_origin, 6.0, Color(1, 1, 1, 0.14))
		var knob_pos := _origin + _knob
		draw_circle(knob_pos, KNOB_RADIUS, Color(0.96, 0.82, 0.53, 0.30))
		draw_arc(knob_pos, KNOB_RADIUS, 0.0, TAU, 40, Color(0.96, 0.82, 0.53, 0.9), 2.0)
	else:
		# Trạng thái nghỉ: chỉ một vòng mờ để đánh dấu vùng chạm.
		draw_arc(_hint, BASE_RADIUS * 0.85, 0.0, TAU, 40, Color(1, 1, 1, 0.10), 2.0)
		draw_circle(_hint, 5.0, Color(1, 1, 1, 0.08))
