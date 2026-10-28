extends Node
## Thin facade over src/core/*: owns the tick loop, save/lifecycle and EventBus emissions.

const EventBusType: GDScript = preload("res://src/autoload/event_bus.gd")

const CURRENCY_COINS: String = "coins"
const CURRENCY_FIELDWORK: String = "fieldwork"
const TICK_DT: float = 0.1
const SUMMARY_INTERVAL: float = 1.0
const CURRENCY_EMIT_INTERVAL: float = 0.1
const MAX_TICKS_PER_CALL: int = 600
const MAX_FRAME_DELTA: float = 5.0
const MAX_ACTIVE_SLABS: int = 8
const MAX_COUNT: float = 4.0e18
const EPS: float = 1e-9
const DEFAULT_OFFLINE_EMIT_DELAY: float = 0.5

# Injection points (tests, simulator). Defaults are production values.
var bus: EventBusType = null
var save_path: String = "user://save.json"
var data_dir: String = GameData.DATA_DIR
var rng_seed: int = 0  # 0 = randomize
var now_unix: float = -1.0  # >= 0 overrides the wall clock
var offline_emit_delay: float = DEFAULT_OFFLINE_EMIT_DELAY

var _data: GameData
var _rng: RandomNumberGenerator
var _gen: SlabGenerator
var _collection: Collection
var _save: SaveSystem
var _eras: Array[String] = []

var _coins: float = 0.0
var _fieldwork: float = 0.0
var _total_coins: float = 0.0
var _slabs_dug: int = 0
var _play_seconds: float = 0.0
var _owned: Dictionary = {}
var _site_id: String = ""
var _next_slab_id: int = 0
var _slab_frac: float = 0.0
var _fieldwork_basis: float = 0.0
var _prestige_avail: bool = false
var _pending_offline: Dictionary = {}
var _last_active: float = 0.0

var _active: Dictionary = {}
var _acc: float = 0.0
var _clock_s: float = 0.0
var _summary_t: float = 0.0
var _autosave_t: float = 0.0
var _last_emit: Dictionary = {}
var _dirty: Dictionary = {}
var _summary: Dictionary = {}

var _speed_mult: float = 1.0
var _click_mult: float = 1.0
var _fw_mult: float = 1.0
var _luck: float = 0.0
var _era_mult: Dictionary = {}
var _slabs_ps: float = 0.0
var _auto_value_mult: float = 1.0
var _ev_auto: float = 0.0
var _income: float = 0.0
var _booted: bool = false


func _ready() -> void:
	boot()


func boot() -> void:
	if bus == null:
		bus = get_node("/root/EventBus")
	_data = GameData.load_dir(data_dir)
	var errs: Array[String] = _data.validate()
	if not errs.is_empty():
		push_error("Data validation failed: %s" % str(errs))
	_rng = RandomNumberGenerator.new()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_save = SaveSystem.new(save_path)
	for s: Dictionary in _data.specimens:
		if not _eras.has(s["era"]):
			_eras.append(s["era"])
	_new_game()
	var saved: Dictionary = _save.load_game()
	var pity: Dictionary = {}
	if not saved.is_empty():
		pity = _apply_state(saved)
	_build_generator(pity)
	_recalc()
	_prestige_avail = _prestige_gain() >= 1.0
	_booted = true
	check_offline()


func _process(delta: float) -> void:
	if _booted:
		advance(minf(delta, MAX_FRAME_DELTA))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			save_now()
		NOTIFICATION_APPLICATION_RESUMED:
			if _booted:
				check_offline()


# ---------------------------------------------------------------- tick loop

## Advances game time. _process calls this; tests and the simulator call it directly.
func advance(delta: float) -> void:
	if not _booted or is_nan(delta) or delta <= 0.0:
		return
	_acc += delta
	var ticks: int = 0
	while _acc >= TICK_DT - EPS and ticks < MAX_TICKS_PER_CALL:
		_acc = maxf(_acc - TICK_DT, 0.0)
		_tick(TICK_DT)
		ticks += 1
	if _acc >= TICK_DT - EPS:  # huge delta: one coarse step instead of unbounded work
		var rest: float = _acc
		_acc = 0.0
		_tick(rest)


func _tick(dt: float) -> void:
	_clock_s += dt
	_play_seconds += dt
	_auto_dig(dt)
	_summary_t += dt
	if _summary_t >= SUMMARY_INTERVAL - EPS:
		_flush_summary()
		_update_prestige_available()
	_flush_currency()
	_autosave_t += dt
	if _autosave_t >= float(_data.config["autosave_seconds"]):
		save_now()


## Coins arrive smoothly (income x dt); slab rolls only decide discoveries and the best find.
func _auto_dig(dt: float) -> void:
	if _slabs_ps <= 0.0:
		return
	var coins: float = Economy.clamp_value(_income * dt)
	_credit(coins)
	_summary["coins"] += coins
	_slab_frac += _slabs_ps * dt
	var whole: float = floorf(_slab_frac)
	if whole < 1.0:
		return
	whole = minf(whole, MAX_COUNT)
	_slab_frac = maxf(_slab_frac - whole, 0.0) if _slab_frac < MAX_COUNT else 0.0
	var n: int = int(whole)
	var res: Dictionary = _gen.roll_many(n, _luck, int(_data.config["auto_dig_max_rolls"]))
	for id: String in res["counts"]:
		var spec: Dictionary = _data.specimen_by_id[id]
		var v: float = Economy.specimen_value(float(spec["base_value"]), _fw_mult * _auto_value_mult, float(_era_mult.get(spec["era"], 1.0)))
		if _collection.discover(id):
			_summary["new"].append(id)
			bus.specimen_discovered.emit(id)
		_consider_best(spec, v)
	_summary["count"] += n


func _consider_best(spec: Dictionary, value: float) -> void:
	var best: Dictionary = _summary["best"]
	var rank: int = GameData.RARITIES.find(spec["rarity"])
	if best.is_empty() or rank > int(best["rank"]) or (rank == int(best["rank"]) and value > float(best["value"])):
		_summary["best"] = {"rank": rank, "spec": spec, "value": value}


func _flush_summary() -> void:
	_summary_t = 0.0
	if int(_summary["count"]) <= 0:
		return  # coins keep accumulating until a summary with a find can be emitted
	var best: Dictionary = _summary["best"]
	var spec: Dictionary = best["spec"]
	bus.auto_dig_tick.emit({
		"count": _summary["count"], "coins": _summary["coins"],
		"best_find": {
			"slab_id": -1, "specimen_id": spec["id"], "name": spec["name"], "rarity": spec["rarity"],
			"era": spec["era"], "value": best["value"], "is_new": (_summary["new"] as Array).has(spec["id"]),
		},
		"new_discoveries": (_summary["new"] as Array).duplicate(),
	})
	_reset_summary()


func _reset_summary() -> void:
	_summary = {"count": 0, "coins": 0.0, "best": {}, "new": []}


# ---------------------------------------------------------------- currency

func _credit(amount: float) -> void:
	if amount <= 0.0:
		return
	_coins = Economy.clamp_value(_coins + amount)
	_total_coins = Economy.clamp_value(_total_coins + amount)
	_touch(CURRENCY_COINS)


## Throttled to <= 10 emissions/s per currency; deferred ones flush on the next tick.
func _touch(currency: String) -> void:
	if _clock_s - float(_last_emit.get(currency, -INF)) >= CURRENCY_EMIT_INTERVAL - EPS:
		_last_emit[currency] = _clock_s
		_dirty.erase(currency)
		bus.currency_changed.emit(currency, get_balance(currency))
	else:
		_dirty[currency] = true


func _flush_currency() -> void:
	for c: String in _dirty.keys():
		_touch(c)


func get_balance(currency: String) -> float:
	match currency:
		CURRENCY_COINS:
			return _coins
		CURRENCY_FIELDWORK:
			return _fieldwork
	return 0.0


func get_income_per_sec() -> float:
	return _income


func get_brush_power() -> float:
	return Economy.brush_power(_owned, _data.tools)


func get_current_site() -> Dictionary:
	return _site_dict(_data.site_by_id[_site_id])


# ---------------------------------------------------------------- slabs

func start_new_slab() -> Dictionary:
	var roll: Dictionary = _gen.roll(_luck)
	var spec: Dictionary = roll["specimen"]
	_next_slab_id += 1
	var slab: Dictionary = {
		"id": _next_slab_id, "specimen_id": spec["id"], "rarity": roll["rarity"],
		"hardness": roll["hardness"], "reveal_threshold": float(_data.config["reveal_threshold"]),
		"rock_tint": _data.site_by_id[_site_id]["rock_tint"],
	}
	_active[_next_slab_id] = spec
	while _active.size() > MAX_ACTIVE_SLABS:
		_active.erase(_active.keys()[0])
	bus.slab_started.emit(slab)
	return slab


func report_brush_progress(slab_id: int, fraction: float) -> void:
	if is_nan(fraction) or not _active.has(slab_id):
		return
	if fraction < float(_data.config["reveal_threshold"]):
		return
	var spec: Dictionary = _active[slab_id]
	_active.erase(slab_id)  # finished: later duplicate reports are ignored
	var value: float = _manual_value(spec)
	_credit(value)
	_slabs_dug += 1
	var is_new: bool = _collection.discover(spec["id"])
	bus.slab_revealed.emit({
		"slab_id": slab_id, "specimen_id": spec["id"], "name": spec["name"], "rarity": spec["rarity"],
		"era": spec["era"], "value": value, "is_new": is_new,
	})
	if is_new:
		bus.specimen_discovered.emit(spec["id"])


func _manual_value(spec: Dictionary) -> float:
	return Economy.specimen_value(float(spec["base_value"]), _click_mult * _fw_mult, float(_era_mult.get(spec["era"], 1.0)))


# ---------------------------------------------------------------- shop

func get_shop_items(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _data.item_by_id:
		var entry: Dictionary = _data.item_by_id[id]
		if entry["category"] == category:
			out.append(_shop_entry(id, entry))
	return out


func get_buy_cost(item_id: String, qty: int) -> float:
	var entry: Dictionary = _data.item_by_id.get(item_id, {})
	if entry.is_empty():
		return 0.0
	var def: Dictionary = entry["def"]
	var owned: int = int(_owned.get(item_id, 0))
	var room: int = _room(entry, owned)
	var n: int = qty
	if qty == -1:
		n = maxi(Economy.max_affordable(float(def["base_cost"]), float(def["cost_growth"]), owned, _coins, room), 1)
	if room >= 0:
		n = mini(n, room)
	return Economy.bulk_cost(float(def["base_cost"]), float(def["cost_growth"]), owned, n)


func buy(item_id: String, qty: int = 1) -> bool:
	var entry: Dictionary = _data.item_by_id.get(item_id, {})
	if entry.is_empty() or qty == 0 or qty < -1:
		return false
	var def: Dictionary = entry["def"]
	if _is_locked(def):
		return false
	var owned: int = int(_owned.get(item_id, 0))
	var room: int = _room(entry, owned)
	if room == 0 or (room > 0 and qty > room):
		return false
	var base: float = float(def["base_cost"])
	var growth: float = float(def["cost_growth"])
	var n: int = Economy.max_affordable(base, growth, owned, _coins, room) if qty == -1 else qty
	if n <= 0:
		return false
	var total: float = Economy.bulk_cost(base, growth, owned, n)
	if total > _coins:
		return false
	_coins = maxf(_coins - total, 0.0)
	_owned[item_id] = owned + n
	_recalc()
	bus.item_purchased.emit(item_id, owned + n)
	_touch(CURRENCY_COINS)
	return true


func _room(entry: Dictionary, owned: int) -> int:
	var cap: int = _max_owned(entry)
	return -1 if cap < 0 else maxi(cap - owned, 0)


func _max_owned(entry: Dictionary) -> int:
	if entry["category"] == "brush":
		return 1
	return int(entry["def"].get("max_owned", -1))


func _is_locked(def: Dictionary) -> bool:
	var req: Dictionary = def.get("requires", {})
	if req.has("item_id") and int(_owned.get(req["item_id"], 0)) <= 0:
		return true
	return req.has("fieldwork") and _fieldwork < float(req["fieldwork"])


func _unlock_text(def: Dictionary) -> String:
	var req: Dictionary = def.get("requires", {})
	var parts: Array[String] = []
	if req.has("item_id") and int(_owned.get(req["item_id"], 0)) <= 0:
		parts.append("Requires %s" % _data.item_by_id[req["item_id"]]["def"]["name"])
	if req.has("fieldwork") and _fieldwork < float(req["fieldwork"]):
		parts.append("Requires %s fieldwork" % NumFormat.fmt(float(req["fieldwork"])))
	return ", ".join(parts)


func _shop_entry(id: String, entry: Dictionary) -> Dictionary:
	var def: Dictionary = entry["def"]
	var owned: int = int(_owned.get(id, 0))
	var room: int = _room(entry, owned)
	var cost: float = Economy.cost(float(def["base_cost"]), float(def["cost_growth"]), owned)
	var locked: bool = _is_locked(def)
	return {
		"id": id, "category": entry["category"], "name": def["name"], "desc": def["desc"],
		"icon": def.get("icon", id), "owned": owned, "max_owned": _max_owned(entry),
		"cost": cost, "affordable": not locked and room != 0 and _coins >= cost,
		"locked": locked, "unlock_text": _unlock_text(def), "effect_text": _effect_text(entry),
	}


func _effect_text(entry: Dictionary) -> String:
	var def: Dictionary = entry["def"]
	match entry["category"]:
		"brush":
			return "Brush size x%s" % NumFormat.fmt(float(def["brush_power"]))
		"digger":
			return "+%s coins/sec each" % NumFormat.fmt(float(def["slabs_per_sec"]) * _speed_mult * _ev_auto)
	var v: float = float(def["effect_value"])
	var pct: String = NumFormat.fmt(v * 100.0)
	match def["effect_type"]:
		"click_value_mult":
			return "+%s%% brushing find value" % pct
		"digger_speed_mult":
			return "+%s%% digger speed" % pct
		"rarity_luck":
			return "+%s%% rare find luck" % pct
		"offline_cap_hours_add":
			return "+%s h offline time" % NumFormat.fmt(v)
		"offline_efficiency_add":
			return "+%s%% offline earnings" % pct
		"value_mult_era":
			return "+%s%% %s find value" % [pct, def.get("era", "")]
		"fieldwork_gain_mult":
			return "+%s%% fieldwork on prestige" % pct
	return ""


func _recalc() -> void:
	var ups: Array[Dictionary] = _data.upgrades
	_speed_mult = Economy.upgrade_multiplier(_owned, ups, "digger_speed_mult")
	_click_mult = Economy.upgrade_multiplier(_owned, ups, "click_value_mult")
	_luck = Economy.upgrade_bonus(_owned, ups, "rarity_luck")
	_fw_mult = Economy.fieldwork_multiplier(_fieldwork, float(_data.prestige["per_fieldwork_income_mult"]))
	_era_mult.clear()
	for era: String in _eras:
		_era_mult[era] = Economy.upgrade_multiplier(_owned, ups, "value_mult_era", era)
	_slabs_ps = Economy.slabs_per_sec(_owned, _data.diggers, _speed_mult)
	_auto_value_mult = float(_data.config["auto_dig_value_mult"])
	_ev_auto = _gen.expected_value(_luck, _fw_mult * _auto_value_mult, _era_mult)
	var old: float = _income
	_income = Economy.income_per_sec(_slabs_ps, _ev_auto, 1.0)
	if not is_equal_approx(old, _income):
		bus.income_changed.emit(_income)


# ---------------------------------------------------------------- collection

func get_collection(site_id: String = "") -> Array[Dictionary]:
	return _collection.entries(site_id, _manual_value)


func get_collection_progress() -> Dictionary:
	return _collection.progress()


func get_specimen(specimen_id: String) -> Dictionary:
	var s: Dictionary = _data.specimen_by_id.get(specimen_id, {})
	return {} if s.is_empty() else _collection.entry(specimen_id, _manual_value(s))


# ---------------------------------------------------------------- offline

## Computes away-time earnings from the last save/active time. Called at boot and on app resume.
func check_offline() -> void:
	var now: float = _now()
	var ups: Array[Dictionary] = _data.upgrades
	var cap_h: float = float(_data.config["offline_cap_hours"]) + Economy.upgrade_bonus(_owned, ups, "offline_cap_hours_add")
	var eff: float = float(_data.config["offline_efficiency"]) + Economy.upgrade_bonus(_owned, ups, "offline_efficiency_add")
	var rep: Dictionary = Offline.compute(_last_active, now, _income, _slabs_ps, cap_h, eff, float(_data.config["offline_min_seconds"]))
	_last_active = now  # also re-bases after clock tampering
	if float(rep["seconds"]) <= 0.0:
		return
	var rolls: Dictionary = _gen.roll_many(int(rep["slabs"]), _luck, int(_data.config["offline_max_rolls"]))
	if _pending_offline.is_empty():
		_pending_offline = {"seconds": 0.0, "coins": 0.0, "slabs": 0, "new_discoveries": [], "capped": false}
	_pending_offline["seconds"] += rep["seconds"]
	_pending_offline["coins"] = Economy.clamp_value(float(_pending_offline["coins"]) + float(rep["coins"]))
	_pending_offline["slabs"] += rep["slabs"]
	_pending_offline["capped"] = bool(_pending_offline["capped"]) or bool(rep["capped"])
	var found: Array = _pending_offline["new_discoveries"]
	for id: String in rolls["counts"]:
		if not _collection.is_discovered(id) and not found.has(id):
			found.append(id)
	if offline_emit_delay <= 0.0 or not is_inside_tree():
		_emit_offline_report()
	else:
		get_tree().create_timer(offline_emit_delay).timeout.connect(_emit_offline_report)


func _emit_offline_report() -> void:
	if not _pending_offline.is_empty():
		bus.offline_report_ready.emit(_pending_offline.duplicate(true))


func claim_offline_report() -> void:
	if _pending_offline.is_empty():
		return
	var rep: Dictionary = _pending_offline
	_pending_offline = {}
	_credit(float(rep["coins"]))
	for id: String in rep["new_discoveries"]:
		if _collection.discover(id):
			bus.specimen_discovered.emit(id)


# ---------------------------------------------------------------- prestige

func get_prestige_preview() -> Dictionary:
	var gain: float = _prestige_gain()
	var after: float = _fieldwork + gain
	var site: Dictionary = Prestige.next_site(_data.sites_in_order(), _site_id, after)
	return {
		"can_prestige": gain >= 1.0, "fieldwork_gain": gain,
		"bonus_text": Prestige.bonus_text(after, float(_data.prestige["per_fieldwork_income_mult"])),
		"next_site": _site_dict(site),
	}


## Resets the run (coins, brushes, diggers, upgrades, slabs) and moves to the next site.
## Keeps collection, fieldwork, lifetime stats and the pity-free fresh generator.
func do_prestige() -> void:
	var gain: float = _prestige_gain()
	if gain < 1.0:
		return
	_fieldwork_basis += Prestige.raw_gain(_total_coins, _fieldwork_basis, _data.prestige)
	_fieldwork = Economy.clamp_value(_fieldwork + gain)
	_site_id = str(Prestige.next_site(_data.sites_in_order(), _site_id, _fieldwork)["id"])
	_coins = 0.0
	_owned = {str(_data.tools[0]["id"]): 1}
	_slab_frac = 0.0
	_active.clear()
	_reset_summary()
	_build_generator({})
	_recalc()
	bus.prestige_done.emit({"site_id": _site_id, "fieldwork_gained": gain, "total_fieldwork": _fieldwork})
	bus.site_changed.emit(get_current_site())
	_prestige_avail = false
	bus.prestige_available_changed.emit(false)
	_touch(CURRENCY_COINS)
	_touch(CURRENCY_FIELDWORK)
	save_now()


func _prestige_gain() -> float:
	var mult: float = Economy.upgrade_multiplier(_owned, _data.upgrades, "fieldwork_gain_mult")
	return Prestige.gain(_total_coins, _fieldwork_basis, _data.prestige, mult)


func _update_prestige_available() -> void:
	var now_ok: bool = _prestige_gain() >= 1.0
	if now_ok != _prestige_avail:
		_prestige_avail = now_ok
		bus.prestige_available_changed.emit(now_ok)


func _site_dict(s: Dictionary) -> Dictionary:
	return {"id": s["id"], "name": s["name"], "bg_tint": s["bg_tint"], "rock_tint": s["rock_tint"]}


# ---------------------------------------------------------------- stats / save

func get_stats() -> Dictionary:
	return {"slabs_dug": _slabs_dug, "play_seconds": _play_seconds, "total_coins": _total_coins}


func save_now() -> void:
	if _save == null or not _booted:
		return
	_last_active = _now()
	_autosave_t = 0.0
	if _save.save(_build_state()):
		bus.save_completed.emit()


func reset_all_data() -> void:
	_save.delete_all()
	_new_game()
	_build_generator({})
	_recalc()
	_touch(CURRENCY_COINS)


func _now() -> float:
	return now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()


func _new_game() -> void:
	_coins = 0.0
	_fieldwork = 0.0
	_total_coins = 0.0
	_slabs_dug = 0
	_play_seconds = 0.0
	_owned = {str(_data.tools[0]["id"]): 1}
	_site_id = str(_data.sites_in_order()[0]["id"])
	_next_slab_id = 0
	_slab_frac = 0.0
	_fieldwork_basis = 0.0
	_prestige_avail = false
	_pending_offline = {}
	_active.clear()
	_collection = Collection.new(_data)
	_last_active = _now()
	_reset_summary()


func _build_generator(pity: Dictionary) -> void:
	_gen = SlabGenerator.new(_data.config, _data.specimens_for_site(_site_id), _rng)
	if not pity.is_empty():
		_gen.set_state(pity)


func _build_state() -> Dictionary:
	return {
		"version": SaveSystem.CURRENT_VERSION, "saved_at": _last_active,
		"coins": _coins, "fieldwork": _fieldwork, "total_coins": _total_coins,
		"slabs_dug": _slabs_dug, "play_seconds": _play_seconds, "owned": _owned.duplicate(),
		"discovered": _collection.to_array(), "site_id": _site_id, "next_slab_id": _next_slab_id,
		"slab_frac": _slab_frac, "fieldwork_basis": _fieldwork_basis, "pity": _gen.get_state(), "pending_offline": _pending_offline.duplicate(true),
	}


## Applies a loaded save (tolerating bad values) and returns the saved pity state.
func _apply_state(s: Dictionary) -> Dictionary:
	_coins = _clean(s.get("coins", 0.0))
	_fieldwork = _clean(s.get("fieldwork", 0.0))
	_total_coins = maxf(_clean(s.get("total_coins", 0.0)), _coins)
	_slabs_dug = maxi(int(s.get("slabs_dug", 0)), 0)
	_play_seconds = _clean(s.get("play_seconds", 0.0))
	_next_slab_id = maxi(int(s.get("next_slab_id", 0)), 0)
	_slab_frac = minf(_clean(s.get("slab_frac", 0.0)), 1.0)
	_fieldwork_basis = _clean(s.get("fieldwork_basis", 0.0))
	_last_active = float(s.get("saved_at", _now()))
	var site: String = str(s.get("site_id", _site_id))
	if _data.site_by_id.has(site):
		_site_id = site
	var owned: Variant = s.get("owned", {})
	if owned is Dictionary:
		for id: Variant in owned:
			var entry: Dictionary = _data.item_by_id.get(str(id), {})
			if entry.is_empty():
				continue
			var cap: int = _max_owned(entry)
			var n: int = maxi(int(owned[id]), 0)
			_owned[str(id)] = n if cap < 0 else mini(n, cap)
	_collection.load_array(s.get("discovered", []) as Array)
	var pending: Variant = s.get("pending_offline", {})
	if pending is Dictionary and not (pending as Dictionary).is_empty():
		_pending_offline = {
			"seconds": _clean(pending.get("seconds", 0.0)), "coins": _clean(pending.get("coins", 0.0)),
			"slabs": maxi(int(pending.get("slabs", 0)), 0), "capped": bool(pending.get("capped", false)),
			"new_discoveries": (pending.get("new_discoveries", []) as Array).duplicate(),
		}
	var pity: Variant = s.get("pity", {})
	return pity if pity is Dictionary else {}


func _clean(x: Variant) -> float:
	var f: float = float(x)
	return 0.0 if (is_nan(f) or f < 0.0) else minf(f, Economy.MAX_VALUE)
