class_name SafeArea
extends RefCounted
## Display-cutout / system-bar insets converted to canvas units (left, top, right, bottom).


static func insets(vp: Viewport) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen: Vector2i = DisplayServer.screen_get_size()
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var k: Vector2 = vp.get_visible_rect().size / win
	return Vector4(
		maxf(float(safe.position.x), 0.0) * k.x,
		maxf(float(safe.position.y), 0.0) * k.y,
		maxf(float(screen.x - safe.end.x), 0.0) * k.x,
		maxf(float(screen.y - safe.end.y), 0.0) * k.y)
