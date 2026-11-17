extends "res://tests/test_case.gd"

# Reproductions for the save, combat, transport and event faults found in the review.
func run(_tree: SceneTree) -> bool:
	_test_restore_disposes_stale_combat()
	_test_timeout_can_settle()
	_test_transport_loadout_and_road()
	_test_drone_damage_modifiers()
	_test_status_expire_filter()
	return failure_count == 0

func _test_restore_disposes_stale_combat() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/review-stale-combat")
	if not check(session.start_new_game(1762900000701) and session.start_expedition("review-stale-combat"), "review: could not create a saved active run"):
		return
	var stale: CombatState = CombatState.new()
	stale.time_ms = 4000
	session._combat = stale
	check(session.load_saved_game() and session.combat_state() == null, "review: loading a route save kept the old in-memory combat")
	check(session.flush_combat_snapshot() and session.state.run.combat_snapshot == null, "review: stale combat was persisted after loading a route save")
	session._combat = stale
	if check(session.restore_save_snapshot(1), "review: could not restore the pre-expedition backup: %s" % session.last_error):
		check(session.state.run == null and session.combat_state() == null, "review: restoring a garage backup retained the previous battle")
		check(session.flush_combat_snapshot(), "review: stale combat was flushed into the restored garage")

func _test_timeout_can_settle() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/review-timeout")
	if not check(session.start_new_game(1762900000702) and session.start_expedition("review-timeout"), "review: could not create a timeout run"):
		return
	var combat: CombatState = CombatState.new()
	combat.operator = CombatActorState.new()
	combat.operator.id = "operator"
	combat.operator.kind = "operator"
	combat.operator.side = "player"
	combat.operator.hp = float(session.state.run.resources.get("hp", 1.0))
	combat.operator.shield = float(session.state.run.resources.get("shield", 0.0))
	combat.outcome = "TIMEOUT"
	combat.time_ms = 180000
	session._combat = combat
	if check(session.resolve_active_combat(), "review: TIMEOUT did not settle: %s" % session.last_error):
		check(session.state.run.phase == "DEFEATED" and session.combat_state() == null, "review: TIMEOUT left the game stuck in an active encounter")
		check(session.state.run.combat_snapshot == null, "review: TIMEOUT retained an obsolete combat snapshot")
		check(str(session.state.run.last_command_id).begins_with("combat:timeout:"), "review: TIMEOUT settlement lost its audit marker")
		var resumed: GameSession = GameSession.new()
		resumed.configure_save_directory("user://test-saves/review-timeout")
		check(resumed.load_saved_game() and resumed.state.run.phase == "DEFEATED", "review: settled TIMEOUT did not survive reload")

func _test_transport_loadout_and_road() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://test-saves/review-transport")
	if not check(session.start_new_game(1762900000703), "review: could not create a transport profile"):
		return
	var catalog: ItemCatalog = ItemCatalog.new()
	if not check(bool(catalog.load_catalog().get("ok", false)), "review: transport item catalog unavailable"):
		return
	var specs: Array[Dictionary] = [
		{"templateId": "TR_ENGINE_2", "slot": "ENGINE"},
		{"templateId": "TR_CHASSIS_2", "slot": "CHASSIS"},
		{"templateId": "TR_CARGO_2", "slot": "CARGO"},
		{"templateId": "TR_SCANNER_2", "slot": "SCANNER"},
		{"templateId": "TR_SERVICE_2", "slot": "SERVICE"},
		{"templateId": "TR_SUPPORT_2", "slot": "SUPPORT"},
	]
	var inventory_payload: Dictionary = session.state.to_payload()
	var item_ids: Dictionary = {}
	for index: int in range(specs.size()):
		var spec: Dictionary = specs[index]
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed("review-transport", str(spec["templateId"]))
		var created: Dictionary = ItemFactory.new().create_item(rng, catalog, {
			"templateId": spec["templateId"], "techLevel": 1, "rarity": "COMMON", "secured": true,
			"originGrantId": "review-transport:%d" % index, "origin": "test", "acquiredAt": 0,
		})
		if not check(bool(created.get("ok", false)), "review: could not create %s: %s" % [spec["templateId"], created.get("error", "")]):
			return
		var item: Dictionary = (created["item"] as ItemInstance).to_dictionary()
		inventory_payload["meta"]["inventory"].append(item)
		item_ids[str(spec["slot"])] = str(item.get("itemId", ""))
	if not check(session._commit_payload(inventory_payload), "review: could not store the transport fixtures: %s" % session.last_error):
		return
	for spec: Dictionary in specs:
		var slot: String = str(spec["slot"])
		var item_id: String = str(item_ids[slot])
		check(session.valid_equipment_slots(item_id).has(slot), "review: slot %s not offered for the correct transport item" % slot)
		if not check(session.equip_item(slot, item_id), "review: cannot equip transport slot %s: %s" % [slot, session.last_error]):
			return
		check(session.equipped_slot(item_id) == slot, "review: transport equipment failed to persist for %s" % slot)
	var stats: Dictionary = session.build_preview().get("stats", {})
	check(is_equal_approx(float(stats.get("fuelMax", 0.0)), 32.0), "review: engine fuelMax was not built")
	check(is_equal_approx(float(stats.get("hullMax", 0.0)), 130.0), "review: chassis hullMax was not built")
	check(is_equal_approx(float(stats.get("cargoUnits", 0.0)), 32.0), "review: cargo capacity was not built")
	check(is_equal_approx(float(stats.get("travelDurationLess", 0.0)), 10.0), "review: engine travel duration was not built")
	check(is_equal_approx(float(stats.get("scanRange", 0.0)), 1.0), "review: scanner bonus was not built")
	if not check(session.start_expedition("review-transport"), "review: could not start upgraded transport expedition: %s" % session.last_error):
		return
	check(is_equal_approx(float(session.state.run.resources.get("maxFuel", 0.0)), 32.0), "review: expedition ignored engine fuel capacity")
	check(is_equal_approx(float(session.state.run.resources.get("fuel", 0.0)), 32.0), "review: upgraded fuel tank was not filled")
	check(is_equal_approx(float(session.state.run.resources.get("maxHull", 0.0)), 130.0), "review: expedition ignored chassis capacity")
	check(is_equal_approx(float(session.state.run.resources.get("hull", 0.0)), 130.0), "review: upgraded chassis did not start intact")
	var cargo_probe: Dictionary = session.state.run.to_dictionary()
	cargo_probe["unsecuredCargo"] = []
	for item_index: int in range(25):
		cargo_probe["unsecuredCargo"].append({"templateId": "PISTOL_K1"})
	check(session._cargo_fits(cargo_probe, {"templateId": "PISTOL_K1"}), "review: 26 cargo units did not fit the upgraded 32-unit hold")
	for item_index: int in range(7):
		cargo_probe["unsecuredCargo"].append({"templateId": "PISTOL_K1"})
	check(not session._cargo_fits(cargo_probe, {"templateId": "PISTOL_K1"}), "review: over-capacity load was accepted")
	var intel: Dictionary = session.route_intel()
	var seen_distance_two: bool = false
	var queue: Array[Dictionary] = session.reachable_nodes()
	if not check(not queue.is_empty(), "review: transport sortie had no reachable first node"):
		return
	var destination: String = str(queue[0].get("id", ""))
	var payload: Dictionary = session.state.to_payload()
	payload["run"]["pendingTravelDeltaMs"] = 15000
	if not check(session._commit_payload(payload), "review: could not prepare pending event travel delta"):
		return
	var before_time: float = float(session.state.run.resources.get("gameTimeMs", 0.0))
	if check(session.travel_to(destination), "review: event-modified transport trip failed: %s" % session.last_error):
		check(is_equal_approx(float(session.state.run.resources.get("gameTimeMs", 0.0)) - before_time, 37500.0), "review: engine speed or +15s event delay was ignored")
		check(int(session.state.run.pending_travel_delta_ms) == 0, "review: event travel modifier was not consumed")
	# The native scanner gives one additional distance layer without changing INTEL level.
	for entry: Variant in intel.get("nodes", {}).values():
		if entry is Dictionary and bool(entry.get("revealed", false)):
			seen_distance_two = true
	check(seen_distance_two, "review: scanner did not reveal any route intelligence")

func _test_drone_damage_modifiers() -> void:
	var factory: CombatFactory = CombatFactory.new()
	var drone_spec: Dictionary = {
		"itemId": "review-drone", "templateId": "DR_GUN", "damage": 20.0,
		"hp": 100.0, "shield": 0.0, "intervalMs": 1000.0, "type": "KINETIC",
	}
	var base_actor: CombatActorState = factory._create_drone({"stats": {"droneDamage": 0.0, "moreDrone": 1.0}}, drone_spec, 0, {})
	var boosted_actor: CombatActorState = factory._create_drone({"stats": {"droneDamage": 25.0, "moreDrone": 1.2}}, drone_spec, 0, {})
	var sim: CombatSimulator = CombatSimulator.new()
	var normal: float = sim._outgoing_multiplier(base_actor.base_sheet, "KINETIC", false, true)
	var boosted: float = sim._outgoing_multiplier(boosted_actor.base_sheet, "KINETIC", false, true)
	check(is_equal_approx(normal, 1.0), "review: unbuffed drone multiplier changed unexpectedly")
	check(is_equal_approx(boosted, 1.5), "review: boosted drone did not apply additive and moreDrone modifiers")
	check(is_equal_approx(sim._outgoing_multiplier(boosted_actor.base_sheet, "KINETIC", false), 1.0), "review: drone-only multipliers leaked into ordinary weapon hits")

func _test_status_expire_filter() -> void:
	var state: CombatState = CombatState.new()
	state.operator = CombatActorState.new()
	state.operator.id = "operator"
	state.operator.side = "player"
	state.operator.kind = "operator"
	state.operator.base_sheet = StatMath.new().empty_sheet()
	state.operator.cooldowns["SK_EMP"] = 10000.0
	var enemy: CombatActorState = CombatActorState.new()
	enemy.id = "enemy:0"
	enemy.side = "enemy"
	enemy.base_sheet = StatMath.new().empty_sheet()
	state.enemies.append(enemy)
	state.build = {"triggerEffects": [{
		"sourceId": "U17", "sourceKind": "item",
		"effect": {
			"id": "U17_cd", "event": "ON_STATUS_EXPIRE", "statusFilter": ["JAM"],
			"action": {"kind": "reduceCooldown", "skillId": "SK_EMP", "amountMs": 2000},
		},
	}]}
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("review", "status-expire")
	var sim: CombatSimulator = CombatSimulator.new()
	sim._dispatch_authored_event(state, rng, "ON_STATUS_EXPIRE", state.operator, enemy, "bleed-expired", 0, "", "", false, 1.0, 0.0, "BLEED")
	check(is_equal_approx(float(state.operator.cooldowns["SK_EMP"]), 10000.0), "review: a BLEED expiry incorrectly triggered the JAM-only unique")
	sim._dispatch_authored_event(state, rng, "ON_STATUS_EXPIRE", state.operator, enemy, "jam-expired", 0, "", "", false, 1.0, 0.0, "JAM")
	check(is_equal_approx(float(state.operator.cooldowns["SK_EMP"]), 8000.0), "review: the JAM expiry did not trigger U17 cooldown reduction")
