extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
func run(_tree: SceneTree) -> bool:
	_run_replay("main_skill_replay", "SK_BURST")
	_run_replay("pierce_skill_replay", "SK_PIERCE")
	_run_replay("execute_skill_replay", "SK_EXEC")
	_run_replay("plasma_skill_replay", "SK_PLASMA")
	_run_reaction_shield()
	_run_reaction_emp_interrupt()
	_run_enemy_telegraphed_attack()
	_run_enemy_death_burst()
	_run_boss_threshold_phase()
	_run_elite_split()
	_run_main_skill_effects()
	_run_enemy_escape_wanted_protection()
	_run_drone_roles()
	return failure_count == 0

func _run_reaction_shield() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	if not check(not meta.is_empty() and not fixture.is_empty(), "reaction_shield: fixture or starter save is missing"):
		return
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "reaction_shield: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": ["SK_SHIELD"], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	if not check(bool(build.get("valid", false)), "reaction_shield: build was rejected"):
		return
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": config["seed"], "depth": config["depth"], "biome": config.get("biome", "B01"),
		"nodeType": config.get("nodeType", "COMBAT"), "build": build, "enemies": [config["enemy"]],
		"tactics": {"id": "test", "rules": [{"id": "shield", "priority": 1, "enabled": true, "skillId": "SK_SHIELD", "target": "self", "conditions": []}]},
		"startEnergy": 100,
	})
	if not check(bool(initialized.get("ok", false)), "reaction_shield: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	for _tick: int in range(2):
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "reaction_shield: step failed: %s" % stepped.get("error", "")):
			return
		state = stepped["state"] as CombatState
	check(int(state.metrics.get("skillUses", {}).get("SK_SHIELD", 0)) == 1, "reaction_shield: reaction did not resolve independently of the main channel")
	check(not state.operator.temp_shields.is_empty() and is_equal_approx(float(state.operator.temp_shields[0].get("amount", 0.0)), 60.0), "reaction_shield: temporary shield pool was not applied")

func _run_reaction_emp_interrupt() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "reaction_emp: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": ["SK_EMP"], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	if not check(bool(build.get("valid", false)), "reaction_emp: build was rejected"):
		return
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": config["seed"], "depth": config["depth"], "biome": config.get("biome", "B01"),
		"nodeType": config.get("nodeType", "COMBAT"), "build": build, "enemies": [config["enemy"]],
		"tactics": {"id": "test", "rules": [{"id": "emp", "priority": 1, "enabled": true, "skillId": "SK_EMP", "target": "imminentCast", "conditions": [{"kind": "enemyCasting", "interruptibleOnly": true}]}]},
		"startEnergy": 100,
	})
	if not check(bool(initialized.get("ok", false)), "reaction_emp: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	state.enemies[0].cast = {"actionId": "enemy:test-cast", "abilityId": "test", "skillId": "", "startedAt": 0.0, "resolveAt": 1000.0, "endAt": 1200.0, "targetId": "operator", "interruptible": true, "telegraph": true, "channel": "main"}
	for _tick: int in range(3):
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "reaction_emp: step failed: %s" % stepped.get("error", "")):
			return
		state = stepped["state"] as CombatState
	check(int(state.metrics.get("interrupts", 0)) == 1, "reaction_emp: reaction did not interrupt the imminent cast")
	check(state.enemies[0].cast == null, "reaction_emp: interrupted cast remained active")

func _run_enemy_telegraphed_attack() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "enemy_snipe: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"],
		"skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0,
	})
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({
		"seed": config["seed"], "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build,
		"enemies": [{"templateId": "E02"}], "tactics": {"id": "test", "rules": []},
		"startEnergy": 100,
	})
	if not check(bool(initialized.get("ok", false)), "enemy_snipe: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	state.operator.next_attack_at = 999999.0
	var initial_hp: float = state.operator.hp
	while state.time_ms < 7000 and state.outcome.is_empty():
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "enemy_snipe: step failed at %d: %s" % [state.time_ms + 100, stepped.get("error", "")]):
			return
		state = stepped["state"] as CombatState
	var telegraphed: bool = false
	var resolved: bool = false
	for event: Dictionary in state.log:
		if str(event.get("actionId", "")).contains("E02_snipe"):
			telegraphed = telegraphed or str(event.get("kind", "")) == "TELEGRAPH"
			resolved = resolved or str(event.get("kind", "")) in ["DAMAGE", "MISS"]
	check(telegraphed, "enemy_snipe: enemy ability did not show its telegraph")
	check(resolved, "enemy_snipe: telegraphed heavy attack did not resolve")
	check(state.operator.hp <= initial_hp, "enemy_snipe: enemy action unexpectedly healed its target")

func _run_enemy_death_burst() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "enemy_death: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"], "skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({"seed": config["seed"], "depth": 1, "nodeType": "COMBAT", "build": build, "enemies": [{"templateId": "E19"}], "tactics": {"rules": []}, "startEnergy": 100})
	if not check(bool(initialized.get("ok", false)), "enemy_death: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	state.enemies[0].hp = 0.0
	state.operator.next_attack_at = 999999.0
	var first: Dictionary = simulator.step_combat(state)
	if not check(bool(first.get("ok", false)), "enemy_death: death step failed: %s" % first.get("error", "")):
		return
	state = first["state"] as CombatState
	check(state.outcome.is_empty() and state.enemies[0].cast != null, "enemy_death: encounter ended before the death burst was scheduled")
	while state.time_ms < 1400 and state.outcome.is_empty():
		var stepped: Dictionary = simulator.step_combat(state)
		if not check(bool(stepped.get("ok", false)), "enemy_death: burst step failed: %s" % stepped.get("error", "")):
			return
		state = stepped["state"] as CombatState
	var burst_resolved: bool = false
	for event: Dictionary in state.log:
		if str(event.get("actionId", "")).contains("E19_death") and str(event.get("kind", "")) in ["DAMAGE", "MISS"]:
			burst_resolved = true
	check(burst_resolved and state.outcome == "VICTORY", "enemy_death: delayed death burst failed to resolve before victory")

func _run_boss_threshold_phase() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "boss_phase: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"], "skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({"seed": config["seed"], "depth": 12, "nodeType": "BOSS", "build": build, "enemies": [{"templateId": "BOSS_A"}], "tactics": {"rules": []}, "startEnergy": 100})
	if not check(bool(initialized.get("ok", false)), "boss_phase: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	var boss: CombatActorState = state.enemies[0]
	boss.hp = float(boss.base_sheet.get("maxHP", 1.0)) * 0.69
	state.operator.next_attack_at = 999999.0
	var stepped: Dictionary = simulator.step_combat(state)
	if not check(bool(stepped.get("ok", false)), "boss_phase: phase transition failed: %s" % stepped.get("error", "")):
		return
	state = stepped["state"] as CombatState
	var phase_seen: bool = false
	for event: Dictionary in state.log:
		phase_seen = phase_seen or str(event.get("kind", "")) == "PHASE"
	check(phase_seen and state.enemies.size() == 2 and state.enemies[1].template_id == "E09", "boss_phase: threshold summon was not executed")

func _run_elite_split() -> void:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var fixture: Dictionary = _read_dictionary("res://tests/fixtures/combat/basic_auto_replay.json")
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not check(main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]), "elite_split: starter weapon did not parse"):
		return
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"], "skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	var config: Dictionary = fixture["config"]
	var initialized: Dictionary = CombatSimulator.new().create_state({"seed": config["seed"], "depth": 1, "nodeType": "ELITE", "build": build, "enemies": [{"templateId": "E01", "elite": "EL_SPLIT"}], "tactics": {"rules": []}, "startEnergy": 100})
	if not check(bool(initialized.get("ok", false)), "elite_split: state initialization failed: %s" % initialized.get("error", "")):
		return
	var simulator: CombatSimulator = CombatSimulator.new()
	var state: CombatState = initialized["state"] as CombatState
	state.enemies[0].hp = 0.0
	state.operator.next_attack_at = 999999.0
	var stepped: Dictionary = simulator.step_combat(state)
	if not check(bool(stepped.get("ok", false)), "elite_split: death step failed: %s" % stepped.get("error", "")):
		return
	state = stepped["state"] as CombatState
	var spawned: int = 0
	for enemy: CombatActorState in state.enemies:
		if enemy.template_id == "E20" and enemy.summoned and enemy.no_loot:
			spawned += 1
	check(spawned == 2 and state.outcome.is_empty(), "elite_split: death did not produce two no-loot swarm enemies")

func _run_enemy_escape_wanted_protection() -> void:
	var escape_data: Dictionary = _make_enemy_state([{"templateId": "E06"}], "escape-test")
	var escape_state: CombatState = escape_data.get("state") as CombatState
	var escape_simulator: CombatSimulator = escape_data.get("simulator") as CombatSimulator
	if escape_state != null and escape_simulator != null:
		escape_state.operator.hp = 100000.0
		escape_state.operator.next_attack_at = 999999.0
		while escape_state.time_ms < 16000 and escape_state.outcome.is_empty():
			var step: Dictionary = escape_simulator.step_combat(escape_state)
			if not bool(step.get("ok", false)):
				check(false, "enemy_escape: step failed: %s" % step.get("error", ""))
				break
			escape_state = step["state"] as CombatState
		check(escape_state.outcome == "VICTORY" and escape_state.metrics.get("escaped", []).size() == 1, "enemy_escape: E06 did not escape with one cargo item")
	var wanted_data: Dictionary = _make_enemy_state([{"templateId": "E11"}], "wanted-test")
	var wanted_state: CombatState = wanted_data.get("state") as CombatState
	var wanted_simulator: CombatSimulator = wanted_data.get("simulator") as CombatSimulator
	if wanted_state != null and wanted_simulator != null:
		wanted_state.operator.hp = 100000.0
		wanted_state.operator.next_attack_at = 999999.0
		while wanted_state.time_ms < 5400:
			var step: Dictionary = wanted_simulator.step_combat(wanted_state)
			if not bool(step.get("ok", false)):
				check(false, "enemy_wanted: step failed: %s" % step.get("error", ""))
				break
			wanted_state = step["state"] as CombatState
		check(wanted_state.wanted_delta == 3, "enemy_wanted: E11 did not add its post-combat wanted")
	var protect_data: Dictionary = _make_enemy_state([{"templateId": "E12"}, {"templateId": "E01"}], "protect-test")
	var protect_state: CombatState = protect_data.get("state") as CombatState
	var protect_simulator: CombatSimulator = protect_data.get("simulator") as CombatSimulator
	if protect_state != null and protect_simulator != null:
		protect_state.operator.hp = 100000.0
		protect_state.operator.next_attack_at = 999999.0
		protect_state.enemies[1].hp = 1.0
		while protect_state.time_ms < 5200:
			var step: Dictionary = protect_simulator.step_combat(protect_state)
			if not bool(step.get("ok", false)):
				check(false, "enemy_protect: step failed: %s" % step.get("error", ""))
				break
			protect_state = step["state"] as CombatState
		check(str(protect_state.enemies[1].flags.get("protectedBy", "")) == protect_state.enemies[0].id, "enemy_protect: E12 did not guard the weakest ally")
		var guarded: CombatState = protect_state.clone()
		var unguarded: CombatState = protect_state.clone()
		unguarded.enemies[1].flags.erase("protectedBy")
		var guarded_rng: DeterministicRng = DeterministicRng.new()
		var unguarded_rng: DeterministicRng = DeterministicRng.new()
		guarded_rng.seed("combat", "protect-hit")
		unguarded_rng.seed("combat", "protect-hit")
		protect_simulator._resolve_basic_hit(guarded, guarded_rng, guarded.operator, guarded.enemies[1], 100.0, "KINETIC", "protect-check", false)
		protect_simulator._resolve_basic_hit(unguarded, unguarded_rng, unguarded.operator, unguarded.enemies[1], 100.0, "KINETIC", "protect-check", false)
		var guarded_hit: Dictionary = guarded.log.back()
		var unguarded_hit: Dictionary = unguarded.log.back()
		check(guarded_hit.get("kind", "") == "DAMAGE" and unguarded_hit.get("kind", "") == "DAMAGE", "enemy_protect: comparison hit did not land")
		if guarded_hit.get("kind", "") == "DAMAGE" and unguarded_hit.get("kind", "") == "DAMAGE":
			check(is_equal_approx(float(guarded_hit.get("amountAfterDefense", 0.0)), float(unguarded_hit.get("amountAfterDefense", 0.0)) * 0.85), "enemy_protect: guard did not reduce ally damage by 15 percent (%s vs %s; %s)" % [guarded_hit.get("amountAfterDefense", -1), unguarded_hit.get("amountAfterDefense", -1), guarded.enemies[1].flags.get("protectedBy", "")])

func _make_enemy_state(enemy_specs: Array[Dictionary], seed_value: String) -> Dictionary:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]):
		return {}
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"], "skillIds": [], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	if not bool(build.get("valid", false)):
		return {}
	var simulator: CombatSimulator = CombatSimulator.new()
	var initialized: Dictionary = simulator.create_state({"seed": seed_value, "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build, "enemies": enemy_specs, "tactics": {"rules": []}, "startEnergy": 100})
	return {"simulator": simulator, "state": initialized.get("state")} if bool(initialized.get("ok", false)) else {}

func _run_drone_roles() -> void:
	var mark_data: Dictionary = _make_drone_state("DR_GUN", [], "drone-mark-test", [{"templateId": "E01"}, {"templateId": "E02"}])
	var mark_state: CombatState = mark_data.get("state") as CombatState
	if mark_state != null:
		var marked: Dictionary = CombatSimulator.new().apply_status(mark_state, "operator", mark_state.enemies[1].id, "DRONE_MARK", {"durationMs": 5000})
		if bool(marked.get("ok", false)):
			mark_state = marked["state"] as CombatState
			var selected: CombatActorState = CombatSimulator.new()._pick_auto_target(mark_state, mark_state.drones[0])
			check(selected != null and selected.id == mark_state.enemies[1].id, "drone_mark: marker drone did not prioritize marked enemy")
	var swarm_data: Dictionary = _make_drone_state("DR_SWARM", [], "drone-swarm-test", [{"templateId": "E01"}])
	var swarm_state: CombatState = swarm_data.get("state") as CombatState
	if swarm_state != null:
		check(CombatSimulator.new()._attack_packets(swarm_state.drones[0], {}).size() == 3, "drone_swarm: swarm did not create three attack packets")
	var bulwark_data: Dictionary = _make_drone_state("DR_BULWARK", [], "drone-bulwark-test", [{"templateId": "E01"}])
	var bulwark_state: CombatState = bulwark_data.get("state") as CombatState
	if bulwark_state != null:
		var bulwark_rng: DeterministicRng = DeterministicRng.new()
		bulwark_rng.seed("combat", "drone-bulwark-hit")
		CombatSimulator.new()._resolve_basic_hit(bulwark_state, bulwark_rng, bulwark_state.enemies[0], bulwark_state.operator, 100.0, "KINETIC", "bulwark-check", false)
		var redirected: bool = false
		for event: Dictionary in bulwark_state.log:
			redirected = redirected or bool(event.get("data", {}).get("redirected", false)) and str(event.get("targetId", "")) == bulwark_state.drones[0].id
		check(redirected, "drone_bulwark: part of enemy damage was not redirected to the bulwark drone")
	var medic_data: Dictionary = _make_drone_state("DR_MED", ["SK_DRONE_REPAIR"], "drone-medic-test", [{"templateId": "E01"}])
	var medic_state: CombatState = medic_data.get("state") as CombatState
	var medic_simulator: CombatSimulator = medic_data.get("simulator") as CombatSimulator
	if medic_state != null and medic_simulator != null:
		medic_state.operator.next_attack_at = 999999.0
		medic_state.drones[0].next_attack_at = 999999.0
		medic_state.drones[0].hp -= 30.0
		medic_state.operator.shield -= 30.0
		var drone_hp_before: float = medic_state.drones[0].hp
		var shield_before: float = medic_state.operator.shield
		for _tick: int in range(3):
			var step: Dictionary = medic_simulator.step_combat(medic_state)
			if not bool(step.get("ok", false)):
				check(false, "drone_medic: step failed: %s" % step.get("error", ""))
				break
			medic_state = step["state"] as CombatState
		check(medic_state.drones[0].hp == drone_hp_before + 25.0 and medic_state.operator.shield == shield_before + 20.0, "drone_medic: repair did not heal the drone and restore operator shields")
	var medic_periodic_data: Dictionary = _make_drone_state("DR_MED", [], "drone-medic-periodic-test", [{"templateId": "E01"}])
	var medic_periodic_state: CombatState = medic_periodic_data.get("state") as CombatState
	var medic_periodic_simulator: CombatSimulator = medic_periodic_data.get("simulator") as CombatSimulator
	if medic_periodic_state != null and medic_periodic_simulator != null:
		medic_periodic_state.operator.next_attack_at = 999999.0
		medic_periodic_state.drones[0].next_attack_at = 999999.0
		medic_periodic_state.enemies[0].next_attack_at = 999999.0
		medic_periodic_state.operator.shield -= 30.0
		var shield_before: float = medic_periodic_state.operator.shield
		while medic_periodic_state.time_ms < 10100:
			var step: Dictionary = medic_periodic_simulator.step_combat(medic_periodic_state)
			if not bool(step.get("ok", false)):
				check(false, "drone_medic: periodic step failed: %s" % step.get("error", ""))
				break
			medic_periodic_state = step["state"] as CombatState
		check(medic_periodic_state.operator.shield == shield_before + 18.0, "drone_medic: periodic support did not restore 18 operator shields after 10 seconds")
	var emp_data: Dictionary = _make_drone_state("DR_EMP", ["SK_DRONE_EMP"], "drone-emp-test", [{"templateId": "E02"}])
	var emp_state: CombatState = emp_data.get("state") as CombatState
	var emp_simulator: CombatSimulator = emp_data.get("simulator") as CombatSimulator
	if emp_state != null and emp_simulator != null:
		emp_state.operator.next_attack_at = 999999.0
		emp_state.drones[0].next_attack_at = 999999.0
		emp_state.enemies[0].cast = {"actionId": "enemy:drone-emp-test", "abilityId": "E02_snipe", "startedAt": 0.0, "resolveAt": 1000.0, "endAt": 1000.0, "targetId": "operator", "interruptible": true, "telegraph": true, "channel": "main"}
		for _tick: int in range(3):
			var step: Dictionary = emp_simulator.step_combat(emp_state)
			if not bool(step.get("ok", false)):
				check(false, "drone_emp: step failed: %s" % step.get("error", ""))
				break
			emp_state = step["state"] as CombatState
		check(int(emp_state.metrics.get("interrupts", 0)) == 1 and emp_state.enemies[0].cast == null and emp_state.enemies[0].statuses.has("JAM"), "drone_emp: drone failed to interrupt, damage, and jam the caster")

func _make_drone_state(drone_template_id: String, skill_ids: Array[String], seed_value: String, enemy_specs: Array[Dictionary]) -> Dictionary:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var equipment: Dictionary = {}
	for slot: String in ["MAIN", "DRONE_1"]:
		var raw_item: Dictionary = items_by_id[str(meta["equipment"][slot])].duplicate(true)
		if slot == "DRONE_1":
			var item_catalog: ItemCatalog = ItemCatalog.new()
			if not bool(item_catalog.load_catalog().get("ok", false)):
				return {}
			raw_item["templateId"] = drone_template_id
			raw_item["itemId"] = "test:%s" % drone_template_id
			raw_item["neuralCost"] = float(item_catalog.get_template(drone_template_id).get("neuralCost", 0.0))
			raw_item["affixes"] = []
		var item: ItemInstance = ItemInstance.new()
		if not item.instantiate_from_dictionary(raw_item):
			return {}
		equipment[slot] = item
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": equipment, "attributes": meta["operator"]["attributes"], "skillIds": skill_ids, "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	if not bool(build.get("valid", false)):
		return {}
	var simulator: CombatSimulator = CombatSimulator.new()
	var initialized: Dictionary = simulator.create_state({"seed": seed_value, "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build, "enemies": enemy_specs, "tactics": {"rules": []}, "startEnergy": 100})
	return {"simulator": simulator, "state": initialized.get("state")} if bool(initialized.get("ok", false)) else {}

func _run_main_skill_effects() -> void:
	var blade_data: Dictionary = _make_skill_state("SK_BLADE", "nearest", [{"templateId": "E01"}], "blade-test")
	check(_cast_until_used(blade_data), "skill_blade: skill did not cast")
	var blade_state: CombatState = blade_data.get("state") as CombatState
	check(blade_state != null and blade_state.enemies[0].statuses.has("BLEED"), "skill_blade: three-hit skill did not apply its final-hit bleed")
	var overclock_data: Dictionary = _make_skill_state("SK_OVR", "self", [{"templateId": "E01"}], "overclock-test")
	check(_cast_until_used(overclock_data), "skill_overclock: skill did not cast")
	var overclock_state: CombatState = overclock_data.get("state") as CombatState
	check(overclock_state != null and overclock_state.operator.statuses.has("OVERCLOCK"), "skill_overclock: timed attack-speed status was not applied")
	var detonate_data: Dictionary = _make_skill_state("SK_DETONATE", "infected", [{"templateId": "E01"}], "detonate-test")
	var detonate_simulator: CombatSimulator = detonate_data.get("simulator") as CombatSimulator
	var detonate_state: CombatState = detonate_data.get("state") as CombatState
	if detonate_state != null and detonate_simulator != null:
		detonate_simulator._add_dot_status(detonate_state, detonate_state.operator, detonate_state.enemies[0], "VIRUS", 60.0, "test-virus", 3)
		check(_cast_until_used(detonate_data), "skill_detonate: skill did not cast")
		detonate_state = detonate_data.get("state") as CombatState
		check(detonate_state != null and not detonate_state.enemies[0].statuses.has("VIRUS") and int(detonate_state.metrics.get("hits", 0)) > 0, "skill_detonate: failed to consume virus stacks and resolve their remaining damage")

func _make_skill_state(skill_id: String, target_mode: String, enemy_specs: Array[Dictionary], seed_value: String) -> Dictionary:
	var meta: Dictionary = _read_dictionary(SAVE_FIXTURE).get("meta", {})
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var main_item: ItemInstance = ItemInstance.new()
	if not main_item.instantiate_from_dictionary(items_by_id[str(meta["equipment"]["MAIN"])]):
		return {}
	var build: Dictionary = BuildResolver.new().resolve_build({"equipment": {"MAIN": main_item}, "attributes": meta["operator"]["attributes"], "skillIds": [skill_id], "passiveIds": [], "treeNodeIds": [], "attributePointsEarned": 0, "treePointsEarned": 0})
	if not bool(build.get("valid", false)):
		return {}
	var simulator: CombatSimulator = CombatSimulator.new()
	var initialized: Dictionary = simulator.create_state({"seed": seed_value, "depth": 1, "biome": "B01", "nodeType": "COMBAT", "build": build, "enemies": enemy_specs, "tactics": {"id": "skill-test", "rules": [{"id": "skill-test", "priority": 1, "enabled": true, "skillId": skill_id, "target": target_mode, "conditions": []}]}, "startEnergy": 100})
	return {"simulator": simulator, "state": initialized.get("state")} if bool(initialized.get("ok", false)) else {}

func _cast_until_used(data: Dictionary) -> bool:
	var simulator: CombatSimulator = data.get("simulator") as CombatSimulator
	var state: CombatState = data.get("state") as CombatState
	if simulator == null or state == null:
		return false
	var skill_id: String = str(state.tactics.get("rules", [])[0].get("skillId", ""))
	for _tick: int in range(80):
		if int(state.metrics.get("skillUses", {}).get(skill_id, 0)) > 0:
			data["state"] = state
			return true
		var stepped: Dictionary = simulator.step_combat(state)
		if not bool(stepped.get("ok", false)):
			return false
		state = stepped["state"] as CombatState
	data["state"] = state
	return int(state.metrics.get("skillUses", {}).get(skill_id, 0)) > 0

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
		"maxDurationMs": config.get("maxDurationMs", 180000), "startEnergy": config.get("startEnergy", 0),
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
