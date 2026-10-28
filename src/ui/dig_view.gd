class_name DigView
extends Control
## Dig screen: two pooled DirtSlabs (active + incoming) so slab swaps never leave a gap.
## All numbers come from GameState / EventBus; this node only presents and forwards touch progress.

signal reveal_started(result: Dictionary, slab: DirtSlab)
signal reveal_popped(result: Dictionary, slab: DirtSlab)

const SLAB_SIZE: float = 960.0
const SLIDE_TIME: float = 0.35
const REVEAL_BEAT: float = 0.9 # pause on the revealed fossil before the next slab
const HINT_IDLE_SEC: float = 5.0
const BACKDROP_FADE: float = 0.6
const HINT_KEY: String = "tut_brush"

var reveal_beat: float = REVEAL_BEAT

var _active: DirtSlab
var _spare: DirtSlab
var _home: Vector2 = Vector2.ZERO
var _busy: bool = false
var _first_slab_id: int = -1
var _hint_done: bool = SettingsStore.get_bool(HINT_KEY, false)
var _slab_tween: Tween
var _backdrop_tween: Tween

@onready var _backdrop: ColorRect = $Backdrop
@onready var _slab_a: DirtSlab = $SlabA
@onready var _slab_b: DirtSlab = $SlabB
@onready var _hint: BrushHint = $Hint
@onready var _hint_timer: Timer = $HintTimer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s: DirtSlab in [_slab_a, _slab_b]:
		s.size = Vector2.ONE * SLAB_SIZE
		s.visible = false
		s.touched.connect(_on_touched)
		s.progress_reported.connect(_on_progress_reported)
		s.stroke_moved.connect(Sfx.brush_move)
		s.stroke_ended.connect(Sfx.brush_stop)
	_active = _slab_a
	_spare = _slab_b
	resized.connect(_layout)
	_layout()
	EventBus.slab_revealed.connect(_on_slab_revealed)
	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.site_changed.connect(_on_site_changed)
	EventBus.prestige_done.connect(_on_prestige_done)
	_backdrop.color = _site_bg(GameState.get_current_site())
	_hint_timer.one_shot = true
	_hint_timer.wait_time = HINT_IDLE_SEC
	_hint_timer.timeout.connect(_show_hint)
	var data: Dictionary = GameState.start_new_slab()
	_first_slab_id = int(data.get("id", -1))
	_active.setup(data, GameState.get_brush_power())
	_active.position = _home
	_active.visible = true
	if not _hint_done:
		_hint_timer.start()


func get_active_slab() -> DirtSlab:
	return _active


func _layout() -> void:
	_home = (size - Vector2.ONE * SLAB_SIZE) * 0.5
	if not _busy and _active != null:
		_active.position = _home


func _site_bg(site: Dictionary) -> Color:
	return Color.from_string(String(site.get("bg_tint", "")), Palette.SAND)


func _on_site_changed(site: Dictionary) -> void:
	if _backdrop_tween != null:
		_backdrop_tween.kill()
	_backdrop_tween = create_tween()
	_backdrop_tween.tween_property(_backdrop, "color", _site_bg(site), BACKDROP_FADE)


func _on_touched() -> void:
	if not _hint_done:
		SettingsStore.set_bool(HINT_KEY, true)
	_hint_done = true
	_hint_timer.stop()
	_hint.stop()


func _show_hint() -> void:
	if _hint_done or _active.slab_id != _first_slab_id:
		return
	var origin: Vector2 = _active.position
	_hint.start(origin + Vector2(0.3, 0.4) * SLAB_SIZE, origin + Vector2(0.7, 0.55) * SLAB_SIZE)


func _on_progress_reported(slab_id: int, fraction: float) -> void:
	GameState.report_brush_progress(slab_id, fraction)


func _on_item_purchased(_item_id: String, _new_count: int) -> void:
	_active.set_brush_power(GameState.get_brush_power())


func _on_slab_revealed(result: Dictionary) -> void:
	if _busy or int(result.get("slab_id", -1)) != _active.slab_id:
		return
	_busy = true
	_active.reveal_popped.connect(_on_popped.bind(result), CONNECT_ONE_SHOT)
	_active.finish_reveal()
	reveal_started.emit(result, _active)


func _on_popped(result: Dictionary) -> void:
	reveal_popped.emit(result, _active)
	await get_tree().create_timer(reveal_beat).timeout
	_advance()


func _advance() -> void:
	var data: Dictionary = GameState.start_new_slab()
	var incoming: DirtSlab = _spare
	var outgoing: DirtSlab = _active
	incoming.setup(data, GameState.get_brush_power())
	incoming.set_input_enabled(false)
	incoming.position = Vector2(size.x, _home.y)
	incoming.visible = true
	if _slab_tween != null:
		_slab_tween.kill()
	_slab_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slab_tween.tween_property(incoming, "position", _home, SLIDE_TIME)
	_slab_tween.tween_property(outgoing, "position", Vector2(-SLAB_SIZE, _home.y), SLIDE_TIME)
	_slab_tween.chain().tween_callback(_on_slide_done.bind(incoming, outgoing))


func _on_slide_done(incoming: DirtSlab, outgoing: DirtSlab) -> void:
	outgoing.visible = false
	_active = incoming
	_spare = outgoing
	_active.set_input_enabled(true)
	_busy = false


func _on_prestige_done(_info: Dictionary) -> void:
	# Core reset everything: abandon any reveal in flight and start a clean slab in place.
	if _slab_tween != null:
		_slab_tween.kill()
	_busy = false
	_spare.visible = false
	var data: Dictionary = GameState.start_new_slab()
	_active.setup(data, GameState.get_brush_power())
	_active.position = _home
	_active.visible = true
