extends GutTest

const HOUR: float = 3600.0
const INCOME: float = 10.0
const SLABS: float = 0.5
const CAP_H: float = 8.0
const EFF: float = 0.5
const MIN_S: float = 60.0


func _run(delta: float, cap: float = CAP_H) -> Dictionary:
	return Offline.compute(1000.0, 1000.0 + delta, INCOME, SLABS, cap, EFF, MIN_S)


func test_table() -> void:
	var cases: Array = [
		# [delta, cap, seconds, coins, slabs, capped]
		[0.0, CAP_H, 0.0, 0.0, 0, false],
		[30.0, CAP_H, 0.0, 0.0, 0, false],
		[60.0, CAP_H, 60.0, 300.0, 15, false],
		[3.0 * HOUR, CAP_H, 3.0 * HOUR, 54000.0, 2700, false],
		[8.0 * HOUR, CAP_H, 8.0 * HOUR, 144000.0, 7200, false],
		[20.0 * HOUR, CAP_H, 8.0 * HOUR, 144000.0, 7200, true],
		[20.0 * HOUR, 10.0, 10.0 * HOUR, 180000.0, 9000, true],
		[-500.0, CAP_H, 0.0, 0.0, 0, false],
		[1e12, CAP_H, 8.0 * HOUR, 144000.0, 7200, true],
	]
	for c: Array in cases:
		var r: Dictionary = _run(c[0], c[1])
		assert_almost_eq(r["seconds"], c[2], 1e-6, "seconds @%s" % c[0])
		assert_almost_eq(r["coins"], c[3], 1e-6, "coins @%s" % c[0])
		assert_eq(r["slabs"], c[4], "slabs @%s" % c[0])
		assert_eq(r["capped"], c[5], "capped @%s" % c[0])


func test_bad_inputs_earn_nothing() -> void:
	assert_eq(Offline.compute(NAN, 5000.0, INCOME, SLABS, CAP_H, EFF)["seconds"], 0.0)
	assert_eq(Offline.compute(1000.0, NAN, INCOME, SLABS, CAP_H, EFF)["coins"], 0.0)
	assert_eq(Offline.compute(1000.0, 9000.0, INCOME, SLABS, 0.0, EFF)["seconds"], 0.0)
	assert_eq(Offline.compute(1000.0, 9000.0, -5.0, -5.0, CAP_H, EFF)["coins"], 0.0)


func test_efficiency_clamped_and_huge_income_safe() -> void:
	assert_almost_eq(Offline.compute(0.0, 100.0, 10.0, 0.0, CAP_H, 5.0)["coins"], 1000.0, 1e-9)
	assert_eq(Offline.compute(0.0, 100.0, 10.0, 0.0, CAP_H, -1.0)["coins"], 0.0)
	var big: Dictionary = Offline.compute(0.0, 20.0 * HOUR, 1e299, 1e299, CAP_H, 1.0)
	assert_eq(big["coins"], Economy.MAX_VALUE)
	assert_lte(float(big["slabs"]), Offline.MAX_SLABS)
