class_name ItemCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1
const CATEGORIES: Array[String] = ["MAIN", "OFFHAND", "ARMOR", "IMPLANT", "DRONE", "ENGINE", "CHASSIS", "SCANNER", "SERVICE", "CARGO", "SUPPORT", "MATERIAL"]

var _templates: Dictionary = {}
var _template_order: Array[Dictionary] = []
var _affixes: Dictionary = {}
var _rules: Dictionary = {}

func load_catalog(path: String = "res://data/catalog/item_templates.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать каталог предметов: %s" % path)
	var source: String = file.get_as_text()
	file.close()
	var document: Variant = JSON.parse_string(source)
	if not document is Dictionary or not document.has("schemaVersion") or not document.has("templates"):
		return _failure("Каталог предметов имеет неверный корневой формат.")
	if not (document["schemaVersion"] is int or document["schemaVersion"] is float) or int(document["schemaVersion"]) != SCHEMA_VERSION:
		return _failure("Версия каталога предметов не поддерживается.")
	if not document["templates"] is Array:
		return _failure("Каталог предметов должен содержать массив шаблонов.")
	var parsed: Dictionary = {}
	var parsed_order: Array[Dictionary] = []
	for index: int in range(document["templates"].size()):
		var value: Variant = document["templates"][index]
		if not _valid_template(value):
			return _failure("Шаблон предмета #%d имеет неверную структуру." % index)
		var template: Dictionary = value
		var id: String = str(template["id"])
		if parsed.has(id):
			return _failure("Каталог содержит повторяющийся ID предмета %s." % id)
		parsed[id] = template.duplicate(true)
		parsed_order.append(template.duplicate(true))
	var rules_result: Dictionary = _read_rules("res://data/catalog/item_rules.json")
	if not bool(rules_result.get("ok", false)):
		return rules_result
	_templates = parsed
	_template_order = parsed_order
	_affixes = rules_result["affixes"]
	_rules = rules_result["rules"]
	return {"ok": true, "count": _templates.size(), "error": ""}

func has_template(template_id: String) -> bool:
	return _templates.has(template_id)

func get_template(template_id: String) -> Dictionary:
	if not _templates.has(template_id):
		return {}
	return _templates[template_id].duplicate(true)

func has_affix(affix_id: String) -> bool:
	return _affixes.has(affix_id)

func get_affix(affix_id: String) -> Dictionary:
	return _affixes.get(affix_id, {}).duplicate(true)

func get_rules() -> Dictionary:
	return _rules.duplicate(true)

func template_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _templates.keys():
		result.append(str(key))
	result.sort()
	return result

func all_templates() -> Array[Dictionary]:
	return _template_order.duplicate(true)

func _valid_template(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var template: Dictionary = value
	for key: String in ["id", "name", "category", "tags", "effects", "cargoUnits", "desc", "craftable"]:
		if not template.has(key):
			return false
	if not _nonempty_string(template["id"]) or not _nonempty_string(template["name"]) or not CATEGORIES.has(str(template["category"])):
		return false
	if not template["tags"] is Array or not template["effects"] is Array or not template["desc"] is String or not template["craftable"] is bool:
		return false
	if not _finite_number(template["cargoUnits"]) or float(template["cargoUnits"]) < 0.0:
		return false
	for tag: Variant in template["tags"]:
		if not _nonempty_string(tag):
			return false
	for effect: Variant in template["effects"]:
		if not effect is Dictionary or not effect.has("type"):
			return false
		if not ["stat", "trigger"].has(str(effect["type"])):
			return false
	return true

func _read_rules(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать правила предметов: %s" % path)
	var source: String = file.get_as_text()
	file.close()
	var document: Variant = JSON.parse_string(source)
	if not document is Dictionary or not document.has("schemaVersion") or not document.has("affixes"):
		return _failure("Правила предметов имеют неверный корневой формат.")
	if not (document["schemaVersion"] is int or document["schemaVersion"] is float) or int(document["schemaVersion"]) != SCHEMA_VERSION:
		return _failure("Версия правил предметов не поддерживается.")
	for key: String in ["rarityAffixCount", "trRanges", "rarityPriceMultipliers", "rarityTables", "slotGroupWeights"]:
		if not document.has(key) or not document[key] is Dictionary:
			return _failure("Правила предметов: отсутствует объект %s." % key)
	if not document["affixes"] is Array:
		return _failure("Правила предметов: affixes должен быть массивом.")
	var affixes: Dictionary = {}
	for value: Variant in document["affixes"]:
		if not value is Dictionary:
			return _failure("Правила предметов: неверное определение аффикса.")
		var affix: Dictionary = value
		if not _nonempty_string(affix.get("id")) or not _nonempty_string(affix.get("name")) or not _nonempty_string(affix.get("stat")):
			return _failure("Правила предметов: у аффикса отсутствует ID, имя или характеристика.")
		if not affix.get("tiers") is Array or affix["tiers"].size() != 4 or not affix.get("slots") is Array:
			return _failure("Правила предметов: неверные tiers/slots у %s." % str(affix["id"]))
		if affixes.has(str(affix["id"])):
			return _failure("Правила предметов: повторяется аффикс %s." % str(affix["id"]))
		affixes[str(affix["id"])] = affix.duplicate(true)
	return {"ok": true, "affixes": affixes, "rules": document.duplicate(true), "error": ""}

func _nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "count": 0, "error": message}
