extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var autopilot_session: GameSession = GameSession.new()
	autopilot_session.configure_save_directory("user://test-saves/autopilot")
	if check(autopilot_session.start_new_game(1762900000050), "game_session: could not create an autopilot profile"):
		check(autopilot_session.start_expedition("autopilot-fixed-seed"), "game_session: autopilot expedition could not start")
		check(autopilot_session.set_autopilot_enabled(true), "game_session: offline autopilot could not be enabled")
		var resumed_autopilot: GameSession = GameSession.new()
		resumed_autopilot.configure_save_directory("user://test-saves/autopilot")
		check(resumed_autopilot.load_saved_game() and resumed_autopilot.state.run.autopilot_enabled, "game_session: offline autopilot opt-in did not persist")
		resumed_autopilot.state.updated_at = int(Time.get_unix_time_from_system() * 1000.0) - 120000
		check(bool(resumed_autopilot._repository.save_game(GameSession.SLOT_ID, resumed_autopilot.state, resumed_autopilot.state.updated_at).get("ok", false)), "game_session: could not prepare an elapsed offline interval")
		var offline_resumed: GameSession = GameSession.new()
		offline_resumed.configure_save_directory("user://test-saves/autopilot")
		check(offline_resumed.load_saved_game(), "game_session: offline recovery could not load the profile: %s" % offline_resumed.last_error)
		var offline_report: Dictionary = offline_resumed.last_autopilot_report
		check(not offline_report.is_empty() and int(offline_report.get("simulatedMs", 0)) > 0 and int(offline_report.get("nodesVisited", 0)) > 0, "game_session: elapsed offline wall time did not run the shared autopilot simulation: %s" % offline_report)
		var autopilot_report: Dictionary = offline_resumed.simulate_autopilot(600000)
		check(bool(autopilot_report.get("ok", false)), "game_session: autopilot did not produce a route report: %s" % autopilot_report)
		check(not ["SAFE_ERROR_STOP", "RUNNING"].has(str(autopilot_report.get("status", ""))), "game_session: autopilot returned without a clear stop state")
	var contract_session: GameSession = GameSession.new()
	contract_session.configure_save_directory("user://test-saves/contracts")
	if check(contract_session.start_new_game(1762900000100), "game_session: could not create a contract profile"):
		var offers: Array[Dictionary] = contract_session.available_contract_offers()
		var offers_repeat: Array[Dictionary] = contract_session.available_contract_offers()
		var offer_ids: Array[String] = []
		var offer_targets_match: bool = offers.size() == 3 and offers_repeat.size() == offers.size()
		for offer_index: int in range(offers.size()):
			offer_ids.append(str(offers[offer_index].get("id", "")))
			if str(offers[offer_index].get("targetBiome", "")) != "B01" or str(offers_repeat[offer_index].get("id", "")) != str(offers[offer_index].get("id", "")):
				offer_targets_match = false
		check(offer_targets_match and offer_ids.has("CT_HUNT") and offer_ids.has("CT_TECH") and offer_ids.has("CT_ESCORT"), "game_session: world-seeded offers did not expose all contract types for the current biome")
		check(str(offers[0].get("eventId", "")) == "contract-offer:1:%s" % str(offers[0].get("id", "")), "game_session: generated offer did not retain its world event identifier")
		check(contract_session.start_expedition("contract-fixed-seed", false, "CT_HUNT"), "game_session: HUNT contract failed to start: %s" % contract_session.last_error)
		if contract_session.state.run != null:
			var contract: Dictionary = contract_session.state.run.contract
			check(str(contract.get("status", "")) == "ACTIVE" and not str(contract.get("targetNodeId", "")).is_empty(), "game_session: HUNT contract did not retain an active target")
			var found_target: bool = false
			for layer: Array in contract_session.state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("id", "")) == str(contract.get("targetNodeId", "")):
						found_target = str(node.get("type", "")) == "ELITE" and not node.get("enemies", []).is_empty() and str(node["enemies"][0].get("templateId", "")) == str(contract.get("targetEnemyId", ""))
			check(found_target, "game_session: HUNT target did not exist in the generated road graph")
			var round_trip: Dictionary = GameSaveState.new().parse_payload(contract_session.state.to_payload())
			check(bool(round_trip.get("ok", false)) and str(round_trip["state"].run.contract.get("instanceId", "")) == str(contract.get("instanceId", "")), "game_session: active contract save did not validate and roundtrip")
			var payout: Dictionary = contract_session.state.to_payload()
			var credits_before: float = float(payout["run"]["runWallet"].get("CREDITS", 0.0))
			check(contract_session._complete_contract(payout, {"CREDITS": 30}, {"rarity": "RARE", "tag": "weapon"}), "game_session: contract reward transaction failed: %s" % contract_session.last_error)
			check(contract_session._commit_payload(payout), "game_session: contract reward transaction could not be saved: %s" % contract_session.last_error)
			check(str(contract_session.state.run.contract.get("status", "")) == "COMPLETE" and contract_session.state.run.unsecured_cargo.size() == 1 and is_equal_approx(contract_session.state.run.wallet.credits, credits_before + 30.0), "game_session: contract reward did not grant its item and credits")
			var repeat_payout: Dictionary = contract_session.state.to_payload()
			contract_session._complete_contract(repeat_payout, {"CREDITS": 30}, {"rarity": "RARE", "tag": "weapon"})
			check(contract_session._commit_payload(repeat_payout) and is_equal_approx(contract_session.state.run.wallet.credits, credits_before + 30.0) and contract_session.state.run.unsecured_cargo.size() == 1, "game_session: repeated contract payout duplicated its grant")
	var tech_offer_session: GameSession = GameSession.new()
	tech_offer_session.configure_save_directory("user://test-saves/contracts-tech-any-biome")
	if check(tech_offer_session.start_new_game(1762900000105), "game_session: could not create a cross-biome TECH profile"):
		if check(tech_offer_session.start_expedition("tech-contract-b01", false, "CT_TECH"), "game_session: generated TECH offer was rejected outside its template biome: %s" % tech_offer_session.last_error):
			var tech_target: Dictionary = {}
			for layer: Array in tech_offer_session.state.run.graph.get("layers", []):
				for candidate: Dictionary in layer:
					if str(candidate.get("id", "")) == str(tech_offer_session.state.run.contract.get("targetNodeId", "")): tech_target = candidate
			check(str(tech_offer_session.state.run.biome) == "B01" and str(tech_offer_session.state.run.contract.get("targetBiome", "")) == "B01" and str(tech_target.get("type", "")) == "CACHE", "game_session: cross-biome TECH offer did not inject its target cache")
	var signal_session: GameSession = GameSession.new()
	signal_session.configure_save_directory("user://test-saves/signal-contract")
	if check(signal_session.start_new_game(1762900000110), "game_session: could not create a signal-contract profile"):
		var signal_unlock_payload: Dictionary = signal_session.state.to_payload()
		signal_unlock_payload["meta"]["unlockedForpost"] = 4
		signal_unlock_payload["meta"]["campaignFlags"].append("quest-unlock:signalContract:U09")
		check(signal_session._commit_payload(signal_unlock_payload), "game_session: could not prepare the unlocked signal contract")
		var signal_offers: Array[Dictionary] = signal_session.available_contract_offers()
		var signal_offer_found: bool = false
		for offer: Dictionary in signal_offers:
			if str(offer.get("id", "")) == "SIGNAL_U09" and str(offer.get("targetBiome", "")) == "B04": signal_offer_found = true
		check(signal_offer_found, "game_session: unlocked U09 signal contract was not offered in its source biome")
		if signal_session.start_expedition("signal-contract-seed", false, "SIGNAL_U09"):
			var signal_contract: Dictionary = signal_session.state.run.contract
			check(str(signal_contract.get("kind", "")) == "SIGNAL" and str(signal_contract.get("targetUniqueId", "")) == "U09" and not str(signal_contract.get("targetNodeId", "")).is_empty(), "game_session: signal contract did not create a targeted elite encounter")
			var signal_round_trip: Dictionary = GameSaveState.new().parse_payload(signal_session.state.to_payload())
			check(bool(signal_round_trip.get("ok", false)) and str(signal_round_trip["state"].run.contract.get("kind", "")) == "SIGNAL", "game_session: active signal contract did not survive save validation")
			var signal_payout: Dictionary = signal_session.state.to_payload()
			check(signal_session._complete_contract(signal_payout, {}, {"rarity": "UNIQUE", "templateId": "U09"}), "game_session: unique signal contract reward failed: %s" % signal_session.last_error)
			check(signal_session._commit_payload(signal_payout), "game_session: unique signal contract reward could not be saved: %s" % signal_session.last_error)
			var signal_cargo: Array = signal_session.state.run.unsecured_cargo
			check(str(signal_session.state.run.contract.get("status", "")) == "COMPLETE" and signal_cargo.size() == 1 and str(signal_cargo[0].get("templateId", "")) == "U09", "game_session: signal contract did not grant its exact unique item")
			var signal_repeat: Dictionary = signal_session.state.to_payload()
			signal_session._complete_contract(signal_repeat, {}, {"rarity": "UNIQUE", "templateId": "U09"})
			check(signal_session._commit_payload(signal_repeat) and signal_session.state.run.unsecured_cargo.size() == 1, "game_session: repeated signal payout duplicated the unique item")
	var ending_session: GameSession = GameSession.new()
	ending_session.configure_save_directory("user://test-saves/campaign-ending")
	if check(ending_session.start_new_game(1762900000120), "game_session: could not create a campaign-ending profile"):
		check(ending_session.start_expedition("campaign-ending-seed"), "game_session: campaign-ending expedition did not start")
		var ending_payload: Dictionary = ending_session.state.to_payload()
		ending_payload["run"]["depth"] = 12
		ending_payload["run"]["biome"] = "B06"
		ending_payload["run"]["graph"]["depth"] = 12
		ending_payload["run"]["graph"]["biome"] = "B06"
		ending_payload["run"]["phase"] = "CHECKPOINT"
		ending_payload["meta"]["campaignFlags"].append_array(["CAMPAIGN_COMPLETED", "BIOME_HISTORY:11:B06", "BIOME_HISTORY:12:B06"])
		check(ending_session._commit_payload(ending_payload), "game_session: could not prepare the final checkpoint: %s" % ending_session.last_error)
		check(not ending_session.continue_campaign() and ending_session.last_error.contains("исход кампании"), "game_session: final sector continued without an ending choice")
		check(ending_session.resolve_campaign_ending("FACTION_CONTROL", "F_RUST"), "game_session: faction ending could not be resolved: %s" % ending_session.last_error)
		check(ending_session.state.meta.campaign_flags.has("ENDGAME_UNLOCKED") and ending_session.state.meta.campaign_flags.has("ENDING_FACTION:F_RUST"), "game_session: faction ending did not unlock and record endgame control")
		check(ending_session.continue_campaign(), "game_session: campaign could not continue into endgame: %s" % ending_session.last_error)
		check(ending_session.state.run.depth == 13 and ending_session.state.run.biome != "B06", "game_session: endgame did not begin or enforced a three-sector biome streak")
	var deadline_session: GameSession = GameSession.new()
	deadline_session.configure_save_directory("user://test-saves/quest-deadline")
	if check(deadline_session.start_new_game(1762900000130), "game_session: could not create a deadline profile"):
		var deadline_payload: Dictionary = deadline_session.state.to_payload()
		deadline_payload["meta"]["questProgress"] = {"Q02": {"status": "ACTIVE", "stage": 2, "startedDepth": 2, "stageStartedDepth": 2, "completedStages": ["S1"], "choiceHistory": [{"stage": 1, "choiceId": "A", "nodeId": "D2N1"}], "flags": []}}
		check(deadline_session._commit_payload(deadline_payload), "game_session: Q02 deadline fixture could not be saved")
		var expired_meta: Dictionary = deadline_session.state.to_payload()["meta"]
		deadline_session._expire_quest_deadlines(expired_meta, 6)
		check(str(expired_meta["questProgress"]["Q02"].get("status", "")) == "FAILED" and int(expired_meta["reputation"]["F_ECHO"]) == -3, "game_session: Q02 deadline did not fail with its F_ECHO compensation")
		deadline_session._expire_quest_deadlines(expired_meta, 7)
		check(int(expired_meta["reputation"]["F_ECHO"]) == -3, "game_session: Q02 deadline compensation was applied more than once")
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
	var affix_craft_session: GameSession = GameSession.new()
	affix_craft_session.configure_save_directory("user://test-saves/affix-crafting")
	if check(affix_craft_session.start_new_game(1762900000350), "game_session: could not create an affix-crafting profile"):
		var craft_payload: Dictionary = affix_craft_session.state.to_payload()
		var craft_item: Dictionary = craft_payload["meta"]["inventory"][2]
		craft_item["rarity"] = "MODIFIED"
		craft_item["tr"] = 18.0
		craft_item["affixes"] = [{"affixId": "AF_ARM", "tier": 1, "value": 2.0, "rawRoll": 1.0, "tierBoosted": false, "center": 2.0, "min": 2.0, "max": 2.0}]
		craft_payload["meta"]["inventory"][2] = craft_item
		craft_payload["meta"]["protectedBank"]["SCRAP"] = 100.0
		craft_payload["meta"]["protectedBank"]["DATA"] = 100.0
		check(affix_craft_session._commit_payload(craft_payload), "game_session: affix-crafting fixture could not be saved")
		var craft_item_id: String = str(craft_item.get("itemId", ""))
		var replace_quote: Dictionary = affix_craft_session.affix_replacement_options(craft_item_id, 0)
		check(bool(replace_quote.get("valid", false)) and bool(replace_quote.get("affordable", false)) and replace_quote.get("options", []).any(func(option: Dictionary) -> bool: return str(option.get("id", "")) == "AF_HP"), "game_session: replacement preview did not provide a compatible alternate affix")
		var scrap_before_replace: float = affix_craft_session.state.meta.protected_bank.scrap
		var data_before_replace: float = affix_craft_session.state.meta.protected_bank.data
		check(affix_craft_session.replace_item_affix(craft_item_id, 0, "AF_HP"), "game_session: replacing a selected affix failed: %s" % affix_craft_session.last_error)
		var replaced_item: Dictionary = affix_craft_session.state.meta.inventory[2]
		check(str(replaced_item.get("itemId", "")) == craft_item_id and str(replaced_item["affixes"][0].get("affixId", "")) == "AF_HP" and int(replaced_item["affixes"][0].get("tier", 0)) == 1, "game_session: replacement did not preserve item identity and use the TechLevel tier")
		check(is_equal_approx(float(replaced_item.get("tr", 0.0)), 10.0) and is_equal_approx(affix_craft_session.state.meta.protected_bank.scrap, scrap_before_replace) and is_equal_approx(affix_craft_session.state.meta.protected_bank.data, data_before_replace - float(replace_quote["data"])), "game_session: replacement charged the wrong TR or materials")
		var add_quote: Dictionary = affix_craft_session.affix_replacement_options(craft_item_id)
		check(bool(add_quote.get("valid", false)) and bool(add_quote.get("affordable", false)) and int(add_quote.get("tr", 0)) == 10, "game_session: free-slot crafting preview is invalid")
		var scrap_before_add: float = affix_craft_session.state.meta.protected_bank.scrap
		var data_before_add: float = affix_craft_session.state.meta.protected_bank.data
		check(affix_craft_session.add_item_affix(craft_item_id, "AF_SR"), "game_session: adding an affix to a free rarity slot failed: %s" % affix_craft_session.last_error)
		var added_item: Dictionary = affix_craft_session.state.meta.inventory[2]
		check(added_item["affixes"].size() == 2 and str(added_item["affixes"][1].get("affixId", "")) == "AF_SR" and is_equal_approx(float(added_item.get("tr", 0.0)), 0.0), "game_session: added affix did not occupy a free slot or spend exactly 10 TR")
		check(is_equal_approx(affix_craft_session.state.meta.protected_bank.scrap, scrap_before_add - float(add_quote["scrap"])) and is_equal_approx(affix_craft_session.state.meta.protected_bank.data, data_before_add - float(add_quote["data"])), "game_session: free-slot crafting charged the wrong materials")
		check(not affix_craft_session.add_item_affix(craft_item_id, "AF_ACC"), "game_session: crafting exceeded the item's rarity affix cap")
	var disposal_session: GameSession = GameSession.new()
	disposal_session.configure_save_directory("user://test-saves/item-disposal")
	if check(disposal_session.start_new_game(1762900000360), "game_session: could not create an item-disposal profile"):
		var disposal_catalog: ItemCatalog = ItemCatalog.new()
		check(bool(disposal_catalog.load_catalog().get("ok", false)), "game_session: disposal test catalog failed to load")
		var disposal_factory: ItemFactory = ItemFactory.new()
		var disposal_rng: DeterministicRng = DeterministicRng.new()
		disposal_rng.seed("item-disposal-test", 1)
		var sale_created: Dictionary = disposal_factory.create_item(disposal_rng, disposal_catalog, {"templateId": "ARM_CLOTH", "techLevel": 1, "rarity": "COMMON", "secured": true, "originGrantId": "test-sale-item", "origin": "TEST", "acquiredAt": 1762900000360})
		var dismantle_created: Dictionary = disposal_factory.create_item(disposal_rng, disposal_catalog, {"templateId": "ARM_NET", "techLevel": 1, "rarity": "COMMON", "secured": true, "originGrantId": "test-dismantle-item", "origin": "TEST", "acquiredAt": 1762900000360})
		check(bool(sale_created.get("ok", false)) and bool(dismantle_created.get("ok", false)), "game_session: could not create sale/dismantle fixture items")
		if bool(sale_created.get("ok", false)) and bool(dismantle_created.get("ok", false)):
			var sale_item: Dictionary = (sale_created["item"] as ItemInstance).to_dictionary()
			var dismantle_item: Dictionary = (dismantle_created["item"] as ItemInstance).to_dictionary()
			var disposal_payload: Dictionary = disposal_session.state.to_payload()
			disposal_payload["meta"]["inventory"].append(sale_item)
			disposal_payload["meta"]["inventory"].append(dismantle_item)
			check(disposal_session._commit_payload(disposal_payload), "game_session: disposal fixtures failed save validation: %s" % disposal_session.last_error)
			var credits_before_sale: float = disposal_session.state.meta.protected_bank.credits
			var sale_quote: Dictionary = disposal_session.item_disposal_quote(str(sale_item["itemId"]), "SELL")
			check(bool(sale_quote.get("valid", false)) and int(sale_quote.get("credits", 0)) > 0, "game_session: sale preview did not calculate an offer")
			check(disposal_session.sell_item(str(sale_item["itemId"])), "game_session: sale transaction failed: %s" % disposal_session.last_error)
			check(is_equal_approx(disposal_session.state.meta.protected_bank.credits, credits_before_sale + float(sale_quote["credits"])) and disposal_session._secured_inventory_item(str(sale_item["itemId"])).is_empty(), "game_session: sale did not atomically pay and remove its item")
			check(not disposal_session.sell_item(str(sale_item["itemId"])), "game_session: a sold item granted sale value more than once")
			var scrap_before_dismantle: float = disposal_session.state.meta.protected_bank.scrap
			var data_before_dismantle: float = disposal_session.state.meta.protected_bank.data
			var dismantle_quote: Dictionary = disposal_session.item_disposal_quote(str(dismantle_item["itemId"]), "DISMANTLE")
			check(bool(dismantle_quote.get("valid", false)) and int(dismantle_quote.get("scrap", 0)) > 0 and int(dismantle_quote.get("data", 0)) == 1, "game_session: digital-item dismantle preview did not include capped materials")
			check(disposal_session.dismantle_item(str(dismantle_item["itemId"])), "game_session: dismantle transaction failed: %s" % disposal_session.last_error)
			check(is_equal_approx(disposal_session.state.meta.protected_bank.scrap, scrap_before_dismantle + float(dismantle_quote["scrap"])) and is_equal_approx(disposal_session.state.meta.protected_bank.data, data_before_dismantle + 1.0) and disposal_session._secured_inventory_item(str(dismantle_item["itemId"])).is_empty(), "game_session: dismantling did not return capped scrap/data and consume its item")
			check(disposal_session.state.meta.disassembly_history.size() == 1 and disposal_session.can_undo_last_dismantle(), "game_session: dismantle history or immediate undo was not persisted")
			var dismantle_roundtrip: Dictionary = GameSaveState.new().parse_payload(disposal_session.state.to_payload())
			check(bool(dismantle_roundtrip.get("ok", false)) and dismantle_roundtrip["state"].meta.disassembly_history.size() == 1, "game_session: dismantle history did not survive save-schema roundtrip")
			check(disposal_session.undo_last_dismantle(), "game_session: immediate dismantle undo failed: %s" % disposal_session.last_error)
			check(not disposal_session.can_undo_last_dismantle() and not disposal_session._secured_inventory_item(str(dismantle_item["itemId"])).is_empty() and is_equal_approx(disposal_session.state.meta.protected_bank.scrap, scrap_before_dismantle) and is_equal_approx(disposal_session.state.meta.protected_bank.data, data_before_dismantle), "game_session: undo did not restore the same item and reverse the material grant")
			check(bool(disposal_session.state.meta.disassembly_history[0].get("undone", false)), "game_session: historical entry was not updated as undone")
			check(disposal_session.dismantle_item(str(dismantle_item["itemId"])), "game_session: restored item could not be dismantled again")
			check(disposal_session.start_expedition("dismantle-undo-boundary"), "game_session: undo boundary test expedition could not start")
			check(disposal_session.can_undo_last_dismantle(), "game_session: disassembly undo expired before the next route node")
			var first_route_node: String = ""
			for edge: Dictionary in disposal_session.state.run.graph.get("edges", []):
				if str(edge.get("from", "")) == "START":
					first_route_node = str(edge.get("to", ""))
					break
			check(not first_route_node.is_empty() and disposal_session.travel_to(first_route_node), "game_session: undo boundary could not enter the first route node")
			check(not disposal_session.can_undo_last_dismantle() and disposal_session.state.meta.disassembly_undo.is_empty(), "game_session: entering the next node did not expire dismantle undo")
	var base_craft_session: GameSession = GameSession.new()
	base_craft_session.configure_save_directory("user://test-saves/base-crafting")
	if check(base_craft_session.start_new_game(1762900000370), "game_session: could not create a base-crafting profile"):
		var base_payload: Dictionary = base_craft_session.state.to_payload()
		base_payload["meta"]["protectedBank"]["SCRAP"] = 100.0
		base_payload["meta"]["protectedBank"]["DATA"] = 100.0
		check(base_craft_session._commit_payload(base_payload), "game_session: base-craft resources could not be saved")
		var no_blueprint: Dictionary = base_craft_session.base_item_craft_quote("ARM_NET", 1)
		check(not bool(no_blueprint.get("valid", false)) and no_blueprint.get("error", "").contains("схема"), "game_session: base item crafting did not require a blueprint")
		var blueprint_payload: Dictionary = base_craft_session.state.to_payload()
		blueprint_payload["meta"]["campaignFlags"].append("quest-unlock:schematic:ARM_NET")
		check(base_craft_session._commit_payload(blueprint_payload), "game_session: unlocked blueprint fixture could not be saved")
		var base_quote: Dictionary = base_craft_session.base_item_craft_quote("ARM_NET", 1)
		check(bool(base_quote.get("valid", false)) and bool(base_quote.get("affordable", false)) and int(base_quote.get("scrap", 0)) == ceili(18.0 * CydleFormula.new().reward_scale(1.0)) and int(base_quote.get("data", 0)) == ceili(10.0 * CydleFormula.new().reward_scale(1.0)), "game_session: base crafting preview differs from the Master Spec recipe")
		var inventory_before_craft: int = base_craft_session.state.meta.inventory.size()
		check(base_craft_session.craft_base_item("ARM_NET", 1), "game_session: blueprinted base item could not be crafted: %s" % base_craft_session.last_error)
		var crafted_item: Dictionary = base_craft_session.state.meta.inventory[-1]
		check(base_craft_session.state.meta.inventory.size() == inventory_before_craft + 1 and str(crafted_item.get("templateId", "")) == "ARM_NET" and bool(crafted_item.get("secured", false)) and str(crafted_item.get("origin", "")) == "craft", "game_session: base crafting did not add a secured correctly sourced item")
		check(is_equal_approx(base_craft_session.state.meta.protected_bank.scrap, 100.0 - float(base_quote["scrap"])) and is_equal_approx(base_craft_session.state.meta.protected_bank.data, 100.0 - float(base_quote["data"])), "game_session: base crafting did not atomically charge recipe materials")
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
	var anomaly_session: GameSession = GameSession.new()
	anomaly_session.configure_save_directory("user://test-saves/anomaly-route")
	if check(anomaly_session.start_new_game(1762900000905), "game_session: could not create an anomaly profile"):
		check(anomaly_session.start_expedition("anomaly-route-seed"), "game_session: could not prepare an anomaly run")
		var anomaly_generated: Dictionary = anomaly_session._generator.generate("anomaly-route-seed", 9, "B06", false)
		var anomaly_payload: Dictionary = anomaly_session.state.to_payload()
		var anomaly_graph: Dictionary = anomaly_generated.get("graph", {})
		anomaly_payload["meta"]["garage"]["INTEL"] = 3
		anomaly_payload["meta"]["questProgress"] = {"Q06": {"status": "ACTIVE", "stage": 2, "startedDepth": 9, "stageStartedDepth": 9, "completedStages": ["S1"], "choiceHistory": [{"stage": 1, "choiceId": "A", "nodeId": "prior-event"}], "flags": []}}
		anomaly_payload["run"]["depth"] = 9
		anomaly_payload["run"]["biome"] = "B06"
		anomaly_payload["run"]["graph"] = anomaly_graph
		anomaly_payload["run"]["currentNodeId"] = "START"
		anomaly_payload["run"]["visitedNodeIds"] = []
		anomaly_payload["run"]["clearedNodeIds"] = []
		anomaly_payload["run"]["phase"] = "ROUTE"
		check(anomaly_session._commit_payload(anomaly_payload), "game_session: B06 anomaly fixture could not be saved: %s" % anomaly_session.last_error)
		var anomaly_node: Dictionary = anomaly_graph["layers"][1][1]
		var anomaly_id: String = str(anomaly_node.get("id", ""))
		var reduced_intel: Dictionary = anomaly_session.route_intel()
		check(int(reduced_intel.get("effectiveLevel", 0)) == 2 and not bool(reduced_intel.get("nodes", {}).get(anomaly_id, {}).get("revealed", false)), "game_session: B06 did not reduce route scouting by one INTEL level")
		var early_payload: Dictionary = anomaly_session.state.to_payload()
		early_payload["meta"]["questProgress"]["Q06"]["flags"] = ["earlyAnomaly"]
		check(anomaly_session._commit_payload(early_payload), "game_session: Q06 preview flag could not be saved")
		var anomaly_intel: Dictionary = anomaly_session.route_intel().get("nodes", {}).get(anomaly_id, {})
		check(bool(anomaly_intel.get("preview", false)) and str(anomaly_intel.get("anomalyProtocol", "")) == str(anomaly_node.get("anomalyProtocol", "")), "game_session: Q06 early anomaly preview did not reveal the next B06 protocol")
		var route_payload: Dictionary = anomaly_session.state.to_payload()
		route_payload["run"]["currentNodeId"] = str(anomaly_graph["layers"][0][0].get("id", ""))
		route_payload["run"]["visitedNodeIds"] = [route_payload["run"]["currentNodeId"]]
		var tech_contract: Dictionary = {"id": "CT_TECH", "kind": "TECH", "targetBiome": "B06", "instanceId": "anomaly-contract-instance", "status": "ACTIVE", "targetNodeId": anomaly_id, "targetTechTag": "tech", "rewardClaimed": false, "combatNodes": 0}
		route_payload["run"]["contract"] = tech_contract
		check(anomaly_session._commit_payload(route_payload), "game_session: anomaly TECH contract fixture could not be saved: %s" % anomaly_session.last_error)
		check(anomaly_session.travel_to(anomaly_id), "game_session: B06 anomaly was not reachable from the route: %s" % anomaly_session.last_error)
		check(anomaly_session.state.meta.campaign_flags.has("ANOMALY_PREVIEW_USED:EARLY"), "game_session: early anomaly preview was not consumed on approach")
		check(anomaly_session.begin_combat(), "game_session: anomaly did not enter the shared combat simulator: %s" % anomaly_session.last_error)
		if anomaly_session.combat_state() != null:
			anomaly_session.combat_state().outcome = "VICTORY"
			check(anomaly_session.resolve_active_combat(), "game_session: anomaly battle settlement failed: %s" % anomaly_session.last_error)
		check(anomaly_session.state.run.phase == "NODE" and anomaly_session.state.run.cleared_node_ids.has(anomaly_id), "game_session: anomaly victory did not retain a cleared node for its follow-up")
		check(str(anomaly_session.state.run.contract.get("status", "")) == "COMPLETE", "game_session: clearing the TECH target anomaly did not pay its contract")
		check(not anomaly_session.begin_combat(), "game_session: cleared anomaly could be fought and rewarded twice")
		check(anomaly_session.resolve_service_node("LEAVE_NODE"), "game_session: cleared anomaly could not be exited: %s" % anomaly_session.last_error)
		var q06_event: Dictionary = anomaly_graph["layers"][3][0]
		var q06_payload: Dictionary = anomaly_session.state.to_payload()
		q06_payload["run"]["currentNodeId"] = str(q06_event.get("id", ""))
		q06_payload["run"]["phase"] = "NODE"
		q06_payload["run"]["wanted"] = 25.0
		check(anomaly_session._commit_payload(q06_payload), "game_session: Q06 follow-up event fixture could not be saved")
		var q06_stages: Array[Dictionary] = anomaly_session.available_quest_stages()
		check(q06_stages.size() == 1 and str(q06_stages[0].get("quest", {}).get("id", "")) == "Q06", "game_session: Q06 stage two did not become available after surviving the B06 anomaly")
		check(anomaly_session.resolve_quest_choice("Q06", "A"), "game_session: Q06 anomaly route choice could not resolve: %s" % anomaly_session.last_error)
		check(float(anomaly_session.state.run.wanted) == 20.0 and int(anomaly_session.state.meta.quest_progress["Q06"].get("stage", 0)) == 3, "game_session: Q06 anomaly route choice did not apply its wanted reduction and progress")
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
	var simulation_session: GameSession = GameSession.new()
	simulation_session.configure_save_directory("user://test-saves/simulation-lab")
	if check(simulation_session.start_new_game(1762900000960), "game_session: could not create a Simulation Lab profile"):
		var simulation_payload: Dictionary = simulation_session.state.to_payload()
		var comparison_item: Dictionary = simulation_payload["meta"]["inventory"][0].duplicate(true)
		comparison_item["itemId"] = "lab-comparison-pistol"
		comparison_item["originGrantId"] = "grant:lab-comparison-pistol"
		simulation_payload["meta"]["inventory"].append(comparison_item)
		check(simulation_session._commit_payload(simulation_payload), "game_session: Simulation Lab candidate fixture could not be saved: %s" % simulation_session.last_error)
		var candidate_items: Array[Dictionary] = simulation_session.simulation_equipment_candidates("MAIN")
		check(candidate_items.any(func(candidate: Dictionary) -> bool: return str(candidate.get("itemId", "")) == "lab-comparison-pistol"), "game_session: Simulation Lab did not expose a BuildResolver-valid equipment candidate")
		var simulation_result: Dictionary = simulation_session.simulate_equipment_comparison("MAIN", "lab-comparison-pistol", "E01", 1)
		check(bool(simulation_result.get("ok", false)) and simulation_result.get("results", []).size() == 2, "game_session: paired Simulation Lab combat failed: %s" % str(simulation_result.get("error", "")))
		if bool(simulation_result.get("ok", false)):
			var paired_results: Array = simulation_result["results"]
			check(paired_results[0] == paired_results[1], "game_session: identical builds diverged under a shared deterministic seed")
		check(str(simulation_session.state.meta.equipment.get("MAIN", "")) != "lab-comparison-pistol", "game_session: Simulation Lab mutated the saved equipment loadout")
	var quest_session: GameSession = GameSession.new()
	quest_session.configure_save_directory("user://test-saves/quest-chain")
	if check(quest_session.start_new_game(1762900000970), "game_session: could not create a quest-chain profile"):
		var quest_payload: Dictionary = quest_session.state.to_payload()
		quest_payload["meta"]["maxSectorCleared"] = 1
		quest_payload["meta"]["unlockedForpost"] = 1
		check(quest_session._commit_payload(quest_payload), "game_session: quest unlock fixture could not be saved")
		var quest_catalog: QuestCatalog = QuestCatalog.new()
		var quest_catalog_result: Dictionary = quest_catalog.load_catalog()
		check(bool(quest_catalog_result.get("ok", false)) and int(quest_catalog_result.get("questCount", 0)) == 6 and int(quest_catalog_result.get("contractCount", 0)) == 3, "game_session: all quest chains and contracts were not imported from the legacy data catalog")
		check(quest_session.accept_quest("Q02") and not quest_session.accept_quest("Q02"), "game_session: quest acceptance or duplicate-acceptance protection failed: %s" % quest_session.last_error)
		check(quest_session.start_expedition("quest-chain-seed"), "game_session: quest test expedition could not start")
		var quest_run_payload: Dictionary = quest_session.state.to_payload()
		quest_run_payload["run"]["biome"] = "B01"
		quest_run_payload["run"]["graph"] = {"layers": [[{"id": "quest-event", "layer": 0, "type": "EVENT", "eventId": "EV02", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "quest-event", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		check(quest_session._commit_payload(quest_run_payload), "game_session: quest event fixture could not be saved: %s" % quest_session.last_error)
		check(quest_session.travel_to("quest-event") and quest_session.available_quest_stages().size() == 1, "game_session: active quest stage was not offered at its matching story event")
		check(quest_session.resolve_quest_choice("Q02", "A"), "game_session: quest choice transaction failed: %s" % quest_session.last_error)
		var quest_progress: Dictionary = quest_session.state.meta.quest_progress.get("Q02", {})
		check(str(quest_progress.get("status", "")) == "ACTIVE" and int(quest_progress.get("stage", 0)) == 2 and int(quest_session.state.run.wanted) == 5, "game_session: quest choice did not persist stage, status, and wanted consequence")
		check(not quest_session.resolve_quest_choice("Q02", "A"), "game_session: quest choice could be claimed twice or repeated at the same story node")
		var quest_reload: GameSession = GameSession.new()
		quest_reload.configure_save_directory("user://test-saves/quest-chain")
		check(quest_reload.load_saved_game() and int(quest_reload.state.meta.quest_progress.get("Q02", {}).get("stage", 0)) == 2, "game_session: quest stage did not survive save reload")
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
	var scout_session: GameSession = GameSession.new()
	scout_session.configure_save_directory("user://test-saves/event-route-scouting")
	if check(scout_session.start_new_game(1762900000101), "game_session: could not create an event-scouting profile") and check(scout_session.start_expedition("event-route-scouting"), "game_session: could not start an event-scouting run"):
		var scout_payload: Dictionary = scout_session.state.to_payload()
		scout_payload["run"]["graph"] = {"layers": [
			[{"id": "scout-event", "layer": 0, "type": "EVENT", "eventId": "EV06", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}],
			[{"id": "scout-next-a", "layer": 1, "type": "COMBAT", "threat": "medium", "enemies": [{"templateId": "E01"}], "revealLevel": 1, "lootHint": "combat"}, {"id": "scout-next-b", "layer": 1, "type": "CACHE", "threat": "low", "enemies": [], "revealLevel": 1, "lootHint": "cache"}],
			[{"id": "scout-future-a", "layer": 2, "type": "REPAIR", "threat": "low", "enemies": [], "revealLevel": 1, "lootHint": "repair"}, {"id": "scout-future-b", "layer": 2, "type": "FUEL", "threat": "low", "enemies": [], "revealLevel": 1, "lootHint": "fuel"}]
		], "edges": [
			{"from": "START", "to": "scout-event", "fromLayer": -1, "toLayer": 0, "fuelCost": 1},
			{"from": "scout-event", "to": "scout-next-a", "fromLayer": 0, "toLayer": 1, "fuelCost": 1},
			{"from": "scout-event", "to": "scout-next-b", "fromLayer": 0, "toLayer": 1, "fuelCost": 1},
			{"from": "scout-next-a", "to": "scout-future-a", "fromLayer": 1, "toLayer": 2, "fuelCost": 1},
			{"from": "scout-next-b", "to": "scout-future-b", "fromLayer": 1, "toLayer": 2, "fuelCost": 1}
		]}
		scout_payload["run"]["runWallet"]["DATA"] = 10.0
		check(scout_session._commit_payload(scout_payload), "game_session: event-scouting graph could not be saved: %s" % scout_session.last_error)
		check(scout_session.travel_to("scout-event") and scout_session.resolve_event("A"), "game_session: EV06 did not resolve its map-scan choice: %s" % scout_session.last_error)
		var scouted_ids: Array[String] = scout_session.state.run.scouted_node_ids
		check(scouted_ids == ["scout-next-a", "scout-next-b", "scout-future-a"], "game_session: EV06 did not record the next three deterministic route nodes")
		var scouted_intel: Dictionary = scout_session.route_intel().get("nodes", {})
		check(scouted_ids.all(func(id: String) -> bool: return bool(scouted_intel.get(id, {}).get("revealed", false)) and bool(scouted_intel.get(id, {}).get("scouted", false))), "game_session: EV06 scan did not reveal its nodes to the route map/autopilot")
		var scout_reload: GameSession = GameSession.new()
		scout_reload.configure_save_directory("user://test-saves/event-route-scouting")
		check(scout_reload.load_saved_game() and scout_reload.state.run.scouted_node_ids == scouted_ids, "game_session: event-scanned node knowledge did not persist across reload")
		var mutation_payload: Dictionary = event_session.state.to_payload()
		mutation_payload["run"]["graph"] = {"layers": [[{"id": "mutation-test", "layer": 0, "type": "EVENT", "eventId": "EV22", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "mutation-test", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		mutation_payload["run"]["currentNodeId"] = "START"
		mutation_payload["run"]["phase"] = "ROUTE"
		check(event_session._commit_payload(mutation_payload), "game_session: could not install mutation event fixture")
		check(event_session.travel_to("mutation-test"), "game_session: mutation event travel failed")
		check(event_session.resolve_event("A"), "game_session: temporary mutation event failed: %s" % event_session.last_error)
		check(event_session.state.run.temporary_mutation_ids == ["MUT_REGEN"], "game_session: event mutation did not enter the temporary run build")
	return failure_count == 0
