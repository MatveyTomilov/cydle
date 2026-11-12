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
	check(not session.combat_notice.is_empty(), "game_session: omitted reaction rules were not disclosed")
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
