class_name Juice
extends Control
## Rarity-scaled reveal payoff. Hooks DigView signals; pooled nodes + CPU particles only.
## Sound hooks come with the audio manager (B8); haptics are wired here.

signal museum_pulse

const FX: Dictionary = {
	"common": {"puff": 10, "bright": 0.0, "coins": 3, "ring": false, "rays": false, "flash": 0.0,
			"shower": 0, "shake": 0.0, "shake_time": 0.0, "haptic": [12], "slowmo": 0.0, "beat": 0.9},
	"uncommon": {"puff": 18, "bright": 0.3, "coins": 5, "ring": false, "rays": false, "flash": 0.0,
			"shower": 0, "shake": 0.0, "shake_time": 0.0, "haptic": [20], "slowmo": 0.0, "beat": 1.0},
	"rare": {"puff": 26, "bright": 0.2, "coins": 7, "ring": true, "rays": false, "flash": 0.0,
			"shower": 0, "shake": 6.0, "shake_time": 0.25, "haptic": [40], "slowmo": 0.0, "beat": 1.2},
	"epic": {"puff": 48, "bright": 0.2, "coins": 10, "ring": true, "rays": false, "flash": 0.4,
			"shower": 0, "shake": 10.0, "shake_time": 0.35, "haptic": [70, -40, 70], "slowmo": 0.0, "beat": 1.5},
	"legendary": {"puff": 48, "bright": 0.3, "coins": 14, "ring": true, "rays": true, "flash": 0.5,
			"shower": 80, "shake": 14.0, "shake_time": 0.5, "haptic": [60, -50, 60, -50, 220],
			"slowmo": 0.4, "beat": 2.4},
}
const PUFF_MAX: int = 48
const PUFF_POOL: int = 3
const SHOWER_MAX: int = 80
const COIN_POOL: int = 14
const COIN_SIZE: float = 28.0
const COIN_FLY_TIME: float = 0.55
const COIN_STAGGER: float = 0.05
const SLOWMO_SCALE: float = 0.3
const CARD_GAP: float = 28.0
const CARD_FADE: float = 0.25
const RING_START: float = 0.3
const RING_END: float = 1.5
const RAYS_SPIN: float = 0.5 # radians per second of node time
const RAYS_FADE_IN: float = 0.25
const RAYS_HOLD: float = 1.4

var coin_target_global: Vector2 = Vector2(540.0, 90.0) # HUD sets this to its coin counter

var _dig: DigView
var _puffs: Array[CPUParticles2D] = []
var _puff_i: int = 0
var _shower: CPUParticles2D
var _coins: Array[Panel] = []
var _coin_i: int = 0
var _fade: Gradient
var _card_tween: Tween
var _shake_tween: Tween
var _flash_tween: Tween
var _ring_tween: Tween
var _rays_tween: Tween
var _badge_tween: Tween

@onready var _flash: ColorRect = $Flash
@onready var _rays: FxShape = $Rays
@onready var _ring: FxShape = $Ring
@onready var _card: VBoxContainer = $Card
@onready var _name: Label = $Card/Name
@onready var _info: Label = $Card/Info
@onready var _badge: Label = $Badge


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade = Gradient.new()
	_fade.set_color(0, Color.WHITE)
	_fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	for i in PUFF_POOL:
		_puffs.append(_make_particles(PUFF_MAX))
	_shower = _make_particles(SHOWER_MAX)
	var coin_style: StyleBoxFlat = StyleBoxFlat.new()
	coin_style.bg_color = Palette.ACCENT
	coin_style.set_corner_radius_all(int(COIN_SIZE))
	coin_style.border_color = Palette.UMBER
	coin_style.set_border_width_all(3)
	for i in COIN_POOL:
		var p: Panel = Panel.new()
		p.size = Vector2.ONE * COIN_SIZE
		p.pivot_offset = p.size * 0.5
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", coin_style)
		p.visible = false
		add_child(p)
		_coins.append(p)
	for n: CanvasItem in [_flash, _rays, _ring, _card, _badge]:
		n.visible = false
	_dig = get_parent() as DigView
	if _dig != null:
		_dig.reveal_started.connect(_on_started)
		_dig.reveal_popped.connect(_on_popped)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _cfg(rarity: String) -> Dictionary:
	return FX.get(rarity, FX["common"])


func _on_started(result: Dictionary, _slab: DirtSlab) -> void:
	_dig.reveal_beat = float(_cfg(String(result.get("rarity", "common")))["beat"])


func _on_popped(result: Dictionary, slab: DirtSlab) -> void:
	var rarity: String = String(result.get("rarity", "common"))
	var cfg: Dictionary = _cfg(rarity)
	var col: Color = Palette.rarity_color(rarity)
	var center: Vector2 = slab.global_position - global_position + slab.size * 0.5
	Sfx.reveal(rarity)
	_burst(center, int(cfg["puff"]), col.lightened(float(cfg["bright"])))
	_show_card(result, slab, col)
	_fly_coins(center, int(cfg["coins"]))
	if bool(cfg["ring"]):
		_play_ring(center, col)
	if bool(cfg["rays"]):
		_play_rays(center, col)
	if float(cfg["flash"]) > 0.0:
		_play_flash(col, float(cfg["flash"]))
	if int(cfg["shower"]) > 0:
		_play_shower(col, int(cfg["shower"]))
	if float(cfg["shake"]) > 0.0:
		_play_shake(float(cfg["shake"]), float(cfg["shake_time"]))
	if float(cfg["slowmo"]) > 0.0:
		_play_slowmo(float(cfg["slowmo"]))
	if bool(result.get("is_new", false)):
		_play_badge(slab)
		museum_pulse.emit()
	_play_haptics(cfg["haptic"])


func _make_particles(max_amount: int) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = max_amount
	p.one_shot = true
	p.emitting = false
	p.local_coords = false
	p.color_ramp = _fade
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	add_child(p)
	return p


func _burst(center: Vector2, count: int, col: Color) -> void:
	var p: CPUParticles2D = _puffs[_puff_i]
	_puff_i = (_puff_i + 1) % _puffs.size()
	p.position = center
	p.color = col
	p.amount = clampi(count, 1, PUFF_MAX)
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 160.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0.0, 500.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.restart()
	p.emitting = true


func _play_shower(col: Color, count: int) -> void:
	var p: CPUParticles2D = _shower
	p.position = Vector2(size.x * 0.5, -40.0)
	p.color = col
	p.amount = clampi(count, 1, SHOWER_MAX)
	p.explosiveness = 0.0
	p.lifetime = 1.8
	p.direction = Vector2.DOWN
	p.spread = 12.0
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 700.0
	p.gravity = Vector2(0.0, 600.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x * 0.5, 10.0)
	p.restart()
	p.emitting = true


func _show_card(result: Dictionary, slab: DirtSlab, col: Color) -> void:
	_name.text = String(result.get("name", ""))
	_info.text = "%s  +%s" % [String(result.get("rarity", "")).to_upper(),
			NumFormat.fmt(float(result.get("value", 0.0)))]
	_info.add_theme_color_override("font_color", col.darkened(0.35))
	_card.size = Vector2(slab.size.x, 0.0)
	_card.position = slab.global_position - global_position + Vector2(0.0, slab.size.y + CARD_GAP)
	_card.modulate.a = 0.0
	_card.visible = true
	if _card_tween != null:
		_card_tween.kill()
	var hold: float = maxf(_dig.reveal_beat - CARD_FADE * 2.0, 0.2)
	_card_tween = create_tween()
	_card_tween.tween_property(_card, "modulate:a", 1.0, CARD_FADE)
	_card_tween.tween_interval(hold)
	_card_tween.tween_property(_card, "modulate:a", 0.0, CARD_FADE)
	_card_tween.tween_callback(_card.hide)


func _play_badge(slab: DirtSlab) -> void:
	_badge.position = slab.global_position - global_position + Vector2(slab.size.x - 220.0, 24.0)
	_badge.pivot_offset = _badge.size * 0.5
	_badge.scale = Vector2.ZERO
	_badge.modulate.a = 1.0
	_badge.visible = true
	if _badge_tween != null:
		_badge_tween.kill()
	_badge_tween = create_tween()
	_badge_tween.tween_property(_badge, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_badge_tween.tween_interval(maxf(_dig.reveal_beat - 0.55, 0.1))
	_badge_tween.tween_property(_badge, "modulate:a", 0.0, CARD_FADE)
	_badge_tween.tween_callback(_badge.hide)


func _play_ring(center: Vector2, col: Color) -> void:
	_ring.color = col
	_ring.position = center - _ring.size * 0.5
	_ring.scale = Vector2.ONE * RING_START
	_ring.modulate.a = 1.0
	_ring.visible = true
	if _ring_tween != null:
		_ring_tween.kill()
	_ring_tween = create_tween().set_parallel(true)
	_ring_tween.tween_property(_ring, "scale", Vector2.ONE * RING_END, 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(_ring, "modulate:a", 0.0, 0.6)
	_ring_tween.chain().tween_callback(_ring.hide)


func _play_rays(center: Vector2, col: Color) -> void:
	_rays.color = col
	_rays.position = center - _rays.size * 0.5
	_rays.modulate.a = 0.0
	_rays.visible = true
	if _rays_tween != null:
		_rays_tween.kill()
	_rays_tween = create_tween()
	_rays_tween.set_parallel(true)
	_rays_tween.tween_property(_rays, "rotation", _rays.rotation + RAYS_SPIN * (RAYS_FADE_IN + RAYS_HOLD + 0.5), \
			RAYS_FADE_IN + RAYS_HOLD + 0.5)
	_rays_tween.tween_property(_rays, "modulate:a", 1.0, RAYS_FADE_IN)
	_rays_tween.chain().tween_interval(RAYS_HOLD)
	_rays_tween.chain().tween_property(_rays, "modulate:a", 0.0, 0.5)
	_rays_tween.chain().tween_callback(_rays.hide)


func _play_flash(col: Color, strength: float) -> void:
	_flash.color = col
	_flash.modulate.a = 0.0
	_flash.visible = true
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", strength, 0.06)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.45)
	_flash_tween.tween_callback(_flash.hide)


func _play_shake(amplitude: float, duration: float) -> void:
	if _dig == null:
		return
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_shake_step.bind(amplitude), 1.0, 0.0, duration)
	_shake_tween.tween_callback(func() -> void: _dig.position = Vector2.ZERO)


func _shake_step(v: float, amplitude: float) -> void:
	var t: float = float(Time.get_ticks_msec()) * 0.06
	_dig.position = Vector2(sin(t * 7.3), cos(t * 5.9)) * amplitude * v


func _fly_coins(center: Vector2, count: int) -> void:
	var target: Vector2 = coin_target_global - global_position - Vector2.ONE * COIN_SIZE * 0.5
	for i in mini(count, _coins.size()):
		var c: Panel = _coins[_coin_i]
		_coin_i = (_coin_i + 1) % _coins.size()
		var ang: float = float(i) * 2.399 # golden angle spread
		c.position = center - Vector2.ONE * COIN_SIZE * 0.5 + Vector2(cos(ang), sin(ang)) * 40.0
		c.scale = Vector2.ONE
		c.modulate.a = 1.0
		c.visible = true
		var tw: Tween = create_tween()
		tw.tween_interval(float(i) * COIN_STAGGER)
		tw.tween_property(c, "position", target, COIN_FLY_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector2.ONE * 0.5, COIN_FLY_TIME)
		tw.tween_callback(_coin_landed.bind(c))


## Coin shower for the offline "Collect" button (center is in global coordinates).
func play_collect(center_global: Vector2) -> void:
	_fly_coins(center_global - global_position, COIN_POOL)
	_play_shower(Palette.ACCENT, SHOWER_MAX)
	Haptics.pulse(30)


func _coin_landed(c: Panel) -> void:
	c.hide()
	Sfx.coin_tick()


func _play_slowmo(real_seconds: float) -> void:
	Engine.time_scale = SLOWMO_SCALE
	# process_always + ignore_time_scale so it ends on real time
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(
			func() -> void: Engine.time_scale = 1.0)


func _play_haptics(pattern: Array) -> void:
	for step: int in pattern:
		if step > 0:
			Haptics.pulse(step)
		else:
			await get_tree().create_timer(float(-step) / 1000.0, true, false, true).timeout
		if step > 0 and pattern.size() > 1:
			await get_tree().create_timer(float(step) / 1000.0, true, false, true).timeout
