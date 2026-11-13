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
	var first_step: Dictionary = simulator.step_combat(current)
	if not check(bool(first_step.get("ok", false)), "v2_runtime: first preparation step failed: %s" % str(first_step.get("error", ""))):
		return false
	current = first_step["state"]
	check(not current.action_channel["active"].is_empty(), "v2_runtime: real weapon did not prepare")
	var restored: CombatState = CombatState.from_dictionary(current.to_dictionary(), build)
	if not check(restored != null, "v2_runtime: V2 channel snapshot did not restore"):
		return false
	var forged_target_snapshot: Dictionary = current.to_dictionary()
	var original_targets: Array = forged_target_snapshot["actionChannel"]["active"].get("targetIds", [])
	if not original_targets.is_empty():
		forged_target_snapshot["actionChannel"]["active"]["targetIds"] = ["enemy:1"] if str(original_targets[0]) != "enemy:1" else ["enemy:0"]
		check(CombatState.from_dictionary(forged_target_snapshot, build) == null, "v2_runtime: restore accepted a target that differed from the compiled action's doctrine selection")
	var changed_build: Dictionary = build.duplicate(true)
	changed_build["mainWeapon"]["damage"] = float(changed_build["mainWeapon"]["damage"]) + 1.0
	check(CombatState.from_dictionary(current.to_dictionary(), changed_build) == null, "v2_runtime: changed build silently reinterpreted an active snapshot")
	var sidearm_build: Dictionary = build.duplicate(true)
	sidearm_build["sidearm"] = {"itemId": "SIDEARM:fixture", "damage": 1.0, "type": "KINETIC"}
	check(CombatState.from_dictionary(current.to_dictionary(), sidearm_build) == null, "v2_runtime: sidearm change silently reinterpreted an active snapshot")
	var old_v2: Dictionary = current.to_dictionary()
	old_v2["combatRulesVersion"] = "cydle-combat-2.1-development"
	check(CombatState.from_dictionary(old_v2, build) == null, "v2_runtime: older target/action snapshots were accepted without explicit migration")
	var forged: Dictionary = current.to_dictionary()
	forged["actionChannel"]["active"]["action"]["sourceId"] = "fake-weapon"
	check(CombatState.from_dictionary(forged, build) == null, "v2_runtime: unauthored action source restored")
	for tick: int in range(150):
		var first: Dictionary = simulator.step_combat(current)
		var resumed: Dictionary = simulator.step_combat(restored)
		if not check(bool(first.get("ok", false)) and bool(resumed.get("ok", false)), "v2_runtime: shared simulator step failed"):
			return false
		current = first["state"]
		restored = resumed["state"]
	check(StateHash.new().state_hash(current.to_dictionary()) == StateHash.new().state_hash(restored.to_dictionary()), "v2_runtime: channel restore changed real combat")
	check(float(current.metrics.get("damageDealt", 0)) > 0, "v2_runtime: canonical damage path did no real damage")
	var prepared: Dictionary = {}
	var linked: bool = false
	var linked_damage: bool = false
	for event: Dictionary in current.log:
		if str(event.get("kind", "")) == "ACTION_PREPARE":
			prepared[str(event.get("actionId", ""))] = event
		if str(event.get("kind", "")) == "ATTACK" and str(event.get("actorId", "")) == "operator":
			var parent: Dictionary = prepared.get(str(event.get("actionId", "")), {})
			linked = linked or (not parent.is_empty() and int(event.get("causeId", 0)) == int(parent.get("eventId", -1)) and str(event.get("sourceId", "")) == str(weapon["itemId"]))
		if str(event.get("kind", "")) == "DAMAGE" and str(event.get("actorId", "")) == "operator":
			linked_damage = linked_damage or prepared.has(str(event.get("originActionId", "")))
	check(linked, "v2_runtime: real attack lost preparation/item causal identity")
	check(linked_damage, "v2_runtime: canonical damage trace lost its prepared action identity")
	var retarget_config: Dictionary = config.duplicate(true)
	retarget_config["seed"] = "v2-runtime-target-died-during-windup"
	retarget_config["enemies"] = [{"templateId": "E01"}, {"templateId": "E01"}]
	var retarget_created: Dictionary = simulator.create_state(retarget_config)
	if not check(bool(retarget_created.get("ok", false)), "v2_runtime: retarget scenario setup failed"):
		return false
	var retarget_state: CombatState = simulator.step_combat(retarget_created["state"])["state"]
	check(retarget_state.action_channel["active"].get("targetIds", []) == ["enemy:0"], "v2_runtime: initial highest-threat target was not locked")
	retarget_state.enemies[0].alive = false
	var reacquired: bool = false
	var hit_replacement: bool = false
	for tick: int in range(20):
		var retarget_step: Dictionary = simulator.step_combat(retarget_state)
		if not check(bool(retarget_step.get("ok", false)), "v2_runtime: target death during preparation failed: %s" % str(retarget_step.get("error", ""))):
			return false
		retarget_state = retarget_step["state"]
		for event: Dictionary in retarget_state.log:
			if str(event.get("kind", "")) == "TARGET_REACQUIRED" and str(event.get("targetId", "")) == "enemy:1": reacquired = true
			if str(event.get("kind", "")) == "ATTACK" and str(event.get("targetId", "")) == "enemy:1": hit_replacement = true
	check(reacquired and hit_replacement and float(retarget_state.enemies[1].hp) < float(retarget_created["state"].enemies[1].hp), "v2_runtime: dead locked target was not reacquired and hit through V2")
	var skill_build: Dictionary = _build_with_skill("SK_PIERCE")
	if not check(bool(skill_build.get("valid", false)), "v2_runtime: BuildResolver rejected the real main skill fixture"):
		return false
	var forged_skill_build: Dictionary = skill_build.duplicate(true)
	forged_skill_build["skills"][0]["coefficient"] = float(forged_skill_build["skills"][0].get("coefficient", 1.0)) + 100.0
	var forged_skill_result: Dictionary = simulator.create_state({"combatRulesVersion": CombatState.V2_RULES_VERSION, "seed": "v2-runtime-forged-skill", "depth": 1, "build": forged_skill_build, "enemies": [{"templateId": "E01"}], "startEnergy": 100})
	check(not bool(forged_skill_result.get("ok", true)) and str(forged_skill_result.get("error", "")).contains("NON_CANONICAL_V2_SKILL"), "v2_runtime: V2 accepted a mutated noncanonical skill definition")
	var skill_config: Dictionary = {"combatRulesVersion": CombatState.V2_RULES_VERSION, "seed": "v2-runtime-real-skill", "depth": 1, "build": skill_build, "enemies": [{"templateId": "E01"}], "startEnergy": 100}
	var skill_created: Dictionary = simulator.create_state(skill_config)
	if not check(bool(skill_created.get("ok", false)), "v2_runtime: real main skill adapter failed: %s" % str(skill_created.get("error", ""))):
		return false
	var skill_state: CombatState = skill_created["state"]
	var skill_before_hp: float = skill_state.enemies[0].hp
	var skill_before_energy: float = skill_state.operator.energy
	var skill_committed: bool = false
	var skill_damaged_target: bool = false
	var skill_action_id: String = ""
	var skill_restored: CombatState = null
	for tick: int in range(40):
		var skill_step: Dictionary = simulator.step_combat(skill_state)
		if not check(bool(skill_step.get("ok", false)), "v2_runtime: real skill step failed: %s" % str(skill_step.get("error", ""))):
			return false
		skill_state = skill_step["state"]
		if tick == 0:
			check(str(skill_state.action_channel.get("active", {}).get("action", {}).get("sourceId", "")) == "SK_PIERCE", "v2_runtime: real skill was not prepared through V2 channel")
			skill_restored = CombatState.from_dictionary(skill_state.to_dictionary(), skill_build)
			if not check(skill_restored != null, "v2_runtime: prepared skill and locked target did not restore"):
				return false
		elif skill_restored != null:
			var resumed_skill_step: Dictionary = simulator.step_combat(skill_restored)
			if not check(bool(resumed_skill_step.get("ok", false)), "v2_runtime: restored skill action failed: %s" % str(resumed_skill_step.get("error", ""))):
				return false
			skill_restored = resumed_skill_step["state"]
			check(StateHash.new().state_hash(skill_state.to_dictionary()) == StateHash.new().state_hash(skill_restored.to_dictionary()), "v2_runtime: restoring a prepared skill changed its commit effects")
		for event: Dictionary in skill_state.log:
			if str(event.get("kind", "")) == "ACTION_PREPARE" and str(event.get("sourceId", "")) == "SK_PIERCE": skill_action_id = str(event.get("actionId", ""))
			if str(event.get("kind", "")) == "SKILL_USE" and str(event.get("skillId", "")) == "SK_PIERCE":
				skill_committed = true
				check(str(event.get("targetId", "")) == "enemy:0" and str(event.get("actionId", "")) == skill_action_id, "v2_runtime: V2 skill commit lost its prepared target or action identity")
			if str(event.get("kind", "")) == "DAMAGE" and str(event.get("skillId", "")) == "SK_PIERCE" and str(event.get("targetId", "")) == "enemy:0": skill_damaged_target = true
		if skill_committed: break
	check(skill_committed and skill_damaged_target and skill_state.enemies[0].hp < skill_before_hp, "v2_runtime: BuildResolver skill did not execute real damage in shared simulator")
	check(skill_state.operator.energy < skill_before_energy and float(skill_state.operator.cooldowns.get("SK_PIERCE", 0.0)) > float(skill_state.time_ms), "v2_runtime: skill cost/cooldown mismatch energy=%.2f→%.2f cooldown=%.2f time=%d" % [skill_before_energy, skill_state.operator.energy, float(skill_state.operator.cooldowns.get("SK_PIERCE", 0.0)), skill_state.time_ms])
	check(int(skill_state.action_channel.get("cooldowns", {}).get("skill:SK_PIERCE", 0)) > skill_state.time_ms, "v2_runtime: action channel lost the committed skill cooldown")
	var expected_skill_ready_at: int = -1
	for event: Dictionary in skill_state.log:
		if str(event.get("kind", "")) == "ACTION_PREPARE" and str(event.get("sourceId", "")) == "SK_PIERCE":
			var prepared_action: Dictionary = event.get("data", {})
			var prepare_at: int = int(event.get("timestamp", 0))
			expected_skill_ready_at = maxi(prepare_at + int(prepared_action.get("prepareMs", 0)) + int(prepared_action.get("recoveryMs", 0)), prepare_at + int(prepared_action.get("cooldownMs", 0)))
			break
	check(int(skill_state.action_channel.get("cooldowns", {}).get("skill:SK_PIERCE", 0)) == expected_skill_ready_at, "v2_runtime: cooldown did not expire from cast start after accounting for recovery")
	for _recovery_tick: int in range(8):
		if skill_state.action_channel.get("active", {}).is_empty(): break
		var recovery_step: Dictionary = simulator.step_combat(skill_state)
		if not check(bool(recovery_step.get("ok", false)), "v2_runtime: skill recovery step failed: %s" % str(recovery_step.get("error", ""))):
			return false
		skill_state = recovery_step["state"]
		if skill_restored != null:
			var resumed_recovery: Dictionary = simulator.step_combat(skill_restored)
			if not check(bool(resumed_recovery.get("ok", false)), "v2_runtime: restored skill recovery step failed"):
				return false
			skill_restored = resumed_recovery["state"]
	check(str(skill_state.action_channel.get("active", {}).get("action", {}).get("classId", "")) == "BASIC_ATTACK", "v2_runtime: main action channel did not return to a ready weapon after skill recovery")
	var skill_cooldown_rejected: bool = false
	for event: Dictionary in skill_state.log:
		if str(event.get("kind", "")) == "ACTION_UNAVAILABLE" and str(event.get("data", {}).get("actionId", "")) == "skill:SK_PIERCE" and str(event.get("data", {}).get("reason", "")) == "COOLDOWN":
			skill_cooldown_rejected = true
	check(skill_cooldown_rejected, "v2_runtime: skill cooldown did not gate the next channel selection")
	if skill_restored != null:
		check(StateHash.new().state_hash(skill_state.to_dictionary()) == StateHash.new().state_hash(skill_restored.to_dictionary()), "v2_runtime: resumed skill recovery diverged")
	var cdr_config: Dictionary = skill_config.duplicate(true)
	cdr_config["seed"] = "v2-runtime-cdr-expires-during-windup"
	var cdr_created: Dictionary = simulator.create_state(cdr_config)
	if check(bool(cdr_created.get("ok", false)), "v2_runtime: CDR expiry scenario failed to initialize"):
		var cdr_state: CombatState = cdr_created["state"]
		cdr_state.operator.buffs.append({"id": "test-cdr-window", "expiresAt": 150.0, "mods": [{"stat": "cooldownRecovery", "op": "INCREASED", "value": 50.0, "source": {"id": "test-cdr", "name": "test", "kind": "test"}}]})
		var cdr_expected_ready: int = -1
		var cdr_committed: bool = false
		for _tick: int in range(8):
			var cdr_step: Dictionary = simulator.step_combat(cdr_state)
			if not check(bool(cdr_step.get("ok", false)), "v2_runtime: CDR expiry step failed"): break
			cdr_state = cdr_step["state"]
			for event: Dictionary in cdr_state.log:
				if str(event.get("kind", "")) == "ACTION_PREPARE" and str(event.get("sourceId", "")) == "SK_PIERCE":
					var cdr_prepared: Dictionary = event.get("data", {})
					cdr_expected_ready = int(event.get("timestamp", 0)) + int(cdr_prepared.get("cooldownMs", 0))
				if str(event.get("kind", "")) == "SKILL_USE" and str(event.get("skillId", "")) == "SK_PIERCE": cdr_committed = true
			if cdr_committed: break
		check(cdr_expected_ready > 0 and cdr_committed, "v2_runtime: CDR test did not prepare and commit SK_PIERCE")
		check(int(cdr_state.action_channel.get("cooldowns", {}).get("skill:SK_PIERCE", 0)) == cdr_expected_ready and int(cdr_state.operator.cooldowns.get("SK_PIERCE", 0.0)) == cdr_expected_ready, "v2_runtime: cooldown was recalculated after its captured CDR expired during PREPARE")
	var shocked: CombatState = created["state"].clone()
	simulator._add_simple_status(shocked, shocked.enemies[0], shocked.operator, "SHOCK", 1000)
	shocked = simulator.step_combat(shocked)["state"]
	var slowed: Dictionary = shocked.action_channel["active"]["action"]
	var normal: Dictionary = CombatFactory.new().compile_v2_weapon_action(build)
	check(int(slowed["prepareMs"]) + int(slowed["recoveryMs"]) > int(normal["prepareMs"]) + int(normal["recoveryMs"]), "v2_runtime: SHOCK did not slow new action timing")
	check(CombatState.from_dictionary(shocked.to_dictionary(), build) != null, "v2_runtime: slowed preparation failed snapshot restore")
	for tick: int in range(20):
		shocked = simulator.step_combat(shocked)["state"]
	var recovered_action: Dictionary = shocked.action_channel["active"].get("action", {})
	check(not recovered_action.is_empty() and int(recovered_action["prepareMs"]) == int(normal["prepareMs"]), "v2_runtime: expired SHOCK left permanent slow timing")
	config["tactics"] = {"rules": [{"priority": 100}]}
	check(not bool(simulator.create_state(config).get("ok", true)), "v2_runtime: V1 tactics accepted")
	var unsupported_trigger_config: Dictionary = {"combatRulesVersion": CombatState.V2_RULES_VERSION, "seed": "v2-unsupported-item-trigger", "depth": 1, "build": build.duplicate(true), "enemies": [{"templateId": "E01"}]}
	unsupported_trigger_config["build"]["triggerEffects"] = [{"sourceKind": "item", "sourceId": "ITEM:UNPORTED", "effect": {"id": "unported", "event": "ON_HIT", "action": {"kind": "applyStatus", "status": "VIRUS", "target": "target"}}}]
	var unsupported_trigger: Dictionary = simulator.create_state(unsupported_trigger_config)
	check(not bool(unsupported_trigger.get("ok", true)) and str(unsupported_trigger.get("error", "")).contains("UNSUPPORTED_V2_TRIGGER"), "v2_runtime: item trigger configuration was not explicitly rejected")
	return failure_count == 0

func _build_with_skill(skill_id: String) -> Dictionary:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/initial_save.json"))
	var meta: Dictionary = payload.get("meta", {})
	var weapon: ItemInstance = ItemInstance.new()
	for item: Dictionary in meta.get("inventory", []):
		if str(item.get("itemId", "")) == str(meta.get("equipment", {}).get("MAIN", "")):
			weapon.instantiate_from_dictionary(item)
			break
	return BuildResolver.new().resolve_build({"equipment": {"MAIN": weapon}, "attributes": meta.get("operator", {}).get("attributes", {}), "skillIds": [skill_id], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
