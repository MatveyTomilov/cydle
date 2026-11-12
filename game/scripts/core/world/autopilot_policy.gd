class_name AutopilotPolicy
extends RefCounted

## Chooses only among reachable nodes and uses only the information disclosed by
## route_intel(). Hidden node types, enemy rolls, and rewards never enter scoring.
func choose_node(reachable: Array[Dictionary], intel: Dictionary, run: GameSaveState.RunState, risk_weight: float = 4.0) -> Dictionary:
	if reachable.is_empty() or run == null:
		return {}
	var facts: Dictionary = intel.get("nodes", {})
	var resources: Dictionary = run.resources
	var hp_ratio: float = float(resources.get("hp", 0.0)) / maxf(1.0, float(resources.get("maxHP", 1.0)))
	var hull_ratio: float = float(resources.get("hull", 0.0)) / maxf(1.0, float(resources.get("maxHull", 1.0)))
	var fuel_ratio: float = float(resources.get("fuel", 0.0)) / maxf(1.0, float(resources.get("maxFuel", 1.0)))
	var best: Dictionary = {}
	var best_score: float = -INF
	for node: Dictionary in reachable:
		var id: String = str(node.get("id", ""))
		var known: Dictionary = facts.get(id, {})
		var node_type: String = str(known.get("type", "UNKNOWN")) if bool(known.get("revealed", false)) else "UNKNOWN"
		var score: float = _base_value(node_type)
		if node_type == "REPAIR":
			score += 18.0 if hp_ratio < 0.55 or hull_ratio < 0.55 else 0.0
		if node_type == "FUEL":
			score += 22.0 if fuel_ratio < 0.4 else 0.0
		if node_type in ["ELITE", "BOUNTY", "BOSS"]:
			score -= risk_weight
		if node_type == "UNKNOWN":
			score -= 0.5
		if score > best_score or (is_equal_approx(score, best_score) and id < str(best.get("id", "~"))):
			best_score = score
			best = node.duplicate(true)
	return best

func _base_value(node_type: String) -> float:
	match node_type:
		"CACHE": return 5.0
		"EVENT", "QUEST": return 4.0
		"COMBAT": return 3.0
		"SHOP": return 2.0
		"REPAIR", "FUEL": return 1.0
		"ELITE", "BOUNTY": return 0.0
		"BOSS", "CHECKPOINT": return -1.0
		_: return 0.0
