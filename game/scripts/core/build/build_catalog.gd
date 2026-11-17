class_name BuildCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1

var skills: Dictionary = {}
var passives: Dictionary = {}
var tree_nodes: Dictionary = {}
var mutations: Dictionary = {}

func load_catalog(path: String = "res://data/catalog/build_definitions.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать каталог сборок: %s" % path)
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary or not (document.get("schemaVersion") is int or document.get("schemaVersion") is float) or int(document["schemaVersion"]) != SCHEMA_VERSION:
		return _failure("Каталог сборок имеет неверный формат или версию.")
	var parsed: Dictionary = {}
	for collection: String in ["skills", "passives", "treeNodes", "mutations"]:
		if not document.get(collection) is Array:
			return _failure("Каталог сборок: %s должен быть массивом." % collection)
		var by_id: Dictionary = {}
		for entry: Variant in document[collection]:
			if not entry is Dictionary or not _nonempty_string(entry.get("id")) or not entry.get("effects", []) is Array:
				return _failure("Каталог сборок: неверная запись в %s." % collection)
			var id: String = str(entry["id"])
			if by_id.has(id):
				return _failure("Каталог сборок: повторяется ID %s." % id)
			by_id[id] = entry.duplicate(true)
		parsed[collection] = by_id
	skills = parsed["skills"]
	passives = parsed["passives"]
	tree_nodes = parsed["treeNodes"]
	mutations = parsed["mutations"]
	return {"ok": true, "counts": {"skills": skills.size(), "passives": passives.size(), "treeNodes": tree_nodes.size(), "mutations": mutations.size()}, "error": ""}

func _nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "counts": {}, "error": message}
