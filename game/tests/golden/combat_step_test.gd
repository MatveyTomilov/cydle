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
	var threshold_actor: CombatActorState = state.operator.clone()
	threshold_actor.hp = float(threshold_actor.base_sheet.get("maxHP", 1.0)) * 0.5
	check(not simulator._eval_tactic_condition(state, threshold_actor, {"kind": "hpBelow", "value": 45.0}, null), "combat_step: legacy 45-percent HP condition did not retain its intended threshold")
	check(simulator._eval_tactic_condition(state, threshold_actor, {"kind": "hpBelow", "value": 0.55}, null), "combat_step: fractional HP condition stopped using its 0–1 threshold")
	var escalation_state_result: Dictionary = simulator.create_state({
		"seed": "endgame-escalation-combat", "depth": 13, "biome": "B01", "nodeType": "ELITE",
		"build": build, "enemies": [{"templateId": "E02", "elite": "EL_FAST"}], "tactics": config.get("tactics", {}),
		"coolingPenalty": 2.0, "enemyWindupMult": 0.8, "minimumEnemyTelegraphMs": 600,
		"elitePen": 10.0, "droneWar": true,
	})
	if check(bool(escalation_state_result.get("ok", false)), "combat_step: escalation combat state initialization failed"):
		var escalation_state: CombatState = escalation_state_result["state"] as CombatState
		var restored_escalation: CombatState = CombatState.from_dictionary(escalation_state.to_dictionary(), build)
		check(restored_escalation != null and restored_escalation.cooling_penalty == 2.0 and restored_escalation.enemy_windup_mult == 0.8 and restored_escalation.elite_pen == 10.0 and restored_escalation.drone_war, "combat_step: escalation combat modifiers did not survive the combat snapshot roundtrip")
		var jam_abilities: Array[Dictionary] = simulator._enemy_ability_definitions(escalation_state.enemies[0], escalation_state)
		check(jam_abilities.any(func(ability: Dictionary) -> bool: return str(ability.get("status", "")) == "DRONE_JAM"), "combat_step: DRONE_WAR elite did not gain its telegraphed drone-jam ability")
		var telegraph_ability: Dictionary = {"id": "escalation-telegraph", "kind": "heavyAttack", "windupMs": 500, "telegraphMs": 500, "interruptible": true}
		simulator._start_enemy_ability(escalation_state, escalation_state.enemies[0], telegraph_ability)
		check(is_equal_approx(float(escalation_state.enemies[0].cast.get("resolveAt", 0.0)), 600.0), "combat_step: HUNT_FAST violated its 600 ms telegraph floor")
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
	_test_support_relay(config, operator)
	_test_attack_counter_items(config, operator)
	_test_direct_status_tree_trigger(config, build)
	_test_direct_hit_trigger_actions(config, build)
	_test_on_kill_triggers(config, build)
	_test_before_hit_and_shield_absorb(config, build)
	_test_unsupported_trigger_is_rejected(config, build)
	_test_event_turret_ally(config, build)
	return failure_count == 0

func _test_unsupported_trigger_is_rejected(config: Dictionary, build: Dictionary) -> void:
	var trigger_build: Dictionary = build.duplicate(true)
	trigger_build["triggerEffects"] = [{
		"sourceId": "U01_discharge", "sourceName": "Перегрузка", "sourceKind": "item",
		"effect": {"type": "trigger", "id": "U01_discharge", "event": "ON_HEAT_FULL", "action": {"kind": "consumeShieldForDamage", "fraction": 0.5}},
	}]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "unsupported-trigger-guard", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": "COMBAT", "build": trigger_build, "enemies": [config.get("enemy", {})], "tactics": config.get("tactics", {}),
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: trigger guard fixture failed to initialize"):
		return
	var stepped: Dictionary = CombatSimulator.new().step_combat(initialized["state"] as CombatState)
	check(not bool(stepped.get("ok", false)) and str(stepped.get("error", "")).contains("триггеры"), "combat_step: unsupported ON_HEAT_FULL trigger was silently accepted")

func _test_direct_hit_trigger_actions(config: Dictionary, build: Dictionary) -> void:
	var trigger_build: Dictionary = build.duplicate(true)
	trigger_build["triggerEffects"] = [
		{"sourceId": "K4B", "sourceKind": "tree", "effect": {"type": "trigger", "id": "K4B", "event": "ON_HIT", "chance": 1.0, "action": {"kind": "restoreShield", "amount": 12}}},
		{"sourceId": "U12", "sourceKind": "item", "effect": {"type": "trigger", "id": "U12_leech", "event": "ON_HIT", "chance": 1.0, "condition": {"kind": "targetStatus", "status": "VIRUS", "minStacks": 1}, "action": {"kind": "restoreEnergy", "amount": 4, "perSecondCap": 12}}},
		{"sourceId": "X2", "sourceKind": "tree", "effect": {"type": "trigger", "id": "X2", "event": "ON_HIT", "chance": 1.0, "action": {"kind": "extendStatus", "status": "VIRUS", "ms": 1000, "stacks": 1}}},
		{"sourceId": "X4", "sourceKind": "tree", "effect": {"type": "trigger", "id": "X4", "event": "ON_HIT", "chance": 1.0, "action": {"kind": "secondaryDamage", "basis": "techPower", "coefficient": 0.3, "damageType": "DIGITAL", "targeting": "target", "canProc": false}}},
	]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "direct-trigger-action-fixture", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": "COMBAT", "build": trigger_build, "enemies": [config.get("enemy", {})], "tactics": config.get("tactics", {}),
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: direct-hit action fixture failed to initialize"):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	var target: CombatActorState = state.enemies[0]
	target.statuses["VIRUS"] = [{"sourceId": "test", "sourceActorId": state.operator.id, "expiresAt": 2000.0, "nextTickAt": 1000.0, "snapshot": 0.0, "stacks": 1}]
	state.operator.shield = maxf(0.0, float(state.operator.base_sheet.get("maxShield", 0.0)) - 20.0)
	state.operator.energy = maxf(0.0, state.operator.energy - 10.0)
	var energy_before: float = state.operator.energy
	var shield_before: float = state.operator.shield
	var enemy_hp_before: float = target.hp
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("direct-trigger-action-fixture", "triggers")
	simulator._dispatch_direct_status_triggers(state, rng, state.operator, target, "KINETIC", "direct-trigger", "", true, 1.0)
	check(is_equal_approx(state.operator.shield, shield_before + 12.0), "combat_step: K4B ON_HIT did not restore shield")
	check(is_equal_approx(state.operator.energy, energy_before + 4.0), "combat_step: U12 ON_HIT did not restore energy against VIRUS")
	check(float(target.statuses["VIRUS"][0].get("expiresAt", 0.0)) == 3000.0, "combat_step: X2 ON_HIT did not extend VIRUS duration")
	check(target.hp < enemy_hp_before, "combat_step: X4 ON_HIT did not deal secondary damage")

func _test_on_kill_triggers(config: Dictionary, build: Dictionary) -> void:
	var trigger_build: Dictionary = build.duplicate(true)
	trigger_build["triggerEffects"] = [
		{"sourceId": "K3D", "sourceKind": "tree", "effect": {"type": "trigger", "id": "K3D", "event": "ON_KILL", "chance": 1.0, "icdMs": 2000, "requireKillType": "KINETIC", "action": {"kind": "restoreEnergy", "amount": 4}}},
		{"sourceId": "H3C", "sourceKind": "tree", "effect": {"type": "trigger", "id": "H3C", "event": "ON_KILL", "requireKillType": "ENERGY", "action": {"kind": "changeHeat", "amount": -15}}},
		{"sourceId": "U02", "sourceKind": "item", "effect": {"type": "trigger", "id": "U02_echo", "event": "ON_KILL", "requireDirect": true, "requireKillType": "DIGITAL", "action": {"kind": "secondaryDamage", "basis": "techPower", "coefficient": 0.6, "damageType": "DIGITAL", "targeting": "otherEnemy", "canProc": false}}},
		{"sourceId": "N4C", "sourceKind": "tree", "effect": {"type": "trigger", "id": "N4C", "event": "ON_KILL", "condition": {"kind": "targetStatus", "status": "VIRUS"}, "action": {"kind": "transferVirus", "stacks": 2}}},
	]
	var enemy_specs: Array[Dictionary] = [config.get("enemy", {}), config.get("enemy", {}), config.get("enemy", {}), config.get("enemy", {})]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "on-kill-trigger-fixture", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": "COMBAT", "build": trigger_build, "enemies": enemy_specs, "tactics": config.get("tactics", {}),
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: ON_KILL fixture failed to initialize"):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	var max_energy: float = float(state.operator.base_sheet.get("maxEnergy", 0.0))
	state.operator.energy = maxf(0.0, max_energy - 20.0)
	var energy_before: float = state.operator.energy
	state.operator.heat = 50.0
	var targets: Array[CombatActorState] = state.enemies
	for index: int in range(3):
		var killed: CombatActorState = targets[index]
		killed.hp = 0.0
		killed.last_hit_by_id = state.operator.id
		killed.last_hit_can_proc = true
		killed.last_hit_proc_weight = 1.0
		killed.last_hit_direct = true
		killed.last_hit_event_source = "DIRECT"
		killed.last_hit_action_id = "on-kill:%d" % index
		killed.last_hit_origin_action_id = "on-kill:%d" % index
		killed.last_hit_cause_id = index + 1
	targets[0].last_hit_damage_type = "KINETIC"
	targets[1].last_hit_damage_type = "ENERGY"
	targets[2].last_hit_damage_type = "DIGITAL"
	targets[2].statuses["VIRUS"] = [
		{"sourceId": "test:VIRUS", "sourceActorId": state.operator.id, "expiresAt": 6000.0, "nextTickAt": 1000.0, "snapshot": 0.0, "stacks": 1},
		{"sourceId": "test:VIRUS", "sourceActorId": state.operator.id, "expiresAt": 6000.0, "nextTickAt": 1000.0, "snapshot": 0.0, "stacks": 1},
	]
	var living_target: CombatActorState = targets[3]
	living_target.base_sheet["evasion"] = 0.0
	var hp_before: float = living_target.hp
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("on-kill-trigger-fixture", "kills")
	simulator._resolve_basic_deaths(state, rng)
	check(is_equal_approx(state.operator.energy, energy_before + 4.0), "combat_step: K3D kinetic kill did not restore energy")
	check(is_equal_approx(state.operator.heat, 35.0), "combat_step: H3C energy kill did not reduce heat")
	check(living_target.statuses.get("VIRUS", []).size() == 2, "combat_step: N4C did not transfer two VIRUS stacks from a killed target")
	check(living_target.hp < hp_before, "combat_step: U02 did not echo digital kill damage onto another enemy")
	check(int(state.metrics.get("procsTriggered", 0)) == 4, "combat_step: ON_KILL actions were not each counted once")

func _test_before_hit_and_shield_absorb(config: Dictionary, build: Dictionary) -> void:
	var trigger_build: Dictionary = build.duplicate(true)
	trigger_build["triggerEffects"] = [
		{"sourceId": "U04", "sourceKind": "item", "effect": {"type": "trigger", "id": "U04_charge", "event": "ON_SHIELD_ABSORB", "action": {"kind": "charge", "amountFromAbsorbed": 0.2, "capFormula": "H(T)", "capFlat": 100}}},
		{"sourceId": "U04", "sourceKind": "item", "effect": {"type": "trigger", "id": "U04_release", "event": "ON_BEFORE_HIT", "icdMs": 4000, "action": {"kind": "spendFlagForDamage", "flag": "charge", "perStack": 1, "maxStacks": 1, "intervalMs": 4000}}},
		{"sourceId": "K4C", "sourceKind": "tree", "effect": {"type": "trigger", "id": "K4C", "event": "ON_BEFORE_HIT", "action": {"kind": "packetMod", "penMultiplier": 2}}},
		{"sourceId": "H4D", "sourceKind": "tree", "effect": {"type": "trigger", "id": "H4D", "event": "ON_BEFORE_HIT", "action": {"kind": "packetMod", "damageMultiplier": 1.25, "consumeShield": 10, "requireShield": 10}}},
		{"sourceId": "X1", "sourceKind": "tree", "effect": {"type": "trigger", "id": "X1", "event": "ON_EFFECT_SHIELD_SPENT", "action": {"kind": "tempShield", "amount": 0, "cap": 25, "durationMs": 5000, "fromFlag": "effectShieldSpent", "ratio": 0.5}}},
		{"sourceId": "S3A", "sourceKind": "tree", "effect": {"type": "trigger", "id": "S3A", "event": "ON_SHIELD_ABSORB", "action": {"kind": "restoreEnergy", "amount": 8}}},
		{"sourceId": "S4D", "sourceKind": "tree", "effect": {"type": "trigger", "id": "S4D", "event": "ON_SHIELD_ABSORB", "action": {"kind": "secondaryDamage", "basis": "consumedShield", "coefficient": 0.15, "damageType": "DIGITAL", "targeting": "attacker", "canProc": false}}},
	]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "before-hit-shield-absorb-fixture", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": "COMBAT", "build": trigger_build, "enemies": [config.get("enemy", {})], "tactics": config.get("tactics", {}),
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: before-hit fixture failed to initialize"):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	var attacker: CombatActorState = state.enemies[0]
	attacker.base_sheet["evasion"] = 0.0
	state.operator.shield = 100.0
	state.operator.energy = maxf(0.0, float(state.operator.base_sheet.get("maxEnergy", 0.0)) - 20.0)
	var energy_before: float = state.operator.energy
	var incoming_rng: DeterministicRng = DeterministicRng.new()
	incoming_rng.seed("before-hit-shield-absorb-fixture", "incoming")
	var incoming: Dictionary = simulator._resolve_basic_hit(state, incoming_rng, attacker, state.operator, 20.0, "ENERGY", "enemy-hit", false)
	if not check(bool(incoming.get("ok", false)), "combat_step: shield-absorb hit did not resolve"):
		return
	check(float(state.operator.flags.get("charge", 0.0)) > 0.0, "combat_step: U04 did not charge from absorbed shield")
	check(is_equal_approx(state.operator.energy, energy_before + 8.0), "combat_step: S3A did not restore energy on shield absorb")
	var shield_before: float = state.operator.shield
	var player_rng: DeterministicRng = DeterministicRng.new()
	player_rng.seed("before-hit-shield-absorb-fixture", "player")
	var outgoing: Dictionary = simulator._resolve_basic_hit(state, player_rng, state.operator, attacker, 20.0, "KINETIC", "operator-hit", true, "", 0.0, true, 1.0)
	if not check(bool(outgoing.get("ok", false)), "combat_step: modified direct hit did not resolve"):
		return
	check(is_zero_approx(float(state.operator.flags.get("charge", 0.0))), "combat_step: U04 release did not consume stored charge")
	check(is_equal_approx(shield_before - state.operator.shield, 10.0), "combat_step: H4D did not consume its authored 10 shield")
	var temporary_shield: float = 0.0
	for pool: Dictionary in state.operator.temp_shields:
		temporary_shield += float(pool.get("amount", 0.0))
	check(is_equal_approx(temporary_shield, 5.0), "combat_step: X1 did not convert spent effect shield into temporary shield")

func _test_event_turret_ally(config: Dictionary, build: Dictionary) -> void:
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "event-ev18-turret", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": "COMBAT", "build": build, "enemies": [config.get("enemy", {})],
		"tactics": config.get("tactics", {}), "alliedEnemies": [{"templateId": "E08", "strength": 0.5}],
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: EV18 allied turret combat did not initialize: %s" % str(initialized.get("error", ""))):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	if not check(state.allies.size() == 1, "combat_step: EV18 did not create exactly one allied turret"):
		return
	var turret: CombatActorState = state.allies[0]
	check(turret.template_id == "E08" and turret.kind == "ally" and turret.side == "player", "combat_step: EV18 turret did not use E08 ally combat identity")
	var expected_hp: float = 0.0
	var expected_damage: float = 0.0
	var catalog: EnemyCatalog = EnemyCatalog.new()
	if bool(catalog.load_catalog().get("ok", false)):
		var template: Dictionary = catalog.get_template("E08")
		var formula: CydleFormula = CydleFormula.new()
		expected_hp = float(template.get("hp", 0.0)) * formula.h_depth(float(config.get("depth", 1))) * 0.5
		expected_damage = float(template.get("damage", 0.0)) * formula.d_depth(float(config.get("depth", 1))) * 0.5
	check(is_equal_approx(turret.hp, expected_hp) and is_equal_approx(turret.attack_damage, expected_damage), "combat_step: EV18 turret did not enter at 50% HP and attack strength")
	var started: Dictionary = state.log[0] if not state.log.is_empty() else {}
	check(int(started.get("data", {}).get("alliedCount", 0)) == 1, "combat_step: combat-start event did not report the allied turret")
	state.operator.next_attack_at = 100000.0
	for actor: CombatActorState in state.enemies:
		actor.next_attack_at = 100000.0
	turret.next_attack_at = 100.0
	var stepped: Dictionary = simulator.step_combat(state)
	if not check(bool(stepped.get("ok", false)), "combat_step: EV18 turret could not attack: %s" % str(stepped.get("error", ""))):
		return
	state = stepped["state"] as CombatState
	check(state.log.any(func(event: Dictionary) -> bool: return str(event.get("kind", "")) == "ATTACK" and str(event.get("actorId", "")) == turret.id), "combat_step: EV18 turret did not make a real combat attack")

func _test_direct_status_tree_trigger(config: Dictionary, build: Dictionary) -> void:
	var trigger_build: Dictionary = build.duplicate(true)
	trigger_build["triggerEffects"] = [{
		"sourceId": "K3A", "sourceName": "Раскол брони", "sourceKind": "tree",
		"effect": {"type": "trigger", "id": "K3A", "event": "ON_HIT", "chance": 1.0, "icdMs": 4000, "requireDirect": true, "damageTypeFilter": ["KINETIC"], "action": {"kind": "applyStatus", "status": "ARMOR_BREAK", "stacks": 1, "target": "target"}},
	}]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": "campaign-k3a-trigger", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
		"nodeType": str(config.get("nodeType", "COMBAT")), "build": trigger_build,
		"enemies": [config.get("enemy", {})], "tactics": config.get("tactics", {}), "maxDurationMs": 180000,
	})
	if not check(bool(initialized.get("ok", false)), "combat_step: K3A trigger combat did not initialize: %s" % str(initialized.get("error", ""))):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	var ticks: int = 0
	while not state.enemies.is_empty() and not state.enemies[0].statuses.has("ARMOR_BREAK") and ticks < 100:
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "combat_step: K3A trigger tick failed: %s" % str(stepped.get("error", ""))):
			return
		state = stepped["state"] as CombatState
		ticks += 1
	check(not state.enemies.is_empty() and state.enemies[0].statuses.has("ARMOR_BREAK"), "combat_step: K3A did not apply ARMOR_BREAK on a direct kinetic hit")
	check(int(state.metrics.get("procsTriggered", 0)) == 1, "combat_step: K3A trigger was not recorded exactly once")

func _test_support_relay(config: Dictionary, operator: Dictionary) -> void:
	var catalog: ItemCatalog = ItemCatalog.new()
	if not check(bool(catalog.load_catalog().get("ok", false)), "combat_step: item catalog failed to load for support relay"):
		return
	var raw_by_tech: Dictionary = {}
	for tech_level: int in [1, 3]:
		var item_rng: DeterministicRng = DeterministicRng.new()
		item_rng.seed("support-test", "tech-%d" % tech_level)
		var created: Dictionary = ItemFactory.new().create_item(item_rng, catalog, {
			"templateId": "TR_SUPPORT_2", "techLevel": tech_level, "rarity": "COMMON",
			"secured": false, "originGrantId": "support-test-%d" % tech_level,
			"origin": "test", "acquiredAt": 0,
		})
		if not check(bool(created.get("ok", false)), "combat_step: relay item could not be created"):
			return
		var relay: ItemInstance = created["item"] as ItemInstance
		var main: ItemInstance = ItemInstance.new()
		var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
		var main_raw: Dictionary = {}
		for item_value: Dictionary in meta.get("inventory", []):
			if str(item_value.get("itemId", "")) == str(meta.get("equipment", {}).get("MAIN", "")):
				main_raw = item_value
				break
		if not check(main.instantiate_from_dictionary(main_raw), "combat_step: main weapon failed to parse for support relay"):
			return
		var build: Dictionary = BuildResolver.new().resolve_build({
			"equipment": {"MAIN": main, "SUPPORT": relay}, "attributes": operator.get("attributes", {}),
			"skillIds": [], "passiveIds": [], "treeNodeIds": [],
			"attributePointsEarned": 0, "treePointsEarned": 0,
		})
		if not check(bool(build.get("valid", false)), "combat_step: relay build was rejected: %s" % str(build.get("issues", []))):
			return
		var initialized: Dictionary = CombatSimulator.new().create_state({
			"seed": "support-relay-seed", "depth": int(config.get("depth", 1)), "biome": str(config.get("biome", "B01")),
			"nodeType": "COMBAT", "build": build, "enemies": [config.get("enemy", {})],
			"tactics": config.get("tactics", {}), "maxDurationMs": 30000,
		})
		if not check(bool(initialized.get("ok", false)), "combat_step: relay combat could not initialize"):
			return
		var state: CombatState = initialized["state"] as CombatState
		state.operator.next_attack_at = 100000.0
		for enemy: CombatActorState in state.enemies:
			enemy.next_attack_at = 100000.0
		state.operator.ability_next["periodic:TR_SUPPORT_blast"] = 100.0
		var stepped: Dictionary = CombatSimulator.new().step_combat(state)
		if not check(bool(stepped.get("ok", false)), "combat_step: relay pulse was rejected: %s" % str(stepped.get("error", ""))):
			return
		var next: CombatState = stepped["state"] as CombatState
		for event: Dictionary in next.log:
			if str(event.get("kind", "")) == "DAMAGE" and str(event.get("actionId", "")).begins_with("operator:periodic:TR_SUPPORT_blast:"):
				raw_by_tech[tech_level] = float(event.get("amountBeforeDefense", 0.0))
				break
		check(raw_by_tech.has(tech_level), "combat_step: support relay did not produce its periodic ENERGY hit")
	if raw_by_tech.has(1) and raw_by_tech.has(3):
		var expected_ratio: float = CydleFormula.new().h_depth(3.0) / CydleFormula.new().h_depth(1.0)
		check(absf(float(raw_by_tech[3]) / maxf(0.000001, float(raw_by_tech[1])) - expected_ratio) < 0.000001, "combat_step: support relay damage ignored support-item TechLevel")

func _test_attack_counter_items(config: Dictionary, operator: Dictionary) -> void:
	var catalog: ItemCatalog = ItemCatalog.new()
	if not check(bool(catalog.load_catalog().get("ok", false)), "combat_step: catalog failed to load for attack counters"):
		return
	for weapon_id: String in ["ARC_E2", "FOCUS_D1", "DR_ARC"]:
		var item_rng: DeterministicRng = DeterministicRng.new()
		item_rng.seed("counter-test", weapon_id)
		var created: Dictionary = ItemFactory.new().create_item(item_rng, catalog, {
			"templateId": weapon_id, "techLevel": 1, "rarity": "COMMON", "secured": false,
			"originGrantId": "counter-%s" % weapon_id, "origin": "test", "acquiredAt": 0,
		})
		if not check(bool(created.get("ok", false)), "combat_step: counter weapon %s could not be created" % weapon_id):
			return
		var weapon: ItemInstance = created["item"] as ItemInstance
		var equipment: Dictionary = {}
		if weapon_id == "DR_ARC":
			var starter_meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
			var starter_main: ItemInstance = ItemInstance.new()
			var starter_main_data: Dictionary = {}
			for item_value: Dictionary in starter_meta.get("inventory", []):
				if str(item_value.get("itemId", "")) == str(starter_meta.get("equipment", {}).get("MAIN", "")):
					starter_main_data = item_value
					break
			if not check(starter_main.instantiate_from_dictionary(starter_main_data), "combat_step: starter weapon failed to parse for DR_ARC"):
				return
			equipment = {"MAIN": starter_main, "DRONE_1": weapon}
		else:
			equipment = {"MAIN": weapon}
		var build: Dictionary = BuildResolver.new().resolve_build({
			"equipment": equipment, "attributes": operator.get("attributes", {}),
			"skillIds": [], "passiveIds": [], "treeNodeIds": [],
			"attributePointsEarned": 0, "treePointsEarned": 0,
		})
		if not check(bool(build.get("valid", false)), "combat_step: counter weapon build %s was rejected" % weapon_id):
			return
		var enemies: Array[Dictionary] = [config.get("enemy", {})]
		if weapon_id == "ARC_E2": enemies.append(config.get("enemy", {}).duplicate(true))
		var initialized: Dictionary = CombatSimulator.new().create_state({
			"seed": "counter-%s" % weapon_id, "depth": int(config.get("depth", 1)),
			"biome": str(config.get("biome", "B01")), "nodeType": "COMBAT",
			"build": build, "enemies": enemies, "tactics": config.get("tactics", {}), "maxDurationMs": 30000,
		})
		if not check(bool(initialized.get("ok", false)), "combat_step: %s counter combat failed to initialize" % weapon_id):
			return
		var state: CombatState = initialized["state"] as CombatState
		var counter_actor: CombatActorState = state.drones[0] if weapon_id == "DR_ARC" and not state.drones.is_empty() else state.operator
		state.operator.next_attack_at = 100000.0 if weapon_id == "DR_ARC" else 100.0
		counter_actor.next_attack_at = 100.0
		for enemy: CombatActorState in state.enemies:
			enemy.hp = 100000.0
			enemy.next_attack_at = 100000.0
			for modifier: Dictionary in enemy.base_mods:
				if str(modifier.get("stat", "")) == "evasion": modifier["value"] = 0.0
		var ticks: int = 0
		var required_attacks: int = 20 if weapon_id == "DR_ARC" else 4
		while _attack_counter_count(state, weapon_id) < required_attacks and ticks < 1000:
			var stepped: Dictionary = CombatSimulator.new().step_combat(state)
			if not check(bool(stepped.get("ok", false)), "combat_step: %s counter tick failed: %s" % [weapon_id, str(stepped.get("error", ""))]):
				return
			state = stepped["state"] as CombatState
			ticks += 1
		check(_attack_counter_count(state, weapon_id) == required_attacks, "combat_step: %s did not reach attack %d" % [weapon_id, required_attacks])
		var trigger_found: bool = false
		var child_hit_found: bool = false
		var expected_trigger_id: String = "ARC_E2_splash" if weapon_id == "ARC_E2" else "FOCUS_D1_virus" if weapon_id == "FOCUS_D1" else "DR_ARC_shock"
		for event: Dictionary in state.log:
			if str(event.get("kind", "")) == "TRIGGER" and str(event.get("actionId", "")).contains(expected_trigger_id):
				trigger_found = true
			if weapon_id == "ARC_E2" and str(event.get("kind", "")) == "DAMAGE" and str(event.get("actionId", "")).contains("ARC_E2_splash") and str(event.get("targetId", "")) == "enemy:1":
				child_hit_found = true
		check(trigger_found, "combat_step: %s did not execute its fourth-attack trigger" % weapon_id)
		if weapon_id == "ARC_E2":
			check(child_hit_found, "combat_step: ARC_E2 did not damage the secondary enemy")
		elif weapon_id == "FOCUS_D1":
			check(state.enemies[0].statuses.get("VIRUS", []).size() == 1, "combat_step: FOCUS_D1 did not apply its VIRUS stack")
		else:
			check(state.enemies[0].statuses.has("SHOCK"), "combat_step: DR_ARC did not apply SHOCK on its fifth attack")

func _attack_counter_count(state: CombatState, source_id: String) -> int:
	var actor: CombatActorState = state.drones[0] if source_id == "DR_ARC" and not state.drones.is_empty() else state.operator
	return int(actor.counters.get("attacks", 0))

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
