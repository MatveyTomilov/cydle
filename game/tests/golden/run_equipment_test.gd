extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/run-equipment")
	if not check(session.start_new_game(1762900000301), "run_equipment: could not create a profile"):
		return false
	if not check(session.start_expedition("run-equipment-seed"), "run_equipment: could not start an expedition"):
		return false
	var catalog: ItemCatalog = ItemCatalog.new()
	if not check(bool(catalog.load_catalog().get("ok", false)), "run_equipment: item catalog failed to load"):
		return false
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("run-equipment-seed", "field-implant")
	var created: Dictionary = ItemFactory.new().create_item(rng, catalog, {
		"templateId": "IMP_SHIELD", "techLevel": 1, "rarity": "MODIFIED", "secured": false,
		"originGrantId": "run-equipment:field-implant", "origin": "test", "acquiredAt": 0,
	})
	if not check(bool(created.get("ok", false)), "run_equipment: field item fixture failed: %s" % str(created.get("error", ""))):
		return false
	var item: Dictionary = (created["item"] as ItemInstance).to_dictionary()
	var payload: Dictionary = session.state.to_payload()
	payload["run"]["unsecuredCargo"].append(item)
	check(session._commit_payload(payload), "run_equipment: could not add test item to unsecured cargo: %s" % session.last_error)
	var item_id: String = str(item.get("itemId", ""))
	var slots: Array[String] = session.valid_run_equipment_slots(item_id)
	check(not slots.is_empty(), "run_equipment: no compatible implant slot was offered: %s" % str(slots))
	if slots.is_empty():
		return false
	var selected_slot: String = slots[0]
	var meta_equipment_before: Dictionary = session.state.meta.equipment.duplicate(true)
	var shield_before: float = float(session.run_build_preview().get("stats", {}).get("maxShield", 0.0))
	check(session.equip_run_item(selected_slot, item_id), "run_equipment: cargo equip failed: %s" % session.last_error)
	check(str(session.state.run.equipment.get(selected_slot, "")) == item_id, "run_equipment: run equipment did not point at the cargo item")
	check(not session.state.meta.equipment.values().has(item_id), "run_equipment: equipping cargo changed permanent equipment")
	check(not bool(session.state.run.unsecured_cargo.filter(func(value: Dictionary) -> bool: return str(value.get("itemId", "")) == item_id)[0].get("secured", true)), "run_equipment: field item was secured during equip")
	check(float(session.run_build_preview().get("stats", {}).get("maxShield", 0.0)) > shield_before, "run_equipment: field preview ignored the equipped shield implant")
	check(session.state.meta.equipment == meta_equipment_before, "run_equipment: permanent loadout changed during a field swap")
	check(not bool(session.run_item_dismantle_quote(item_id).get("valid", false)), "run_equipment: equipped cargo could still be dismantled")
	check(session.unequip_run_item(selected_slot), "run_equipment: restoring the stock slot failed: %s" % session.last_error)
	check(str(session.state.run.equipment.get(selected_slot, "")) != item_id and session.state.run.unsecured_cargo.size() == 1, "run_equipment: unequip removed or retained the wrong cargo reference")
	check(session.equip_run_item(selected_slot, item_id), "run_equipment: cargo could not be re-equipped: %s" % session.last_error)
	var saved: bool = session.save()
	check(saved, "run_equipment: save failed: %s" % session.last_error)
	var loaded: GameSession = GameSession.new()
	loaded.configure_save_directory("user://test-saves/run-equipment")
	check(loaded.load_saved_game(), "run_equipment: field-equipped save did not reload: %s" % loaded.last_error)
	check(str(loaded.state.run.equipment.get(selected_slot, "")) == item_id and not bool(loaded.state.run.unsecured_cargo[0].get("secured", true)), "run_equipment: save/load lost ownership or field slot")
	check(is_equal_approx(float(loaded.run_build_preview().get("stats", {}).get("maxShield", 0.0)), float(session.run_build_preview().get("stats", {}).get("maxShield", -1.0))), "run_equipment: field build changed after load")
	var continuation: Dictionary = loaded.state.to_payload()
	continuation["run"]["phase"] = "CHECKPOINT"
	continuation["run"]["combatSnapshot"] = null
	loaded._combat = null
	check(loaded._commit_payload(continuation), "run_equipment: could not prepare a checkpoint continuation: %s" % loaded.last_error)
	check(loaded.continue_campaign(), "run_equipment: continuing the sector reset the field loadout: %s" % loaded.last_error)
	check(str(loaded.state.run.equipment.get(selected_slot, "")) == item_id, "run_equipment: field loadout was reset at sector continuation")
	var extraction: Dictionary = loaded.state.to_payload()
	extraction["run"]["phase"] = "CHECKPOINT"
	check(loaded._commit_payload(extraction), "run_equipment: could not prepare extraction: %s" % loaded.last_error)
	check(loaded.extract_run(), "run_equipment: extraction failed: %s" % loaded.last_error)
	check(str(loaded.state.meta.equipment.get(selected_slot, "")) == item_id, "run_equipment: extracted field loadout was not saved as permanent equipment")
	var secured_item: Dictionary = loaded.state.meta.inventory.filter(func(value: Dictionary) -> bool: return str(value.get("itemId", "")) == item_id)[0]
	check(bool(secured_item.get("secured", false)), "run_equipment: extraction did not secure equipped cargo")
	var combat_session: GameSession = GameSession.new()
	combat_session.configure_save_directory("user://test-saves/run-equipment-combat")
	if check(combat_session.start_new_game(1762900000302) and combat_session.start_expedition("run-equipment-combat"), "run_equipment: could not prepare a combat field-build profile"):
		var combat_payload: Dictionary = combat_session.state.to_payload()
		combat_payload["run"]["unsecuredCargo"].append(item.duplicate(true))
		check(combat_session._commit_payload(combat_payload), "run_equipment: combat field-item fixture was rejected")
		var combat_slots: Array[String] = combat_session.valid_run_equipment_slots(item_id)
		check(not combat_slots.is_empty(), "run_equipment: combat field item had no compatible slot")
		if combat_slots.is_empty():
			return false
		var combat_slot: String = combat_slots[0]
		check(combat_session.equip_run_item(combat_slot, item_id), "run_equipment: combat field item could not be equipped")
		var combat_run: Dictionary = combat_session.state.to_payload()["run"]
		combat_run["graph"] = {"layers": [[{"id": "field-build-combat", "layer": 0, "type": "COMBAT", "threat": "low", "enemies": [{"templateId": "E01"}], "revealLevel": 1, "lootHint": "combat"}]], "edges": [{"from": "START", "to": "field-build-combat", "fromLayer": -1, "toLayer": 0, "fuelCost": 1}]}
		var graph_payload: Dictionary = combat_session.state.to_payload()
		graph_payload["run"] = combat_run
		check(combat_session._commit_payload(graph_payload) and combat_session.travel_to("field-build-combat") and combat_session.begin_combat(), "run_equipment: combat failed to start with field equipment: %s" % combat_session.last_error)
		if combat_session.combat_state() != null:
			var combat_max_shield: float = float(combat_session.combat_state().operator.base_sheet.get("maxShield", 0.0))
			check(is_equal_approx(combat_max_shield, float(combat_session.run_build_preview().get("stats", {}).get("maxShield", -1.0))), "run_equipment: real combat did not use the field BuildResolver result")
	return failure_count == 0
