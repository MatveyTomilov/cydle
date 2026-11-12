class_name QuestCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1
const BIOMES: Array[String] = ["B01", "B02", "B03", "B04", "B05", "B06"]
const FACTIONS: Array[String] = ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]

var quests: Dictionary = {}
var contracts: Dictionary = {}

func load_catalog(path: String = "res://data/catalog/quest_definitions.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать каталог заданий: %s" % path)
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary or int(document.get("schemaVersion", 0)) != SCHEMA_VERSION or not document.get("quests") is Array or not document.get("contracts") is Array:
		return _failure("Каталог заданий имеет неверный формат или версию.")
	var parsed_quests: Dictionary = {}
	for quest_value: Variant in document["quests"]:
		if not _valid_quest(quest_value):
			return _failure("Каталог содержит неверную квестовую цепочку.")
		var quest: Dictionary = quest_value
		if parsed_quests.has(str(quest["id"])):
			return _failure("Каталог содержит повторяющийся квест %s." % str(quest["id"]))
		parsed_quests[str(quest["id"])] = quest.duplicate(true)
	var parsed_contracts: Dictionary = {}
	for contract_value: Variant in document["contracts"]:
		if not _valid_contract(contract_value):
			return _failure("Каталог содержит неверный контракт.")
		var contract: Dictionary = contract_value
		if parsed_contracts.has(str(contract["id"])):
			return _failure("Каталог содержит повторяющийся контракт %s." % str(contract["id"]))
		parsed_contracts[str(contract["id"])] = contract.duplicate(true)
	quests = parsed_quests
	contracts = parsed_contracts
	return {"ok": true, "questCount": quests.size(), "contractCount": contracts.size(), "error": ""}

func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {}).duplicate(true)

func get_contract(contract_id: String) -> Dictionary:
	return contracts.get(contract_id, {}).duplicate(true)

func _valid_quest(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not _text(value.get("id")) or not _text(value.get("name")) or not _text(value.get("desc")) or not FACTIONS.has(str(value.get("faction", ""))) or not BIOMES.has(str(value.get("biome", ""))):
		return false
	if not _integer(value.get("minDepth")) or int(value["minDepth"]) < 1 or not value.get("stages") is Array or value["stages"].size() != 3:
		return false
	for index: int in range(3):
		var stage: Variant = value["stages"][index]
		if not stage is Dictionary or int(stage.get("stage", 0)) != index + 1 or not _text(stage.get("name")) or not _text(stage.get("text")) or not stage.get("choices") is Array or stage["choices"].size() != 2:
			return false
		if stage.has("biome") and not BIOMES.has(str(stage["biome"])):
			return false
		for choice: Variant in stage["choices"]:
			if not choice is Dictionary or not _text(choice.get("id")) or not _text(choice.get("label")) or not _text(choice.get("desc")):
				return false
	return true

func _valid_contract(value: Variant) -> bool:
	if not value is Dictionary or not _text(value.get("id")) or not _text(value.get("name")) or not _text(value.get("desc")):
		return false
	return str(value.get("kind", "")) in ["HUNT", "TECH", "ESCORT"] and BIOMES.has(str(value.get("targetBiome", "")))

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value)

func _text(value: Variant) -> bool:
	return value is String and not str(value).strip_edges().is_empty()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "questCount": 0, "contractCount": 0, "error": message}
