class_name GameSaveSchema
extends RefCounted

const SCHEMA_VERSION: int = 1
const BIOMES: Array[String] = ["B01", "B02", "B03", "B04", "B05", "B06"]
const RARITIES: Array[String] = ["COMMON", "MODIFIED", "RARE", "LEGENDARY", "UNIQUE"]
const GARAGE_KEYS: Array[String] = ["WORKSHOP", "NEUROLAB", "SERVER", "HANGAR", "MARKET", "INTEL", "GARAGE_MED", "CALIBRATOR"]
const ATTRIBUTE_KEYS: Array[String] = ["POW", "REF", "INT", "ENG", "SYN"]
const FACTION_KEYS: Array[String] = ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]
const WALLET_KEYS: Array[String] = ["CREDITS", "SCRAP", "DATA"]
const SLOT_KEYS: Array[String] = ["MAIN", "OFFHAND", "ARMOR", "IMP_1", "IMP_2", "IMP_3", "IMP_4", "IMP_5", "IMP_6", "DRONE_1", "DRONE_2", "ENGINE", "CHASSIS", "SCANNER", "SERVICE", "CARGO", "SUPPORT"]

func validate_payload(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("save: ожидался объект.")
	var payload: Dictionary = value
	if _is_integer(payload.get("schemaVersion")) and int(payload["schemaVersion"]) > SCHEMA_VERSION:
		return _failure("Сохранение использует будущую игровую схему %d; поддерживается версия %d." % [int(payload["schemaVersion"]), SCHEMA_VERSION])
	if not _has_exact_keys(payload, ["schemaVersion", "balanceVersion", "gameVersion", "saveId", "createdAt", "updatedAt", "revision", "meta", "run"]):
		return _failure("save: отсутствуют обязательные поля или есть неизвестные поля.")
	if not _is_integer(payload["schemaVersion"]) or int(payload["schemaVersion"]) != SCHEMA_VERSION:
		return _failure("schemaVersion: неподдерживаемая версия.")
	for key: String in ["balanceVersion", "gameVersion", "saveId"]:
		if not payload[key] is String or str(payload[key]).is_empty():
			return _failure("%s: ожидалась непустая строка." % key)
	for key: String in ["createdAt", "updatedAt"]:
		if not _is_finite_number(payload[key]) or float(payload[key]) < 0.0:
			return _failure("%s: ожидалось конечное неотрицательное число." % key)
	if not _is_integer(payload["revision"]) or int(payload["revision"]) < 1:
		return _failure("revision: ожидалось целое число не меньше 1.")
	var meta_result: Dictionary = _validate_meta(payload["meta"])
	if not bool(meta_result.get("ok", false)):
		return meta_result
	if payload["run"] != null:
		var run_result: Dictionary = _validate_run(payload["run"], payload["meta"])
		if not bool(run_result.get("ok", false)):
			return run_result
	return {"ok": true, "error": ""}

func _validate_meta(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("meta: ожидался объект.")
	var meta: Dictionary = value
	var keys: Array[String] = ["operator", "tutorial", "reputation", "campaignFlags", "transport", "protectedBank", "unsecuredWallet", "inventory", "equipment", "garage", "unlockedForpost", "maxSectorCleared", "unlockedBiomes", "skillIds", "passiveIds", "treeNodeIds", "unlockedImplantSlots", "unlockedDroneSlots", "tactics", "activeTacticId", "autopilotProfiles"]
	var meta_allowed: Array[String] = keys.duplicate()
	meta_allowed.append("questProgress")
	meta_allowed.append("disassemblyHistory")
	meta_allowed.append("disassemblyUndo")
	if not _has_keys(meta, keys) or not _has_only_keys(meta, meta_allowed):
		return _failure("meta: отсутствуют обязательные поля или есть неизвестные поля.")
	if meta.has("questProgress") and not _validate_quest_progress(meta["questProgress"]):
		return _failure("meta.questProgress: состояние заданий повреждено.")
	if meta.has("disassemblyHistory") and not _validate_disassembly_history(meta["disassemblyHistory"]):
		return _failure("meta.disassemblyHistory: история разбора повреждена.")
	if meta.has("disassemblyUndo") and not _validate_disassembly_undo(meta["disassemblyUndo"]):
		return _failure("meta.disassemblyUndo: запись отмены разбора повреждена.")
	var operator_value: Variant = meta["operator"]
	if not operator_value is Dictionary or not _has_exact_keys(operator_value, ["level", "xp", "attributes", "attributePoints", "treePoints"]):
		return _failure("meta.operator: неверная структура.")
	var operator: Dictionary = operator_value
	if not _is_integer(operator["level"]) or int(operator["level"]) < 1 or int(operator["level"]) > 999:
		return _failure("meta.operator.level: вне допустимого диапазона.")
	for key: String in ["xp", "attributePoints", "treePoints"]:
		if not _is_integer(operator[key]) or int(operator[key]) < 0:
			return _failure("meta.operator.%s: ожидалось неотрицательное целое число." % key)
	if not _is_number_map(operator["attributes"], ATTRIBUTE_KEYS, 1.0, 999.0, true):
		return _failure("meta.operator.attributes: требуются пять атрибутов с целыми значениями не меньше 1.")
	if not meta["tutorial"] is Dictionary or not _has_exact_keys(meta["tutorial"], ["firstSectorCompleted", "starterPrototypeSecured"]):
		return _failure("meta.tutorial: неверная структура.")
	for key: String in ["firstSectorCompleted", "starterPrototypeSecured"]:
		if not meta["tutorial"][key] is bool:
			return _failure("meta.tutorial.%s: ожидалось логическое значение." % key)
	if not _is_number_map(meta["reputation"], FACTION_KEYS, -100.0, 100.0, true):
		return _failure("meta.reputation: ожидались четыре целые репутации от -100 до 100.")
	if not _string_array(meta["campaignFlags"]) or not _validate_transport(meta["transport"]):
		return _failure("meta.campaignFlags или meta.transport: неверные данные.")
	if not _validate_wallet(meta["protectedBank"]) or not _validate_wallet(meta["unsecuredWallet"]):
		return _failure("meta.wallet: баланс должен содержать конечные неотрицательные значения.")
	if not meta["inventory"] is Array or not meta["equipment"] is Dictionary or not _has_only_keys(meta["equipment"], SLOT_KEYS):
		return _failure("meta.inventory/equipment: неверная структура.")
	var catalog: ItemCatalog = ItemCatalog.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return _failure("meta.inventory: каталог предметов недоступен: %s" % str(catalog_result.get("error", "")))
	var item_ids: Dictionary = {}
	var items_by_id: Dictionary = {}
	for item_value: Variant in meta["inventory"]:
		if not item_value is Dictionary or not _validate_item(item_value):
			return _failure("meta.inventory: экземпляр предмета имеет неверную структуру.")
		var item_id: String = str(item_value["itemId"])
		if item_ids.has(item_id):
			return _failure("meta.inventory: повторяется ID экземпляра предмета %s." % item_id)
		var template: Dictionary = catalog.get_template(str(item_value["templateId"]))
		if template.is_empty():
			return _failure("meta.inventory.%s: неизвестный шаблон предмета %s." % [item_id, str(item_value["templateId"])])
		if not _validate_item_catalog_refs(item_value, template, catalog):
			return _failure("meta.inventory.%s: аффиксы или уникальные эффекты не соответствуют каталогу." % item_id)
		item_ids[item_id] = true
		var item: ItemInstance = ItemInstance.new()
		if not item.instantiate_from_dictionary(item_value):
			return _failure("meta.inventory.%s: экземпляр предмета не удалось разобрать." % item_id)
		items_by_id[item_id] = item
	for slot_value: Variant in meta["equipment"].keys():
		var item_id: String = str(meta["equipment"][slot_value])
		if not item_ids.has(item_id):
			return _failure("meta.equipment.%s: предмет отсутствует в инвентаре." % str(slot_value))
	var build_result: Dictionary = _validate_meta_build(meta, items_by_id)
	if not bool(build_result.get("ok", false)):
		return build_result
	if not _is_number_map(meta["garage"], GARAGE_KEYS, 1.0, 3.0, true):
		return _failure("meta.garage: уровни гаража должны быть целыми от 1 до 3.")
	if not _is_integer(meta["unlockedForpost"]) or int(meta["unlockedForpost"]) < 0 or int(meta["unlockedForpost"]) > 12:
		return _failure("meta.unlockedForpost: недопустимая глубина.")
	if not _is_integer(meta["maxSectorCleared"]) or int(meta["maxSectorCleared"]) < 0:
		return _failure("meta.maxSectorCleared: ожидалось неотрицательное целое число.")
	if not _enum_string_array(meta["unlockedBiomes"], BIOMES) or not _string_array(meta["skillIds"]) or meta["skillIds"].size() > 3:
		return _failure("meta.unlockedBiomes/skillIds: неверный список.")
	if not _string_array(meta["passiveIds"]) or meta["passiveIds"].size() > 3 or not _string_array(meta["treeNodeIds"]):
		return _failure("meta.passiveIds/treeNodeIds: неверный список.")
	if not _is_integer(meta["unlockedImplantSlots"]) or int(meta["unlockedImplantSlots"]) < 4 or int(meta["unlockedImplantSlots"]) > 6:
		return _failure("meta.unlockedImplantSlots: ожидалось значение от 4 до 6.")
	if not _is_integer(meta["unlockedDroneSlots"]) or int(meta["unlockedDroneSlots"]) < 1 or int(meta["unlockedDroneSlots"]) > 2:
		return _failure("meta.unlockedDroneSlots: ожидалось значение 1 или 2.")
	if not _validate_profiles(meta["tactics"], meta["activeTacticId"], "tactics"):
		return _failure("meta.tactics: профиль пуст, повреждён или activeTacticId неизвестен.")
	if not meta["autopilotProfiles"] is Array or meta["autopilotProfiles"].is_empty():
		return _failure("meta.autopilotProfiles: требуется хотя бы один профиль.")
	for profile: Variant in meta["autopilotProfiles"]:
		if not profile is Dictionary or not _has_exact_keys(profile, ["id", "name", "startDepth", "enabled"]):
			return _failure("meta.autopilotProfiles: неверная структура профиля.")
		if not _nonempty_string(profile["id"]) or not _nonempty_string(profile["name"]) or not _is_integer(profile["startDepth"]) or int(profile["startDepth"]) < 1 or int(profile["startDepth"]) > 13 or not profile["enabled"] is bool:
			return _failure("meta.autopilotProfiles: неверные значения профиля.")
	return {"ok": true, "error": ""}

func _validate_run(value: Variant, meta: Dictionary) -> Dictionary:
	if not value is Dictionary:
		return _failure("run: ожидался объект или null.")
	var run: Dictionary = value
	var required: Array[String] = ["seed", "depth", "biome", "graph", "equipment", "currentNodeId", "visitedNodeIds", "clearedNodeIds", "phase", "wanted", "revealLevel", "resources", "runWallet", "unsecuredCargo", "shippedCargo", "grantIds", "commandIds", "serviceScrapFuelCounts", "shippedCheckpointIds", "combatResult", "lastCommandId", "worldRng", "lootRng"]
	if not _has_keys(run, required):
		return _failure("run: отсутствуют обязательные поля.")
	if not _nonempty_string(run["seed"]) or not _is_integer(run["depth"]) or int(run["depth"]) < 1 or not BIOMES.has(str(run["biome"])):
		return _failure("run.seed/depth/biome: неверные значения.")
	if not run["graph"] is Dictionary or not run["equipment"] is Dictionary or not _nonempty_string(run["currentNodeId"]):
		return _failure("run.graph/equipment/currentNodeId: неверная структура.")
	if not _string_array(run["visitedNodeIds"]) or not _string_array(run["clearedNodeIds"]) or not _string_array(run.get("eventsSeen", [])) or not _string_array(run["grantIds"]) or not _string_array(run["commandIds"]) or not _string_array(run["shippedCheckpointIds"]):
		return _failure("run: неверный список ID.")
	var scouted_node_ids: Variant = run.get("scoutedNodeIds", [])
	if not _string_array(scouted_node_ids) or scouted_node_ids.size() > 128 or not _unique_strings(scouted_node_ids):
		return _failure("run.scoutedNodeIds: неверный список разведанных узлов.")
	if not _string_array(run.get("temporaryMutationIds", [])) or run.get("temporaryMutationIds", []).size() > 2:
		return _failure("run.temporaryMutationIds: неверный список временных мутаций.")
	var build_catalog: BuildCatalog = BuildCatalog.new()
	var build_catalog_result: Dictionary = build_catalog.load_catalog()
	if not bool(build_catalog_result.get("ok", false)):
		return _failure("run: каталог сборки недоступен для проверки мутаций.")
	for mutation_id: Variant in run.get("temporaryMutationIds", []):
		if not build_catalog.mutations.has(str(mutation_id)):
			return _failure("run.temporaryMutationIds: неизвестная мутация %s." % str(mutation_id))
	if run["commandIds"].size() > 128 or not _unique_strings(run["grantIds"]) or not _unique_strings(run["commandIds"]):
		return _failure("run: ID наград/команд повторяются или лимит команд превышен.")
	if not ["ROUTE", "NODE", "CHECKPOINT", "EXTRACTED", "TOWED", "ABANDONED", "DEFEATED", "SAFE_ERROR_STOP"].has(str(run["phase"])):
		return _failure("run.phase: неизвестное состояние.")
	if not _is_finite_number(run["wanted"]) or float(run["wanted"]) < 0.0 or float(run["wanted"]) > 100.0:
		return _failure("run.wanted: ожидалось значение от 0 до 100.")
	if not _is_integer(run["revealLevel"]) or int(run["revealLevel"]) < 0 or int(run["revealLevel"]) > 2:
		return _failure("run.revealLevel: ожидалось значение от 0 до 2.")
	if not run["resources"] is Dictionary or not _validate_wallet(run["runWallet"]):
		return _failure("run.resources/runWallet: неверная структура.")
	if not _is_integer(run.get("pendingTravelDeltaMs", 0)) or int(run.get("pendingTravelDeltaMs", 0)) < -60000 or int(run.get("pendingTravelDeltaMs", 0)) > 60000:
		return _failure("run.pendingTravelDeltaMs: ожидалось целое число от -60000 до 60000.")
	if not _validate_pending_combat_effects(run.get("pendingCombatEffects", {"initialTempShield": 0.0, "extraHeat": 0.0})):
		return _failure("run.pendingCombatEffects: неверные значения.")
	if not _validate_pending_next_combat(run.get("pendingNextCombat", {
		"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false,
		"bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false,
		"alliedTurret": false, "extraRareOnElite": false,
	})):
		return _failure("run.pendingNextCombat: неверная структура.")
	if run.has("contract") and not _validate_contract_instance(run["contract"]):
		return _failure("run.contract: неверный активный контракт.")
	if run.has("autopilotEnabled") and not run["autopilotEnabled"] is bool:
		return _failure("run.autopilotEnabled: ожидалось логическое значение.")
	if not _validate_count_map(run["serviceScrapFuelCounts"]) or run["lastCommandId"] != null and not _nonempty_string(run["lastCommandId"]):
		return _failure("run.serviceScrapFuelCounts/lastCommandId: неверные значения.")
	if run["combatResult"] != null and not run["combatResult"] is Dictionary:
		return _failure("run.combatResult: ожидался объект или null.")
	for key: String in ["fuel", "maxFuel", "hull", "maxHull", "hp", "maxHP", "shield", "maxShield", "energy", "heat", "gameTimeMs"]:
		if not run["resources"].has(key) or not _is_finite_number(run["resources"][key]) or float(run["resources"][key]) < 0.0:
			return _failure("run.resources.%s: ожидалось конечное неотрицательное число." % key)
	if float(run["resources"]["fuel"]) > float(run["resources"]["maxFuel"]) or float(run["resources"]["hull"]) > float(run["resources"]["maxHull"]) or float(run["resources"]["hp"]) > float(run["resources"]["maxHP"]) or float(run["resources"]["shield"]) > float(run["resources"]["maxShield"]):
		return _failure("run.resources: текущее значение превышает максимум.")
	for key: String in ["unsecuredCargo", "shippedCargo"]:
		if not run[key] is Array:
			return _failure("run.%s: ожидался массив." % key)
	for key: String in ["worldRng", "lootRng"]:
		if not _validate_rng(run[key]):
			return _failure("run.%s: неверное состояние RNG." % key)
	if run.has("combatSnapshot") and run["combatSnapshot"] != null and not _validate_combat_snapshot(run["combatSnapshot"]):
		return _failure("run.combatSnapshot: снимок боя повреждён.")
	var ownership_result: Dictionary = _validate_run_ownership(run, meta)
	if not bool(ownership_result.get("ok", false)):
		return ownership_result
	return {"ok": true, "error": ""}

func _validate_contract_instance(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	var contract: Dictionary = value
	if not _nonempty_string(contract.get("id")) or not _nonempty_string(contract.get("instanceId")) or not _nonempty_string(contract.get("kind")):
		return false
	if not ["HUNT", "TECH", "ESCORT"].has(str(contract["kind"])) or not ["ACTIVE", "COMPLETE", "FAILED"].has(str(contract.get("status", ""))):
		return false
	if not BIOMES.has(str(contract.get("targetBiome", ""))) or not _is_integer(contract.get("combatNodes", 0)) or int(contract.get("combatNodes", 0)) < 0:
		return false
	return true

func _validate_run_ownership(run: Dictionary, meta: Dictionary) -> Dictionary:
	var catalog: ItemCatalog = ItemCatalog.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return _failure("run: каталог предметов недоступен: %s" % str(catalog_result.get("error", "")))
	var available_items: Dictionary = {}
	for item_value: Variant in meta["inventory"]:
		available_items[str(item_value["itemId"])] = item_value
	for item_value: Variant in run["unsecuredCargo"]:
		if not item_value is Dictionary or not _validate_item(item_value):
			return _failure("run.unsecuredCargo: экземпляр предмета имеет неверную структуру.")
		var item_id: String = str(item_value["itemId"])
		if available_items.has(item_id):
			return _failure("run: ID предмета %s повторяется в собственности и грузе." % item_id)
		var template: Dictionary = catalog.get_template(str(item_value["templateId"]))
		if template.is_empty() or not _validate_item_catalog_refs(item_value, template, catalog):
			return _failure("run.unsecuredCargo.%s: шаблон или эффекты предмета отсутствуют в каталоге." % item_id)
		available_items[item_id] = item_value
	for item_value: Variant in run["shippedCargo"]:
		if not item_value is Dictionary or not _validate_item(item_value):
			return _failure("run.shippedCargo: экземпляр предмета имеет неверную структуру.")
		var template: Dictionary = catalog.get_template(str(item_value["templateId"]))
		if template.is_empty() or not _validate_item_catalog_refs(item_value, template, catalog):
			return _failure("run.shippedCargo: шаблон или эффекты предмета отсутствуют в каталоге.")
	var run_equipment: Variant = run["equipment"]
	if not _has_only_keys(run_equipment, SLOT_KEYS):
		return _failure("run.equipment: неизвестный слот экипировки.")
	var equipped_ids: Dictionary = {}
	var build_equipment: Dictionary = {}
	for slot_value: Variant in run_equipment.keys():
		var item_id: String = str(run_equipment[slot_value])
		if not available_items.has(item_id):
			return _failure("run.equipment.%s: предмет отсутствует среди доступных." % str(slot_value))
		if equipped_ids.has(item_id):
			return _failure("run.equipment: предмет %s установлен более одного раза." % item_id)
		equipped_ids[item_id] = true
		var item: ItemInstance = ItemInstance.new()
		if not item.instantiate_from_dictionary(available_items[item_id]):
			return _failure("run.equipment.%s: экземпляр предмета повреждён." % str(slot_value))
		build_equipment[str(slot_value)] = item
	var operator: Dictionary = meta["operator"]
	var build: Dictionary = BuildResolver.new().resolve_build({
		"equipment": build_equipment,
		"attributes": operator["attributes"],
		"attributePointsEarned": operator["attributePoints"],
		"treePointsEarned": operator["treePoints"],
		"skillIds": meta["skillIds"],
		"passiveIds": meta["passiveIds"],
		"treeNodeIds": meta["treeNodeIds"],
		"unlockedImplantSlots": meta["unlockedImplantSlots"],
		"unlockedDroneSlots": meta["unlockedDroneSlots"],
	})
	if not bool(build.get("valid", false)):
		return _failure("run.build: полевая сборка некорректна.")
	return {"ok": true, "error": ""}

func _validate_pending_combat_effects(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["initialTempShield", "extraHeat"]):
		return false
	return _is_finite_number(value["initialTempShield"]) and float(value["initialTempShield"]) >= 0.0 and float(value["initialTempShield"]) <= 200.0 and _is_finite_number(value["extraHeat"]) and float(value["extraHeat"]) >= 0.0 and float(value["extraHeat"]) <= 100.0

func _validate_pending_next_combat(value: Variant) -> bool:
	var keys: Array[String] = ["skipOrdinary", "forceElite", "extraItemRoll", "forceBounty", "bountyCreditsBonus", "bountyEnemyId", "extraRareItemRoll", "alliedTurret", "extraRareOnElite"]
	if not value is Dictionary or not _has_exact_keys(value, keys):
		return false
	for key: String in ["skipOrdinary", "forceElite", "extraItemRoll", "forceBounty", "extraRareItemRoll", "alliedTurret", "extraRareOnElite"]:
		if not value[key] is bool:
			return false
	if not _is_finite_number(value["bountyCreditsBonus"]) or float(value["bountyCreditsBonus"]) < 0.0 or float(value["bountyCreditsBonus"]) > 1.0:
		return false
	return value["bountyEnemyId"] == null or _nonempty_string(value["bountyEnemyId"])

func _validate_count_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value.keys():
		if not _nonempty_string(key) or not _is_integer(value[key]) or int(value[key]) < 0 or int(value[key]) > 4:
			return false
	return true

func _validate_combat_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["simTimeMs", "actors", "eventQueue", "rngStreams", "eventLog", "nextSequenceId", "rulesHash"]):
		return false
	if not _is_integer(value["simTimeMs"]) or int(value["simTimeMs"]) < 0 or not _is_integer(value["nextSequenceId"]) or int(value["nextSequenceId"]) < 1:
		return false
	if not _nonempty_string(value["rulesHash"]):
		return false
	for key: String in ["actors", "eventQueue", "rngStreams", "eventLog"]:
		if not _dictionary_array(value[key]):
			return false
	if value["eventLog"].size() > 5000:
		return false
	for rng_value: Variant in value["rngStreams"]:
		if not _validate_rng(rng_value):
			return false
	return true

func _validate_rng(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["stream", "state", "calls"]):
		return false
	if not _nonempty_string(value["stream"]) or not value["state"] is Array or value["state"].size() != 4 or not _is_integer(value["calls"]) or int(value["calls"]) < 0:
		return false
	for word: Variant in value["state"]:
		if not _is_integer(word) or int(word) < 0 or int(word) > 4294967295:
			return false
	return true

func _validate_item(value: Dictionary) -> bool:
	var item: ItemInstance = ItemInstance.new()
	return item.instantiate_from_dictionary(value)

func _validate_item_catalog_refs(value: Dictionary, template: Dictionary, catalog: ItemCatalog) -> bool:
	if not value.get("uniqueEffectIds") is Array or not value.get("affixes") is Array:
		return false
	var expected_unique: Array = [str(template["uniqueEffectId"])] if template.has("uniqueEffectId") else []
	if value["uniqueEffectIds"] != expected_unique:
		return false
	for affix_value: Variant in value["affixes"]:
		var affix_id: String = str(affix_value.get("affixId", "")) if affix_value is Dictionary else ""
		var definition: Dictionary = catalog.get_affix(affix_id)
		if definition.is_empty() or not (definition.get("slots", []) as Array).has(str(template["category"])):
			return false
	return true

func _validate_meta_build(meta: Dictionary, items_by_id: Dictionary) -> Dictionary:
	var equipment: Dictionary = {}
	for slot_value: Variant in meta["equipment"].keys():
		var item_id: String = str(meta["equipment"][slot_value])
		if items_by_id.has(item_id):
			equipment[str(slot_value)] = items_by_id[item_id]
	var operator: Dictionary = meta["operator"]
	var resolver: BuildResolver = BuildResolver.new()
	var result: Dictionary = resolver.resolve_build({
		"equipment": equipment,
		"attributes": operator["attributes"],
		"attributePointsEarned": operator["attributePoints"],
		"treePointsEarned": operator["treePoints"],
		"skillIds": meta["skillIds"],
		"passiveIds": meta["passiveIds"],
		"treeNodeIds": meta["treeNodeIds"],
		"unlockedImplantSlots": meta["unlockedImplantSlots"],
		"unlockedDroneSlots": meta["unlockedDroneSlots"],
	})
	if not bool(result.get("valid", false)):
		var messages: PackedStringArray = PackedStringArray()
		for issue: Dictionary in result.get("issues", []):
			messages.append(str(issue.get("message", "Неверная сборка.")))
		return _failure("meta.build: %s" % " ".join(messages))
	return {"ok": true, "error": ""}

func _validate_transport(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["fuel", "fuelMax", "hull", "hullMax", "cargoCapacity"]):
		return false
	for key: String in ["fuel", "fuelMax", "hull", "hullMax", "cargoCapacity"]:
		if not _is_finite_number(value[key]) or float(value[key]) < 0.0:
			return false
	return float(value["fuel"]) <= float(value["fuelMax"]) and float(value["hull"]) <= float(value["hullMax"])

func _validate_wallet(value: Variant) -> bool:
	return _is_number_map(value, WALLET_KEYS, 0.0, 1.0e100, false)

func _validate_profiles(value: Variant, active_id: Variant, label: String) -> bool:
	if not value is Array or value.is_empty() or not _nonempty_string(active_id):
		return false
	var ids: Dictionary = {}
	for profile: Variant in value:
		if not profile is Dictionary or not _has_exact_keys(profile, ["id", "name", "rules"]):
			return false
		if not _nonempty_string(profile["id"]) or not _nonempty_string(profile["name"]) or not profile["rules"] is Array or profile["rules"].size() > 12 or ids.has(str(profile["id"])):
			return false
		ids[str(profile["id"])] = true
	return ids.has(str(active_id))

func _validate_quest_progress(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for quest_id: Variant in value.keys():
		var progress: Variant = value[quest_id]
		if not _nonempty_string(quest_id) or not progress is Dictionary or not _has_exact_keys(progress, ["status", "stage", "startedDepth", "stageStartedDepth", "completedStages", "choiceHistory", "flags"]):
			return false
		if not ["ACTIVE", "PAUSED", "COMPLETE", "FAILED"].has(str(progress["status"])):
			return false
		if not _is_integer(progress["stage"]) or int(progress["stage"]) < 1 or int(progress["stage"]) > 3 or not _is_integer(progress["startedDepth"]) or int(progress["startedDepth"]) < 1 or not _is_integer(progress["stageStartedDepth"]) or int(progress["stageStartedDepth"]) < 1:
			return false
		if not _string_array(progress["completedStages"]) or not _string_array(progress["flags"]) or not progress["choiceHistory"] is Array:
			return false
		for choice: Variant in progress["choiceHistory"]:
			if not choice is Dictionary or not _has_exact_keys(choice, ["stage", "choiceId", "nodeId"]) or not _is_integer(choice["stage"]) or int(choice["stage"]) < 1 or int(choice["stage"]) > 3 or not _nonempty_string(choice["choiceId"]) or not _nonempty_string(choice["nodeId"]):
				return false
	return true

func _validate_disassembly_history(value: Variant) -> bool:
	if not value is Array or value.size() > 100:
		return false
	for entry: Variant in value:
		if not entry is Dictionary or not _has_exact_keys(entry, ["itemId", "templateId", "seed", "reason", "scrap", "data", "createdAt", "undone"]):
			return false
		if not _nonempty_string(entry["itemId"]) or not _nonempty_string(entry["templateId"]) or not entry["seed"] is String or not _nonempty_string(entry["reason"]):
			return false
		for key: String in ["scrap", "data", "createdAt"]:
			if not _is_finite_number(entry[key]) or float(entry[key]) < 0.0:
				return false
		if not entry["undone"] is bool:
			return false
	return true

func _validate_disassembly_undo(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["item", "scrap", "data", "createdAt"]):
		return false
	if not value["item"] is Dictionary or not _validate_item(value["item"]):
		return false
	if not bool(value["item"].get("secured", false)):
		return false
	for key: String in ["scrap", "data", "createdAt"]:
		if not _is_finite_number(value[key]) or float(value[key]) < 0.0:
			return false
	return true

func _is_number_map(value: Variant, expected_keys: Array[String], minimum: float, maximum: float, must_be_int: bool) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, expected_keys):
		return false
	for key: String in expected_keys:
		if not _is_finite_number(value[key]) or float(value[key]) < minimum or float(value[key]) > maximum:
			return false
		if must_be_int and not _is_integer(value[key]):
			return false
	return true

func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not _nonempty_string(entry):
			return false
	return true

func _enum_string_array(value: Variant, allowed: Array[String]) -> bool:
	if not _string_array(value):
		return false
	for entry: Variant in value:
		if not allowed.has(str(entry)):
			return false
	return true

func _unique_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true

func _dictionary_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is Dictionary:
			return false
	return true

func _has_keys(value: Dictionary, required: Array[String]) -> bool:
	for key: String in required:
		if not value.has(key):
			return false
	return true

func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true

func _has_only_keys(value: Dictionary, allowed: Array[String]) -> bool:
	for key: Variant in value.keys():
		if not allowed.has(str(key)):
			return false
	return true

func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
