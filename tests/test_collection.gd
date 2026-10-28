extends GutTest

var _d: GameData
var _c: Collection


func before_all() -> void:
	_d = GameData.load_dir()


func before_each() -> void:
	_c = Collection.new(_d)


func _value(spec: Dictionary) -> float:
	return float(spec["base_value"])


func test_discover_reports_new_once() -> void:
	assert_false(_c.is_discovered("trilobite"))
	assert_true(_c.discover("trilobite"))
	assert_false(_c.discover("trilobite"))
	assert_false(_c.discover("not_a_specimen"))
	assert_true(_c.is_discovered("trilobite"))
	assert_eq(_c.count(), 1)


func test_masking() -> void:
	var hidden: Dictionary = _c.entry("ammonite", 5.0)
	assert_eq(hidden["name"], "???")
	assert_eq(hidden["fact"], "")
	assert_false(hidden["discovered"])
	assert_eq(hidden["value"], 5.0)
	_c.discover("ammonite")
	var shown: Dictionary = _c.entry("ammonite", 5.0)
	assert_eq(shown["name"], "Ammonite")
	assert_ne(shown["fact"], "")
	assert_eq(_c.entry("nope", 1.0), {})


func test_entries_by_site() -> void:
	assert_eq(_c.entries("", _value).size(), 60)
	assert_eq(_c.entries("dry_creek", _value).size(), 30)
	assert_eq(_c.entries("salt_flats", _value)[0]["site"], "salt_flats")
	assert_eq(_c.entries("nowhere", _value).size(), 0)


func test_progress_by_era_and_site() -> void:
	_c.discover("trilobite")
	_c.discover("anomalocaris_appendage")
	_c.discover("mammoth_tusk")
	var all: Dictionary = _c.progress()
	assert_eq(all["discovered"], 3)
	assert_eq(all["total"], 60)
	assert_eq(all["by_era"]["Cambrian"], {"discovered": 2, "total": 2})
	assert_eq(all["by_era"]["Quaternary"]["discovered"], 1)
	var one: Dictionary = _c.progress("dry_creek")
	assert_eq(one["discovered"], 2)
	assert_eq(one["total"], 30)
	assert_false(one["by_era"].has("Quaternary"))


func test_array_roundtrip_drops_unknown() -> void:
	_c.discover("trilobite")
	_c.discover("amber")
	var saved: Array = _c.to_array()
	var fresh: Collection = Collection.new(_d)
	fresh.load_array(saved + ["ghost_id"])
	assert_eq(fresh.to_array(), saved)
	assert_eq(fresh.count(), 2)
