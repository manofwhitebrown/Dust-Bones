class_name GameData
extends RefCounted
## Loads and validates data/*.json. Pure data access, no gameplay math.

const DATA_DIR: String = "res://data"
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const EFFECT_TYPES: Array[String] = [
	"click_value_mult", "digger_speed_mult", "rarity_luck", "offline_cap_hours_add",
	"offline_efficiency_add", "value_mult_era", "fieldwork_gain_mult",
]
const CONFIG_KEYS: Array[String] = [
	"reveal_threshold", "offline_cap_hours", "offline_efficiency", "autosave_seconds",
	"pity", "rarity_weights", "cost_growth_default", "hardness_per_tier",
	"offline_min_seconds", "offline_max_rolls", "auto_dig_max_rolls", "auto_dig_value_mult",
]
const PRESTIGE_KEYS: Array[String] = ["k", "base", "exp", "per_fieldwork_income_mult", "min_lifetime_coins"]

var config: Dictionary = {}
var prestige: Dictionary = {}
var sites: Array[Dictionary] = []
var specimens: Array[Dictionary] = []
var tools: Array[Dictionary] = []
var diggers: Array[Dictionary] = []
var upgrades: Array[Dictionary] = []
var specimen_by_id: Dictionary = {}
var site_by_id: Dictionary = {}
## id -> {"category": "brush"|"digger"|"upgrade", "def": Dictionary}
var item_by_id: Dictionary = {}
var load_errors: Array[String] = []


static func load_dir(dir: String = DATA_DIR) -> GameData:
	var d: GameData = GameData.new()
	d.config = d._read_dict(dir.path_join("config.json"))
	d.prestige = d._read_dict(dir.path_join("prestige.json"))
	d.sites = d._read_list(dir.path_join("sites.json"))
	d.specimens = d._read_list(dir.path_join("specimens.json"))
	d.tools = d._read_list(dir.path_join("tools.json"))
	d.diggers = d._read_list(dir.path_join("diggers.json"))
	d.upgrades = d._read_list(dir.path_join("upgrades.json"))
	d._index()
	return d


func specimens_for_site(site_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in specimens:
		if s["site"] == site_id:
			out.append(s)
	return out


func sites_in_order() -> Array[Dictionary]:
	var out: Array[Dictionary] = sites.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return out


func validate() -> Array[String]:
	var errs: Array[String] = load_errors.duplicate()
	_validate_config(errs)
	_validate_specimens(errs)
	_validate_items(errs)
	for key: String in PRESTIGE_KEYS:
		if not prestige.has(key):
			errs.append("prestige missing %s" % key)
	return errs


func _validate_config(errs: Array[String]) -> void:
	for key: String in CONFIG_KEYS:
		if not config.has(key):
			errs.append("config missing %s" % key)
	if not (config.has("rarity_weights") and config.has("pity")):
		return
	for r: String in RARITIES:
		if float(config["rarity_weights"].get(r, 0.0)) <= 0.0:
			errs.append("rarity weight for %s must be > 0" % r)
		if r != "common" and int(config["pity"].get(r, 0)) <= 0:
			errs.append("pity for %s must be > 0" % r)


func _validate_specimens(errs: Array[String]) -> void:
	for site: Dictionary in sites:
		for sid: String in site["specimen_ids"]:
			var sp: Dictionary = specimen_by_id.get(sid, {})
			if sp.is_empty():
				errs.append("site %s references unknown specimen %s" % [site["id"], sid])
			elif sp["site"] != site["id"]:
				errs.append("specimen %s site mismatch" % sid)
	for s: Dictionary in specimens:
		var id: String = s["id"]
		if not RARITIES.has(s["rarity"]):
			errs.append("%s: bad rarity" % id)
		if not site_by_id.has(s["site"]):
			errs.append("%s: unknown site" % id)
		elif not site_by_id[s["site"]]["specimen_ids"].has(id):
			errs.append("%s: missing from its site's specimen_ids" % id)
		if float(s["base_value"]) <= 0.0 or float(s["weight"]) <= 0.0:
			errs.append("%s: base_value and weight must be > 0" % id)
		var fact: String = s["fact"]
		if fact.is_empty() or fact.length() > 120:
			errs.append("%s: fact must be 1-120 chars" % id)


func _validate_items(errs: Array[String]) -> void:
	var eras: Dictionary = {}
	for s: Dictionary in specimens:
		eras[s["era"]] = true
	for id: String in item_by_id:
		var entry: Dictionary = item_by_id[id]
		var def: Dictionary = entry["def"]
		var req: Dictionary = def.get("requires", {})
		if req.has("item_id") and not item_by_id.has(req["item_id"]):
			errs.append("%s requires unknown item %s" % [id, req["item_id"]])
		if float(def["base_cost"]) < 0.0 or float(def["cost_growth"]) < 1.0:
			errs.append("%s: bad cost numbers" % id)
		if entry["category"] == "upgrade":
			if not EFFECT_TYPES.has(def["effect_type"]):
				errs.append("%s: bad effect_type" % id)
			if def["effect_type"] == "value_mult_era" and not eras.has(def.get("era", "")):
				errs.append("%s: value_mult_era needs a known era" % id)


func _index() -> void:
	for s: Dictionary in specimens:
		if specimen_by_id.has(s["id"]):
			load_errors.append("duplicate specimen id %s" % s["id"])
		specimen_by_id[s["id"]] = s
	for s: Dictionary in sites:
		if site_by_id.has(s["id"]):
			load_errors.append("duplicate site id %s" % s["id"])
		site_by_id[s["id"]] = s
	_index_items(tools, "brush")
	_index_items(diggers, "digger")
	_index_items(upgrades, "upgrade")


func _index_items(defs: Array[Dictionary], category: String) -> void:
	for def: Dictionary in defs:
		if item_by_id.has(def["id"]):
			load_errors.append("duplicate item id %s" % def["id"])
		item_by_id[def["id"]] = {"category": category, "def": def}


func _read_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		load_errors.append("invalid JSON in %s" % path)
	return parsed


func _read_dict(path: String) -> Dictionary:
	var v: Variant = _read_json(path)
	return v if v is Dictionary else {}


func _read_list(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v: Variant = _read_json(path)
	if v is Array:
		for e: Variant in v:
			if e is Dictionary:
				out.append(e)
	return out
