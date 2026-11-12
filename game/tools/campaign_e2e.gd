extends SceneTree

const MAX_NODE_STEPS: int = 1600
const MAX_COMBAT_TICKS: int = 3600

func _initialize() -> void:
	call_deferred("_run_campaign")

func _run_campaign() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://campaign-e2e")
	var resume_existing: bool = OS.get_cmdline_user_args().has("--resume")
	if resume_existing:
		if not session.load_saved_game() or session.state == null or session.state.run == null:
			_fail("Не удалось продолжить сохранённую кампанию: %s" % session.last_error)
			return
		print("E2E resume d%d phase=%s activeCombat=%s" % [session.state.run.depth, session.state.run.phase, str(session.has_active_combat())])
	else:
		if not session.start_new_game(1762900001001):
			_fail("Не удалось создать стартовый профиль: %s" % session.last_error)
			return
		# Keep the authored starter skills, but focus its existing group burst on healers.
		if not session.set_tactic_rule_target("starter-burst", "healer"):
			_fail("Не удалось настроить правило фокусировки SK_BURST на лекаре: %s" % session.last_error)
			return
	var sector_attempts: Dictionary = {}
	var prepared_gate_depths: Dictionary = {}
	var secured_boss_depths: Dictionary = {}
	var processed_nodes: int = 0
	var seed_index: int = 3 if resume_existing else 0
	if resume_existing and int(session.state.meta.unlocked_forpost) < 4:
		sector_attempts[1] = 3
	while int(session.state.meta.unlocked_forpost) < 12 and processed_nodes < MAX_NODE_STEPS:
		if session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
			var next_depth: int = int(session.state.meta.unlocked_forpost) + 1
			if session.state.run != null and ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
				print("E2E terminal d%d phase=%s hp=%d hull=%d fuel=%d error=%s" % [session.state.run.depth, session.state.run.phase, int(session.state.run.resources.get("hp", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.run.resources.get("fuel", 0)), session.last_error])
			sector_attempts[next_depth] = int(sector_attempts.get(next_depth, 0)) + 1
			seed_index += 1
			if int(sector_attempts[next_depth]) > 8:
				_fail("Акт с открытым сектором %d не пройден за восемь выездов." % next_depth)
				return
			if int(sector_attempts[next_depth]) > 1 and not _prepare_garage(session):
				_fail("Не удалось применить найденные улучшения в гараже: %s" % session.last_error)
				return
			if not session.start_expedition("campaign-e2e:%d:%d" % [next_depth, seed_index]):
				_fail("Не удалось начать сектор %d: %s" % [next_depth, session.last_error])
				return
			print("E2E start d%d try%d fuel=%d hull=%d credits=%d" % [next_depth, int(sector_attempts[next_depth]), int(session.state.run.resources.get("fuel", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.meta.protected_bank.credits)])
		match session.state.run.phase:
			"ROUTE":
				var target: Dictionary = _choose_node(session)
				if target.is_empty():
					_fail("Нет доступного перехода в секторе %d, слой узла %s, топливо %d; маршруты: %s" % [session.state.run.depth, str(session.state.run.current_node_id), int(session.state.run.resources.get("fuel", 0)), _route_diagnostics(session)])
					return
				if not session.travel_to(str(target.get("id", ""))):
					_fail("Переход отклонён в секторе %d: %s" % [session.state.run.depth, session.last_error])
					return
				print("E2E route d%d -> %s (%s), fuel=%d" % [session.state.run.depth, str(target.get("id", "")), str(target.get("type", "")), int(session.state.run.resources.get("fuel", 0))])
				processed_nodes += 1
			"NODE":
				if not _resolve_node(session):
					_fail("Узел %s не разрешён: %s" % [str(session.current_node().get("id", "")), session.last_error])
					return
				processed_nodes += 1
			"CHECKPOINT":
				var depth: int = int(session.state.run.depth)
				if depth % 4 == 3 and not prepared_gate_depths.has(depth + 1):
					prepared_gate_depths[depth + 1] = true
					if not session.extract_run():
						_fail("Не удалось закрепить добычу перед боссом d%d: %s" % [depth + 1, session.last_error])
						return
					print("E2E farm checkpoint d%d: secured loot and XP before replaying act" % depth)
					continue
				if depth in [4, 8] and not secured_boss_depths.has(depth):
					secured_boss_depths[depth] = true
					if not session.extract_run():
						_fail("Не удалось закрепить добычу после босса d%d: %s" % [depth, session.last_error])
						return
					print("E2E boss checkpoint d%d: secured boss rewards" % depth)
					continue
				if depth == 12 and not session.state.meta.campaign_flags.has("ENDING_SELECTED"):
					if not session.resolve_campaign_ending("FREE_CORRIDOR"):
						_fail("Не удалось зафиксировать финал кампании: %s" % session.last_error)
						return
					if not session.continue_campaign():
						_fail("Не удалось открыть эндгейм: %s" % session.last_error)
						return
					if session.state.run.depth != 13 or not session.state.meta.campaign_flags.has("CAMPAIGN_COMPLETED"):
						_fail("Кампания не перешла в сектор 13 после финала.")
						return
					print("PASS campaign E2E: d1–d12 cleared, ending recorded, d13 unlocked; nodes=%d" % processed_nodes)
					quit(0)
					return
				if not session.continue_campaign():
					_fail("Не удалось перейти из checkpoint d%d: %s" % [depth, session.last_error])
					return
			"EXTRACTED", "DEFEATED", "ABANDONED", "TOWED":
				print("E2E terminal d%d phase=%s hp=%d hull=%d fuel=%d" % [session.state.run.depth, session.state.run.phase, int(session.state.run.resources.get("hp", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.run.resources.get("fuel", 0))])
				continue
			_:
				_fail("Неподдерживаемая фаза выезда: %s" % str(session.state.run.phase))
				return
	_fail("E2E превысил лимит узлов либо не достиг d12; последний сектор %d, фаза %s." % [session.state.run.depth, session.state.run.phase])

func _choose_node(session: GameSession) -> Dictionary:
	var choices: Array[Dictionary] = session.reachable_nodes()
	var intel: Dictionary = session.route_intel().get("nodes", {})
	var resources: Dictionary = session.state.run.resources
	var fuel: int = int(resources.get("fuel", 0))
	var best: Dictionary = {}
	var best_score: float = -INF
	for candidate: Dictionary in choices:
		var node_id: String = str(candidate.get("id", ""))
		var edge_cost: int = _edge_cost(session, node_id)
		if edge_cost > fuel:
			continue
		var known: Dictionary = intel.get(node_id, {})
		var node_type: String = str(known.get("type", "UNKNOWN"))
		var score: float = 0.0
		if node_type == "CHECKPOINT": score = 100.0
		elif node_type == "FUEL": score = 70.0
		elif node_type == "REPAIR":
			var hp_fraction: float = float(resources.get("hp", 0.0)) / maxf(1.0, float(resources.get("maxHP", 1.0)))
			var repair_needed: bool = float(resources.get("hull", 0.0)) <= 70.0 or hp_fraction <= 0.9
			score = (82.0 if int(session.state.run.depth) % 4 == 0 else 62.0) if repair_needed else 4.0
		elif node_type == "CACHE": score = 22.0
		elif node_type == "EVENT": score = 16.0
		elif node_type == "COMBAT": score = 10.0
		elif node_type == "SHOP": score = 32.0 if int(session.state.run.depth) <= 3 and float(session.state.run.wallet.credits) >= 40.0 else 2.0
		elif node_type in ["ELITE", "BOUNTY"]: score = -6.0
		if score > best_score or is_equal_approx(score, best_score) and node_id < str(best.get("id", "~")):
			best = candidate
			best_score = score
	return best

func _edge_cost(session: GameSession, node_id: String) -> int:
	for edge: Dictionary in session.state.run.graph.get("edges", []):
		if str(edge.get("from", "")) == str(session.state.run.current_node_id) and str(edge.get("to", "")) == node_id:
			return int(edge.get("fuelCost", 1))
	return 999

func _route_diagnostics(session: GameSession) -> String:
	var values: Array[String] = []
	var fuel: int = int(session.state.run.resources.get("fuel", 0))
	for candidate: Dictionary in session.reachable_nodes():
		var node_id: String = str(candidate.get("id", ""))
		var intel: Dictionary = session.route_intel().get("nodes", {}).get(node_id, {})
		values.append("%s:%s(cost=%d)" % [node_id, str(intel.get("type", "?")), _edge_cost(session, node_id)])
	return "fuel=%d [%s]" % [fuel, ", ".join(values)]

func _resolve_node(session: GameSession) -> bool:
	var node: Dictionary = session.current_node()
	var kind: String = str(node.get("type", ""))
	if kind in ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"]:
		if not session.has_active_combat() and not session.begin_combat():
			return false
		var ticks: int = 0
		while session.combat_state() != null and session.combat_state().outcome.is_empty() and ticks < MAX_COMBAT_TICKS:
			if not session.advance_combat_step():
				return false
			ticks += 1
		if session.combat_state() == null or session.combat_state().outcome.is_empty():
			session.last_error = "Бой превысил %d тиков." % MAX_COMBAT_TICKS
			return false
		var combat: CombatState = session.combat_state()
		var enemies_left: Array[String] = []
		for enemy: CombatActorState in combat.enemies:
			enemies_left.append("%s %.0f/%.0f dealt=%.0f" % [enemy.template_id, enemy.hp, float(enemy.base_sheet.get("maxHP", 0.0)), enemy.damage_dealt])
		print("E2E combat d%d node=%s outcome=%s ticks=%d opHP=%.0f opDamage=%.0f opTaken=%.0f enemies=%s level=%d fuel=%d" % [session.state.run.depth, str(node.get("id", "")), combat.outcome, ticks, combat.operator.hp, combat.operator.damage_dealt, combat.operator.damage_taken, ",".join(enemies_left), session.state.meta.operator.level, int(session.state.run.resources.get("fuel", 0))])
		if kind == "BOSS":
			print("E2E boss metrics skills=%s interrupts=%d damageSources=%s takenSources=%s shieldAbsorbed=%.0f hpLost=%.0f ruleFailures=%s" % [str(combat.metrics.get("skillUses", {})), int(combat.metrics.get("interrupts", 0)), str(combat.metrics.get("damageBySource", {})), str(combat.metrics.get("takenBySource", {})), float(combat.metrics.get("shieldAbsorbed", 0.0)), float(combat.metrics.get("hpLost", 0.0)), str(combat.metrics.get("ruleFailures", []))])
		return session.resolve_active_combat()
	if kind == "EVENT":
		var event: Dictionary = session.current_event()
		for choice: Dictionary in event.get("choices", []):
			if session.resolve_event(str(choice.get("id", ""))):
				return true
		return session.resolve_service_node("LEAVE_NODE")
	if kind == "CACHE":
		var options: Array = node.get("prototypeChoices", [])
		var prototype: String = "IMP_SHIELD" if options.has("IMP_SHIELD") else str(options[0]) if not options.is_empty() else ""
		return session.resolve_service_node("OPEN_CACHE", prototype)
	if kind == "FUEL":
		return session.resolve_service_node("BUY_FUEL") or session.resolve_service_node("SCRAP_FUEL") or session.resolve_service_node("LEAVE_NODE")
	if kind == "REPAIR":
		return session.resolve_service_node("REPAIR_HULL") or session.resolve_service_node("REPAIR_HP") or session.resolve_service_node("LEAVE_NODE")
	if kind == "SHOP":
		var catalog: ItemCatalog = ItemCatalog.new()
		if bool(catalog.load_catalog().get("ok", false)):
			var offers: Array[Dictionary] = session.shop_offers()
			for index: int in range(offers.size()):
				var item: Dictionary = offers[index].get("item", {})
				var template: Dictionary = catalog.get_template(str(item.get("templateId", "")))
				if str(template.get("category", "")) == "MAIN" and session.buy_shop_item(index):
					break
		return session.resolve_service_node("LEAVE_NODE")
	return session.resolve_service_node("LEAVE_NODE")

func _prepare_garage(session: GameSession) -> bool:
	var catalog: ItemCatalog = ItemCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return false
	var current_slots: Array[String] = ["MAIN", "ARMOR", "OFFHAND", "DRONE_1", "IMP_1", "IMP_2", "IMP_3", "IMP_4"]
	for slot: String in current_slots:
		var current_id: String = str(session.state.meta.equipment.get(slot, ""))
		var expected_category: String = "IMPLANT" if slot.begins_with("IMP_") else slot
		var current_rank: int = 0
		for item: Dictionary in session.state.meta.inventory:
			if str(item.get("itemId", "")) == current_id:
				current_rank = _item_rank(item)
				break
		var candidates: Array[Dictionary] = []
		for item: Dictionary in session.state.meta.inventory:
			if not bool(item.get("secured", false)) or str(item.get("itemId", "")) == current_id:
				continue
			var template: Dictionary = catalog.get_template(str(item.get("templateId", "")))
			if str(template.get("category", "")) == expected_category and _item_rank(item) > current_rank and session.valid_equipment_slots(str(item.get("itemId", ""))).has(slot):
				candidates.append(item)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _item_rank(a) > _item_rank(b))
		for item: Dictionary in candidates:
			if session.equip_item(slot, str(item.get("itemId", ""))):
				current_rank = _item_rank(item)
				break
	if session.tree_points_available() > 0 and not session.state.meta.tree_node_ids.has("K1A"):
		session.set_tree_node_allocated("K1A", true)
	var equipped_ids: Array[String] = []
	for item_id: Variant in session.state.meta.equipment.values():
		equipped_ids.append(str(item_id))
	for item_id: String in equipped_ids:
		var item: Dictionary = session.state.meta.inventory.filter(func(value: Dictionary) -> bool: return str(value.get("itemId", "")) == item_id)[0]
		if float(item.get("durability", 100.0)) < 100.0:
			session.repair_item(item_id)
	return bool(session.build_preview().get("valid", false))

func _item_rank(item: Dictionary) -> int:
	var rarity_order: Dictionary = {"COMMON": 0, "MODIFIED": 1, "RARE": 2, "LEGENDARY": 3, "UNIQUE": 4}
	return int(item.get("techLevel", 0)) * 100 + int(rarity_order.get(str(item.get("rarity", "COMMON")), 0)) * 10 + roundi(float(item.get("durability", 0.0)) / 10.0)

func _fail(message: String) -> void:
	push_error("campaign E2E: " + message)
	quit(1)
