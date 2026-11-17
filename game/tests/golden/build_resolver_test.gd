extends "res://tests/test_case.gd"

const RESOLVER_PATH: String = "res://scripts/core/build/build_resolver.gd"
const FIXTURE_PATH: String = "res://tests/fixtures/items/build_cases.json"

func run(_tree: SceneTree) -> bool:
	var resolver_script: Script = load(RESOLVER_PATH) as Script
	if not check(resolver_script != null, "build_resolver: implementation is missing"):
		return false
	var definitions: Object = BuildCatalog.new()
	var definitions_result: Dictionary = definitions.call("load_catalog")
	check(bool(definitions_result.get("ok", false)), "build_resolver: exported skill/passive/tree/mutation data failed validation")
	check(definitions_result.get("counts", {}) == {"skills": 24, "passives": 10, "treeNodes": 100, "mutations": 12}, "build_resolver: native definition counts differ from the TypeScript source")
	var file: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if not check(file != null, "build_resolver: TypeScript oracle fixtures are missing"):
		return false
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not check(document is Dictionary and document.get("cases") is Array, "build_resolver: fixture document is invalid"):
		return false
	var resolver: Object = resolver_script.new()
	for fixture: Variant in document["cases"]:
		var equipment: Dictionary = {}
		for slot: Variant in fixture["equipment"].keys():
			var item: ItemInstance = ItemInstance.new()
			check(item.instantiate_from_dictionary(fixture["equipment"][slot]), "build_resolver: fixture item failed typed parsing")
			equipment[str(slot)] = item
		var input: Dictionary = {
			"attributes": fixture["attributes"],
			"attributePointsEarned": fixture["attributePointsEarned"],
			"skillIds": fixture.get("skillIds", []),
			"passiveIds": fixture.get("passiveIds", []),
			"treeNodeIds": fixture.get("treeNodeIds", []),
			"treePointsEarned": fixture.get("treePointsEarned", 0),
			"mutationIds": fixture.get("mutationIds", []),
			"equipment": equipment,
		}
		var result: Dictionary = resolver.call("resolve_build", input)
		var expected: Dictionary = fixture["expected"]
		check(_json_equivalent(result["valid"], expected["valid"]), "build_resolver: %s legality differs from oracle" % str(fixture["name"]))
		for field: String in ["attributes", "stats", "mainWeapon", "sidearm", "drones", "modifiers", "effects", "triggerEffects", "skills", "skillIds", "passives", "passiveIds", "treeNodes", "treeNodeIds", "mutationIds"]:
			if expected.has(field):
				if not _json_equivalent(result[field], expected[field]):
					print("DIFF ", fixture["name"], " ", field)
					print("ACTUAL=", JSON.stringify(result[field]))
					print("EXPECTED=", JSON.stringify(expected[field]))
					check(false, "build_resolver: %s field %s differs from oracle" % [str(fixture["name"]), field])
	var invalid: Dictionary = resolver.call("resolve_build", {"equipment": {}, "attributes": {"POW": 0}})
	check(not bool(invalid.get("valid", true)), "build_resolver: missing main / invalid attribute was accepted")
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
