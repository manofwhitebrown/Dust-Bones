class_name NavBar
extends PanelContainer
## Bottom tabs: Dig / Shop / Museum / Prestige (+ glow dot, + pulse for new finds).

signal tab_selected(tab: StringName)

const TABS: Array[StringName] = [&"dig", &"shop", &"museum", &"prestige"]
const LABELS: Dictionary = {&"dig": "Dig", &"shop": "Shop", &"museum": "Museum", &"prestige": "Prestige"}
const BUTTON_H: float = 132.0 # >= 48 dp at typical phone density
const BASE_MARGIN_BOTTOM: float = 16.0
const DOT_SIZE: float = 26.0
const PULSE_SCALE: float = 1.18

var _buttons: Dictionary = {}
var _dot: Panel
var _dot_tween: Tween

@onready var _margin: MarginContainer = $Margin
@onready var _row: HBoxContainer = $Margin/Row


func _ready() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for tab: StringName in TABS:
		var b: Button = Button.new()
		b.text = String(LABELS[tab])
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"NavButton"
		b.custom_minimum_size = Vector2(0.0, BUTTON_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			Sfx.play(&"ui_tap")
			tab_selected.emit(tab))
		_row.add_child(b)
		_buttons[tab] = b
	(_buttons[&"dig"] as Button).button_pressed = true
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.ACCENT
	style.set_corner_radius_all(int(DOT_SIZE))
	_dot = Panel.new()
	_dot.size = Vector2.ONE * DOT_SIZE
	_dot.pivot_offset = _dot.size * 0.5
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.add_theme_stylebox_override("panel", style)
	_dot.visible = false
	var pb: Button = _buttons[&"prestige"]
	pb.add_child(_dot)
	pb.resized.connect(func() -> void: _dot.position = Vector2(pb.size.x * 0.5 + 70.0, 16.0))


func set_bottom_inset(px: float) -> void:
	_margin.add_theme_constant_override("margin_bottom", int(BASE_MARGIN_BOTTOM + px))


func select(tab: StringName) -> void:
	(_buttons[tab] as Button).button_pressed = true
	tab_selected.emit(tab)


func set_prestige_dot(on: bool) -> void:
	if _dot_tween != null:
		_dot_tween.kill()
		_dot_tween = null
	_dot.visible = on
	_dot.scale = Vector2.ONE
	if on:
		_dot_tween = create_tween().set_loops()
		_dot_tween.tween_property(_dot, "scale", Vector2.ONE * PULSE_SCALE, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_dot_tween.tween_property(_dot, "scale", Vector2.ONE, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func pulse(tab: StringName) -> void:
	var b: Button = _buttons[tab]
	b.pivot_offset = b.size * 0.5
	var tw: Tween = create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * PULSE_SCALE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_tab_rect(tab: StringName) -> Rect2:
	return (_buttons[tab] as Button).get_global_rect()
