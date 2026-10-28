extends Control
## App shell: HUD on top, tabs on the bottom, one view visible at a time.

const TAB_DIG: StringName = &"dig"
const MUSEUM_SCENE: PackedScene = preload("res://scenes/museum_view.tscn")
const SHOP_SCENE: PackedScene = preload("res://scenes/shop_view.tscn")

var _views: Dictionary = {} # tab -> Control (non-dig tabs live under $Views)

@onready var _dig: DigView = $DigView
@onready var _fx: Juice = $DigView/RevealFX
@onready var _view_host: Control = $Views
@onready var _hud: Hud = $HUD
@onready var _nav: NavBar = $NavBar


func _ready() -> void:
	_nav.tab_selected.connect(_show_tab)
	_hud.resized.connect(_update_view_rect)
	_nav.resized.connect(_update_view_rect)
	get_tree().root.size_changed.connect(_apply_insets)
	EventBus.prestige_available_changed.connect(_nav.set_prestige_dot)
	_nav.set_prestige_dot(bool(GameState.get_prestige_preview().get("can_prestige", false)))
	_fx.museum_pulse.connect(_nav.pulse.bind(&"museum"))
	_dig.reveal_started.connect(_on_reveal_started)
	register_view(&"shop", SHOP_SCENE.instantiate() as Control)
	register_view(&"museum", MUSEUM_SCENE.instantiate() as Control)
	register_view(&"prestige", PlaceholderView.new().setup("Prestige"))
	_apply_insets()
	_show_tab(TAB_DIG)


func register_view(tab: StringName, view: Control) -> void:
	if _views.has(tab):
		(_views[tab] as Control).queue_free()
	view.visible = false
	_view_host.add_child(view)
	_views[tab] = view


func _show_tab(tab: StringName) -> void:
	_dig.visible = tab == TAB_DIG
	_view_host.visible = tab != TAB_DIG
	for t: StringName in _views:
		(_views[t] as Control).visible = t == tab


func _on_reveal_started(_result: Dictionary, _slab: DirtSlab) -> void:
	_fx.coin_target_global = _hud.get_coin_anchor()


func _apply_insets() -> void:
	var ins: Vector4 = SafeArea.insets(get_viewport())
	_hud.set_top_inset(ins.y)
	_nav.set_bottom_inset(ins.w)


func _update_view_rect() -> void:
	_view_host.offset_top = _hud.size.y
	_view_host.offset_bottom = -_nav.size.y
