class_name GameSession
extends RefCounted

const SLOT_ID: String = "cylde-main"

var state: GameSaveState
var last_error: String = ""
var combat_notice: String = ""
var _repository: SaveRepository = SaveRepository.new()
var _generator: SectorGenerator = SectorGenerator.new()
var _stats: StatMath = StatMath.new()
var _simulator: CombatSimulator = CombatSimulator.new()
var _combat: CombatState
var _active_node_type: String = ""
var _active_reward_modifiers: Dictionary = {}
var _item_catalog: ItemCatalog = ItemCatalog.new()
var _loot_rng: DeterministicRng

func configure_save_directory(path: String) -> void:
	_repository.configure_directory(path)

func load_saved_game() -> bool:
	var loaded: Dictionary = _repository.load_game(SLOT_ID)
	if bool(loaded.get("ok", false)):
		state = loaded["state"] as GameSaveState
		if state.run != null and state.run.combat_snapshot != null:
			if not _restore_combat_snapshot():
				return false
		last_error = ""
		return true
	if bool(loaded.get("empty", false)):
		state = null
		last_error = ""
		return false
	last_error = str(loaded.get("error", "Ошибка чтения сохранения."))
	return false

func start_new_game(now_ms: int = -1) -> bool:
	var timestamp: int = now_ms if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var save_id: String = "CYDLE-%d-%d" % [timestamp, Time.get_ticks_usec()]
	var initial: Dictionary = GameSaveFactory.new().create_initial_payload(save_id, timestamp)
	if not bool(initial.get("ok", false)):
		last_error = str(initial.get("error", "Не удалось создать профиль."))
		return false
	var parsed: Dictionary = GameSaveState.new().parse_payload(initial["payload"])
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Стартовый профиль не прошёл проверку."))
		return false
	return _commit(parsed["state"] as GameSaveState)

func save() -> bool:
	if state == null:
		last_error = "Нет активного профиля для сохранения."
		return false
	state.updated_at = int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = _repository.save_game(SLOT_ID, state, state.updated_at)
	if not bool(saved.get("ok", false)):
		last_error = str(saved.get("error", "Не удалось сохранить игру."))
		return false
	last_error = ""
	return true

func build_preview() -> Dictionary:
	if state == null:
		return {"valid": false, "issues": [{"message": "Нет активного профиля."}]}
	var items_by_id: Dictionary = {}
	for item_value: Dictionary in state.meta.inventory:
		items_by_id[str(item_value.get("itemId", ""))] = item_value
	var equipment: Dictionary = {}
	for slot_value: Variant in state.meta.equipment.keys():
		var item_value: Dictionary = items_by_id.get(str(state.meta.equipment[slot_value]), {})
		if item_value.is_empty():
			continue
		var item: ItemInstance = ItemInstance.new()
		if item.instantiate_from_dictionary(item_value):
			equipment[str(slot_value)] = item
	var operator: GameSaveState.OperatorState = state.meta.operator
	return BuildResolver.new().resolve_build({
		"equipment": equipment, "attributes": operator.attributes,
		"skillIds": state.meta.skill_ids, "passiveIds": state.meta.passive_ids,
		"treeNodeIds": state.meta.tree_node_ids,
		"mutationIds": state.run.temporary_mutation_ids if state.run != null else [],
		"attributePointsEarned": operator.attribute_points, "treePointsEarned": operator.tree_points,
		"unlockedImplantSlots": state.meta.unlocked_implant_slots,
		"unlockedDroneSlots": state.meta.unlocked_drone_slots,
	})

func attribute_points_available() -> int:
	if state == null:
		return 0
	var spent: int = 0
	for value: Variant in state.meta.operator.attributes.values():
		spent += maxi(0, int(value) - 5)
	return maxi(0, state.meta.operator.attribute_points - spent)

func allocate_attribute(attribute_id: String) -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if not ["POW", "REF", "INT", "ENG", "SYN"].has(attribute_id):
		last_error = "Неизвестный атрибут %s." % attribute_id
		return false
	if attribute_points_available() <= 0:
		last_error = "Нет свободных очков атрибутов."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Атрибуты можно распределять только в гараже между выездами."
		return false
	var payload: Dictionary = state.to_payload()
	var operator: Dictionary = payload["meta"]["operator"]
	var attributes: Dictionary = operator["attributes"]
	attributes[attribute_id] = int(attributes.get(attribute_id, 5)) + 1
	operator["attributes"] = attributes
	payload["meta"]["operator"] = operator
	if not _commit_payload(payload):
		return false
	var build: Dictionary = build_preview()
	if not bool(build.get("valid", false)):
		last_error = "Распределение отклонено BuildResolver: %s" % str(build.get("issues", []))
		return false
	return true

func respec_attributes() -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Перераспределение доступно только в гараже между выездами."
		return false
	var spent: int = 0
	for value: Variant in state.meta.operator.attributes.values():
		spent += maxi(0, int(value) - 5)
	if spent <= 0:
		last_error = "Нет распределённых очков для сброса."
		return false
	var cost: int = spent * 10
	if state.meta.protected_bank.credits < cost:
		last_error = "Для сброса требуется %d защищённых кредитов." % cost
		return false
	var payload: Dictionary = state.to_payload()
	var operator: Dictionary = payload["meta"]["operator"]
	operator["attributes"] = {"POW": 5, "REF": 5, "INT": 5, "ENG": 5, "SYN": 5}
	payload["meta"]["operator"] = operator
	payload["meta"]["protectedBank"]["CREDITS"] = float(payload["meta"]["protectedBank"].get("CREDITS", 0.0)) - float(cost)
	return _commit_payload(payload)

func set_skill_equipped(skill_id: String, equipped: bool) -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Активные умения меняются только в гараже между выездами."
		return false
	var catalog: BuildCatalog = BuildCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not bool(loaded.get("ok", false)) or not catalog.skills.has(skill_id):
		last_error = "Неизвестное умение %s." % skill_id
		return false
	var skill_ids: Array[String] = state.meta.skill_ids.duplicate()
	if equipped:
		if skill_ids.has(skill_id):
			last_error = "Умение уже установлено."
			return false
		if skill_ids.size() >= 3:
			last_error = "Доступны только три слота умений. Снимите одно умение перед заменой."
			return false
		skill_ids.append(skill_id)
	else:
		if not skill_ids.has(skill_id):
			last_error = "Умение не установлено."
			return false
		skill_ids.erase(skill_id)
	var payload: Dictionary = state.to_payload()
	payload["meta"]["skillIds"] = skill_ids
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Изменение слотов не прошло проверку."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Умение нельзя установить в эту сборку: %s" % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func set_passive_equipped(passive_id: String, equipped: bool) -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Пассивные протоколы меняются только в гараже между выездами."
		return false
	var catalog: BuildCatalog = BuildCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not bool(loaded.get("ok", false)) or not catalog.passives.has(passive_id):
		last_error = "Неизвестный пассивный протокол %s." % passive_id
		return false
	var passive_ids: Array[String] = state.meta.passive_ids.duplicate()
	if equipped:
		if passive_ids.has(passive_id):
			last_error = "Пассивный протокол уже установлен."
			return false
		if passive_ids.size() >= 3:
			last_error = "Доступны только три слота пассивных протоколов."
			return false
		passive_ids.append(passive_id)
	else:
		if not passive_ids.has(passive_id):
			last_error = "Пассивный протокол не установлен."
			return false
		passive_ids.erase(passive_id)
	var payload: Dictionary = state.to_payload()
	payload["meta"]["passiveIds"] = passive_ids
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Изменение пассивных слотов не прошло проверку."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Пассивный протокол нельзя установить в эту сборку: %s" % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func tree_points_available() -> int:
	if state == null:
		return 0
	return maxi(0, state.meta.operator.tree_points - state.meta.tree_node_ids.size())

func set_tree_node_allocated(node_id: String, allocated: bool) -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Дерево меняется только в гараже между выездами."
		return false
	var catalog: BuildCatalog = BuildCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not bool(loaded.get("ok", false)) or not catalog.tree_nodes.has(node_id):
		last_error = "Неизвестный узел дерева %s." % node_id
		return false
	var current_ids: Array[String] = state.meta.tree_node_ids.duplicate()
	if allocated:
		var resolver: BuildResolver = BuildResolver.new()
		var lock_reason: String = resolver.tree_node_lock_reason(node_id, current_ids, state.meta.operator.tree_points)
		if not lock_reason.is_empty():
			last_error = "%s: %s." % [node_id, lock_reason]
			return false
		current_ids.append(node_id)
		return _commit_tree_selection(current_ids, 0)
	if not current_ids.has(node_id):
		last_error = "Узел %s не изучен." % node_id
		return false
	current_ids.erase(node_id)
	var resolver: BuildResolver = BuildResolver.new()
	var removed_ids: Array[String] = [node_id]
	var validation: Dictionary = resolver.resolve_build(_build_input_with_tree(state, current_ids))
	while not bool(validation.get("valid", false)):
		var invalid_node: String = ""
		for issue_value: Variant in validation.get("issues", []):
			if issue_value is Dictionary and str(issue_value.get("code", "")) == "TREE_LOCKED":
				invalid_node = str(issue_value.get("sourceId", ""))
				break
		if invalid_node.is_empty() or not current_ids.has(invalid_node):
			last_error = "Нельзя снять узел: %s." % str(validation.get("issues", []))
			return false
		current_ids.erase(invalid_node)
		removed_ids.append(invalid_node)
		validation = resolver.resolve_build(_build_input_with_tree(state, current_ids))
	var respec_cost: int = removed_ids.size() * 10
	if state.meta.protected_bank.credits < float(respec_cost):
		last_error = "Для снятия %d узлов требуется %d защищённых кредитов." % [removed_ids.size(), respec_cost]
		return false
	return _commit_tree_selection(current_ids, respec_cost)

func _commit_tree_selection(tree_ids: Array[String], respec_cost: int) -> bool:
	var payload: Dictionary = state.to_payload()
	payload["meta"]["treeNodeIds"] = tree_ids
	payload["meta"]["protectedBank"]["CREDITS"] = float(payload["meta"]["protectedBank"].get("CREDITS", 0.0)) - float(respec_cost)
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Изменение дерева не прошло проверку сохранения."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Распределение дерева отклонено BuildResolver: %s" % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func _build_input_with_tree(save_state: GameSaveState, tree_ids: Array[String]) -> Dictionary:
	var input: Dictionary = _build_input(save_state)
	input["treeNodeIds"] = tree_ids
	return input

func start_expedition(seed_value: String = "", use_medical_restore: bool = false) -> bool:
	if state == null:
		last_error = "Сначала создайте или загрузите профиль."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Завершите текущий выезд перед началом следующего."
		return false
	var build: Dictionary = build_preview()
	if not bool(build.get("valid", false)):
		last_error = "Сборка не готова к выезду."
		return false
	var depth: int = maxi(1, state.meta.unlocked_forpost + 1)
	var medical_cost: int = ceili(8.0 * CydleFormula.new().reward_scale(float(depth))) if use_medical_restore else 0
	if use_medical_restore:
		if garage_level("GARAGE_MED") < 3:
			last_error = "Полное восстановление перед выездом требует GARAGE_MED уровня 3."
			return false
		if state.meta.protected_bank.credits < float(medical_cost):
			last_error = "Полное восстановление требует %d защищённых кредитов." % medical_cost
			return false
	var seed: String = seed_value.strip_edges()
	if seed.is_empty():
		seed = "%s:run:%d" % [state.save_id, int(Time.get_ticks_usec())]
	var biome: String = _generator.campaign_biome(depth, seed)
	var generated: Dictionary = _generator.generate(
		seed, depth, biome,
		depth == 1 and not bool(state.meta.tutorial.get("firstSectorCompleted", false)) and not bool(state.meta.tutorial.get("starterPrototypeSecured", false)),
		0.0,
	)
	if not bool(generated.get("ok", false)):
		last_error = str(generated.get("error", "Не удалось создать дорожную карту."))
		return false
	var world_rng: DeterministicRng = DeterministicRng.new()
	world_rng.seed("world", seed)
	var loot_rng: DeterministicRng = DeterministicRng.new()
	loot_rng.seed("loot", seed)
	var transport: GameSaveState.TransportState = state.meta.transport
	var stats: Dictionary = build.get("stats", {})
	var run_payload: Dictionary = {
		"seed": seed, "depth": depth, "biome": biome, "graph": generated["graph"],
		"equipment": state.meta.equipment.duplicate(true), "currentNodeId": "START",
		"visitedNodeIds": [], "clearedNodeIds": [], "eventsSeen": [], "phase": "ROUTE",
		"wanted": 0.0, "revealLevel": 1, "pendingTravelDeltaMs": 0,
		"pendingCombatEffects": {"initialTempShield": 0.0, "extraHeat": 0.0},
		"pendingNextCombat": {
			"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false,
			"bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false,
			"alliedTurret": false, "extraRareOnElite": false,
		},
		"resources": {
			"fuel": transport.fuel, "maxFuel": transport.fuel_max,
			"hull": transport.hull, "maxHull": transport.hull_max,
			"hp": float(stats.get("maxHP", 0.0)), "maxHP": float(stats.get("maxHP", 0.0)),
			"shield": float(stats.get("maxShield", 0.0)), "maxShield": float(stats.get("maxShield", 0.0)),
			"energy": float(stats.get("maxEnergy", 0.0)), "heat": 0.0, "gameTimeMs": 0.0,
		},
		"runWallet": {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0},
		"unsecuredCargo": [], "shippedCargo": [], "grantIds": [], "commandIds": [],
		"serviceScrapFuelCounts": {}, "shippedCheckpointIds": [], "combatResult": null, "lastCommandId": null,
		"worldRng": world_rng.serialize(), "lootRng": loot_rng.serialize(), "combatSnapshot": null,
	}
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	if use_medical_restore:
		payload["meta"]["protectedBank"]["CREDITS"] = float(payload["meta"]["protectedBank"].get("CREDITS", 0.0)) - float(medical_cost)
		run_payload["resources"]["hull"] = run_payload["resources"]["maxHull"]
		payload["run"] = run_payload
	return _commit_payload(payload)

func reachable_nodes() -> Array[Dictionary]:
	if state == null or state.run == null or state.run.phase != "ROUTE":
		return []
	return _generator.reachable_nodes(state.run.graph, state.run.current_node_id)

func travel_to(node_id: String) -> bool:
	if state == null or state.run == null or state.run.phase != "ROUTE":
		last_error = "Переход доступен только на карте дороги."
		return false
	var run_payload: Dictionary = state.run.to_dictionary()
	var edge: Dictionary = {}
	for edge_value: Dictionary in state.run.graph.get("edges", []):
		if str(edge_value.get("from", "")) == state.run.current_node_id and str(edge_value.get("to", "")) == node_id:
			edge = edge_value
			break
	if edge.is_empty():
		last_error = "Этот узел не соединён с текущей позицией."
		return false
	var cost: int = int(edge.get("fuelCost", 1))
	if float(run_payload["resources"].get("fuel", 0.0)) < cost:
		last_error = "Недостаточно топлива для выбранного маршрута."
		return false
	run_payload["resources"]["fuel"] = float(run_payload["resources"]["fuel"]) - cost
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"]["gameTimeMs"]) + 25000.0
	run_payload["currentNodeId"] = node_id
	run_payload["visitedNodeIds"].append(node_id)
	var target_node: Dictionary = {}
	for layer: Array in state.run.graph.get("layers", []):
		for node: Dictionary in layer:
			if str(node.get("id", "")) == node_id:
				target_node = node
				break
	if str(target_node.get("type", "")) == "CHECKPOINT":
		run_payload["phase"] = "CHECKPOINT"
		run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"].get("gameTimeMs", 0.0)) + 8000.0
	else:
		run_payload["phase"] = "NODE"
	run_payload["combatResult"] = null
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	return _commit_payload(payload)

func current_node() -> Dictionary:
	if state == null or state.run == null or str(state.run.current_node_id) == "START":
		return {}
	for layer_value: Variant in state.run.graph.get("layers", []):
		for node: Dictionary in layer_value:
			if str(node.get("id", "")) == state.run.current_node_id:
				return node.duplicate(true)
	return {}

func current_event() -> Dictionary:
	var node: Dictionary = current_node()
	if str(node.get("type", "")) != "EVENT":
		return {}
	return EventCatalog.new().get_event(str(node.get("eventId", "")))

func resolve_event(choice_id: String) -> bool:
	if state == null or state.run == null or state.run.phase != "NODE":
		last_error = "Выбор события доступен только в активном узле."
		return false
	var node: Dictionary = current_node()
	var node_id: String = str(node.get("id", ""))
	if str(node.get("type", "")) != "EVENT" or state.run.cleared_node_ids.has(node_id):
		last_error = "Текущий узел не является неразрешённым событием."
		return false
	var event: Dictionary = current_event()
	var choice: Dictionary = {}
	for candidate: Dictionary in event.get("choices", []):
		if str(candidate.get("id", "")) == choice_id:
			choice = candidate
			break
	if choice.is_empty():
		last_error = "Выбранный вариант отсутствует у этого события."
		return false
	var payload: Dictionary = state.to_payload()
	var meta: Dictionary = payload["meta"]
	var run_payload: Dictionary = payload["run"]
	var wallet: Dictionary = run_payload["runWallet"]
	var scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
	var costs: Dictionary = choice.get("cost", {}).duplicate(true)
	var special: String = str(choice.get("special", ""))
	if special == "dataForCredits":
		costs["DATA"] = ceili(10.0 * scale)
	if special == "greyDealer":
		costs["CREDITS"] = ceili((25.0 + 7.0 * state.run.depth) * 2.0 * scale * 0.6)
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		if float(wallet.get(currency, 0.0)) < float(costs.get(currency, 0.0)):
			last_error = "Для выбора недостаточно незакреплённых средств: %s." % currency
			return false
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var gain: float = float(choice.get("gains", {}).get(currency, 0.0))
		if bool(choice.get("scaled", false)):
			gain = ceili(gain * scale)
		if special == "dataForCredits" and currency == "CREDITS":
			gain = ceili(30.0 * scale)
		wallet[currency] = float(wallet.get(currency, 0.0)) - float(costs.get(currency, 0.0)) + gain
	var resources: Dictionary = run_payload["resources"]
	if choice.has("wanted"):
		run_payload["wanted"] = clampf(float(run_payload["wanted"]) + float(choice["wanted"]), 0.0, 100.0)
	if choice.has("travelDelta"):
		run_payload["pendingTravelDeltaMs"] = clampi(int(run_payload.get("pendingTravelDeltaMs", 0)) + int(choice["travelDelta"]), -60000, 60000)
	if choice.has("fuel"):
		resources["fuel"] = clampf(float(resources["fuel"]) + float(choice["fuel"]), 0.0, float(resources["maxFuel"]))
	if choice.has("hull"):
		resources["hull"] = clampf(float(resources["hull"]) + float(choice["hull"]), 0.0, float(resources["maxHull"]))
	if choice.has("healMissingFraction"):
		var hp: float = float(resources["hp"])
		resources["hp"] = minf(float(resources["maxHP"]), hp + (float(resources["maxHP"]) - hp) * float(choice["healMissingFraction"]))
	if bool(choice.get("refillEnergy", false)):
		var build: Dictionary = build_preview()
		if not bool(build.get("valid", false)):
			last_error = "Невозможно рассчитать энергию текущей сборки."
			return false
		resources["energy"] = float(build.get("stats", {}).get("maxEnergy", resources["maxEnergy"]))
	if choice.has("reputation"):
		for faction: Variant in choice["reputation"].keys():
			meta["reputation"][str(faction)] = clampi(int(meta["reputation"].get(str(faction), 0)) + int(choice["reputation"][faction]), -100, 100)
	var next_combat: Dictionary = choice.get("nextCombat", {})
	var pending_combat: Dictionary = run_payload["pendingCombatEffects"]
	pending_combat["initialTempShield"] = float(pending_combat.get("initialTempShield", 0.0)) + float(next_combat.get("shieldBonus", 0.0))
	pending_combat["extraHeat"] = float(pending_combat.get("extraHeat", 0.0)) + float(next_combat.get("extraHeat", 0.0))
	var pending_next: Dictionary = run_payload["pendingNextCombat"]
	if bool(next_combat.get("skip", false)): pending_next["skipOrdinary"] = true
	if bool(next_combat.get("forceElite", false)): pending_next["forceElite"] = true
	if bool(next_combat.get("forceBounty", false)): pending_next["forceBounty"] = true
	if bool(next_combat.get("alliedTurret", false)): pending_next["alliedTurret"] = true
	if bool(next_combat.get("extraRareRoll", false)):
		if str(event.get("id", "")) == "EV16": pending_next["extraItemRoll"] = true
		else: pending_next["extraRareItemRoll"] = true
	if next_combat.has("bountyCredits"):
		pending_next["bountyCreditsBonus"] = float(pending_next.get("bountyCreditsBonus", 0.0)) + float(next_combat["bountyCredits"])
	var flag: String = str(choice.get("flag", ""))
	if flag == "bountyE21":
		pending_next["bountyEnemyId"] = "E21"
		pending_next["extraRareItemRoll"] = true
	if flag == "huntElite": pending_next["extraRareOnElite"] = true
	if not flag.is_empty(): meta["campaignFlags"].append("event-flag:%s:%s" % [flag, node_id])
	var grant: Dictionary = choice.get("grantItem", {}).duplicate(true)
	if special == "greyDealer": grant["rarity"] = "RARE"
	var item_values: Array[Dictionary] = []
	if not grant.is_empty():
		var loot: DeterministicRng = DeterministicRng.new()
		loot.restore(run_payload["lootRng"])
		var grant_id: String = "event:%s:%s:%s" % [str(run_payload["seed"]), node_id, choice_id]
		var options: Dictionary = {"depth": state.run.depth, "biome": state.run.biome, "table": "ORDINARY", "secured": false, "grantId": grant_id, "origin": "event", "acquiredAt": state.updated_at}
		if grant.has("templateId"): options["forceTemplateId"] = grant["templateId"]
		if grant.has("category"): options["forceCategory"] = grant["category"]
		if grant.has("tag"): options["forceTag"] = grant["tag"]
		if grant.has("rarity"): options["forceRarity"] = grant["rarity"]
		var rolled: Dictionary = ItemFactory.new().roll_item(loot, _item_catalog, options)
		if not bool(rolled.get("ok", false)):
			last_error = str(rolled.get("error", "Предмет события не удалось создать."))
			return false
		item_values.append((rolled["item"] as ItemInstance).to_dictionary())
		if not _cargo_fits(run_payload, item_values[0]):
			last_error = "В грузовом отсеке нет места для предмета события."
			return false
		run_payload["unsecuredCargo"].append_array(item_values)
		run_payload["grantIds"].append(grant_id)
		run_payload["lootRng"] = loot.serialize()
	if choice.has("grantMutation"):
		var mutation_id: String = str(choice["grantMutation"])
		if not run_payload["temporaryMutationIds"].has(mutation_id) and run_payload["temporaryMutationIds"].size() < 2:
			run_payload["temporaryMutationIds"].append(mutation_id)
	var one_time_flag: String = "%s:%s" % [str(event.get("id", "")), choice_id]
	if not meta["campaignFlags"].has(one_time_flag): meta["campaignFlags"].append(one_time_flag)
	if not run_payload["eventsSeen"].has(str(event.get("id", ""))): run_payload["eventsSeen"].append(str(event.get("id", "")))
	run_payload["clearedNodeIds"].append(node_id)
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"].get("gameTimeMs", 0.0)) + 10000.0
	run_payload["phase"] = "ROUTE"
	run_payload["lastCommandId"] = "event:%s:%s" % [node_id, choice_id]
	return _commit_payload(payload)

func resolve_service_node(action: String, prototype_id: String = "") -> bool:
	if state == null or state.run == null or state.run.phase != "NODE":
		last_error = "Сервисное действие доступно только в дорожном узле."
		return false
	var node: Dictionary = current_node()
	var node_id: String = str(node.get("id", ""))
	var kind: String = str(node.get("type", ""))
	if state.run.cleared_node_ids.has(node_id):
		last_error = "Этот узел уже использован."
		return false
	if action == "LEAVE_NODE":
		var leave_payload: Dictionary = state.to_payload()
		var leave_run: Dictionary = leave_payload["run"]
		leave_run["clearedNodeIds"].append(node_id)
		leave_run["phase"] = "ROUTE"
		var leave_time: int = 5000 if kind == "CACHE" else 8000 if kind in ["SHOP", "REPAIR", "FUEL"] else 10000
		leave_run["resources"]["gameTimeMs"] = float(leave_run["resources"].get("gameTimeMs", 0.0)) + leave_time
		leave_run["lastCommandId"] = "node:%s:leave" % node_id
		return _commit_payload(leave_payload)
	if (kind == "FUEL" and action not in ["BUY_FUEL", "SCRAP_FUEL"]) or (kind == "REPAIR" and action not in ["REPAIR_HULL", "REPAIR_HP"]) or (kind == "CACHE" and action != "OPEN_CACHE"):
		last_error = "Действие не подходит для узла %s." % kind
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var wallet: Dictionary = run_payload["runWallet"]
	var resources: Dictionary = run_payload["resources"]
	var depth: int = int(run_payload["depth"])
	var scale: float = CydleFormula.new().reward_scale(float(depth))
	var elapsed: float = 8000.0
	if kind == "FUEL":
		var fuel: int = int(resources.get("fuel", 0))
		var maximum: int = int(resources.get("maxFuel", 0))
		if fuel >= maximum:
			last_error = "Топливный бак уже полон."
			return false
		if action == "BUY_FUEL":
			var price: int = ceili(3.0 * scale)
			if float(wallet.get("CREDITS", 0.0)) < price:
				last_error = "Недостаточно незакреплённых кредитов (%d требуется)." % price
				return false
			wallet["CREDITS"] = float(wallet["CREDITS"]) - price
		else:
			if float(wallet.get("SCRAP", 0.0)) < 5.0:
				last_error = "Для аварийной заправки нужно 5 scrap."
				return false
			wallet["SCRAP"] = float(wallet["SCRAP"]) - 5.0
		resources["fuel"] = fuel + 1
	elif kind == "REPAIR":
		if action == "REPAIR_HULL":
			var hull: float = float(resources.get("hull", 0.0))
			var max_hull: float = float(resources.get("maxHull", 0.0))
			var credit_cost: int = ceili(15.0 * scale)
			if hull >= max_hull:
				last_error = "Корпус уже цел."
				return false
			if float(wallet.get("CREDITS", 0.0)) < credit_cost:
				last_error = "Недостаточно незакреплённых кредитов (%d требуется)." % credit_cost
				return false
			wallet["CREDITS"] = float(wallet["CREDITS"]) - credit_cost
			resources["hull"] = minf(max_hull, hull + 30.0)
		else:
			var hp: float = float(resources.get("hp", 0.0))
			var max_hp: float = float(resources.get("maxHP", 0.0))
			var credit_cost: int = ceili(10.0 * scale)
			if hp >= max_hp:
				last_error = "Здоровье оператора уже восстановлено."
				return false
			if float(wallet.get("CREDITS", 0.0)) < credit_cost:
				last_error = "Недостаточно незакреплённых кредитов (%d требуется)." % credit_cost
				return false
			wallet["CREDITS"] = float(wallet["CREDITS"]) - credit_cost
			resources["hp"] = minf(max_hp, hp + (max_hp - hp) * 0.3)
	elif kind == "CACHE":
		elapsed = 5000.0
		if prototype_id.is_empty() and node.has("prototypeChoices"):
			last_error = "Выберите один из доступных прототипов."
			return false
		var grant_id: String = "cache:%s:%s" % [str(run_payload["seed"]), node_id]
		if not run_payload["grantIds"].has(grant_id):
			var rng: DeterministicRng = DeterministicRng.new()
			rng.restore(run_payload["lootRng"])
			wallet["CREDITS"] = float(wallet.get("CREDITS", 0.0)) + ceili(8.0 * scale)
			wallet["SCRAP"] = float(wallet.get("SCRAP", 0.0)) + ceili(2.0 * scale)
			var prototype: String = prototype_id
			var choices: Array = node.get("prototypeChoices", [])
			if not prototype.is_empty() and not choices.has(prototype):
				last_error = "Выбранный прототип отсутствует в этом тайнике."
				return false
			var item_value: Dictionary = {}
			if prototype.is_empty():
				var catalog_result: Dictionary = _item_catalog.load_catalog()
				if bool(catalog_result.get("ok", false)) and rng.chance(0.45):
					var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, {"depth": depth, "biome": str(run_payload["biome"]), "table": "ORDINARY", "secured": false, "grantId": grant_id, "origin": "cache"})
					if bool(rolled.get("ok", false)):
						item_value = (rolled["item"] as ItemInstance).to_dictionary()
				if rng.chance(0.02):
					var core: Dictionary = ItemFactory.new().create_item(rng, _item_catalog, {"templateId": "MAT_CORE", "techLevel": depth, "rarity": "COMMON", "secured": false, "originGrantId": grant_id + ":core", "origin": "cache"})
					if bool(core.get("ok", false)):
						item_value = (core["item"] as ItemInstance).to_dictionary()
			else:
				var created: Dictionary = ItemFactory.new().create_item(rng, _item_catalog, {"templateId": prototype, "techLevel": 1, "rarity": "MODIFIED", "secured": false, "originGrantId": grant_id, "origin": "tutorial-cache"})
				if bool(created.get("ok", false)):
					item_value = (created["item"] as ItemInstance).to_dictionary()
			if not item_value.is_empty() and _cargo_fits(run_payload, item_value):
				run_payload["unsecuredCargo"].append(item_value)
			run_payload["grantIds"].append(grant_id)
			run_payload["lootRng"] = rng.serialize()
	else:
		last_error = "Сначала приобретите товар или выйдите из магазина."
		return false
	run_payload["clearedNodeIds"].append(node_id)
	run_payload["phase"] = "ROUTE"
	resources["gameTimeMs"] = float(resources.get("gameTimeMs", 0.0)) + elapsed
	run_payload["lastCommandId"] = "node:%s:%s" % [node_id, action]
	return _commit_payload(payload)

func continue_campaign() -> bool:
	if state == null or state.run == null or state.run.phase != "CHECKPOINT":
		last_error = "Продолжить кампанию можно только с контрольного узла."
		return false
	var next_depth: int = state.run.depth + 1
	var build: Dictionary = build_preview()
	var seed: String = "%s:sector:%d" % [state.run.seed, next_depth]
	var biome: String = _generator.campaign_biome(next_depth, seed)
	var generated: Dictionary = _generator.generate(seed, next_depth, biome, false, state.run.wanted, state.run.events_seen)
	if not bool(generated.get("ok", false)):
		last_error = str(generated.get("error", "Не удалось создать следующий сектор."))
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	run_payload["seed"] = seed
	run_payload["depth"] = next_depth
	run_payload["biome"] = biome
	run_payload["graph"] = generated["graph"]
	run_payload["currentNodeId"] = "START"
	run_payload["visitedNodeIds"] = []
	run_payload["clearedNodeIds"] = []
	run_payload["phase"] = "ROUTE"
	run_payload["combatResult"] = null
	run_payload["pendingTravelDeltaMs"] = 0
	run_payload["equipment"] = state.meta.equipment.duplicate(true)
	if not build.is_empty():
		var stats: Dictionary = build.get("stats", {})
		var resources: Dictionary = run_payload["resources"]
		for pair: Array in [["maxHP", "maxHP"], ["maxShield", "maxShield"], ["maxEnergy", "maxEnergy"]]:
			resources[pair[0]] = float(stats.get(pair[1], resources.get(pair[0], 0.0)))
		resources["hp"] = minf(float(resources.get("hp", 0.0)), float(resources["maxHP"]))
		resources["shield"] = minf(float(resources.get("shield", 0.0)), float(resources["maxShield"]))
		resources["energy"] = minf(float(resources.get("energy", 0.0)), float(resources["maxEnergy"]))
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"].get("gameTimeMs", 0.0)) + 8000.0
	return _commit_payload(payload)

func shop_offers() -> Array[Dictionary]:
	if state == null or state.run == null or state.run.phase != "NODE" or str(current_node().get("type", "")) != "SHOP":
		return []
	var node_id: String = state.run.current_node_id
	var graph: Dictionary = state.run.graph
	for layer: Array in graph.get("layers", []):
		for node: Dictionary in layer:
			if str(node.get("id", "")) != node_id:
				continue
			if node.has("shopStock"):
				return (node["shopStock"] as Array).duplicate(true)
			var catalog_result: Dictionary = _item_catalog.load_catalog()
			if not bool(catalog_result.get("ok", false)):
				last_error = str(catalog_result.get("error", "Каталог предметов недоступен."))
				return []
			var rng: DeterministicRng = DeterministicRng.new()
			rng.seed("shop", "%s:%s" % [state.run.seed, node_id])
			var market_level: int = garage_level("MARKET")
			var categories: Array[String] = ["MAIN", "IMPLANT", "ARMOR"]
			if market_level >= 2:
				categories.append_array(["MAIN", "DRONE"])
			if market_level >= 3:
				categories.append("")
			var stock: Array[Dictionary] = []
			for index: int in range(categories.size()):
				var grant_id: String = "shop:%s:%s:%d" % [state.run.seed, node_id, index]
				var roll_options: Dictionary = {
					"depth": state.run.depth, "biome": state.run.biome, "table": "ORDINARY",
					"secured": false, "grantId": grant_id,
					"origin": "shop", "acquiredAt": state.updated_at,
				}
				if not categories[index].is_empty():
					roll_options["forceCategory"] = categories[index]
				elif market_level >= 3:
					var target_tags: Dictionary = {"B01": "weapon", "B02": "armor", "B03": "drone", "B04": "digital", "B05": "energy", "B06": "hybrid"}
					roll_options["forceTag"] = str(target_tags.get(state.run.biome, "weapon"))
				var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, roll_options)
				if not bool(rolled.get("ok", false)):
					continue
				var item: Dictionary = (rolled["item"] as ItemInstance).to_dictionary()
				var rarity: String = str(item.get("rarity", "COMMON"))
				var multiplier: float = {"COMMON": 1.0, "MODIFIED": 1.3, "RARE": 2.0, "LEGENDARY": 4.0, "UNIQUE": 10.0}.get(rarity, 1.0)
				var tech: int = int(item.get("techLevel", state.run.depth))
				var price: int = ceili((25.0 + 7.0 * tech) * multiplier * CydleFormula.new().reward_scale(float(tech)))
				stock.append({"item": item, "price": price, "purchased": false})
			if stock.is_empty():
				last_error = "Не удалось сформировать ассортимент магазина."
				return []
			node["shopStock"] = stock
			var payload: Dictionary = state.to_payload()
			payload["run"]["graph"] = graph
			if not _commit_payload(payload):
				return []
			return stock.duplicate(true)
	return []

func buy_shop_item(index: int) -> bool:
	var offers: Array[Dictionary] = shop_offers()
	if index < 0 or index >= offers.size() or state == null or state.run == null:
		last_error = "Предложение магазина больше недоступно."
		return false
	var offer: Dictionary = offers[index]
	if bool(offer.get("purchased", false)):
		last_error = "Этот предмет уже куплен."
		return false
	var run_payload: Dictionary = state.run.to_dictionary()
	var cost: int = int(offer.get("price", 0))
	if float(run_payload["runWallet"].get("CREDITS", 0.0)) < cost:
		last_error = "Недостаточно незакреплённых кредитов (%d требуется)." % cost
		return false
	var item: Dictionary = offer.get("item", {}).duplicate(true)
	if not _cargo_fits(run_payload, item):
		last_error = "В грузовом отсеке нет места для этого предмета."
		return false
	var graph: Dictionary = run_payload["graph"]
	for layer: Array in graph.get("layers", []):
		for node: Dictionary in layer:
			if str(node.get("id", "")) != state.run.current_node_id:
				continue
			var stock: Array = node.get("shopStock", [])
			stock[index]["purchased"] = true
			node["shopStock"] = stock
	run_payload["graph"] = graph
	run_payload["runWallet"]["CREDITS"] = float(run_payload["runWallet"]["CREDITS"]) - cost
	run_payload["unsecuredCargo"].append(item)
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"].get("gameTimeMs", 0.0)) + 8000.0
	run_payload["lastCommandId"] = "shop:%s:%d" % [state.run.current_node_id, index]
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	return _commit_payload(payload)

func begin_combat() -> bool:
	if state == null or state.run == null or state.run.phase != "NODE":
		last_error = "Для боя нужно находиться на боевом узле."
		return false
	var node: Dictionary = current_node()
	if not ["COMBAT", "ELITE", "BOUNTY", "BOSS"].has(str(node.get("type", ""))):
		last_error = "Текущий узел не является боевым."
		return false
	var build: Dictionary = build_preview()
	if not bool(build.get("valid", false)):
		last_error = "Сборка не прошла проверку BuildResolver."
		return false
	var tactic: Dictionary = {}
	for profile: Dictionary in state.meta.tactics:
		if str(profile.get("id", "")) == state.meta.active_tactic_id:
			tactic = profile
			break
	if tactic.is_empty():
		last_error = "Активный профиль тактики не найден."
		return false
	combat_notice = ""
	var compatible_rules: Array[Dictionary] = []
	var omitted_rules: Array[String] = []
	for rule_value: Variant in tactic.get("rules", []):
		if not rule_value is Dictionary or not bool(rule_value.get("enabled", false)):
			continue
		var skill_id: String = str(rule_value.get("skillId", "AUTO"))
		if skill_id in ["AUTO", "SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_BLADE", "SK_PLASMA", "SK_ARC", "SK_OVR", "SK_NEURO", "SK_SEED", "SK_DETONATE", "SK_BREAK", "SK_SCAN", "SK_LEECH", "SK_CHAIN", "SK_KINETIC", "SK_SIDE_FIRE", "SK_SHIELD", "SK_EMP", "SK_GUARD", "SK_VENT", "SK_HEAL", "SK_DRONE_MARK"]:
			var compatible_rule: Dictionary = rule_value.duplicate(true)
			if skill_id == "SK_BURST" and str(compatible_rule.get("target", "")) == "allEnemies":
				compatible_rule["target"] = "nearest"
			compatible_rules.append(compatible_rule)
		else:
			omitted_rules.append(skill_id)
	if compatible_rules.is_empty():
		compatible_rules.append({"id": "basic-auto", "priority": -999, "enabled": true, "skillId": "AUTO", "target": "nearest", "conditions": []})
	var effective_tactic: Dictionary = {"id": str(tactic.get("id", "DEFAULT")), "name": str(tactic.get("name", "Тактика")), "rules": compatible_rules}
	if not omitted_rules.is_empty():
		combat_notice = "Пока не поддерживаются умения: %s. Остальные правила и условия работают; исходный профиль сохранён." % ", ".join(omitted_rules)
	var resources: Dictionary = state.run.resources
	var pending_next: Dictionary = state.run.pending_next_combat
	var effective_type: String = str(node.get("type", "COMBAT"))
	var enemy_specs: Array = node.get("enemies", []).duplicate(true)
	if effective_type == "COMBAT" and bool(pending_next.get("skipOrdinary", false)):
		var skipped_payload: Dictionary = state.to_payload()
		var skipped_run: Dictionary = skipped_payload["run"]
		skipped_run["clearedNodeIds"].append(state.run.current_node_id)
		skipped_run["phase"] = "ROUTE"
		skipped_run["pendingNextCombat"]["skipOrdinary"] = false
		skipped_run["resources"]["gameTimeMs"] = float(skipped_run["resources"].get("gameTimeMs", 0.0))
		last_error = ""
		return _commit_payload(skipped_payload)
	if effective_type == "COMBAT" and bool(pending_next.get("forceElite", false)):
		effective_type = "ELITE"
		if not enemy_specs.is_empty(): enemy_specs[0]["elite"] = "EL_PEN"
	if effective_type == "COMBAT" and bool(pending_next.get("forceBounty", false)):
		effective_type = "BOUNTY"
		if not enemy_specs.is_empty() and not str(pending_next.get("bountyEnemyId", "")).is_empty(): enemy_specs[0]["templateId"] = str(pending_next["bountyEnemyId"])
	var pending_effects: Dictionary = state.run.pending_combat_effects
	var config: Dictionary = {
		"seed": "%s:%s" % [state.run.seed, state.run.current_node_id],
		"depth": state.run.depth, "biome": state.run.biome, "nodeType": effective_type,
		"build": build, "enemies": enemy_specs, "tactics": effective_tactic,
		"startHpFraction": float(resources.get("hp", 0.0)) / maxf(1.0, float(resources.get("maxHP", 1.0))),
		"startShieldFraction": float(resources.get("shield", 0.0)) / maxf(1.0, float(resources.get("maxShield", 1.0))),
		"startEnergy": float(resources.get("energy", 0.0)), "startHeat": float(resources.get("heat", 0.0)),
		"initialTempShield": float(pending_effects.get("initialTempShield", 0.0)),
		"initialExtraHeat": float(pending_effects.get("extraHeat", 0.0)),
	}
	var initialized: Dictionary = _simulator.create_state(config)
	if not bool(initialized.get("ok", false)):
		last_error = str(initialized.get("error", "Боевой симулятор не смог создать встречу."))
		return false
	_combat = initialized["state"] as CombatState
	_active_node_type = effective_type
	_active_reward_modifiers = pending_next.duplicate(true)
	if not _persist_combat_snapshot():
		_combat = null
		return false
	last_error = ""
	return true

func has_active_combat() -> bool:
	return _combat != null

func combat_state() -> CombatState:
	return _combat

func advance_combat_step() -> bool:
	if _combat == null:
		last_error = "Нет активного боя."
		return false
	var stepped: Dictionary = _simulator.step_combat(_combat)
	if not bool(stepped.get("ok", false)):
		last_error = str(stepped.get("error", "Боевой шаг отклонён."))
		return false
	var previous: CombatState = _combat
	_combat = stepped["state"] as CombatState
	if not _persist_combat_snapshot():
		_combat = previous
		return false
	last_error = ""
	return true

func resolve_active_combat() -> bool:
	if _combat == null or _combat.outcome.is_empty() or state == null or state.run == null:
		last_error = "Бой ещё не завершён."
		return false
	var run_payload: Dictionary = state.run.to_dictionary()
	var resources: Dictionary = run_payload["resources"]
	resources["hp"] = _combat.operator.hp
	resources["shield"] = _combat.operator.shield
	resources["energy"] = _combat.operator.energy
	resources["heat"] = _combat.operator.heat
	resources["gameTimeMs"] = float(resources["gameTimeMs"]) + _combat.time_ms
	var node: Dictionary = current_node()
	var node_id: String = str(node.get("id", ""))
	if _combat.outcome == "DEFEAT":
		return _resolve_combat_defeat(run_payload, node_id)
	if _combat.outcome != "VICTORY":
		last_error = "Бой завершился без победы; безопасное восстановление ещё не реализовано."
		return false
	if _combat.wanted_delta != 0:
		run_payload["wanted"] = clampf(float(run_payload.get("wanted", 0.0)) + float(_combat.wanted_delta), 0.0, 100.0)
	var escaped_cargo: int = 0
	for escape_value: Dictionary in _combat.metrics.get("escaped", []):
		escaped_cargo += int(escape_value.get("cargoItems", 1))
	var unsecured: Array = run_payload.get("unsecuredCargo", [])
	for _item_index: int in range(mini(escaped_cargo, unsecured.size())):
		unsecured.pop_back()
	run_payload["unsecuredCargo"] = unsecured
	var reward: Dictionary = _battle_reward(_active_node_type if not _active_node_type.is_empty() else str(node.get("type", "COMBAT")), state.run.depth, state.run.biome, node_id, run_payload, _active_reward_modifiers)
	var payload: Dictionary = state.to_payload()
	var wallet: Dictionary = run_payload["runWallet"]
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		wallet[currency] = float(wallet.get(currency, 0.0)) + float(reward["wallet"].get(currency, 0.0))
	for item_value: Dictionary in reward["items"]:
		if _cargo_fits(run_payload, item_value):
			run_payload["unsecuredCargo"].append(item_value)
		else:
			reward["discardedItems"] += 1
	run_payload["grantIds"].append_array(reward["grantIds"])
	run_payload["lootRng"] = reward["lootRng"]
	var xp_grant_id: String = "combat:%s:%s:xp" % [state.run.seed, node_id]
	if not run_payload["grantIds"].has(xp_grant_id):
		_grant_experience(payload["meta"]["operator"], int(reward["xp"]))
		run_payload["grantIds"].append(xp_grant_id)
	if not run_payload["clearedNodeIds"].has(node_id):
		run_payload["clearedNodeIds"].append(node_id)
	run_payload["phase"] = "CHECKPOINT" if int(node.get("layer", 0)) == 5 else "ROUTE"
	run_payload["combatResult"] = null
	run_payload["combatSnapshot"] = null
	run_payload["lastCommandId"] = "combat:%s" % node_id
	var retain_elite_contract: bool = bool(_active_reward_modifiers.get("extraRareOnElite", false)) and _active_node_type != "ELITE"
	run_payload["pendingCombatEffects"] = {"initialTempShield": 0.0, "extraHeat": 0.0}
	run_payload["pendingNextCombat"] = {"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false, "bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false, "alliedTurret": false, "extraRareOnElite": retain_elite_contract}
	if str(node.get("type", "")) == "BOSS":
		var depth: int = int(state.run.depth)
		if depth % 4 == 0:
			payload["meta"]["unlockedForpost"] = maxi(int(payload["meta"]["unlockedForpost"]), depth)
			payload["meta"]["maxSectorCleared"] = maxi(int(payload["meta"]["maxSectorCleared"]), depth)
			var boss_flag: String = "SECTOR_BOSS_%d" % depth
			if not payload["meta"]["campaignFlags"].has(boss_flag):
				payload["meta"]["campaignFlags"].append(boss_flag)
		if depth == 12 and not payload["meta"]["campaignFlags"].has("CAMPAIGN_COMPLETED"):
			payload["meta"]["campaignFlags"].append("CAMPAIGN_COMPLETED")
	payload["run"] = run_payload
	if not _commit_payload(payload):
		return false
	_combat = null
	_active_node_type = ""
	_active_reward_modifiers = {}
	return true

func _battle_reward(node_type: String, depth: int, biome: String, node_id: String, run_payload: Dictionary, modifiers: Dictionary = {}) -> Dictionary:
	var scale: float = CydleFormula.new().reward_scale(float(depth))
	var credits: float = 12.0
	var scrap: float = 3.0
	var data: float = 1.0
	var xp: int = ceili(22.0 * scale)
	var item_chance: float = 0.7
	var extra_item_chance: float = 0.0
	var core_chance: float = 0.0
	var table: String = "ORDINARY"
	match node_type:
		"ELITE":
			credits = 28.0; scrap = 7.0; data = 3.0; xp = ceili(55.0 * scale)
			item_chance = 1.0; extra_item_chance = 0.25; core_chance = 0.15; table = "ELITE"
		"BOUNTY":
			credits = 35.0; scrap = 5.0; data = 3.0; xp = 0
			item_chance = 0.9; core_chance = 0.08; table = "ELITE"
		"BOSS":
			credits = 85.0; scrap = 18.0; data = 8.0; xp = ceili(160.0 * scale)
			item_chance = 1.0; extra_item_chance = 0.5; core_chance = 1.0; table = "BOSS"
	credits = ceili(credits * scale * (1.1 if biome == "B02" else 1.0) * (1.0 + float(modifiers.get("bountyCreditsBonus", 0.0))))
	data = ceili(data * scale * (1.2 if biome == "B04" else 1.0))
	var wallet: Dictionary = {"CREDITS": credits, "SCRAP": ceili(scrap * scale), "DATA": data}
	var items: Array[Dictionary] = []
	var grant_ids: Array[String] = []
	var rng: DeterministicRng = DeterministicRng.new()
	rng.restore(run_payload["lootRng"])
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return {"wallet": wallet, "items": items, "grantIds": grant_ids, "lootRng": run_payload["lootRng"], "xp": xp, "discardedItems": 0}
	var grants: Array[float] = [item_chance, extra_item_chance]
	var forced_rarities: Array[String] = ["", ""]
	if bool(modifiers.get("extraItemRoll", false)):
		grants.append(1.0)
		forced_rarities.append("")
	if bool(modifiers.get("extraRareItemRoll", false)) or bool(modifiers.get("extraRareOnElite", false)) and node_type == "ELITE":
		grants.append(1.0)
		forced_rarities.append("RARE")
	for index: int in range(grants.size()):
		var grant_id: String = "combat:%s:%s:item:%d" % [state.run.seed, node_id, index]
		if grants[index] <= 0.0 or not rng.chance(grants[index]):
			continue
		var roll_options: Dictionary = {
			"depth": depth, "biome": biome, "table": table, "secured": false,
			"grantId": grant_id, "origin": "combat", "acquiredAt": state.updated_at,
		}
		if not forced_rarities[index].is_empty(): roll_options["forceRarity"] = forced_rarities[index]
		var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, roll_options)
		if bool(rolled.get("ok", false)):
			items.append((rolled["item"] as ItemInstance).to_dictionary())
			grant_ids.append(grant_id)
	if core_chance >= 1.0 or rng.chance(core_chance):
		var core_grant: String = "combat:%s:%s:core" % [state.run.seed, node_id]
		var core_created: Dictionary = ItemFactory.new().create_item(rng, _item_catalog, {
			"templateId": "MAT_CORE", "techLevel": depth, "rarity": "COMMON", "secured": false,
			"originGrantId": core_grant, "origin": "core", "acquiredAt": state.updated_at,
		})
		if bool(core_created.get("ok", false)):
			var core: ItemInstance = core_created["item"] as ItemInstance
			core.core_group = clampi(int(ceil(float(depth) / 4.0)), 1, 4)
			core.label = "Ядро группы %d" % core.core_group
			items.append(core.to_dictionary())
			grant_ids.append(core_grant)
	return {"wallet": wallet, "items": items, "grantIds": grant_ids, "lootRng": rng.serialize(), "xp": xp, "discardedItems": 0}

func _cargo_fits(run_payload: Dictionary, candidate: Dictionary) -> bool:
	var catalog_result: Dictionary = _item_catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return false
	var used: int = 0
	for item_value: Dictionary in run_payload.get("unsecuredCargo", []):
		used += int(_item_catalog.get_template(str(item_value.get("templateId", ""))).get("cargoUnits", 1))
	var units: int = int(_item_catalog.get_template(str(candidate.get("templateId", ""))).get("cargoUnits", 1))
	var capacity: int = int(state.meta.transport.cargo_capacity)
	return used + units <= capacity

func _grant_experience(operator: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	var xp: int = int(operator.get("xp", 0)) + amount
	var level: int = int(operator.get("level", 1))
	var attribute_points: int = int(operator.get("attributePoints", 0))
	var tree_points: int = int(operator.get("treePoints", 0))
	while level < 61 and xp >= CydleFormula.new().xp_required(level):
		xp -= CydleFormula.new().xp_required(level)
		level += 1
		tree_points += 1
		if level <= 60 and level % 5 == 0:
			attribute_points += 1
	operator["xp"] = xp
	operator["level"] = level
	operator["attributePoints"] = attribute_points
	operator["treePoints"] = tree_points

func _resolve_combat_defeat(run_payload: Dictionary, node_id: String) -> bool:
	var payload: Dictionary = state.to_payload()
	var meta: Dictionary = payload["meta"]
	var equipped_ids: Array = meta["equipment"].values()
	for index: int in range(meta["inventory"].size()):
		var item: Dictionary = meta["inventory"][index]
		if equipped_ids.has(str(item.get("itemId", ""))):
			item["durability"] = maxf(0.0, float(item.get("durability", 100.0)) - 20.0)
		meta["inventory"][index] = item
	var revive_cost: int = 5 if int(meta.get("garage", {}).get("GARAGE_MED", 1)) >= 2 else 10
	var paid: bool = float(meta["protectedBank"].get("CREDITS", 0.0)) >= float(revive_cost)
	if paid:
		meta["protectedBank"]["CREDITS"] = float(meta["protectedBank"]["CREDITS"]) - float(revive_cost)
	var build: Dictionary = build_preview()
	var stats: Dictionary = build.get("stats", {})
	var resources: Dictionary = run_payload["resources"]
	resources["hp"] = float(stats.get("maxHP", 1.0)) * (1.0 if paid else 0.5)
	resources["maxHP"] = float(stats.get("maxHP", 1.0))
	resources["shield"] = float(stats.get("maxShield", 0.0)) if paid else 0.0
	resources["maxShield"] = float(stats.get("maxShield", 0.0))
	run_payload["phase"] = "DEFEATED"
	run_payload["combatResult"] = null
	run_payload["combatSnapshot"] = null
	run_payload["unsecuredCargo"] = []
	run_payload["shippedCargo"] = []
	run_payload["temporaryMutationIds"] = []
	run_payload["runWallet"] = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	run_payload["pendingCombatEffects"] = {"initialTempShield": 0.0, "extraHeat": 0.0}
	run_payload["pendingNextCombat"] = {"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false, "bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false, "alliedTurret": false, "extraRareOnElite": false}
	run_payload["equipment"] = meta["equipment"].duplicate(true)
	run_payload["lastCommandId"] = "combat:defeat:%s" % node_id
	payload["meta"] = meta
	payload["run"] = run_payload
	if not _commit_payload(payload):
		return false
	_combat = null
	_active_node_type = ""
	_active_reward_modifiers = {}
	return true

func equip_item(slot: String, item_id: String) -> bool:
	if state == null:
		last_error = "Нет активного профиля."
		return false
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Постоянное снаряжение меняется в гараже после завершения выезда."
		return false
	var candidate: Dictionary = {}
	for value: Dictionary in state.meta.inventory:
		if str(value.get("itemId", "")) == item_id:
			candidate = value
			break
	if candidate.is_empty() or not bool(candidate.get("secured", false)):
		last_error = "Предмет не найден в постоянном складе."
		return false
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		last_error = str(loaded.get("error", "Каталог предметов недоступен."))
		return false
	var template: Dictionary = _item_catalog.get_template(str(candidate.get("templateId", "")))
	if template.is_empty() or not _slot_accepts(slot, str(template.get("category", ""))):
		last_error = "Этот предмет нельзя установить в выбранный слот."
		return false
	var payload: Dictionary = state.to_payload()
	for equipped_slot: Variant in payload["meta"]["equipment"].keys():
		if str(payload["meta"]["equipment"][equipped_slot]) == item_id:
			payload["meta"]["equipment"].erase(equipped_slot)
	payload["meta"]["equipment"][slot] = item_id
	var validation: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(validation.get("ok", false)):
		last_error = str(validation.get("error", "Новая сборка не прошла проверку."))
		return false
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(validation["state"] as GameSaveState))
	if not bool(resolved.get("valid", false)):
		last_error = "Сборка невалидна: %s" % str(resolved.get("issues", []))
		return false
	return _commit(validation["state"] as GameSaveState)

func equipped_slot(item_id: String) -> String:
	if state == null:
		return ""
	for slot_value: Variant in state.meta.equipment.keys():
		if str(state.meta.equipment[slot_value]) == item_id:
			return str(slot_value)
	return ""

func valid_equipment_slots(item_id: String) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		return result
	var item: Dictionary = {}
	for inventory_item: Dictionary in state.meta.inventory:
		if str(inventory_item.get("itemId", "")) == item_id and bool(inventory_item.get("secured", false)):
			item = inventory_item
			break
	if item.is_empty():
		return result
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return result
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	var category: String = str(template.get("category", ""))
	var candidates: Array[String] = []
	match category:
		"MAIN": candidates = ["MAIN"]
		"OFFHAND": candidates = ["OFFHAND"]
		"ARMOR": candidates = ["ARMOR"]
		"IMPLANT": candidates = ["IMP_1", "IMP_2", "IMP_3", "IMP_4", "IMP_5", "IMP_6"]
		"DRONE": candidates = ["DRONE_1", "DRONE_2"]
		"ENGINE": candidates = ["ENGINE"]
		"CHASSIS": candidates = ["CHASSIS"]
		"SCANNER": candidates = ["SCANNER"]
		"SERVICE": candidates = ["SERVICE"]
		"CARGO": candidates = ["CARGO"]
		"SUPPORT": candidates = ["SUPPORT"]
	var payload: Dictionary = state.to_payload()
	for equipped_slot_value: Variant in payload["meta"]["equipment"].keys():
		if str(payload["meta"]["equipment"][equipped_slot_value]) == item_id:
			payload["meta"]["equipment"].erase(equipped_slot_value)
	for slot: String in candidates:
		var candidate_payload: Dictionary = payload.duplicate(true)
		candidate_payload["meta"]["equipment"][slot] = item_id
		var parsed: Dictionary = GameSaveState.new().parse_payload(candidate_payload)
		if not bool(parsed.get("ok", false)):
			continue
		var build: Dictionary = BuildResolver.new().resolve_build(_build_input(parsed["state"] as GameSaveState))
		if bool(build.get("valid", false)):
			result.append(slot)
	return result

func unequip_item(slot: String) -> bool:
	if not _garage_action_allowed():
		last_error = "Постоянное снаряжение меняется в гараже после завершения выезда."
		return false
	if not state.meta.equipment.has(slot):
		last_error = "Слот %s пуст." % slot
		return false
	var payload: Dictionary = state.to_payload()
	payload["meta"]["equipment"].erase(slot)
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Снятие предмета не прошло проверку."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Нельзя снять предмет: сборка станет невалидной (%s)." % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func repair_item(item_id: String) -> bool:
	if not _garage_action_allowed():
		last_error = "Экипировку можно ремонтировать только в гараже между выездами."
		return false
	if garage_level("WORKSHOP") < 1:
		last_error = "Ремонт требует WORKSHOP уровня 1."
		return false
	var repair_catalog: Dictionary = _item_catalog.load_catalog()
	if not bool(repair_catalog.get("ok", false)):
		last_error = str(repair_catalog.get("error", "Каталог предметов недоступен."))
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	for index: int in range(inventory.size()):
		var item: Dictionary = inventory[index]
		if str(item.get("itemId", "")) != item_id or not bool(item.get("secured", false)):
			continue
		var durability: float = float(item.get("durability", 100.0))
		if durability >= 100.0:
			last_error = "Предмет уже полностью исправен."
			return false
		var tech_level: int = int(item.get("techLevel", 1))
		var formula: CydleFormula = CydleFormula.new()
		var repair_cost: int = ceili((100.0 - durability) / 10.0 * (2.0 + float(tech_level) / 5.0))
		var replacement_cap: int = ceili((25.0 + 7.0 * float(tech_level)) * formula.reward_scale(float(tech_level)))
		repair_cost = mini(repair_cost, replacement_cap)
		if str(_item_catalog.get_template(str(item.get("templateId", ""))).get("category", "")) == "DRONE" and garage_level("HANGAR") >= 3:
			repair_cost = ceili(float(repair_cost) * 0.8)
		var scrap: float = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0))
		if scrap < float(repair_cost):
			last_error = "Ремонт требует %d SCRAP, доступно %d." % [repair_cost, int(scrap)]
			return false
		item["durability"] = 100.0
		inventory[index] = item
		payload["meta"]["inventory"] = inventory
		payload["meta"]["protectedBank"]["SCRAP"] = scrap - float(repair_cost)
		return _commit_payload(payload)
	last_error = "Предмет не найден в постоянном складе."
	return false

func calibrate_item_affix(item_id: String, affix_index: int) -> bool:
	if not _garage_action_allowed():
		last_error = "Калибровка доступна только в гараже между выездами."
		return false
	if garage_level("WORKSHOP") < 2:
		last_error = "Изменение ролла требует WORKSHOP уровня 2."
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	for item_index: int in range(inventory.size()):
		var item: Dictionary = inventory[item_index]
		if str(item.get("itemId", "")) != item_id or not bool(item.get("secured", false)):
			continue
		if affix_index < 0 or affix_index >= item.get("affixes", []).size():
			last_error = "У предмета нет выбранного аффикса."
			return false
		if str(item.get("rarity", "")) == "UNIQUE":
			last_error = "Уникальные эффекты нельзя калибровать обычной операцией."
			return false
		if float(item.get("tr", 0.0)) < 3.0:
			last_error = "Недостаточно TR: требуется 3."
			return false
		var tech_level: int = int(item.get("techLevel", 1))
		var scrap_cost: int = ceili(10.0 * CydleFormula.new().reward_scale(float(tech_level)))
		var scrap: float = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0))
		if scrap < float(scrap_cost):
			last_error = "Калибровка требует %d SCRAP, доступно %d." % [scrap_cost, int(scrap)]
			return false
		var affix: Dictionary = item["affixes"][affix_index]
		var catalog_result: Dictionary = _item_catalog.load_catalog()
		if not bool(catalog_result.get("ok", false)):
			last_error = str(catalog_result.get("error", "Каталог предметов недоступен."))
			return false
		var definition: Dictionary = _item_catalog.get_affix(str(affix.get("affixId", "")))
		if definition.is_empty():
			last_error = "Аффикс отсутствует в каталоге."
			return false
		var tier: int = int(affix.get("tier", 1))
		var tiers: Array = definition.get("tiers", [])
		var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
		if tier < 1 or tier > tiers.size() or template.is_empty() or not (definition.get("slots", []) as Array).has(str(template.get("category", ""))):
			last_error = "Аффикс или его tier несовместимы с шаблоном предмета."
			return false
		var center: float = float(tiers[tier - 1])
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed("craft:%s:%s:%d:%d" % [state.save_id, item_id, state.revision, affix_index], state.revision)
		var raw_roll: float = 1.0 if bool(definition.get("fixed", false)) else rng.range_float(0.8, 1.2)
		var integer_value: bool = bool(definition.get("integer", false))
		var value: float = maxf(1.0, roundf(center * raw_roll)) if integer_value else floorf(center * raw_roll * 100.0 + 0.5) / 100.0
		affix["rawRoll"] = floorf(raw_roll * 10000.0 + 0.5) / 10000.0
		affix["center"] = center
		affix["value"] = value
		affix["min"] = maxf(1.0, roundf(center * 0.8)) if integer_value else floorf(center * 0.8 * 100.0 + 0.5) / 100.0
		affix["max"] = roundf(center * 1.2) if integer_value else floorf(center * 1.2 * 100.0 + 0.5) / 100.0
		item["affixes"][affix_index] = affix
		item["tr"] = float(item.get("tr", 0.0)) - 3.0
		item["rollSeed"] = "%s:%d" % [rng.stream, rng.calls]
		inventory[item_index] = item
		payload["meta"]["inventory"] = inventory
		payload["meta"]["protectedBank"]["SCRAP"] = scrap - float(scrap_cost)
		return _commit_payload(payload)
	last_error = "Предмет не найден в постоянном складе."
	return false

func upgrade_item_affix_tier(item_id: String, affix_index: int) -> bool:
	if not _garage_action_allowed():
		last_error = "Повышение tier доступно только в гараже между выездами."
		return false
	if garage_level("WORKSHOP") < 3:
		last_error = "Повышение tier требует WORKSHOP уровня 3."
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	for item_index: int in range(inventory.size()):
		var item: Dictionary = inventory[item_index]
		if str(item.get("itemId", "")) != item_id or not bool(item.get("secured", false)):
			continue
		if str(item.get("rarity", "")) == "UNIQUE" or affix_index < 0 or affix_index >= item.get("affixes", []).size():
			last_error = "Этот предмет нельзя улучшить выбранной операцией."
			return false
		if float(item.get("tr", 0.0)) < 6.0:
			last_error = "Повышение tier требует 6 TR."
			return false
		var affix: Dictionary = item["affixes"][affix_index]
		var catalog_result: Dictionary = _item_catalog.load_catalog()
		if not bool(catalog_result.get("ok", false)):
			last_error = str(catalog_result.get("error", "Каталог предметов недоступен."))
			return false
		var definition: Dictionary = _item_catalog.get_affix(str(affix.get("affixId", "")))
		var tiers: Array = definition.get("tiers", [])
		var tier: int = int(affix.get("tier", 1))
		var max_tier: int = clampi(int(ceil(float(item.get("techLevel", 1)) / 4.0)), 1, 4)
		var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
		if definition.is_empty() or template.is_empty() or not (definition.get("slots", []) as Array).has(str(template.get("category", ""))) or tier < 1 or tier >= max_tier or tier >= tiers.size():
			last_error = "Аффикс уже достиг разрешённого tier или несовместим с предметом."
			return false
		var scale: float = CydleFormula.new().reward_scale(float(item.get("techLevel", 1)))
		var scrap_cost: int = ceili(20.0 * scale)
		var data_cost: int = ceili(5.0 * scale)
		var scrap: float = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0))
		var data: float = float(payload["meta"]["protectedBank"].get("DATA", 0.0))
		if scrap < float(scrap_cost) or data < float(data_cost):
			last_error = "Повышение tier требует %d SCRAP и %d DATA." % [scrap_cost, data_cost]
			return false
		var new_tier: int = tier + 1
		var center: float = float(tiers[new_tier - 1])
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed("tier:%s:%s:%d:%d" % [state.save_id, item_id, state.revision, affix_index], state.revision)
		var raw_roll: float = 1.0 if bool(definition.get("fixed", false)) else rng.range_float(0.8, 1.2)
		var is_integer: bool = bool(definition.get("integer", false))
		affix["tier"] = new_tier
		affix["tierBoosted"] = false
		affix["center"] = center
		affix["rawRoll"] = floorf(raw_roll * 10000.0 + 0.5) / 10000.0
		affix["value"] = maxf(1.0, roundf(center * raw_roll)) if is_integer else floorf(center * raw_roll * 100.0 + 0.5) / 100.0
		affix["min"] = maxf(1.0, roundf(center * 0.8)) if is_integer else floorf(center * 0.8 * 100.0 + 0.5) / 100.0
		affix["max"] = roundf(center * 1.2) if is_integer else floorf(center * 1.2 * 100.0 + 0.5) / 100.0
		item["affixes"][affix_index] = affix
		item["tr"] = float(item.get("tr", 0.0)) - 6.0
		item["rollSeed"] = "%s:%d" % [rng.stream, rng.calls]
		inventory[item_index] = item
		payload["meta"]["inventory"] = inventory
		payload["meta"]["protectedBank"]["SCRAP"] = scrap - float(scrap_cost)
		payload["meta"]["protectedBank"]["DATA"] = data - float(data_cost)
		var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
		if not bool(parsed.get("ok", false)):
			last_error = str(parsed.get("error", "Улучшение аффикса не прошло проверку сохранения."))
			return false
		var candidate: GameSaveState = parsed["state"] as GameSaveState
		var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
		if not bool(resolved.get("valid", false)):
			last_error = "Улучшение аффикса отклонено BuildResolver: %s" % str(resolved.get("issues", []))
			return false
		return _commit(candidate)
	last_error = "Предмет не найден в постоянном складе."
	return false

func tech_calibration_quote(item_id: String, target_level: int) -> Dictionary:
	if not _garage_action_allowed():
		return {"valid": false, "affordable": false, "error": "Калибровка доступна только в гараже между выездами."}
	var item: Dictionary = {}
	for inventory_item: Dictionary in state.meta.inventory:
		if str(inventory_item.get("itemId", "")) == item_id and bool(inventory_item.get("secured", false)):
			item = inventory_item
			break
	if item.is_empty():
		return {"valid": false, "affordable": false, "error": "Предмет отсутствует в постоянном складе."}
	var current_level: int = int(item.get("techLevel", 1))
	var max_target: int = maxi(4, state.meta.unlocked_forpost)
	if target_level <= current_level or target_level > max_target:
		return {"valid": false, "affordable": false, "error": "Целевой TechLevel должен быть выше текущего и не выше открытого форпоста."}
	var delta: int = target_level - current_level
	var scale: float = CydleFormula.new().reward_scale(float(target_level))
	var calibrator_discount: float = 0.9 if garage_level("CALIBRATOR") >= 2 else 1.0
	var scrap_cost: int = ceili(5.0 * float(delta) * scale * calibrator_discount)
	var data_cost: int = ceili(2.0 * float(delta) * scale)
	var core_count: int = ceili(float(delta) / 4.0)
	var core_group: int = clampi(int(ceil(float(target_level) / 4.0)), 1, 4)
	var cores_available: int = 0
	for inventory_item: Dictionary in state.meta.inventory:
		if bool(inventory_item.get("secured", false)) and str(inventory_item.get("templateId", "")) == "MAT_CORE" and int(inventory_item.get("coreGroup", 0)) == core_group:
			cores_available += 1
	var scrap_available: int = int(state.meta.protected_bank.scrap)
	var data_available: int = int(state.meta.protected_bank.data)
	var affordable: bool = scrap_available >= scrap_cost and data_available >= data_cost and cores_available >= core_count
	var reason: String = ""
	if scrap_available < scrap_cost:
		reason = "Нужно %d SCRAP" % scrap_cost
	elif data_available < data_cost:
		reason = "Нужно %d DATA" % data_cost
	elif cores_available < core_count:
		reason = "Нужно %d CalibrationCore группы %d" % [core_count, core_group]
	return {"valid": true, "affordable": affordable, "error": reason, "itemId": item_id, "currentTechLevel": current_level, "targetTechLevel": target_level, "scrap": scrap_cost, "data": data_cost, "coreCount": core_count, "coreGroup": core_group, "coresAvailable": cores_available}

func calibrate_item_tech_level(item_id: String, target_level: int) -> bool:
	var quote: Dictionary = tech_calibration_quote(item_id, target_level)
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Калибровка недоступна."))
		return false
	if not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Недостаточно ресурсов для калибровки."))
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	var found_item: bool = false
	var remaining_cores: int = int(quote["coreCount"])
	for index: int in range(inventory.size() - 1, -1, -1):
		var item: Dictionary = inventory[index]
		if str(item.get("itemId", "")) == item_id and bool(item.get("secured", false)):
			item["techLevel"] = target_level
			inventory[index] = item
			found_item = true
			continue
		if remaining_cores > 0 and bool(item.get("secured", false)) and str(item.get("templateId", "")) == "MAT_CORE" and int(item.get("coreGroup", 0)) == int(quote["coreGroup"]):
			inventory.remove_at(index)
			remaining_cores -= 1
	if not found_item or remaining_cores > 0:
		last_error = "Состав инвентаря изменился; калибровка отменена."
		return false
	payload["meta"]["inventory"] = inventory
	payload["meta"]["protectedBank"]["SCRAP"] = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0)) - float(quote["scrap"])
	payload["meta"]["protectedBank"]["DATA"] = float(payload["meta"]["protectedBank"].get("DATA", 0.0)) - float(quote["data"])
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Калибровка не прошла проверку сохранения."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Калибровка отклонена BuildResolver: %s" % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func _garage_action_allowed() -> bool:
	return state != null and (state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase))

func garage_level(object_id: String) -> int:
	if state == null:
		return 0
	return int(state.meta.garage.get(object_id, 0))

func garage_upgrade_quote(object_id: String) -> Dictionary:
	if not _garage_action_allowed():
		return {"valid": false, "affordable": false, "error": "Гаражные объекты улучшаются между выездами."}
	var garage_objects: Array[String] = ["WORKSHOP", "NEUROLAB", "SERVER", "HANGAR", "MARKET", "INTEL", "GARAGE_MED", "CALIBRATOR"]
	if not garage_objects.has(object_id):
		return {"valid": false, "affordable": false, "error": "Неизвестный объект гаража."}
	var level: int = garage_level(object_id)
	if level < 1 or level >= 3:
		return {"valid": false, "affordable": false, "error": "Объект уже достиг максимального уровня."}
	var target_level: int = level + 1
	var cleared: int = state.meta.max_sector_cleared
	if object_id == "NEUROLAB" and target_level == 2 and cleared < 5:
		return {"valid": false, "affordable": false, "error": "NEUROLAB L2 требует завершить сектор 5."}
	if object_id == "NEUROLAB" and target_level == 3 and cleared < 9:
		return {"valid": false, "affordable": false, "error": "NEUROLAB L3 требует завершить сектор 9."}
	if object_id == "HANGAR" and target_level == 2 and cleared < 6:
		return {"valid": false, "affordable": false, "error": "HANGAR L2 требует завершить сектор 6."}
	var scale: float = CydleFormula.new().reward_scale(float(state.meta.unlocked_forpost + 1))
	var credits_cost: int = ceili((40.0 + 25.0 * float(level)) * scale)
	var scrap_cost: int = ceili((15.0 + 10.0 * float(level)) * scale)
	var data_cost: int = 0
	if object_id == "CALIBRATOR":
		data_cost = ceili(5.0 * scale)
	elif object_id == "SERVER" and target_level == 3:
		data_cost = 10
	var credits_available: float = state.meta.protected_bank.credits
	var scrap_available: float = state.meta.protected_bank.scrap
	var data_available: float = state.meta.protected_bank.data
	var affordable: bool = credits_available >= credits_cost and scrap_available >= scrap_cost and data_available >= data_cost
	var reason: String = ""
	if credits_available < credits_cost:
		reason = "Нужно %d CREDITS" % credits_cost
	elif scrap_available < scrap_cost:
		reason = "Нужно %d SCRAP" % scrap_cost
	elif data_available < data_cost:
		reason = "Нужно %d DATA" % data_cost
	return {"valid": true, "affordable": affordable, "error": reason, "objectId": object_id, "currentLevel": level, "targetLevel": target_level, "credits": credits_cost, "scrap": scrap_cost, "data": data_cost}

func upgrade_garage_object(object_id: String) -> bool:
	var quote: Dictionary = garage_upgrade_quote(object_id)
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Улучшение гаража недоступно."))
		return false
	if not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Недостаточно ресурсов для улучшения."))
		return false
	var payload: Dictionary = state.to_payload()
	var meta: Dictionary = payload["meta"]
	var target_level: int = int(quote["targetLevel"])
	meta["garage"][object_id] = target_level
	meta["protectedBank"]["CREDITS"] = float(meta["protectedBank"].get("CREDITS", 0.0)) - float(quote["credits"])
	meta["protectedBank"]["SCRAP"] = float(meta["protectedBank"].get("SCRAP", 0.0)) - float(quote["scrap"])
	meta["protectedBank"]["DATA"] = float(meta["protectedBank"].get("DATA", 0.0)) - float(quote["data"])
	if object_id == "NEUROLAB":
		meta["unlockedImplantSlots"] = 4 + (1 if target_level >= 2 else 0) + (1 if target_level >= 3 else 0)
	if object_id == "HANGAR" and target_level >= 2:
		meta["unlockedDroneSlots"] = 2
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Улучшение гаража не прошло проверку сохранения."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
	if not bool(resolved.get("valid", false)):
		last_error = "Улучшение отклонено BuildResolver: %s" % str(resolved.get("issues", []))
		return false
	return _commit(candidate)

func extract_run() -> bool:
	if state == null or state.run == null:
		last_error = "Нет активного выезда для эвакуации."
		return false
	if state.run.phase != "CHECKPOINT":
		last_error = "Эвакуация доступна на контрольном узле."
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var meta: Dictionary = payload["meta"]
	var bank: Dictionary = meta["protectedBank"]
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		bank[currency] = float(bank.get(currency, 0.0)) + float(run_payload["runWallet"].get(currency, 0.0))
	for item: Dictionary in run_payload["unsecuredCargo"]:
		var secured: Dictionary = item.duplicate(true)
		secured["secured"] = true
		secured["origin"] = "extraction"
		if not _inventory_has(meta["inventory"], str(secured.get("itemId", ""))):
			meta["inventory"].append(secured)
	run_payload["unsecuredCargo"] = []
	run_payload["runWallet"] = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	run_payload["temporaryMutationIds"] = []
	var resources: Dictionary = run_payload["resources"]
	var transport: Dictionary = meta["transport"]
	transport["fuel"] = int(resources.get("fuel", transport.get("fuel", 0)))
	transport["hull"] = int(resources.get("hull", transport.get("hull", 0)))
	if int(run_payload["depth"]) == 1:
		meta["tutorial"]["firstSectorCompleted"] = true
	for item: Dictionary in meta["inventory"]:
		if ["IMP_HEAT", "IMP_VIRUS", "IMP_SHIELD"].has(str(item.get("templateId", ""))) and bool(item.get("secured", false)):
			meta["tutorial"]["starterPrototypeSecured"] = true
			break
	run_payload["phase"] = "EXTRACTED"
	run_payload["lastCommandId"] = "extract:%s" % str(run_payload["seed"])
	return _commit_payload(payload)

func _build_input(save_state: GameSaveState) -> Dictionary:
	var items_by_id: Dictionary = {}
	for item: Dictionary in save_state.meta.inventory:
		items_by_id[str(item.get("itemId", ""))] = item
	var equipment: Dictionary = {}
	for slot_value: Variant in save_state.meta.equipment.keys():
		var raw: Dictionary = items_by_id.get(str(save_state.meta.equipment[slot_value]), {})
		if raw.is_empty():
			continue
		var item: ItemInstance = ItemInstance.new()
		if item.instantiate_from_dictionary(raw):
			equipment[str(slot_value)] = item
	var operator: GameSaveState.OperatorState = save_state.meta.operator
	return {
		"equipment": equipment, "attributes": operator.attributes,
		"skillIds": save_state.meta.skill_ids, "passiveIds": save_state.meta.passive_ids,
		"treeNodeIds": save_state.meta.tree_node_ids,
		"mutationIds": save_state.run.temporary_mutation_ids if save_state.run != null else [],
		"attributePointsEarned": operator.attribute_points, "treePointsEarned": operator.tree_points,
		"unlockedImplantSlots": save_state.meta.unlocked_implant_slots,
		"unlockedDroneSlots": save_state.meta.unlocked_drone_slots,
	}

func _persist_combat_snapshot() -> bool:
	if state == null or state.run == null or _combat == null:
		last_error = "Нельзя сохранить снимок: нет активного профиля, выезда или боя."
		return false
	var snapshot: GameSaveState.CombatSnapshotState = GameSaveState.CombatSnapshotState.new()
	snapshot.sim_time_ms = _combat.time_ms
	snapshot.actors = [{
		"combatState": _combat.to_dictionary(), "nodeType": _active_node_type,
		"rewardModifiers": _active_reward_modifiers.duplicate(true),
	}]
	snapshot.event_queue = []
	snapshot.rng_streams = [_combat.rng.duplicate(true)]
	snapshot.event_log = _combat.log.duplicate(true)
	snapshot.next_sequence_id = _combat.next_event_id
	snapshot.rules_hash = _combat.rules_hash
	var payload: Dictionary = state.to_payload()
	payload["run"]["combatSnapshot"] = snapshot.to_dictionary()
	return _commit_payload(payload)

func _restore_combat_snapshot() -> bool:
	var snapshot: GameSaveState.CombatSnapshotState = state.run.combat_snapshot
	if snapshot.actors.is_empty() or not snapshot.actors[0] is Dictionary:
		last_error = "Снимок активного боя пуст или повреждён."
		return false
	var saved: Dictionary = snapshot.actors[0]
	var serialized: Variant = saved.get("combatState")
	if not serialized is Dictionary:
		last_error = "В снимке отсутствует сериализованное состояние симулятора."
		return false
	var build: Dictionary = build_preview()
	if not bool(build.get("valid", false)):
		last_error = "Нельзя восстановить бой: сохранённая сборка недействительна."
		return false
	var restored: CombatState = CombatState.from_dictionary(serialized, build)
	if restored == null or restored.time_ms != snapshot.sim_time_ms or restored.rules_hash != snapshot.rules_hash:
		last_error = "Снимок боя не прошёл проверку времени/правил."
		return false
	_combat = restored
	_active_node_type = str(saved.get("nodeType", restored.node_type))
	_active_reward_modifiers = saved.get("rewardModifiers", {}).duplicate(true)
	return true

func _slot_accepts(slot: String, category: String) -> bool:
	match category:
		"MAIN": return slot == "MAIN"
		"OFFHAND": return slot == "OFFHAND"
		"ARMOR": return slot == "ARMOR"
		"IMPLANT": return slot.begins_with("IMP_")
		"DRONE": return slot.begins_with("DRONE_")
	return false

func _inventory_has(items: Array, item_id: String) -> bool:
	for item: Variant in items:
		if item is Dictionary and str(item.get("itemId", "")) == item_id:
			return true
	return false

func _commit(candidate: GameSaveState) -> bool:
	candidate.updated_at = int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = _repository.save_game(SLOT_ID, candidate, candidate.updated_at)
	if not bool(saved.get("ok", false)):
		last_error = str(saved.get("error", "Не удалось сохранить профиль."))
		return false
	state = candidate
	last_error = ""
	return true

func _commit_payload(payload: Dictionary) -> bool:
	payload["updatedAt"] = int(Time.get_unix_time_from_system() * 1000.0)
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Изменение не прошло проверку сохранения."))
		return false
	return _commit(parsed["state"] as GameSaveState)
