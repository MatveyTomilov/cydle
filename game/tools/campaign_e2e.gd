extends SceneTree

const MAX_NODE_STEPS: int = 1600
const MAX_COMBAT_TICKS: int = 3600

func _initialize() -> void:
	call_deferred("_run_campaign")

func _run_campaign() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://campaign-e2e-repro")
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
	var sector_attempts: Dictionary = {}
	var gate_farm_counts: Dictionary = {}
	var secured_boss_depths: Dictionary = {}
	var processed_nodes: int = 0
	var endgame_verified: bool = false
	var seed_index: int = 3 if resume_existing else 0
	var seed_nonce: String = str(Time.get_ticks_usec())
	if resume_existing and int(session.state.meta.max_sector_cleared) >= 6:
		sector_attempts[int(session.state.meta.unlocked_forpost) + 1] = 1
	if resume_existing and int(session.state.meta.unlocked_forpost) < 4:
		sector_attempts[1] = 3
	while (not session.state.meta.campaign_flags.has("CAMPAIGN_COMPLETED") or not endgame_verified or (session.state.run != null and session.state.run.depth == 12 and session.state.run.phase == "CHECKPOINT" and not session.state.meta.campaign_flags.has("ENDING_SELECTED"))) and processed_nodes < MAX_NODE_STEPS:
		if session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
			var next_depth: int = int(session.state.meta.unlocked_forpost) + 1
			if session.state.run != null and ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
				print("E2E terminal d%d phase=%s hp=%d hull=%d fuel=%d error=%s" % [session.state.run.depth, session.state.run.phase, int(session.state.run.resources.get("hp", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.run.resources.get("fuel", 0)), session.last_error])
				if session.state.run.phase == "DEFEATED" and session.state.run.depth % 4 == 0:
					gate_farm_counts.erase(session.state.run.depth)
			sector_attempts[next_depth] = int(sector_attempts.get(next_depth, 0)) + 1
			seed_index += 1
			if int(sector_attempts[next_depth]) > 20:
				_fail("Акт с открытым сектором %d не пройден за двадцать выездов." % next_depth)
				return
			if int(sector_attempts[next_depth]) > 1 and not _prepare_garage(session):
				_fail("Не удалось применить найденные улучшения в гараже: %s" % session.last_error)
				return
			var expedition_seed: String = "campaign-e2e:%d:%d" % [next_depth, seed_index]
			if resume_existing or seed_index > 1:
				expedition_seed += ":%s" % seed_nonce
			if not session.start_expedition(expedition_seed):
				_fail("Не удалось начать сектор %d: %s" % [next_depth, session.last_error])
				return
			print("E2E start d%d try%d fuel=%d hull=%d credits=%d" % [next_depth, int(sector_attempts[next_depth]), int(session.state.run.resources.get("fuel", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.meta.protected_bank.credits)])
		match session.state.run.phase:
			"ROUTE":
				var target: Dictionary = _choose_node(session)
				if target.is_empty():
					var emergency: Dictionary = session.emergency_exit_quote()
					if bool(emergency.get("valid", false)):
						var emergency_ok: bool = session.call_evacuation_tow() if bool(emergency.get("towAffordable", false)) else session.abandon_run()
						if not emergency_ok:
							_fail("Нет топлива для перехода, аварийный выход не завершился в секторе %d: %s; маршруты: %s" % [session.state.run.depth, session.last_error, _route_diagnostics(session)])
							return
						print("E2E emergency d%d phase=%s report=%s" % [session.state.run.depth, session.state.run.phase, str(session.last_emergency_report)])
						processed_nodes += 1
						continue
					_fail("Нет доступного перехода в секторе %d, слой узла %s, топливо %d; аварийный выход недоступен: %s; маршруты: %s" % [session.state.run.depth, str(session.state.run.current_node_id), int(session.state.run.resources.get("fuel", 0)), str(emergency.get("error", "нет причины")), _route_diagnostics(session)])
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
				if depth >= 13 and session.state.meta.campaign_flags.has("CAMPAIGN_COMPLETED"):
					endgame_verified = true
					print("PASS campaign and endgame E2E: d1–d12 cleared, ending recorded, d13 route and checkpoint played; nodes=%d" % processed_nodes)
					quit(0)
					return
				var boss_depth: int = depth + 1
				var farm_count: int = int(gate_farm_counts.get(boss_depth, 0))
				var required_farms: int = 1
				if depth % 4 == 3 and farm_count < required_farms:
					gate_farm_counts[boss_depth] = farm_count + 1
					if not session.extract_run():
						_fail("Не удалось закрепить добычу перед боссом d%d: %s" % [boss_depth, session.last_error])
						return
					print("E2E farm checkpoint d%d: secured loot and XP (%d/%d) before boss d%d" % [depth, farm_count + 1, required_farms, boss_depth])
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
					print("E2E ending recorded; playing the first endgame route through its checkpoint.")
					continue
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
		if session.combat_state() == null and session.state.run.cleared_node_ids.has(str(node.get("id", ""))):
			print("E2E combat d%d node=%s skipped by an authored one-time effect; no loot or XP awarded." % [session.state.run.depth, str(node.get("id", ""))])
			return true
		var ticks: int = 0
		while session.combat_state() != null and session.combat_state().outcome.is_empty() and ticks < MAX_COMBAT_TICKS:
			if not session.advance_combat_step():
				return false
			ticks += 1
		if session.combat_state() == null or session.combat_state().outcome.is_empty():
			if session.combat_state() != null:
				var stalled_combat: CombatState = session.combat_state()
				var stalled_enemies: Array[String] = []
				for enemy: CombatActorState in stalled_combat.enemies:
					stalled_enemies.append("%s %.0f/%.0f" % [enemy.template_id, enemy.hp, float(enemy.base_sheet.get("maxHP", 0.0))])
				print("E2E combat stalled d%d node=%s ticks=%d opHP=%.0f opDamage=%.0f enemies=%s metrics=%s" % [session.state.run.depth, str(node.get("id", "")), ticks, stalled_combat.operator.hp, stalled_combat.operator.damage_dealt, ",".join(stalled_enemies), str(stalled_combat.metrics)])
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
		print("E2E garage rejected: item catalog")
		return false
	var current_slots: Array[String] = ["MAIN", "ARMOR", "OFFHAND", "DRONE_1", "IMP_1", "IMP_2", "IMP_3", "IMP_4"]
	if session.state.meta.unlocked_drone_slots < 2:
		var hangar_quote: Dictionary = session.garage_upgrade_quote("HANGAR")
		if bool(hangar_quote.get("valid", false)) and bool(hangar_quote.get("affordable", false)):
			if not session.upgrade_garage_object("HANGAR"):
				print("E2E hangar upgrade rejected: %s" % session.last_error)
				return false
			print("E2E unlocked the second drone through the d6 HANGAR L2 progression gate")
	if session.state.meta.unlocked_drone_slots >= 2:
		current_slots.append("DRONE_2")
	for slot: String in current_slots:
		var current_id: String = str(session.state.meta.equipment.get(slot, ""))
		var expected_category: String = "IMPLANT" if slot.begins_with("IMP_") else "DRONE" if slot.begins_with("DRONE_") else slot
		var current_rank: int = 0
		var current_template_id: String = ""
		var current_tech_level: int = 0
		var current_weapon_type: String = ""
		for item: Dictionary in session.state.meta.inventory:
			if str(item.get("itemId", "")) == current_id:
				current_rank = _item_rank(item)
				current_template_id = str(item.get("templateId", ""))
				current_tech_level = int(item.get("techLevel", 1))
				current_weapon_type = str(catalog.get_template(str(item.get("templateId", ""))).get("weapon", {}).get("type", ""))
				break
		var candidates: Array[Dictionary] = []
		for item: Dictionary in session.state.meta.inventory:
			if not bool(item.get("secured", false)) or str(item.get("itemId", "")) == current_id:
				continue
			var item_id: String = str(item.get("itemId", ""))
			var equipped_elsewhere: bool = false
			for equipped_slot_value: Variant in session.state.meta.equipment.keys():
				var equipped_slot: String = str(equipped_slot_value)
				if equipped_slot != slot and str(session.state.meta.equipment.get(equipped_slot, "")) == item_id:
					equipped_elsewhere = true
					break
			if equipped_elsewhere:
				continue
			var template: Dictionary = catalog.get_template(str(item.get("templateId", "")))
			var candidate_type: String = str(template.get("weapon", {}).get("type", ""))
			var is_compatible_kinetic: bool = slot == "MAIN" and candidate_type == "KINETIC" and current_weapon_type != "KINETIC" and _item_rank(item) >= current_rank - 15
			var preferred_rifle: bool = slot == "MAIN" and str(template.get("id", "")) == "RIFLE_K2" and int(item.get("techLevel", 1)) >= 3 and current_template_id != "RIFLE_K2" and _item_rank(item) >= current_rank - 15
			var preferred_heavy_armor: bool = slot == "ARMOR" and str(template.get("id", "")) == "ARM_HEAVY" and current_template_id != "ARM_HEAVY" and int(item.get("techLevel", 1)) >= maxi(1, current_tech_level - 1)
			var preserve_heavy_armor: bool = slot == "ARMOR" and current_template_id == "ARM_HEAVY" and str(template.get("id", "")) != "ARM_HEAVY" and _item_rank(item) <= current_rank + 100
			var preserve_test_rifle: bool = slot == "MAIN" and current_template_id == "RIFLE_K2" and current_tech_level >= 3 and str(template.get("id", "")) != "RIFLE_K2" and _item_rank(item) <= current_rank + 15
			var ranked_upgrade: bool = _item_rank(item) > current_rank and not preserve_test_rifle and not preserve_heavy_armor
			if str(template.get("category", "")) == expected_category and (ranked_upgrade or is_compatible_kinetic or preferred_rifle or preferred_heavy_armor):
				candidates.append(item)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if slot == "ARMOR":
				var a_heavy: bool = str(catalog.get_template(str(a.get("templateId", ""))).get("id", "")) == "ARM_HEAVY"
				var b_heavy: bool = str(catalog.get_template(str(b.get("templateId", ""))).get("id", "")) == "ARM_HEAVY"
				if a_heavy != b_heavy:
					return a_heavy
			if slot == "MAIN":
				var a_template: Dictionary = catalog.get_template(str(a.get("templateId", "")))
				var b_template: Dictionary = catalog.get_template(str(b.get("templateId", "")))
				var a_kinetic: bool = str(a_template.get("weapon", {}).get("type", "")) == "KINETIC"
				var b_kinetic: bool = str(b_template.get("weapon", {}).get("type", "")) == "KINETIC"
				if a_kinetic != b_kinetic:
					return a_kinetic
				var a_rifle: bool = str(a_template.get("id", "")) == "RIFLE_K2" and int(a.get("techLevel", 1)) >= 3
				var b_rifle: bool = str(b_template.get("id", "")) == "RIFLE_K2" and int(b.get("techLevel", 1)) >= 3
				if a_rifle != b_rifle:
					return a_rifle
			if slot.begins_with("DRONE_"):
				var a_role: String = str(catalog.get_template(str(a.get("templateId", ""))).get("drone", {}).get("role", ""))
				var b_role: String = str(catalog.get_template(str(b.get("templateId", ""))).get("drone", {}).get("role", ""))
				var role_priority: Dictionary = {"bulwark": 3, "medic": 2, "emp": 1}
				var a_role_priority: int = int(role_priority.get(a_role, 0))
				var b_role_priority: int = int(role_priority.get(b_role, 0))
				if a_role_priority != b_role_priority:
					return a_role_priority > b_role_priority
			return _item_rank(a) > _item_rank(b)
		)
		for item: Dictionary in candidates:
			if session.equip_item(slot, str(item.get("itemId", ""))):
				current_rank = _item_rank(item)
				break
			if slot == "MAIN":
				print("E2E main candidate rejected template=%s T%d rarity=%s error=%s" % [str(item.get("templateId", "")), int(item.get("techLevel", 1)), str(item.get("rarity", "COMMON")), session.last_error])
	var campaign_tree: Array[String] = ["S1A", "S1B", "S2C", "S1C", "K1A", "K1B", "K2A", "K1C", "K2B", "K3A"]
	for node_id: String in session.state.meta.tree_node_ids.duplicate():
		if session.state.meta.tree_node_ids.has(node_id) and not campaign_tree.has(node_id) and not session.set_tree_node_allocated(node_id, false):
			print("E2E garage rejected: tree removal %s error=%s" % [node_id, session.last_error])
			return false
	for node_id: String in campaign_tree:
		if session.tree_points_available() <= 0:
			break
		if not session.state.meta.tree_node_ids.has(node_id) and not session.set_tree_node_allocated(node_id, true):
			print("E2E garage rejected: tree allocation %s error=%s" % [node_id, session.last_error])
			return false
	while session.attribute_points_available() > 0:
		if not session.allocate_attribute("POW"):
			print("E2E garage rejected: attribute allocation error=%s" % session.last_error)
			return false
	if not session.state.meta.passive_ids.has("PP_AMMO") and not session.set_passive_equipped("PP_AMMO", true):
		print("E2E garage rejected: main-damage protocol error=%s" % session.last_error)
		return false
	var equipped_ids: Array[String] = []
	for item_id: Variant in session.state.meta.equipment.values():
		equipped_ids.append(str(item_id))
	for item_id: String in equipped_ids:
		var item: Dictionary = session.state.meta.inventory.filter(func(value: Dictionary) -> bool: return str(value.get("itemId", "")) == item_id)[0]
		if float(item.get("durability", 100.0)) < 100.0 and not _repair_with_secured_scrap(session, item_id):
			print("E2E garage could not repair %s: %s" % [item_id, session.last_error])
	if not _prepare_boss_tactic(session):
		print("E2E garage rejected: final tactic setup error=%s skills=%s rules=%s" % [session.last_error, str(session.state.meta.skill_ids), str(session.state.meta.tactics)])
		return false
	var build: Dictionary = session.build_preview()
	var stats: Dictionary = build.get("stats", {})
	print("E2E garage stats HP=%.0f shield=%.0f armor=%.0f tree=%s" % [float(stats.get("maxHP", 0.0)), float(stats.get("maxShield", 0.0)), float(stats.get("armor", 0.0)), ",".join(session.state.meta.tree_node_ids)])
	var main_id: String = str(session.state.meta.equipment.get("MAIN", ""))
	for item: Dictionary in session.state.meta.inventory:
		if str(item.get("itemId", "")) == main_id:
			print("E2E garage build level=%d POW=%d main=%s T%d rank=%d" % [session.state.meta.operator.level, int(session.state.meta.operator.attributes.get("POW", 5)), str(item.get("templateId", "")), int(item.get("techLevel", 1)), _item_rank(item)])
			break
	return bool(build.get("valid", false))

func _repair_with_secured_scrap(session: GameSession, item_id: String) -> bool:
	while not session.repair_item(item_id):
		if not session.last_error.contains("SCRAP"):
			return false
		var dismantle_id: String = _lowest_safe_dismantle_candidate(session)
		if dismantle_id.is_empty():
			return false
		var quote: Dictionary = session.item_disposal_quote(dismantle_id, "DISMANTLE")
		if not bool(quote.get("valid", false)) or int(quote.get("scrap", 0)) <= 0:
			return false
		if not session.dismantle_item(dismantle_id):
			return false
		print("E2E garage dismantled low-rank duplicate %s for %d SCRAP" % [dismantle_id, int(quote.get("scrap", 0))])
	return true

func _lowest_safe_dismantle_candidate(session: GameSession) -> String:
	var catalog: ItemCatalog = ItemCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return ""
	var equipped_ids: Array[String] = []
	for value: Variant in session.state.meta.equipment.values():
		equipped_ids.append(str(value))
	var best_by_category: Dictionary = {}
	for item: Dictionary in session.state.meta.inventory:
		if not bool(item.get("secured", false)):
			continue
		var template: Dictionary = catalog.get_template(str(item.get("templateId", "")))
		var category: String = str(template.get("category", ""))
		var rank: int = _item_rank(item)
		best_by_category[category] = maxi(int(best_by_category.get(category, -1)), rank)
	var candidates: Array[Dictionary] = []
	for item: Dictionary in session.state.meta.inventory:
		var item_id: String = str(item.get("itemId", ""))
		if not bool(item.get("secured", false)) or equipped_ids.has(item_id):
			continue
		var template: Dictionary = catalog.get_template(str(item.get("templateId", "")))
		var category: String = str(template.get("category", ""))
		if _item_rank(item) >= int(best_by_category.get(category, _item_rank(item))):
			continue
		var quote: Dictionary = session.item_disposal_quote(item_id, "DISMANTLE")
		if bool(quote.get("valid", false)) and int(quote.get("scrap", 0)) > 0:
			candidates.append(item)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _item_rank(a) < _item_rank(b))
	return str(candidates[0].get("itemId", "")) if not candidates.is_empty() else ""

func _prepare_boss_tactic(session: GameSession) -> bool:
	var main_id: String = str(session.state.meta.equipment.get("MAIN", ""))
	var main_template: Dictionary = {}
	for item: Dictionary in session.state.meta.inventory:
		if str(item.get("itemId", "")) == main_id:
			var catalog: ItemCatalog = ItemCatalog.new()
			if not bool(catalog.load_catalog().get("ok", false)):
				return false
			main_template = catalog.get_template(str(item.get("templateId", "")))
			break
	if str(main_template.get("weapon", {}).get("type", "")) != "KINETIC":
		var auto_skill_ok: bool = session.set_tactic_rule_skill("starter-burst", "AUTO")
		var auto_condition_ok: bool = session.set_tactic_rule_condition("starter-burst", {"kind": "always"})
		return auto_skill_ok and auto_condition_ok
	if session.state.meta.skill_ids.has("SK_SHIELD") and not session.state.meta.skill_ids.has("SK_HEAL"):
		if not session.set_skill_equipped("SK_SHIELD", false):
			return false
	if session.state.meta.skill_ids.has("SK_GUARD") and not session.state.meta.skill_ids.has("SK_HEAL"):
		if not session.set_skill_equipped("SK_GUARD", false):
			return false
	if not session.state.meta.skill_ids.has("SK_HEAL") and not session.set_skill_equipped("SK_HEAL", true):
		return false
	if session.state.meta.skill_ids.has("SK_SHIELD"):
		if not session.set_skill_equipped("SK_SHIELD", false):
			return false
	if not session.state.meta.skill_ids.has("SK_EMP") and not session.set_skill_equipped("SK_EMP", true):
		return false
	for starter_skill: String in ["SK_BURST"]:
		if not session.state.meta.skill_ids.has(starter_skill) and not session.set_skill_equipped(starter_skill, true):
			return false
	return session.set_tactic_rule_skill("starter-shield", "SK_HEAL") and session.set_tactic_rule_target("starter-shield", "self") and session.set_tactic_rule_condition("starter-shield", {"kind": "hpBelow", "value": 0.75}) and session.set_tactic_rule_skill("starter-emp", "SK_EMP") and session.set_tactic_rule_target("starter-emp", "boss") and session.set_tactic_rule_condition("starter-emp", {"kind": "enemyCasting", "interruptibleOnly": true}) and session.set_tactic_rule_skill("starter-burst", "SK_BURST") and session.set_tactic_rule_target("starter-burst", "healer") and session.set_tactic_rule_condition("starter-burst", {"kind": "always"})

func _item_rank(item: Dictionary) -> int:
	var rarity_order: Dictionary = {"COMMON": 0, "MODIFIED": 1, "RARE": 2, "LEGENDARY": 3, "UNIQUE": 4}
	return int(item.get("techLevel", 0)) * 100 + int(rarity_order.get(str(item.get("rarity", "COMMON")), 0)) * 10 + roundi(float(item.get("durability", 0.0)) / 10.0)

func _fail(message: String) -> void:
	push_error("campaign E2E: " + message)
	quit(1)
