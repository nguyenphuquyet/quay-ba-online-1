class_name QBOVirtualJoystick
extends Control
## Joystick ảo cho mobile: kéo để di chuyển, nhả để dừng.

signal moved(value: Vector2)

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _radius := 68.0


func _ready() -> void:
	custom_minimum_size = Vector2(176, 176)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_origin = size * 0.5
	_radius = minf(size.x, size.y) * 0.38


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_origin = touch.position
			_radius = minf(size.x, size.y) * 0.38
			_knob = Vector2.ZERO
			queue_redraw()
		elif not touch.pressed and touch.index == _touch_index:
			_reset()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			var delta := drag.position - _origin
			var length := delta.length()
			if length > _radius:
				delta = delta / length * _radius
			_knob = delta
			moved.emit(Vector2(delta.x, -delta.y) / _radius)
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_touch_index = 0
				_origin = mb.position
				_knob = Vector2.ZERO
				queue_redraw()
			elif _touch_index == 0:
				_reset()
	elif event is InputEventMouseMotion and _touch_index == 0:
		var motion := event as InputEventMouseMotion
		var delta := motion.position - _origin
		var length := delta.length()
		if length > _radius:
			delta = delta / length * _radius
		_knob = delta
		moved.emit(Vector2(delta.x, -delta.y) / _radius)
		queue_redraw()


func _reset() -> void:
	_touch_index = -1
	_knob = Vector2.ZERO
	moved.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	draw_circle(center, _radius + 12.0, Color(0.03, 0.02, 0.05, 0.42))
	draw_arc(center, _radius + 12.0, 0, TAU, 48, Color(1, 1, 1, 0.16), 2.0)
	draw_circle(center, 7.0, Color(1, 1, 1, 0.12))
	var knob_pos := center + _knob
	draw_circle(knob_pos, _radius * 0.42, Color(0.96, 0.82, 0.53, 0.24))
	draw_arc(knob_pos, _radius * 0.42, 0, TAU, 40, Color(0.96, 0.82, 0.53, 0.85), 2.0)
