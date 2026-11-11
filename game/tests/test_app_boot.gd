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

	var title: Label = app.get_node_or_null("SafeMargin/Content/Title") as Label
	if not check(title != null, "test_app_boot: CYDLE title is missing after launch"):
		app.queue_free()
		return false
	check(title.text == "CYDLE", "test_app_boot: launch title is not CYDLE")

	var status: Label = app.get_node_or_null("SafeMargin/Content/RuntimeStatus") as Label
	if not check(status != null, "test_app_boot: runtime status is missing"):
		app.queue_free()
		return false
	check(status.text.contains("ИГРОВОЙ ЦИКЛ ЕЩЁ НЕ ПОДКЛЮЧЁН"), "test_app_boot: boot screen does not disclose the incomplete gameplay state")

	var quit_button: Button = app.get_node_or_null("SafeMargin/Content/QuitButton") as Button
	if not check(quit_button != null, "test_app_boot: quit action is missing"):
		app.queue_free()
		return false
	check(quit_button.focus_mode == Control.FOCUS_ALL, "test_app_boot: quit action cannot receive keyboard/controller focus")

	if not check(quit_button.pressed.is_connected(Callable(app, "_on_quit_button_pressed")), "test_app_boot: quit action is not connected"):
		app.queue_free()
		return false

	app.queue_free()
	await tree.process_frame
	return failure_count == 0
