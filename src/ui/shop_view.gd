class_name ShopView
extends Control
## Brushes / Diggers / Upgrades. Rows come straight from GameState.get_shop_items(); nodes are reused.

const ROW_SCENE: PackedScene = preload("res://scenes/shop_row.tscn")
const CATEGORIES: Array[Array] = [["brush", "Brushes"], ["digger", "Diggers"], ["upgrade", "Upgrades"]]
const MODES: Array[Array] = [[1, "x1"], [10, "x10"], [100, "x100"], [-1, "Max"]]
const REFRESH_THROTTLE: float = 0.2
const BUTTON_H: float = 120.0
const SCROLL_DEADZONE: int = 24

var _cat: String = "brush"
var _mode: int = 1
var _lists: Dictionary = {} # category -> VBoxContainer
var _rows: Dictionary = {} # category -> {item_id -> ShopRow}
var _stale: Dictionary = {}
var _tab_buttons: Dictionary = {}

@onready var _tabs: HBoxContainer = $VBox/Tabs
@onready var _modes: HBoxContainer = $VBox/Modes
@onready var _scroll: ScrollContainer = $VBox/Scroll
@onready var _host: Control = $VBox/Scroll/Lists
@onready var _timer: Timer = $RefreshTimer


func _ready() -> void:
	_scroll.scroll_deadzone = SCROLL_DEADZONE
	var tab_group: ButtonGroup = ButtonGroup.new()
	for entry: Array in CATEGORIES:
		var cat: String = entry[0]
		var b: Button = _toggle(String(entry[1]), tab_group)
		b.pressed.connect(_select_category.bind(cat))
		_tabs.add_child(b)
		_tab_buttons[cat] = b
		var list: VBoxContainer = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 16)
		list.visible = false
		_host.add_child(list)
		_lists[cat] = list
		_rows[cat] = {}
		_stale[cat] = true
	(_tab_buttons["brush"] as Button).button_pressed = true
	var mode_group: ButtonGroup = ButtonGroup.new()
	for entry: Array in MODES:
		var b: Button = _toggle(String(entry[1]), mode_group)
		b.pressed.connect(_select_mode.bind(int(entry[0])))
		_modes.add_child(b)
		if int(entry[0]) == 1:
			b.button_pressed = true
	_timer.one_shot = true
	_timer.wait_time = REFRESH_THROTTLE
	_timer.timeout.connect(_on_timer)
	EventBus.item_purchased.connect(_on_purchased)
	EventBus.currency_changed.connect(_on_currency)
	EventBus.site_changed.connect(func(_s: Dictionary) -> void: _mark_all_stale())
	EventBus.prestige_done.connect(func(_i: Dictionary) -> void: _mark_all_stale())
	visibility_changed.connect(_on_visibility)
	_select_category(_cat)


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(0.0, BUTTON_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	return b


func _select_category(cat: String) -> void:
	_cat = cat
	for c: String in _lists:
		(_lists[c] as Control).visible = c == cat
	_scroll.scroll_vertical = 0
	_stale[cat] = true
	_refresh_current()


func _select_mode(mode: int) -> void:
	_mode = mode
	Sfx.play(&"ui_tap")
	_mark_all_stale()
	_refresh_current()


func _mark_all_stale() -> void:
	for c: String in _stale:
		_stale[c] = true
	if is_visible_in_tree() and _timer.is_stopped():
		_timer.start()


func _on_purchased(_id: String, _count: int) -> void:
	_mark_all_stale()


func _on_currency(currency: String, _amount: float) -> void:
	if currency == "coins":
		_mark_all_stale()


func _on_timer() -> void:
	if is_visible_in_tree():
		_refresh_current()


func _on_visibility() -> void:
	if is_visible_in_tree():
		_refresh_current()


func _refresh_current() -> void:
	if not is_visible_in_tree() or not bool(_stale[_cat]):
		return
	_stale[_cat] = false
	var items: Array[Dictionary] = GameState.get_shop_items(_cat)
	var balance: float = GameState.get_balance("coins")
	var rows: Dictionary = _rows[_cat]
	var seen: Dictionary = {}
	for i in items.size():
		var item: Dictionary = items[i]
		var id: String = String(item["id"])
		var row: ShopRow = rows.get(id)
		if row == null:
			row = ROW_SCENE.instantiate() as ShopRow
			row.buy_pressed.connect(_on_buy.bind(row))
			(_lists[_cat] as VBoxContainer).add_child(row)
			rows[id] = row
		(_lists[_cat] as VBoxContainer).move_child(row, i)
		row.visible = true
		row.bind(item, _mode, balance)
		seen[id] = true
	for id: String in rows:
		if not seen.has(id):
			(rows[id] as ShopRow).visible = false


func _on_buy(item_id: String, row: ShopRow) -> void:
	if GameState.buy(item_id, row.buy_qty(_mode)):
		row.play_bought()
		Sfx.play(&"buy")
		Haptics.pulse(15)
	_stale[_cat] = true
	_refresh_current()
