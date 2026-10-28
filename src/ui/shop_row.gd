class_name ShopRow
extends PanelContainer
## One reusable shop row. bind() only touches nodes whose value actually changed.

signal buy_pressed(item_id: String)

const DEBOUNCE_MSEC: int = 80
const FLASH_COLOR: Color = Color("#F2B84B")
const FLASH_TIME: float = 0.5
const SQUISH: float = 0.93
const LOCKED_ALPHA: float = 0.62
const ICON_DIR: String = "res://assets/icons/"
const CATEGORY_TINT: Dictionary = {
	"brush": Color("#C0643C"), "digger": Color("#7E8F52"), "upgrade": Color("#5E8DA6")}

var item_id: String = ""
var owned: int = 0
var max_owned: int = -1
var can_buy: bool = false

var _last_press_msec: int = -100000
var _tint_set: String = ""
var _flash_tween: Tween
var _press_tween: Tween

@onready var _icon_box: Panel = $Margin/Row/IconBox
@onready var _letter: Label = $Margin/Row/IconBox/Letter
@onready var _photo: TextureRect = $Margin/Row/IconBox/Photo
@onready var _name: Label = $Margin/Row/Info/Name
@onready var _effect: Label = $Margin/Row/Info/Effect
@onready var _note: Label = $Margin/Row/Info/Note
@onready var _button: Button = $Margin/Row/Buy


func _ready() -> void:
	_button.pressed.connect(_on_pressed)
	_button.pivot_offset = _button.size * 0.5
	_button.resized.connect(func() -> void: _button.pivot_offset = _button.size * 0.5)


## Quantity to pass to GameState.buy for the selected mode (-1 = max affordable).
func buy_qty(mode: int) -> int:
	if mode == -1:
		return -1
	if max_owned >= 0:
		return maxi(mini(mode, max_owned - owned), 1)
	return mode


func bind(item: Dictionary, mode: int, balance: float) -> void:
	item_id = String(item["id"])
	owned = int(item["owned"])
	max_owned = int(item["max_owned"])
	var locked: bool = bool(item["locked"])
	var maxed: bool = max_owned >= 0 and owned >= max_owned
	_set_text(_name, String(item["name"]))
	_set_text(_effect, String(item["effect_text"]))
	var owned_text: String = "Owned %d" % owned if max_owned < 0 else "Owned %d/%d" % [owned, max_owned]
	_set_text(_note, String(item["unlock_text"]) if locked else owned_text)
	_apply_icon(String(item["category"]), String(item["icon"]), String(item["name"]))
	var cost: float = float(item["cost"])
	if mode != 1 and not locked and not maxed:
		cost = GameState.get_buy_cost(item_id, buy_qty(mode))
	var btn_text: String = "MAX" if maxed else ("Locked" if locked else _cost_text(cost, mode))
	if _button.text != btn_text:
		_button.text = btn_text
	can_buy = not locked and not maxed and balance >= cost
	_button.disabled = not can_buy
	modulate.a = LOCKED_ALPHA if locked else 1.0


func play_bought() -> void:
	if _press_tween != null:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(_button, "scale", Vector2.ONE * SQUISH, 0.06)
	_press_tween.tween_property(_button, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _flash_tween != null:
		_flash_tween.kill()
	_effect.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_effect, "modulate", Color.WHITE, FLASH_TIME)


func _cost_text(cost: float, mode: int) -> String:
	var c: String = NumFormat.fmt(cost)
	return c if mode == 1 else ("Max  " if mode == -1 else "x%d  " % mode) + c


func _set_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value


func _apply_icon(category: String, icon: String, display_name: String) -> void:
	if _tint_set == icon:
		return
	_tint_set = icon
	var path: String = ICON_DIR + icon + ".png"
	if ResourceLoader.exists(path):
		_photo.texture = load(path) as Texture2D
		_photo.visible = true
		_letter.visible = false
		return
	_photo.visible = false
	_letter.visible = true
	_letter.text = display_name.substr(0, 1).to_upper()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CATEGORY_TINT.get(category, Palette.TERRACOTTA)
	style.set_corner_radius_all(24)
	_icon_box.add_theme_stylebox_override("panel", style)


func _on_pressed() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_press_msec < DEBOUNCE_MSEC or not can_buy:
		return
	_last_press_msec = now
	buy_pressed.emit(item_id)
