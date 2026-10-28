extends Node
## PHASE 0 STUB: fake data + fake signals so the UI can be built against the
## frozen contract (docs/CONTRACT.md). Replaced by the real core in M2.

const REVEAL_THRESHOLD: float = 0.85
const TICK_SECONDS: float = 1.0
const OFFLINE_REPORT_DELAY: float = 2.0
const STUB_INCOME: float = 12.5
const STUB_BRUSH_POWER: float = 1.0
const RARITIES: Array[String] = ["common", "rare", "legendary"]
const CATEGORIES: Array[String] = ["brush", "digger", "upgrade"]
const SITE: Dictionary = {"id": "dry_creek", "name": "Dry Creek", "bg_tint": "#c9a66b", "rock_tint": "#8a6f4d"}
const NEXT_SITE: Dictionary = {"id": "salt_flats", "name": "Salt Flats", "bg_tint": "#e8e2d0", "rock_tint": "#b9b09a"}
const SPECIMENS: Array[Dictionary] = [
	{"id": "trilobite", "name": "Trilobite", "era": "Cambrian", "rarity": "common", "value": 10.0, "fact": "Trilobites ruled the seas for about 270 million years."},
	{"id": "brachiopod", "name": "Brachiopod", "era": "Ordovician", "rarity": "common", "value": 11.0, "fact": "Brachiopods look like clams but are an unrelated group."},
	{"id": "crinoid", "name": "Crinoid Stem", "era": "Ordovician", "rarity": "common", "value": 12.0, "fact": "Crinoids are animals, often called sea lilies."},
	{"id": "horn_coral", "name": "Horn Coral", "era": "Devonian", "rarity": "common", "value": 13.0, "fact": "Rugose corals grew in a horn shape on ancient seabeds."},
	{"id": "ammonite", "name": "Ammonite", "era": "Jurassic", "rarity": "common", "value": 14.0, "fact": "Ammonites were shelled cephalopods related to squid."},
	{"id": "fish_scale", "name": "Fish Scale", "era": "Devonian", "rarity": "common", "value": 15.0, "fact": "Early fish wore bony armor in the form of scales."},
	{"id": "orthocone", "name": "Orthocone", "era": "Ordovician", "rarity": "rare", "value": 100.0, "fact": "Orthocones were straight-shelled cephalopods."},
	{"id": "eurypterid", "name": "Eurypterid", "era": "Silurian", "rarity": "rare", "value": 110.0, "fact": "Sea scorpions were among the largest arthropods ever."},
	{"id": "belemnite", "name": "Belemnite", "era": "Jurassic", "rarity": "rare", "value": 120.0, "fact": "Belemnites were squid-like animals with a bullet-shaped guard."},
	{"id": "shark_tooth", "name": "Shark Tooth", "era": "Cretaceous", "rarity": "rare", "value": 130.0, "fact": "Sharks shed thousands of teeth over a lifetime."},
	{"id": "dunkleosteus", "name": "Dunkleosteus Plate", "era": "Devonian", "rarity": "legendary", "value": 1000.0, "fact": "Dunkleosteus was an armored fish with bony shearing plates."},
	{"id": "archaeopteryx", "name": "Archaeopteryx Feather", "era": "Jurassic", "rarity": "legendary", "value": 1200.0, "fact": "Archaeopteryx had feathers and also reptile-like teeth."},
]

var _coins: float = 100.0
var _fieldwork: float = 0.0
var _slab_counter: int = 0
var _slabs: Dictionary = {}
var _discovered: Dictionary = {}
var _owned: Dictionary = {}
var _reveal_count: int = 0
var _slabs_dug: int = 0
var _play_seconds: float = 0.0
var _total_coins: float = 100.0
var _pending_offline: Dictionary = {}


func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)
	get_tree().create_timer(OFFLINE_REPORT_DELAY).timeout.connect(_emit_fake_offline)


func _on_tick() -> void:
	_coins += STUB_INCOME
	_total_coins += STUB_INCOME
	_play_seconds += TICK_SECONDS
	EventBus.currency_changed.emit("coins", _coins)
	EventBus.income_changed.emit(STUB_INCOME)


func _emit_fake_offline() -> void:
	_pending_offline = {"seconds": 10800.0, "coins": 5000.0, "slabs": 120, "new_discoveries": ["eurypterid"], "capped": false}
	EventBus.offline_report_ready.emit(_pending_offline)


func get_balance(currency: String) -> float:
	return _fieldwork if currency == "fieldwork" else _coins


func get_income_per_sec() -> float:
	return STUB_INCOME


func get_brush_power() -> float:
	return STUB_BRUSH_POWER


func get_current_site() -> Dictionary:
	return SITE.duplicate()


func start_new_slab() -> Dictionary:
	_slab_counter += 1
	var spec: Dictionary = SPECIMENS[_slab_counter % SPECIMENS.size()]
	var slab: Dictionary = {
		"id": _slab_counter,
		"specimen_id": spec["id"],
		"rarity": spec["rarity"],
		"hardness": 1.0 + float(RARITIES.find(spec["rarity"])) * 0.15,
		"reveal_threshold": REVEAL_THRESHOLD,
		"rock_tint": SITE["rock_tint"],
	}
	_slabs[_slab_counter] = {"specimen": spec, "revealed": false}
	EventBus.slab_started.emit(slab)
	return slab


func report_brush_progress(slab_id: int, fraction: float) -> void:
	if not _slabs.has(slab_id):
		return
	var entry: Dictionary = _slabs[slab_id]
	if entry["revealed"] or fraction < REVEAL_THRESHOLD:
		return
	entry["revealed"] = true
	var spec: Dictionary = entry["specimen"]
	_reveal_count += 1
	_slabs_dug += 1
	var is_new: bool = _reveal_count % 2 == 1
	var value: float = spec["value"]
	_coins += value
	_total_coins += value
	if is_new:
		_discovered[spec["id"]] = true
	EventBus.slab_revealed.emit({
		"slab_id": slab_id, "specimen_id": spec["id"], "name": spec["name"],
		"rarity": spec["rarity"], "era": spec["era"], "value": value, "is_new": is_new,
	})
	if is_new:
		EventBus.specimen_discovered.emit(spec["id"])
	EventBus.currency_changed.emit("coins", _coins)


func _fake_items(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 3:
		var id: String = "%s_%d" % [category, i + 1]
		var cost: float = 50.0 * pow(6.0, i)
		var owned: int = _owned.get(id, 0)
		out.append({
			"id": id, "category": category, "name": "%s %d" % [category.capitalize(), i + 1],
			"desc": "Placeholder %s." % category, "icon": "",
			"owned": owned, "max_owned": 1 if category == "brush" else -1,
			"cost": cost, "affordable": _coins >= cost, "locked": i == 2,
			"unlock_text": "Own %s_%d first" % [category, i + 1] if i == 2 else "",
			"effect_text": "+%d%% placeholder effect" % ((i + 1) * 10),
		})
	return out


func get_shop_items(category: String) -> Array[Dictionary]:
	if not CATEGORIES.has(category):
		return [] as Array[Dictionary]
	return _fake_items(category)


func get_buy_cost(item_id: String, qty: int) -> float:
	return 50.0 * float(maxi(qty, 1))


func buy(item_id: String, qty: int = 1) -> bool:
	var count: int = maxi(qty, 1)
	_owned[item_id] = int(_owned.get(item_id, 0)) + count
	EventBus.item_purchased.emit(item_id, _owned[item_id])
	EventBus.currency_changed.emit("coins", _coins)
	EventBus.income_changed.emit(STUB_INCOME)
	return true


func _specimen_entry(spec: Dictionary) -> Dictionary:
	var found: bool = _discovered.has(spec["id"])
	return {
		"id": spec["id"], "name": spec["name"] if found else "???", "era": spec["era"],
		"rarity": spec["rarity"], "site": SITE["id"], "discovered": found,
		"value": spec["value"], "fact": spec["fact"] if found else "",
	}


func get_collection(site_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if site_id != "" and site_id != SITE["id"]:
		return out
	for spec: Dictionary in SPECIMENS:
		out.append(_specimen_entry(spec))
	return out


func get_collection_progress() -> Dictionary:
	var by_era: Dictionary = {}
	for spec: Dictionary in SPECIMENS:
		var era: String = spec["era"]
		if not by_era.has(era):
			by_era[era] = {"discovered": 0, "total": 0}
		by_era[era]["total"] += 1
		if _discovered.has(spec["id"]):
			by_era[era]["discovered"] += 1
	return {"discovered": _discovered.size(), "total": SPECIMENS.size(), "by_era": by_era}


func get_specimen(specimen_id: String) -> Dictionary:
	for spec: Dictionary in SPECIMENS:
		if spec["id"] == specimen_id:
			return _specimen_entry(spec)
	return {}


func claim_offline_report() -> void:
	if _pending_offline.is_empty():
		return
	_coins += float(_pending_offline["coins"])
	_pending_offline = {}
	EventBus.currency_changed.emit("coins", _coins)


func get_prestige_preview() -> Dictionary:
	return {"can_prestige": true, "fieldwork_gain": 5.0, "bonus_text": "+25% income", "next_site": NEXT_SITE.duplicate()}


func do_prestige() -> void:
	_fieldwork += 5.0
	EventBus.prestige_done.emit({"site_id": NEXT_SITE["id"], "fieldwork_gained": 5.0, "total_fieldwork": _fieldwork})
	EventBus.site_changed.emit(NEXT_SITE.duplicate())


func get_stats() -> Dictionary:
	return {"slabs_dug": _slabs_dug, "play_seconds": _play_seconds, "total_coins": _total_coins}


func save_now() -> void:
	EventBus.save_completed.emit()


func reset_all_data() -> void:
	_coins = 100.0
	_fieldwork = 0.0
	_discovered.clear()
	_owned.clear()
	_slabs.clear()
	EventBus.currency_changed.emit("coins", _coins)
