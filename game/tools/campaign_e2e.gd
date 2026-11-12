extends SceneTree

const MAX_NODE_STEPS: int = 1600
const MAX_COMBAT_TICKS: int = 3600

func _initialize() -> void:
	call_deferred("_run_campaign")

func _run_campaign() -> void:
	var session: GameSession = GameSession.new()
	session.configure_save_directory("user://campaign-e2e")
	if not session.start_new_game(1762900001001):
		_fail("Не удалось создать стартовый профиль: %s" % session.last_error)
		return
	var sector_attempts: Dictionary = {}
	var processed_nodes: int = 0
	var seed_index: int = 0
	while int(session.state.meta.unlocked_forpost) < 12 and processed_nodes < MAX_NODE_STEPS:
		if session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
			var next_depth: int = int(session.state.meta.unlocked_forpost) + 1
			if session.state.run != null and ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(session.state.run.phase):
				print("E2E terminal d%d phase=%s hp=%d hull=%d fuel=%d error=%s" % [session.state.run.depth, session.state.run.phase, int(session.state.run.resources.get("hp", 0)), int(session.state.run.resources.get("hull", 0)), int(session.state.run.resources.get("fuel", 0)), session.last_error])
			sector_attempts[next_depth] = int(sector_attempts.get(next_depth, 0)) + 1
			seed_index += 1
			if int(sector_attempts[next_depth]) > 1:
				_fail("Сектор %d не пройден за один диагностический выезд." % next_depth)
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
				processed_nodes += 1
			"NODE":
				if not _resolve_node(session):
					_fail("Узел %s не разрешён: %s" % [str(session.current_node().get("id", "")), session.last_error])
					return
				processed_nodes += 1
			"CHECKPOINT":
				var depth: int = int(session.state.run.depth)
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
		elif node_type == "REPAIR": score = 65.0 if float(resources.get("hull", 0.0)) <= 70.0 or float(resources.get("hp", 0.0)) <= float(resources.get("maxHP", 1.0)) * 0.55 else 4.0
		elif node_type == "CACHE": score = 22.0
		elif node_type == "EVENT": score = 16.0
		elif node_type == "COMBAT": score = 10.0
		elif node_type == "SHOP": score = 2.0
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
		if not session.begin_combat():
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
		return session.resolve_active_combat()
	if kind == "EVENT":
		var event: Dictionary = session.current_event()
		for choice: Dictionary in event.get("choices", []):
			if session.resolve_event(str(choice.get("id", ""))):
				return true
		return session.resolve_service_node("LEAVE_NODE")
	if kind == "CACHE":
		var options: Array = node.get("prototypeChoices", [])
		return session.resolve_service_node("OPEN_CACHE", str(options[0]) if not options.is_empty() else "")
	if kind == "FUEL":
		return session.resolve_service_node("BUY_FUEL") or session.resolve_service_node("SCRAP_FUEL") or session.resolve_service_node("LEAVE_NODE")
	if kind == "REPAIR":
		return session.resolve_service_node("REPAIR_HULL") or session.resolve_service_node("REPAIR_HP") or session.resolve_service_node("LEAVE_NODE")
	return session.resolve_service_node("LEAVE_NODE")

func _fail(message: String) -> void:
	push_error("campaign E2E: " + message)
	quit(1)
