extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var terminal_build_session: GameSession = GameSession.new()
	terminal_build_session.configure_save_directory("user://test-saves/terminal-build-history")
	if check(terminal_build_session.start_new_game(1762900000048), "game_session: could not create a terminal-build regression profile") and check(terminal_build_session.start_expedition("terminal-build-history"), "game_session: could not start terminal-build regression sortie"):
		var item_catalog: ItemCatalog = ItemCatalog.new()
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed("terminal-build-history", "energy-main")
		var catalog_result: Dictionary = item_catalog.load_catalog()
		var energy_result: Dictionary = ItemFactory.new().create_item(rng, item_catalog, {"templateId": "LASER_E3", "techLevel": 1, "rarity": "COMMON", "secured": true, "originGrantId": "terminal-build-history:laser", "origin": "test", "acquiredAt": 0})
		if check(bool(catalog_result.get("ok", false)) and bool(energy_result.get("ok", false)), "game_session: could not create an energy weapon for terminal-build regression: %s" % energy_result):
			var energy_item: ItemInstance = energy_result["item"] as ItemInstance
			var invalid_live_payload: Dictionary = terminal_build_session.state.to_payload()
			invalid_live_payload["meta"]["inventory"].append(energy_item.to_dictionary())
			invalid_live_payload["run"]["equipment"]["MAIN"] = energy_item.item_id
			check(not bool(GameSaveSchema.new().validate_payload(invalid_live_payload).get("ok", false)), "game_session: a live field build accepted kinetic skills on an energy weapon")
			invalid_live_payload["run"]["phase"] = "DEFEATED"
			check(terminal_build_session._commit_payload(invalid_live_payload), "game_session: a terminal field loadout blocked later garage builds: %s" % terminal_build_session.last_error)
			var terminal_reload: GameSession = GameSession.new()
			terminal_reload.configure_save_directory("user://test-saves/terminal-build-history")
			check(terminal_reload.load_saved_game() and terminal_reload.state.run.phase == "DEFEATED", "game_session: terminal history did not reload after a garage build change")

	var e09_session: GameSession = GameSession.new()
	e09_session.configure_save_directory("user://test-saves/e09-solo-integration")
	if check(e09_session.start_new_game(1762900000047), "game_session: could not create an E09 integration profile") and check(e09_session.start_expedition("e09-solo-integration"), "game_session: could not start E09 integration sortie"):
		var e09_payload: Dictionary = e09_session.state.to_payload()
		e09_payload["run"]["graph"] = {"layers": [[{"id": "e09-solo", "layer": 0, "type": "COMBAT", "threat": "medium", "enemies": [{"templateId": "E09"}], "revealLevel": 1, "lootHint": "combat"}]], "edges": [{"from": "START", "to": "e09-solo", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		check(e09_session._commit_payload(e09_payload) and e09_session.travel_to("e09-solo") and e09_session.begin_combat(), "game_session: E09 solo encounter could not start: %s" % e09_session.last_error)
		var e09_ticks: int = 0
		while e09_session.combat_state() != null and e09_session.combat_state().outcome.is_empty() and e09_ticks < 900:
			if not e09_session.advance_combat_step():
				break
			e09_ticks += 1
		var e09_state: CombatState = e09_session.combat_state()
		var e09_hp: float = -1.0
		if e09_state != null and not e09_state.enemies.is_empty(): e09_hp = e09_state.enemies[0].hp
		check(e09_state != null and e09_state.outcome == "VICTORY" and e09_ticks < 900, "game_session: solo E09 fight stalled at %d ticks, HP %.1f, metrics %s" % [e09_ticks, e09_hp, str(e09_state.metrics if e09_state != null else {})])

	var sortie_fuel_session: GameSession = GameSession.new()
	sortie_fuel_session.configure_save_directory("user://test-saves/sortie-fuel")
	if check(sortie_fuel_session.start_new_game(1762900000049), "game_session: could not create a sortie fuel profile"):
		sortie_fuel_session.state.meta.transport.fuel = 3.0
		check(sortie_fuel_session.start_expedition("sortie-refill-test"), "game_session: sortie could not start from a depleted garage tank: %s" % sortie_fuel_session.last_error)
		check(is_equal_approx(float(sortie_fuel_session.state.run.resources.get("fuel", 0.0)), sortie_fuel_session.state.meta.transport.fuel_max), "game_session: a new sortie did not leave with a full transport tank")

	var sector_progress_session: GameSession = GameSession.new()
	sector_progress_session.configure_save_directory("user://test-saves/sector-progress")
	if check(sector_progress_session.start_new_game(17629000000491), "game_session: could not create a sector progression profile"):
		var progression_payload: Dictionary = sector_progress_session.state.to_payload()
		progression_payload["meta"]["unlockedForpost"] = 4
		progression_payload["meta"]["maxSectorCleared"] = 4
		check(sector_progress_session._commit_payload(progression_payload), "game_session: sector progression fixture could not be saved")
		check(sector_progress_session.start_expedition("sector-six-clear"), "game_session: sector progression sortie could not start")
		sector_progress_session.state.run.depth = 6
		sector_progress_session.state.run.phase = "CHECKPOINT"
		check(sector_progress_session.continue_campaign(), "game_session: checkpoint continuation failed to clear its completed depth")
		check(sector_progress_session.state.run.depth == 7 and sector_progress_session.state.meta.max_sector_cleared == 6, "game_session: advancing past d6 did not persist the sector-clear milestone")
		sector_progress_session.state.run.phase = "EXTRACTED"
		check(bool(sector_progress_session.garage_upgrade_quote("HANGAR").get("valid", false)), "game_session: clearing d6 did not unlock the authored HANGAR L2 gate")

	var autopilot_session: GameSession = GameSession.new()
	autopilot_session.configure_save_directory("user://test-saves/autopilot")
	if check(autopilot_session.start_new_game(1762900000050), "game_session: could not create an autopilot profile"):
		check(autopilot_session.state.meta.autopilot_profiles.size() == 3 and autopilot_session.active_autopilot_profile_id() == "BALANCED", "game_session: new profiles do not include the three authored pilot presets")
		var old_pilot_payload: Dictionary = autopilot_session.state.to_payload()
		old_pilot_payload["meta"]["autopilotProfiles"] = [{"id": "BALANCED", "name": "Сбалансированный", "startDepth": 1, "enabled": false}]
		old_pilot_payload["meta"].erase("activeAutopilotProfileId")
		check(autopilot_session._commit_payload(old_pilot_payload) and autopilot_session.active_autopilot_profile_id() == "BALANCED", "game_session: legacy single-profile save did not retain the balanced default")
		check(autopilot_session.set_active_autopilot_profile("CAUTIOUS") and autopilot_session.active_autopilot_profile_id() == "CAUTIOUS" and autopilot_session.state.meta.autopilot_profiles.size() == 3, "game_session: legacy garage did not migrate and persist the selected preset")
		var selected_pilot: GameSession = GameSession.new()
		selected_pilot.configure_save_directory("user://test-saves/autopilot")
		check(selected_pilot.load_saved_game() and selected_pilot.active_autopilot_profile_id() == "CAUTIOUS", "game_session: selected autopilot preset did not survive save reload")
		check(autopilot_session.start_expedition("autopilot-fixed-seed"), "game_session: autopilot expedition could not start")
		check(not autopilot_session.set_active_autopilot_profile("AGGRESSIVE"), "game_session: active outing allowed changing its risk policy mid-run")
		var pilot_policy: AutopilotPolicy = AutopilotPolicy.new()
		var policy_run: GameSaveState.RunState = GameSaveState.RunState.new()
		var elite_choice: Array[Dictionary] = [{"id": "elite", "layer": 0, "type": "ELITE"}]
		var elite_intel: Dictionary = {"nodes": {"elite": {"revealed": true, "type": "ELITE", "threat": "high", "lootHint": "elite"}}}
		check(pilot_policy.choose_node(elite_choice, elite_intel, policy_run, 4.0, "CAUTIOUS").is_empty(), "game_session: cautious preset selected a disallowed elite")
		check(str(pilot_policy.choose_node(elite_choice, elite_intel, policy_run, 4.0, "AGGRESSIVE").get("id", "")) == "elite", "game_session: aggressive preset failed to select its allowed elite route")
		var disclosed_choices: Array[Dictionary] = [{"id": "cache", "type": "CACHE"}, {"id": "hidden-elite", "type": "ELITE"}]
		var disclosed_intel: Dictionary = {"nodes": {"cache": {"revealed": true, "type": "CACHE", "threat": "low", "lootHint": "три прототипа"}, "hidden-elite": {"revealed": false}}}
		check(str(pilot_policy.choose_node(disclosed_choices, disclosed_intel, policy_run, 4.0, "BALANCED").get("id", "")) == "cache", "game_session: route policy leaked a hidden node's type or ignored its disclosed loot hint")
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
		check(offline_resumed.state.meta.autopilot_report_history.size() == 2 and str(offline_resumed.state.meta.autopilot_report_history.back().get("reasonCode", "")) == str(autopilot_report.get("reasonCode", "")), "game_session: offline and interactive autopilot reports were not persisted in order")
		var report_history_reload: GameSession = GameSession.new()
		report_history_reload.configure_save_directory("user://test-saves/autopilot")
		check(report_history_reload.load_saved_game() and report_history_reload.state.meta.autopilot_report_history.size() == 2, "game_session: autopilot report history did not survive save reload")
	var mutation_pilot_session: GameSession = GameSession.new()
	mutation_pilot_session.configure_save_directory("user://test-saves/autopilot-mutation-choice")
	if check(mutation_pilot_session.start_new_game(1762900000052), "game_session: could not create an autopilot mutation-choice profile"):
		var mutation_profile: Dictionary = AutopilotPolicy.profile("BALANCED")
		mutation_profile.erase("id")
		mutation_profile.erase("name")
		mutation_profile["preferMutations"] = ["MUT_REGEN"]
		check(mutation_pilot_session.save_autopilot_profile_settings("BALANCED", mutation_profile), "game_session: could not save preferred mutation policy: %s" % mutation_pilot_session.last_error)
		if check(mutation_pilot_session.start_expedition("autopilot-mutation-choice"), "game_session: mutation-choice sortie failed to start"):
			var mutation_event_payload: Dictionary = mutation_pilot_session.state.to_payload()
			mutation_event_payload["run"]["graph"] = {"layers": [[{"id": "mutation-auto-choice", "layer": 0, "type": "EVENT", "eventId": "EV22", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "mutation-auto-choice", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
			mutation_event_payload["run"]["currentNodeId"] = "mutation-auto-choice"
			mutation_event_payload["run"]["phase"] = "NODE"
			check(mutation_pilot_session._commit_payload(mutation_event_payload), "game_session: could not prepare the preferred mutation event: %s" % mutation_pilot_session.last_error)
			var mutation_pilot_report: Dictionary = mutation_pilot_session.simulate_autopilot(20000)
			check(not mutation_pilot_report.is_empty() and mutation_pilot_session.state.meta.reputation.get("F_CHOIR", 0) == 4 and mutation_pilot_session.state.run.temporary_mutation_ids.has("MUT_REGEN"), "game_session: autopilot did not choose its explicitly preferred event mutation: %s" % mutation_pilot_report)
	var repair_budget_session: GameSession = GameSession.new()
	repair_budget_session.configure_save_directory("user://test-saves/autopilot-repair-budget")
	if check(repair_budget_session.start_new_game(1762900000053), "game_session: could not create an autopilot repair-budget profile"):
		var repair_policy: Dictionary = AutopilotPolicy.profile("BALANCED")
		repair_policy.erase("id")
		repair_policy.erase("name")
		repair_policy["maxSpendRepair"] = 0.0
		check(repair_budget_session.save_autopilot_profile_settings("BALANCED", repair_policy) and repair_budget_session.start_expedition("autopilot-repair-budget"), "game_session: could not prepare the zero repair budget profile: %s" % repair_budget_session.last_error)
		var repair_node_payload: Dictionary = repair_budget_session.state.to_payload()
		repair_node_payload["run"]["graph"] = {"layers": [[{"id": "budget-repair", "layer": 0, "type": "REPAIR", "threat": "low", "enemies": [], "revealLevel": 1, "lootHint": "repair"}]], "edges": []}
		repair_node_payload["run"]["currentNodeId"] = "budget-repair"
		repair_node_payload["run"]["phase"] = "NODE"
		repair_node_payload["run"]["resources"]["hull"] = 50.0
		repair_node_payload["run"]["runWallet"]["CREDITS"] = 100.0
		check(repair_budget_session._commit_payload(repair_node_payload), "game_session: could not prepare the paid repair node: %s" % repair_budget_session.last_error)
		var repair_stop: Dictionary = repair_budget_session.simulate_autopilot(60000)
		check(str(repair_stop.get("reasonCode", "")) == "REPAIR_UNAVAILABLE" and is_equal_approx(repair_budget_session.state.run.wallet.credits, 100.0) and is_zero_approx(repair_budget_session.state.run.resources.hull - 50.0), "game_session: autopilot exceeded its explicit repair-spend limit: %s" % repair_stop)
	var restart_session: GameSession = GameSession.new()
	restart_session.configure_save_directory("user://test-saves/autopilot-restart")
	if check(restart_session.start_new_game(1762900000054), "game_session: could not create an auto-restart profile"):
		var restart_policy: Dictionary = AutopilotPolicy.profile("BALANCED")
		restart_policy.erase("id")
		restart_policy.erase("name")
		restart_policy["checkpointAction"] = "EXTRACT"
		restart_policy["autoRestartAllowed"] = true
		restart_policy["maxRuns"] = 2
		check(restart_session.save_autopilot_profile_settings("BALANCED", restart_policy) and restart_session.start_expedition("autopilot-restart-first"), "game_session: could not configure the bounded auto-restart policy: %s" % restart_session.last_error)
		var restart_checkpoint: Dictionary = restart_session.state.to_payload()
		restart_checkpoint["run"]["phase"] = "CHECKPOINT"
		restart_checkpoint["run"]["autopilotEnabled"] = true
		check(restart_session._commit_payload(restart_checkpoint), "game_session: could not prepare the restart checkpoint: %s" % restart_session.last_error)
		var restart_report: Dictionary = restart_session.simulate_autopilot(1000)
		check(restart_session.state.run.autopilot_run_count == 2 and restart_session.state.run.phase == "ROUTE" and str(restart_report.get("reasonCode", "")) == "TIME_BUDGET", "game_session: opted-in auto-restart did not begin exactly one bounded follow-up outing: %s" % restart_report)
		var restart_reload: GameSession = GameSession.new()
		restart_reload.configure_save_directory("user://test-saves/autopilot-restart")
		check(restart_reload.load_saved_game() and restart_reload.state.run.autopilot_run_count == 2, "game_session: auto-restart count did not persist across save reload")
		var final_restart_checkpoint: Dictionary = restart_reload.state.to_payload()
		final_restart_checkpoint["run"]["phase"] = "CHECKPOINT"
		check(restart_reload._commit_payload(final_restart_checkpoint), "game_session: could not prepare the max-runs checkpoint")
		var max_runs_report: Dictionary = restart_reload.simulate_autopilot(1000)
		check(restart_reload.state.run.autopilot_run_count == 2 and restart_reload.state.run.phase == "EXTRACTED" and str(max_runs_report.get("reasonCode", "")) == "MAX_RUNS", "game_session: autopilot started another outing after reaching maxRuns: %s" % max_runs_report)
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
		var escort_offer: Dictionary = offers.filter(func(offer: Dictionary) -> bool: return str(offer.get("id", "")) == "CT_ESCORT")[0]
		var escort_faction: String = str(escort_offer.get("factionId", ""))
		check(["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(escort_faction) and int(escort_offer.get("rewardReputation", {}).get(escort_faction, 0)) == 8, "game_session: ESCORT offer did not select and disclose its faction reputation reward")
		check(str(offers[0].get("eventId", "")) == "contract-offer:1:%s" % str(offers[0].get("id", "")), "game_session: generated offer did not retain its world event identifier")
		check(contract_session.start_expedition("contract-fixed-seed", false, "CT_HUNT"), "game_session: HUNT contract failed to start: %s" % contract_session.last_error)
		if contract_session.state.run != null:
			var contract: Dictionary = contract_session.state.run.contract
			check(str(contract.get("status", "")) == "ACTIVE" and not str(contract.get("targetNodeId", "")).is_empty() and str(contract.get("eventId", "")) == "contract-offer:1:CT_HUNT", "game_session: HUNT contract did not retain its active objective and world event")
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
	var escort_session: GameSession = GameSession.new()
	escort_session.configure_save_directory("user://test-saves/contracts-escort-faction")
	if check(escort_session.start_new_game(1762900000107), "game_session: could not create a faction ESCORT profile"):
		var expected_escort_faction: String = str(escort_session.available_contract_offers().filter(func(offer: Dictionary) -> bool: return str(offer.get("id", "")) == "CT_ESCORT")[0].get("factionId", ""))
		if check(escort_session.start_expedition("escort-faction-contract", false, "CT_ESCORT"), "game_session: faction ESCORT contract did not start: %s" % escort_session.last_error):
			check(str(escort_session.state.run.contract.get("factionId", "")) == expected_escort_faction and int(escort_session.state.run.contract.get("rewardReputation", {}).get(expected_escort_faction, 0)) == 8, "game_session: accepted ESCORT instance lost its themed faction reward")
	var favored_session: GameSession = GameSession.new()
	favored_session.configure_save_directory("user://test-saves/faction-threshold-contract")
	if check(favored_session.start_new_game(1762900000108), "game_session: could not create a favored faction profile"):
		var favored_payload: Dictionary = favored_session.state.to_payload()
		favored_payload["meta"]["reputation"]["F_CHOIR"] = 60
		check(favored_session._commit_payload(favored_payload), "game_session: could not set favored faction reputation")
		var favored_offer: Dictionary = favored_session.available_contract_offers().filter(func(offer: Dictionary) -> bool: return str(offer.get("id", "")) == "CT_FACTION_F_CHOIR")[0]
		check(str(favored_offer.get("factionId", "")) == "F_CHOIR" and int(favored_offer.get("rewardReputation", {}).get("F_CHOIR", 0)) == 8, "game_session: +60 reputation did not unlock its thematic contract")
		if check(favored_session.start_expedition("faction-hunt-contract", false, "CT_FACTION_F_CHOIR"), "game_session: thematic faction hunt was rejected: %s" % favored_session.last_error):
			check(str(favored_session.state.run.contract.get("factionId", "")) == "F_CHOIR" and str(favored_session.state.run.contract.get("kind", "")) == "HUNT", "game_session: accepted thematic contract lost its faction target")
	var hostile_session: GameSession = GameSession.new()
	hostile_session.configure_save_directory("user://test-saves/faction-hostile-bounty")
	if check(hostile_session.start_new_game(1762900000109), "game_session: could not create a hostile faction profile"):
		var hostile_payload: Dictionary = hostile_session.state.to_payload()
		hostile_payload["meta"]["reputation"]["F_ECHO"] = -60
		check(hostile_session._commit_payload(hostile_payload), "game_session: could not set hostile faction reputation")
		if check(hostile_session.start_expedition("faction-hostile-route"), "game_session: hostile faction route could not start: %s" % hostile_session.last_error):
			var themed_bounty_found: bool = false
			for layer: Array in hostile_session.state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "BOUNTY" and str(node.get("factionId", "")) == "F_ECHO" and bool(node.get("factionBounty", false)): themed_bounty_found = true
			check(themed_bounty_found, "game_session: -60 faction reputation did not add a themed bounty to the route")
	var wanted_start_session: GameSession = GameSession.new()
	wanted_start_session.configure_save_directory("user://test-saves/vanta-start-wanted")
	if check(wanted_start_session.start_new_game(1762900000112), "game_session: could not create a VANTA pressure profile"):
		var wanted_start_payload: Dictionary = wanted_start_session.state.to_payload()
		wanted_start_payload["meta"]["reputation"]["F_VANTA"] = -61
		check(wanted_start_session._commit_payload(wanted_start_payload), "game_session: could not set VANTA hostility")
		if check(wanted_start_session.start_expedition("vanta-start-wanted"), "game_session: VANTA hostility expedition could not start: %s" % wanted_start_session.last_error):
			check(is_equal_approx(wanted_start_session.state.run.wanted, 10.0), "game_session: VANTA reputation below -60 did not add 10 starting wanted")
	var wanted_elite_session: GameSession = GameSession.new()
	wanted_elite_session.configure_save_directory("user://test-saves/high-wanted-elite")
	if check(wanted_elite_session.start_new_game(1762900000113), "game_session: could not create a high wanted profile"):
		if check(wanted_elite_session.start_expedition("high-wanted-elite"), "game_session: high wanted route could not start: %s" % wanted_elite_session.last_error):
			var wanted_route: Array[Dictionary] = wanted_elite_session.reachable_nodes()
			if not wanted_route.is_empty() and check(wanted_elite_session.travel_to(str(wanted_route[0].get("id", ""))), "game_session: high wanted route could not enter combat"):
				var wanted_payload: Dictionary = wanted_elite_session.state.to_payload()
				wanted_payload["run"]["wanted"] = 80.0
				check(wanted_elite_session._commit_payload(wanted_payload), "game_session: could not prepare high wanted combat")
				if check(wanted_elite_session.begin_combat(), "game_session: high wanted combat failed to initialize: %s" % wanted_elite_session.last_error):
					var all_high_wanted_elite: bool = not wanted_elite_session.combat_state().enemies.is_empty()
					for enemy: CombatActorState in wanted_elite_session.combat_state().enemies:
						all_high_wanted_elite = all_high_wanted_elite and not enemy.elite_mod.is_empty()
					check(all_high_wanted_elite, "game_session: 80+ wanted did not add a catalogued elite modifier to each ordinary enemy")
	var shop_session: GameSession = GameSession.new()
	shop_session.configure_save_directory("user://test-saves/faction-shop-discount")
	if check(shop_session.start_new_game(1762900000111), "game_session: could not create a faction shop profile"):
		if check(shop_session.start_expedition("faction-shop-discount"), "game_session: faction shop route could not start: %s" % shop_session.last_error):
			var shop_node_id: String = ""
			var shop_faction: String = ""
			var shop_payload: Dictionary = shop_session.state.to_payload()
			for layer: Array in shop_payload["run"]["graph"].get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "SHOP":
						shop_node_id = str(node.get("id", ""))
						shop_faction = shop_session._world_faction("faction-shop-discount", shop_node_id)
			shop_payload["meta"]["reputation"][shop_faction] = 60
			shop_payload["run"]["phase"] = "NODE"
			shop_payload["run"]["currentNodeId"] = shop_node_id
			if check(shop_session._commit_payload(shop_payload), "game_session: could not prepare faction shop visit"):
				var discounted_offers: Array[Dictionary] = shop_session.shop_offers()
				check(not discounted_offers.is_empty() and int(discounted_offers[0].get("discountPercent", 0)) == 15 and int(discounted_offers[0].get("price", 0)) < int(discounted_offers[0].get("basePrice", 0)), "game_session: +60 faction standing did not reduce themed shop prices")
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
			check(str(signal_contract.get("kind", "")) == "SIGNAL" and str(signal_contract.get("targetUniqueId", "")) == "U09" and not str(signal_contract.get("targetNodeId", "")).is_empty() and str(signal_contract.get("eventId", "")) == "contract-offer:5:SIGNAL_U09", "game_session: signal contract did not create a targeted elite encounter tied to its world event")
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
	var escalation_session: GameSession = GameSession.new()
	escalation_session.configure_save_directory("user://test-saves/endgame-escalations")
	if check(escalation_session.start_new_game(1762900000115), "game_session: could not create an endgame escalation profile"):
		var endgame_unlock: Dictionary = escalation_session.state.to_payload()
		endgame_unlock["meta"]["unlockedForpost"] = 12
		endgame_unlock["meta"]["campaignFlags"].append_array(["ENDGAME_UNLOCKED", "ENDING_SELECTED", "ENDING_FACTION:F_CHOIR"])
		check(escalation_session._commit_payload(endgame_unlock), "game_session: could not unlock test endgame depth")
		var endgame_escort: Dictionary = escalation_session.available_contract_offers().filter(func(offer: Dictionary) -> bool: return str(offer.get("id", "")) == "CT_ESCORT")[0]
		check(str(endgame_escort.get("factionId", "")) == "F_CHOIR", "game_session: faction-control ending did not theme endgame ESCORTs to the controlling faction")
		var exclusive_offer: Dictionary = escalation_session.available_contract_offers().filter(func(offer: Dictionary) -> bool: return str(offer.get("id", "")) == "CT_CONTROL_F_CHOIR")[0]
		check(str(exclusive_offer.get("factionId", "")) == "F_CHOIR" and str(exclusive_offer.get("rewardItem", {}).get("tag", "")) == "digital", "game_session: faction-control ending did not expose its exclusive themed HUNT contract")
		var escalation_ids: Array[String] = ["REPAIR_RARE", "SCAN_DARK", "LONG_RUN"]
		check(not escalation_session.start_expedition("endgame-escalation-seed", false, "", ["WANTED_PLUS", "HUNT_FAST", "REPAIR_RARE", "SCAN_DARK"]), "game_session: more than three escalations were accepted")
		if check(escalation_session.start_expedition("endgame-escalation-seed", false, "CT_CONTROL_F_CHOIR", escalation_ids), "game_session: selected endgame escalations were rejected: %s" % escalation_session.last_error):
			check(escalation_session.state.run.depth == 13 and escalation_session.state.run.escalation_ids == escalation_ids, "game_session: endgame escalation selection did not persist on RUN")
			check(str(escalation_session.state.run.contract.get("factionId", "")) == "F_CHOIR" and str(escalation_session.state.run.contract.get("kind", "")) == "HUNT", "game_session: accepted exclusive endgame contract lost its faction target")
			var escalation_round_trip: Dictionary = GameSaveState.new().parse_payload(escalation_session.state.to_payload())
			check(bool(escalation_round_trip.get("ok", false)) and escalation_round_trip["state"].run.escalation_ids == escalation_ids, "game_session: endgame escalation state did not survive save validation")
			var normal_route: Dictionary = SectorGenerator.new().generate("endgame-escalation-seed", 13, escalation_session.state.run.biome)
			var normal_repairs: int = 0
			var reduced_repairs: int = 0
			for layer: Array in normal_route.get("graph", {}).get("layers", []):
				for candidate: Dictionary in layer:
					if str(candidate.get("type", "")) == "REPAIR": normal_repairs += 1
			for layer: Array in escalation_session.state.run.graph.get("layers", []):
				for candidate: Dictionary in layer:
					if str(candidate.get("type", "")) == "REPAIR": reduced_repairs += 1
			check(reduced_repairs == normal_repairs - 1 if normal_repairs > 0 else reduced_repairs == 0, "game_session: REPAIR_RARE did not replace one repair node while preserving route connectivity")
			var intel_after_dark: int = int(escalation_session.route_intel().get("effectiveLevel", -1))
			var expected_intel: int = maxi(0, escalation_session.garage_level("INTEL") - (1 if escalation_session.state.run.biome == "B06" else 0) - 1)
			check(intel_after_dark == expected_intel, "game_session: SCAN_DARK did not lower disclosed intel")
			var start_time: float = float(escalation_session.state.run.resources.get("gameTimeMs", 0.0))
			var route_choices: Array[Dictionary] = escalation_session.reachable_nodes()
			if not route_choices.is_empty():
				var destination: Dictionary = route_choices[0]
				check(escalation_session.travel_to(str(destination.get("id", ""))), "game_session: LONG_RUN route transition failed: %s" % escalation_session.last_error)
				var expected_time: float = 40000.0 + (8000.0 if str(destination.get("type", "")) == "CHECKPOINT" else 0.0)
				check(is_equal_approx(float(escalation_session.state.run.resources.get("gameTimeMs", 0.0)) - start_time, expected_time), "game_session: LONG_RUN did not add fifteen seconds to route travel")
	var checkpoint_repair_session: GameSession = GameSession.new()
	checkpoint_repair_session.configure_save_directory("user://test-saves/checkpoint-service-upgrade")
	if check(checkpoint_repair_session.start_new_game(1762900000117), "game_session: could not create a checkpoint repair profile") and check(checkpoint_repair_session.start_expedition("checkpoint-service-upgrade"), "game_session: checkpoint repair test run did not start"):
		var repair_setup: Dictionary = checkpoint_repair_session.state.to_payload()
		repair_setup["run"]["phase"] = "CHECKPOINT"
		repair_setup["run"]["resources"]["hull"] = 50.0
		repair_setup["run"]["runWallet"]["CREDITS"] = 100.0
		check(checkpoint_repair_session._commit_payload(repair_setup), "game_session: could not prepare checkpoint repair resources")
		check(is_equal_approx(float(checkpoint_repair_session.checkpoint_repair_quote().get("repair", 0.0)), 30.0), "game_session: base checkpoint repair amount was not 30 hull")
		var service_upgrade: Dictionary = checkpoint_repair_session.state.to_payload()
		service_upgrade["meta"]["campaignFlags"].append("quest-service-upgrade")
		check(checkpoint_repair_session._commit_payload(service_upgrade), "game_session: could not activate Q03 service upgrade")
		var upgraded_quote: Dictionary = checkpoint_repair_session.checkpoint_repair_quote()
		check(is_equal_approx(float(upgraded_quote.get("repair", 0.0)), 34.5), "game_session: Q03 service upgrade did not increase checkpoint repair by 15 percent")
		var credits_before_repair: float = checkpoint_repair_session.state.run.wallet.credits
		check(checkpoint_repair_session.repair_checkpoint_hull(), "game_session: checkpoint hull repair failed: %s" % checkpoint_repair_session.last_error)
		check(is_equal_approx(checkpoint_repair_session.state.run.resources["hull"], 84.5) and checkpoint_repair_session.state.run.wallet.credits < credits_before_repair, "game_session: checkpoint repair did not apply its upgrade and cost")
	var checkpoint_ship_session: GameSession = GameSession.new()
	checkpoint_ship_session.configure_save_directory("user://test-saves/checkpoint-shipping")
	if check(checkpoint_ship_session.start_new_game(1762900000118), "game_session: could not create a checkpoint cargo profile") and check(checkpoint_ship_session.start_expedition("checkpoint-shipping"), "game_session: could not start checkpoint cargo sortie"):
		var ship_catalog: ItemCatalog = ItemCatalog.new()
		var ship_rng: DeterministicRng = DeterministicRng.new()
		ship_rng.seed("checkpoint-shipping", "secured-armor")
		var ship_catalog_result: Dictionary = ship_catalog.load_catalog()
		var shipped_item_result: Dictionary = ItemFactory.new().create_item(ship_rng, ship_catalog, {"templateId": "ARM_HEAVY", "techLevel": 1, "rarity": "COMMON", "secured": false, "originGrantId": "checkpoint-shipping:armor", "origin": "test", "acquiredAt": 0})
		if check(bool(ship_catalog_result.get("ok", false)) and bool(shipped_item_result.get("ok", false)), "game_session: could not create checkpoint shipment cargo: %s" % shipped_item_result):
			var shipped_item: ItemInstance = shipped_item_result["item"] as ItemInstance
			var shipping_payload: Dictionary = checkpoint_ship_session.state.to_payload()
			shipping_payload["run"]["phase"] = "CHECKPOINT"
			shipping_payload["run"]["currentNodeId"] = "boss-clear-d1"
			shipping_payload["run"]["unsecuredCargo"].append(shipped_item.to_dictionary())
			shipping_payload["run"]["runWallet"] = {"CREDITS": 100.0, "SCRAP": 40.0, "DATA": 20.0}
			check(checkpoint_ship_session._commit_payload(shipping_payload), "game_session: could not prepare checkpoint cargo shipment: %s" % checkpoint_ship_session.last_error)
			var shipment_ids: Array[String] = [shipped_item.item_id]
			var shipping_quote: Dictionary = checkpoint_ship_session.checkpoint_shipping_quote(shipment_ids, 50)
			check(bool(shipping_quote.get("valid", false)) and bool(shipping_quote.get("affordable", false)) and int(shipping_quote.get("cargoUnits", 0)) == 2 and int(shipping_quote.get("credits", 0)) == 10, "game_session: checkpoint shipment did not quote the authored cargo cap/cost: %s" % shipping_quote)
			var insufficient_fee_payload: Dictionary = checkpoint_ship_session.state.to_payload()
			insufficient_fee_payload["run"]["runWallet"]["CREDITS"] = 18.0
			check(checkpoint_ship_session._commit_payload(insufficient_fee_payload) and not bool(checkpoint_ship_session.checkpoint_shipping_quote(shipment_ids, 50).get("affordable", false)), "game_session: shipment allowed transferring half the credits when fee plus transfer exceeded the wallet")
			check(checkpoint_ship_session._commit_payload(shipping_payload), "game_session: could not restore the affordable checkpoint shipping fixture")
			var protected_credits_before: float = checkpoint_ship_session.state.meta.protected_bank.credits
			var protected_scrap_before: float = checkpoint_ship_session.state.meta.protected_bank.scrap
			var protected_data_before: float = checkpoint_ship_session.state.meta.protected_bank.data
			check(checkpoint_ship_session.ship_checkpoint_cargo(shipment_ids, 50), "game_session: checkpoint shipment failed: %s" % checkpoint_ship_session.last_error)
			check(checkpoint_ship_session.state.run.unsecured_cargo.is_empty() and checkpoint_ship_session.state.meta.inventory.any(func(item: Dictionary) -> bool: return str(item.get("itemId", "")) == shipped_item.item_id and bool(item.get("secured", false))), "game_session: checkpoint shipment did not secure cargo into the permanent inventory")
			check(is_equal_approx(checkpoint_ship_session.state.meta.protected_bank.credits, protected_credits_before + 50.0) and is_equal_approx(checkpoint_ship_session.state.meta.protected_bank.scrap, protected_scrap_before + 20.0) and is_equal_approx(checkpoint_ship_session.state.meta.protected_bank.data, protected_data_before + 10.0), "game_session: shipment did not bank the selected maximum half of run currency")
			check(is_equal_approx(checkpoint_ship_session.state.run.wallet.credits, 40.0) and is_equal_approx(checkpoint_ship_session.state.run.wallet.scrap, 20.0) and is_equal_approx(checkpoint_ship_session.state.run.wallet.data, 10.0), "game_session: shipment failed to charge the fee and deduct banked currency")
			check(not checkpoint_ship_session.ship_checkpoint_cargo(shipment_ids, 50), "game_session: checkpoint shipment could be repeated to duplicate banked value")
			var autopilot_ship_session: GameSession = GameSession.new()
			autopilot_ship_session.configure_save_directory("user://test-saves/checkpoint-autopilot-shipping")
			if check(autopilot_ship_session.start_new_game(1762900000119), "game_session: could not create an autopilot checkpoint shipping profile") and check(autopilot_ship_session.start_expedition("checkpoint-autopilot-shipping"), "game_session: could not start autopilot checkpoint shipping sortie"):
				var autopilot_shipping_payload: Dictionary = autopilot_ship_session.state.to_payload()
				autopilot_shipping_payload["run"]["phase"] = "CHECKPOINT"
				autopilot_shipping_payload["run"]["currentNodeId"] = "balanced-boss-clear"
				autopilot_shipping_payload["run"]["unsecuredCargo"].append(shipped_item.to_dictionary())
				autopilot_shipping_payload["run"]["runWallet"] = {"CREDITS": 200.0, "SCRAP": 40.0, "DATA": 20.0}
				check(autopilot_ship_session._commit_payload(autopilot_shipping_payload), "game_session: could not prepare autopilot checkpoint cargo: %s" % autopilot_ship_session.last_error)
				var autopilot_shipping_report: Dictionary = autopilot_ship_session.simulate_autopilot(1000)
				check(not autopilot_shipping_report.is_empty() and str(autopilot_shipping_report.get("status", "")) == "OFFLINE_CAPPED", "game_session: balanced pilot did not continue after its checkpoint action: %s" % autopilot_shipping_report)
				check(autopilot_ship_session.state.run.depth == 2 and autopilot_ship_session.state.meta.inventory.any(func(item: Dictionary) -> bool: return str(item.get("itemId", "")) == shipped_item.item_id and bool(item.get("secured", false))), "game_session: balanced pilot did not ship checkpoint cargo before continuing")
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
	var quest_target_session: GameSession = GameSession.new()
	quest_target_session.configure_save_directory("user://test-saves/quest-target-elite")
	if check(quest_target_session.start_new_game(1762900000131), "game_session: could not create a targeted quest profile"):
		var quest_target_payload: Dictionary = quest_target_session.state.to_payload()
		quest_target_payload["meta"]["unlockedForpost"] = 2
		quest_target_payload["meta"]["maxSectorCleared"] = 2
		quest_target_payload["meta"]["reputation"]["F_ECHO"] = -60
		quest_target_payload["meta"]["questProgress"] = {"Q04": {"status": "ACTIVE", "stage": 2, "startedDepth": 2, "stageStartedDepth": 2, "completedStages": ["S1"], "choiceHistory": [{"stage": 1, "choiceId": "A", "nodeId": "D2N1"}], "flags": []}}
		check(quest_target_session._commit_payload(quest_target_payload), "game_session: could not prepare the Q04 elite objective")
		if check(quest_target_session.start_expedition("q04-target-elite"), "game_session: next-sector Q04 expedition failed: %s" % quest_target_session.last_error):
			var q04_target_found: bool = false
			var q04_bounty_found: bool = false
			for layer: Array in quest_target_session.state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "ELITE" and node.get("questTargets", []).has("Q04") and node.get("enemies", []).any(func(enemy: Dictionary) -> bool: return str(enemy.get("templateId", "")) == "E12"): q04_target_found = true
					if str(node.get("type", "")) == "BOUNTY" and str(node.get("factionId", "")) == "F_ECHO" and bool(node.get("factionBounty", false)): q04_bounty_found = true
			check(quest_target_session.state.run.biome == "B02" and q04_target_found and q04_bounty_found, "game_session: faction bounty replaced the active Q04 target or its promised route bounty was missing")
	var rust_quest_target: GameSession = GameSession.new()
	rust_quest_target.configure_save_directory("user://test-saves/q03-target-elite")
	if check(rust_quest_target.start_new_game(1762900000132), "game_session: could not create a Q03 target profile"):
		var rust_payload: Dictionary = rust_quest_target.state.to_payload()
		rust_payload["meta"]["unlockedForpost"] = 1
		rust_payload["meta"]["maxSectorCleared"] = 1
		rust_payload["meta"]["questProgress"] = {"Q03": {"status": "ACTIVE", "stage": 2, "startedDepth": 1, "stageStartedDepth": 1, "completedStages": ["S1"], "choiceHistory": [{"stage": 1, "choiceId": "A", "nodeId": "D1N1"}], "flags": []}}
		check(rust_quest_target._commit_payload(rust_payload), "game_session: could not prepare the Q03 target")
		if check(rust_quest_target.start_expedition("q03-target-elite"), "game_session: Q03 next stage expedition failed: %s" % rust_quest_target.last_error):
			var q03_target_found: bool = false
			for layer: Array in rust_quest_target.state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "ELITE" and node.get("questTargets", []).has("Q03") and node.get("enemies", []).any(func(enemy: Dictionary) -> bool: return str(enemy.get("templateId", "")) == "E09"): q03_target_found = true
			check(rust_quest_target.state.run.biome == "B03" and q03_target_found, "game_session: active Q03 did not create its E09 technician target in B03")
	var thermal_quest_target: GameSession = GameSession.new()
	thermal_quest_target.configure_save_directory("user://test-saves/q05-target-elite")
	if check(thermal_quest_target.start_new_game(1762900000133), "game_session: could not create a Q05 target profile"):
		var thermal_payload: Dictionary = thermal_quest_target.state.to_payload()
		thermal_payload["meta"]["unlockedForpost"] = 6
		thermal_payload["meta"]["maxSectorCleared"] = 6
		thermal_payload["meta"]["questProgress"] = {"Q05": {"status": "ACTIVE", "stage": 2, "startedDepth": 6, "stageStartedDepth": 6, "completedStages": ["S1"], "choiceHistory": [{"stage": 1, "choiceId": "A", "nodeId": "D6N1"}], "flags": []}}
		check(thermal_quest_target._commit_payload(thermal_payload), "game_session: could not prepare the Q05 target")
		if check(thermal_quest_target.start_expedition("q05-target-elite"), "game_session: Q05 target expedition failed: %s" % thermal_quest_target.last_error):
			var q05_target_found: bool = false
			for layer: Array in thermal_quest_target.state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "ELITE" and node.get("questTargets", []).has("Q05") and node.get("enemies", []).any(func(enemy: Dictionary) -> bool: return str(enemy.get("templateId", "")) == "E19"): q05_target_found = true
			check(thermal_quest_target.state.run.biome == "B05" and q05_target_found, "game_session: active Q05 did not create its E19 objective in B05")
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
	battle_payload["run"]["graph"]["layers"][0][0]["factionId"] = "F_VANTA"
	battle_payload["meta"]["reputation"]["F_VANTA"] = -30
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
	var wanted_before_faction_fight: float = session.state.run.wanted
	if session.combat_state() != null and not session.combat_state().outcome.is_empty():
		check(session.resolve_active_combat(), "game_session: combat reward/defeat transaction failed: %s" % session.last_error)
	if session.state.run != null and session.state.run.phase == "ROUTE":
		check(is_equal_approx(session.state.run.wanted, wanted_before_faction_fight + 7.0), "game_session: ordinary VANTA encounter did not add 4 base wanted plus 3 hostile-standing wanted")
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
		check(tactics_session.set_tactic_rule_target("starter-burst", "boss") and tactics_session.set_tactic_rule_target("starter-burst", "healer") and not tactics_session.set_tactic_rule_target("starter-burst", "unknown"), "game_session: tactic target selector validation failed")
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
		var q02_definition: Dictionary = quest_catalog.get_quest("Q02")
		var q02_progress: Dictionary = quest_reload.state.meta.quest_progress.get("Q02", {})
		quest_reload.state.run.biome = "B03"
		quest_reload.state.run.phase = "NODE"
		quest_reload.state.run.current_node_id = "quest-stage-two-event"
		quest_reload.state.run.graph = {"layers": [[{"id": "quest-stage-two-event", "layer": 0, "type": "EVENT", "eventId": "EV03", "enemies": []}]], "edges": []}
		check(not quest_reload._quest_stage_ready(q02_definition, q02_definition["stages"][1], q02_progress), "game_session: Q02 delivery stage was offered in the same sector as the courier pickup")
		quest_reload.state.run.depth += 1
		check(quest_reload._quest_stage_ready(q02_definition, q02_definition["stages"][1], q02_progress), "game_session: Q02 delivery stage did not activate in the next matching sector")
		var q04_definition: Dictionary = quest_catalog.get_quest("Q04")
		var q04_progress: Dictionary = {"stage": 2, "stageStartedDepth": quest_reload.state.run.depth, "startedDepth": quest_reload.state.run.depth, "choiceHistory": []}
		quest_reload.state.run.biome = "B02"
		quest_reload.state.run.current_node_id = "q04-followup-event"
		quest_reload.state.run.graph["layers"] = [[{"id": "q04-followup-event", "layer": 0, "type": "EVENT", "eventId": "EV04", "enemies": []}, {"id": "q04-cleared-elite", "layer": 0, "type": "ELITE", "enemies": [{"templateId": "E12"}]}]]
		quest_reload.state.run.cleared_node_ids.append("q04-cleared-elite")
		check(not quest_reload._quest_stage_ready(q04_definition, q04_definition["stages"][1], q04_progress), "game_session: Q04 elimination objective was available in its source sector")
		quest_reload.state.run.depth += 1
		check(quest_reload._quest_stage_ready(q04_definition, q04_definition["stages"][1], q04_progress), "game_session: Q04 elimination objective did not become available in the next B02 sector")
	var quest_autopilot_session: GameSession = GameSession.new()
	quest_autopilot_session.configure_save_directory("user://test-saves/quest-autopilot-match")
	if check(quest_autopilot_session.start_new_game(1762900000971), "game_session: could not create a named quest-policy profile"):
		var quest_autopilot_meta: Dictionary = quest_autopilot_session.state.to_payload()
		quest_autopilot_meta["meta"]["maxSectorCleared"] = 1
		quest_autopilot_meta["meta"]["unlockedForpost"] = 1
		check(quest_autopilot_session._commit_payload(quest_autopilot_meta), "game_session: could not unlock the named-choice quest fixture")
		var named_quest_policy: Dictionary = AutopilotPolicy.profile("BALANCED")
		named_quest_policy.erase("id")
		named_quest_policy.erase("name")
		named_quest_policy["chooseQuest"] = "MATCH"
		named_quest_policy["questChoiceMap"] = {"Q02:1": "A"}
		check(quest_autopilot_session.save_autopilot_profile_settings("BALANCED", named_quest_policy), "game_session: could not save the explicitly named quest choice: %s" % quest_autopilot_session.last_error)
		check(quest_autopilot_session.accept_quest("Q02") and quest_autopilot_session.start_expedition("named-quest-choice"), "game_session: named-choice quest could not be accepted or started")
		var named_quest_run: Dictionary = quest_autopilot_session.state.to_payload()
		named_quest_run["run"]["biome"] = "B01"
		named_quest_run["run"]["graph"] = {"layers": [[{"id": "named-quest-event", "layer": 0, "type": "EVENT", "eventId": "EV02", "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}]], "edges": [{"from": "START", "to": "named-quest-event", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		check(quest_autopilot_session._commit_payload(named_quest_run) and quest_autopilot_session.travel_to("named-quest-event"), "game_session: named-choice event route could not be prepared: %s" % quest_autopilot_session.last_error)
		var named_quest_report: Dictionary = quest_autopilot_session.simulate_autopilot(60000)
		check(int(quest_autopilot_session.state.meta.quest_progress.get("Q02", {}).get("stage", 0)) == 2 and int(quest_autopilot_session.state.run.wanted) == 5, "game_session: MATCH policy failed to resolve the configured Q02 stage 1 choice: %s" % named_quest_report)
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
	var tow_session: GameSession = GameSession.new()
	tow_session.configure_save_directory("user://test-saves/emergency-tow")
	if check(tow_session.start_new_game(1762900000102), "game_session: could not create an emergency-tow profile") and check(tow_session.start_expedition("emergency-tow"), "game_session: could not start emergency-tow sortie"):
		var tow_catalog: ItemCatalog = ItemCatalog.new()
		var tow_loaded: Dictionary = tow_catalog.load_catalog()
		var tow_payload: Dictionary = tow_session.state.to_payload()
		tow_payload["run"]["resources"]["fuel"] = 0
		tow_payload["run"]["runWallet"] = {"CREDITS": 100.0, "SCRAP": 30.0, "DATA": 10.0}
		var cargo: Array[Dictionary] = []
		for cargo_index: int in range(3):
			var cargo_rng: DeterministicRng = DeterministicRng.new()
			cargo_rng.seed("emergency-tow", "cargo-%d" % cargo_index)
			var created: Dictionary = ItemFactory.new().create_item(cargo_rng, tow_catalog, {"templateId": "ARM_CLOTH", "techLevel": 1, "rarity": "COMMON", "secured": false, "originGrantId": "emergency-tow:cargo:%d" % cargo_index, "origin": "test", "acquiredAt": 0})
			if bool(created.get("ok", false)):
				cargo.append((created["item"] as ItemInstance).to_dictionary())
		check(bool(tow_loaded.get("ok", false)) and cargo.size() == 3, "game_session: tow fixture could not build its unsecured cargo")
		tow_payload["run"]["unsecuredCargo"] = cargo
		check(tow_session._commit_payload(tow_payload), "game_session: tow fixture could not be saved: %s" % tow_session.last_error)
		var tow_quote: Dictionary = tow_session.emergency_exit_quote()
		check(bool(tow_quote.get("valid", false)) and bool(tow_quote.get("towAffordable", false)) and int(tow_quote.get("towCost", 0)) > 0, "game_session: stranded route did not offer the spec-priced tow")
		check(tow_session.call_evacuation_tow(), "game_session: emergency tow failed: %s" % tow_session.last_error)
		check(tow_session.state.run.phase == "TOWED" and tow_session.state.run.unsecured_cargo.is_empty() and tow_session.state.run.wallet.credits == 0.0, "game_session: tow did not end the run and clear temporary cargo/wallet")
		check(tow_session.last_emergency_report.get("cargoSecured", 0) == 2 and not str(tow_session.last_emergency_report.get("droppedItemId", "")).is_empty(), "game_session: tow did not save exactly all but one random item")
		check(tow_session.state.meta.inventory.filter(func(item: Dictionary) -> bool: return str(item.get("origin", "")) == "emergency-tow").size() == 2, "game_session: tow failed to secure the surviving cargo exactly once")
		check(not tow_session.emergency_exit_quote().get("valid", false) and not tow_session.call_evacuation_tow(), "game_session: terminal tow could be awarded repeatedly")
	var abandon_session: GameSession = GameSession.new()
	abandon_session.configure_save_directory("user://test-saves/emergency-abandon")
	if check(abandon_session.start_new_game(1762900000103), "game_session: could not create an abandon-run profile") and check(abandon_session.start_expedition("emergency-abandon"), "game_session: could not start abandon-run sortie"):
		var abandon_payload: Dictionary = abandon_session.state.to_payload()
		abandon_payload["run"]["resources"]["fuel"] = 0
		abandon_payload["run"]["runWallet"] = {"CREDITS": 100.0, "SCRAP": 30.0, "DATA": 10.0}
		var equipped_main_id: String = str(abandon_payload["meta"]["equipment"].get("MAIN", ""))
		check(abandon_session._commit_payload(abandon_payload), "game_session: abandon fixture could not be saved")
		check(bool(abandon_session.emergency_exit_quote().get("valid", false)) and abandon_session.abandon_run(), "game_session: abandoning a stranded sortie failed: %s" % abandon_session.last_error)
		var abandoned_main: Dictionary = abandon_session.state.meta.inventory.filter(func(item: Dictionary) -> bool: return str(item.get("itemId", "")) == equipped_main_id)[0]
		check(abandon_session.state.run.phase == "ABANDONED" and abandon_session.state.run.wallet.credits == 0.0 and abandon_session.state.run.unsecured_cargo.is_empty(), "game_session: abandoned cargo/currency were not lost")
		check(float(abandoned_main.get("durability", 100.0)) == 90.0, "game_session: abandonment did not damage permanent equipped gear by 10 durability")
		check(not abandon_session.abandon_run(), "game_session: abandonment could be settled more than once")
	return failure_count == 0
