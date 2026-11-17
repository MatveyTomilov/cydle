class_name EnemyCatalog
extends RefCounted

const SCHEMA_VERSION: int = 1
const DAMAGE_TYPES: Array[String] = ["KINETIC", "ENERGY", "DIGITAL"]
const ABILITY_KINDS: Array[String] = ["heavyAttack", "heal", "summon", "applyStatus", "heat", "shieldRestore", "mark", "deathBurst", "escape", "wantedBoost", "protectAlly", "jamPunish", "shieldBypass"]

var enemies: Dictionary = {}
var bosses: Dictionary = {}
var elite_mods: Dictionary = {}

func load_catalog(path: String = "res://data/catalog/enemy_definitions.json") -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать каталог врагов: %s" % path)
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary or not (document.get("schemaVersion") is int or document.get("schemaVersion") is float) or int(document["schemaVersion"]) != SCHEMA_VERSION:
		return _failure("Каталог врагов имеет неверную структуру или версию.")
	for key: String in ["enemies", "bosses", "eliteMods"]:
		if not document.get(key) is Array:
			return _failure("Каталог врагов: %s должен быть массивом." % key)
	var parsed_enemies: Dictionary = {}
	var parsed_bosses: Dictionary = {}
	var parsed_elites: Dictionary = {}
	for entry: Variant in document["enemies"]:
		if not _valid_enemy(entry, false):
			return _failure("Каталог врагов содержит неверное обычное существо.")
		if parsed_enemies.has(str(entry["id"])):
			return _failure("Каталог врагов содержит повторяющийся ID %s." % str(entry["id"]))
		parsed_enemies[str(entry["id"])] = entry.duplicate(true)
	for entry: Variant in document["bosses"]:
		if not _valid_enemy(entry, true):
			return _failure("Каталог врагов содержит неверного босса.")
		if parsed_bosses.has(str(entry["id"])) or parsed_enemies.has(str(entry["id"])):
			return _failure("Каталог врагов содержит повторяющийся ID %s." % str(entry["id"]))
		parsed_bosses[str(entry["id"])] = entry.duplicate(true)
	for entry: Variant in document["eliteMods"]:
		if not entry is Dictionary or not _nonempty_string(entry.get("id")) or not _nonempty_string(entry.get("name")) or not _nonempty_string(entry.get("desc")):
			return _failure("Каталог врагов содержит неверный элитный модификатор.")
		if parsed_elites.has(str(entry["id"])):
			return _failure("Каталог врагов содержит повторяющийся элитный модификатор %s." % str(entry["id"]))
		parsed_elites[str(entry["id"])] = entry.duplicate(true)
	enemies = parsed_enemies
	bosses = parsed_bosses
	elite_mods = parsed_elites
	return {"ok": true, "counts": {"enemies": enemies.size(), "bosses": bosses.size(), "eliteMods": elite_mods.size()}, "error": ""}

func get_template(template_id: String) -> Dictionary:
	var source: Dictionary = bosses.get(template_id, enemies.get(template_id, {}))
	return source.duplicate(true)

func _valid_enemy(value: Variant, is_boss: bool) -> bool:
	if not value is Dictionary:
		return false
	var required: Array[String] = ["id", "name", "hp", "shield", "armor", "resE", "resD", "evasion", "damage", "intervalMs", "type", "threatUnits", "mechanical", "healer", "role", "abilities", "unlockDepth", "biomes", "desc"]
	if is_boss:
		required.append_array(["isBoss", "phases", "accuracy"])
	if not _has_keys(value, required):
		return false
	if not _nonempty_string(value["id"]) or not _nonempty_string(value["name"]) or not _nonempty_string(value["role"]) or not value["desc"] is String:
		return false
	for key: String in ["hp", "shield", "armor", "resE", "resD", "evasion", "damage", "intervalMs", "threatUnits", "unlockDepth"]:
		if not _finite_number(value[key]) or float(value[key]) < 0.0:
			return false
	if not DAMAGE_TYPES.has(str(value["type"])) or not value["mechanical"] is bool or not value["healer"] is bool or not value["biomes"] is Array or not value["abilities"] is Array:
		return false
	for biome: Variant in value["biomes"]:
		if not _nonempty_string(biome):
			return false
	for ability: Variant in value["abilities"]:
		if not _valid_ability(ability):
			return false
	if value.has("passives") and not value["passives"] is Array:
		return false
	if is_boss:
		if value["isBoss"] != true or not _finite_number(value["accuracy"]) or not value["phases"] is Array or not value.get("rotating", []) is Array:
			return false
		for phase: Variant in value["phases"]:
			if not phase is Dictionary or not _finite_number(phase.get("hpFraction")) or float(phase["hpFraction"]) < 0.0 or float(phase["hpFraction"]) > 1.0 or not _nonempty_string(phase.get("kind")):
				return false
		for ability: Variant in value.get("rotating", []):
			if not _valid_ability(ability):
				return false
	return true

func _valid_ability(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["id", "kind", "firstAtMs", "everyMs", "windupMs", "telegraphMs", "interruptible", "desc"]:
		if not value.has(key):
			return false
	if not _nonempty_string(value["id"]) or not ABILITY_KINDS.has(str(value["kind"])) or not value["interruptible"] is bool or not value["desc"] is String:
		return false
	for key: String in ["firstAtMs", "everyMs", "windupMs", "telegraphMs"]:
		if not _finite_number(value[key]) or float(value[key]) < 0.0:
			return false
	if value.has("damageType") and not DAMAGE_TYPES.has(str(value["damageType"])):
		return false
	return true

func _has_keys(value: Dictionary, required: Array[String]) -> bool:
	for key: String in required:
		if not value.has(key):
			return false
	return true

func _nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "counts": {}, "error": message}
