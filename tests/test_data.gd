extends GutTest

var _d: GameData


func before_all() -> void:
	_d = GameData.load_dir()


func test_loads_and_validates() -> void:
	assert_eq(_d.validate(), [] as Array[String], "validation errors")


func test_counts() -> void:
	assert_eq(_d.specimens.size(), 60)
	assert_eq(_d.sites.size(), 2)
	assert_eq(_d.tools.size(), 8)
	assert_eq(_d.diggers.size(), 6)
	assert_between(_d.upgrades.size(), 15, 22)


func test_site_rarity_mix() -> void:
	var expected: Dictionary = {"common": 14, "uncommon": 8, "rare": 5, "epic": 2, "legendary": 1}
	for site: Dictionary in _d.sites:
		var got: Dictionary = {}
		for s: Dictionary in _d.specimens_for_site(site["id"]):
			got[s["rarity"]] = int(got.get(s["rarity"], 0)) + 1
		assert_eq(got, expected, "mix for %s" % site["id"])


func test_values_rise_by_rarity() -> void:
	for site: Dictionary in _d.sites:
		var lo: Dictionary = {}
		var hi: Dictionary = {}
		for s: Dictionary in _d.specimens_for_site(site["id"]):
			var r: String = s["rarity"]
			lo[r] = minf(float(lo.get(r, INF)), float(s["base_value"]))
			hi[r] = maxf(float(hi.get(r, 0.0)), float(s["base_value"]))
		for i: int in range(1, GameData.RARITIES.size()):
			var prev: String = GameData.RARITIES[i - 1]
			var cur: String = GameData.RARITIES[i]
			assert_gt(lo[cur], hi[prev], "%s tier above %s" % [cur, prev])


func test_every_effect_type_is_covered() -> void:
	var seen: Dictionary = {}
	for u: Dictionary in _d.upgrades:
		seen[u["effect_type"]] = true
	for t: String in GameData.EFFECT_TYPES:
		assert_true(seen.has(t), "no upgrade for %s" % t)


func test_sites_ordered_and_helpers() -> void:
	var ordered: Array[Dictionary] = _d.sites_in_order()
	assert_eq(ordered[0]["id"], "dry_creek")
	assert_eq(ordered[1]["id"], "salt_flats")
	assert_eq(_d.specimens_for_site("dry_creek").size(), 30)
	assert_eq(_d.specimens_for_site("nowhere").size(), 0)


func test_validate_catches_problems() -> void:
	var bad: GameData = GameData.load_dir()
	bad.specimens[0]["fact"] = "x".repeat(121)
	bad.specimens[1]["rarity"] = "mythic"
	bad.upgrades[0]["requires"] = {"item_id": "does_not_exist"}
	bad.config["rarity_weights"]["rare"] = 0
	var errs: Array[String] = bad.validate()
	assert_gte(errs.size(), 4)
	var missing: GameData = GameData.load_dir("res://nope")
	assert_gt(missing.validate().size(), 0)
