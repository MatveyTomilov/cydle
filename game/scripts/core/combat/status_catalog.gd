class_name StatusCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1
const DAMAGE_TYPES: Array[String] = ["KINETIC", "ENERGY", "DIGITAL"]
const SNAPSHOT_SOURCES: Array[String] = ["rawDamage", "techPower", "none"]

var definitions: Dictionary = {}

func load_catalog(path: String = "res://data/catalog/status_definitions.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать каталог статусов: %s" % path)
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary or int(document.get("schemaVersion", -1)) != SCHEMA_VERSION or not document.get("statuses") is Array:
		return _failure("Каталог статусов имеет неверную структуру или версию.")
	var parsed: Dictionary = {}
	for entry: Variant in document["statuses"]:
		if not _valid_definition(entry):
			return _failure("Каталог статусов содержит неверное определение.")
		var status_id: String = str(entry["id"])
		if parsed.has(status_id):
			return _failure("Каталог статусов содержит повторяющийся ID %s." % status_id)
		parsed[status_id] = entry.duplicate(true)
	definitions = parsed
	return {"ok": true, "count": definitions.size(), "error": ""}

func get_definition(status_id: String) -> Dictionary:
	return definitions.get(status_id, {}).duplicate(true)

func _valid_definition(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["id", "name", "durationMs", "snapshotFrom", "maxStacks", "refresh", "independentStacks", "desc", "harmful"]:
		if not value.has(key):
			return false
	if not _nonempty_string(value["id"]) or not _nonempty_string(value["name"]) or not _nonempty_string(value["desc"]):
		return false
	if not _finite_number(value["durationMs"]) or float(value["durationMs"]) < 0.0 or not _finite_number(value["maxStacks"]) or int(value["maxStacks"]) < 1:
		return false
	if not SNAPSHOT_SOURCES.has(str(value["snapshotFrom"])) or not value["refresh"] is bool or not value["independentStacks"] is bool or not value["harmful"] is bool:
		return false
	if value.has("damageType") and not DAMAGE_TYPES.has(str(value["damageType"])):
		return false
	if value.has("tickMs") and (not _finite_number(value["tickMs"]) or float(value["tickMs"]) <= 0.0):
		return false
	if value.has("tickFraction") and not _finite_number(value["tickFraction"]):
		return false
	return true

func _nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "count": 0, "error": message}
