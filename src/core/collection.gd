class_name Collection
extends RefCounted
## Discovered-specimen set plus masked views and progress counts.

const MASK_NAME: String = "???"

var _data: GameData
var _found: Dictionary = {}


func _init(data: GameData) -> void:
	_data = data


func is_discovered(specimen_id: String) -> bool:
	return _found.has(specimen_id)


## Returns true only the first time a known specimen is discovered.
func discover(specimen_id: String) -> bool:
	if not _data.specimen_by_id.has(specimen_id) or _found.has(specimen_id):
		return false
	_found[specimen_id] = true
	return true


func count() -> int:
	return _found.size()


## Masked view: name "???" and fact "" until discovered. `value` is supplied by the caller.
func entry(specimen_id: String, value: float) -> Dictionary:
	var s: Dictionary = _data.specimen_by_id.get(specimen_id, {})
	if s.is_empty():
		return {}
	var found: bool = _found.has(specimen_id)
	return {
		"id": s["id"], "name": s["name"] if found else MASK_NAME, "era": s["era"],
		"rarity": s["rarity"], "site": s["site"], "discovered": found,
		"value": value, "fact": s["fact"] if found else "",
	}


## value_of: Callable(specimen: Dictionary) -> float. Empty site_id = every site in order.
func entries(site_id: String, value_of: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for site: Dictionary in _data.sites_in_order():
		if site_id != "" and site["id"] != site_id:
			continue
		for sid: String in site["specimen_ids"]:
			out.append(entry(sid, float(value_of.call(_data.specimen_by_id[sid]))))
	return out


func progress(site_id: String = "") -> Dictionary:
	var by_era: Dictionary = {}
	var found: int = 0
	var total: int = 0
	for s: Dictionary in _data.specimens:
		if site_id != "" and s["site"] != site_id:
			continue
		var era: String = s["era"]
		if not by_era.has(era):
			by_era[era] = {"discovered": 0, "total": 0}
		by_era[era]["total"] += 1
		total += 1
		if _found.has(s["id"]):
			by_era[era]["discovered"] += 1
			found += 1
	return {"discovered": found, "total": total, "by_era": by_era}


func to_array() -> Array:
	var ids: Array = _found.keys()
	ids.sort()
	return ids


## Unknown ids in old/edited saves are dropped.
func load_array(ids: Array) -> void:
	_found.clear()
	for id: Variant in ids:
		discover(str(id))
