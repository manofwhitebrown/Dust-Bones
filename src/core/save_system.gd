class_name SaveSystem
extends RefCounted
## Atomic JSON save with .bak fallback and a version migration table.

const CURRENT_VERSION: int = 1
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"
## Godot's JSON float parser is not bit-exact, so non-integral floats are stored as hex strings.
const HEX_PREFIX: String = "f64:"
const PLAIN_INT_MAX: float = 1e15

var path: String
## "main", "bak" or "fresh": where the last load_game() got its data.
var last_load_source: String = "fresh"


func _init(save_path: String = "user://save.json") -> void:
	path = save_path


func save(data: Dictionary) -> bool:
	var tmp: String = path + TMP_SUFFIX
	var bak: String = path + BAK_SUFFIX
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(encode(data), "", true, true))
	f.flush()
	f.close()
	if _read(tmp).is_empty():  # never promote a file we cannot read back
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	if DirAccess.rename_absolute(tmp, path) != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, path)
		return false
	return true


## Main file, then .bak, then {} (fresh game). Result is migrated to CURRENT_VERSION.
func load_game() -> Dictionary:
	for candidate: Array in [["main", path], ["bak", path + BAK_SUFFIX]]:
		var d: Dictionary = _read(candidate[1])
		if not d.is_empty():
			last_load_source = candidate[0]
			return migrate(decode(d))
	last_load_source = "fresh"
	return {}


func delete_all() -> void:
	for p: String in [path, path + BAK_SUFFIX, path + TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func migrate(data: Dictionary) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	var steps: Dictionary = _migrations()
	var v: int = int(d.get("version", 0))
	while v < CURRENT_VERSION:
		if not steps.has(v):
			return {}
		d = (steps[v] as Callable).call(d)
		v = int(d.get("version", v + 1))
	return d


## Prepares data for JSON: non-finite floats become 0, non-integral or huge floats become exact hex strings.
static func encode(value: Variant) -> Variant:
	if value is float:
		var x: float = value
		if is_nan(x) or is_inf(x):
			return 0.0
		if x != floorf(x) or absf(x) >= PLAIN_INT_MAX:
			var b: PackedByteArray = PackedByteArray()
			b.resize(8)
			b.encode_double(0, x)
			return HEX_PREFIX + b.hex_encode()
		return x
	if value is Dictionary:
		var out: Dictionary = {}
		for k: Variant in value:
			out[k] = encode(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for e: Variant in value:
			arr.append(encode(e))
		return arr
	return value


static func decode(value: Variant) -> Variant:
	if value is String and (value as String).begins_with(HEX_PREFIX):
		var b: PackedByteArray = (value as String).substr(HEX_PREFIX.length()).hex_decode()
		return b.decode_double(0) if b.size() == 8 else 0.0
	if value is Dictionary:
		var out: Dictionary = {}
		for k: Variant in value:
			out[k] = decode(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for e: Variant in value:
			arr.append(decode(e))
		return arr
	return value


static func _migrations() -> Dictionary:
	return {0: Callable(SaveSystem, "_migrate_0_to_1")}


## v0 stored the soft currency as "money".
static func _migrate_0_to_1(d: Dictionary) -> Dictionary:
	if d.has("money"):
		d["coins"] = d["money"]
		d.erase("money")
	d["version"] = 1
	return d


func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("version"):
		return {}
	return parsed
