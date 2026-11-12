extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
func run(_tree: SceneTree) -> bool:
	_run_replay("main_skill_replay", "SK_BURST")
	_run_replay("pierce_skill_replay", "SK_PIERCE")
	return failure_count == 0

func _run_replay(replay_name: String, skill_id: String) -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/%s.json" % replay_name)
	if not check(not meta.is_empty() and not fixture.is_empty(), "%s: starter save or skill replay is missing" % replay_name):
		return
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "%s: starter weapon did not parse" % replay_name):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": [skill_id], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	if not check(bool(build.get("valid", false)), "%s: %s build was rejected" % [replay_name, skill_id]):
		return
	var config: Dictionary = fixture.get("config", {})
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": config.get("seed", ""), "depth": config.get("depth", 0), "biome": config.get("biome", "B01"),
		"nodeType": config.get("nodeType", "COMBAT"), "build": build,
		"enemies": [config.get("enemy", {})], "tactics": config.get("tactics", {}),
		"maxDurationMs": config.get("maxDurationMs", 180000),
	})
	if not check(bool(initialized.get("ok", false)), "%s: combat init failed: %s" % [replay_name, initialized.get("error", "")]):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	for frame: Dictionary in fixture.get("frames", []):
		var previous_log_length: int = state.log.size()
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "%s: step failed at %d ms: %s" % [replay_name, state.time_ms + 100, stepped.get("error", "")]):
			return
		state = stepped["state"] as CombatState
		var actual: Dictionary = {
			"timeMs": state.time_ms, "rng": state.rng, "nextEventId": state.next_event_id,
			"metrics": state.metrics, "outcome": state.outcome if not state.outcome.is_empty() else null,
			"operator": _actor_frame(state.operator), "enemies": _actor_frames(state.enemies),
			"events": state.log.slice(previous_log_length),
		}
		if not _json_equivalent(actual, frame):
			print("%s_MISMATCH t=" % replay_name.to_upper(), frame.get("timeMs", -1), " diff=", _first_difference(actual, frame, "root"), "\nactual=", JSON.stringify(actual), "\nexpected=", JSON.stringify(frame))
			check(false, "%s: mismatch at %d ms" % [replay_name, int(frame.get("timeMs", -1))])

func _actor_frame(actor: CombatActorState) -> Dictionary:
	return {
		"id": actor.id, "hp": actor.hp, "shield": actor.shield, "energy": actor.energy, "heat": actor.heat,
		"nextAttackAt": actor.next_attack_at, "alive": actor.alive, "flags": actor.flags, "counters": actor.counters,
		"cooldowns": actor.cooldowns, "cast": actor.cast, "damageDealt": actor.damage_dealt, "damageTaken": actor.damage_taken,
	}

func _actor_frames(actors: Array[CombatActorState]) -> Array[Dictionary]:
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

func _first_difference(left: Variant, right: Variant, path: String) -> String:
	if (left is int or left is float) and (right is int or right is float):
		return "" if absf(float(left) - float(right)) <= 0.000000001 else "%s numeric %s != %s" % [path, left, right]
	if left is Array and right is Array:
		if left.size() != right.size():
			return "%s size %d != %d" % [path, left.size(), right.size()]
		for index: int in range(left.size()):
			var diff: String = _first_difference(left[index], right[index], "%s[%d]" % [path, index])
			if not diff.is_empty():
				return diff
		return ""
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return "%s keys count %d != %d" % [path, left.size(), right.size()]
		for key: Variant in left.keys():
			if not right.has(key):
				return "%s missing key %s" % [path, key]
			var diff: String = _first_difference(left[key], right[key], "%s.%s" % [path, key])
			if not diff.is_empty():
				return diff
		return ""
	return "" if left == right else "%s value %s != %s" % [path, left, right]
