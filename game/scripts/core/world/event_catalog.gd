class_name EventCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1

var events: Dictionary = {}
var _loaded: bool = false

func load_catalog(path: String = "res://data/catalog/event_definitions.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Не удалось открыть каталог событий: %s" % path}
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary or int(document.get("schemaVersion", -1)) != SCHEMA_VERSION or not document.get("events", []) is Array:
		return {"ok": false, "error": "Каталог событий имеет неверную версию или структуру."}
	var parsed: Dictionary = {}
	for value: Variant in document["events"]:
		if not _valid_event(value):
			return {"ok": false, "error": "В каталоге есть событие неверной структуры."}
		var event: Dictionary = value
		var event_id: String = str(event["id"])
		if parsed.has(event_id):
			return {"ok": false, "error": "Повторяется ID события %s." % event_id}
		parsed[event_id] = event.duplicate(true)
	if parsed.size() != 24:
		return {"ok": false, "error": "Ожидалось 24 события, найдено %d." % parsed.size()}
	events = parsed
	_loaded = true
	return {"ok": true, "count": events.size(), "error": ""}

func get_event(event_id: String) -> Dictionary:
	if not _loaded:
		var loaded: Dictionary = load_catalog()
		if not bool(loaded.get("ok", false)):
			return {}
	return events.get(event_id, {}).duplicate(true)

func available_ids(used_ids: Array[String]) -> Array[String]:
	if not _loaded:
		var loaded: Dictionary = load_catalog()
		if not bool(loaded.get("ok", false)):
			return []
	var result: Array[String] = []
	for event_id: String in events.keys():
		if not used_ids.has(event_id):
			result.append(event_id)
	result.sort()
	return result

func _valid_event(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var event: Dictionary = value
	if not _nonempty(event.get("id")) or not _nonempty(event.get("name")) or not _nonempty(event.get("text")):
		return false
	if not event.get("choices", []) is Array or event["choices"].size() != 2:
		return false
	var ids: Array[String] = []
	for choice_value: Variant in event["choices"]:
		if not choice_value is Dictionary or not _nonempty(choice_value.get("id")) or not _nonempty(choice_value.get("label")) or not _nonempty(choice_value.get("desc")):
			return false
		ids.append(str(choice_value["id"]))
	return ids.has("A") and ids.has("B")

func _nonempty(value: Variant) -> bool:
	return value is String and not str(value).strip_edges().is_empty()
