class_name OfflinePopup
extends Control
## "While you were away..." card. One report at a time; Collect can only fire once per report.

signal collected(center_global: Vector2)

enum State { HIDDEN, SHOWN, CLAIMED }

const FADE: float = 0.25
const CLOSE_DELAY: float = 0.7

var _state: State = State.HIDDEN
var _queued: Dictionary = {}
var _dim: ColorRect
var _card: PanelContainer
var _time: Label
var _cap: Label
var _coins: Label
var _slabs: Label
var _finds: Label
var _collect: Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.color = Color(Palette.UMBER, 0.65)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(900.0, 0.0)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_card.add_child(box)
	var title: Label = Label.new()
	title.text = "While you were away..."
	title.theme_type_variation = &"Heading"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_time = _line(box, 38)
	_cap = _line(box, 30)
	_cap.add_theme_color_override("font_color", Palette.TERRACOTTA.darkened(0.2))
	_coins = _line(box, 64)
	_slabs = _line(box, 38)
	_finds = _line(box, 38)
	_collect = Button.new()
	_collect.text = "Collect"
	_collect.custom_minimum_size = Vector2(0.0, 144.0)
	_collect.add_theme_font_size_override("font_size", 52)
	_collect.pressed.connect(_on_collect)
	box.add_child(_collect)
	EventBus.offline_report_ready.connect(_on_report)


func is_open() -> bool:
	return _state != State.HIDDEN


func _line(parent: Control, size_px: int) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size_px)
	parent.add_child(l)
	return l


static func format_duration(seconds: float) -> String:
	var total_min: int = int(seconds / 60.0)
	if total_min < 1:
		return "less than a minute"
	var h: int = int(float(total_min) / 60.0)
	var m: int = total_min % 60
	if h == 0:
		return "%d min" % m
	return "%dh %02dm" % [h, m]


func _on_report(report: Dictionary) -> void:
	if _state == State.CLAIMED:
		_queued = report
		return
	_fill(report)
	if _state == State.HIDDEN:
		_state = State.SHOWN
		_collect.disabled = false
		modulate.a = 0.0
		visible = true
		create_tween().tween_property(self, "modulate:a", 1.0, FADE)


func _fill(report: Dictionary) -> void:
	_time.text = "You were gone for %s" % format_duration(float(report.get("seconds", 0.0)))
	_cap.text = "Your crew rested after hitting the offline limit." if bool(report.get("capped", false)) else ""
	_cap.visible = _cap.text != ""
	_coins.text = "+%s coins" % NumFormat.fmt(float(report.get("coins", 0.0)))
	var slabs: int = int(report.get("slabs", 0))
	_slabs.text = "%d slab%s dug" % [slabs, "" if slabs == 1 else "s"]
	var finds: int = (report.get("new_discoveries", []) as Array).size()
	_finds.text = "%d new discover%s!" % [finds, "y" if finds == 1 else "ies"] if finds > 0 else ""
	_finds.visible = finds > 0


func _on_collect() -> void:
	if _state != State.SHOWN:
		return
	_state = State.CLAIMED
	_collect.disabled = true
	GameState.claim_offline_report()
	Sfx.play(&"buy")
	collected.emit(_collect.get_global_rect().get_center())
	var tw: Tween = create_tween()
	tw.tween_interval(CLOSE_DELAY)
	tw.tween_property(self, "modulate:a", 0.0, FADE)
	tw.tween_callback(_finish)


func _finish() -> void:
	visible = false
	_state = State.HIDDEN
	if not _queued.is_empty():
		var next: Dictionary = _queued
		_queued = {}
		_on_report(next)
