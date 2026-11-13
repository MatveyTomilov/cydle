extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var directory: String = "user://test-saves/autobattle-v2-session-%d" % Time.get_ticks_usec()
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.start_new_game(1762900000421), "v2_session: could not create profile"):
		return false
	var loadout: Dictionary = session.state.to_payload()
	var main_id: String = str(loadout["meta"]["equipment"].get("MAIN", ""))
	loadout["meta"]["equipment"] = {"MAIN": main_id}
	loadout["meta"]["skillIds"] = ["SK_PIERCE"]
	if not check(session._commit_payload(loadout), "v2_session: could not install V2-compatible test loadout: %s" % session.last_error):
		return false
	if not check(session.start_expedition("v2-session-seed"), "v2_session: could not start test sortie: %s" % session.last_error):
		return false
	var route_payload: Dictionary = session.state.to_payload()
	route_payload["run"]["graph"] = {"layers": [[{"id": "v2-session-combat", "layer": 0, "type": "COMBAT", "threat": "low", "enemies": [{"templateId": "E01"}], "revealLevel": 1, "lootHint": "combat"}]], "edges": [{"from": "START", "to": "v2-session-combat", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
	if not check(session._commit_payload(route_payload) and session.travel_to("v2-session-combat"), "v2_session: could not enter test combat node: %s" % session.last_error):
		return false
	if not check(session.begin_combat(true), "v2_session: GameSession failed to start V2 from its resolved loadout: %s" % session.last_error):
		return false
	check(session.combat_state().combat_rules_version == CombatState.V2_RULES_VERSION, "v2_session: explicit V2 request silently ran the V1 simulator")
	var first_state: CombatState = session.combat_state()
	var first_step: bool = session.advance_combat_step()
	check(first_step and session.combat_state().action_channel.get("active", {}).get("action", {}).get("skillId", "") == "SK_PIERCE", "v2_session: resolved equipped skill was not prepared by the real GameSession combat path")
	var before_restore_hash: String = StateHash.new().state_hash(session.combat_state().to_dictionary())
	var restored_session: GameSession = GameSession.new()
	restored_session.configure_save_directory(directory)
	check(restored_session.load_saved_game(), "v2_session: GameSession did not restore a V2 snapshot: %s" % restored_session.last_error)
	check(restored_session.combat_state() != null and restored_session.combat_state().combat_rules_version == CombatState.V2_RULES_VERSION and StateHash.new().state_hash(restored_session.combat_state().to_dictionary()) == before_restore_hash, "v2_session: V2 save/reload changed the active channel or combat state")
	var restored: CombatState = restored_session.combat_state()
	var ticks: int = 0
	while restored != null and restored.outcome.is_empty() and ticks < 1200:
		if not restored_session.advance_combat_step(): break
		restored = restored_session.combat_state()
		ticks += 1
	var skill_fired: bool = false
	if restored != null:
		for event: Dictionary in restored.log:
			if str(event.get("kind", "")) == "SKILL_USE" and str(event.get("skillId", "")) == "SK_PIERCE": skill_fired = true
	check(restored != null and restored.outcome == "VICTORY" and ticks < 1200 and skill_fired, "v2_session: integrated V2 combat did not complete a real skill battle (outcome=%s, ticks=%d)" % [restored.outcome if restored != null else "null", ticks])
	if restored != null and restored.outcome == "VICTORY":
		check(restored_session.resolve_active_combat(), "v2_session: V2 battle outcome failed to settle through GameSession: %s" % restored_session.last_error)
		check(restored_session.state.run.phase == "ROUTE" and restored_session.state.run.cleared_node_ids.has("v2-session-combat"), "v2_session: V2 victory did not advance route state")
	var legacy: GameSession = GameSession.new()
	var legacy_directory: String = "user://test-saves/autobattle-v2-legacy-load-%d" % Time.get_ticks_usec()
	legacy.configure_save_directory(legacy_directory)
	check(legacy.start_new_game(1762900000422) and legacy.start_expedition("v2-legacy-load-seed"), "v2_session: V1 compatibility fixture could not initialize")
	var legacy_route: Dictionary = legacy.state.to_payload()
	legacy_route["run"]["graph"] = {"layers": [[{"id": "v1-session-combat", "layer": 0, "type": "COMBAT", "threat": "low", "enemies": [{"templateId": "E01"}], "revealLevel": 1, "lootHint": "combat"}]], "edges": [{"from": "START", "to": "v1-session-combat", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
	check(legacy._commit_payload(legacy_route) and legacy.travel_to("v1-session-combat") and legacy.begin_combat() and legacy.combat_state().combat_rules_version == CombatSimulator.COMBAT_RULES_VERSION, "v2_session: default V1 path changed after V2 integration: %s" % legacy.last_error)
	var legacy_reload: GameSession = GameSession.new()
	legacy_reload.configure_save_directory(legacy_directory)
	check(legacy_reload.load_saved_game() and legacy_reload.combat_state() != null and legacy_reload.combat_state().combat_rules_version == CombatSimulator.COMBAT_RULES_VERSION, "v2_session: active V1 snapshot did not keep loading as V1: %s" % legacy_reload.last_error)
	check(first_state != null, "v2_session: test source state was lost")
	return failure_count == 0
