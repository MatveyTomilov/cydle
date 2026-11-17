extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var catalog: StatusCatalog = StatusCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not check(bool(loaded.get("ok", false)), "status_catalog: generated definitions failed validation: %s" % str(loaded.get("error", ""))):
		return false
	check(int(loaded.get("count", 0)) == 25, "status_catalog: source count changed")
	var bleed: Dictionary = catalog.get_definition("BLEED")
	check(int(bleed.get("durationMs", 0)) == 4000 and int(bleed.get("tickMs", 0)) == 1000, "status_catalog: BLEED timing differs from source")
	check(str(catalog.get_definition("VIRUS").get("snapshotFrom", "")) == "techPower", "status_catalog: VIRUS snapshot rule was not exported")
	return failure_count == 0
