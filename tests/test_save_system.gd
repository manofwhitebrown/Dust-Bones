extends GutTest

const PATH: String = "user://test_save_system.json"

var _s: SaveSystem


func before_each() -> void:
	_s = SaveSystem.new(PATH)
	_s.delete_all()


func after_each() -> void:
	_s.delete_all()


func _sample(coins: float) -> Dictionary:
	return {
		"version": float(SaveSystem.CURRENT_VERSION), "coins": coins, "owned": {"soft_bristle": 1.0, "intern": 12.0},
		"discovered": ["amber", "trilobite"], "big": 1.2345678901234567e250, "tiny": 0.1 + 0.2,
		"nested": {"a": [1.0, 2.5, {"b": "c"}]},
	}


func test_roundtrip_is_exact() -> void:
	var d: Dictionary = _sample(123.456)
	assert_true(_s.save(d))
	var loaded: Dictionary = _s.load_game()
	assert_eq(_s.last_load_source, "main")
	assert_eq(loaded, d)
	assert_eq(loaded["big"], d["big"])
	assert_eq(loaded["tiny"], d["tiny"])


func test_float_fuzz_roundtrips_bit_exact() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 321
	var values: Array = []
	for _i: int in 3000:
		var mag: float = pow(10.0, rng.randf_range(-320.0, 300.0))
		values.append(mag * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.0, 9.99))
	assert_true(_s.save({"version": 1, "v": values}))
	var loaded: Array = _s.load_game()["v"]
	for i: int in values.size():
		assert_eq(loaded[i], values[i], "value %d" % i)


func test_second_save_keeps_backup() -> void:
	_s.save(_sample(1.0))
	_s.save(_sample(2.0))
	assert_true(FileAccess.file_exists(PATH + SaveSystem.BAK_SUFFIX))
	assert_false(FileAccess.file_exists(PATH + SaveSystem.TMP_SUFFIX))
	assert_eq(_s.load_game()["coins"], 2.0)


func test_truncated_main_falls_back_to_bak() -> void:
	_s.save(_sample(1.0))
	_s.save(_sample(2.0))
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	var half: String = f.get_as_text().substr(0, 20)
	f.close()
	var w: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	w.store_string(half)
	w.close()
	var loaded: Dictionary = _s.load_game()
	assert_eq(_s.last_load_source, "bak")
	assert_eq(loaded["coins"], 1.0)


func test_both_corrupt_or_missing_gives_fresh() -> void:
	assert_eq(_s.load_game(), {})
	assert_eq(_s.last_load_source, "fresh")
	for p: String in [PATH, PATH + SaveSystem.BAK_SUFFIX]:
		var w: FileAccess = FileAccess.open(p, FileAccess.WRITE)
		w.store_string("{not json")
		w.close()
	assert_eq(_s.load_game(), {})
	assert_eq(_s.last_load_source, "fresh")


func test_non_finite_numbers_are_sanitized() -> void:
	assert_true(_s.save({"version": 1, "a": INF, "b": NAN, "c": [-INF, 2.0]}))
	var d: Dictionary = _s.load_game()
	assert_eq(d["a"], 0.0)
	assert_eq(d["b"], 0.0)
	assert_eq(d["c"], [0.0, 2.0])


func test_v0_fixture_migrates() -> void:
	var f: FileAccess = FileAccess.open("res://tests/fixtures/save_v0.json", FileAccess.READ)
	var v0: Dictionary = JSON.parse_string(f.get_as_text())
	var d: Dictionary = SaveSystem.migrate(v0)
	assert_eq(d["version"], SaveSystem.CURRENT_VERSION)
	assert_eq(d["coins"], 42.5)
	assert_false(d.has("money"))
	assert_eq(d["discovered"], ["trilobite"])
	assert_true(v0.has("money"), "input not mutated")


func test_migrate_current_is_noop_and_unknown_version_rejected() -> void:
	var d: Dictionary = _sample(5.0)
	assert_eq(SaveSystem.migrate(d), d)
	assert_eq(SaveSystem.migrate({"version": -7}), {})


func test_load_migrates_old_file() -> void:
	var w: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	w.store_string('{"version": 0, "money": 9.0}')
	w.close()
	assert_eq(_s.load_game()["coins"], 9.0)


func test_delete_all() -> void:
	_s.save(_sample(1.0))
	_s.save(_sample(2.0))
	_s.delete_all()
	assert_false(FileAccess.file_exists(PATH))
	assert_false(FileAccess.file_exists(PATH + SaveSystem.BAK_SUFFIX))
