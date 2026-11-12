extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var catalog: EventCatalog = EventCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	check(bool(loaded.get("ok", false)), "event_catalog: could not load canonical events: %s" % str(loaded.get("error", "")))
	check(int(loaded.get("count", 0)) == 24, "event_catalog: expected all 24 canonical events")
	var event: Dictionary = catalog.get_event("EV22")
	check(event.size() > 0 and event.get("choices", []).size() == 2, "event_catalog: event choices are missing")
	var used: Array[String] = ["EV22"]
	check(not catalog.available_ids(used).has("EV22"), "event_catalog: used event remained available for the campaign")
	return failure_count == 0
