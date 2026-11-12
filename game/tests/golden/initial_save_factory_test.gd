extends "res://tests/test_case.gd"

const FIXTURE_PATH: String = "res://tests/fixtures/saves/initial_save.json"

func run(_tree: SceneTree) -> bool:
	var factory: GameSaveFactory = GameSaveFactory.new()
	var created: Dictionary = factory.create_initial_payload("native-starter-oracle", 1700000000000)
	if not check(bool(created.get("ok", false)), "initial_save_factory: failed to create a starter profile: %s" % created.get("error", "")):
		return false
	var file: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if not check(file != null, "initial_save_factory: TypeScript starter-save oracle is missing"):
		return false
	var expected: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	check(expected is Dictionary, "initial_save_factory: starter-save oracle is invalid JSON")
	if expected is Dictionary:
		check(_json_equivalent(created["payload"], expected), "initial_save_factory: native starter save differs from the TypeScript oracle")
		check(created["payload"]["meta"]["inventory"].size() == 12, "initial_save_factory: expected twelve starter items")
	return failure_count == 0

func _json_equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) <= 0.000000001
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _json_equivalent(left[index], right[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left.keys():
			if not right.has(key) or not _json_equivalent(left[key], right[key]):
				return false
		return true
	return left == right
