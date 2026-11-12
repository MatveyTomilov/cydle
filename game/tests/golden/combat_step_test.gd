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
	_test_support_relay(config, operator)
	_test_attack_counter_items(config, operator)
	return failure_count == 0

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
