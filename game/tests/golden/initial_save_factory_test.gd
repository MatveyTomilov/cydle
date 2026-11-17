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
		var starter_burst: Dictionary = created["payload"]["meta"]["tactics"][0]["rules"].filter(func(rule: Dictionary) -> bool: return str(rule.get("id", "")) == "starter-burst")[0]
		var burst_condition: Dictionary = starter_burst.get("conditions", [{}])[0]
		check(str(starter_burst.get("target", "")) == "allEnemies" and str(burst_condition.get("kind", "")) == "enemiesAtLeast" and int(burst_condition.get("value", 0)) == 2, "initial_save_factory: starter burst rule differs from Master Spec's two-enemy condition")
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
