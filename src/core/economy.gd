class_name Economy
extends RefCounted
## Pure economy math. No state, no time, no RNG.

const MAX_VALUE: float = 1e300
const GROWTH_EPSILON: float = 1e-9
const MAX_BULK: int = 1000000
const BASE_BRUSH_POWER: float = 1.0
const MIN_MULT: float = 0.0


static func clamp_value(x: float) -> float:
	if is_nan(x):
		return 0.0
	return clampf(x, -MAX_VALUE, MAX_VALUE)


static func cost(base: float, growth: float, owned: int) -> float:
	return clamp_value(base * pow(growth, float(maxi(owned, 0))))


## Total price of `qty` units starting from `owned` (geometric series, closed form).
static func bulk_cost(base: float, growth: float, owned: int, qty: int) -> float:
	if qty <= 0:
		return 0.0
	var first: float = base * pow(growth, float(maxi(owned, 0)))
	if absf(growth - 1.0) < GROWTH_EPSILON:
		return clamp_value(first * float(qty))
	return clamp_value(first * (pow(growth, float(qty)) - 1.0) / (growth - 1.0))


## Largest qty with bulk_cost(qty) <= budget. max_qty < 0 means unlimited.
static func max_affordable(base: float, growth: float, owned: int, budget: float, max_qty: int = -1) -> int:
	var limit: int = MAX_BULK if max_qty < 0 else mini(max_qty, MAX_BULK)
	if limit <= 0 or is_nan(budget) or budget < 0.0:
		return 0
	var first: float = cost(base, growth, owned)
	if first <= 0.0:
		return limit if max_qty >= 0 else 1
	if first > budget:
		return 0
	var n: float
	if absf(growth - 1.0) < GROWTH_EPSILON:
		n = floorf(budget / first)
	else:
		n = floorf(log(budget * (growth - 1.0) / first + 1.0) / log(growth))
	var qty: int = clampi(int(minf(n, float(MAX_BULK))), 0, limit)
	while qty > 0 and bulk_cost(base, growth, owned, qty) > budget:
		qty -= 1
	while qty < limit and bulk_cost(base, growth, owned, qty + 1) <= budget:
		qty += 1
	return qty


## Sum of owned upgrade effect values for one effect type (additive stacking).
static func upgrade_bonus(owned: Dictionary, upgrades: Array[Dictionary], effect_type: String, era: String = "") -> float:
	var total: float = 0.0
	for u: Dictionary in upgrades:
		if u["effect_type"] != effect_type:
			continue
		if effect_type == "value_mult_era" and u.get("era", "") != era:
			continue
		total += float(u["effect_value"]) * float(owned.get(u["id"], 0))
	return clamp_value(total)


static func upgrade_multiplier(owned: Dictionary, upgrades: Array[Dictionary], effect_type: String, era: String = "") -> float:
	return maxf(MIN_MULT, 1.0 + upgrade_bonus(owned, upgrades, effect_type, era))


static func slabs_per_sec(owned: Dictionary, diggers: Array[Dictionary], speed_mult: float) -> float:
	var total: float = 0.0
	for d: Dictionary in diggers:
		total += float(d["slabs_per_sec"]) * float(owned.get(d["id"], 0))
	return clamp_value(total * maxf(speed_mult, MIN_MULT))


static func income_per_sec(slabs_per_second: float, expected_slab_value: float, income_mult: float) -> float:
	return clamp_value(slabs_per_second * expected_slab_value * maxf(income_mult, MIN_MULT))


static func fieldwork_multiplier(fieldwork: float, per_fieldwork: float) -> float:
	return clamp_value(1.0 + maxf(fieldwork, 0.0) * per_fieldwork)


static func brush_power(owned: Dictionary, tools: Array[Dictionary]) -> float:
	var best: float = BASE_BRUSH_POWER
	for t: Dictionary in tools:
		if int(owned.get(t["id"], 0)) > 0:
			best = maxf(best, float(t["brush_power"]))
	return best


## Coin value of one specimen: base x global value mult x era mult.
static func specimen_value(base_value: float, value_mult: float, era_mult: float) -> float:
	return clamp_value(base_value * maxf(value_mult, MIN_MULT) * maxf(era_mult, MIN_MULT))
