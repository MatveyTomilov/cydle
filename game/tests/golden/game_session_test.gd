extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/game-session")
	if not check(session.start_new_game(1762900000000), "game_session: could not create a new game: %s" % session.last_error):
		return false
	check(session.state != null and session.state.meta.inventory.size() == 12, "game_session: new profile did not preserve the canonical starter inventory")
	if not check(session.start_expedition("fixed-session-seed"), "game_session: could not start expedition: %s" % session.last_error):
		return false
	check(session.state.run != null and session.state.run.depth == 1, "game_session: expedition did not initialize at depth one")
	check(session.state.run.graph.get("layers", []).size() == 6, "game_session: saved run has no six-layer route")
	var choices: Array[Dictionary] = session.reachable_nodes()
	check(choices.size() == 1, "game_session: starting route does not expose its connected node")
	var starter_intel: Dictionary = session.route_intel().get("nodes", {})
	if not choices.is_empty():
		var first_known: Dictionary = starter_intel.get(str(choices[0].get("id", "")), {})
		check(bool(first_known.get("revealed", false)) and first_known.has("type") and not first_known.has("lootHint"), "game_session: INTEL L1 did not reveal adjacent type while hiding reward bands")
	if choices.is_empty():
		return false
	var battle_payload: Dictionary = session.state.to_payload()
	battle_payload["run"]["graph"]["layers"][0][0]["enemies"] = [{"templateId": "E01"}, {"templateId": "E01"}]
	check(session._commit_payload(battle_payload), "game_session: could not install the tactical-rule test encounter")
	if not check(session.travel_to(str(choices[0]["id"])), "game_session: reachable node travel failed: %s" % session.last_error):
		return false
	check(session.state.run.phase == "NODE", "game_session: travel did not enter the node")
	if not check(session.begin_combat(), "game_session: first combat could not start: %s" % session.last_error):
		return false
	check(session.combat_notice.is_empty(), "game_session: supported starter reactions were incorrectly filtered")
	for _tick: int in range(3):
		if not check(session.advance_combat_step(), "game_session: active combat snapshot could not be saved: %s" % session.last_error):
			return false
	var before_resume: Dictionary = session.combat_state().to_dictionary()
	var combat_resumed: GameSession = GameSession.new()
	combat_resumed.configure_save_directory("user://test-saves/game-session")
	if not check(combat_resumed.load_saved_game(), "game_session: active combat could not be restored: %s" % combat_resumed.last_error):
		return false
	check(combat_resumed.has_active_combat(), "game_session: loaded profile lost its active combat")
	check(StateHash.new().state_hash(combat_resumed.combat_state().to_dictionary()) == StateHash.new().state_hash(before_resume), "game_session: restored combat state differs from the saved state")
	check(session.advance_combat_step(), "game_session: original combat could not advance after snapshot")
	check(combat_resumed.advance_combat_step(), "game_session: restored combat could not advance: %s" % combat_resumed.last_error)
	check(StateHash.new().state_hash(combat_resumed.combat_state().to_dictionary()) == StateHash.new().state_hash(session.combat_state().to_dictionary()), "game_session: restored combat diverged from uninterrupted deterministic simulation")
	var ticks: int = 0
	var used_burst: bool = false
	while session.combat_state() != null and session.combat_state().outcome.is_empty() and ticks < 1800:
		if not session.advance_combat_step():
			check(false, "game_session: combat step failed: %s" % session.last_error)
			return false
		used_burst = used_burst or int(session.combat_state().metrics.get("skillUses", {}).get("SK_BURST", 0)) > 0
		ticks += 1
	check(used_burst, "game_session: supported conditional SK_BURST rule never fired on the two-enemy encounter")
	check(session.combat_state() != null and not session.combat_state().outcome.is_empty(), "game_session: combat did not resolve within its simulation limit")
	if session.combat_state() != null and not session.combat_state().outcome.is_empty():
		check(session.resolve_active_combat(), "game_session: combat reward/defeat transaction failed: %s" % session.last_error)
	if session.state.run != null and session.state.run.phase == "ROUTE":
		var next_nodes: Array[Dictionary] = session.reachable_nodes()
		if not next_nodes.is_empty() and str(next_nodes[0].get("type", "")) == "CACHE":
			check(session.travel_to(str(next_nodes[0]["id"])), "game_session: tutorial cache travel failed: %s" % session.last_error)
			check(session.resolve_service_node("OPEN_CACHE", "IMP_HEAT"), "game_session: tutorial cache reward failed: %s" % session.last_error)
			var found_prototype: bool = false
			for item: Dictionary in session.state.run.unsecured_cargo:
				if str(item.get("templateId", "")) == "IMP_HEAT":
					found_prototype = true
			check(found_prototype, "game_session: chosen tutorial prototype was not added to run cargo")
	var attribute_session: GameSession = GameSession.new()
	attribute_session.configure_save_directory("user://test-saves/attribute-investment")
	if check(attribute_session.start_new_game(1762900000200), "game_session: could not create an attribute-investment profile"):
		var attribute_payload: Dictionary = attribute_session.state.to_payload()
		attribute_payload["meta"]["operator"]["attributePoints"] = 2
		attribute_payload["meta"]["operator"]["treePoints"] = 3
		attribute_payload["meta"]["protectedBank"]["CREDITS"] = 50.0
		check(attribute_session._commit_payload(attribute_payload), "game_session: attribute-investment fixture could not be saved")
		var base_kinetic: float = float(attribute_session.build_preview().get("stats", {}).get("kineticDamage", 0.0))
		check(attribute_session.attribute_points_available() == 2, "game_session: free attribute points were calculated incorrectly")
		check(attribute_session.allocate_attribute("POW"), "game_session: POW could not be allocated: %s" % attribute_session.last_error)
		check(int(attribute_session.state.meta.operator.attributes.get("POW", 0)) == 6 and attribute_session.attribute_points_available() == 1, "game_session: attribute allocation was not persisted")
		check(float(attribute_session.build_preview().get("stats", {}).get("kineticDamage", 0.0)) > base_kinetic, "game_session: allocated POW did not affect the resolved build")
		check(attribute_session.respec_attributes(), "game_session: attribute respec failed: %s" % attribute_session.last_error)
		check(int(attribute_session.state.meta.operator.attributes.get("POW", 0)) == 5 and attribute_session.attribute_points_available() == 2, "game_session: respec did not return its point")
		check(is_equal_approx(attribute_session.state.meta.protected_bank.credits, 40.0), "game_session: attribute respec did not charge 10 credits per allocated point")
		check(attribute_session.state.meta.skill_ids.size() == 3, "game_session: starter active-skill loadout did not fill its three slots")
		check(attribute_session.set_skill_equipped("SK_BURST", false), "game_session: starter skill could not be removed")
		check(attribute_session.set_skill_equipped("SK_PIERCE", true), "game_session: compatible active skill could not be installed: %s" % attribute_session.last_error)
		check(not attribute_session.set_skill_equipped("SK_BLADE", true) and attribute_session.state.meta.skill_ids.size() == 3, "game_session: active-skill loadout exceeded three slots")
		check(attribute_session.set_skill_equipped("SK_PIERCE", false) and not attribute_session.state.meta.skill_ids.has("SK_PIERCE"), "game_session: installed skill could not be removed")
		var main_damage_before_passive: float = float(attribute_session.build_preview().get("stats", {}).get("mainDamage", 0.0))
		check(attribute_session.set_passive_equipped("PP_AMMO", true), "game_session: passive protocol could not be installed: %s" % attribute_session.last_error)
		check(float(attribute_session.build_preview().get("stats", {}).get("mainDamage", 0.0)) > main_damage_before_passive, "game_session: PP_AMMO did not change BuildResolver output")
		check(not attribute_session.set_passive_equipped("PP_HEAT", true) and attribute_session.state.meta.passive_ids.size() == 3, "game_session: passive loadout exceeded three slots")
		check(attribute_session.set_passive_equipped("PP_AMMO", false) and not attribute_session.state.meta.passive_ids.has("PP_AMMO"), "game_session: installed passive protocol could not be removed")
		var base_tree_damage: float = float(attribute_session.build_preview().get("stats", {}).get("kineticDamage", 0.0))
		check(attribute_session.tree_points_available() == 3, "game_session: available tree points were calculated incorrectly")
		check(not attribute_session.set_tree_node_allocated("K2A", true), "game_session: tier 2 tree node was allocated before its branch requirements")
		check(attribute_session.set_tree_node_allocated("K1A", true), "game_session: first-tier tree node could not be allocated: %s" % attribute_session.last_error)
		check(float(attribute_session.build_preview().get("stats", {}).get("kineticDamage", 0.0)) > base_tree_damage, "game_session: allocated tree node did not affect BuildResolver output")
		check(attribute_session.set_tree_node_allocated("K1B", true) and attribute_session.set_tree_node_allocated("K2A", true), "game_session: valid tier 2 progression was rejected: %s" % attribute_session.last_error)
		check(attribute_session.tree_points_available() == 0 and not attribute_session.set_tree_node_allocated("K1C", true), "game_session: tree allocation exceeded earned points")
		check(attribute_session.set_tree_node_allocated("K1A", false), "game_session: tree respec did not remove invalid dependent nodes: %s" % attribute_session.last_error)
		check(attribute_session.state.meta.tree_node_ids == ["K1B"] and attribute_session.tree_points_available() == 2, "game_session: dependent tree nodes were not cascaded and refunded")
		check(is_equal_approx(attribute_session.state.meta.protected_bank.credits, 20.0), "game_session: tree respec did not charge 10 credits per removed node")
		check(attribute_session.start_expedition("attribute-lock-test"), "game_session: attribute test expedition failed to start")
		check(not attribute_session.allocate_attribute("REF") and int(attribute_session.state.meta.operator.attributes.get("REF", 0)) == 5, "game_session: attribute allocation was allowed during an active expedition")
		check(not attribute_session.set_tree_node_allocated("K1C", true), "game_session: tree allocation was allowed during an active expedition")
	var item_ops_session: GameSession = GameSession.new()
	item_ops_session.configure_save_directory("user://test-saves/item-operations")
	if check(item_ops_session.start_new_game(1762900000300), "game_session: could not create an item-operation profile"):
		var item_ops_payload: Dictionary = item_ops_session.state.to_payload()
		var starter_item: Dictionary = item_ops_payload["meta"]["inventory"][0]
		starter_item["durability"] = 50.0
		starter_item["rarity"] = "MODIFIED"
		starter_item["tr"] = 12.0
		starter_item["affixes"] = [{"affixId": "AF_KDM", "tier": 1, "value": 5.0, "rawRoll": 1.0, "tierBoosted": false, "center": 5.0, "min": 4.0, "max": 6.0}]
		item_ops_payload["meta"]["inventory"][0] = starter_item
		item_ops_payload["meta"]["protectedBank"]["SCRAP"] = 30.0
		item_ops_payload["meta"]["garage"]["WORKSHOP"] = 2
		check(item_ops_session._commit_payload(item_ops_payload), "game_session: item-operation fixture could not be saved: %s" % item_ops_session.last_error)
		var drone_id: String = str(item_ops_session.state.meta.inventory[5].get("itemId", ""))
		check(item_ops_session.valid_equipment_slots(drone_id) == ["DRONE_1"], "game_session: locked second drone slot was exposed")
		var unlock_payload: Dictionary = item_ops_session.state.to_payload()
		unlock_payload["meta"]["unlockedDroneSlots"] = 2
		check(item_ops_session._commit_payload(unlock_payload), "game_session: drone-slot fixture could not be saved")
		check(item_ops_session.valid_equipment_slots(drone_id) == ["DRONE_1", "DRONE_2"], "game_session: valid unlocked drone slots were not enumerated")
		check(item_ops_session.unequip_item("DRONE_1"), "game_session: equipped drone could not be removed: %s" % item_ops_session.last_error)
		check(item_ops_session.equip_item("DRONE_2", drone_id) and item_ops_session.equipped_slot(drone_id) == "DRONE_2", "game_session: item could not be moved to the unlocked drone socket")
		var item_id: String = str(starter_item.get("itemId", ""))
		check(item_ops_session.repair_item(item_id), "game_session: secured item repair failed: %s" % item_ops_session.last_error)
		check(is_equal_approx(float(item_ops_session.state.meta.inventory[0].get("durability", 0.0)), 100.0) and is_equal_approx(item_ops_session.state.meta.protected_bank.scrap, 19.0), "game_session: item repair did not restore durability and charge the formula cost")
		check(item_ops_session.calibrate_item_affix(item_id, 0), "game_session: TechResource calibration failed: %s" % item_ops_session.last_error)
		var calibrated_item: Dictionary = item_ops_session.state.meta.inventory[0]
		var calibrated_affix: Dictionary = calibrated_item["affixes"][0]
		check(float(calibrated_item.get("tr", 0.0)) == 9.0 and is_equal_approx(item_ops_session.state.meta.protected_bank.scrap, 9.0), "game_session: affix calibration did not charge TR and TechLevel-scaled scrap")
		check(float(calibrated_affix.get("value", 0.0)) >= 4.0 and float(calibrated_affix.get("value", 0.0)) <= 6.0 and float(calibrated_affix.get("rawRoll", 0.0)) >= 0.8 and float(calibrated_affix.get("rawRoll", 0.0)) <= 1.2, "game_session: calibrated roll escaped its same-tier range")
		check(item_ops_session.start_expedition("item-operations-lock"), "game_session: item-operation lock test run could not start")
		check(not item_ops_session.repair_item(item_id) and not item_ops_session.calibrate_item_affix(item_id, 0), "game_session: garage crafting was allowed during an active run")
	var tech_calibration_session: GameSession = GameSession.new()
	tech_calibration_session.configure_save_directory("user://test-saves/tech-calibration")
	if check(tech_calibration_session.start_new_game(1762900000400), "game_session: could not create a TechLevel-calibration profile"):
		var tech_payload: Dictionary = tech_calibration_session.state.to_payload()
		tech_payload["meta"]["protectedBank"]["SCRAP"] = 100.0
		tech_payload["meta"]["protectedBank"]["DATA"] = 50.0
		var core: ItemInstance = ItemInstance.new()
		core.item_id = "calibration-core-fixture"
		core.template_id = "MAT_CORE"
		core.secured = true
		core.origin_grant_id = "grant:calibration-core-fixture"
		core.origin = "boss"
		core.core_group = 1
		tech_payload["meta"]["inventory"].append(core.to_dictionary())
		check(tech_calibration_session._commit_payload(tech_payload), "game_session: TechLevel-calibration fixture could not be saved")
		var calibrate_id: String = str(tech_calibration_session.state.meta.inventory[0].get("itemId", ""))
		var calibration_quote: Dictionary = tech_calibration_session.tech_calibration_quote(calibrate_id, 4)
		check(bool(calibration_quote.get("affordable", false)) and int(calibration_quote.get("coreCount", 0)) == 1 and int(calibration_quote.get("coreGroup", 0)) == 1, "game_session: TechLevel calibration quote did not count the matching core")
		check(not tech_calibration_session.tech_calibration_quote(calibrate_id, 5).get("valid", false), "game_session: TechLevel calibration exceeded the starting cap")
		check(tech_calibration_session.calibrate_item_tech_level(calibrate_id, 4), "game_session: item TechLevel calibration failed: %s" % tech_calibration_session.last_error)
		check(int(tech_calibration_session.state.meta.inventory[0].get("techLevel", 0)) == 4 and float(tech_calibration_session.state.meta.protected_bank.scrap) == float(100 - int(calibration_quote["scrap"])) and float(tech_calibration_session.state.meta.protected_bank.data) == float(50 - int(calibration_quote["data"])), "game_session: TechLevel calibration did not update the item and charge quoted resources")
		check(tech_calibration_session.state.meta.inventory.size() == 12, "game_session: consumed CalibrationCore remained in the secured inventory")
	var tier_upgrade_session: GameSession = GameSession.new()
	tier_upgrade_session.configure_save_directory("user://test-saves/tier-upgrade")
	if check(tier_upgrade_session.start_new_game(1762900000500), "game_session: could not create an affix-tier profile"):
		var tier_payload: Dictionary = tier_upgrade_session.state.to_payload()
		tier_payload["meta"]["unlockedForpost"] = 8
		tier_payload["meta"]["garage"]["WORKSHOP"] = 3
		tier_payload["meta"]["protectedBank"]["SCRAP"] = 100.0
		tier_payload["meta"]["protectedBank"]["DATA"] = 100.0
		var tier_item: Dictionary = tier_payload["meta"]["inventory"][0]
		tier_item["techLevel"] = 5
		tier_item["rarity"] = "RARE"
		tier_item["tr"] = 18.0
		tier_item["affixes"] = [{"affixId": "AF_KDM", "tier": 1, "value": 5.0, "rawRoll": 1.0, "tierBoosted": false, "center": 5.0, "min": 4.0, "max": 6.0}]
		tier_payload["meta"]["inventory"][0] = tier_item
		check(tier_upgrade_session._commit_payload(tier_payload), "game_session: affix-tier fixture could not be saved")
		var tier_item_id: String = str(tier_item.get("itemId", ""))
		var tier_scale: float = CydleFormula.new().reward_scale(5.0)
		var tier_scrap_cost: int = ceili(20.0 * tier_scale)
		var tier_data_cost: int = ceili(5.0 * tier_scale)
		check(tier_upgrade_session.upgrade_item_affix_tier(tier_item_id, 0), "game_session: tier upgrade failed: %s" % tier_upgrade_session.last_error)
		var upgraded_affix: Dictionary = tier_upgrade_session.state.meta.inventory[0]["affixes"][0]
		check(str(tier_upgrade_session.state.meta.inventory[0].get("itemId", "")) == tier_item_id and int(upgraded_affix.get("tier", 0)) == 2 and float(upgraded_affix.get("value", 0.0)) >= 7.2 and float(upgraded_affix.get("value", 0.0)) <= 10.8, "game_session: tier upgrade did not preserve identity or use the new tier range")
		check(float(tier_upgrade_session.state.meta.inventory[0].get("tr", 0.0)) == 12.0 and is_equal_approx(tier_upgrade_session.state.meta.protected_bank.scrap, 100.0 - tier_scrap_cost) and is_equal_approx(tier_upgrade_session.state.meta.protected_bank.data, 100.0 - tier_data_cost), "game_session: tier upgrade did not charge its declared resources")
		check(not tier_upgrade_session.upgrade_item_affix_tier(tier_item_id, 0), "game_session: affix was upgraded above the TechLevel tier cap")
	var garage_session: GameSession = GameSession.new()
	garage_session.configure_save_directory("user://test-saves/garage-upgrades")
	if check(garage_session.start_new_game(1762900000600), "game_session: could not create a garage-upgrade profile"):
		var garage_payload: Dictionary = garage_session.state.to_payload()
		garage_payload["meta"]["protectedBank"]["CREDITS"] = 500.0
		garage_payload["meta"]["protectedBank"]["SCRAP"] = 200.0
		garage_payload["meta"]["protectedBank"]["DATA"] = 100.0
		check(garage_session._commit_payload(garage_payload), "game_session: garage-upgrade currency fixture could not be saved")
		var workshop_quote: Dictionary = garage_session.garage_upgrade_quote("WORKSHOP")
		check(bool(workshop_quote.get("valid", false)) and int(workshop_quote.get("credits", 0)) == 65 and int(workshop_quote.get("scrap", 0)) == 25, "game_session: WORKSHOP L2 price differs from the master formula")
		var protected_starter_id: String = str(garage_session.state.meta.inventory[0].get("itemId", ""))
		check(not garage_session.calibrate_item_affix(protected_starter_id, 0) and garage_session.last_error.contains("WORKSHOP уровня 2"), "game_session: affix roll editing bypassed the WORKSHOP L2 gate")
		check(not garage_session.upgrade_item_affix_tier(protected_starter_id, 0) and garage_session.last_error.contains("WORKSHOP уровня 3"), "game_session: tier upgrade bypassed the WORKSHOP L3 gate")
		check(garage_session.upgrade_garage_object("WORKSHOP") and garage_session.garage_level("WORKSHOP") == 2, "game_session: WORKSHOP could not reach L2")
		check(garage_session.upgrade_garage_object("WORKSHOP") and garage_session.garage_level("WORKSHOP") == 3, "game_session: WORKSHOP could not reach L3")
		check(not garage_session.garage_upgrade_quote("WORKSHOP").get("valid", false), "game_session: garage object exceeded max level 3")
		check(not garage_session.garage_upgrade_quote("NEUROLAB").get("valid", false), "game_session: NEUROLAB L2 unlocked before sector 5")
		var gates_payload: Dictionary = garage_session.state.to_payload()
		gates_payload["meta"]["maxSectorCleared"] = 6
		gates_payload["meta"]["unlockedForpost"] = 4
		check(garage_session._commit_payload(gates_payload), "game_session: garage gate fixture could not be saved")
		check(garage_session.upgrade_garage_object("NEUROLAB") and garage_session.state.meta.unlocked_implant_slots == 5, "game_session: NEUROLAB L2 did not unlock implant socket five")
		check(garage_session.upgrade_garage_object("HANGAR") and garage_session.state.meta.unlocked_drone_slots == 2, "game_session: HANGAR L2 did not unlock drone socket two")
		check(garage_session.state.meta.protected_bank.credits < 500.0 and garage_session.state.meta.protected_bank.scrap < 200.0, "game_session: garage upgrades did not spend protected resources")
	var intel_session: GameSession = GameSession.new()
	intel_session.configure_save_directory("user://test-saves/garage-intel")
	if check(intel_session.start_new_game(1762900000900), "game_session: could not create an Intel profile"):
		var intel_payload: Dictionary = intel_session.state.to_payload()
		intel_payload["meta"]["garage"]["INTEL"] = 3
		check(intel_session._commit_payload(intel_payload), "game_session: Intel fixture could not be saved")
		check(intel_session.start_expedition("intel-scan"), "game_session: Intel scan route could not start")
		var intel_report: Dictionary = intel_session.route_intel()
		var revealed_next_layer: bool = false
		for edge_value: Variant in intel_session.state.run.graph.get("edges", []):
			var edge: Dictionary = edge_value
			if str(edge.get("from", "")) == "START":
				continue
			var visible_node: Dictionary = intel_report.get("nodes", {}).get(str(edge.get("to", "")), {})
			if bool(visible_node.get("revealed", false)):
				revealed_next_layer = true
				check(visible_node.has("type") and visible_node.has("threat") and visible_node.has("lootHint"), "game_session: INTEL L3 omitted scanned type or reward bands")
		check(revealed_next_layer, "game_session: INTEL L3 did not scan one layer beyond adjacent nodes")
	var medical_session: GameSession = GameSession.new()
	medical_session.configure_save_directory("user://test-saves/garage-medical")
	if check(medical_session.start_new_game(1762900000700), "game_session: could not create a medical-bay profile"):
		var medical_payload: Dictionary = medical_session.state.to_payload()
		medical_payload["meta"]["garage"]["GARAGE_MED"] = 2
		medical_payload["meta"]["protectedBank"]["CREDITS"] = 5.0
		check(medical_session._commit_payload(medical_payload), "game_session: medical revive fixture could not be saved")
		check(medical_session.start_expedition("medical-revive"), "game_session: could not start medical revive scenario")
		var defeated_run: Dictionary = medical_session.state.run.to_dictionary()
		check(medical_session._resolve_combat_defeat(defeated_run, "medical-test-node"), "game_session: L2 medical bay defeat transaction failed: %s" % medical_session.last_error)
		check(is_zero_approx(medical_session.state.meta.protected_bank.credits) and medical_session.state.run.phase == "DEFEATED", "game_session: L2 medical bay did not apply the discounted 5-credit revive")
	var medical_restore_session: GameSession = GameSession.new()
	medical_restore_session.configure_save_directory("user://test-saves/garage-medical-restore")
	if check(medical_restore_session.start_new_game(1762900000800), "game_session: could not create a medical-restore profile"):
		var restore_payload: Dictionary = medical_restore_session.state.to_payload()
		restore_payload["meta"]["garage"]["GARAGE_MED"] = 3
		restore_payload["meta"]["transport"]["hull"] = 40.0
		restore_payload["meta"]["protectedBank"]["CREDITS"] = 50.0
		check(medical_restore_session._commit_payload(restore_payload), "game_session: medical-restore fixture could not be saved")
		check(medical_restore_session.start_expedition("paid-medical-restore", true), "game_session: paid medical restoration did not start: %s" % medical_restore_session.last_error)
		check(is_equal_approx(float(medical_restore_session.state.run.resources.get("hull", 0.0)), float(medical_restore_session.state.run.resources.get("maxHull", 0.0))) and is_equal_approx(medical_restore_session.state.meta.protected_bank.credits, 42.0), "game_session: medical restore did not restore hull and charge ceil(8 × R(depth))")
	var tactics_session: GameSession = GameSession.new()
	tactics_session.configure_save_directory("user://test-saves/tactic-editor")
	if check(tactics_session.start_new_game(1762900000950), "game_session: could not create a tactic-editor profile"):
		var tactics_payload: Dictionary = tactics_session.state.to_payload()
		tactics_payload["meta"]["garage"]["SERVER"] = 2
		check(tactics_session._commit_payload(tactics_payload), "game_session: tactic-editor fixture could not be saved")
		check(tactics_session.set_tactic_rule_enabled("starter-burst", false), "game_session: tactic rule could not be disabled: %s" % tactics_session.last_error)
		check(not tactics_session.active_tactic().get("rules", []).filter(func(rule: Dictionary) -> bool: return str(rule.get("id", "")) == "starter-burst")[0].get("enabled", true), "game_session: disabled tactic rule was not persisted")
		check(tactics_session.set_tactic_rule_skill("starter-burst", "SK_EMP") and not tactics_session.set_tactic_rule_skill("starter-burst", "SK_PIERCE"), "game_session: tactic skill selector accepted an uninstalled skill or rejected an installed one")
		check(tactics_session.set_tactic_rule_target("starter-burst", "boss") and not tactics_session.set_tactic_rule_target("starter-burst", "unknown"), "game_session: tactic target selector validation failed")
		check(tactics_session.set_tactic_rule_condition("starter-burst", {"kind": "hpBelow", "value": 0.4}) and not tactics_session.set_tactic_rule_condition("starter-burst", {"kind": "hpBelow", "value": 1.4}), "game_session: tactic condition thresholds were not validated")
		check(tactics_session.move_tactic_rule("starter-auto", -1), "game_session: tactic priority could not be reordered: %s" % tactics_session.last_error)
		var added_before: int = tactics_session.active_tactic().get("rules", []).size()
		check(tactics_session.add_tactic_rule("SK_SHIELD") and tactics_session.active_tactic().get("rules", []).size() == added_before + 1, "game_session: user tactic rule could not be added: %s" % tactics_session.last_error)
		var added_rule: Dictionary = tactics_session.active_tactic().get("rules", [])[-1]
		check(int(added_rule.get("priority", 0)) < 0, "game_session: appended tactic rule did not receive the lowest priority")
		check(tactics_session.duplicate_active_tactic(), "game_session: SERVER L2 could not duplicate a tactic profile: %s" % tactics_session.last_error)
		for _copy_index: int in range(3):
			check(tactics_session.duplicate_active_tactic(), "game_session: profile limit rejected a valid duplicate: %s" % tactics_session.last_error)
		check(tactics_session.state.meta.tactics.size() == 5 and not tactics_session.duplicate_active_tactic(), "game_session: SERVER profile limit exceeded five or rejected state was incorrect")
		check(tactics_session.select_tactic("DEFAULT"), "game_session: saved tactic profile could not be reselected: %s" % tactics_session.last_error)
		var tactics_reload: GameSession = GameSession.new()
		tactics_reload.configure_save_directory("user://test-saves/tactic-editor")
		check(tactics_reload.load_saved_game() and tactics_reload.state.meta.tactics.size() == 5 and str(tactics_reload.active_tactic().get("id", "")) == "DEFAULT", "game_session: tactic changes or profile selection did not survive save reload")
		check(tactics_session.start_expedition("tactics-lock-test") and not tactics_session.set_tactic_rule_enabled("starter-burst", true), "game_session: tactic editor remained mutable during an expedition")
	var resumed: GameSession = GameSession.new()
	resumed.configure_save_directory("user://test-saves/game-session")
	check(resumed.load_saved_game(), "game_session: persisted state did not reload: %s" % resumed.last_error)
	check(resumed.state.run.current_node_id == session.state.run.current_node_id, "game_session: route position changed after reload")
	var event_session: GameSession = GameSession.new()
	event_session.configure_save_directory("user://test-saves/game-session-events")
	if check(event_session.start_new_game(1762900000100), "game_session: could not create an event-test profile") and check(event_session.start_expedition("fixed-event-seed"), "game_session: could not start event-test run"):
		var event_payload: Dictionary = event_session.state.to_payload()
		event_payload["run"]["graph"] = {"layers": [[{"id": "event-test", "layer": 0, "type": "EVENT", "eventId": "EV02", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "event-test", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		check(event_session._commit_payload(event_payload), "game_session: could not install isolated event fixture: %s" % event_session.last_error)
		check(event_session.travel_to("event-test"), "game_session: event node travel failed: %s" % event_session.last_error)
		check(event_session.current_event().get("id", "") == "EV02", "game_session: event node did not resolve its canonical definition")
		check(event_session.resolve_event("A"), "game_session: event choice did not resolve: %s" % event_session.last_error)
		check(event_session.state.run.events_seen.has("EV02") and event_session.state.run.wanted == 10.0, "game_session: event outcome flags were not persisted")
		var mutation_payload: Dictionary = event_session.state.to_payload()
		mutation_payload["run"]["graph"] = {"layers": [[{"id": "mutation-test", "layer": 0, "type": "EVENT", "eventId": "EV22", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "mutation-test", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		mutation_payload["run"]["currentNodeId"] = "START"
		mutation_payload["run"]["phase"] = "ROUTE"
		check(event_session._commit_payload(mutation_payload), "game_session: could not install mutation event fixture")
		check(event_session.travel_to("mutation-test"), "game_session: mutation event travel failed")
		check(event_session.resolve_event("A"), "game_session: temporary mutation event failed: %s" % event_session.last_error)
		check(event_session.state.run.temporary_mutation_ids == ["MUT_REGEN"], "game_session: event mutation did not enter the temporary run build")
	return failure_count == 0
