extends "res://tests/test_case.gd"

const FIXTURE_SEED: int = 1762900000307
const TICK_MS: int = 100
const CADENCE_MS: int = 1000

func run(_tree: SceneTree) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var template: String = _profile_template(stamp)
	if template.is_empty():
		return false
	if not _playback_matches_reference(stamp, template):
		return false
	if not _cadence_and_resume(stamp, template):
		return false
	if not _skip_parity_and_settlement(stamp, template):
		return false
	_idle_session_guards(stamp)
	return failure_count == 0

## Item identifiers embed the profile save id, so two freshly rolled profiles can never
## hash identically; every scenario therefore starts from a clone of one template profile.
func _profile_template(stamp: int) -> String:
	var directory: String = "user://test-saves/playback-template-%d" % stamp
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.start_new_game(FIXTURE_SEED) and session.start_expedition("combat-playback"), "combat_playback: could not create the template profile: %s" % session.last_error):
		return ""
	var repository: SaveRepository = SaveRepository.new()
	repository.configure_directory(directory)
	var exported: Dictionary = repository.export_text(GameSession.SLOT_ID)
	if not check(bool(exported.get("ok", false)), "combat_playback: template profile could not be exported: %s" % str(exported.get("error", ""))):
		return ""
	return str(exported["text"])

func _battle(directory: String, template: String) -> GameSession:
	var repository: SaveRepository = SaveRepository.new()
	repository.configure_directory(directory)
	var imported: Dictionary = repository.import_text(GameSession.SLOT_ID, template, FIXTURE_SEED)
	if not check(bool(imported.get("ok", false)), "combat_playback: template profile could not be cloned: %s" % str(imported.get("error", ""))):
		return null
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.load_saved_game(), "combat_playback: cloned profile did not load: %s" % session.last_error):
		return null
	var payload: Dictionary = session.state.to_payload()
	var node_id: String = str(payload["run"]["graph"]["layers"][0][0].get("id", ""))
	for node: Dictionary in payload["run"]["graph"]["layers"][0]:
		if str(node.get("id", "")) == node_id:
			node["type"] = "COMBAT"
			node["enemies"] = [{"templateId": "E01"}, {"templateId": "E01"}]
	if not check(session._commit_payload(payload), "combat_playback: battle fixture was rejected: %s" % session.last_error):
		return null
	if not check(session.travel_to(node_id) and session.begin_combat(), "combat_playback: battle could not begin: %s" % session.last_error):
		return null
	return session

func _playback_matches_reference(stamp: int, template: String) -> bool:
	var reference: GameSession = _battle("user://test-saves/playback-reference-%d" % stamp, template)
	var played: GameSession = _battle("user://test-saves/playback-realtime-%d" % stamp, template)
	if reference == null or played == null:
		return false
	for _tick: int in range(6):
		if not check(reference.advance_combat_step(), "combat_playback: reference tick failed: %s" % reference.last_error):
			return false
	if not check(played.advance_combat_playback(6 * TICK_MS), "combat_playback: playback advance failed: %s" % played.last_error):
		return false
	check(played.combat_state().time_ms == reference.combat_state().time_ms, "combat_playback: playback did not advance the requested budget")
	check(_combat_hash(played) == _combat_hash(reference), "combat_playback: real-time playback diverged from the per-tick reference simulation")
	var before_subtick: String = _combat_hash(played)
	check(played.advance_combat_playback(TICK_MS - 1) and played.advance_combat_playback(-5 * TICK_MS), "combat_playback: sub-tick budget was rejected")
	check(_combat_hash(played) == before_subtick, "combat_playback: a sub-tick or negative budget changed combat state")
	var scaled: GameSession = _battle("user://test-saves/playback-scaled-%d" % stamp, template)
	if scaled == null:
		return false
	if not check(scaled.advance_combat_playback(30 * TICK_MS, 3 * CADENCE_MS), "combat_playback: scaled-cadence playback failed: %s" % scaled.last_error):
		return false
	check(scaled.combat_state().time_ms == 30 * TICK_MS, "combat_playback: scaled-cadence playback did not advance the requested budget")
	check(scaled.state.run.combat_snapshot.sim_time_ms == 3 * CADENCE_MS, "combat_playback: a scaled cadence persisted somewhere other than its own boundary")
	if not check(played.advance_combat_playback(24 * TICK_MS), "combat_playback: default-cadence playback failed: %s" % played.last_error):
		return false
	check(_combat_hash(scaled) == _combat_hash(played), "combat_playback: the persistence interval changed the simulated battle")
	return true

func _cadence_and_resume(stamp: int, template: String) -> bool:
	var directory: String = "user://test-saves/playback-cadence-%d" % stamp
	var live: GameSession = _battle(directory, template)
	if live == null:
		return false
	check(live.state.run.combat_snapshot.sim_time_ms == 0, "combat_playback: a fresh battle did not persist its zero-time snapshot")
	var boundaries: Array[int] = []
	var persisted_ms: int = 0
	var elapsed_ms: int = 0
	for _step: int in range(30):
		if not check(live.advance_combat_playback(TICK_MS), "combat_playback: cadence tick failed: %s" % live.last_error):
			return false
		elapsed_ms += TICK_MS
		var snapshot_ms: int = live.state.run.combat_snapshot.sim_time_ms
		if snapshot_ms != persisted_ms:
			boundaries.append(snapshot_ms)
			persisted_ms = snapshot_ms
		if not live.combat_state().outcome.is_empty():
			break
		check(live.combat_state().time_ms == elapsed_ms, "combat_playback: in-memory combat time drifted from the requested playback budget")
		check(snapshot_ms % CADENCE_MS == 0, "combat_playback: snapshot was written off the cadence boundary at %d ms" % snapshot_ms)
	check(boundaries.size() >= 3, "combat_playback: fixture battle was too short to observe the persistence cadence: %s" % str(boundaries))
	check(boundaries.size() <= 4, "combat_playback: playback persisted more often than the cadence allows: %s" % str(boundaries))
	if not check(live.advance_combat_playback(4 * TICK_MS), "combat_playback: could not stop inside a cadence window: %s" % live.last_error):
		return false
	elapsed_ms += 4 * TICK_MS
	if live.combat_state().outcome.is_empty():
		var lag_ms: int = live.combat_state().time_ms - live.state.run.combat_snapshot.sim_time_ms
		check(lag_ms > 0 and lag_ms < CADENCE_MS, "combat_playback: expected unflushed progress inside one cadence window, got %d ms" % lag_ms)
		var unflushed: GameSession = GameSession.new()
		unflushed.configure_save_directory(directory)
		if not check(unflushed.load_saved_game() and unflushed.combat_state() != null, "combat_playback: interrupted battle did not reload: %s" % unflushed.last_error):
			return false
		check(unflushed.combat_state().time_ms == persisted_ms, "combat_playback: an interrupted run resumed from something other than the last durable boundary")
		if not check(unflushed.advance_combat_playback(lag_ms), "combat_playback: resumed battle could not replay the lost window: %s" % unflushed.last_error):
			return false
		check(_combat_hash(unflushed) == _combat_hash(live), "combat_playback: replaying the unpersisted window after a reload diverged from uninterrupted playback")
	var live_hash: String = _combat_hash(live)
	if not check(live.flush_combat_snapshot(), "combat_playback: explicit flush failed: %s" % live.last_error):
		return false
	check(live.state.run.combat_snapshot.sim_time_ms == live.combat_state().time_ms, "combat_playback: flush did not persist the current combat time")
	check(live.flush_combat_snapshot(), "combat_playback: a second flush was rejected")
	var flushed: GameSession = GameSession.new()
	flushed.configure_save_directory(directory)
	if not check(flushed.load_saved_game() and flushed.combat_state() != null, "combat_playback: flushed battle did not reload: %s" % flushed.last_error):
		return false
	check(_combat_hash(flushed) == live_hash, "combat_playback: flushed combat did not reload identically")
	return true

func _skip_parity_and_settlement(stamp: int, template: String) -> bool:
	var skip_directory: String = "user://test-saves/playback-skip-%d" % stamp
	var skipped: GameSession = _battle(skip_directory, template)
	var streamed: GameSession = _battle("user://test-saves/playback-stream-%d" % stamp, template)
	if skipped == null or streamed == null:
		return false
	if not check(skipped.skip_combat_to_outcome(), "combat_playback: skip to outcome failed: %s" % skipped.last_error):
		return false
	var windows: int = 0
	while streamed.combat_state().outcome.is_empty() and windows < 200:
		if not check(streamed.advance_combat_playback(CADENCE_MS), "combat_playback: streamed window failed: %s" % streamed.last_error):
			return false
		windows += 1
	if not check(not streamed.combat_state().outcome.is_empty(), "combat_playback: streamed playback never reached an outcome"):
		return false
	check(skipped.combat_state().outcome == streamed.combat_state().outcome, "combat_playback: skip and real-time playback reached different outcomes")
	check(skipped.combat_state().time_ms == streamed.combat_state().time_ms, "combat_playback: skip and real-time playback settled at different combat times")
	check(_combat_hash(skipped) == _combat_hash(streamed), "combat_playback: skip and real-time playback produced different combat states")
	check(skipped.state.run.combat_snapshot.sim_time_ms == skipped.combat_state().time_ms, "combat_playback: skip did not persist the settled battle")
	var settled_hash: String = _combat_hash(skipped)
	check(skipped.advance_combat_playback(5 * CADENCE_MS) and skipped.skip_combat_to_outcome(), "combat_playback: playback APIs rejected a settled battle")
	check(_combat_hash(skipped) == settled_hash, "combat_playback: a settled battle kept simulating")
	if not check(skipped.resolve_active_combat(), "combat_playback: skipped battle could not settle: %s" % skipped.last_error):
		return false
	check(not skipped.resolve_active_combat(), "combat_playback: a skipped battle paid out twice")
	if not check(streamed.resolve_active_combat(), "combat_playback: streamed battle could not settle: %s" % streamed.last_error):
		return false
	check(_run_hash(skipped) == _run_hash(streamed), "combat_playback: skip and real-time settlement diverged in economy, progression or run resources")
	var reloaded: GameSession = GameSession.new()
	reloaded.configure_save_directory(skip_directory)
	check(reloaded.load_saved_game() and reloaded.state.run.combat_snapshot == null, "combat_playback: settled combat snapshot survived reload")
	check(not reloaded.resolve_active_combat(), "combat_playback: settled battle could pay twice after reload")
	return true

func _idle_session_guards(stamp: int) -> void:
	var idle: GameSession = GameSession.new()
	idle.configure_save_directory("user://test-saves/playback-idle-%d" % stamp)
	if not check(idle.start_new_game(FIXTURE_SEED), "combat_playback: could not create an idle profile: %s" % idle.last_error):
		return
	check(not idle.advance_combat_playback(CADENCE_MS) and not idle.skip_combat_to_outcome(), "combat_playback: playback APIs accepted a session without an active battle")
	check(idle.flush_combat_snapshot(), "combat_playback: flush failed on a session without an active battle")

## The save format stringifies floats with ~15 significant digits, so a reloaded battle is
## only representable to that precision; both sides are normalised the same way before hashing.
func _combat_hash(session: GameSession) -> String:
	var serialized: String = JSON.stringify(session.combat_state().to_dictionary())
	return StateHash.new().state_hash(JSON.parse_string(serialized))

func _run_hash(session: GameSession) -> String:
	var run: Dictionary = session.state.run.to_dictionary()
	var cargo: Array = []
	for item: Dictionary in run.get("unsecuredCargo", []):
		var normalized: Dictionary = item.duplicate(true)
		normalized.erase("acquiredAt")
		cargo.append(normalized)
	return StateHash.new().state_hash({
		"resources": run.get("resources", {}),
		"wallet": run.get("runWallet", {}),
		"cargo": cargo,
		"grants": run.get("grantIds", []),
		"cleared": run.get("clearedNodeIds", []),
		"phase": run.get("phase", ""),
		"operator": session.state.meta.operator.to_dictionary(),
	})