class_name FxShape
extends Control
## Cached glow ring or radiant rays; animated by scaling/rotating/fading the node.

enum Kind { RING, RAYS }

const RING_WIDTH: float = 16.0
const RAY_COUNT: int = 14
const RAY_FILL: float = 0.4
const RAY_ALPHA: float = 0.55

@export var kind: Kind = Kind.RING
var color: Color = Palette.ACCENT:
	set(value):
		color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = size.x * 0.5
	if kind == Kind.RING:
		draw_arc(c, r - RING_WIDTH, 0.0, TAU, 64, color, RING_WIDTH, true)
		return
	var step: float = TAU / float(RAY_COUNT)
	var cols: PackedColorArray = PackedColorArray([
		Color(color, RAY_ALPHA), Color(color, 0.0), Color(color, 0.0)])
	for i in RAY_COUNT:
		var a0: float = float(i) * step
		var a1: float = a0 + step * RAY_FILL
		draw_polygon(PackedVector2Array([
			c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), cols)
