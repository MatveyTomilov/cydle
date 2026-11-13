class_name GameSaveFactory
extends RefCounted

const STARTER_ITEMS: Array[Dictionary] = [
	{"slot": "MAIN", "templateId": "PISTOL_K1"},
	{"slot": "OFFHAND", "templateId": "OFF_SHIELD"},
	{"slot": "ARMOR", "templateId": "ARM_CLOTH"},
	{"slot": "IMP_2", "templateId": "IMP_ARMOR"},
	{"slot": "IMP_3", "templateId": "IMP_REFLEX"},
	{"slot": "DRONE_1", "templateId": "DR_GUN"},
	{"slot": "ENGINE", "templateId": "TR_ENGINE_1"},
	{"slot": "CHASSIS", "templateId": "TR_CHASSIS_1"},
	{"slot": "SCANNER", "templateId": "TR_SCANNER_1"},
	{"slot": "SERVICE", "templateId": "TR_SERVICE_1"},
	{"slot": "CARGO", "templateId": "TR_CARGO_1"},
	{"slot": "SUPPORT", "templateId": "TR_SUPPORT_1"},
]

func create_initial_payload(save_id: String, now_ms: int) -> Dictionary:
	if save_id.is_empty() or now_ms < 0:
		return _failure("Стартовое сохранение требует непустой ID и неотрицательный timestamp.")
	var catalog: ItemCatalog = ItemCatalog.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return _failure("Не удалось загрузить каталог для стартового сохранения: %s" % str(catalog_result.get("error", "")))
	var loot: DeterministicRng = DeterministicRng.new()
	loot.seed("loot", "CYDLE_STARTER_V1:%s" % save_id)
	var factory: ItemFactory = ItemFactory.new()
	var inventory: Array[Dictionary] = []
	var equipment: Dictionary = {}
	for entry: Dictionary in STARTER_ITEMS:
		var created: Dictionary = factory.create_item(loot, catalog, {
			"templateId": entry["templateId"], "techLevel": 1, "rarity": "COMMON", "secured": true,
			"originGrantId": "starter:%s:%s" % [save_id, str(entry["slot"])], "origin": "starter", "acquiredAt": now_ms,
		})
		if not bool(created.get("ok", false)):
			return _failure("Не удалось создать стартовый предмет: %s" % str(created.get("error", "")))
		var item: ItemInstance = created["item"] as ItemInstance
		inventory.append(item.to_dictionary())
		equipment[str(entry["slot"])] = item.item_id
	var payload: Dictionary = {
		"schemaVersion": GameSaveState.SAVE_SCHEMA_VERSION,
		"balanceVersion": GameSaveState.BALANCE_VERSION,
		"gameVersion": GameSaveState.GAME_VERSION,
		"saveId": save_id,
		"createdAt": now_ms,
		"updatedAt": now_ms,
		"revision": 1,
		"meta": {
			"operator": {"level": 1, "xp": 0, "attributes": {"POW": 5, "REF": 5, "INT": 5, "ENG": 5, "SYN": 5}, "attributePoints": 0, "treePoints": 0},
			"tutorial": {"firstSectorCompleted": false, "starterPrototypeSecured": false},
			"reputation": {"F_VANTA": 0, "F_RUST": 0, "F_CHOIR": 0, "F_ECHO": 0},
			"campaignFlags": [],
			"transport": {"fuel": 24, "fuelMax": 24, "hull": 100, "hullMax": 100, "cargoCapacity": 20},
			"protectedBank": {"CREDITS": 120, "SCRAP": 30, "DATA": 20},
			"unsecuredWallet": {"CREDITS": 0, "SCRAP": 0, "DATA": 0},
			"inventory": inventory,
			"equipment": equipment,
			"garage": {"WORKSHOP": 1, "NEUROLAB": 1, "SERVER": 1, "HANGAR": 1, "MARKET": 1, "INTEL": 1, "GARAGE_MED": 1, "CALIBRATOR": 1},
			"unlockedForpost": 0,
			"maxSectorCleared": 0,
			"unlockedBiomes": ["B01"],
			"skillIds": ["SK_BURST", "SK_SHIELD", "SK_EMP"],
			"passiveIds": ["PP_ACCURACY", "PP_SHIELD"],
			"treeNodeIds": [],
			"unlockedImplantSlots": 4,
			"unlockedDroneSlots": 1,
			"tactics": [{"id": "DEFAULT", "name": "Тактика по умолчанию", "rules": [
				{"id": "starter-shield", "priority": 3, "enabled": true, "skillId": "SK_SHIELD", "target": "self", "conditions": [{"kind": "hpBelow", "value": 0.45}], "logic": "AND", "note": "Защита при низком HP"},
				{"id": "starter-emp", "priority": 2, "enabled": true, "skillId": "SK_EMP", "target": "imminentCast", "conditions": [{"kind": "enemyCasting", "interruptibleOnly": true}], "logic": "AND", "note": "Прерывание опасного каста"},
				{"id": "starter-burst", "priority": 1, "enabled": true, "skillId": "SK_BURST", "target": "nearest", "conditions": [{"kind": "always"}], "logic": "AND", "note": "Очередь по приоритетной цели"},
				{"id": "starter-auto", "priority": 0, "enabled": true, "skillId": "AUTO", "target": "nearest", "conditions": [{"kind": "always"}], "logic": "AND", "note": "Базовая атака"},
			]}],
			"activeTacticId": "DEFAULT",
			"autopilotProfiles": [
				{"id": "CAUTIOUS", "name": "Осторожный", "startDepth": 1, "enabled": false},
				{"id": "BALANCED", "name": "Сбалансированный", "startDepth": 1, "enabled": false},
				{"id": "AGGRESSIVE", "name": "Агрессивный", "startDepth": 1, "enabled": false},
			],
			"activeAutopilotProfileId": "BALANCED",
		},
		"run": null,
	}
	return {"ok": true, "payload": payload, "error": ""}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "payload": {}, "error": message}
