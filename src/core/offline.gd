class_name Offline
extends RefCounted
## Offline earnings. Pure: time is always passed in.

const SECONDS_PER_HOUR: float = 3600.0
const MAX_SLABS: float = 4.0e18


## Returns {seconds, coins, slabs, capped}. Credited seconds are limited to the cap;
## negative, NaN or sub-minimum deltas (clock tampering, quick app switches) earn nothing.
static func compute(last_save_unix: float, now_unix: float, income_per_sec: float,
		slabs_per_sec: float, cap_hours: float, efficiency: float, min_seconds: float = 0.0) -> Dictionary:
	var delta: float = now_unix - last_save_unix
	if is_nan(delta) or delta <= 0.0 or delta < min_seconds:
		return _empty()
	var cap_seconds: float = maxf(cap_hours, 0.0) * SECONDS_PER_HOUR
	var seconds: float = minf(delta, cap_seconds)
	if seconds <= 0.0:
		return _empty()
	var eff: float = clampf(efficiency, 0.0, 1.0)
	return {
		"seconds": seconds,
		"coins": Economy.clamp_value(maxf(income_per_sec, 0.0) * seconds * eff),
		"slabs": int(minf(floorf(maxf(slabs_per_sec, 0.0) * seconds * eff), MAX_SLABS)),
		"capped": delta > cap_seconds,
	}


static func _empty() -> Dictionary:
	return {"seconds": 0.0, "coins": 0.0, "slabs": 0, "capped": false}
