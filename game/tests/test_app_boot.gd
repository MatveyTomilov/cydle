extends "res://tests/test_case.gd"

const APP_SCENE_PATH: String = "res://scenes/app/main.tscn"

func run(tree: SceneTree) -> bool:
	if not check(ResourceLoader.exists(APP_SCENE_PATH), "test_app_boot: native launch scene is missing"):
		return false

	var packed_scene: PackedScene = load(APP_SCENE_PATH) as PackedScene
	if not check(packed_scene != null, "test_app_boot: launch scene did not load as PackedScene"):
		return false

	var app: Control = packed_scene.instantiate() as Control
	if not check(app != null, "test_app_boot: launch scene root is not Control"):
		return false
	tree.root.add_child(app)
	await tree.process_frame
	var body: VBoxContainer = app.get("_body") as VBoxContainer
	if not check(body != null, "test_app_boot: game shell did not create its content area"):
		app.queue_free()
		return false
	check(str(app.get("_screen")) == "menu", "test_app_boot: new profile should open the main menu")
	check(_has_label(app, "CYDLE"), "test_app_boot: CYDLE title is missing from the game shell")
	check(_has_button(body, "НОВАЯ ИГРА"), "test_app_boot: new game action is missing")
	check(_has_button(body, "ПРОДОЛЖИТЬ"), "test_app_boot: continue action is missing")
	var pilot_session: GameSession = GameSession.new()
	pilot_session.configure_save_directory("user://test-saves/autopilot-ui")
	if check(pilot_session.start_new_game(17629000000501), "test_app_boot: could not create an isolated autopilot UI profile"):
		app.set("_session", pilot_session)
		app.call("_show_campaign_chronicle")
		check(str(app.get("_screen")) == "campaign_chronicle" and _has_label(app, "Хроника"), "test_app_boot: campaign chronicle did not open from the garage navigation")
		app.call("_show_road")
		var pilot_picker: OptionButton = _find_option_button(app)
		check(pilot_picker != null and pilot_picker.item_count == 3, "test_app_boot: road did not render all three autopilot presets")
		if pilot_picker != null and pilot_picker.item_count == 3:
			check(str(pilot_picker.get_item_metadata(1)) == "BALANCED" and pilot_picker.selected == 1, "test_app_boot: selected balanced preset was not reflected in road UI")
			pilot_picker.item_selected.emit(0)
			check(pilot_session.active_autopilot_profile_id() == "CAUTIOUS", "test_app_boot: selecting a road preset did not save the active policy")
		app.call("_show_autopilot_profile_editor")
		var profile_weights: Dictionary = app.get("_autopilot_profile_weights")
		check(str(app.get("_screen")) == "autopilot_profile" and profile_weights.has("loot"), "test_app_boot: autopilot profile editor did not open its scoring controls")
		if profile_weights.has("loot"):
			(profile_weights["loot"] as SpinBox).value = 5.0
			app.call("_on_save_autopilot_profile")
			check(is_equal_approx(float(pilot_session.active_autopilot_profile().get("objectiveWeights", {}).get("loot", 0.0)), 5.0), "test_app_boot: profile editor did not persist the custom route scoring weight")
		check(pilot_session.start_expedition("checkpoint-shipping-ui"), "test_app_boot: could not open a checkpoint-shipping UI sortie")
		var checkpoint_payload: Dictionary = pilot_session.state.to_payload()
		checkpoint_payload["run"]["phase"] = "CHECKPOINT"
		check(pilot_session._commit_payload(checkpoint_payload), "test_app_boot: could not prepare the checkpoint-shipping UI")
		app.call("_show_road")
		check(_has_button(body, "ОТПРАВИТЬ НА СКЛАД И ПРОДОЛЖИТЬ"), "test_app_boot: checkpoint did not expose protected cargo shipping")
		app.call("_show_inventory")
		check(_has_label(app, "ФИЛЬТР ДОБЫЧИ · РЕШЕНИЕ О ПОДБОРЕ ПРИМЕНЯЕТСЯ К БОЕВЫМ, КВЕСТОВЫМ И СОБЫТИЙНЫМ НАГРАДАМ"), "test_app_boot: inventory omitted the persistent loot filter controls")
		check(_has_button(body, "СОХРАНИТЬ ФИЛЬТР"), "test_app_boot: inventory did not expose the loot filter save action")
		var live_save_id: String = pilot_session.state.save_id
		var live_revision: int = pilot_session.state.revision
		app.call("_show_menu")
		var new_game_button: Button = _find_button(app, "НОВАЯ ИГРА")
		if check(new_game_button != null, "test_app_boot: menu lost the new game action"):
			new_game_button.pressed.emit()
			await tree.process_frame
			check(str(app.get("_screen")) == "new_game_confirm", "test_app_boot: new game overwrote a live profile without confirmation")
			check(pilot_session.state.save_id == live_save_id and pilot_session.state.revision == live_revision, "test_app_boot: opening the confirmation already mutated the live save")
			var cancel_button: Button = _find_button(app, "ОТМЕНА")
			if check(cancel_button != null, "test_app_boot: confirmation offered no cancel"):
				cancel_button.pressed.emit()
				await tree.process_frame
				check(pilot_session.state.save_id == live_save_id, "test_app_boot: cancelling the confirmation changed the save")
		app.call("_show_settings")
		check(_has_label(app, "Резервные копии сейва"), "test_app_boot: settings omitted the backup restore panel")
		check(_has_button(body, "ВОССТАНОВИТЬ"), "test_app_boot: settings offered no way to restore a backup")

	app.queue_free()
	await tree.process_frame
	return failure_count == 0

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null

func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child: Node in node.get_children():
		if _has_label(child, text):
			return true
	return false

func _has_button(node: Node, text: String) -> bool:
	if node is Button and (node as Button).text == text:
		return true
	for child: Node in node.get_children():
		if _has_button(child, text):
			return true
	return false

func _find_option_button(node: Node) -> OptionButton:
	if node is OptionButton:
		return node as OptionButton
	for child: Node in node.get_children():
		var found: OptionButton = _find_option_button(child)
		if found != null:
			return found
	return null
