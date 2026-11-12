extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
const REPLAY_FIXTURE: String = "res://tests/fixtures/combat/status_effect_replays.json"

func run(_tree: SceneTree) -> bool:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var cases: Array = _read_array(REPLAY_FIXTURE)
	if not check(not meta.is_empty() and cases.size() == 13, "status_effect_replay: starter save or replay cases are missing"):
		return false
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "status_effect_replay: starter main weapon did not parse")
	var drone_item: ItemInstance = ItemInstance.new()
	check(drone_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["DRONE_1"])]), "status_effect_replay: starter drone did not parse")
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item, "DRONE_1": drone_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	var simulator: CombatSimulator = CombatSimulator.new()
	for replay: Dictionary in cases:
		var initialized: Dictionary = simulator.create_state({
			"seed": "basic-auto-replay", "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build,
			"enemies": [{"templateId": "E01"}], "tactics": {"id": "EMPTY", "name": "Empty", "rules": []}, "maxDurationMs": 3000,
		})
		if not check(bool(initialized.get("ok", false)), "status_effect_replay: initialization failed for %s" % replay.get("status", "?")):
			return false
		var state: CombatState = initialized["state"] as CombatState
		var target_id: String = str(replay.get("target", ""))
		var source_id: String = "enemy:0" if target_id == "operator" or target_id.begins_with("drone:") else "operator"
		if str(replay.get("status", "")) in ["SHIELD_LEAK", "SHIELD_REGEN_BUFF"]:
			var regen_target: CombatActorState = state.operator if target_id == "operator" else state.enemies[0]
			regen_target.shield = maxf(0.0, float(regen_target.base_sheet.get("maxShield", 0.0)) - 20.0)
			regen_target.flags["lastDamagedAt"] = -100000.0
		var applied: Dictionary = simulator.apply_status(state, source_id, target_id, str(replay.get("status", "")))
		if not check(bool(applied.get("ok", false)), "status_effect_replay: status apply failed for %s: %s" % [replay.get("status", "?"), applied.get("error", "")]):
			return false
		state = applied["state"] as CombatState
		for _tick: int in range(40):
			var stepped: Dictionary = simulator.step_combat(state)
			if not check(bool(stepped.get("ok", false)), "status_effect_replay: step failed for %s at %d ms: %s" % [replay.get("status", "?"), state.time_ms + 100, stepped.get("error", "")]):
				return false
			state = stepped["state"] as CombatState
		var actual: Dictionary = {
			"status": replay.get("status", ""), "target": target_id, "timeMs": state.time_ms,
			"rng": state.rng, "nextEventId": state.next_event_id, "metrics": state.metrics,
			"outcome": state.outcome,
			"operator": {"hp": state.operator.hp, "shield": state.operator.shield, "statuses": state.operator.statuses, "nextAttackAt": state.operator.next_attack_at},
			"drones": _drone_frames(state.drones),
			"enemies": _enemy_frames(state.enemies),
		}
		check(_json_equivalent(actual, replay), "status_effect_replay: %s diverged from TypeScript oracle" % replay.get("status", "?"))
	return failure_count == 0

func _enemy_frames(actors: Array[CombatActorState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: CombatActorState in actors:
		result.append({"hp": actor.hp, "shield": actor.shield, "statuses": actor.statuses, "nextAttackAt": actor.next_attack_at, "damageTaken": actor.damage_taken})
	return result

func _drone_frames(actors: Array[CombatActorState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: CombatActorState in actors:
		result.append({"hp": actor.hp, "shield": actor.shield, "statuses": actor.statuses, "nextAttackAt": actor.next_attack_at, "damageTaken": actor.damage_taken})
	return result

func _read_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}

func _read_array(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Array else []

func _json_equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) <= 0.000000001
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _json_equivalent(left[index], right[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left.keys():
			if not right.has(key) or not _json_equivalent(left[key], right[key]):
				return false
		return true
	return left == right
