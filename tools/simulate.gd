extends SceneTree
## Balance simulator. Run: godot --headless -s tools/simulate.gd -- --hours 8
## Options: --hours N  --active-minutes N  --checkin-minutes N  --seed N  --policy checkin|active
##          --prestiges N (auto-prestige when available)  --stress (10 forced prestiges over --hours, NaN check)

const GS: GDScript = preload("res://src/autoload/game_state.gd")
const BUS: GDScript = preload("res://src/autoload/event_bus.gd")
const T_BASE: float = 1.7e9
const SLAB_SECONDS: float = 6.0
const STEP_MAX: float = 30.0
const BUY_INTERVAL: float = 3.0
const MILESTONE_FRACTIONS: Array[float] = [0.25, 0.5, 1.0]
const CATEGORIES: Array[String] = ["brush", "digger", "upgrade"]

var hours: float = 8.0
var active_minutes: float = 20.0
var checkin_minutes: float = 30.0
var seed_value: int = 1
var policy: String = "checkin"
var max_prestiges: int = 0
var stress: bool = false
var list_minutes: float = 0.0

var gs: Node
var bus: Node
var data: GameData
var t: float = 0.0
var run_start: float = 0.0
var last_buy: float = -999.0
var last_poll: float = -999.0
var prestiges: int = 0
var events: Array = []
var purchases: Array = []
var tier_seen: Dictionary = {}
var flags: Dictionary = {}
var site_marks: Dictionary = {}
var gens: Dictionary = {}
var problems: Array[String] = []
var snapshots: Array = []
var slabs_manual: int = 0
var slabs_auto: int = 0
var run_slabs: int = 0


func _initialize() -> void:
	_parse_args()
	data = GameData.load_dir()
	bus = BUS.new()
	root.add_child(bus)
	gs = GS.new()
	gs.bus = bus
	gs.save_path = "user://sim_save.json"
	gs.rng_seed = seed_value
	gs.now_unix = T_BASE
	gs.offline_emit_delay = 0.0
	root.add_child(gs)
	await process_frame  # lets GameState._ready boot
	gs._data.config["autosave_seconds"] = 1e18
	bus.slab_revealed.connect(_on_reveal)
	bus.prestige_done.connect(_on_prestige)
	bus.auto_dig_tick.connect(_on_auto)
	_run()
	_report()
	SaveSystem.new("user://sim_save.json").delete_all()
	quit()


func _parse_args() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < a.size():
		match a[i]:
			"--hours": hours = float(a[i + 1]); i += 1
			"--active-minutes": active_minutes = float(a[i + 1]); i += 1
			"--checkin-minutes": checkin_minutes = float(a[i + 1]); i += 1
			"--seed": seed_value = int(a[i + 1]); i += 1
			"--policy": policy = a[i + 1]; i += 1
			"--prestiges": max_prestiges = int(a[i + 1]); i += 1
			"--list-purchases": list_minutes = float(a[i + 1]); i += 1
			"--stress": stress = true
		i += 1


# ------------------------------------------------------------------ main loop

func _run() -> void:
	var end: float = hours * 3600.0
	while t < end:
		var in_active: bool = policy == "active" or (t - run_start) < active_minutes * 60.0
		if in_active:
			var slab: Dictionary = gs.start_new_slab()
			gs.report_brush_progress(slab["id"], 1.0)
			slabs_manual += 1
			run_slabs += 1
			_step(SLAB_SECONDS / gs.get_brush_power(), "active")
		else:
			_away(minf(checkin_minutes * 60.0, end - t))
			_buy_best("away")
		if stress:
			_stress_tick(end)


func _step(dt: float, mode: String) -> void:
	var remaining: float = dt
	while remaining > 0.0:
		var d: float = minf(remaining, STEP_MAX)
		gs.advance(d)
		t += d
		gs.now_unix = T_BASE + t
		remaining -= d
	if t - last_buy >= BUY_INTERVAL:
		last_buy = t
		_buy_best(mode)
	if t - last_poll >= 60.0 or last_poll < 0.0:
		last_poll = t
		_poll()
	_maybe_prestige()


func _away(seconds: float) -> void:
	gs.save_now()
	t += seconds
	gs.now_unix = T_BASE + t
	gs.check_offline()
	gs.claim_offline_report()
	_poll()
	_maybe_prestige()


func _maybe_prestige() -> void:
	var prev: Dictionary = gs.get_prestige_preview()
	if prev["can_prestige"] and not flags.has("avail_%d" % prestiges):
		flags["avail_%d" % prestiges] = true
		events.append([t, "prestige #%d available (gain %s)" % [prestiges + 1, NumFormat.fmt(prev["fieldwork_gain"])]])
	if prev["can_prestige"] and prestiges < max_prestiges:
		gs.do_prestige()


func _on_auto(summary: Dictionary) -> void:
	slabs_auto += int(summary["count"])
	run_slabs += int(summary["count"])


func _on_prestige(info: Dictionary) -> void:
	prestiges += 1
	run_slabs = 0
	run_start = t
	events.append([t, "PRESTIGE #%d -> %s, fieldwork %s" % [prestiges, info["site_id"], NumFormat.fmt(info["total_fieldwork"])]])


func _on_reveal(res: Dictionary) -> void:
	var key: String = "%s/%s" % [gs.get_current_site()["id"], res["rarity"]]
	if not tier_seen.has(key):
		tier_seen[key] = t
		events.append([t, "first %s find (%s)" % [res["rarity"], res["name"]]])


# ------------------------------------------------------------------ buying policy

func _owned() -> Dictionary:
	var o: Dictionary = {}
	for cat: String in CATEGORIES:
		for it: Dictionary in gs.get_shop_items(cat):
			o[it["id"]] = it["owned"]
	return o


func _gen_for(site_id: String) -> SlabGenerator:
	if not gens.has(site_id):
		var r: RandomNumberGenerator = RandomNumberGenerator.new()
		gens[site_id] = SlabGenerator.new(data.config, data.specimens_for_site(site_id), r)
	return gens[site_id]


## Estimated coins/sec for an ownership set. mode "active": auto + brushing; "away": auto x offline efficiency.
func _eff(owned: Dictionary, fw: float, site_id: String, mode: String) -> float:
	var ups: Array[Dictionary] = data.upgrades
	var speed: float = Economy.upgrade_multiplier(owned, ups, "digger_speed_mult")
	var click: float = Economy.upgrade_multiplier(owned, ups, "click_value_mult")
	var luck: float = Economy.upgrade_bonus(owned, ups, "rarity_luck")
	var fwm: float = Economy.fieldwork_multiplier(fw, float(data.prestige["per_fieldwork_income_mult"]))
	var era: Dictionary = {}
	for s: Dictionary in data.specimens_for_site(site_id):
		era[s["era"]] = Economy.upgrade_multiplier(owned, ups, "value_mult_era", s["era"])
	var gen: SlabGenerator = _gen_for(site_id)
	var amult: float = float(data.config["auto_dig_value_mult"])
	var auto: float = Economy.income_per_sec(Economy.slabs_per_sec(owned, data.diggers, speed), gen.expected_value(luck, fwm * amult, era), 1.0)
	if mode == "active":
		var power: float = Economy.brush_power(owned, data.tools)
		return auto + gen.expected_value(luck, click * fwm, era) / (SLAB_SECONDS / power)
	var eff: float = clampf(float(data.config["offline_efficiency"]) + Economy.upgrade_bonus(owned, ups, "offline_efficiency_add"), 0.0, 1.0)
	return auto * eff


func _buy_best(mode: String) -> void:
	for _n: int in 2000:
		var owned: Dictionary = _owned()
		var fw: float = gs.get_balance("fieldwork")
		var site: String = gs.get_current_site()["id"]
		var cur: float = _eff(owned, fw, site, mode)
		var best_id: String = ""
		var best_pay: float = INF
		var best_cost: float = 0.0
		for cat: String in CATEGORIES:
			for it: Dictionary in gs.get_shop_items(cat):
				if it["locked"] or (it["max_owned"] >= 0 and it["owned"] >= it["max_owned"]):
					continue
				var o2: Dictionary = owned.duplicate()
				o2[it["id"]] = it["owned"] + 1
				var delta: float = _eff(o2, fw, site, mode) - cur
				if delta > 1e-12 and it["cost"] / delta < best_pay:
					best_pay = it["cost"] / delta
					best_id = it["id"]
					best_cost = it["cost"]
		if best_id == "" or gs.get_balance("coins") < best_cost:
			return
		gs.buy(best_id)
		purchases.append([t, best_id])
		var cat_of: String = data.item_by_id[best_id]["category"]
		_flag_once("first_" + cat_of, "first %s bought (%s)" % [cat_of, best_id])
		if cat_of == "brush" and _owned_count("brush") >= 5:
			_flag_once("brushes5", "5 brushes owned")


func _owned_count(cat: String) -> int:
	var n: int = 0
	for it: Dictionary in gs.get_shop_items(cat):
		n += 1 if it["owned"] > 0 else 0
	return n


func _flag_once(key: String, text: String) -> void:
	if not flags.has(key):
		flags[key] = t
		events.append([t, text])


# ------------------------------------------------------------------ polling & checks

func _poll() -> void:
	var intern_cost: float = float(data.diggers[0]["base_cost"])
	if gs.get_stats()["total_coins"] >= intern_cost:
		_flag_once("digger_affordable", "first digger affordable")
	var site: String = gs.get_current_site()["id"]
	var list: Array[Dictionary] = gs.get_collection(site)
	var found: int = 0
	for e: Dictionary in list:
		found += 1 if e["discovered"] else 0
	var frac: float = float(found) / float(list.size())
	for m: float in MILESTONE_FRACTIONS:
		var key: String = "%s_%d" % [site, int(m * 100.0)]
		if frac >= m - 1e-9 and not site_marks.has(key):
			site_marks[key] = t
			events.append([t, "%s collection %d%%" % [site, int(m * 100.0)]])
	for v: float in [gs.get_balance("coins"), gs.get_balance("fieldwork"), gs.get_income_per_sec()]:
		if not is_finite(v) or v < 0.0:
			problems.append("bad value %s at t=%d" % [v, int(t)])
	for cat: String in CATEGORIES:
		for it: Dictionary in gs.get_shop_items(cat):
			if not is_finite(it["cost"]) or it["cost"] < 0.0:
				problems.append("bad cost %s: %s" % [it["id"], it["cost"]])
	if int(t / 3600.0) > snapshots.size():
		_snapshot()


func _snapshot() -> void:
	var owned: Dictionary = _owned()
	var site: String = gs.get_current_site()["id"]
	var fw: float = gs.get_balance("fieldwork")
	var active: float = _eff(owned, fw, site, "active")
	var away: float = _eff(owned, fw, site, "away")
	var cap_h: float = float(data.config["offline_cap_hours"])
	snapshots.append({"h": snapshots.size() + 1, "income": gs.get_income_per_sec(), "active": active, "life": gs.get_stats()["total_coins"], "run_slabs": run_slabs,
		"offline_equiv_h": (away * cap_h) / maxf(active, 1e-9)})


func _stress_tick(end: float) -> void:
	var cycle: float = end / 10.0
	if t >= cycle * float(prestiges + 1) and prestiges < 10:
		gs._total_coins = maxf(gs._total_coins, float(data.prestige["base"]) * pow(10.0, float(prestiges + 2)))
		gs.do_prestige()


# ------------------------------------------------------------------ report

func _report() -> void:
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("== Dust & Bones simulation: %s h, policy %s, active %d min, check-in %d min, seed %d ==" % [NumFormat.fmt(hours), policy, int(active_minutes), int(checkin_minutes), seed_value])
	for e: Array in events:
		print("%s  %s" % [_hms(e[0]), e[1]])
	var first_hour: Array = []
	for p: Array in purchases:
		if p[0] <= 3600.0:
			first_hour.append(p[0])
	for k: String in tier_seen:
		if tier_seen[k] <= 3600.0:
			first_hour.append(tier_seen[k])
	first_hour.sort()
	var gap: float = 0.0
	var prev: float = 0.0
	for x: float in first_hour:
		if x - prev > 360.0:
			print("  gap %s -> %s (%.1f min)" % [_hms(prev), _hms(x), (x - prev) / 60.0])
		gap = maxf(gap, x - prev)
		prev = x
	print("purchases: %d total, %d in first 5 min; longest purchase/tier gap in hour 1: %.1f min" % [purchases.size(), _count_before(300.0), gap / 60.0])
	for p: Array in purchases:
		if p[0] <= list_minutes * 60.0:
			print("  buy %s %s" % [_hms(p[0]), p[1]])
	for s: Dictionary in snapshots:
		print("hour %2d: income %s/s (active %s/s), lifetime %s, run slabs %d, 8h-away = %.2f h of active play" % [s["h"], NumFormat.fmt(s["income"]), NumFormat.fmt(s["active"]), NumFormat.fmt(s["life"]), s["run_slabs"], s["offline_equiv_h"]])
	var st: Dictionary = gs.get_stats()
	print("final: coins %s, fieldwork %s, lifetime %s, prestiges %d" % [NumFormat.fmt(gs.get_balance("coins")), NumFormat.fmt(gs.get_balance("fieldwork")), NumFormat.fmt(st["total_coins"]), prestiges])
	print("numeric check: %s" % ("OK" if problems.is_empty() else "PROBLEMS " + str(problems.slice(0, 5))))


func _count_before(limit: float) -> int:
	var n: int = 0
	for p: Array in purchases:
		n += 1 if p[0] <= limit else 0
	return n


func _hms(sec: float) -> String:
	var s: int = int(sec)
	return "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
