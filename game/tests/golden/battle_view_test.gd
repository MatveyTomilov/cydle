extends "res://tests/test_case.gd"

const FIXTURE_SEED: int = 1762900000411
const PLAYBACK_DEADLINE_MS: int = 60000

var _settled: bool = false

func run(tree: SceneTree) -> bool:
	var stamp: int = Time.get_ticks_usec()
	var template: String = _profile_template(stamp)
	if template.is_empty():
		return false
	var directory: String = "user://test-saves/battle-view-%d" % stamp
	var session: GameSession = _battle(directory, template)
	if session == null:
		return false
	var reference: GameSession = _battle("user://test-saves/battle-view-reference-%d" % stamp, template)
	if reference == null:
		return false
	var view: BattleView = BattleView.new(session, true)
	tree.root.add_child(view)
	check(session.combat_state().time_ms == 0, "battle_view: constructing the screen advanced the battle")
	await tree.process_frame
	view._on_pause()
	var paused_at: int = session.combat_state().time_ms
	var pause_frames: int = 0
	while pause_frames < 30:
		await tree.process_frame
		pause_frames += 1
	check(session.combat_state().time_ms == paused_at, "battle_view: pause did not stop the simulation")
	view._on_speed(4.0)
	var started: int = Time.get_ticks_msec()
	while session.combat_state().outcome.is_empty() and Time.get_ticks_msec() - started < PLAYBACK_DEADLINE_MS:
		await tree.process_frame
	if not check(not session.combat_state().outcome.is_empty(), "battle_view: real-time playback never reached an outcome within %d ms" % PLAYBACK_DEADLINE_MS):
		view.queue_free()
		return false
	check(session.combat_state().time_ms > 0, "battle_view: the rendered battle did not advance combat time")
	check(view._seen_event_id > 0, "battle_view: the arena was never fed any simulator events")
	check(not view._action_box.get_children().is_empty(), "battle_view: reaching an outcome did not offer settlement")
	check(reference.skip_combat_to_outcome(), "battle_view: reference skip failed: %s" % reference.last_error)
	check(session.combat_state().outcome == reference.combat_state().outcome, "battle_view: rendering changed the battle outcome")
	check(session.combat_state().time_ms == reference.combat_state().time_ms, "battle_view: rendering changed the battle duration")
	check(StateHash.new().state_hash(_normalized(session)) == StateHash.new().state_hash(_normalized(reference)), "battle_view: rendering changed the simulated combat state")
	view.settlement_requested.connect(_on_settlement_requested)
	var settle_button: Button = null
	for child: Node in view._action_box.get_children():
		if child is Button:
			settle_button = child as Button
	if not check(settle_button != null, "battle_view: settlement button is missing"):
		view.queue_free()
		return false
	settle_button.pressed.emit()
	await tree.process_frame
	check(_settled, "battle_view: the settlement button did not emit settlement_requested")
	check(session.resolve_active_combat(), "battle_view: the rendered battle could not be settled: %s" % session.last_error)
	check(session.state.run.phase == "ROUTE", "battle_view: settlement did not return the run to the route")
	view.queue_free()
	await tree.process_frame
	return failure_count == 0

func _on_settlement_requested() -> void:
	_settled = true

func _normalized(session: GameSession) -> Variant:
	return JSON.parse_string(JSON.stringify(session.combat_state().to_dictionary()))

func _profile_template(stamp: int) -> String:
	var directory: String = "user://test-saves/battle-view-template-%d" % stamp
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.start_new_game(FIXTURE_SEED) and session.start_expedition("battle-view"), "battle_view: could not create the template profile: %s" % session.last_error):
		return ""
	var repository: SaveRepository = SaveRepository.new()
	repository.configure_directory(directory)
	var exported: Dictionary = repository.export_text(GameSession.SLOT_ID)
	if not check(bool(exported.get("ok", false)), "battle_view: template export failed: %s" % str(exported.get("error", ""))):
		return ""
	return str(exported["text"])

func _battle(directory: String, template: String) -> GameSession:
	var repository: SaveRepository = SaveRepository.new()
	repository.configure_directory(directory)
	var imported: Dictionary = repository.import_text(GameSession.SLOT_ID, template, FIXTURE_SEED)
	if not check(bool(imported.get("ok", false)), "battle_view: template clone failed: %s" % str(imported.get("error", ""))):
		return null
	var session: GameSession = GameSession.new()
	session.configure_save_directory(directory)
	if not check(session.load_saved_game(), "battle_view: cloned profile did not load: %s" % session.last_error):
		return null
	var payload: Dictionary = session.state.to_payload()
	var node_id: String = str(payload["run"]["graph"]["layers"][0][0].get("id", ""))
	for node: Dictionary in payload["run"]["graph"]["layers"][0]:
		if str(node.get("id", "")) == node_id:
			node["type"] = "COMBAT"
			node["enemies"] = [{"templateId": "E01"}, {"templateId": "E02"}]
	if not check(session._commit_payload(payload), "battle_view: battle fixture rejected: %s" % session.last_error):
		return null
	if not check(session.travel_to(node_id) and session.begin_combat(), "battle_view: battle could not begin: %s" % session.last_error):
		return null
	return session