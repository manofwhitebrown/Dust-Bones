extends SceneTree
## Regenerate the shared theme:  godot --headless --path . -s tools/assets_gen/make_theme.gd

func _init() -> void:
	var err: int = ResourceSaver.save(UiTheme.build(), "res://src/ui/theme/dust_theme.tres")
	print("theme saved, err=", err)
	quit(err)
