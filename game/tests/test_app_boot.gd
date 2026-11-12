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

	app.queue_free()
	await tree.process_frame
	return failure_count == 0

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
