class_name PlaceholderView
extends Control
## Temporary tab content until the real view lands (shop B5, museum B6, prestige B7).


func setup(title: String) -> PlaceholderView:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var l: Label = Label.new()
	l.text = "%s\ncoming soon" % title
	l.theme_type_variation = &"Heading"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(l)
	return self
