extends GutTest

const GROWTHS: Array[float] = [1.0, 1.14, 1.15, 1.17]
const OWNED: Array[int] = [0, 1, 10, 100, 1000]


func test_cost_table() -> void:
	for g: float in GROWTHS:
		for n: int in OWNED:
			var want: float = 50.0 * pow(g, float(n))
			assert_almost_eq(Economy.cost(50.0, g, n), want, want * 1e-12 + 1e-12, "g=%s n=%d" % [g, n])


func test_cost_guards() -> void:
	assert_eq(Economy.cost(50.0, 1.15, -5), 50.0)
	assert_eq(Economy.cost(0.0, 1.15, 100000), 0.0)
	assert_eq(Economy.cost(1e200, 1.17, 100000), Economy.MAX_VALUE)
	assert_eq(Economy.clamp_value(NAN), 0.0)
	assert_eq(Economy.clamp_value(INF), Economy.MAX_VALUE)


func test_bulk_equals_sum_of_singles() -> void:
	for g: float in GROWTHS:
		for n: int in OWNED:
			for qty: int in [1, 5, 25]:
				var sum: float = 0.0
				for i: int in qty:
					sum += Economy.cost(80.0, g, n + i)
				var bulk: float = Economy.bulk_cost(80.0, g, n, qty)
				assert_almost_eq(bulk, sum, absf(sum) * 1e-9, "g=%s n=%d qty=%d" % [g, n, qty])
	assert_eq(Economy.bulk_cost(80.0, 1.15, 3, 0), 0.0)
	assert_eq(Economy.bulk_cost(80.0, 1.15, 3, -2), 0.0)


func test_max_affordable_never_overspends() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for g: float in GROWTHS:
		for n: int in OWNED:
			for _k: int in 20:
				var budget: float = pow(10.0, rng.randf_range(0.0, 12.0))
				var q: int = Economy.max_affordable(100.0, g, n, budget)
				assert_lte(Economy.bulk_cost(100.0, g, n, q), budget)
				if q < Economy.MAX_BULK:
					assert_gt(Economy.bulk_cost(100.0, g, n, q + 1), budget, "q+1 must overspend")


func test_max_affordable_edges() -> void:
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, 99.0), 0)
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, 100.0), 1)
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, 1e6, 3), 3)
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, 1e6, 0), 0)
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, NAN), 0)
	assert_eq(Economy.max_affordable(100.0, 1.15, 0, -5.0), 0)
	assert_eq(Economy.max_affordable(0.0, 1.0, 0, 0.0), 1, "free single item")
	assert_gt(Economy.max_affordable(100.0, 1.15, 0, 1e300), 1000)


func test_upgrade_bonus_and_multiplier() -> void:
	var ups: Array[Dictionary] = [
		{"id": "a", "effect_type": "digger_speed_mult", "effect_value": 0.1},
		{"id": "b", "effect_type": "digger_speed_mult", "effect_value": 0.25},
		{"id": "c", "effect_type": "value_mult_era", "effect_value": 0.5, "era": "Devonian"},
		{"id": "d", "effect_type": "value_mult_era", "effect_value": 0.5, "era": "Jurassic"},
	]
	var owned: Dictionary = {"a": 3, "b": 1, "c": 2, "d": 1}
	assert_almost_eq(Economy.upgrade_bonus(owned, ups, "digger_speed_mult"), 0.55, 1e-12)
	assert_almost_eq(Economy.upgrade_multiplier(owned, ups, "digger_speed_mult"), 1.55, 1e-12)
	assert_almost_eq(Economy.upgrade_multiplier(owned, ups, "value_mult_era", "Devonian"), 2.0, 1e-12)
	assert_almost_eq(Economy.upgrade_multiplier(owned, ups, "value_mult_era", "Permian"), 1.0, 1e-12)
	assert_eq(Economy.upgrade_multiplier({}, ups, "rarity_luck"), 1.0)


func test_income_and_brush_and_value() -> void:
	var d: GameData = GameData.load_dir()
	assert_eq(Economy.slabs_per_sec({}, d.diggers, 1.0), 0.0)
	var owned: Dictionary = {"intern": 10, "field_crew": 2}
	assert_almost_eq(Economy.slabs_per_sec(owned, d.diggers, 1.0), 0.2 + 0.24, 1e-12)
	assert_almost_eq(Economy.slabs_per_sec(owned, d.diggers, 2.0), 0.88, 1e-12)
	assert_eq(Economy.slabs_per_sec(owned, d.diggers, -3.0), 0.0, "negative mult clamps")
	assert_almost_eq(Economy.income_per_sec(2.0, 25.0, 1.5), 75.0, 1e-12)
	assert_almost_eq(Economy.fieldwork_multiplier(10.0, 0.05), 1.5, 1e-12)
	assert_eq(Economy.fieldwork_multiplier(-4.0, 0.05), 1.0)
	assert_eq(Economy.brush_power({}, d.tools), 1.0)
	assert_eq(Economy.brush_power({"soft_bristle": 1, "badger": 1}, d.tools), 1.5)
	assert_almost_eq(Economy.specimen_value(10.0, 2.0, 1.5), 30.0, 1e-12)
	assert_eq(Economy.specimen_value(1e300, 1e300, 1e300), Economy.MAX_VALUE)
