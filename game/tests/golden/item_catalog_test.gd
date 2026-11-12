extends "res://tests/test_case.gd"

const CATALOG_PATH: String = "res://scripts/core/items/item_catalog.gd"

func run(_tree: SceneTree) -> bool:
	var catalog_script: Script = load(CATALOG_PATH) as Script
	if not check(catalog_script != null, "item_catalog: implementation is missing"):
		return false
	var catalog: Object = catalog_script.new()
	var loaded: Dictionary = catalog.call("load_catalog")
	if not check(bool(loaded.get("ok", false)), "item_catalog: source catalog failed validation: %s" % loaded.get("error", "")):
		return false
	check(int(loaded.get("count", 0)) == 73, "item_catalog: unexpected template count")
	check(bool(catalog.call("has_template", "PISTOL_K1")), "item_catalog: ordinary item is missing")
	check(bool(catalog.call("has_template", "U01")), "item_catalog: unique item is missing")
	check(bool(catalog.call("has_affix", "AF_HP")), "item_catalog: affix definitions are missing")
	check(catalog.call("get_rules").get("affixes", []).size() == 30, "item_catalog: affix count differs from source data")
	check(not bool(catalog.call("has_template", "UNKNOWN_ITEM")), "item_catalog: unknown item was reported present")
	var template: Dictionary = catalog.call("get_template", "PISTOL_K1")
	check(template.get("category") == "MAIN", "item_catalog: pistol category differs from source data")
	check(float(template.get("weapon", {}).get("damage", 0.0)) == 34.0, "item_catalog: pistol damage differs from source data")
	template["name"] = "mutated"
	check(catalog.call("get_template", "PISTOL_K1").get("name") != "mutated", "item_catalog: callers can mutate catalog definitions")
	check(catalog.call("template_ids").size() == 73, "item_catalog: sorted ID index is incomplete")
	return failure_count == 0
