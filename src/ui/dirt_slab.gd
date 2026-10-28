class_name DirtSlab
extends Control
## One brushable slab: rock + specimen art under a dirt overlay driven by an R8 mask.
## Progress is tracked incrementally on a coarse grid; work only happens on touched pixels.

signal touched
signal progress_reported(slab_id: int, fraction: float)
signal reveal_popped
signal stroke_moved(speed: float)
signal stroke_ended

const MASK_SIZE: int = 256
const CELL_SHIFT: int = 3 # 8x8 mask px per progress cell -> 32x32 grid
const CELLS_PER_ROW: int = 32
const CELL_COUNT: int = CELLS_PER_ROW * CELLS_PER_ROW
const CLEAR_CUT: int = 80 # mask value at/below which a pixel counts as cleared
const CELL_CLEAR_PX: int = 32 # cleared pixels (of 64) for a cell to count as cleared
const BASE_RADIUS_PX: float = 24.0 # mask px at brush power 1.0
const ERASE_PER_STAMP: float = 0.45 # fraction of full dirt removed at the stamp center
const STAMP_SPACING: float = 0.5 # stamp spacing as a fraction of radius
const MIN_HARDNESS: float = 0.1
const REPORT_STEP: float = 0.01
const REPORT_INTERVAL_MSEC: int = 100
const SWEEP_TIME: float = 0.45
const POP_UP_TIME: float = 0.12
const POP_SETTLE_TIME: float = 0.2
const POP_SCALE: float = 1.12
const ROCK_DARKEN: float = 0.55
const SPECIMEN_DIR: String = "res://assets/sprites/specimens/"

var slab_id: int = -1

var _hardness: float = 1.0
var _power: float = 1.0
var _mask: PackedByteArray = PackedByteArray()
var _cell_px: PackedInt32Array = PackedInt32Array()
var _kernel: PackedInt32Array = PackedInt32Array()
var _kernel_r: int = 2
var _kernel_dim: int = 5
var _cleared: int = 0
var _dirty: bool = false
var _force_report: bool = false
var _last_reported: float = 0.0
var _last_report_msec: int = 0
var _touch: int = -1
var _last_pos: Vector2 = Vector2.ZERO
var _carry: float = 0.0
var _last_event_usec: int = 0
var _input_on: bool = false
var _image: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _tween: Tween

@onready var _rock: Panel = $Rock
@onready var _art: Control = $Art
@onready var _fossil: ProceduralFossil = $Art/Fossil
@onready var _photo: TextureRect = $Art/Photo
@onready var _dirt: ColorRect = $Dirt


func _ready() -> void:
	_mask.resize(MASK_SIZE * MASK_SIZE)
	_mask.fill(255)
	_cell_px.resize(CELL_COUNT)
	_image = Image.create_from_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8, _mask)
	_tex = ImageTexture.create_from_image(_image)
	_mat = _dirt.material as ShaderMaterial
	_mat.set_shader_parameter("mask", _tex)
	_art.resized.connect(_on_art_resized)
	_on_art_resized()
	set_process(false)


func setup(slab: Dictionary, brush_power: float) -> void:
	slab_id = int(slab.get("id", -1))
	_hardness = float(slab.get("hardness", 1.0))
	_power = maxf(brush_power, 0.1)
	var tint: Color = Color.from_string(String(slab.get("rock_tint", "")), Palette.DEFAULT_ROCK_TINT)
	_mat.set_shader_parameter("rock_tint", tint)
	_mat.set_shader_parameter("sweep", 0.0)
	(_rock.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = tint.darkened(ROCK_DARKEN)
	_load_art(String(slab.get("specimen_id", "")), String(slab.get("rarity", "common")))
	if _tween != null:
		_tween.kill()
	_art.scale = Vector2.ONE
	_mask.fill(255)
	_cell_px.fill(0)
	_cleared = 0
	_last_reported = 0.0
	_force_report = false
	_dirty = false
	_touch = -1
	_carry = 0.0
	_rebuild_kernel()
	_upload()
	_input_on = true
	set_process(false)


func set_brush_power(power: float) -> void:
	_power = maxf(power, 0.1)
	_rebuild_kernel()


func set_input_enabled(on: bool) -> void:
	_input_on = on
	if not on:
		cancel_touch()


func cancel_touch() -> void:
	if _touch != -1:
		_touch = -1
		stroke_ended.emit()
		_force_report = true
		set_process(true)


func get_fraction() -> float:
	return float(_cleared) / float(CELL_COUNT)


## Quick sweep of the remaining dirt, then the fossil pops (scale overshoot).
func finish_reveal() -> void:
	_input_on = false
	_touch = -1
	set_process(false)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_mat, "shader_parameter/sweep", 1.0, SWEEP_TIME)
	_tween.tween_property(_art, "scale", Vector2.ONE * POP_SCALE, POP_UP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_art, "scale", Vector2.ONE, POP_SETTLE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(reveal_popped.emit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_touch()


func _gui_input(event: InputEvent) -> void:
	if not _input_on:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			if _touch == -1:
				_touch = t.index
				_last_pos = t.position
				_carry = 0.0
				_last_event_usec = Time.get_ticks_usec()
				touched.emit()
				_stamp(t.position * _px_scale())
		elif t.index == _touch:
			cancel_touch()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _touch:
			_stroke_to(d.position)


func _px_scale() -> float:
	return float(MASK_SIZE) / maxf(size.x, 1.0)


# Interpolate stamps along the segment so fast swipes leave no gaps.
func _stroke_to(pos: Vector2) -> void:
	var k: float = _px_scale()
	var a: Vector2 = _last_pos * k
	var b: Vector2 = pos * k
	var seg: float = a.distance_to(b)
	_last_pos = pos
	var now: int = Time.get_ticks_usec()
	var dt: float = maxf(float(now - _last_event_usec) / 1000000.0, 0.004)
	_last_event_usec = now
	if seg <= 0.0:
		return
	stroke_moved.emit(seg / k / dt)
	var spacing: float = maxf(float(_kernel_r) * STAMP_SPACING, 1.0)
	var dir: Vector2 = (b - a) / seg
	var dist: float = spacing - _carry
	while dist <= seg:
		_stamp(a + dir * dist)
		dist += spacing
	_carry = seg - (dist - spacing)


func _stamp(c: Vector2) -> void:
	var cx: int = roundi(c.x)
	var cy: int = roundi(c.y)
	var x0: int = maxi(cx - _kernel_r, 0)
	var x1: int = mini(cx + _kernel_r, MASK_SIZE - 1)
	var y0: int = maxi(cy - _kernel_r, 0)
	var y1: int = mini(cy + _kernel_r, MASK_SIZE - 1)
	for y in range(y0, y1 + 1):
		var krow: int = (y - cy + _kernel_r) * _kernel_dim - cx + _kernel_r
		var mrow: int = y * MASK_SIZE
		var cell_row: int = (y >> CELL_SHIFT) * CELLS_PER_ROW
		for x in range(x0, x1 + 1):
			var k: int = _kernel[krow + x]
			if k == 0:
				continue
			var idx: int = mrow + x
			var old: int = _mask[idx]
			if old == 0:
				continue
			var nv: int = maxi(old - k, 0)
			_mask[idx] = nv
			if old > CLEAR_CUT and nv <= CLEAR_CUT:
				var cell: int = cell_row + (x >> CELL_SHIFT)
				var n: int = _cell_px[cell] + 1
				_cell_px[cell] = n
				if n == CELL_CLEAR_PX:
					_cleared += 1
	_dirty = true
	set_process(true)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_upload()
	var frac: float = get_fraction()
	var now: int = Time.get_ticks_msec()
	if frac > _last_reported and (_force_report or frac - _last_reported >= REPORT_STEP \
			or now - _last_report_msec >= REPORT_INTERVAL_MSEC):
		_last_reported = frac
		_last_report_msec = now
		_force_report = false
		progress_reported.emit(slab_id, frac)
		return
	if not _dirty and frac <= _last_reported:
		_force_report = false
		set_process(false)


func _upload() -> void:
	_image.set_data(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8, _mask)
	_tex.update(_image)


func _rebuild_kernel() -> void:
	_kernel_r = maxi(ceili(BASE_RADIUS_PX * _power), 2)
	_kernel_dim = _kernel_r * 2 + 1
	_kernel.resize(_kernel_dim * _kernel_dim)
	var amount: float = ERASE_PER_STAMP * 255.0 / maxf(_hardness, MIN_HARDNESS)
	var r: float = float(_kernel_r)
	for y in _kernel_dim:
		for x in _kernel_dim:
			var d: float = Vector2(x - _kernel_r, y - _kernel_r).length() / r
			var f: float = clampf(1.0 - d, 0.0, 1.0)
			_kernel[y * _kernel_dim + x] = int(f * f * (3.0 - 2.0 * f) * amount)


func _load_art(specimen_id: String, rarity: String) -> void:
	var path: String = SPECIMEN_DIR + specimen_id + ".png"
	if ResourceLoader.exists(path):
		_photo.texture = load(path) as Texture2D
		_photo.visible = true
		_fossil.visible = false
	else:
		_photo.visible = false
		_fossil.visible = true
		_fossil.setup(specimen_id, rarity)


func _on_art_resized() -> void:
	_art.pivot_offset = _art.size * 0.5
