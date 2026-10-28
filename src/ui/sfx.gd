class_name Sfx
extends RefCounted
## Thin, null-safe facade over the AudioManager autoload (so views never depend on it directly).


static func _mgr() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioManager") if tree != null else null


static func play(sound: StringName, pitch: float = 1.0) -> void:
	var m: Node = _mgr()
	if m != null:
		m.call("play", sound, pitch)


static func coin_tick() -> void:
	var m: Node = _mgr()
	if m != null:
		m.call("coin_tick")


static func brush_move(speed: float) -> void:
	var m: Node = _mgr()
	if m != null:
		m.call("brush_move", speed)


static func brush_stop() -> void:
	var m: Node = _mgr()
	if m != null:
		m.call("brush_stop")


static func reveal(rarity: String) -> void:
	play(StringName("reveal_" + rarity))
