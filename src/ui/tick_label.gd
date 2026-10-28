class_name TickLabel
extends Label
## Number label that eases toward its target but always ends exactly on it.
## Processes only while animating; set_value() is O(1) so event storms are cheap.

const TICK_TIME: float = 0.45
const CATCH_RATE: float = 14.0

@export var prefix: String = ""
@export var suffix: String = ""

var _shown: float = 0.0
var _target: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	set_process(false)
	_refresh()


func set_value(value: float, instant: bool = false) -> void:
	_target = value
	if instant or not is_visible_in_tree():
		_shown = value
		_refresh()
		set_process(false)
		return
	_age = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _age >= TICK_TIME:
		_shown = _target
		set_process(false)
	else:
		_shown = lerpf(_shown, _target, 1.0 - exp(-CATCH_RATE * delta))
	_refresh()


func _refresh() -> void:
	var t: String = prefix + NumFormat.fmt(_shown) + suffix
	if t != text:
		text = t
