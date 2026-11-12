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
var _item_catalog: ItemCatalog = ItemCatalog.new()
var _loot_rng: DeterministicRng

func configure_save_directory(path: String) -> void:
	_repository.configure_directory(path)

func load_saved_game() -> bool:
	var loaded: Dictionary = _repository.load_game(SLOT_ID)
	if bool(loaded.get("ok", false)):
		state = loaded["state"] as GameSaveState
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
		"attributePointsEarned": operator.attribute_points, "treePointsEarned": operator.tree_points,
		"unlockedImplantSlots": state.meta.unlocked_implant_slots,
		"unlockedDroneSlots": state.meta.unlocked_drone_slots,
	})

func start_expedition(seed_value: String = "") -> bool:
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
	var generated: Dictionary = _generator.generate(seed, next_depth, biome, false, state.run.wanted)
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
	run_payload["eventsSeen"] = []
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
			var categories: Array[String] = ["MAIN", "MAIN", "IMPLANT", "ARMOR", "DRONE"]
			var stock: Array[Dictionary] = []
			for index: int in range(categories.size()):
				var grant_id: String = "shop:%s:%s:%d" % [state.run.seed, node_id, index]
				var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, {
					"depth": state.run.depth, "biome": state.run.biome, "table": "ORDINARY",
					"forceCategory": categories[index], "secured": false, "grantId": grant_id,
					"origin": "shop", "acquiredAt": state.updated_at,
				})
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
	var effective_tactic: Dictionary = tactic
	if not _supports_current_tactics(tactic):
		effective_tactic = {"id": "BASIC_AUTO", "name": "Базовый автопилот", "rules": [
			{"id": "basic-auto", "priority": 0, "enabled": true, "skillId": "AUTO", "target": "nearest", "conditions": []},
		]}
		combat_notice = "Профиль «%s» содержит ещё не подключённые условия/умения. Этот бой использует только автоатаку; сохранённый профиль не изменён." % str(tactic.get("name", tactic.get("id", "")))
	var resources: Dictionary = state.run.resources
	var config: Dictionary = {
		"seed": "%s:%s" % [state.run.seed, state.run.current_node_id],
		"depth": state.run.depth, "biome": state.run.biome, "nodeType": node["type"],
		"build": build, "enemies": node.get("enemies", []), "tactics": effective_tactic,
		"startHpFraction": float(resources.get("hp", 0.0)) / maxf(1.0, float(resources.get("maxHP", 1.0))),
		"startShieldFraction": float(resources.get("shield", 0.0)) / maxf(1.0, float(resources.get("maxShield", 1.0))),
		"startEnergy": float(resources.get("energy", 0.0)), "startHeat": float(resources.get("heat", 0.0)),
	}
	var initialized: Dictionary = _simulator.create_state(config)
	if not bool(initialized.get("ok", false)):
		last_error = str(initialized.get("error", "Боевой симулятор не смог создать встречу."))
		return false
	_combat = initialized["state"] as CombatState
	last_error = ""
	return true

func _supports_current_tactics(tactic: Dictionary) -> bool:
	for rule_value: Variant in tactic.get("rules", []):
		if not rule_value is Dictionary or not bool(rule_value.get("enabled", false)):
			continue
		if str(rule_value.get("skillId", "AUTO")) not in ["AUTO", "SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_PLASMA"]:
			return false
		if not rule_value.get("conditions", []).is_empty():
			return false
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
	_combat = stepped["state"] as CombatState
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
	var reward: Dictionary = _battle_reward(str(node.get("type", "COMBAT")), state.run.depth, state.run.biome, node_id, run_payload)
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
		_grant_experience(int(reward["xp"]))
		run_payload["grantIds"].append(xp_grant_id)
	if not run_payload["clearedNodeIds"].has(node_id):
		run_payload["clearedNodeIds"].append(node_id)
	run_payload["phase"] = "CHECKPOINT" if int(node.get("layer", 0)) == 5 else "ROUTE"
	run_payload["combatResult"] = null
	run_payload["lastCommandId"] = "combat:%s" % node_id
	var payload: Dictionary = state.to_payload()
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
	return true

func _battle_reward(node_type: String, depth: int, biome: String, node_id: String, run_payload: Dictionary) -> Dictionary:
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
	credits = ceili(credits * scale * (1.1 if biome == "B02" else 1.0))
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
	for index: int in range(grants.size()):
		var grant_id: String = "combat:%s:%s:item:%d" % [state.run.seed, node_id, index]
		if grants[index] <= 0.0 or not rng.chance(grants[index]):
			continue
		var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, {
			"depth": depth, "biome": biome, "table": table, "secured": false,
			"grantId": grant_id, "origin": "combat", "acquiredAt": state.updated_at,
		})
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

func _grant_experience(amount: int) -> void:
	if amount <= 0:
		return
	var operator: GameSaveState.OperatorState = state.meta.operator
	var xp: int = operator.xp + amount
	var level: int = operator.level
	var attribute_points: int = operator.attribute_points
	var tree_points: int = operator.tree_points
	while level < 61 and xp >= CydleFormula.new().xp_required(level):
		xp -= CydleFormula.new().xp_required(level)
		level += 1
		tree_points += 1
		if level <= 60 and level % 5 == 0:
			attribute_points += 1
	operator.xp = xp
	operator.level = level
	operator.attribute_points = attribute_points
	operator.tree_points = tree_points

func _resolve_combat_defeat(run_payload: Dictionary, node_id: String) -> bool:
	var equipped_ids: Array = state.meta.equipment.values()
	for index: int in range(state.meta.inventory.size()):
		var item: Dictionary = state.meta.inventory[index]
		if equipped_ids.has(str(item.get("itemId", ""))):
			item["durability"] = maxf(0.0, float(item.get("durability", 100.0)) - 20.0)
		state.meta.inventory[index] = item
	var paid: bool = state.meta.protected_bank.credits >= 10.0
	if paid:
		state.meta.protected_bank.credits -= 10.0
	var build: Dictionary = build_preview()
	var stats: Dictionary = build.get("stats", {})
	var resources: Dictionary = run_payload["resources"]
	resources["hp"] = float(stats.get("maxHP", 1.0)) * (1.0 if paid else 0.5)
	resources["maxHP"] = float(stats.get("maxHP", 1.0))
	resources["shield"] = float(stats.get("maxShield", 0.0)) if paid else 0.0
	resources["maxShield"] = float(stats.get("maxShield", 0.0))
	run_payload["phase"] = "DEFEATED"
	run_payload["combatResult"] = null
	run_payload["unsecuredCargo"] = []
	run_payload["shippedCargo"] = []
	run_payload["runWallet"] = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	run_payload["equipment"] = state.meta.equipment.duplicate(true)
	run_payload["lastCommandId"] = "combat:defeat:%s" % node_id
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	if not _commit_payload(payload):
		return false
	_combat = null
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
		"attributePointsEarned": operator.attribute_points, "treePointsEarned": operator.tree_points,
		"unlockedImplantSlots": save_state.meta.unlocked_implant_slots,
		"unlockedDroneSlots": save_state.meta.unlocked_drone_slots,
	}

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
