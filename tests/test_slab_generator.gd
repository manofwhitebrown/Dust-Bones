extends GutTest

const ROLLS: int = 100000
const TOLERANCE: float = 0.015

var _d: GameData


func before_all() -> void:
	_d = GameData.load_dir()


func _gen(seed_value: int, site: String = "dry_creek") -> SlabGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return SlabGenerator.new(_d.config, _d.specimens_for_site(site), rng)


func test_tier_frequencies_match_expected_with_pity() -> void:
	var g: SlabGenerator = _gen(1234)
	var base: Dictionary = g.tier_probabilities(0.0)
	var p_common: float = base["common"]
	var n: int = int(_d.config["pity"]["uncommon"])
	# Commons run until a natural non-common, or is forced on the n-th slab.
	var e_k: float = 0.0
	for k: int in n - 1:
		e_k += float(k) * pow(p_common, float(k)) * (1.0 - p_common)
	e_k += float(n - 1) * pow(p_common, float(n - 1))
	var common_freq: float = e_k / (e_k + 1.0)
	var rest: float = 1.0 - base["common"]
	var counts: Dictionary = {}
	for _i: int in ROLLS:
		var r: String = g.roll()["rarity"]
		counts[r] = int(counts.get(r, 0)) + 1
	assert_almost_eq(float(counts["common"]) / ROLLS, common_freq, TOLERANCE, "common")
	for r: String in ["uncommon", "rare", "epic", "legendary"]:
		var expected: float = (1.0 - common_freq) * base[r] / rest
		assert_almost_eq(float(counts.get(r, 0)) / ROLLS, expected, TOLERANCE, r)


func test_pity_never_violated() -> void:
	for luck: float in [0.0, -0.9]:
		var g: SlabGenerator = _gen(99)
		var run: Dictionary = {}
		for r: String in _d.config["pity"]:
			run[r] = 0
		for _i: int in ROLLS:
			var idx: int = GameData.RARITIES.find(g.roll(luck)["rarity"])
			for r: String in _d.config["pity"]:
				if idx >= GameData.RARITIES.find(r):
					run[r] = 0
				else:
					run[r] += 1
					assert_lt(run[r], int(_d.config["pity"][r]), "pity %s luck %s" % [r, luck])


func test_pity_triggers_when_odds_are_tiny() -> void:
	var g: SlabGenerator = _gen(5)
	var legendary: int = 0
	for _i: int in 5000:
		if g.roll(-0.9)["rarity"] == "legendary":
			legendary += 1
	assert_gte(legendary, 5000 / int(_d.config["pity"]["legendary"]) - 1)


func test_luck_shifts_weights() -> void:
	var g: SlabGenerator = _gen(1)
	var lo: Dictionary = g.tier_probabilities(0.0)
	var hi: Dictionary = g.tier_probabilities(1.0)
	assert_gt(hi["legendary"], lo["legendary"])
	assert_lt(hi["common"], lo["common"])
	var sum: float = 0.0
	for r: String in hi:
		sum += hi[r]
	assert_almost_eq(sum, 1.0, 1e-12)
	assert_eq(g.tier_probabilities(-5.0), g.tier_probabilities(SlabGenerator.MIN_LUCK), "luck clamps")


func test_hardness_rises_with_rarity_and_specimen_in_pool() -> void:
	var g: SlabGenerator = _gen(3, "salt_flats")
	var by_rarity: Dictionary = {}
	for _i: int in 3000:
		var res: Dictionary = g.roll(2.0)
		by_rarity[res["rarity"]] = res["hardness"]
		assert_eq(res["specimen"]["site"], "salt_flats")
		assert_eq(res["specimen"]["rarity"], res["rarity"])
	var prev: float = 0.0
	for r: String in GameData.RARITIES:
		if by_rarity.has(r):
			assert_gt(by_rarity[r], prev)
			prev = by_rarity[r]
	assert_eq(by_rarity["common"], 1.0)


func test_deterministic_and_state_roundtrip() -> void:
	var a: SlabGenerator = _gen(42)
	var b: SlabGenerator = _gen(42)
	for _i: int in 200:
		assert_eq(a.roll()["specimen"]["id"], b.roll()["specimen"]["id"])
	var c: SlabGenerator = _gen(8)
	for _i: int in 5:
		c.roll()
	var state: Dictionary = c.get_state()
	var e: SlabGenerator = _gen(8)
	e.set_state(state)
	assert_eq(e.get_state(), state)
	e.set_state({"since": {"uncommon": -4}})
	assert_eq(e.get_state()["since"]["uncommon"], 0, "negative counters clamp")


func test_roll_many_caps_and_scales() -> void:
	var g: SlabGenerator = _gen(11)
	var res: Dictionary = g.roll_many(10000, 0.0, 200)
	assert_eq(res["rolled"], 200)
	assert_almost_eq(res["scale"], 50.0, 1e-12)
	var total: int = 0
	for id: String in res["counts"]:
		total += res["counts"][id]
	assert_eq(total, 200)
	var small: Dictionary = g.roll_many(7, 0.0, 200)
	assert_eq(small["rolled"], 7)
	assert_eq(small["scale"], 1.0)
	assert_eq(g.roll_many(0, 0.0, 200)["scale"], 0.0)
	assert_eq(g.roll_many(-5, 0.0, 200)["count"], 0)


func test_expected_value_and_era_mult() -> void:
	var g: SlabGenerator = _gen(1)
	var ev: float = g.expected_value(0.0)
	assert_between(ev, 15.0, 40.0)
	assert_almost_eq(g.expected_value(0.0, 2.0), ev * 2.0, ev * 1e-9)
	assert_gt(g.expected_value(0.0, 1.0, {"Devonian": 3.0}), ev)
	assert_gt(g.expected_value(2.0), ev, "luck raises value")


func test_missing_tier_falls_back() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2
	var only_common: Array[Dictionary] = []
	for s: Dictionary in _d.specimens_for_site("dry_creek"):
		if s["rarity"] == "common":
			only_common.append(s)
	var g: SlabGenerator = SlabGenerator.new(_d.config, only_common, rng)
	for _i: int in 500:
		assert_eq(g.roll()["rarity"], "common")
