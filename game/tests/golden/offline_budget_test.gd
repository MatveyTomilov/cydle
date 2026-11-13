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
	return failure_count == 0
