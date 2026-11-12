extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
const DOT_FIXTURE: String = "res://tests/fixtures/combat/dot_replay.json"

func run(_tree: SceneTree) -> bool:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary(DOT_FIXTURE)
	if not check(not meta.is_empty() and not fixture.is_empty(), "dot_status: starter-save or status replay fixture is missing"):
		return false
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "dot_status: starter main weapon did not parse")
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	var config: Dictionary = fixture.get("config", {})
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": config.get("seed", ""), "depth": config.get("depth", 0), "biome": config.get("biome", "B01"),
		"nodeType": config.get("nodeType", "COMBAT"), "build": build, "enemies": [config.get("enemy", {})],
		"tactics": config.get("tactics", {}), "maxDurationMs": config.get("maxDurationMs", 180000),
	})
	if not check(bool(initialized.get("ok", false)), "dot_status: combat initialization failed"):
		return false
	var original: CombatState = initialized["state"] as CombatState
	var simulator: CombatSimulator = CombatSimulator.new()
	var status: Dictionary = fixture.get("status", {})
	var applied: Dictionary = simulator.apply_status(original, "operator", "enemy:0", str(status.get("id", "")), {"snapshot": status.get("snapshot", 0.0)})
	if not check(bool(applied.get("ok", false)), "dot_status: apply_status failed: %s" % str(applied.get("error", ""))):
		return false
	var state: CombatState = applied["state"] as CombatState
	check(original.enemies[0].statuses.is_empty(), "dot_status: applying a status mutated its source state")
	check(_json_equivalent(state.log[state.log.size() - 1], fixture.get("appliedEvent", {})), "dot_status: STATUS_APPLY event differs from legacy oracle")
	for frame: Dictionary in fixture.get("frames", []):
		var previous_log_length: int = state.log.size()
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "dot_status: tick failed at %d ms: %s" % [state.time_ms + 100, str(stepped.get("error", ""))]):
			return false
		state = stepped["state"] as CombatState
		var actual: Dictionary = {
			"timeMs": state.time_ms, "rng": state.rng, "nextEventId": state.next_event_id,
			"metrics": state.metrics, "outcome": state.outcome if not state.outcome.is_empty() else null,
			"operator": {"hp": state.operator.hp, "shield": state.operator.shield, "statuses": state.operator.statuses},
			"enemies": _enemy_frames(state.enemies), "events": state.log.slice(previous_log_length),
		}
		check(_json_equivalent(actual, frame), "dot_status: replay diverged at %d ms" % int(frame.get("timeMs", -1)))
	return failure_count == 0

func _enemy_frames(actors: Array[CombatActorState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: CombatActorState in actors:
		result.append({"hp": actor.hp, "shield": actor.shield, "statuses": actor.statuses, "damageTaken": actor.damage_taken})
	return result

func _read_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}

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
