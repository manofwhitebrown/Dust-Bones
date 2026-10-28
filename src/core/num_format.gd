class_name NumFormat
extends RefCounted
## Compact number formatting: 950, 1.24K, 3.50M, 1.20e15.

const SUFFIXES: Array[String] = ["", "K", "M", "B", "T"]
const SCI_START_EXP: int = 15
const STEP_EXP: int = 3
const ROUND_UP_LIMIT: float = 999.995


static func fmt(x: float) -> String:
	if is_nan(x):
		return "0"
	if is_inf(x):
		return "inf" if x > 0.0 else "-inf"
	if x < 0.0:
		return "-" + fmt(-x)
	if x < 1000.0:
		return _small(x)
	var exp10: int = int(floor(log(x) / log(10.0)))
	# log() can be off by one near exact powers of ten.
	if pow(10.0, exp10 + 1) <= x:
		exp10 += 1
	elif pow(10.0, exp10) > x:
		exp10 -= 1
	var mant: float = x / pow(10.0, exp10)
	if mant >= 9.995:  # "%.2f" would print 10.00
		exp10 += 1
		mant = x / pow(10.0, exp10)
	if exp10 >= SCI_START_EXP:
		return "%.2fe%d" % [mant, exp10]
	var tier: int = exp10 / STEP_EXP
	var scaled: float = x / pow(10.0, tier * STEP_EXP)
	if scaled >= ROUND_UP_LIMIT and tier + 1 < SUFFIXES.size():
		tier += 1
		scaled = x / pow(10.0, tier * STEP_EXP)
	elif scaled >= ROUND_UP_LIMIT:
		return "%.2fe%d" % [mant, exp10]
	return "%.2f%s" % [scaled, SUFFIXES[tier]]


static func _small(x: float) -> String:
	if x >= 999.5:
		return "1.00K"
	if is_equal_approx(x, round(x)) or x >= 100.0:
		return str(int(round(x)))
	var s: String = ("%.1f" if x >= 10.0 else "%.2f") % x
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s
