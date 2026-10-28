class_name Haptics
extends RefCounted
## Short vibration pulses; user-toggleable, no-op off mobile.

const KEY: String = "haptics"


static func enabled() -> bool:
	return SettingsStore.get_bool(KEY, true)


static func pulse(ms: int) -> void:
	if ms > 0 and enabled() and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
