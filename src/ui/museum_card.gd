class_name MuseumCard
extends Button
## Cheap specimen card: art is built lazily (ensure_art) when the card scrolls near the viewport.

const CARD_H: float = 400.0
const ART_MARGIN: float = 20.0
const BORDER: int = 6
const SILHOUETTE: Color = Color(0.1, 0.07, 0.06, 0.92)
const SHIMMER_PEAK: float = 0.55
const SHIMMER_HALF: float = 0.35
const SPECIMEN_DIR: String = "res://assets/sprites/specimens/"

var entry: Dictionary = {}
var art_built: bool = false

var _style: StyleBoxFlat
var _art: Control
var _fossil: ProceduralFossil
var _photo: TextureRect
var _name: Label
var _value: Label
var _glow: Panel
var _glow_tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(0.0, CARD_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_style = StyleBoxFlat.new()
	_style.bg_color = Palette.BONE
	_style.set_corner_radius_all(24)
	_style.set_border_width_all(BORDER)
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, _style)
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.offset_left = ART_MARGIN
	_art.offset_right = -ART_MARGIN
	_art.offset_top = ART_MARGIN
	_art.offset_bottom = -110.0
	add_child(_art)
	_name = _label(34, Palette.UMBER)
	_name.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name.offset_top = -104.0
	_name.offset_bottom = -52.0
	add_child(_name)
	_value = _label(28, Palette.TERRACOTTA.darkened(0.2))
	_value.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_value.offset_top = -56.0
	_value.offset_bottom = -12.0
	add_child(_value)
	var glow_style: StyleBoxFlat = StyleBoxFlat.new()
	glow_style.bg_color = Color(Palette.ACCENT, 0.6)
	glow_style.set_corner_radius_all(24)
	_glow = Panel.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.add_theme_stylebox_override("panel", glow_style)
	_glow.modulate.a = 0.0
	add_child(_glow)


func set_entry(e: Dictionary) -> void:
	var was_discovered: bool = bool(entry.get("discovered", false))
	entry = e
	var found: bool = bool(e.get("discovered", false))
	_name.text = String(e.get("name", "???")) if found else "???"
	_value.text = NumFormat.fmt(float(e.get("value", 0.0))) if found else ""
	_style.border_color = Palette.rarity_color(String(e.get("rarity", "common"))) if found \
			else Color(Palette.UMBER, 0.35)
	if art_built and found != was_discovered:
		_apply_tint()


func ensure_art() -> void:
	if art_built:
		return
	art_built = true
	var id: String = String(entry.get("id", ""))
	var path: String = SPECIMEN_DIR + id + ".png"
	if ResourceLoader.exists(path):
		_photo = TextureRect.new()
		_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_photo.texture = load(path) as Texture2D
		_art.add_child(_photo)
	else:
		_fossil = ProceduralFossil.new()
		_fossil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fossil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_art.add_child(_fossil)
		_fossil.setup(id, String(entry.get("rarity", "common")))
	_apply_tint()


func shimmer() -> void:
	if _glow_tween != null:
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops(2)
	_glow_tween.tween_property(_glow, "modulate:a", SHIMMER_PEAK, SHIMMER_HALF) \
			.set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_glow, "modulate:a", 0.0, SHIMMER_HALF).set_trans(Tween.TRANS_SINE)


func _apply_tint() -> void:
	_art.modulate = Color.WHITE if bool(entry.get("discovered", false)) else SILHOUETTE


func _label(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
