class_name Prestige
extends RefCounted
## Pure prestige math: fieldwork from lifetime coins, next-site selection, bonus text.


## Total unmultiplied fieldwork "earned" by `lifetime` coins: floor(k * (lifetime / base) ^ exp).
static func total_for(lifetime: float, p: Dictionary) -> float:
	if lifetime < float(p["min_lifetime_coins"]) or lifetime <= 0.0:
		return 0.0
	var v: float = float(p["k"]) * pow(lifetime / float(p["base"]), float(p["exp"]))
	return Economy.clamp_value(floorf(v))


## Unmultiplied gain not yet claimed. `basis` is the unmultiplied total claimed so far.
static func raw_gain(lifetime: float, basis: float, p: Dictionary) -> float:
	return maxf(total_for(lifetime, p) - basis, 0.0)


## Fieldwork actually paid out: the raw gain times the fieldwork_gain_mult multiplier.
static func gain(lifetime: float, basis: float, p: Dictionary, gain_mult: float) -> float:
	return Economy.clamp_value(floorf(raw_gain(lifetime, basis, p) * maxf(gain_mult, 0.0)))


static func bonus_text(fieldwork_after: float, per_fieldwork: float) -> String:
	return "+%s%% income" % NumFormat.fmt(maxf(fieldwork_after, 0.0) * per_fieldwork * 100.0)


## Site after `current_id` in order (looping past the last one). Stays put if it is still locked.
static func next_site(sites_in_order: Array[Dictionary], current_id: String, fieldwork_after: float) -> Dictionary:
	var idx: int = 0
	for i: int in sites_in_order.size():
		if sites_in_order[i]["id"] == current_id:
			idx = i
	var candidate: Dictionary = sites_in_order[(idx + 1) % sites_in_order.size()]
	if float(candidate["unlock_fieldwork"]) <= fieldwork_after:
		return candidate
	return sites_in_order[idx]
