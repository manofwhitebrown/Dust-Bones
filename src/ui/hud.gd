class_name Hud
extends PanelContainer
## Coins, income/sec and (when > 0) fieldwork. Signal-driven; never polls.

const BASE_MARGIN_TOP: float = 20.0
const FLASH_COLOR: Color = Color("#C0643C")
const FLASH_TIME: float = 0.5

var _flash_tween: Tween

@onready var _margin: MarginContainer = $Margin
@onready var _coins: TickLabel = $Margin/Row/Left/CoinsRow/Coins
@onready var _coin_icon: Control = $Margin/Row/Left/CoinsRow/CoinIcon
@onready var _income: TickLabel = $Margin/Row/Left/Income
@onready var _field_row: Control = $Margin/Row/FieldRow
@onready var _field: TickLabel = $Margin/Row/FieldRow/Fieldwork


func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency)
	EventBus.income_changed.connect(_on_income)
	EventBus.item_purchased.connect(_on_item_purchased)
	_on_currency("coins", GameState.get_balance("coins"), true)
	_on_currency("fieldwork", GameState.get_balance("fieldwork"), true)
	_income.set_value(GameState.get_income_per_sec(), true)


func set_top_inset(px: float) -> void:
	_margin.add_theme_constant_override("margin_top", int(BASE_MARGIN_TOP + px))


func get_coin_anchor() -> Vector2:
	return _coin_icon.global_position + _coin_icon.size * 0.5


func _on_currency(currency: String, amount: float, instant: bool = false) -> void:
	if currency == "coins":
		_coins.set_value(amount, instant)
	elif currency == "fieldwork":
		_field_row.visible = amount > 0.0
		_field.set_value(amount, instant)


func _on_income(per_second: float) -> void:
	_income.set_value(per_second)


func _on_item_purchased(_item_id: String, _count: int) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_income.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_income, "modulate", Color.WHITE, FLASH_TIME)
