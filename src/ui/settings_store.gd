class_name SettingsStore
extends RefCounted
## user://settings.cfg wrapper (sound, music, haptics, tutorial flags). Owned by UI.

const PATH: String = "user://settings.cfg"
const SECTION: String = "settings"

static var _cfg: ConfigFile = null


static func get_bool(key: String, default_value: bool) -> bool:
	_ensure()
	return bool(_cfg.get_value(SECTION, key, default_value))


static func set_bool(key: String, value: bool) -> void:
	_ensure()
	_cfg.set_value(SECTION, key, value)
	_cfg.save(PATH)


static func _ensure() -> void:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH) # missing/corrupt file just leaves defaults
