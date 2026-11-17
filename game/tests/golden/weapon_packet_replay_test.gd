extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
const REPLAY_FIXTURE: String = "res://tests/fixtures/combat/weapon_packet_replays.json"

func run(_tree: SceneTree) -> bool:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var cases: Array = _read_array(REPLAY_FIXTURE)
	if not check(not meta.is_empty() and cases.size() == 5, "weapon_packet_replay: starter save or weapon cases are missing"):
		return false
	var attributes: Dictionary = meta.get("operator", {}).get("attributes", {})
	for replay: Dictionary in cases:
		var item: ItemInstance = ItemInstance.new()
		if not check(item.instantiate_from_dictionary(replay.get("item", {})), "weapon_packet_replay: %s item did not parse" % replay.get("templateId", "?")):
			return false
		var build: Dictionary = BuildResolver.new().resolve_build({
			"equipment": {"MAIN": item}, "attributes": attributes,
			"skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
		})
		if not check(bool(build.get("valid", false)), "weapon_packet_replay: %s build failed: %s" % [replay.get("templateId", "?"), build.get("issues", [])]):
			return false
		var initialized: Dictionary = CombatSimulator.new().create_state({
			"seed": "basic-auto-replay", "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build,
			"enemies": [{"templateId": "E01"}], "tactics": {"id": "EMPTY", "name": "Empty", "rules": []}, "maxDurationMs": 3000,
		})
		if not check(bool(initialized.get("ok", false)), "weapon_packet_replay: %s combat initialization failed: %s" % [replay.get("templateId", "?"), initialized.get("error", "")]):
			return false
		var state: CombatState = initialized["state"] as CombatState
		var simulator: CombatSimulator = CombatSimulator.new()
		for frame: Dictionary in replay.get("frames", []):
			var previous_log_length: int = state.log.size()
			var stepped: Dictionary = simulator.step_combat(state)
			if not check(bool(stepped.get("ok", false)), "weapon_packet_replay: %s step failed: %s" % [replay.get("templateId", "?"), stepped.get("error", "")]):
				return false
			state = stepped["state"] as CombatState
			var actual: Dictionary = {
				"timeMs": state.time_ms, "rng": state.rng, "nextEventId": state.next_event_id,
				"metrics": state.metrics, "outcome": state.outcome if not state.outcome.is_empty() else null,
				"operator": _actor_frame(state.operator), "enemies": _enemy_frames(state.enemies),
				"events": state.log.slice(previous_log_length),
			}
			if not _json_equivalent(actual, frame):
				print("WEAPON_REPLAY_MISMATCH ", replay.get("templateId", "?"), " t=", frame.get("timeMs", -1), "\nactual=", JSON.stringify(actual), "\nexpected=", JSON.stringify(frame))
				check(false, "weapon_packet_replay: %s diverged at %d ms" % [replay.get("templateId", "?"), int(frame.get("timeMs", -1))])
	return failure_count == 0

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
