class_name Tutorial
extends Control
## Three one-shot hint bubbles (brush hint lives in DigView): hire a digger, open the museum.
## Each is shown once, persisted the moment it appears, and dismissed by doing the thing.

const KEY_DIGGER: String = "tut_digger"
const KEY_MUSEUM: String = "tut_museum"
const BUBBLE_GAP: float = 18.0
const BOB: float = 10.0
const AUTO_HIDE: float = 12.0

var _nav: NavBar
var _bubble: PanelContainer
var _label: Label
var _arrow: Polygon2D
var _target_tab: StringName = &""
var _bob_tween: Tween
var _hide_tween: Tween


func setup(nav: NavBar) -> void:
	_nav = nav
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bubble()
	_nav.tab_selected.connect(_on_tab)
	EventBus.currency_changed.connect(_on_currency)
	EventBus.specimen_discovered.connect(func(_id: String) -> void: _maybe_museum())
	EventBus.slab_revealed.connect(func(_r: Dictionary) -> void: _maybe_museum())


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.UMBER
	style.set_corner_radius_all(28)
	style.set_content_margin_all(24.0)
	_bubble.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Palette.BONE)
	_label.add_theme_font_size_override("font_size", 38)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_label)
	add_child(_bubble)
	_arrow = Polygon2D.new()
	_arrow.color = Palette.UMBER
	_arrow.polygon = PackedVector2Array([Vector2(-22.0, 0.0), Vector2(22.0, 0.0), Vector2(0.0, 26.0)])
	_arrow.visible = false
	add_child(_arrow)


func _on_currency(currency: String, _amount: float) -> void:
	if currency != "coins" or SettingsStore.get_bool(KEY_DIGGER, false) or _bubble.visible:
		return
	var items: Array[Dictionary] = GameState.get_shop_items("digger")
	if not items.is_empty() and bool(items[0]["affordable"]) and not bool(items[0]["locked"]) \
			and int(items[0]["owned"]) == 0:
		SettingsStore.set_bool(KEY_DIGGER, true)
		_show("Hire your first digger!", &"shop")


func _maybe_museum() -> void:
	if SettingsStore.get_bool(KEY_MUSEUM, false) or _bubble.visible:
		return
	SettingsStore.set_bool(KEY_MUSEUM, true)
	_show("You found something! See it in the Museum.", &"museum")


func _on_tab(tab: StringName) -> void:
	if tab == _target_tab:
		_hide()


func _show(text: String, tab: StringName) -> void:
	_target_tab = tab
	_label.text = text
	_bubble.custom_minimum_size = Vector2(620.0, 0.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.reset_size()
	var rect: Rect2 = _nav.get_tab_rect(tab)
	var x: float = clampf(rect.get_center().x - _bubble.size.x * 0.5, 24.0, size.x - _bubble.size.x - 24.0)
	var y: float = rect.position.y - _bubble.size.y - 26.0 - BUBBLE_GAP
	_bubble.position = Vector2(x, y)
	_arrow.position = Vector2(rect.get_center().x, y + _bubble.size.y)
	_bubble.modulate.a = 0.0
	_bubble.visible = true
	_arrow.visible = true
	if _bob_tween != null:
		_bob_tween.kill()
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(self, "position:y", -BOB, 0.6).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(self, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	create_tween().tween_property(_bubble, "modulate:a", 1.0, 0.25)
	if _hide_tween != null:
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_interval(AUTO_HIDE)
	_hide_tween.tween_callback(_hide)


func _hide() -> void:
	if _bob_tween != null:
		_bob_tween.kill()
	position = Vector2.ZERO
	_bubble.visible = false
	_arrow.visible = false
	_target_tab = &""
