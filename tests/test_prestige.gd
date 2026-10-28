extends GutTest

const GS: GDScript = preload("res://src/autoload/game_state.gd")
const BUS: GDScript = preload("res://src/autoload/event_bus.gd")
const T0: float = 1700000000.0

var _d: GameData
var _bus: Node
var _paths: Array[String] = []


func before_all() -> void:
	_d = GameData.load_dir()


func before_each() -> void:
	_bus = BUS.new()
	add_child_autofree(_bus)
	watch_signals(_bus)


func after_each() -> void:
	for p: String in _paths:
		SaveSystem.new(p).delete_all()
	_paths.clear()


func _make(path: String = "") -> Node:
	if path == "":
		path = "user://test_prestige_%d.json" % Time.get_ticks_usec()
	_paths.append(path)
	var g: Node = GS.new()
	g.bus = _bus
	g.save_path = path
	g.rng_seed = 5
	g.now_unix = T0
	g.offline_emit_delay = 0.0
	add_child_autofree(g)
	return g


func _farm(g: Node, target: float) -> void:
	for _i: int in 5000:
		if g.get_balance("coins") >= target:
			return
		var slab: Dictionary = g.start_new_slab()
		g.report_brush_progress(slab["id"], 1.0)


# ---- pure math

func test_total_for_table() -> void:
	var p: Dictionary = _d.prestige
	var base: float = p["base"]
	assert_eq(Prestige.total_for(0.0, p), 0.0)
	assert_eq(Prestige.total_for(-5.0, p), 0.0)
	assert_eq(Prestige.total_for(float(p["min_lifetime_coins"]) * 0.5, p), 0.0)
	assert_eq(Prestige.total_for(base, p), floorf(float(p["k"])))
	assert_eq(Prestige.total_for(base * 4.0, p), floorf(float(p["k"]) * pow(4.0, float(p["exp"]))))
	assert_true(is_finite(Prestige.total_for(1e300, p)))
	assert_eq(Prestige.total_for(NAN, p), 0.0)


func test_gain_subtracts_basis_and_applies_multiplier() -> void:
	var p: Dictionary = _d.prestige
	var life: float = float(p["base"]) * 100.0
	var total: float = Prestige.total_for(life, p)
	assert_eq(Prestige.raw_gain(life, 0.0, p), total)
	assert_eq(Prestige.raw_gain(life, total, p), 0.0)
	assert_eq(Prestige.raw_gain(life, total + 50.0, p), 0.0)
	assert_eq(Prestige.gain(life, 0.0, p, 1.5), floorf(total * 1.5))
	assert_eq(Prestige.gain(life, 0.0, p, -3.0), 0.0)


func test_bonus_text_and_next_site() -> void:
	assert_eq(Prestige.bonus_text(10.0, 0.05), "+50% income")
	assert_eq(Prestige.bonus_text(-3.0, 0.05), "+0% income")
	var sites: Array[Dictionary] = _d.sites_in_order()
	assert_eq(Prestige.next_site(sites, "dry_creek", 1.0)["id"], "salt_flats")
	assert_eq(Prestige.next_site(sites, "dry_creek", 0.0)["id"], "dry_creek", "locked: stay put")
	assert_eq(Prestige.next_site(sites, "salt_flats", 9.0)["id"], "dry_creek", "loops after the last site")
	var one: Array[Dictionary] = [sites[0]]
	assert_eq(Prestige.next_site(one, "dry_creek", 9.0)["id"], "dry_creek")


# ---- game state

func test_preview_matches_actual_gain_and_resets_run() -> void:
	var g: Node = _make()
	assert_false(g.get_prestige_preview()["can_prestige"])
	g.do_prestige()
	assert_signal_emit_count(_bus, "prestige_done", 0, "not allowed yet")
	_farm(g, 500.0)
	g.buy("intern", 2)
	g.buy("sable")
	g._total_coins = 4.0 * float(_d.prestige["base"])
	g._recalc()
	var prev: Dictionary = g.get_prestige_preview()
	assert_true(prev["can_prestige"])
	assert_gt(prev["fieldwork_gain"], 0.0)
	assert_eq(prev["next_site"]["id"], "salt_flats")
	assert_ne(prev["bonus_text"], "")
	var found: int = g.get_collection_progress()["discovered"]
	var slabs: int = g.get_stats()["slabs_dug"]
	g.do_prestige()
	assert_eq(g.get_balance("fieldwork"), prev["fieldwork_gain"])
	assert_eq(get_signal_parameters(_bus, "prestige_done", 0)[0]["fieldwork_gained"], prev["fieldwork_gain"])
	assert_eq(get_signal_parameters(_bus, "prestige_done", 0)[0]["site_id"], "salt_flats")
	assert_signal_emit_count(_bus, "site_changed", 1)
	assert_signal_emit_count(_bus, "prestige_available_changed", 1)
	assert_eq(g.get_current_site()["id"], "salt_flats")
	assert_eq(g.get_collection_progress()["discovered"], found, "collection survives")
	assert_eq(g.get_stats()["slabs_dug"], slabs, "lifetime stats survive")
	assert_gte(g.get_stats()["total_coins"], 4.0 * float(_d.prestige["base"]))
	assert_false(g.get_prestige_preview()["can_prestige"], "gain is spent")
	# the reset run equals a fresh game (fieldwork aside)
	var fresh: Node = _make()
	assert_eq(g.get_balance("coins"), 0.0)
	assert_eq(g.get_brush_power(), fresh.get_brush_power())
	assert_eq(g.get_income_per_sec(), 0.0)
	for cat: String in ["brush", "digger", "upgrade"]:
		var a: Array[Dictionary] = g.get_shop_items(cat)
		var b: Array[Dictionary] = fresh.get_shop_items(cat)
		for i: int in a.size():
			assert_eq(a[i]["owned"], b[i]["owned"], a[i]["id"])
			assert_eq(a[i]["cost"], b[i]["cost"], a[i]["id"])


func test_sites_unlock_in_order_and_loop() -> void:
	var g: Node = _make()
	var base: float = _d.prestige["base"]
	g._total_coins = 4.0 * base
	g.do_prestige()
	assert_eq(g.get_current_site()["id"], "salt_flats")
	g._total_coins = 25.0 * base
	g.do_prestige()
	assert_eq(g.get_current_site()["id"], "dry_creek", "loops after the last site")
	g._total_coins = 100.0 * base
	g.do_prestige()
	assert_eq(g.get_current_site()["id"], "salt_flats")
	assert_signal_emit_count(_bus, "prestige_done", 3)
	var specimens: Array[Dictionary] = g.get_collection("salt_flats")
	assert_eq(specimens.size(), 30)


func test_second_prestige_only_pays_the_increment() -> void:
	var g: Node = _make()
	var base: float = _d.prestige["base"]
	g._total_coins = 4.0 * base
	var first: float = g.get_prestige_preview()["fieldwork_gain"]
	g.do_prestige()
	g._total_coins = 9.0 * base
	var second: float = g.get_prestige_preview()["fieldwork_gain"]
	var expect: float = Prestige.total_for(9.0 * base, _d.prestige) - Prestige.total_for(4.0 * base, _d.prestige)
	assert_eq(second, expect)
	g.do_prestige()
	assert_eq(g.get_balance("fieldwork"), first + second)


func test_gain_multiplier_upgrade_and_income_bonus() -> void:
	var g: Node = _make()
	var base: float = _d.prestige["base"]
	g._total_coins = 4.0 * base
	var plain: float = g.get_prestige_preview()["fieldwork_gain"]
	g._owned["museum_grant"] = 5
	g._recalc()
	var boosted: float = g.get_prestige_preview()["fieldwork_gain"]
	assert_eq(boosted, floorf(Prestige.total_for(4.0 * base, _d.prestige) * 1.5))
	assert_gt(boosted, plain)
	g.do_prestige()
	assert_eq(g.get_shop_items("upgrade")[0]["owned"], 0, "upgrades reset")
	g._coins = 1000.0
	var fw: float = g.get_balance("fieldwork")
	g.buy("intern")
	var with_fw: float = g.get_income_per_sec()
	g._fieldwork = 0.0
	g._recalc()
	var without: float = g.get_income_per_sec()
	assert_gt(without, 0.0)
	assert_almost_eq(with_fw / without, 1.0 + fw * float(_d.prestige["per_fieldwork_income_mult"]), 1e-9)


func test_prestige_available_signal_and_persistence() -> void:
	var path: String = "user://test_prestige_persist.json"
	var g: Node = _make(path)
	g._total_coins = 4.0 * float(_d.prestige["base"])
	g.advance(1.0)
	assert_signal_emit_count(_bus, "prestige_available_changed", 1)
	assert_eq(get_signal_parameters(_bus, "prestige_available_changed", 0), [true])
	g.advance(3.0)
	assert_signal_emit_count(_bus, "prestige_available_changed", 1, "only on change")
	g.do_prestige()
	g.save_now()
	var reloaded: Node = _make(path)
	assert_eq(reloaded.get_balance("fieldwork"), g.get_balance("fieldwork"))
	assert_eq(reloaded.get_current_site()["id"], "salt_flats")
	assert_false(reloaded.get_prestige_preview()["can_prestige"], "basis persisted")


func test_huge_lifetime_is_finite() -> void:
	var g: Node = _make()
	g._total_coins = 1e299
	var prev: Dictionary = g.get_prestige_preview()
	assert_true(is_finite(prev["fieldwork_gain"]))
	g.do_prestige()
	assert_true(is_finite(g.get_balance("fieldwork")))
	g.advance(3.0)
	assert_true(is_finite(g.get_income_per_sec()))
