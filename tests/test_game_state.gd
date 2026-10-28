extends GutTest

const GS: GDScript = preload("res://src/autoload/game_state.gd")
const BUS: GDScript = preload("res://src/autoload/event_bus.gd")
const T0: float = 1700000000.0
const HOUR: float = 3600.0

var _bus: Node
var _d: GameData
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


func _make(path: String = "", now: float = T0, seed_value: int = 1) -> Node:
	if path == "":
		path = "user://test_gs_%d.json" % Time.get_ticks_usec()
	_paths.append(path)
	var g: Node = GS.new()
	g.bus = _bus
	g.save_path = path
	g.rng_seed = seed_value
	g.now_unix = now
	g.offline_emit_delay = 0.0
	add_child_autofree(g)
	return g


## Pins digger slab rates so tests do not depend on balance tuning.
func _pin_rates(g: Node) -> void:
	var rates: Array[float] = [0.02, 0.12, 0.7, 3.5, 10.0, 25.0]
	for i: int in rates.size():
		g._data.diggers[i]["slabs_per_sec"] = rates[i]
	g._recalc()


func _farm(g: Node, target: float) -> void:
	for _i: int in 5000:
		if g.get_balance("coins") >= target:
			return
		var slab: Dictionary = g.start_new_slab()
		g.report_brush_progress(slab["id"], 1.0)
	fail_test("could not farm %s coins" % target)


func _param(signal_name: String, index: int) -> Dictionary:
	return get_signal_parameters(_bus, signal_name, index)[0]


func test_fresh_boot() -> void:
	var g: Node = _make()
	assert_eq(g.get_balance("coins"), 0.0)
	assert_eq(g.get_balance("fieldwork"), 0.0)
	assert_eq(g.get_balance("nonsense"), 0.0)
	assert_eq(g.get_income_per_sec(), 0.0)
	assert_eq(g.get_brush_power(), 1.0)
	assert_eq(g.get_current_site()["id"], "dry_creek")
	assert_eq(g.get_stats(), {"slabs_dug": 0, "play_seconds": 0.0, "total_coins": 0.0})
	assert_eq(g.get_collection().size(), 60)
	assert_eq(g.get_collection("salt_flats").size(), 30)
	assert_eq(g.get_collection_progress()["discovered"], 0)


func test_shop_items_have_every_contract_field() -> void:
	var g: Node = _make()
	var keys: Array = ["id", "category", "name", "desc", "icon", "owned", "max_owned", "cost",
		"affordable", "locked", "unlock_text", "effect_text"]
	var counts: Dictionary = {"brush": 8, "digger": 6, "upgrade": 19}
	for cat: String in counts:
		var items: Array[Dictionary] = g.get_shop_items(cat)
		assert_eq(items.size(), counts[cat], cat)
		for it: Dictionary in items:
			for k: String in keys:
				assert_true(it.has(k), "%s missing %s" % [it["id"], k])
			assert_ne(it["effect_text"], "", "%s effect_text" % it["id"])
			assert_eq(it["category"], cat)
	assert_eq(g.get_shop_items("bogus").size(), 0)
	var brushes: Array[Dictionary] = g.get_shop_items("brush")
	assert_eq(brushes[0]["owned"], 1)
	assert_eq(brushes[0]["max_owned"], 1)
	assert_true(brushes[2]["locked"])
	assert_eq(brushes[2]["unlock_text"], "Requires Sable Brush")
	var diggers: Array[Dictionary] = g.get_shop_items("digger")
	assert_false(diggers[0]["locked"])
	assert_eq(diggers[0]["max_owned"], -1)
	assert_false(diggers[0]["affordable"])
	assert_eq(diggers[1]["unlock_text"], "Requires Intern")
	assert_eq(g.get_shop_items("upgrade")[2]["unlock_text"], "Requires 1 fieldwork")


func test_slab_reveal_flow_and_guards() -> void:
	var g: Node = _make()
	var slab: Dictionary = g.start_new_slab()
	assert_signal_emit_count(_bus, "slab_started", 1)
	assert_eq(slab["reveal_threshold"], 0.85)
	assert_eq(slab["rock_tint"], g.get_current_site()["rock_tint"])
	g.report_brush_progress(slab["id"], 0.5)
	g.report_brush_progress(slab["id"], NAN)
	assert_signal_emit_count(_bus, "slab_revealed", 0)
	g.report_brush_progress(slab["id"], 0.85)
	g.report_brush_progress(slab["id"], 1.0)
	g.report_brush_progress(999, 1.0)
	assert_signal_emit_count(_bus, "slab_revealed", 1)
	var res: Dictionary = _param("slab_revealed", 0)
	assert_eq(res["slab_id"], slab["id"])
	assert_eq(res["specimen_id"], slab["specimen_id"])
	assert_true(res["is_new"])
	assert_eq(g.get_balance("coins"), res["value"])
	assert_eq(g.get_stats()["slabs_dug"], 1)
	assert_signal_emit_count(_bus, "specimen_discovered", 1)
	var spec: Dictionary = g.get_specimen(slab["specimen_id"])
	assert_true(spec["discovered"])
	assert_ne(spec["name"], "???")
	assert_eq(g.get_collection_progress()["discovered"], 1)
	assert_eq(g.get_specimen("ghost"), {})


func test_buy_validation() -> void:
	var g: Node = _make()
	assert_false(g.buy("intern"), "unaffordable")
	assert_false(g.buy("nope"))
	assert_false(g.buy("soft_bristle"), "max_owned reached")
	assert_false(g.buy("sable", 0))
	assert_false(g.buy("sable", -2))
	assert_false(g.buy("field_crew"), "locked behind intern")
	_farm(g, 400.0)
	assert_false(g.buy("sable", 2), "more than max_owned")
	assert_true(g.buy("sable"))
	assert_eq(g.get_brush_power(), 1.25)
	assert_false(g.buy("sable"), "already owned")
	assert_eq(g.get_stats()["total_coins"] >= g.get_balance("coins"), true)


func test_buy_cost_and_max_qty() -> void:
	var g: Node = _make()
	_farm(g, 3000.0)
	var before: float = g.get_balance("coins")
	assert_almost_eq(g.get_buy_cost("intern", 1), 180.0, 1e-9)
	assert_almost_eq(g.get_buy_cost("intern", 3), Economy.bulk_cost(180.0, 1.14, 0, 3), 1e-9)
	var max_cost: float = g.get_buy_cost("intern", -1)
	assert_lte(max_cost, before)
	assert_true(g.buy("intern", -1))
	var owned: int = g.get_shop_items("digger")[0]["owned"]
	assert_gt(owned, 3)
	assert_almost_eq(g.get_balance("coins"), before - max_cost, 1e-6)
	assert_false(g.buy("intern", -1), "nothing left to afford")
	assert_eq(g.get_buy_cost("ghost", 1), 0.0)


func test_scripted_play_through() -> void:
	var g: Node = _make()
	_pin_rates(g)
	_farm(g, 1400.0)
	assert_true(g.buy("sable"))
	assert_signal_emit_count(_bus, "item_purchased", 1)
	assert_eq(get_signal_parameters(_bus, "item_purchased", 0), ["sable", 1])
	assert_true(g.buy("intern", 5))
	assert_eq(get_signal_parameters(_bus, "item_purchased", 1), ["intern", 5])
	assert_signal_emit_count(_bus, "income_changed", 1)
	var income: float = g.get_income_per_sec()
	assert_gt(income, 0.0)
	assert_almost_eq(_bus_income(), income, 1e-9)
	var coins_before: float = g.get_balance("coins")
	g.advance(36.0)
	var slabs: int = 0
	var coins: float = 0.0
	for i: int in get_signal_emit_count(_bus, "auto_dig_tick"):
		var s: Dictionary = _param("auto_dig_tick", i)
		slabs += s["count"]
		coins += s["coins"]
		assert_gt(s["count"], 0)
		assert_true(s["best_find"].has("specimen_id"))
	assert_eq(slabs, 3, "0.1 slabs/s x 36 s")
	assert_almost_eq(g.get_balance("coins") - coins_before, coins + float(g._summary["coins"]), 1e-6)
	assert_almost_eq(g.get_balance("coins") - coins_before, income * 36.0, income * 0.2, "smooth income")
	assert_almost_eq(g.get_stats()["play_seconds"], 36.0, 1e-6)


func _bus_income() -> float:
	return get_signal_parameters(_bus, "income_changed", 0)[0]


func test_auto_dig_summary_at_most_once_per_second() -> void:
	var g: Node = _make()
	_pin_rates(g)
	_farm(g, 100000.0)
	g.buy("intern", 1)
	g.buy("field_crew", 5)
	g.buy("mini_excavator", 5)
	assert_gt(g.get_income_per_sec(), 1.0)
	g.advance(10.0)
	var n: int = get_signal_emit_count(_bus, "auto_dig_tick")
	assert_between(n, 9, 10)


func test_currency_throttle() -> void:
	var g: Node = _make()
	_farm(g, 30.0)
	var n: int = get_signal_emit_count(_bus, "currency_changed")
	assert_lt(n, 5, "many credits in one instant are coalesced")
	g.advance(0.1)
	var after: int = get_signal_emit_count(_bus, "currency_changed")
	assert_gte(after, n)
	var last: Array = get_signal_parameters(_bus, "currency_changed", after - 1)
	assert_eq(last[0], "coins")
	assert_almost_eq(last[1], g.get_balance("coins"), 1e-9, "flushed value is current")


func test_save_and_load_roundtrip() -> void:
	var path: String = "user://test_gs_roundtrip.json"
	var a: Node = _make(path)
	_farm(a, 800.0)
	a.buy("sable")
	a.buy("intern", 2)
	a.advance(5.0)
	a.save_now()
	assert_signal_emit_count(_bus, "save_completed", 1)
	var b: Node = _make(path, T0 + 1.0)
	assert_eq(b.get_balance("coins"), a.get_balance("coins"))
	assert_eq(b.get_stats(), a.get_stats())
	assert_eq(b.get_brush_power(), a.get_brush_power())
	assert_eq(b.get_income_per_sec(), a.get_income_per_sec())
	assert_eq(b.get_collection_progress(), a.get_collection_progress())
	assert_eq(b.get_shop_items("digger")[0]["owned"], 2)


func test_loading_hostile_save_is_tolerated() -> void:
	var path: String = "user://test_gs_hostile.json"
	_paths.append(path)
	var hostile: Dictionary = {
		"version": 1, "coins": -50.0, "fieldwork": "abc", "owned": {"intern": -4, "ghost": 9, "sable": 7},
		"discovered": ["ghost", "trilobite"], "site_id": "mars", "total_coins": 1e400, "pity": "nope",
	}
	assert_true(SaveSystem.new(path).save(hostile))
	var g: Node = _make(path)
	assert_eq(g.get_balance("coins"), 0.0)
	assert_eq(g.get_current_site()["id"], "dry_creek")
	assert_eq(g.get_collection_progress()["discovered"], 1)
	assert_eq(g.get_shop_items("brush")[1]["owned"], 1, "clamped to max_owned")
	assert_eq(g.get_shop_items("digger")[0]["owned"], 0)


func test_offline_report_on_boot() -> void:
	var path: String = "user://test_gs_offline.json"
	var a: Node = _make(path)
	_farm(a, 1400.0)
	a.buy("intern", 5)
	a.buy("mini_excavator", 1)
	a.save_now()
	var income: float = a.get_income_per_sec()
	assert_gt(income, 0.0)
	var before: float = a.get_balance("coins")
	var b: Node = _make(path, T0 + 3.0 * HOUR)
	var eff: float = float(_d.config["offline_efficiency"])
	assert_signal_emit_count(_bus, "offline_report_ready", 1)
	var rep: Dictionary = _param("offline_report_ready", 0)
	assert_almost_eq(rep["seconds"], 3.0 * HOUR, 1e-6)
	assert_almost_eq(rep["coins"], b.get_income_per_sec() * 3.0 * HOUR * eff, income)
	assert_false(rep["capped"])
	assert_gte(rep["slabs"], 0)
	assert_eq(b.get_balance("coins"), before, "nothing credited before claim")
	b.claim_offline_report()
	assert_almost_eq(b.get_balance("coins"), before + rep["coins"], 1e-6)
	b.claim_offline_report()
	assert_almost_eq(b.get_balance("coins"), before + rep["coins"], 1e-6, "second claim is a no-op")
	for id: String in rep["new_discoveries"]:
		assert_true(b.get_specimen(id)["discovered"])


func test_offline_cap_negative_delta_min_and_upgrade() -> void:
	var path: String = "user://test_gs_offcap.json"
	var a: Node = _make(path)
	_farm(a, 3500.0)
	a.buy("intern", 3)
	a.buy("camp_tent")
	a.save_now()
	_make(path, T0 + 20.0 * HOUR)
	assert_almost_eq(_param("offline_report_ready", 0)["seconds"], 10.0 * HOUR, 1e-6, "8h + 2h tent")
	assert_true(_param("offline_report_ready", 0)["capped"])
	var n: int = get_signal_emit_count(_bus, "offline_report_ready")
	_make(path, T0 - 5000.0)
	_make(path, T0 + 30.0)
	assert_signal_emit_count(_bus, "offline_report_ready", n)


func test_pause_resume_flow() -> void:
	var g: Node = _make()
	_farm(g, 500.0)
	g.buy("intern", 2)
	g.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_signal_emit_count(_bus, "save_completed", 1)
	g.now_unix = T0 + 2.0 * HOUR
	g.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_signal_emit_count(_bus, "offline_report_ready", 1)
	assert_almost_eq(_param("offline_report_ready", 0)["seconds"], 2.0 * HOUR, 1e-6)
	g.now_unix = T0 + 3.0 * HOUR
	g.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var merged: Dictionary = _param("offline_report_ready", 1)
	assert_almost_eq(merged["seconds"], 3.0 * HOUR, 1e-6, "unclaimed reports merge")
	g.now_unix = T0 - 9999.0
	g.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_signal_emit_count(_bus, "offline_report_ready", 2, "clock rollback earns nothing")


func test_autosave_interval() -> void:
	var g: Node = _make()
	g.advance(29.0)
	assert_signal_emit_count(_bus, "save_completed", 0)
	g.advance(2.0)
	assert_signal_emit_count(_bus, "save_completed", 1)


func test_reset_all_data() -> void:
	var path: String = "user://test_gs_reset.json"
	var g: Node = _make(path)
	_farm(g, 300.0)
	g.save_now()
	g.reset_all_data()
	assert_eq(g.get_balance("coins"), 0.0)
	assert_eq(g.get_collection_progress()["discovered"], 0)
	assert_eq(g.get_stats()["total_coins"], 0.0)
	assert_false(FileAccess.file_exists(path))
	var fresh: Node = _make(path)
	assert_eq(fresh.get_balance("coins"), 0.0)


func test_deterministic_with_same_seed() -> void:
	var a: Node = _make("", T0, 77)
	var b: Node = _make("", T0, 77)
	for _i: int in 50:
		assert_eq(a.start_new_slab()["specimen_id"], b.start_new_slab()["specimen_id"])


func test_active_slab_window_is_bounded() -> void:
	var g: Node = _make()
	var first: Dictionary = g.start_new_slab()
	for _i: int in GS.MAX_ACTIVE_SLABS + 2:
		g.start_new_slab()
	g.report_brush_progress(first["id"], 1.0)
	assert_signal_emit_count(_bus, "slab_revealed", 0, "evicted slab is unknown")


func test_huge_numbers_stay_finite() -> void:
	var g: Node = _make()
	g._coins = 1e299
	g._owned["drill_rig"] = 1000000
	g._recalc()
	assert_true(is_finite(g.get_income_per_sec()))
	g.advance(3.0)
	assert_true(is_finite(g.get_balance("coins")))
	assert_lte(g.get_balance("coins"), Economy.MAX_VALUE)
	assert_true(is_finite(g.get_shop_items("digger")[5]["cost"]))
