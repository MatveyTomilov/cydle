extends "res://tests/test_case.gd"

const SAVE_FIXTURE: String = "res://tests/fixtures/saves/initial_save.json"
const COMBAT_FIXTURE: String = "res://tests/fixtures/combat/actor_initialization.json"

func run(_tree: SceneTree) -> bool:
	var save_payload: Dictionary = _read_dictionary(SAVE_FIXTURE)
	var fixture: Dictionary = _read_dictionary(COMBAT_FIXTURE)
	if not check(not save_payload.is_empty() and not fixture.is_empty(), "combat_factory: starter save or combat oracle is missing"):
		return false
	var meta: Dictionary = save_payload.get("meta", {})
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in meta.get("inventory", []):
		items_by_id[str(item_value["itemId"])] = item_value
	var equipment: Dictionary = {}
	for slot_value: Variant in meta.get("equipment", {}).keys():
		var item: ItemInstance = ItemInstance.new()
		var item_data: Dictionary = items_by_id[str(meta["equipment"][slot_value])]
		check(item.instantiate_from_dictionary(item_data), "combat_factory: starter item failed typed parsing")
		equipment[str(slot_value)] = item
	var operator_data: Dictionary = meta.get("operator", {})
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": equipment, "attributes": operator_data.get("attributes", {}),
		"attributePointsEarned": operator_data.get("attributePoints", 0), "treePointsEarned": operator_data.get("treePoints", 0),
		"skillIds": meta.get("skillIds", []), "passiveIds": meta.get("passiveIds", []), "treeNodeIds": meta.get("treeNodeIds", []),
		"unlockedImplantSlots": meta.get("unlockedImplantSlots", 4), "unlockedDroneSlots": meta.get("unlockedDroneSlots", 1),
	})
	if not check(bool(build.get("valid", false)), "combat_factory: starter build was rejected"):
		return false
	var enemy_specs: Array[Dictionary] = []
	for spec: Dictionary in fixture.get("enemies", []):
		enemy_specs.append(spec)
	var created: Dictionary = CombatFactory.new().create_roster(build, enemy_specs, int(fixture["depth"]), fixture.get("options", {}))
	if not check(bool(created.get("ok", false)), "combat_factory: failed to create roster: %s" % str(created.get("error", ""))):
		return false
	var expected: Dictionary = fixture.get("expected", {})
	check(_actors_match(created["operator"], expected.get("operator", {})), "combat_factory: operator initial state differs from legacy oracle")
	check(_actor_list_matches(created.get("drones", []), expected.get("drones", [])), "combat_factory: drone initial state differs from legacy oracle")
	check(_actor_list_matches(created.get("enemies", []), expected.get("enemies", [])), "combat_factory: enemy initial state differs from legacy oracle")
	return failure_count == 0

func _read_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}

func _actor_list_matches(actual_values: Array, expected_values: Array) -> bool:
	if actual_values.size() != expected_values.size():
		return false
	for index: int in range(actual_values.size()):
		if not _actors_match(actual_values[index], expected_values[index]):
			return false
	return true

func _actors_match(actor_value: Variant, expected: Dictionary) -> bool:
	if not actor_value is CombatActorState:
		return false
	var actor: CombatActorState = actor_value
	var actual: Dictionary = actor.to_dictionary()
	for key: Variant in expected.keys():
		if key == "ownerId" and str(actual.get(key, "")).is_empty():
			actual[key] = null
		if key == "eliteMod" and str(actual.get(key, "")).is_empty():
			actual[key] = null
		if not _json_equivalent(actual.get(key), expected[key]):
			return false
	return true

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
