class_name SlabGenerator
extends RefCounted
## Weighted rarity roll with pity counters, limited to one site's specimen pool.

const MIN_LUCK: float = -0.9
const MAX_LUCK: float = 10.0

var _rng: RandomNumberGenerator
var _weights: Dictionary = {}
var _pity: Dictionary = {}
var _hardness_per_tier: float = 0.0
var _pool: Dictionary = {}
## rarity -> consecutive slabs rolled below that rarity
var _since: Dictionary = {}


func _init(config: Dictionary, specimens: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	_rng = rng
	_weights = config["rarity_weights"]
	_pity = config["pity"]
	_hardness_per_tier = float(config["hardness_per_tier"])
	for r: String in GameData.RARITIES:
		_since[r] = 0
	set_pool(specimens)


func set_pool(specimens: Array[Dictionary]) -> void:
	_pool.clear()
	for s: Dictionary in specimens:
		var tier: Array = _pool.get(s["rarity"], [])
		tier.append(s)
		_pool[s["rarity"]] = tier


func get_state() -> Dictionary:
	return {"since": _since.duplicate()}


func set_state(state: Dictionary) -> void:
	var saved: Dictionary = state.get("since", {})
	for r: String in GameData.RARITIES:
		_since[r] = maxi(int(saved.get(r, 0)), 0)


## Probability of each rarity (before pity) given luck. Absent tiers get 0.
func tier_probabilities(luck: float) -> Dictionary:
	var l: float = clampf(luck, MIN_LUCK, MAX_LUCK)
	var w: Dictionary = {}
	var total: float = 0.0
	for i: int in GameData.RARITIES.size():
		var r: String = GameData.RARITIES[i]
		var x: float = 0.0
		if _pool.has(r):
			x = float(_weights[r]) * pow(1.0 + l, float(i))
		w[r] = x
		total += x
	for r: String in w:
		w[r] = w[r] / total if total > 0.0 else 0.0
	return w


## Mean value of a slab (pity ignored). era_mult: era -> value multiplier.
func expected_value(luck: float, value_mult: float = 1.0, era_mult: Dictionary = {}) -> float:
	var probs: Dictionary = tier_probabilities(luck)
	var total: float = 0.0
	for r: String in probs:
		if probs[r] <= 0.0:
			continue
		var tier: Array = _pool[r]
		var wsum: float = 0.0
		var vsum: float = 0.0
		for s: Dictionary in tier:
			wsum += float(s["weight"])
			vsum += float(s["weight"]) * Economy.specimen_value(float(s["base_value"]), value_mult, float(era_mult.get(s["era"], 1.0)))
		total += probs[r] * vsum / wsum
	return Economy.clamp_value(total)


## Returns {specimen: Dictionary, rarity: String, hardness: float}.
func roll(luck: float = 0.0) -> Dictionary:
	var probs: Dictionary = tier_probabilities(luck)
	var min_idx: int = 0
	for i: int in range(1, GameData.RARITIES.size()):
		var r: String = GameData.RARITIES[i]
		if _pity.has(r) and int(_since[r]) >= int(_pity[r]) - 1:
			min_idx = i
	var idx: int = _pick_tier(probs, min_idx)
	for i: int in range(1, GameData.RARITIES.size()):
		_since[GameData.RARITIES[i]] = 0 if idx >= i else int(_since[GameData.RARITIES[i]]) + 1
	var rarity: String = GameData.RARITIES[idx]
	return {
		"specimen": _pick_specimen(_pool[rarity]),
		"rarity": rarity,
		"hardness": 1.0 + _hardness_per_tier * float(idx),
	}


## Aggregate rolls for auto-diggers/offline. Rolls at most `cap`; the caller multiplies
## summed value by `scale` (= count / rolled) so huge counts stay O(cap).
## Returns {count, rolled, scale, counts: {specimen_id: int}}.
func roll_many(count: int, luck: float, cap: int) -> Dictionary:
	var rolled: int = mini(maxi(count, 0), maxi(cap, 0))
	var counts: Dictionary = {}
	for _i: int in rolled:
		var id: String = roll(luck)["specimen"]["id"]
		counts[id] = int(counts.get(id, 0)) + 1
	return {
		"count": maxi(count, 0), "rolled": rolled,
		"scale": float(maxi(count, 0)) / float(rolled) if rolled > 0 else 0.0,
		"counts": counts,
	}


func _pick_tier(probs: Dictionary, min_idx: int) -> int:
	var total: float = 0.0
	var highest: int = 0
	for i: int in range(min_idx, GameData.RARITIES.size()):
		var p: float = float(probs[GameData.RARITIES[i]])
		total += p
	if total <= 0.0:
		for i: int in GameData.RARITIES.size():
			if _pool.has(GameData.RARITIES[i]):
				highest = i
		return highest
	var pick: float = _rng.randf() * total
	for i: int in range(min_idx, GameData.RARITIES.size()):
		var p: float = float(probs[GameData.RARITIES[i]])
		if p <= 0.0:
			continue
		highest = i
		pick -= p
		if pick < 0.0:
			return i
	return highest


func _pick_specimen(tier: Array) -> Dictionary:
	var total: float = 0.0
	for s: Dictionary in tier:
		total += float(s["weight"])
	var pick: float = _rng.randf() * total
	for s: Dictionary in tier:
		pick -= float(s["weight"])
		if pick < 0.0:
			return s
	return tier[tier.size() - 1]
