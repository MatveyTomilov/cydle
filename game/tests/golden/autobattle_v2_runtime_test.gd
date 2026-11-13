extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/initial_save.json"))
	var meta: Dictionary = payload["meta"]
	var weapon: Dictionary = {}
	for item: Dictionary in meta["inventory"]:
		if str(item["itemId"]) == str(meta["equipment"]["MAIN"]):
			weapon = item
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": weapon}, "attributes": meta["operator"]["attributes"], "skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	if not check(bool(build.get("valid", false)), "v2_runtime: real starter weapon did not resolve"):
		return false
	var simulator: CombatSimulator = CombatSimulator.new()
	var config: Dictionary = {"combatRulesVersion": CombatState.V2_RULES_VERSION, "seed": "v2-runtime-real-weapon", "depth": 1, "build": build, "enemies": [{"templateId": "E01"}], "startEnergy": 100}
	var created: Dictionary = simulator.create_state(config)
	if not check(bool(created.get("ok", false)), "v2_runtime: factory adapter failed: %s" % str(created.get("error", ""))):
		return false
	var current: CombatState = created["state"]
	check(current.operator.attack_damage == float(build["mainWeapon"]["damage"]), "v2_runtime: actual weapon damage was replaced")
	check(current.tactics.is_empty(), "v2_runtime: programmable tactics entered V2")
	current = simulator.step_combat(current)["state"]
	check(not current.action_channel["active"].is_empty(), "v2_runtime: real weapon did not prepare")
	var restored: CombatState = CombatState.from_dictionary(current.to_dictionary(), build)
	if not check(restored != null, "v2_runtime: V2 channel snapshot did not restore"):
		return false
	var changed_build: Dictionary = build.duplicate(true)
	changed_build["mainWeapon"]["damage"] = float(changed_build["mainWeapon"]["damage"]) + 1.0
	check(CombatState.from_dictionary(current.to_dictionary(), changed_build) == null, "v2_runtime: changed build silently reinterpreted an active snapshot")
	for tick: int in range(150):
		var first: Dictionary = simulator.step_combat(current)
		var resumed: Dictionary = simulator.step_combat(restored)
		if not check(bool(first.get("ok", false)) and bool(resumed.get("ok", false)), "v2_runtime: shared simulator step failed"):
			return false
		current = first["state"]
		restored = resumed["state"]
	check(StateHash.new().state_hash(current.to_dictionary()) == StateHash.new().state_hash(restored.to_dictionary()), "v2_runtime: channel restore changed real combat")
	check(float(current.metrics.get("damageDealt", 0)) > 0, "v2_runtime: canonical damage path did no real damage")
	config["tactics"] = {"rules": [{"priority": 100}]}
	check(not bool(simulator.create_state(config).get("ok", true)), "v2_runtime: V1 tactics accepted")
	return failure_count == 0
