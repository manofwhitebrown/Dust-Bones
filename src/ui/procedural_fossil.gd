class_name ProceduralFossil
extends Control
## Deterministic placeholder fossil from a specimen id hash, tinted by rarity.
## Built once in setup(); _draw() only replays cached shapes (no per-frame work).

enum Family { SPIRAL, SEGMENTED, FISH, FROND, TOOTH }

const OUTLINE_GROW: float = 0.012
const OUTLINE_DARKEN: float = 0.55
const DETAIL_DARKEN: float = 0.45
const DETAIL_WIDTH: float = 0.008
const STROKE_STEP: float = 0.7

var _blobs: PackedVector3Array = PackedVector3Array() # x, y (unit space), radius
var _lines: PackedVector2Array = PackedVector2Array() # pairs of points
var _fill: Color = Palette.BONE


func setup(specimen_id: String, rarity: String) -> void:
	_fill = Palette.rarity_color(rarity)
	_blobs.clear()
	_lines.clear()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = specimen_id.hash()
	match rng.randi() % Family.size():
		Family.SPIRAL:
			_build_spiral(rng)
		Family.SEGMENTED:
			_build_segmented(rng)
		Family.FISH:
			_build_fish(rng)
		Family.FROND:
			_build_frond(rng)
		_:
			_build_tooth(rng)
	queue_redraw()


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o: Vector2 = Vector2(size.x - s, size.y - s) * 0.5
	var outline: Color = _fill.darkened(OUTLINE_DARKEN)
	for b: Vector3 in _blobs:
		draw_circle(o + Vector2(b.x, b.y) * s, (b.z + OUTLINE_GROW) * s, outline)
	for b: Vector3 in _blobs:
		draw_circle(o + Vector2(b.x, b.y) * s, b.z * s, _fill)
	var detail: Color = _fill.darkened(DETAIL_DARKEN)
	for i in range(0, _lines.size() - 1, 2):
		draw_line(o + _lines[i] * s, o + _lines[i + 1] * s, detail, DETAIL_WIDTH * s, true)


func _stroke(a: Vector2, b: Vector2, r0: float, r1: float) -> void:
	var steps: int = maxi(ceili(a.distance_to(b) / (minf(r0, r1) * STROKE_STEP)), 1)
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var p: Vector2 = a.lerp(b, t)
		_blobs.append(Vector3(p.x, p.y, lerpf(r0, r1, t)))


func _build_spiral(rng: RandomNumberGenerator) -> void:
	var turns: float = rng.randf_range(2.2, 3.2)
	var rot: float = rng.randf() * TAU
	var steps: int = 90
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var ang: float = rot + t * turns * TAU
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var p: Vector2 = Vector2(0.5, 0.5) + dir * (0.03 + 0.33 * t)
		var br: float = 0.02 + 0.07 * t
		_blobs.append(Vector3(p.x, p.y, br))
		if i % 4 == 0 and i > 0:
			_lines.append(p - dir * br)
			_lines.append(p + dir * br)


func _build_segmented(rng: RandomNumberGenerator) -> void:
	var n: int = rng.randi_range(7, 10)
	for a in range(0, 13):
		var ang: float = PI + PI * float(a) / 12.0
		_blobs.append(Vector3(0.5 + cos(ang) * 0.2, 0.32 + sin(ang) * 0.17, 0.05))
	for i in n:
		var t: float = float(i) / float(n - 1)
		var y: float = 0.34 + 0.46 * t
		var w: float = 0.2 * (1.0 - 0.55 * t)
		for k in range(-2, 3):
			_blobs.append(Vector3(0.5 + w * float(k) / 2.0, y, 0.045 * (1.0 - 0.3 * t)))
		_lines.append(Vector2(0.5 - w, y + 0.035))
		_lines.append(Vector2(0.5 + w, y + 0.035))
	_lines.append(Vector2(0.5, 0.3))
	_lines.append(Vector2(0.5, 0.82))


func _build_fish(rng: RandomNumberGenerator) -> void:
	var bend: float = rng.randf_range(-0.06, 0.06)
	var ribs: int = rng.randi_range(6, 9)
	_blobs.append(Vector3(0.24, 0.5, 0.1))
	_stroke(Vector2(0.28, 0.5), Vector2(0.78, 0.5 + bend), 0.022, 0.012)
	for i in ribs:
		var t: float = float(i) / float(ribs - 1)
		var x: float = 0.34 + 0.34 * t
		var y: float = 0.5 + bend * t
		var h: float = 0.17 * (1.0 - 0.6 * t)
		_stroke(Vector2(x, y), Vector2(x - 0.04, y - h), 0.014, 0.006)
		_stroke(Vector2(x, y), Vector2(x - 0.04, y + h), 0.014, 0.006)
	_stroke(Vector2(0.78, 0.5 + bend), Vector2(0.93, 0.36), 0.016, 0.008)
	_stroke(Vector2(0.78, 0.5 + bend), Vector2(0.93, 0.64), 0.016, 0.008)
	_lines.append(Vector2(0.21, 0.47))
	_lines.append(Vector2(0.23, 0.47))


func _build_frond(rng: RandomNumberGenerator) -> void:
	var lean: float = rng.randf_range(-0.14, 0.14)
	var top: Vector2 = Vector2(0.5 + lean, 0.1)
	var base: Vector2 = Vector2(0.5, 0.92)
	_stroke(base, top, 0.022, 0.008)
	var pairs: int = rng.randi_range(7, 10)
	for i in pairs:
		var t: float = 0.12 + 0.8 * float(i) / float(pairs - 1)
		var p: Vector2 = base.lerp(top, t)
		var len: float = 0.26 * (1.0 - t) + 0.07
		for side in [-1.0, 1.0]:
			var tip: Vector2 = p + Vector2(side * len, -len * 0.55)
			_stroke(p, tip, 0.017, 0.004)


func _build_tooth(rng: RandomNumberGenerator) -> void:
	if rng.randi() % 2 == 0:
		var s: float = rng.randf_range(-0.1, 0.1)
		_stroke(Vector2(0.5, 0.58), Vector2(0.5 + s, 0.1), 0.15, 0.012)
		_stroke(Vector2(0.43, 0.58), Vector2(0.4, 0.9), 0.04, 0.02)
		_stroke(Vector2(0.57, 0.58), Vector2(0.61, 0.9), 0.04, 0.02)
	else:
		var flip: float = 1.0 if rng.randi() % 2 == 0 else -1.0
		var steps: int = 40
		for i in steps + 1:
			var t: float = float(i) / float(steps)
			var ang: float = lerpf(0.0, PI * 0.62, t)
			var p: Vector2 = Vector2(0.5 - flip * 0.3 + flip * cos(ang) * 0.3, 0.82 - sin(ang) * 0.62)
			_blobs.append(Vector3(p.x, p.y, lerpf(0.075, 0.008, t)))
