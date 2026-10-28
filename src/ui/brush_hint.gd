class_name BrushHint
extends Control
## Pulsing "brush here" finger shown once, on the very first slab, after idle.

const RADIUS: float = 52.0
const RING_WIDTH: float = 8.0
const SWIPE_TIME: float = 0.9
const PULSE_TIME: float = 0.6

var _tween: Tween
var _caption: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0
	size = custom_minimum_size
	pivot_offset = size * 0.5
	_caption = Label.new()
	_caption.text = "Swipe to brush!"
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_color", Palette.UMBER)
	_caption.add_theme_color_override("font_outline_color", Palette.BONE)
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.position = Vector2(-60.0, RADIUS * 2.0 + 8.0)
	add_child(_caption)
	visible = false


func _draw() -> void:
	var c: Vector2 = size * 0.5
	draw_circle(c, RADIUS, Color(Palette.ACCENT, 0.35))
	draw_arc(c, RADIUS, 0.0, TAU, 40, Palette.ACCENT, RING_WIDTH, true)


func start(from: Vector2, to: Vector2) -> void:
	stop()
	position = from - size * 0.5
	visible = true
	_tween = create_tween().set_parallel(true).set_loops()
	_tween.tween_property(self, "position", to - size * 0.5, SWIPE_TIME) \
			.from(from - size * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * 1.15, PULSE_TIME) \
			.from(Vector2.ONE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func stop() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	scale = Vector2.ONE
	visible = false
