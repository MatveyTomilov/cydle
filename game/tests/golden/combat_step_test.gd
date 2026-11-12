extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
const REPLAY_FIXTURE: String = "res://tests/fixtures/combat/basic_auto_replay.json"

func run(_tree: SceneTree) -> bool:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary(REPLAY_FIXTURE)
	if not check(not meta.is_empty() and not fixture.is_empty(), "combat_step: starter-save or replay fixture is missing"):
		return false
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "combat_step: starter main weapon did not parse")
	var operator: Dictionary = meta.get("operator", {})
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": operator.get("attributes", {}),
		"skillIds": [], "passiveIds": [], "treeNodeIds": [],
		"attributePointsEarned": 0, "treePointsEarned": 0,
	})
	if not check(bool(build.get("valid", false)), "combat_step: baseline build was rejected"):
		return false
	var config: Dictionary = fixture.get("config", {})
	var enemy_specs: Array[Dictionary] = [config.get("enemy", {})]
	var state_result: Dictionary = CombatSimulator.new().create_state({
		"seed": config.get("seed", ""), "depth": config.get("depth", 0), "biome": config.get("biome", "B01"),
		"nodeType": config.get("nodeType", "COMBAT"), "build": build, "enemies": enemy_specs,
		"tactics": config.get("tactics", {}), "maxDurationMs": config.get("maxDurationMs", 180000),
	})
	if not check(bool(state_result.get("ok", false)), "combat_step: state initialization failed: %s" % str(state_result.get("error", ""))):
		return false
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = state_result["state"] as CombatState
	var expected_frames: Array = fixture.get("frames", [])
	var initial_payload: Dictionary = state.to_dictionary()
	for frame: Dictionary in expected_frames:
		var previous_log_length: int = state.log.size()
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "combat_step: tick failed: %s" % str(stepped.get("error", ""))):
			return false
		state = stepped["state"] as CombatState
		var actual_frame: Dictionary = {
			"timeMs": state.time_ms, "rng": state.rng, "nextEventId": state.next_event_id,
			"metrics": state.metrics, "outcome": state.outcome if not state.outcome.is_empty() else null,
			"operator": _actor_frame(state.operator), "enemies": _enemy_frames(state.enemies),
			"events": state.log.slice(previous_log_length),
		}
		check(_json_equivalent(actual_frame, frame), "combat_step: replay diverged at t=%d ms" % int(frame.get("timeMs", -1)))
		if int(frame.get("timeMs", 0)) == 100:
			check(_json_equivalent(initial_payload, _initial_state_payload(state_result["state"])), "combat_step: advancing mutated the source state")
	return failure_count == 0

func _initial_state_payload(state_value: Variant) -> Dictionary:
	return (state_value as CombatState).to_dictionary()

func _actor_frame(actor: CombatActorState) -> Dictionary:
	return {
		"id": actor.id, "hp": actor.hp, "shield": actor.shield, "energy": actor.energy, "heat": actor.heat,
		"nextAttackAt": actor.next_attack_at, "alive": actor.alive, "flags": actor.flags,
		"counters": actor.counters, "damageDealt": actor.damage_dealt, "damageTaken": actor.damage_taken,
	}

func _enemy_frames(actors: Array[CombatActorState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: CombatActorState in actors:
		result.append(_actor_frame(actor))
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
