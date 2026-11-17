extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var directory: String = "user://test-saves/offline-resumed-budget-%d" % Time.get_ticks_usec()
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.start_new_game() and session.start_expedition("offline-resumed-budget"), "offline_budget: could not start isolated sortie"):
		return false
	var destinations: Array[Dictionary] = session.reachable_nodes()
	if not check(not destinations.is_empty() and session.travel_to(str(destinations[0]["id"])) and session.begin_combat(), "offline_budget: could not start first actual encounter"):
		return false
	var simulator: CombatSimulator = CombatSimulator.new()
	var before_final_tick: CombatState = session.combat_state()
	var finished: bool = false
	for _tick: int in range(1800):
		var result: Dictionary = simulator.step_combat(before_final_tick)
		if not check(bool(result.get("ok", false)), "offline_budget: shared simulator rejected fixture"):
			return false
		var advanced: CombatState = result["state"] as CombatState
		if not advanced.outcome.is_empty():
			finished = true
			break
		before_final_tick = advanced
	if not check(finished and before_final_tick.time_ms > 100, "offline_budget: fixture did not reach its final tick"):
		return false
	session._combat = before_final_tick
	if not check(session._persist_combat_snapshot(), "offline_budget: could not save partially played combat"):
		return false
	var resumed: GameSession = GameSession.new()
	resumed.configure_save_directory(directory)
	if not check(resumed.load_saved_game() and resumed.combat_state() != null, "offline_budget: partial combat did not reload"):
		return false
	var prior_time: int = resumed.combat_state().time_ms
	var route_time: float = float(resumed.state.run.resources.get("gameTimeMs", 0.0))
	var report: Dictionary = resumed.simulate_autopilot(100, 100)
	check(int(report.get("battles", 0)) == 1, "offline_budget: final tick did not settle the battle")
	check(int(report.get("simulatedMs", -1)) == 100, "offline_budget: resumed combat charged previously simulated time: %s" % report)
	check(is_equal_approx(float(resumed.state.run.resources.get("gameTimeMs", 0.0)), route_time + prior_time + 100), "offline_budget: cumulative run time lost or duplicated combat ticks")
	var reloaded: GameSession = GameSession.new()
	reloaded.configure_save_directory(directory)
	check(reloaded.load_saved_game() and reloaded.state.run.combat_snapshot == null, "offline_budget: settled combat snapshot survived reload")
	check(not reloaded.resolve_active_combat(), "offline_budget: settled battle could pay twice after reload")
	var manual: GameSession = GameSession.new()
	manual.configure_save_directory("user://test-saves/offline-parity-manual")
	var offline: GameSession = GameSession.new()
	offline.configure_save_directory("user://test-saves/offline-parity-autopilot")
	var parity_setup: bool = manual.start_new_game(1762900000201) and offline.start_new_game(1762900000201)
	parity_setup = parity_setup and manual.start_expedition("offline-parity-seed") and offline.start_expedition("offline-parity-seed")
	check(parity_setup, "offline_budget: could not create matching active/offline battle profiles")
	if parity_setup:
		var parity_node_id: String = str(manual.state.run.graph["layers"][0][0].get("id", ""))
		for session_value: GameSession in [manual, offline]:
			var parity_payload: Dictionary = session_value.state.to_payload()
			for node: Dictionary in parity_payload["run"]["graph"]["layers"][0]:
				if str(node.get("id", "")) == parity_node_id:
					node["type"] = "COMBAT"
					node["enemies"] = [{"templateId": "E01"}]
			check(session_value._commit_payload(parity_payload), "offline_budget: matching battle route fixture was rejected: %s" % session_value.last_error)
			check(session_value.travel_to(parity_node_id) and session_value.begin_combat(), "offline_budget: matching battle could not begin: %s" % session_value.last_error)
		var manual_ticks: int = 0
		while manual.combat_state() != null and manual.combat_state().outcome.is_empty() and manual_ticks < 1800:
			if not manual.advance_combat_step(): break
			manual_ticks += 1
		var manual_outcome: String = manual.combat_state().outcome if manual.combat_state() != null else ""
		var manual_duration_ms: int = manual.combat_state().time_ms if manual.combat_state() != null else 0
		var manual_metrics: Dictionary = manual.combat_state().metrics.duplicate(true) if manual.combat_state() != null else {}
		check(manual_outcome == "VICTORY" and manual.resolve_active_combat(), "offline_budget: manual parity battle did not win and settle: %s" % manual.last_error)
		var parity_report: Dictionary = offline.simulate_autopilot(manual_duration_ms, manual_duration_ms)
		check(int(parity_report.get("battles", 0)) == 1 and int(parity_report.get("battlesWon", 0)) == 1 and int(parity_report.get("simulatedMs", -1)) == manual_duration_ms, "offline_budget: same combat budget did not settle one matching offline battle: %s" % parity_report)
		var manual_run: Dictionary = manual.state.run.to_dictionary()
		var offline_run: Dictionary = offline.state.run.to_dictionary()
		var offline_combat_event: Dictionary = {}
		for event: Dictionary in parity_report.get("eventLog", []):
			if str(event.get("type", "")) == "COMBAT": offline_combat_event = event
		check(manual_outcome == str(offline_combat_event.get("outcome", "")) and manual_metrics == offline_combat_event.get("metrics", {}), "offline_budget: active and offline simulator outcomes or combat metrics diverged")
		var manual_economy: Dictionary = {"resources": manual_run.get("resources", {}), "wallet": manual_run.get("runWallet", {}), "cargo": manual_run.get("unsecuredCargo", []), "grants": manual_run.get("grantIds", []), "cleared": manual_run.get("clearedNodeIds", []), "phase": manual_run.get("phase", ""), "operator": manual.state.meta.operator.to_dictionary()}
		var offline_economy: Dictionary = {"resources": offline_run.get("resources", {}), "wallet": offline_run.get("runWallet", {}), "cargo": offline_run.get("unsecuredCargo", []), "grants": offline_run.get("grantIds", []), "cleared": offline_run.get("clearedNodeIds", []), "phase": offline_run.get("phase", ""), "operator": offline.state.meta.operator.to_dictionary()}
		check(StateHash.new().state_hash(manual_economy) == StateHash.new().state_hash(offline_economy), "offline_budget: active and offline combat settlement diverged in economy, progression or run resources")
		var offline_reload: GameSession = GameSession.new()
		offline_reload.configure_save_directory("user://test-saves/offline-parity-autopilot")
		check(offline_reload.load_saved_game() and offline_reload.state.run.phase == "ROUTE" and offline_reload.state.run.combat_snapshot == null, "offline_budget: parity result did not persist cleanly after settlement")
	return failure_count == 0
