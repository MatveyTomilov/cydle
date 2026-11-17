class_name AutopilotPolicy
extends RefCounted

const PROFILES: Dictionary = {
	"CAUTIOUS": {"id": "CAUTIOUS", "name": "Осторожный", "riskWeight": 8.0, "minHP": 0.50, "minShield": 0.25, "maxWanted": 45, "checkpointAction": "EXTRACT", "allowElite": false, "allowAnomaly": false, "reserveFuel": 2},
	"BALANCED": {"id": "BALANCED", "name": "Сбалансированный", "riskWeight": 4.0, "minHP": 0.35, "minShield": 0.15, "maxWanted": 70, "checkpointAction": "CONDITIONAL", "allowElite": true, "allowAnomaly": true, "reserveFuel": 1},
	"AGGRESSIVE": {"id": "AGGRESSIVE", "name": "Агрессивный", "riskWeight": 1.5, "minHP": 0.20, "minShield": 0.0, "maxWanted": 95, "checkpointAction": "CONTINUE", "allowElite": true, "allowAnomaly": true, "reserveFuel": 0},
}
const NODE_TYPES: Array[String] = ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY", "EVENT", "CACHE", "FUEL", "REPAIR", "SHOP", "QUEST", "CHECKPOINT"]
const DEFAULT_WEIGHTS: Dictionary = {"loot": 3.0, "xp": 2.0, "quest": 2.0, "service": 1.0, "risk": 1.0, "fuel": 2.0, "wanted": 1.0}

static func profile(profile_id: String) -> Dictionary:
	var result: Dictionary = (PROFILES.get(profile_id, PROFILES["BALANCED"]) as Dictionary).duplicate(true)
	var weights: Dictionary = DEFAULT_WEIGHTS.duplicate(true)
	weights["risk"] = float(result.get("riskWeight", 4.0))
	result["objectiveWeights"] = weights
	result["allowedNodeTypes"] = []
	result["maxSpendRepair"] = 1000000000.0
	result["cargoProtectionPriority"] = "RARITY"
	result["preferMutations"] = []
	result["chooseQuest"] = "PAUSE"
	result["questChoiceMap"] = {}
	result["allowTow"] = false
	result["allowAbandon"] = false
	result["autoRestartAllowed"] = false
	result["maxRuns"] = 1
	return result

static func saved_profile(profile_id: String, saved_profiles: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = profile(profile_id)
	for saved: Dictionary in saved_profiles:
		if str(saved.get("id", "")) == profile_id and saved.get("settings", {}) is Dictionary:
			result.merge(saved.get("settings", {}), true)
			break
	return result

static func validate_settings(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "Параметры автопилота должны быть объектом."}
	var settings: Dictionary = value
	var allowed_keys: Array[String] = ["riskWeight", "minHP", "minShield", "maxWanted", "checkpointAction", "allowElite", "allowAnomaly", "reserveFuel", "objectiveWeights", "allowedNodeTypes", "maxSpendRepair", "cargoProtectionPriority", "preferMutations", "chooseQuest", "questChoiceMap", "allowTow", "allowAbandon", "autoRestartAllowed", "maxRuns"]
	for key: Variant in settings.keys():
		if not allowed_keys.has(str(key)):
			return {"ok": false, "error": "Неизвестный параметр автопилота: %s." % str(key)}
	for key: String in ["riskWeight", "minHP", "minShield", "maxWanted", "reserveFuel", "maxSpendRepair", "maxRuns"]:
		if settings.has(key) and not _finite_number(settings[key]):
			return {"ok": false, "error": "Параметр %s должен быть конечным числом." % key}
	if settings.has("riskWeight") and (float(settings["riskWeight"]) < 0.0 or float(settings["riskWeight"]) > 20.0):
		return {"ok": false, "error": "Вес риска должен находиться в диапазоне 0–20."}
	for key: String in ["minHP", "minShield"]:
		if settings.has(key) and (float(settings[key]) < 0.0 or float(settings[key]) > 1.0):
			return {"ok": false, "error": "%s должен находиться в диапазоне 0–1." % key}
	if settings.has("maxWanted") and (float(settings["maxWanted"]) < 0.0 or float(settings["maxWanted"]) > 100.0):
		return {"ok": false, "error": "Предел розыска должен находиться в диапазоне 0–100."}
	if settings.has("reserveFuel") and (float(settings["reserveFuel"]) < 0.0 or float(settings["reserveFuel"]) > 24.0):
		return {"ok": false, "error": "Резерв топлива должен находиться в диапазоне 0–24."}
	if settings.has("maxSpendRepair") and float(settings["maxSpendRepair"]) < 0.0:
		return {"ok": false, "error": "Бюджет ремонта не может быть отрицательным."}
	if settings.has("maxRuns") and (float(settings["maxRuns"]) < 1.0 or float(settings["maxRuns"]) > 100.0 or not is_equal_approx(float(settings["maxRuns"]), roundf(float(settings["maxRuns"])) )):
		return {"ok": false, "error": "Лимит повторных выездов должен быть целым числом от 1 до 100."}
	if settings.has("checkpointAction") and not ["EXTRACT", "CONDITIONAL", "CONTINUE"].has(str(settings["checkpointAction"])):
		return {"ok": false, "error": "Неизвестное действие на контрольном узле."}
	for key: String in ["allowElite", "allowAnomaly", "allowTow", "allowAbandon", "autoRestartAllowed"]:
		if settings.has(key) and not settings[key] is bool:
			return {"ok": false, "error": "Параметр %s должен быть логическим." % key}
	if settings.has("allowedNodeTypes"):
		if not settings["allowedNodeTypes"] is Array:
			return {"ok": false, "error": "Список разрешённых узлов должен быть массивом."}
		var seen: Dictionary = {}
		for node_type: Variant in settings["allowedNodeTypes"]:
			if not node_type is String or not NODE_TYPES.has(str(node_type)) or seen.has(str(node_type)):
				return {"ok": false, "error": "Список разрешённых узлов содержит неизвестный или повторный тип."}
			seen[str(node_type)] = true
	if settings.has("objectiveWeights"):
		var weights: Variant = settings["objectiveWeights"]
		if not weights is Dictionary or not _has_exact_keys(weights, ["loot", "xp", "quest", "service", "risk", "fuel", "wanted"]):
			return {"ok": false, "error": "Требуются все семь весов маршрута."}
		for key: String in DEFAULT_WEIGHTS:
			if not _finite_number(weights[key]) or float(weights[key]) < 0.0 or float(weights[key]) > 10.0:
				return {"ok": false, "error": "Вес %s должен находиться в диапазоне 0–10." % key}
	if settings.has("cargoProtectionPriority") and not ["RARITY", "QUEST", "VALUE"].has(str(settings["cargoProtectionPriority"])):
		return {"ok": false, "error": "Неизвестный порядок защиты груза."}
	if settings.has("chooseQuest") and not ["NEVER", "PAUSE", "MATCH"].has(str(settings["chooseQuest"])):
		return {"ok": false, "error": "Неизвестная политика выбора квеста."}
	if settings.has("questChoiceMap"):
		if not settings["questChoiceMap"] is Dictionary:
			return {"ok": false, "error": "Таблица выборов квеста должна быть объектом."}
		for key: Variant in settings["questChoiceMap"].keys():
			var parts: PackedStringArray = str(key).split(":")
			var choice_id: Variant = settings["questChoiceMap"][key]
			if parts.size() != 2 or not parts[0].begins_with("Q") or not parts[1].is_valid_int() or int(parts[1]) < 1 or int(parts[1]) > 3 or not choice_id is String or str(choice_id).is_empty():
				return {"ok": false, "error": "Ключ квестового выбора должен иметь вид Q01:1 → choiceId."}
	if str(settings.get("chooseQuest", "PAUSE")) == "MATCH" and settings.get("questChoiceMap", {}).is_empty():
		return {"ok": false, "error": "Для автоматического выбора укажите хотя бы один вариант QUEST:STAGE:CHOICE."}
	if settings.has("preferMutations") and (not settings["preferMutations"] is Array or settings["preferMutations"].size() > 32 or not _unique_strings(settings["preferMutations"])):
		return {"ok": false, "error": "Список предпочтительных мутаций некорректен."}
	if settings.has("preferMutations") and not settings["preferMutations"].is_empty():
		var build_catalog: BuildCatalog = BuildCatalog.new()
		var catalog_result: Dictionary = build_catalog.load_catalog()
		if not bool(catalog_result.get("ok", false)):
			return {"ok": false, "error": str(catalog_result.get("error", "Каталог мутаций недоступен."))}
		for mutation_id: String in settings["preferMutations"]:
			if not build_catalog.mutations.has(mutation_id):
				return {"ok": false, "error": "Неизвестная предпочтительная мутация %s." % mutation_id}
	return {"ok": true, "error": ""}

static func starter_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile_id: String in ["CAUTIOUS", "BALANCED", "AGGRESSIVE"]:
		var values: Dictionary = profile(profile_id)
		result.append({"id": profile_id, "name": str(values.get("name", profile_id)), "startDepth": 1, "enabled": false})
	return result

## Chooses only among reachable nodes and uses only the information disclosed by
## route_intel(). Hidden node types, enemy rolls, and rewards never enter scoring.
func choose_node(reachable: Array[Dictionary], intel: Dictionary, run: GameSaveState.RunState, risk_weight: float = 4.0, profile_id: String = "BALANCED", profile_overrides: Dictionary = {}) -> Dictionary:
	if reachable.is_empty() or run == null:
		return {}
	var selected: Dictionary = profile(profile_id)
	selected.merge(profile_overrides, true)
	var effective_risk_weight: float = float(selected.get("riskWeight", risk_weight))
	var facts: Dictionary = intel.get("nodes", {})
	var weights: Dictionary = selected.get("objectiveWeights", DEFAULT_WEIGHTS)
	var allowed_types: Array = selected.get("allowedNodeTypes", [])
	var resources: Dictionary = run.resources
	var hp_ratio: float = float(resources.get("hp", 0.0)) / maxf(1.0, float(resources.get("maxHP", 1.0)))
	var shield_ratio: float = float(resources.get("shield", 0.0)) / maxf(1.0, float(resources.get("maxShield", 1.0)))
	var hull_ratio: float = float(resources.get("hull", 0.0)) / maxf(1.0, float(resources.get("maxHull", 1.0)))
	var fuel_ratio: float = float(resources.get("fuel", 0.0)) / maxf(1.0, float(resources.get("maxFuel", 1.0)))
	var best: Dictionary = {}
	var best_score: float = -INF
	for node: Dictionary in reachable:
		var id: String = str(node.get("id", ""))
		var known: Dictionary = facts.get(id, {})
		var node_type: String = str(known.get("type", "UNKNOWN")) if bool(known.get("revealed", false)) else "UNKNOWN"
		if node_type != "UNKNOWN" and not allowed_types.is_empty() and not allowed_types.has(node_type):
			continue
		if node_type == "ELITE" and not bool(selected.get("allowElite", true)):
			continue
		if node_type == "ANOMALY" and not bool(selected.get("allowAnomaly", true)):
			continue
		var threat: String = str(known.get("threat", "unknown")) if bool(known.get("revealed", false)) else "unknown"
		var loot_hint: String = str(known.get("lootHint", "unknown")) if bool(known.get("revealed", false)) else "unknown"
		var normalized_loot: float = _normalized_loot(node_type, loot_hint)
		var normalized_xp: float = _normalized_xp(node_type)
		var quest_priority: float = 1.0 if bool(known.get("questTarget", false)) and bool(known.get("revealed", false)) else 0.0
		var service_need: float = 0.0
		if node_type == "REPAIR":
			service_need = maxf(1.0 - hp_ratio, maxf(1.0 - shield_ratio, 1.0 - hull_ratio))
		elif node_type == "FUEL":
			service_need = 1.0 - fuel_ratio
		var death_risk: float = _predicted_risk(node_type, threat, hp_ratio, hull_ratio)
		var normalized_fuel: float = clampf(_edge_fuel_cost(run, id) / 2.0, 0.0, 1.0)
		var normalized_wanted: float = clampf(run.wanted / 100.0, 0.0, 1.0)
		var score: float = float(weights.get("loot", 3.0)) * normalized_loot + float(weights.get("xp", 2.0)) * normalized_xp + float(weights.get("quest", 2.0)) * quest_priority + float(weights.get("service", 1.0)) * service_need - float(weights.get("risk", effective_risk_weight)) * death_risk - float(weights.get("fuel", 2.0)) * normalized_fuel - float(weights.get("wanted", 1.0)) * normalized_wanted
		if score > best_score or (is_equal_approx(score, best_score) and id < str(best.get("id", "~"))):
			best_score = score
			best = node.duplicate(true)
	return best

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true

static func _unique_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if not value is String or seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true

func _edge_fuel_cost(run: GameSaveState.RunState, node_id: String) -> float:
	for edge: Dictionary in run.graph.get("edges", []):
		if str(edge.get("from", "")) == run.current_node_id and str(edge.get("to", "")) == node_id:
			return float(edge.get("fuelCost", 1.0))
	return 2.0

func _normalized_loot(node_type: String, loot_hint: String) -> float:
	if node_type == "UNKNOWN" or loot_hint == "unknown":
		return 0.25
	if loot_hint.contains("прототип"):
		return 0.9
	if loot_hint.contains("аномальн"):
		return 0.8
	if loot_hint.contains("добыча после боя"):
		return 0.65 if node_type in ["ELITE", "BOUNTY", "BOSS"] else 0.5
	if loot_hint.contains("товар"):
		return 0.45
	if loot_hint.contains("восстановление"):
		return 0.2
	return 0.25

func _normalized_xp(node_type: String) -> float:
	match node_type:
		"COMBAT": return 0.45
		"ELITE", "BOUNTY": return 0.8
		"BOSS": return 1.0
		"QUEST", "EVENT": return 0.2
		_: return 0.05

func _predicted_risk(node_type: String, threat: String, hp_ratio: float, hull_ratio: float) -> float:
	var threat_risk: float = 0.45
	match threat:
		"low": threat_risk = 0.1
		"medium": threat_risk = 0.35
		"high": threat_risk = 0.7
		"boss": threat_risk = 0.9
	if node_type == "UNKNOWN":
		threat_risk = 0.45
	var survivability_factor: float = 1.0 + (1.0 - clampf(hp_ratio, 0.0, 1.0)) * 0.4 + (1.0 - clampf(hull_ratio, 0.0, 1.0)) * 0.2
	return clampf(threat_risk * survivability_factor, 0.0, 1.0)
