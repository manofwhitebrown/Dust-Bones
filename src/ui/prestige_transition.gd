class_name PrestigeTransition
extends Control
## Short cinematic after a prestige: tint fade, site title card, then back to the dig screen.

signal covered # fully opaque: safe moment to swap screens underneath

const FADE_IN: float = 0.6
const HOLD: float = 1.6
const FADE_OUT: float = 0.7

var _running: bool = false
var _bg: ColorRect
var _title: Label
var _sub: Label
var _fieldwork: float = 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 40)
	_sub.add_theme_color_override("font_color", Palette.UMBER)
	box.add_child(_sub)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 120)
	_title.add_theme_color_override("font_color", Palette.UMBER)
	box.add_child(_title)
	EventBus.prestige_done.connect(_on_done)
	EventBus.site_changed.connect(_on_site)


func _on_done(info: Dictionary) -> void:
	if _running:
		return
	_running = true # guards against prestige_done + site_changed double-triggering
	_fieldwork = float(info.get("fieldwork_gained", 0.0))
	_apply_site(GameState.get_current_site())
	_sub.text = "+%s Fieldwork" % NumFormat.fmt(_fieldwork)
	Sfx.play(&"reveal_epic")
	Haptics.pulse(120)
	modulate.a = 0.0
	visible = true
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_IN)
	tw.tween_callback(covered.emit)
	tw.tween_interval(HOLD)
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(_finish)


func _on_site(site: Dictionary) -> void:
	if _running:
		_apply_site(site) # core may announce the new site just after prestige_done


func _apply_site(site: Dictionary) -> void:
	_title.text = String(site.get("name", ""))
	_bg.color = Color.from_string(String(site.get("bg_tint", "")), Palette.SAND)


func _finish() -> void:
	visible = false
	_running = false
