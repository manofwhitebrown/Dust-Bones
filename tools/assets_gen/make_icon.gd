extends SceneTree
## Rasterize assets/icons/icon.svg to PNGs (splash + store icon):
##   godot --headless --path . -s tools/assets_gen/make_icon.gd

func _init() -> void:
	var svg: String = FileAccess.get_file_as_string("res://assets/icons/icon.svg")
	var err: int = 0
	for target: Array in [["res://assets/icons/icon_512.png", 1.0], ["res://assets/icons/splash.png", 0.75]]:
		var img: Image = Image.new()
		err += img.load_svg_from_string(svg, float(target[1]))
		err += img.save_png(String(target[0]))
	print("icons written, err=", err)
	quit(err)
