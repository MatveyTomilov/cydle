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
	_test_grey_dealer_price_rounding(catalog)
	_test_all_event_choice_transactions(catalog)
	return failure_count == 0

func _test_grey_dealer_price_rounding(catalog: EventCatalog) -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/event-grey-dealer-price")
	if not check(session.start_new_game(1762900000990) and session.start_expedition("event-grey-dealer-price"), "event_catalog: could not prepare Grey Dealer price regression"):
		return
	session.state.run.depth = 12
	var event: Dictionary = catalog.get_event("EV13")
	var rare_choice: Dictionary = {}
	for choice: Dictionary in event.get("choices", []):
		if str(choice.get("special", "")) == "greyDealer":
			rare_choice = choice
			break
	var scale: float = CydleFormula.new().reward_scale(12.0)
	var rare_shop_price: int = ceili((25.0 + 7.0 * 12.0) * 2.0 * scale)
	var expected_cost: int = ceili(float(rare_shop_price) * 0.6)
	var actual_costs: Dictionary = session.event_choice_costs(rare_choice)
	check(not rare_choice.is_empty() and expected_cost == 267 and int(actual_costs.get("CREDITS", -1)) == expected_cost, "event_catalog: EV13 did not apply ceil(60%% × rounded rare shop price) at depth 12; shop=%d expected=%d actual=%s" % [rare_shop_price, expected_cost, str(actual_costs)])

func _test_all_event_choice_transactions(catalog: EventCatalog) -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/event-catalog-matrix")
	if not check(session.start_new_game(1762900000991) and session.start_expedition("event-catalog-matrix"), "event_catalog: could not create the isolated transaction-matrix profile"):
		return
	var item_catalog: ItemCatalog = ItemCatalog.new()
	if not check(bool(item_catalog.load_catalog().get("ok", false)), "event_catalog: item catalog failed for cargo-sensitive event coverage"):
		return
	var tested_choices: int = 0
	for event_id: String in catalog.events.keys():
		var event: Dictionary = catalog.get_event(event_id)
		for choice: Dictionary in event.get("choices", []):
			var node_id: String = "matrix-%s-%s" % [event_id, str(choice.get("id", ""))]
			var event_node: Dictionary = {"id": node_id, "layer": 0, "type": "EVENT", "eventId": event_id, "threat": "medium", "enemies": [], "revealLevel": 1, "lootHint": "event"}
			var boss_node: Dictionary = {"id": "matrix-boss", "layer": 1, "type": "BOSS", "threat": "boss", "enemies": [{"templateId": "BOSS_A"}], "revealLevel": 1, "lootHint": "boss"}
			var payload: Dictionary = session.state.to_payload()
			var run: Dictionary = payload["run"]
			run["graph"] = {"layers": [[event_node], [boss_node]], "edges": [{"from": "START", "to": node_id, "fromLayer": -1, "toLayer": 0, "fuelCost": 1}, {"from": node_id, "to": "matrix-boss", "fromLayer": 0, "toLayer": 1, "fuelCost": 1}]}
			run["phase"] = "ROUTE"
			run["currentNodeId"] = "START"
			run["visitedNodeIds"] = []
			run["clearedNodeIds"] = []
			run["eventsSeen"] = []
			run["unsecuredCargo"] = []
			run["grantIds"] = []
			run["runWallet"] = {"CREDITS": 100000.0, "SCRAP": 100000.0, "DATA": 100000.0}
			run["resources"]["fuel"] = maxf(10.0, float(run["resources"].get("maxFuel", 10.0)))
			var surrender_item_id: String = ""
			if int(choice.get("surrenderCargo", 0)) > 0:
				var cargo_rng: DeterministicRng = DeterministicRng.new()
				cargo_rng.seed("event-catalog-matrix", node_id)
				var cargo_result: Dictionary = ItemFactory.new().create_item(cargo_rng, item_catalog, {"templateId": "PISTOL_K1", "techLevel": 1, "rarity": "COMMON", "secured": false, "originGrantId": "event-catalog-matrix:%s" % node_id, "origin": "test", "acquiredAt": 0})
				if not check(bool(cargo_result.get("ok", false)), "event_catalog: could not construct cargo for %s/%s" % [event_id, str(choice.get("id", ""))]):
					continue
				var cargo_item: ItemInstance = cargo_result["item"] as ItemInstance
				surrender_item_id = cargo_item.item_id
				run["unsecuredCargo"].append(cargo_item.to_dictionary())
			if not check(session._commit_payload(payload) and session.travel_to(node_id), "event_catalog: could not prepare %s/%s: %s" % [event_id, str(choice.get("id", "")), session.last_error]):
				continue
			var resolved: bool = session.resolve_event(str(choice.get("id", "")), surrender_item_id)
			check(resolved, "event_catalog: actual event transaction rejected %s/%s: %s" % [event_id, str(choice.get("id", "")), session.last_error])
			if resolved:
				check(session.state.run.phase == "ROUTE" and session.state.run.cleared_node_ids.has(node_id) and session.state.run.events_seen == [event_id], "event_catalog: %s/%s did not consume its route node and record the event" % [event_id, str(choice.get("id", ""))])
				if event_id == "EV07" and str(choice.get("id", "")) == "A":
					var expected_hull: float = maxf(0.0, float(run["resources"].get("hull", 0.0)) - float(run["resources"].get("maxHull", 0.0)) * 0.1)
					check(is_equal_approx(session.state.run.resources.get("hull", -1.0), expected_hull), "event_catalog: EV07 must remove 10%% of maximum hull, expected=%s actual=%s" % [str(expected_hull), str(session.state.run.resources.get("hull", -1.0))])
				tested_choices += 1
	check(tested_choices == 48, "event_catalog: expected 48 successful real event choices, got %d" % tested_choices)
