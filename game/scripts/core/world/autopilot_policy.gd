class_name AutopilotPolicy
extends RefCounted

const PROFILES: Dictionary = {
	"CAUTIOUS": {"id": "CAUTIOUS", "name": "Осторожный", "riskWeight": 8.0, "minHP": 0.50, "minShield": 0.25, "maxWanted": 45, "checkpointAction": "EXTRACT", "allowElite": false, "allowAnomaly": false, "reserveFuel": 2},
	"BALANCED": {"id": "BALANCED", "name": "Сбалансированный", "riskWeight": 4.0, "minHP": 0.35, "minShield": 0.15, "maxWanted": 70, "checkpointAction": "CONDITIONAL", "allowElite": true, "allowAnomaly": true, "reserveFuel": 1},
	"AGGRESSIVE": {"id": "AGGRESSIVE", "name": "Агрессивный", "riskWeight": 1.5, "minHP": 0.20, "minShield": 0.0, "maxWanted": 95, "checkpointAction": "CONTINUE", "allowElite": true, "allowAnomaly": true, "reserveFuel": 0},
}

static func profile(profile_id: String) -> Dictionary:
	return (PROFILES.get(profile_id, PROFILES["BALANCED"]) as Dictionary).duplicate(true)

static func starter_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile_id: String in ["CAUTIOUS", "BALANCED", "AGGRESSIVE"]:
		var values: Dictionary = profile(profile_id)
		result.append({"id": profile_id, "name": str(values.get("name", profile_id)), "startDepth": 1, "enabled": false})
	return result

## Chooses only among reachable nodes and uses only the information disclosed by
## route_intel(). Hidden node types, enemy rolls, and rewards never enter scoring.
func choose_node(reachable: Array[Dictionary], intel: Dictionary, run: GameSaveState.RunState, risk_weight: float = 4.0, profile_id: String = "BALANCED") -> Dictionary:
	if reachable.is_empty() or run == null:
		return {}
	var selected: Dictionary = profile(profile_id)
	var effective_risk_weight: float = float(selected.get("riskWeight", risk_weight))
	var facts: Dictionary = intel.get("nodes", {})
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
		var score: float = 3.0 * normalized_loot + 2.0 * normalized_xp + 2.0 * quest_priority + service_need - effective_risk_weight * death_risk - 2.0 * normalized_fuel - normalized_wanted
		if score > best_score or (is_equal_approx(score, best_score) and id < str(best.get("id", "~"))):
			best_score = score
			best = node.duplicate(true)
	return best

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
