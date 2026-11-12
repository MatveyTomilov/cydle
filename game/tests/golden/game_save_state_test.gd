extends "res://tests/test_case.gd"

const STATE_PATH: String = "res://scripts/core/persistence/game_save_state.gd"

func run(_tree: SceneTree) -> bool:
	var state_script: Script = load(STATE_PATH) as Script
	if not check(state_script != null, "game_save_state: typed save model is missing"):
		return false
	var state_class: Variant = state_script.new()
	var payload: Dictionary = _valid_payload()
	var parsed: Dictionary = state_class.call("parse_payload", payload)
	if not check(bool(parsed.get("ok", false)), "game_save_state: valid payload was rejected: %s" % parsed.get("error", "")):
		return false
	var state: Object = parsed.get("state") as Object
	if not check(state != null, "game_save_state: parsed payload did not produce a typed state"):
		return false
	var serialized: Dictionary = state.call("to_payload")
	check(_json_equivalent(serialized, payload), "game_save_state: typed round trip changed the payload")
	var repository: Object = load("res://scripts/core/persistence/save_repository.gd").new()
	var test_directory: String = "user://game_save_test_%d" % Time.get_ticks_usec()
	repository.call("configure_directory", test_directory)
	var saved: Dictionary = repository.call("save_game", "native_slot", state, 1000)
	check(bool(saved.get("ok", false)), "game_save_state: repository rejected a valid typed game state: %s" % saved.get("error", ""))
	var loaded: Dictionary = repository.call("load_game", "native_slot")
	check(bool(loaded.get("ok", false)), "game_save_state: repository did not load a typed game state: %s" % loaded.get("error", ""))
	if bool(loaded.get("ok", false)):
		var loaded_state: Object = loaded.get("state") as Object
		check(loaded_state != null, "game_save_state: repository load did not return a typed state")
		if loaded_state != null:
			var loaded_payload: Dictionary = loaded_state.call("to_payload")
			check(_json_equivalent(loaded_payload, payload), "game_save_state: repository round trip changed the game payload")
	_cleanup_directory(test_directory)

	var bad_attributes: Dictionary = _valid_payload()
	bad_attributes["meta"]["operator"]["attributes"]["POW"] = 0
	var bad_attribute_result: Dictionary = state_class.call("parse_payload", bad_attributes)
	check(not bool(bad_attribute_result.get("ok", false)), "game_save_state: zero base attribute was accepted")

	var broken_reputation: Dictionary = _valid_payload()
	broken_reputation["meta"]["reputation"].erase("F_ECHO")
	var broken_reputation_result: Dictionary = state_class.call("parse_payload", broken_reputation)
	check(not bool(broken_reputation_result.get("ok", false)), "game_save_state: incomplete faction state was accepted")

	var unknown_template: Dictionary = _valid_payload()
	unknown_template["meta"]["inventory"][0]["templateId"] = "MISSING_TEMPLATE"
	var unknown_template_result: Dictionary = state_class.call("parse_payload", unknown_template)
	check(not bool(unknown_template_result.get("ok", false)), "game_save_state: inventory item with an unknown template was accepted")

	var invalid_skill: Dictionary = _valid_payload()
	invalid_skill["meta"]["skillIds"][0] = "MISSING_SKILL"
	var invalid_skill_result: Dictionary = state_class.call("parse_payload", invalid_skill)
	check(not bool(invalid_skill_result.get("ok", false)), "game_save_state: build with an unknown skill was accepted")

	var duplicate_equipment: Dictionary = _valid_payload()
	duplicate_equipment["meta"]["equipment"]["OFFHAND"] = duplicate_equipment["meta"]["equipment"]["MAIN"]
	var duplicate_equipment_result: Dictionary = state_class.call("parse_payload", duplicate_equipment)
	check(not bool(duplicate_equipment_result.get("ok", false)), "game_save_state: one owned item equipped in two slots was accepted")

	var missing_owned_item: Dictionary = _valid_payload()
	missing_owned_item["meta"]["equipment"]["MAIN"] = "missing-item"
	var missing_owned_result: Dictionary = state_class.call("parse_payload", missing_owned_item)
	check(not bool(missing_owned_result.get("ok", false)), "game_save_state: equipment without an owned inventory item was accepted")

	var active_payload: Dictionary = _valid_payload()
	active_payload["run"] = _valid_run(active_payload["meta"])
	active_payload["run"]["eventsSeen"] = ["EV19"]
	active_payload["run"]["serviceScrapFuelCounts"] = {"fuel": 2}
	active_payload["run"]["shippedCheckpointIds"] = ["cp-1"]
	active_payload["run"]["pendingTravelDeltaMs"] = -5000
	active_payload["run"]["pendingCombatEffects"] = {"initialTempShield": 50.0, "extraHeat": 12.0}
	active_payload["run"]["pendingNextCombat"]["forceBounty"] = true
	active_payload["run"]["lastCommandId"] = "cmd-active"
	var active_result: Dictionary = state_class.call("parse_payload", active_payload)
	check(bool(active_result.get("ok", false)), "game_save_state: valid active run was rejected: %s" % active_result.get("error", ""))
	if bool(active_result.get("ok", false)):
		var active_state: Object = active_result.get("state") as Object
		check(_json_equivalent(active_state.call("to_payload"), active_payload), "game_save_state: active RUN roundtrip lost run fields")
	var invalid_pending: Dictionary = _valid_payload()
	invalid_pending["run"] = _valid_run(invalid_pending["meta"])
	invalid_pending["run"]["pendingTravelDeltaMs"] = 60001
	var invalid_pending_result: Dictionary = state_class.call("parse_payload", invalid_pending)
	check(not bool(invalid_pending_result.get("ok", false)), "game_save_state: out-of-range pending travel effect was accepted")

	var bad_combat_snapshot: Dictionary = _valid_payload()
	bad_combat_snapshot["run"] = _valid_run(bad_combat_snapshot["meta"])
	bad_combat_snapshot["run"]["combatSnapshot"] = {"simTimeMs": -1}
	var bad_combat_result: Dictionary = state_class.call("parse_payload", bad_combat_snapshot)
	check(not bool(bad_combat_result.get("ok", false)), "game_save_state: invalid combat snapshot was accepted")

	var missing_run_item: Dictionary = _valid_payload()
	missing_run_item["run"] = _valid_run(missing_run_item["meta"])
	missing_run_item["run"]["equipment"]["MAIN"] = "missing-run-item"
	var missing_run_item_result: Dictionary = state_class.call("parse_payload", missing_run_item)
	check(not bool(missing_run_item_result.get("ok", false)), "game_save_state: run equipment without owned item was accepted")

	var duplicate_run_item: Dictionary = _valid_payload()
	duplicate_run_item["run"] = _valid_run(duplicate_run_item["meta"])
	duplicate_run_item["run"]["equipment"]["OFFHAND"] = duplicate_run_item["run"]["equipment"]["MAIN"]
	var duplicate_run_item_result: Dictionary = state_class.call("parse_payload", duplicate_run_item)
	check(not bool(duplicate_run_item_result.get("ok", false)), "game_save_state: one run item equipped in two slots was accepted")
	return failure_count == 0

func _valid_payload() -> Dictionary:
	var created: Dictionary = GameSaveFactory.new().create_initial_payload("save-native-test", 1000)
	if not bool(created.get("ok", false)):
		push_error("game_save_state: starter factory failed: %s" % str(created.get("error", "")))
		return {}
	return created["payload"]

func _valid_run(meta: Dictionary) -> Dictionary:
	return {
		"seed": "native-run-seed", "depth": 1, "biome": "B01", "graph": {}, "equipment": meta["equipment"].duplicate(true), "currentNodeId": "START",
		"visitedNodeIds": [], "clearedNodeIds": [], "eventsSeen": [], "phase": "ROUTE", "wanted": 0.0, "revealLevel": 0,
		"resources": {"fuel": 24.0, "maxFuel": 24.0, "hull": 100.0, "maxHull": 100.0, "hp": 300.0, "maxHP": 300.0, "shield": 75.0, "maxShield": 75.0, "energy": 100.0, "heat": 0.0, "gameTimeMs": 0.0},
		"runWallet": {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0},
		"unsecuredCargo": [], "shippedCargo": [], "grantIds": [], "commandIds": [], "serviceScrapFuelCounts": {}, "shippedCheckpointIds": [],
		"pendingTravelDeltaMs": 0, "pendingCombatEffects": {"initialTempShield": 0.0, "extraHeat": 0.0},
		"pendingNextCombat": {"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false, "bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false, "alliedTurret": false, "extraRareOnElite": false},
		"combatResult": null, "lastCommandId": null, "combatSnapshot": null,
		"worldRng": {"stream": "world", "state": [1, 2, 3, 4], "calls": 0},
		"lootRng": {"stream": "loot", "state": [1, 2, 3, 4], "calls": 0},
	}

func _cleanup_directory(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _json_equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return float(left) == float(right)
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
