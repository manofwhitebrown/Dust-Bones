class_name HoldButton
extends Button
## Press-and-hold confirmation. Emits `confirmed` once per hold; releasing early cancels.

signal confirmed

const HOLD_SECONDS: float = 1.2
const FILL_COLOR: Color = Color(0.949, 0.722, 0.294, 0.55)

var _held: float = 0.0
var _holding: bool = false
var _fired: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	set_process(false)


func _on_down() -> void:
	_holding = true
	_fired = false
	_held = 0.0
	set_process(true)


func _on_up() -> void:
	_holding = false
	_held = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not _holding or _fired:
		return
	_held += delta
	queue_redraw()
	if _held >= HOLD_SECONDS:
		_fired = true
		set_process(false)
		confirmed.emit()


func _draw() -> void:
	if _held > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(_held / HOLD_SECONDS, 0.0, 1.0), size.y)), FILL_COLOR)
