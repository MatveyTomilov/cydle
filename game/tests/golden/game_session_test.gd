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
		check(attribute_session.start_expedition("attribute-lock-test"), "game_session: attribute test expedition failed to start")
		check(not attribute_session.allocate_attribute("REF") and int(attribute_session.state.meta.operator.attributes.get("REF", 0)) == 5, "game_session: attribute allocation was allowed during an active expedition")
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
