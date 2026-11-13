extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/initial_save.json"))
	var meta: Dictionary = payload.get("meta", {})
	var main: ItemInstance = _item_for_slot(meta, "MAIN")
	var catalog: ItemCatalog = ItemCatalog.new()
	check(bool(catalog.load_catalog().get("ok", false)), "v2_skill_catalog: item catalog unavailable")
	var sidearm_rng: DeterministicRng = DeterministicRng.new()
	sidearm_rng.seed("item", "v2-skill-sidearm")
	var sidearm_result: Dictionary = ItemFactory.new().create_item(sidearm_rng, catalog, {
		"templateId": "SIDEARM_1", "techLevel": 1, "rarity": "COMMON", "originGrantId": "v2-skill-fixture",
		"origin": "test", "secured": true, "acquiredAt": 1,
	})
	if not check(bool(sidearm_result.get("ok", false)), "v2_skill_catalog: could not create authored sidearm fixture"):
		return false
	var equipment: Dictionary = {"MAIN": main, "OFFHAND": sidearm_result["item"]}
	var build_catalog: BuildCatalog = BuildCatalog.new()
	if not check(bool(build_catalog.load_catalog().get("ok", false)), "v2_skill_catalog: skill catalog unavailable"):
		return false
	var main_skill_ids: Array[String] = []
	for skill: Dictionary in build_catalog.skills.values():
		if str(skill.get("channel", "main")) == "main": main_skill_ids.append(str(skill.get("id", "")))
	main_skill_ids.sort()
	var supported_skill_ids: Array[String] = AutobattleV2Contract.SUPPORTED_MAIN_SKILLS.duplicate()
	supported_skill_ids.sort()
	check(main_skill_ids == supported_skill_ids, "v2_skill_catalog: supported main skill IDs drifted from the authored catalog (%s vs %s)" % [str(main_skill_ids), str(supported_skill_ids)])
	var resolver: BuildResolver = BuildResolver.new()
	var simulator: CombatSimulator = CombatSimulator.new()
	for skill_id: String in main_skill_ids:
		if not AutobattleV2Contract.SUPPORTED_MAIN_SKILLS.has(skill_id):
			continue
		var build: Dictionary = resolver.resolve_build({
			"equipment": equipment.duplicate(true), "attributes": meta.get("operator", {}).get("attributes", {}),
			"skillIds": [skill_id], "passiveIds": [], "treeNodeIds": [],
			"attributePointsEarned": 0, "treePointsEarned": 0,
		})
		if not check(bool(build.get("valid", false)), "v2_skill_catalog: BuildResolver rejected %s: %s" % [skill_id, str(build.get("issues", []))]):
			continue
		var created: Dictionary = simulator.create_state({
			"combatRulesVersion": CombatState.V2_RULES_VERSION, "seed": "v2-catalog:%s" % skill_id,
			"depth": 1, "nodeType": "BOSS", "build": build,
			"enemies": [{"templateId": "E01"}, {"templateId": "BOSS_A"}], "startEnergy": 100,
		})
		if not check(bool(created.get("ok", false)), "v2_skill_catalog: V2 rejected resolved %s: %s" % [skill_id, str(created.get("error", ""))]):
			continue
		var current: CombatState = created["state"]
		current.operator.accuracy_base = 1000.0
		for enemy: CombatActorState in current.enemies:
			enemy.base_sheet["evasion"] = 0.0
		if skill_id in ["SK_DETONATE", "SK_LEECH"]:
			for enemy: CombatActorState in current.enemies:
				simulator._add_simple_status(current, current.operator, enemy, "VIRUS", 5000)
		var committed: bool = false
		for _tick: int in range(20):
			var stepped: Dictionary = simulator.step_combat(current)
			if not bool(stepped.get("ok", false)):
				check(false, "v2_skill_catalog: %s runtime step rejected: %s" % [skill_id, str(stepped.get("error", ""))])
				break
			current = stepped["state"]
			for event: Dictionary in current.log:
				if str(event.get("kind", "")) == "SKILL_USE" and str(event.get("skillId", "")) == skill_id:
					committed = true
					break
			if committed: break
		check(committed, "v2_skill_catalog: resolved skill %s never committed through the shared V2 channel" % skill_id)
		if committed:
			var skill_definition: Dictionary = build["skills"][0]
			var expected_cost: float = CombatFactory.new().main_skill_energy_cost(skill_definition, current.operator.base_sheet)
			check(is_equal_approx(float(current.metrics.get("energySpent", 0.0)), expected_cost), "v2_skill_catalog: %s did not pay exactly its BuildResolver cost" % skill_id)
			check(float(current.operator.cooldowns.get(skill_id, 0.0)) > float(current.time_ms), "v2_skill_catalog: %s did not set its authored cooldown" % skill_id)
			var active_targets: Array = []
			var skill_damage_logged: bool = false
			for event: Dictionary in current.log:
				if str(event.get("kind", "")) == "SKILL_USE" and str(event.get("skillId", "")) == skill_id:
					active_targets = event.get("targetIds", [])
					if skill_id == "SK_OVR": check(str(event.get("targetId", "")) == "operator", "v2_skill_catalog: SELF doctrine did not select the operator")
					if skill_id == "SK_SCAN": check(str(event.get("targetId", "")) == "enemy:1", "v2_skill_catalog: BOSS doctrine did not select BOSS_A")
					if skill_id == "SK_KINETIC": check(active_targets.size() == 2, "v2_skill_catalog: ALL_ENEMIES did not preserve both selected targets")
				if str(event.get("kind", "")) == "DAMAGE" and str(event.get("skillId", "")) == skill_id:
					skill_damage_logged = true
			var effect_status: String = ""
			match skill_id:
				"SK_OVR": effect_status = "OVERCLOCK"
				"SK_SCAN": effect_status = "SCAN_MARK"
				"SK_BLADE": effect_status = "BLEED"
				"SK_NEURO", "SK_SEED": effect_status = "VIRUS"
				"SK_BREAK": effect_status = "ARMOR_BREAK"
			if not effect_status.is_empty():
				var status_target: CombatActorState = current.operator if skill_id == "SK_OVR" else current.enemies[1] if skill_id == "SK_SCAN" else current.enemies[0]
				check(status_target.statuses.has(effect_status), "v2_skill_catalog: %s committed but its real %s status effect was missing" % [skill_id, effect_status])
			else:
				check(skill_damage_logged, "v2_skill_catalog: %s committed but produced no skill-sourced damage event" % skill_id)
			var resolved: CombatState = CombatState.from_dictionary(current.to_dictionary(), build)
			check(resolved != null, "v2_skill_catalog: committed %s state did not restore with its resolved build" % skill_id)
	return failure_count == 0

func _item_for_slot(meta: Dictionary, slot: String) -> ItemInstance:
	var item_id: String = str(meta.get("equipment", {}).get(slot, ""))
	for item_value: Dictionary in meta.get("inventory", []):
		if str(item_value.get("itemId", "")) == item_id:
			var item: ItemInstance = ItemInstance.new()
			if item.instantiate_from_dictionary(item_value): return item
	return null
