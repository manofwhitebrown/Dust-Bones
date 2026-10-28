class_name UiTheme
extends RefCounted
## Builds the one shared Theme (saved as dust_theme.tres by tools/assets_gen/make_theme.gd).

const FONT_SIZE: int = 40
const RADIUS: int = 28
const HEADING_SIZE: int = 64


static func build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = FONT_SIZE

	t.set_color("font_color", "Label", Palette.UMBER)
	t.set_type_variation(&"Heading", &"Label")
	t.set_font_size("font_size", "Heading", HEADING_SIZE)

	t.set_stylebox("panel", "PanelContainer", _box(Palette.BONE, RADIUS, 24.0))
	t.set_stylebox("panel", "Panel", _box(Palette.BONE, RADIUS, 0.0))

	t.set_type_variation(&"HudPanel", &"PanelContainer")
	t.set_stylebox("panel", "HudPanel", _box(Color(Palette.BONE, 0.94), 0, 0.0, 36))
	t.set_type_variation(&"NavPanel", &"PanelContainer")
	t.set_stylebox("panel", "NavPanel", _box(Color(Palette.BONE, 0.96), 0, 0.0, 0, 36))

	t.set_stylebox("normal", "Button", _box(Palette.TERRACOTTA, RADIUS, 28.0))
	t.set_stylebox("hover", "Button", _box(Palette.TERRACOTTA.lightened(0.1), RADIUS, 28.0))
	t.set_stylebox("pressed", "Button", _box(Palette.TERRACOTTA.darkened(0.15), RADIUS, 28.0))
	t.set_stylebox("disabled", "Button", _box(Color(Palette.UMBER, 0.25), RADIUS, 28.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", Palette.BONE)
	t.set_color("font_disabled_color", "Button", Color(Palette.BONE, 0.6))

	t.set_type_variation(&"NavButton", &"Button")
	var flat: StyleBoxFlat = _box(Color(Palette.SAND, 0.0), RADIUS, 12.0)
	var active: StyleBoxFlat = _box(Palette.SAND, RADIUS, 12.0)
	for s in ["normal", "hover", "disabled"]:
		t.set_stylebox(s, "NavButton", flat)
	t.set_stylebox("pressed", "NavButton", active)
	t.set_stylebox("hover_pressed", "NavButton", active)
	t.set_stylebox("focus", "NavButton", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "NavButton", Palette.UMBER.lightened(0.25))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "NavButton", Palette.TERRACOTTA.darkened(0.2))
	t.set_font_size("font_size", "NavButton", 38)
	return t


static func _box(color: Color, radius: int, margin: float, bottom_radius: int = -1, top_radius: int = -1) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	if bottom_radius >= 0:
		b.corner_radius_top_left = 0
		b.corner_radius_top_right = 0
		b.corner_radius_bottom_left = bottom_radius
		b.corner_radius_bottom_right = bottom_radius
	if top_radius >= 0:
		b.corner_radius_bottom_left = 0
		b.corner_radius_bottom_right = 0
		b.corner_radius_top_left = top_radius
		b.corner_radius_top_right = top_radius
	b.set_content_margin_all(margin)
	return b
