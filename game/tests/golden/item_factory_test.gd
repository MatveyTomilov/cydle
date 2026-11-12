extends "res://tests/test_case.gd"

const FACTORY_PATH: String = "res://scripts/core/items/item_factory.gd"
const CATALOG_PATH: String = "res://scripts/core/items/item_catalog.gd"
const FIXTURE_PATH: String = "res://tests/fixtures/items/create_item_cases.json"

func run(_tree: SceneTree) -> bool:
	var factory_script: Script = load(FACTORY_PATH) as Script
	var catalog_script: Script = load(CATALOG_PATH) as Script
	if not check(factory_script != null and catalog_script != null, "item_factory: required scripts are missing"):
		return false
	var catalog: Object = catalog_script.new()
	var loaded: Dictionary = catalog.call("load_catalog")
	if not check(bool(loaded.get("ok", false)), "item_factory: catalog failed to load: %s" % loaded.get("error", "")):
		return false
	var fixture_file: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if not check(fixture_file != null, "item_factory: TypeScript golden fixtures are missing"):
		return false
	var fixture_document: Variant = JSON.parse_string(fixture_file.get_as_text())
	fixture_file.close()
	if not check(fixture_document is Dictionary and fixture_document.get("cases") is Array, "item_factory: golden fixture format is invalid"):
		return false
	var factory: Object = factory_script.new()
	for fixture: Variant in fixture_document["cases"]:
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed(str(fixture["stream"]), str(fixture["seed"]))
		var created: Dictionary = factory.call("create_item", rng, catalog, fixture["options"])
		if not check(bool(created.get("ok", false)), "item_factory: %s case failed: %s" % [str(fixture["name"]), str(created.get("error", ""))]):
			continue
		var item: ItemInstance = created.get("item") as ItemInstance
		check(item != null, "item_factory: %s did not return an ItemInstance" % str(fixture["name"]))
		if item != null:
			check(_json_equivalent(item.to_dictionary(), fixture["expected"]), "item_factory: %s differs from the TypeScript oracle" % str(fixture["name"]))
			var restored: ItemInstance = ItemInstance.new()
			check(restored.instantiate_from_dictionary(item.to_dictionary()), "item_factory: %s typed item roundtrip failed" % str(fixture["name"]))
			check(_json_equivalent(restored.to_dictionary(), item.to_dictionary()), "item_factory: %s typed item data changed during roundtrip" % str(fixture["name"]))
	for fixture: Variant in fixture_document.get("rarityCases", []):
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed(str(fixture["stream"]), str(fixture["seed"]))
		var rarity: String = str(factory.call("roll_rarity", rng, catalog, str(fixture["table"]), float(fixture["rareShift"])))
		check(rarity == str(fixture["expected"]), "item_factory: %s rarity roll differs from the TypeScript oracle" % str(fixture["name"]))
	for fixture: Variant in fixture_document.get("lootCases", []):
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed(str(fixture["stream"]), str(fixture["seed"]))
		var rolled: Dictionary = factory.call("roll_item", rng, catalog, fixture["options"])
		check(bool(rolled.get("ok", false)), "item_factory: %s loot roll failed: %s" % [str(fixture["name"]), str(rolled.get("error", ""))])
		if bool(rolled.get("ok", false)):
			var item: ItemInstance = rolled.get("item") as ItemInstance
			var expected: Dictionary = fixture["expected"]
			var actual: Dictionary = rolled.duplicate(true)
			actual.erase("ok")
			actual.erase("error")
			actual["item"] = item.to_dictionary()
			check(_json_equivalent(actual, expected), "item_factory: %s loot result differs from the TypeScript oracle" % str(fixture["name"]))
	var malformed: ItemInstance = ItemInstance.new()
	check(not malformed.instantiate_from_dictionary({"itemId": "bad"}), "item_factory: incomplete item save was accepted")
	return failure_count == 0

func _json_equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return float(left) == float(right)
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
