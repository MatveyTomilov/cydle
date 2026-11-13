class_name GameSession
extends RefCounted

const SLOT_ID: String = "cylde-main"
const COMBAT_PLAYBACK_PERSIST_INTERVAL_MS: int = 1000
const ENDGAME_ESCALATIONS: Array[String] = ["WANTED_PLUS", "HUNT_FAST", "REPAIR_RARE", "SCAN_DARK", "DRONE_WAR", "HEAT_FOG", "SHIELD_BREAK", "LONG_RUN"]

var state: GameSaveState
var last_error: String = ""
var combat_notice: String = ""
var last_autopilot_report: Dictionary = {}
var last_emergency_report: Dictionary = {}
var _repository: SaveRepository = SaveRepository.new()
var _generator: SectorGenerator = SectorGenerator.new()
var _stats: StatMath = StatMath.new()
var _simulator: CombatSimulator = CombatSimulator.new()
var _combat: CombatState
var _active_node_type: String = ""
var _active_reward_modifiers: Dictionary = {}
var _item_catalog: ItemCatalog = ItemCatalog.new()
var _item_catalog_ready: bool = false
var _loot_rng: DeterministicRng

func configure_save_directory(path: String) -> void:
	_repository.configure_directory(path)

func save_snapshots() -> Array[Dictionary]:
	return _repository.list_snapshots(SLOT_ID)

func restore_save_snapshot(snapshot_index: int) -> bool:
	var restored: Dictionary = _repository.restore_snapshot(SLOT_ID, snapshot_index)
	if not bool(restored.get("ok", false)):
		last_error = str(restored.get("error", "Не удалось восстановить копию."))
		return false
	return load_saved_game()

func load_saved_game() -> bool:
	var loaded: Dictionary = _repository.load_game(SLOT_ID)
	if bool(loaded.get("ok", false)):
		state = loaded["state"] as GameSaveState
		var offline_since_ms: int = state.updated_at
		if state.run != null and state.run.combat_snapshot != null:
			if not _restore_combat_snapshot():
				return false
		if state.run != null and state.run.autopilot_enabled and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
			var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
			var observed_offline_elapsed_ms: int = now_ms - offline_since_ms
			if observed_offline_elapsed_ms < 0:
				last_autopilot_report = simulate_autopilot(0, observed_offline_elapsed_ms, true)
			elif observed_offline_elapsed_ms >= 1000:
				last_autopilot_report = simulate_autopilot(observed_offline_elapsed_ms, observed_offline_elapsed_ms, true)
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

func run_build_preview() -> Dictionary:
	if state == null or state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		return build_preview()
	return BuildResolver.new().resolve_build(_run_build_input(state))

func _run_build_input(save_state: GameSaveState) -> Dictionary:
	var input: Dictionary = _build_input(save_state)
	if save_state.run == null:
		return input
	var items_by_id: Dictionary = {}
	for item: Dictionary in save_state.meta.inventory:
		items_by_id[str(item.get("itemId", ""))] = item
	for item: Dictionary in save_state.run.unsecured_cargo:
		items_by_id[str(item.get("itemId", ""))] = item
	var equipment: Dictionary = {}
	for slot_value: Variant in save_state.run.equipment.keys():
		var item: ItemInstance = ItemInstance.new()
		var raw: Dictionary = items_by_id.get(str(save_state.run.equipment[slot_value]), {})
		if not raw.is_empty() and item.instantiate_from_dictionary(raw):
			equipment[str(slot_value)] = item
	input["equipment"] = equipment
	return input

func run_equipped_slot(item_id: String) -> String:
	if state == null or state.run == null:
		return ""
	for slot_value: Variant in state.run.equipment.keys():
		if str(state.run.equipment[slot_value]) == item_id:
			return str(slot_value)
	return ""

func valid_run_equipment_slots(item_id: String) -> Array[String]:
	var result: Array[String] = []
	if not _run_equipment_change_allowed():
		return result
	var item: Dictionary = {}
	for candidate: Dictionary in state.run.unsecured_cargo:
		if str(candidate.get("itemId", "")) == item_id:
			item = candidate
			break
	if item.is_empty():
		last_error = "Предмет отсутствует в незакреплённом грузе."
		return result
	if not _item_catalog_loaded():
		return result
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	if template.is_empty():
		last_error = "Шаблон предмета отсутствует в каталоге."
		return result
	var candidates: Array[String] = []
	match str(template.get("category", "")):
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
	for slot: String in candidates:
		if not _run_slot_unlocked(slot):
			continue
		var payload: Dictionary = state.to_payload()
		var run_equipment: Dictionary = payload["run"]["equipment"]
		for equipped_slot: Variant in run_equipment.keys().duplicate():
			if str(run_equipment[equipped_slot]) == item_id:
				run_equipment.erase(equipped_slot)
		run_equipment[slot] = item_id
		var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
		if bool(parsed.get("ok", false)):
			result.append(slot)
	return result

func equip_run_item(slot: String, item_id: String) -> bool:
	if not _run_equipment_change_allowed():
		return false
	if not valid_run_equipment_slots(item_id).has(slot):
		last_error = "Предмет нельзя установить в выбранный полевой слот или сборка станет невалидной."
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var run_equipment: Dictionary = run_payload["equipment"]
	for equipped_slot: Variant in run_equipment.keys().duplicate():
		if str(run_equipment[equipped_slot]) == item_id:
			run_equipment.erase(equipped_slot)
	run_equipment[slot] = item_id
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Полевая сборка не прошла проверку."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var build: Dictionary = BuildResolver.new().resolve_build(_run_build_input(candidate))
	if not bool(build.get("valid", false)):
		last_error = "Полевая сборка невалидна: %s" % str(build.get("issues", []))
		return false
	var resources: Dictionary = run_payload["resources"]
	var stats: Dictionary = build.get("stats", {})
	for key_pair: Array in [["maxHP", "maxHP"], ["maxShield", "maxShield"], ["maxEnergy", "maxEnergy"]]:
		var resource_key: String = str(key_pair[0])
		resources[resource_key] = float(stats.get(str(key_pair[1]), resources.get(resource_key, 0.0)))
	resources["hp"] = minf(float(resources.get("hp", 0.0)), float(resources["maxHP"]))
	resources["shield"] = minf(float(resources.get("shield", 0.0)), float(resources["maxShield"]))
	resources["energy"] = minf(float(resources.get("energy", 0.0)), float(resources["maxEnergy"]))
	run_payload["lastCommandId"] = "run:equipment:%s:%s:%d" % [slot, item_id, state.revision]
	return _commit_payload(payload)

func unequip_run_item(slot: String) -> bool:
	if not _run_equipment_change_allowed():
		return false
	if not state.run.equipment.has(slot):
		last_error = "В выбранном полевом слоте нет предмета."
		return false
	var equipped_id: String = str(state.run.equipment[slot])
	var cargo_item: bool = false
	for item: Dictionary in state.run.unsecured_cargo:
		if str(item.get("itemId", "")) == equipped_id:
			cargo_item = true
			break
	if not cargo_item:
		last_error = "Снять этим действием можно только предмет из незакреплённого груза."
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var fallback_id: String = str(payload["meta"]["equipment"].get(slot, ""))
	if fallback_id.is_empty():
		run_payload["equipment"].erase(slot)
	else:
		run_payload["equipment"][slot] = fallback_id
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Возврат полевого слота не прошёл проверку."))
		return false
	var candidate: GameSaveState = parsed["state"] as GameSaveState
	var build: Dictionary = BuildResolver.new().resolve_build(_run_build_input(candidate))
	if not bool(build.get("valid", false)):
		last_error = "Полевая сборка невалидна: %s" % str(build.get("issues", []))
		return false
	var resources: Dictionary = run_payload["resources"]
	var stats: Dictionary = build.get("stats", {})
	for key_pair: Array in [["maxHP", "maxHP"], ["maxShield", "maxShield"], ["maxEnergy", "maxEnergy"]]:
		var resource_key: String = str(key_pair[0])
		resources[resource_key] = float(stats.get(str(key_pair[1]), resources.get(resource_key, 0.0)))
	resources["hp"] = minf(float(resources.get("hp", 0.0)), float(resources["maxHP"]))
	resources["shield"] = minf(float(resources.get("shield", 0.0)), float(resources["maxShield"]))
	resources["energy"] = minf(float(resources.get("energy", 0.0)), float(resources["maxEnergy"]))
	run_payload["lastCommandId"] = "run:equipment:restore:%s:%d" % [slot, state.revision]
	return _commit_payload(payload)

func _run_equipment_change_allowed() -> bool:
	if state == null or state.run == null or not ["ROUTE", "NODE", "CHECKPOINT"].has(state.run.phase) or _combat != null:
		last_error = "Полевое снаряжение меняется только между боями."
		return false
	return true

func _run_slot_unlocked(slot: String) -> bool:
	if slot.begins_with("IMP_"):
		return int(slot.trim_prefix("IMP_")) <= state.meta.unlocked_implant_slots
	if slot.begins_with("DRONE_"):
		return int(slot.trim_prefix("DRONE_")) <= state.meta.unlocked_drone_slots
	return BuildResolver.EQUIPMENT_SLOTS.has(slot)

func simulation_equipment_candidates(slot: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if state == null or not _garage_action_allowed() or not state.meta.equipment.has(slot):
		return candidates
	var catalog_result: Dictionary = _item_catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return candidates
	for item: Dictionary in state.meta.inventory:
		var item_id: String = str(item.get("itemId", ""))
		if not bool(item.get("secured", false)) or item_id == str(state.meta.equipment.get(slot, "")):
			continue
		var payload: Dictionary = state.to_payload()
		for equipped_slot: Variant in payload["meta"]["equipment"].keys().duplicate():
			if str(payload["meta"]["equipment"][equipped_slot]) == item_id:
				payload["meta"]["equipment"].erase(equipped_slot)
		payload["meta"]["equipment"][slot] = item_id
		var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
		if not bool(parsed.get("ok", false)):
			continue
		var candidate_state: GameSaveState = parsed["state"] as GameSaveState
		var build: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate_state))
		if not bool(build.get("valid", false)):
			continue
		var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
		var label: String = "%s · T%d" % [str(template.get("name", item.get("templateId", "Предмет"))), int(item.get("techLevel", 1))]
		candidates.append({"itemId": item_id, "label": label})
	return candidates

func simulate_equipment_comparison(slot: String, item_id: String, enemy_id: String, runs: int = 3) -> Dictionary:
	if state == null or not _garage_action_allowed():
		return {"ok": false, "error": "Simulation Lab доступна только в гараже между выездами."}
	if not state.meta.equipment.has(slot):
		return {"ok": false, "error": "Выбранный слот сейчас не экипирован."}
	var payload: Dictionary = state.to_payload()
	var item_found: bool = false
	for item: Dictionary in payload["meta"]["inventory"]:
		if str(item.get("itemId", "")) == item_id and bool(item.get("secured", false)):
			item_found = true
			break
	if not item_found:
		return {"ok": false, "error": "Предмет для сравнения отсутствует на складе."}
	for equipped_slot: Variant in payload["meta"]["equipment"].keys().duplicate():
		if str(payload["meta"]["equipment"][equipped_slot]) == item_id:
			payload["meta"]["equipment"].erase(equipped_slot)
	payload["meta"]["equipment"][slot] = item_id
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": str(parsed.get("error", "Кандидатская сборка не прошла проверку."))}
	var candidate_state: GameSaveState = parsed["state"] as GameSaveState
	var current_build: Dictionary = build_preview()
	var candidate_build: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate_state))
	if not bool(candidate_build.get("valid", false)):
		return {"ok": false, "error": "Кандидатская сборка отклонена BuildResolver: %s" % str(candidate_build.get("issues", []))}
	var enemy_catalog: EnemyCatalog = EnemyCatalog.new()
	var loaded: Dictionary = enemy_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "error": str(loaded.get("error", "Каталог противников недоступен."))}
	var enemy: Dictionary = enemy_catalog.get_template(enemy_id)
	if enemy.is_empty():
		return {"ok": false, "error": "Враг или босс %s отсутствует в каталоге." % enemy_id}
	var tactic: Dictionary = active_tactic()
	for rule: Dictionary in tactic.get("rules", []):
		if str(rule.get("skillId", "")) == "SK_BURST" and str(rule.get("target", "")) == "allEnemies":
			rule["target"] = "nearest"
	var depth: int = maxi(1, state.meta.unlocked_forpost + 1)
	var result: Dictionary = SimulationLab.new().compare_builds(current_build, candidate_build, [{"templateId": enemy_id}], tactic, depth, str(enemy.get("biomes", ["B01"])[0]), runs, "%s:%s:%s" % [state.save_id, slot, item_id])
	if bool(result.get("ok", false)):
		result["slot"] = slot
		result["candidateItemId"] = item_id
		result["enemyId"] = enemy_id
		result["depth"] = depth
	return result

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

func available_contract_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if state == null:
		return offers
	var depth: int = maxi(1, state.meta.unlocked_forpost + 1)
	var seed: String = "%s:sector:%d" % [state.save_id, depth]
	var biome: String = _generator.campaign_biome(depth, seed, _campaign_biome_history(state.meta.campaign_flags))
	var catalog: QuestCatalog = QuestCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return offers
	var contract_ids: Array[String] = ["CT_HUNT", "CT_TECH", "CT_ESCORT"]
	var offer_rng: DeterministicRng = DeterministicRng.new()
	offer_rng.seed("contract-offers", seed)
	for index: int in range(contract_ids.size() - 1, 0, -1):
		var swap_index: int = offer_rng.int_range(0, index)
		var swap_id: String = contract_ids[index]
		contract_ids[index] = contract_ids[swap_index]
		contract_ids[swap_index] = swap_id
	var biome_tags: Dictionary = {"B01": "weapon", "B02": "armor", "B03": "drone", "B04": "digital", "B05": "energy", "B06": "hybrid"}
	for id: String in contract_ids:
		var definition: Dictionary = catalog.get_contract(id)
		if not definition.is_empty():
			definition["targetBiome"] = biome
			definition["targetTechTag"] = str(biome_tags.get(biome, "tech"))
			definition["eventId"] = "contract-offer:%d:%s" % [depth, id]
			if str(definition.get("kind", "")) == "ESCORT":
				var escort_faction: String = _contract_offer_faction(depth, id)
				definition["factionId"] = escort_faction
				definition["rewardReputation"] = {escort_faction: 8}
				definition["name"] = "%s · %s" % [str(definition.get("name", "Сопровождение")), escort_faction]
			offers.append(definition)
	var favored_faction: String = _favored_faction()
	if not favored_faction.is_empty():
		offers.append({
			"id": _faction_contract_id(favored_faction),
			"kind": "HUNT",
			"eventId": "contract-offer:%d:%s" % [depth, _faction_contract_id(favored_faction)],
			"name": "Заказ фракции · %s" % favored_faction,
			"desc": "Устранить элиту в целевом секторе. Награда: редкое снаряжение и репутация заказчика.",
			"targetBiome": biome,
			"factionId": favored_faction,
			"rewardReputation": {favored_faction: 8},
			"rewardItem": {"rarity": "RARE", "tag": str(biome_tags.get(biome, "weapon"))},
		})
	var controlled_faction: String = _campaign_controlled_faction() if depth >= 13 else ""
	if not controlled_faction.is_empty():
		offers.append({
			"id": "CT_CONTROL_%s" % controlled_faction,
			"kind": "HUNT",
			"eventId": "contract-offer:%d:CT_CONTROL_%s" % [depth, controlled_faction],
			"name": "Исключительный заказ · %s" % controlled_faction,
			"desc": "Устранить элиту в поддержку фракции, получившей контроль над коридором.",
			"targetBiome": biome,
			"factionId": controlled_faction,
			"rewardReputation": {controlled_faction: 8},
			"rewardItem": {"rarity": "RARE", "tag": _faction_reward_tag(controlled_faction)},
		})
	var signal_catalog: ItemCatalog = ItemCatalog.new()
	if bool(signal_catalog.load_catalog().get("ok", false)):
		for unique_id: String in ["U09", "U04", "U14", "U07", "U18"]:
			var unlock: String = "quest-unlock:signalContract:%s" % unique_id
			var template: Dictionary = signal_catalog.get_template(unique_id)
			if state.meta.campaign_flags.has(unlock) and not template.is_empty() and (template.get("biomes", []) as Array).has(biome):
				offers.append({
					"id": "SIGNAL_%s" % unique_id,
					"kind": "SIGNAL",
					"eventId": "contract-offer:%d:SIGNAL_%s" % [depth, unique_id],
					"name": "Целевой контракт · %s" % str(template.get("name", unique_id)),
					"desc": "Найти указанную уникальную технологию в элитном узле целевого биома.",
					"targetBiome": biome,
					"targetUniqueId": unique_id,
					"rewardItem": {"rarity": "UNIQUE", "templateId": unique_id},
				})
	return offers

func _contract_offer_faction(depth: int, contract_id: String) -> String:
	if depth >= 13:
		for flag_value: Variant in state.meta.campaign_flags:
			var flag: String = str(flag_value)
			if flag.begins_with("ENDING_FACTION:"):
				var controlled_faction: String = flag.trim_prefix("ENDING_FACTION:")
				if ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(controlled_faction):
					return controlled_faction
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("contract-faction", "%s:%d:%s" % [state.save_id, depth, contract_id])
	var factions: Array[String] = ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]
	return factions[rng.int_range(0, factions.size() - 1)]

func _favored_faction() -> String:
	if state == null:
		return ""
	var selected: String = ""
	var highest: int = 59
	for faction_id: String in ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]:
		var reputation: int = int(state.meta.reputation.get(faction_id, 0))
		if reputation > highest:
			highest = reputation
			selected = faction_id
	return selected

func _faction_contract_id(faction_id: String) -> String:
	return "CT_FACTION_%s" % faction_id

func _campaign_controlled_faction() -> String:
	if state == null or not state.meta.campaign_flags.has("ENDING_SELECTED"):
		return ""
	for flag_value: Variant in state.meta.campaign_flags:
		var flag: String = str(flag_value)
		if flag.begins_with("ENDING_FACTION:"):
			var faction_id: String = flag.trim_prefix("ENDING_FACTION:")
			if ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(faction_id):
				return faction_id
	return ""

func _faction_reward_tag(faction_id: String) -> String:
	return {"F_VANTA": "weapon", "F_RUST": "drone", "F_CHOIR": "digital", "F_ECHO": "digital"}.get(faction_id, "weapon")

func _apply_wanted_elite_modifiers(enemy_specs: Array, seed_value: String, node_id: String, wanted: float) -> Array:
	var result: Array = enemy_specs.duplicate(true)
	if wanted < 80.0:
		return result
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("wanted:elite", "%s:%s" % [seed_value, node_id])
	var modifiers: Array[String] = ["EL_SHIELD", "EL_FAST", "EL_VIRUS", "EL_ANTI_DRONE", "EL_PEN", "EL_SPLIT"]
	for index: int in range(result.size()):
		if not result[index] is Dictionary:
			continue
		var spec: Dictionary = result[index]
		if str(spec.get("elite", "")).is_empty():
			spec["elite"] = str(rng.pick(modifiers))
		result[index] = spec
	return result

func _world_faction(seed_value: String, key: String) -> String:
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("world-faction", "%s:%s" % [seed_value, key])
	var factions: Array[String] = ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]
	return factions[rng.int_range(0, factions.size() - 1)]

func _last_boss_history(campaign_flags: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for flag: String in campaign_flags:
		if flag.begins_with("BOSS_LAST:"):
			result.append(flag.trim_prefix("BOSS_LAST:"))
	return result

func _apply_faction_world_effects(graph: Dictionary, seed_value: String) -> void:
	var hostile_nodes: Array[Dictionary] = []
	var hated_faction: String = ""
	var lowest_reputation: int = -59
	for faction_id: String in ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]:
		var reputation: int = int(state.meta.reputation.get(faction_id, 0))
		if reputation < lowest_reputation:
			lowest_reputation = reputation
			hated_faction = faction_id
	for layer: Array in graph.get("layers", []):
		for node: Dictionary in layer:
			var kind: String = str(node.get("type", ""))
			if kind in ["COMBAT", "ELITE", "BOUNTY"]:
				node["factionId"] = _world_faction(seed_value, str(node.get("id", "")))
				hostile_nodes.append(node)
	# At hostile standing the route presents a real named bounty even when wanted
	# alone would not have rolled one; the underlying enemy and battle pipeline remain shared.
	var bounty_candidates: Array[Dictionary] = hostile_nodes.filter(func(node: Dictionary) -> bool: return node.get("questTargets", []).is_empty())
	if not hated_faction.is_empty() and not bounty_candidates.is_empty():
		var target: Dictionary = {}
		for node: Dictionary in bounty_candidates:
			if str(node.get("type", "")) == "BOUNTY":
				target = node
				break
		if target.is_empty():
			target = bounty_candidates[0]
			target["type"] = "BOUNTY"
			target["factionId"] = hated_faction
			target["factionBounty"] = true
		var enemies: Array = target.get("enemies", [])
		if not enemies.is_empty() and not target.has("factionBounty"):
			target["factionId"] = hated_faction
			target["factionBounty"] = true
		if not enemies.is_empty():
			enemies[0]["elite"] = "EL_PEN"
			target["enemies"] = enemies

func _apply_active_quest_targets(graph: Dictionary, biome: String, reserved_node_id: String = "") -> void:
	if state == null:
		return
	var catalog: QuestCatalog = QuestCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return
	var reserved: Dictionary = {}
	if not reserved_node_id.is_empty():
		reserved[reserved_node_id] = true
	var progress_by_quest: Dictionary = state.meta.quest_progress
	var quest_ids: Array[String] = []
	for quest_value: Variant in progress_by_quest.keys():
		quest_ids.append(str(quest_value))
	quest_ids.sort()
	for quest_id: String in quest_ids:
		var progress: Dictionary = progress_by_quest[quest_id]
		if str(progress.get("status", "")) != "ACTIVE":
			continue
		var quest: Dictionary = catalog.get_quest(quest_id)
		var stage_index: int = int(progress.get("stage", 1)) - 1
		if quest.is_empty() or stage_index < 0 or stage_index >= quest.get("stages", []).size():
			continue
		var stage: Dictionary = quest["stages"][stage_index]
		var requirement: Dictionary = stage.get("requirement", {})
		var target_biome: String = str(stage.get("biome", quest.get("biome", "")))
		if target_biome != biome:
			continue
		if str(requirement.get("kind", "")) == "anomaly" and quest_id == "Q06":
			var anomaly_target: Dictionary = _force_quest_anomaly_node(graph.get("layers", []), quest_id, reserved)
			if not anomaly_target.is_empty():
				reserved[str(anomaly_target.get("id", ""))] = true
			var anomaly_event_ids: Array = anomaly_target.get("questTargets", [])
			if not anomaly_event_ids.has(quest_id):
				anomaly_event_ids.append(quest_id)
			anomaly_target["questTargets"] = anomaly_event_ids
			continue
		if str(requirement.get("kind", "")) != "killElite":
			continue
		var target_node: Dictionary = _force_quest_target_node(graph.get("layers", []), str(requirement.get("enemyId", "")), reserved)
		if target_node.is_empty():
			continue
		var node_id: String = str(target_node.get("id", ""))
		reserved[node_id] = true
		var quest_targets: Array = target_node.get("questTargets", [])
		if not quest_targets.has(quest_id):
			quest_targets.append(quest_id)
		target_node["questTargets"] = quest_targets

func _force_quest_anomaly_node(layers: Array, quest_id: String, reserved: Dictionary) -> Dictionary:
	if layers.size() <= 2:
		return {}
	var candidates: Array[Dictionary] = []
	for node_value: Variant in layers[2]:
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		if not reserved.has(str(node.get("id", ""))) and str(node.get("type", "")) == "COMBAT" and not node.get("enemies", []).is_empty():
			candidates.append(node)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("id", "")) < str(right.get("id", "")))
	if candidates.is_empty():
		return {}
	var target: Dictionary = candidates[0]
	var protocol_rng: DeterministicRng = DeterministicRng.new()
	protocol_rng.seed("quest:%s:anomaly" % quest_id, str(target.get("id", "")))
	var protocol: String = str(protocol_rng.pick(["EL_SHIELD", "EL_FAST", "EL_VIRUS", "EL_ANTI_DRONE", "EL_PEN", "EL_SPLIT"]))
	var enemies: Array = target.get("enemies", [])
	var anomaly_enemy: Dictionary = enemies[0].duplicate(true)
	anomaly_enemy["elite"] = protocol
	target["enemies"] = [anomaly_enemy]
	target["type"] = "ANOMALY"
	target["threat"] = "high"
	target["lootHint"] = "аномальная добыча"
	target["anomalyProtocol"] = protocol
	target["questTargets"] = [quest_id]
	return target

func _apply_active_quest_event_ids(graph: Dictionary, biome: String) -> void:
	if state == null or state.meta.quest_progress.is_empty():
		return
	var catalog: QuestCatalog = QuestCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return
	var layers: Array = graph.get("layers", [])
	if layers.size() < 5:
		return
	var quest_ids: Array[String] = []
	for quest_id: Variant in state.meta.quest_progress.keys():
		quest_ids.append(str(quest_id))
	quest_ids.sort()
	var quest_nodes: Array[Dictionary] = []
	for quest_id: String in quest_ids:
		var progress: Dictionary = state.meta.quest_progress[quest_id]
		if str(progress.get("status", "")) != "ACTIVE":
			continue
		var quest: Dictionary = catalog.get_quest(quest_id)
		var stage_index: int = int(progress.get("stage", 1)) - 1
		if quest.is_empty() or stage_index < 0 or stage_index >= quest.get("stages", []).size():
			continue
		var stage: Dictionary = quest["stages"][stage_index]
		var target_biome: String = str(stage.get("biome", quest.get("biome", "")))
		if target_biome != biome:
			continue
		var event_id: String = str(stage.get("eventId", ""))
		quest_nodes.append({
			"eventId": event_id,
			"questId": quest_id, "questStage": int(stage.get("stage", stage_index + 1)),
		})
	if quest_nodes.is_empty():
		return
	var layer_nodes: Array = layers[3]
	var replacement_nodes: Array[Dictionary] = []
	for node_value: Variant in layer_nodes:
		if node_value is Dictionary and str(node_value.get("type", "")) != "QUEST":
			replacement_nodes.append(node_value)
	var replacement_priority: Dictionary = {"CACHE": 0, "REPAIR": 1, "FUEL": 1, "COMBAT": 2, "EVENT": 3, "SHOP": 4}
	replacement_nodes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority: int = int(replacement_priority.get(str(left.get("type", "")), 99))
		var right_priority: int = int(replacement_priority.get(str(right.get("type", "")), 99))
		if left_priority != right_priority:
			return left_priority < right_priority
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	for quest_index: int in range(mini(quest_nodes.size(), replacement_nodes.size())):
		var quest: Dictionary = quest_nodes[quest_index]
		var target: Dictionary = replacement_nodes[quest_index]
		target["type"] = "QUEST"
		target["eventId"] = str(quest.get("eventId", ""))
		target["questId"] = str(quest.get("questId", ""))
		target["questStage"] = int(quest.get("questStage", 1))
		target["threat"] = "medium"
		target["enemies"] = []
		target["lootHint"] = "задание"
		target.erase("prototypeChoices")

func _force_quest_target_node(layers: Array, enemy_id: String, reserved: Dictionary) -> Dictionary:
	if enemy_id.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	for layer: Array in layers:
		for value: Variant in layer:
			if value is Dictionary:
				var node: Dictionary = value
				if not reserved.has(str(node.get("id", ""))) and str(node.get("type", "")) in ["COMBAT", "ELITE", "BOUNTY"]:
					candidates.append(node)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_layer: int = int(left.get("layer", 0))
		var right_layer: int = int(right.get("layer", 0))
		return left_layer < right_layer if left_layer != right_layer else str(left.get("id", "")) < str(right.get("id", "")))
	if candidates.is_empty():
		return {}
	var target: Dictionary = candidates[0]
	target["type"] = "ELITE"
	target["factionBounty"] = false
	var enemies: Array = target.get("enemies", [])
	if enemies.is_empty():
		enemies = [{"templateId": enemy_id, "elite": "EL_FAST"}]
	else:
		enemies[0]["templateId"] = enemy_id
		enemies[0]["elite"] = "EL_FAST"
	target["enemies"] = enemies
	return target

func start_expedition(seed_value: String = "", use_medical_restore: bool = false, contract_id: String = "", escalation_ids: Array[String] = [], autopilot_restart: bool = false) -> bool:
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
	if not _validate_escalation_selection(escalation_ids, depth): return false
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
	var biome: String = _generator.campaign_biome(depth, seed, _campaign_biome_history(state.meta.campaign_flags))
	var previous_boss_ids: Array[String] = _last_boss_history(state.meta.campaign_flags)
	var generated: Dictionary = _generator.generate(
		seed, depth, biome,
		depth == 1 and not bool(state.meta.tutorial.get("firstSectorCompleted", false)) and not bool(state.meta.tutorial.get("starterPrototypeSecured", false)),
		0.0,
	[], escalation_ids, previous_boss_ids,
	)
	if not bool(generated.get("ok", false)):
		last_error = str(generated.get("error", "Не удалось создать дорожную карту."))
		return false
	_apply_active_quest_event_ids(generated["graph"], biome)
	var contract: Dictionary = {}
	if not contract_id.is_empty():
		var contract_catalog: QuestCatalog = QuestCatalog.new()
		if not bool(contract_catalog.load_catalog().get("ok", false)):
			last_error = "Каталог контрактов недоступен."
			return false
		contract = contract_catalog.get_contract(contract_id)
		if contract.is_empty() and contract_id.begins_with("CT_CONTROL_"):
			var controlled_faction: String = _campaign_controlled_faction() if depth >= 13 else ""
			if not controlled_faction.is_empty() and contract_id == "CT_CONTROL_%s" % controlled_faction:
				contract = {"id": contract_id, "kind": "HUNT", "name": "Исключительный заказ · %s" % controlled_faction, "desc": "Устранить элиту в поддержку фракции, получившей контроль над коридором.", "targetBiome": biome, "factionId": controlled_faction, "rewardReputation": {controlled_faction: 8}, "rewardItem": {"rarity": "RARE", "tag": _faction_reward_tag(controlled_faction)}}
		if contract.is_empty() and contract_id.begins_with("CT_FACTION_"):
			var favored_faction: String = _favored_faction()
			if not favored_faction.is_empty() and contract_id == _faction_contract_id(favored_faction):
				var faction_biome_tags: Dictionary = {"B01": "weapon", "B02": "armor", "B03": "drone", "B04": "digital", "B05": "energy", "B06": "hybrid"}
				contract = {"id": contract_id, "kind": "HUNT", "name": "Заказ фракции · %s" % favored_faction, "desc": "Устранить элиту по заказу фракции.", "targetBiome": biome, "factionId": favored_faction, "rewardReputation": {favored_faction: 8}, "rewardItem": {"rarity": "RARE", "tag": str(faction_biome_tags.get(biome, "weapon"))}}
		if contract.is_empty() and contract_id.begins_with("SIGNAL_"):
			var unique_id: String = contract_id.trim_prefix("SIGNAL_")
			var unlock: String = "quest-unlock:signalContract:%s" % unique_id
			var item_catalog: ItemCatalog = ItemCatalog.new()
			if state.meta.campaign_flags.has(unlock) and bool(item_catalog.load_catalog().get("ok", false)):
				var unique_template: Dictionary = item_catalog.get_template(unique_id)
				if not unique_template.is_empty() and str(unique_template.get("uniqueEffectId", "")) == unique_id and (unique_template.get("biomes", []) as Array).has(biome):
					contract = {"id": contract_id, "kind": "SIGNAL", "name": "Целевой контракт · %s" % str(unique_template.get("name", unique_id)), "desc": "Найти указанную уникальную технологию в элитном узле целевого биома.", "targetBiome": biome, "targetUniqueId": unique_id, "rewardItem": {"rarity": "UNIQUE", "templateId": unique_id}}
		elif not contract.is_empty():
			contract["targetBiome"] = biome
		if not contract.is_empty() and str(contract.get("kind", "")) == "ESCORT":
			var escort_faction: String = _contract_offer_faction(depth, contract_id)
			contract["factionId"] = escort_faction
			contract["rewardReputation"] = {escort_faction: 8}
		if contract.is_empty() or str(contract.get("targetBiome", "")) != biome:
			last_error = "Контракт недоступен для биома текущего сектора."
			return false
		var layers: Array = generated["graph"].get("layers", [])
		if str(contract.get("kind", "")) in ["HUNT", "SIGNAL"]:
			var target_node: Dictionary = _force_contract_node(layers, "ELITE", 1)
			if target_node.is_empty():
				last_error = "Для контракта охоты не удалось создать узел элиты."
				return false
			contract["targetNodeId"] = str(target_node.get("id", ""))
			var target_enemies: Array = target_node.get("enemies", [])
			contract["targetEnemyId"] = str(target_enemies[0].get("templateId", "")) if not target_enemies.is_empty() else ""
		elif str(contract.get("kind", "")) == "TECH":
			var target_type: String = "ANOMALY" if biome == "B06" else "CACHE"
			var target_cache: Dictionary = {}
			if target_type == "ANOMALY":
				for layer: Array in layers:
					for candidate: Dictionary in layer:
						if str(candidate.get("type", "")) == "ANOMALY":
							target_cache = candidate
							break
					if not target_cache.is_empty():
						break
			else:
				target_cache = _force_contract_node(layers, target_type, 1)
			if target_cache.is_empty():
				last_error = "Для технического контракта не удалось создать целевой узел."
				return false
			contract["targetNodeId"] = str(target_cache.get("id", ""))
		contract["instanceId"] = "contract:%s:%s" % [seed, contract_id]
		contract["eventId"] = "contract-offer:%d:%s" % [depth, contract_id]
		contract["status"] = "ACTIVE"
		contract["combatNodes"] = 0
		contract["rewardClaimed"] = false
		var biome_tags: Dictionary = {"B01": "weapon", "B02": "armor", "B03": "drone", "B04": "digital", "B05": "energy", "B06": "hybrid"}
		contract["targetTechTag"] = str(contract.get("rewardItem", {}).get("tag", biome_tags.get(biome, "tech")))
	_apply_active_quest_targets(generated["graph"], biome, str(contract.get("targetNodeId", "")))
	_apply_faction_world_effects(generated["graph"], seed)
	var graph_validation: Dictionary = _generator.validate_graph(generated["graph"])
	if not bool(graph_validation.get("ok", false)):
		var graph_errors: Array = graph_validation.get("errors", [])
		last_error = "Сгенерированная карта нарушает правила маршрута: %s" % str(graph_errors[0] if not graph_errors.is_empty() else "неизвестная ошибка")
		return false
	var world_rng: DeterministicRng = DeterministicRng.new()
	world_rng.seed("world", seed)
	var loot_rng: DeterministicRng = DeterministicRng.new()
	loot_rng.seed("loot", seed)
	var transport: GameSaveState.TransportState = state.meta.transport
	var sortie_fuel_max: float = maxf(24.0, transport.fuel_max)
	var stats: Dictionary = build.get("stats", {})
	var run_payload: Dictionary = {
		"seed": seed, "depth": depth, "biome": biome, "graph": generated["graph"],
		"equipment": state.meta.equipment.duplicate(true), "currentNodeId": "START",
		"visitedNodeIds": [], "clearedNodeIds": [], "eventsSeen": [], "phase": "ROUTE",
		"wanted": 10.0 if int(state.meta.reputation.get("F_VANTA", 0)) < -60 else 0.0,
		"revealLevel": 1, "pendingTravelDeltaMs": 0,
		"escalationIds": escalation_ids.duplicate(),
		"pendingCombatEffects": {"initialTempShield": 0.0, "extraHeat": 0.0},
		"pendingNextCombat": {
			"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false,
			"bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false,
			"alliedTurret": false, "extraRareOnElite": false,
		},
		"resources": {
			# A new sortie leaves the garage with a full transport tank. Fuel is
			# persistent only while continuing through checkpoints in the same run.
			"fuel": sortie_fuel_max, "maxFuel": sortie_fuel_max,
			"hull": transport.hull, "maxHull": transport.hull_max,
			"hp": float(stats.get("maxHP", 0.0)), "maxHP": float(stats.get("maxHP", 0.0)),
			"shield": float(stats.get("maxShield", 0.0)), "maxShield": float(stats.get("maxShield", 0.0)),
			"energy": float(stats.get("maxEnergy", 0.0)), "heat": 0.0, "gameTimeMs": 0.0,
		},
		"runWallet": {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0},
		"unsecuredCargo": [], "shippedCargo": [], "grantIds": [], "commandIds": [],
		"serviceScrapFuelCounts": {}, "shippedCheckpointIds": [], "combatResult": null, "lastCommandId": null,
		"worldRng": world_rng.serialize(), "lootRng": loot_rng.serialize(), "combatSnapshot": null,
		"contract": contract,
		"autopilotRunCount": (maxi(1, state.run.autopilot_run_count) + 1) if autopilot_restart and state.run != null else 1,
	}
	if autopilot_restart:
		run_payload["autopilotEnabled"] = true
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	_record_campaign_biome(payload["meta"], depth, biome)
	if use_medical_restore:
		payload["meta"]["protectedBank"]["CREDITS"] = float(payload["meta"]["protectedBank"].get("CREDITS", 0.0)) - float(medical_cost)
		run_payload["resources"]["hull"] = run_payload["resources"]["maxHull"]
		payload["run"] = run_payload
	return _commit_payload(payload)

func set_autopilot_enabled(enabled: bool) -> bool:
	if state == null or state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		last_error = "Настройка автопилота доступна только во время активного выезда."
		return false
	var payload: Dictionary = state.to_payload()
	payload["run"]["autopilotEnabled"] = enabled
	if not enabled:
		payload["run"].erase("autopilotEnabled")
	return _commit_payload(payload)

func active_autopilot_profile_id() -> String:
	if state == null or state.meta.active_autopilot_profile_id.is_empty():
		return "BALANCED"
	return state.meta.active_autopilot_profile_id

func active_autopilot_profile() -> Dictionary:
	if state == null:
		return AutopilotPolicy.profile("BALANCED")
	return AutopilotPolicy.saved_profile(active_autopilot_profile_id(), state.meta.autopilot_profiles)

func save_autopilot_profile_settings(profile_id: String, settings: Dictionary) -> bool:
	if not _garage_action_allowed():
		last_error = "Профиль автопилота настраивается между выездами."
		return false
	var validation: Dictionary = AutopilotPolicy.validate_settings(settings)
	if not bool(validation.get("ok", false)):
		last_error = str(validation.get("error", "Настройки автопилота не прошли проверку."))
		return false
	var payload: Dictionary = state.to_payload()
	var profiles: Array = payload["meta"].get("autopilotProfiles", [])
	var found: bool = false
	for index: int in range(profiles.size()):
		if str(profiles[index].get("id", "")) == profile_id:
			profiles[index]["settings"] = settings.duplicate(true)
			found = true
			break
	if not found:
		last_error = "Профиль автопилота не найден."
		return false
	payload["meta"]["autopilotProfiles"] = profiles
	return _commit_payload(payload)

func set_active_autopilot_profile(profile_id: String) -> bool:
	if not _garage_action_allowed():
		last_error = "Профиль автопилота меняется только между выездами."
		return false
	var profile_value: Dictionary = AutopilotPolicy.profile(profile_id)
	if profile_value.is_empty() or str(profile_value.get("id", "")) != profile_id:
		last_error = "Профиль автопилота не найден."
		return false
	var payload: Dictionary = state.to_payload()
	var saved_profiles: Array = payload["meta"].get("autopilotProfiles", [])
	var found: bool = false
	for profile: Dictionary in saved_profiles:
		if str(profile.get("id", "")) == profile_id:
			found = true
			break
	if not found:
		for preset: Dictionary in AutopilotPolicy.starter_profiles():
			var exists: bool = false
			for profile: Dictionary in saved_profiles:
				if str(profile.get("id", "")) == str(preset.get("id", "")):
					exists = true
					break
			if not exists:
				saved_profiles.append(preset)
		payload["meta"]["autopilotProfiles"] = saved_profiles
	payload["meta"]["activeAutopilotProfileId"] = profile_id
	return _commit_payload(payload)

func _force_contract_node(layers: Array, type: String, preferred_layer: int) -> Dictionary:
	if layers.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	for layer_index: int in range(layers.size()):
		for node_value: Variant in layers[layer_index]:
			if node_value is Dictionary:
				candidates.append(node_value)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ad: int = absi(int(a.get("layer", 0)) - preferred_layer)
		var bd: int = absi(int(b.get("layer", 0)) - preferred_layer)
		return ad < bd if ad != bd else str(a.get("id", "")) < str(b.get("id", "")))
	if candidates.is_empty():
		return {}
	var selected: Dictionary = {}
	for candidate: Dictionary in candidates:
		if type != "ELITE" or not candidate.get("enemies", []).is_empty():
			selected = candidate
			break
	if selected.is_empty():
		return {}
	selected["type"] = type
	if type == "ELITE":
		var enemies: Array = selected.get("enemies", [])
		enemies[0]["elite"] = "EL_FAST"
		selected["enemies"] = enemies
	else:
		selected.erase("eventId")
		selected.erase("prototypeChoices")
		selected["enemies"] = []
	return selected

func _campaign_biome_history(flags: Array) -> Array[String]:
	var entries: Array[Dictionary] = []
	for flag_value: Variant in flags:
		var flag: String = str(flag_value)
		if not flag.begins_with("BIOME_HISTORY:"):
			continue
		var parts: PackedStringArray = flag.split(":")
		if parts.size() == 3:
			entries.append({"depth": int(parts[1]), "biome": parts[2]})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["depth"]) < int(b["depth"]))
	var history: Array[String] = []
	for entry: Dictionary in entries:
		history.append(str(entry["biome"]))
	return history

func _validate_escalation_selection(escalation_ids: Array[String], depth: int) -> bool:
	var seen: Dictionary = {}
	if escalation_ids.size() > 3:
		last_error = "Выберите не более трёх разных договоров эскалации."
		return false
	for escalation_id: String in escalation_ids:
		if not ENDGAME_ESCALATIONS.has(escalation_id) or seen.has(escalation_id):
			last_error = "Неизвестный договор эскалации: %s." % escalation_id
			return false
		seen[escalation_id] = true
	if not escalation_ids.is_empty() and (depth < 13 or not state.meta.campaign_flags.has("ENDGAME_UNLOCKED")):
		last_error = "Договоры эскалации доступны после завершения кампании."
		return false
	return true

func _record_campaign_biome(meta: Dictionary, depth: int, biome: String) -> void:
	var flags: Array = meta.get("campaignFlags", [])
	var prefix: String = "BIOME_HISTORY:%d:" % depth
	for flag_value: Variant in flags.duplicate():
		if str(flag_value).begins_with(prefix): flags.erase(flag_value)
	flags.append("BIOME_HISTORY:%d:%s" % [depth, biome])
	meta["campaignFlags"] = flags

func resolve_campaign_ending(ending_id: String, faction_id: String = "") -> bool:
	if state == null or state.run == null or state.run.phase != "CHECKPOINT" or state.run.depth != 12 or not state.meta.campaign_flags.has("CAMPAIGN_COMPLETED"):
		last_error = "Исход кампании выбирается только после финального босса сектора 12."
		return false
	if state.meta.campaign_flags.has("ENDING_SELECTED"):
		last_error = "Исход кампании уже зафиксирован."
		return false
	var payload: Dictionary = state.to_payload()
	var flags: Array = payload["meta"]["campaignFlags"]
	if ending_id == "FREE_CORRIDOR":
		flags.append_array(["ENDING_SELECTED", "ENDING_FREE_CORRIDOR", "ENDGAME_UNLOCKED", "FORPOST_12", "NEUTRAL_CONTRACTS"])
	elif ending_id == "FACTION_CONTROL" and ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(faction_id):
		flags.append_array(["ENDING_SELECTED", "ENDING_CONTROL_%s" % faction_id, "ENDING_FACTION:%s" % faction_id, "EXCLUSIVE_CONTRACTS:%s" % faction_id, "ENDGAME_UNLOCKED", "FORPOST_12"])
	else:
		last_error = "Выбран недопустимый финал или неизвестная фракция."
		return false
	payload["meta"]["unlockedForpost"] = maxi(12, int(payload["meta"].get("unlockedForpost", 0)))
	return _commit_payload(payload)

func reachable_nodes() -> Array[Dictionary]:
	if state == null or state.run == null or state.run.phase != "ROUTE":
		return []
	return _generator.reachable_nodes(state.run.graph, state.run.current_node_id)

func route_intel() -> Dictionary:
	if state == null or state.run == null:
		return {}
	var graph: Dictionary = state.run.graph
	var adjacency: Dictionary = {}
	for edge_value: Variant in graph.get("edges", []):
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = edge_value
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		(adjacency[from_id] as Array).append(to_id)
	var distances: Dictionary = {state.run.current_node_id: 0}
	var queue: Array[String] = [state.run.current_node_id]
	var cursor: int = 0
	while cursor < queue.size():
		var from_id: String = queue[cursor]
		cursor += 1
		var next_distance: int = int(distances[from_id]) + 1
		for next_id_value: Variant in adjacency.get(from_id, []):
			var next_id: String = str(next_id_value)
			if distances.has(next_id):
				continue
			distances[next_id] = next_distance
			queue.append(next_id)
	var intel_level: int = garage_level("INTEL")
	var effective_intel: int = intel_level
	if state.run.biome == "B06": effective_intel -= 1
	if state.run.escalation_ids.has("SCAN_DARK"): effective_intel -= 1
	effective_intel = maxi(0, effective_intel)
	var scan_distance: int = 1 + (1 if effective_intel >= 3 else 0)
	var result: Dictionary = {"level": intel_level, "effectiveLevel": effective_intel, "nodes": {}}
	var preview_available: bool = state.run.biome == "B06" and _anomaly_preview_available()
	var preview_used_flag: String = "ANOMALY_PREVIEW_USED:%d" % state.run.depth
	for layer: Array in graph.get("layers", []):
		for node: Dictionary in layer:
			var node_id: String = str(node.get("id", ""))
			var visited: bool = state.run.visited_node_ids.has(node_id) or state.run.cleared_node_ids.has(node_id)
			var scouted: bool = state.run.scouted_node_ids.has(node_id)
			var distance: int = int(distances.get(node_id, 999))
			var is_preview: bool = preview_available and not state.meta.campaign_flags.has(preview_used_flag) and str(node.get("type", "")) == "ANOMALY"
			var active_contract: Dictionary = state.run.contract
			var is_contract_target: bool = str(active_contract.get("status", "")) == "ACTIVE" and str(active_contract.get("targetNodeId", "")) == node_id
			var revealed: bool = visited or scouted or is_preview or is_contract_target or (distance > 0 and distance <= scan_distance and effective_intel >= 1)
			var info: Dictionary = {"revealed": revealed, "visited": visited, "scouted": scouted, "contractTarget": is_contract_target}
			if revealed:
				info["type"] = str(node.get("type", "UNKNOWN"))
				info["questTarget"] = str(node.get("type", "")) == "QUEST" or not (node.get("questTargets", []) as Array).is_empty()
				if effective_intel >= 2 or is_preview:
					info["threat"] = str(node.get("threat", "unknown"))
					info["lootHint"] = str(node.get("lootHint", "unknown"))
				if is_preview:
					info["anomalyProtocol"] = str(node.get("anomalyProtocol", ""))
					info["preview"] = true
				elif (visited or effective_intel >= 1) and effective_intel >= 2 and node.has("anomalyProtocol"):
					info["anomalyProtocol"] = str(node.get("anomalyProtocol", ""))
			result["nodes"][node_id] = info
	return result

func _anomaly_preview_available() -> bool:
	if state == null:
		return false
	if state.meta.campaign_flags.has("quest-anomaly-preview") and not state.meta.campaign_flags.has("ANOMALY_PREVIEW_USED:QUEST"):
		return true
	var progress: Dictionary = state.meta.quest_progress.get("Q06", {})
	return (progress.get("flags", []) as Array).has("earlyAnomaly") and not state.meta.campaign_flags.has("ANOMALY_PREVIEW_USED:EARLY")

func simulate_autopilot(simulation_budget_ms: int = 43200000, elapsed_wall_clock_ms: int = -1, wall_clock_delta_provided: bool = false) -> Dictionary:
	const MAX_OFFLINE_MS: int = 43200000
	const MAX_COMMANDS: int = 2048
	var budget: int = clampi(simulation_budget_ms, 0, MAX_OFFLINE_MS)
	var report: Dictionary = {"ok": true, "status": "RUNNING", "reasonCode": "BUDGET", "reason": "Достигнут лимит симуляции.", "simulatedMs": 0, "elapsedWallClockMs": 0, "unappliedTimeMs": 0, "clockRollbackMs": 0, "nodesVisited": 0, "battles": 0, "battlesWon": 0, "battlesLost": 0, "itemsFound": 0, "itemsSecured": 0, "itemsLost": 0, "runsStarted": 1, "runsFinished": 0, "eventLog": [], "seed": "", "error": ""}
	var has_wall_clock_delta: bool = wall_clock_delta_provided or elapsed_wall_clock_ms != -1
	report["_elapsedWallClockMs"] = clampi(elapsed_wall_clock_ms, 0, MAX_OFFLINE_MS) if has_wall_clock_delta else -1
	if has_wall_clock_delta and elapsed_wall_clock_ms > MAX_OFFLINE_MS:
		report["unappliedTimeMs"] = elapsed_wall_clock_ms - MAX_OFFLINE_MS
	elif has_wall_clock_delta and elapsed_wall_clock_ms < 0:
		report["clockRollbackMs"] = absi(elapsed_wall_clock_ms)
	report["_wallClockStartedAtMs"] = int(Time.get_unix_time_from_system() * 1000.0)
	if state == null or state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		return _autopilot_stop("PAUSED_FOR_DECISION", "NO_ACTIVE_RUN", "Автопилот продолжит движение только из активного выезда.", report)
	if budget <= 0:
		return _autopilot_stop("PAUSED_FOR_RESOURCES", "ZERO_BUDGET", "Нулевой лимит симуляции.", report)
	report["seed"] = state.run.seed
	var pilot_profile_id: String = active_autopilot_profile_id()
	var pilot_profile: Dictionary = active_autopilot_profile()
	report["policy"] = {"id": pilot_profile_id, "name": str(pilot_profile.get("name", pilot_profile_id))}
	var starting_time: float = float(state.run.resources.get("gameTimeMs", 0.0))
	# Settlement adds the whole combat duration to run time, including ticks already
	# simulated before this return. Count only newly advanced ticks in this budget.
	if _combat != null:
		starting_time += float(_combat.time_ms)
	var starting_items: int = state.run.unsecured_cargo.size()
	var starting_inventory: int = state.meta.inventory.size()
	report["_startingSnapshot"] = _capture_autopilot_economy_snapshot()
	report["_startingNodeId"] = state.run.current_node_id
	report["_startingDepth"] = state.run.depth
	report["_routePath"] = [state.run.current_node_id]
	report["_startingTime"] = starting_time
	report["_startingItems"] = starting_items
	report["_startingInventory"] = starting_inventory
	report["_completedRunTime"] = 0
	var actions: int = 0
	var combat_time: int = 0
	var policy: AutopilotPolicy = AutopilotPolicy.new()
	while actions < MAX_COMMANDS:
		var action_snapshot: Dictionary = _capture_autopilot_economy_snapshot()
		var used_time: int = int(report.get("_completedRunTime", 0)) + maxi(0, roundi(float(state.run.resources.get("gameTimeMs", starting_time)) - float(report.get("_startingTime", starting_time)))) + combat_time
		if used_time >= budget:
			break
		if _combat != null:
			var combat_node_id: String = state.run.current_node_id
			var combat_depth: int = state.run.depth
			var ticks_left: int = mini(1800, int((budget - used_time) / 100))
			if ticks_left <= 0:
				break
			for _tick: int in range(ticks_left):
				if not _combat.outcome.is_empty():
					break
				var step: Dictionary = _simulator.step_combat(_combat)
				if not bool(step.get("ok", false)):
					return _autopilot_stop("SAFE_ERROR_STOP", "COMBAT_STEP", str(step.get("error", "Боевой шаг автопилота отклонён.")), report)
				_combat = step["state"] as CombatState
				combat_time += 100
				report["_combatTime"] = combat_time
			if _combat.outcome.is_empty():
				_persist_combat_snapshot()
				report["status"] = "OFFLINE_CAPPED" if used_time + ticks_left * 100 >= budget else "PAUSED_FOR_DECISION"
				report["reasonCode"] = "TIME_BUDGET" if report["status"] == "OFFLINE_CAPPED" else "COMBAT_TICK_LIMIT"
				report["reason"] = "Симуляция приостановлена между тиками боя; состояние сохранено."
				break
			var combat_outcome: String = _combat.outcome
			var combat_ticks: int = int(_combat.time_ms / 100)
			var combat_metrics: Dictionary = _combat.metrics.duplicate(true)
			if not _persist_combat_snapshot():
				return _autopilot_stop("SAFE_ERROR_STOP", "COMBAT_SAVE", last_error, report)
			if not resolve_active_combat():
				return _autopilot_stop("SAFE_ERROR_STOP", "COMBAT_SETTLEMENT", last_error, report)
			report["battles"] = int(report["battles"]) + 1
			if combat_outcome == "VICTORY":
				report["battlesWon"] = int(report["battlesWon"]) + 1
			else:
				report["battlesLost"] = int(report["battlesLost"]) + 1
				if state.run.phase == "DEFEATED":
					report["runsFinished"] = int(report["runsFinished"]) + 1
			_record_autopilot_event(report, "COMBAT", action_snapshot, {"depth": combat_depth, "nodeId": combat_node_id, "outcome": combat_outcome, "ticks": combat_ticks, "metrics": combat_metrics})
			combat_time = 0
			report["_combatTime"] = 0
			actions += 1
			if state.run.phase == "DEFEATED":
				report["status"] = "DEFEATED"
				report["reasonCode"] = "OPERATOR_DEFEATED"
				report["reason"] = "Оператор потерпел поражение; автоматический перезапуск отключён."
				break
			continue
		match state.run.phase:
			"ROUTE":
				if state.run.wanted > float(pilot_profile.get("maxWanted", 70)):
					return _autopilot_stop("PAUSED_FOR_RESOURCES", "WANTED_LIMIT", "Розыск превысил предел профиля %s; требуется ручное решение." % str(pilot_profile.get("name", pilot_profile_id)), report)
				var hp_ratio: float = float(state.run.resources.get("hp", 0.0)) / maxf(1.0, float(state.run.resources.get("maxHP", 1.0)))
				var shield_ratio: float = float(state.run.resources.get("shield", 0.0)) / maxf(1.0, float(state.run.resources.get("maxShield", 1.0)))
				var choice: Dictionary = policy.choose_node(reachable_nodes(), route_intel(), state.run, float(pilot_profile.get("riskWeight", 4.0)), pilot_profile_id, pilot_profile)
				if choice.is_empty():
					if _emergency_exit_allowed() and bool(pilot_profile.get("allowTow", false)):
						var tow_quote: Dictionary = emergency_exit_quote()
						if bool(tow_quote.get("towAffordable", false)):
							if call_evacuation_tow():
								report["runsFinished"] = int(report.get("runsFinished", 0)) + 1
								_record_autopilot_event(report, "TOW", action_snapshot, {"depth": state.run.depth, "nodeId": state.run.current_node_id})
								report["status"] = "TOWED"
								report["reasonCode"] = "PROFILE_ALLOWED_TOW"
								report["reason"] = "Профиль %s разрешил оплачиваемую эвакуацию тягачом." % str(pilot_profile.get("name", pilot_profile_id))
								break
							return _autopilot_stop("SAFE_ERROR_STOP", "TOW_FAILED", last_error, report)
						if not bool(tow_quote.get("towAffordable", false)) and not bool(pilot_profile.get("allowAbandon", false)):
							return _autopilot_stop("PAUSED_FOR_RESOURCES", "TOW_UNAFFORDABLE", "Профиль разрешил тягач, но выезд не может оплатить эвакуацию.", report)
					if _emergency_exit_allowed() and bool(pilot_profile.get("allowAbandon", false)):
						if abandon_run():
							report["runsFinished"] = int(report.get("runsFinished", 0)) + 1
							_record_autopilot_event(report, "ABANDON", action_snapshot, {"depth": state.run.depth, "nodeId": state.run.current_node_id})
							report["status"] = "ABANDONED"
							report["reasonCode"] = "PROFILE_ALLOWED_ABANDON"
							report["reason"] = "Профиль %s разрешил отказаться от бесперспективного выезда." % str(pilot_profile.get("name", pilot_profile_id))
							break
						return _autopilot_stop("SAFE_ERROR_STOP", "ABANDON_RUN", last_error, report)
					return _autopilot_stop("PAUSED_FOR_RESOURCES", "NO_ALLOWED_NODE", "В пределах профиля нет подходящего известного перехода; требуется ручное решение.", report)
				var selected_info: Dictionary = route_intel().get("nodes", {}).get(str(choice.get("id", "")), {})
				var selected_type: String = str(selected_info.get("type", "UNKNOWN")) if bool(selected_info.get("revealed", false)) else "UNKNOWN"
				var needs_service: bool = hp_ratio < float(pilot_profile.get("minHP", 0.35)) or shield_ratio < float(pilot_profile.get("minShield", 0.15))
				if needs_service and selected_type != "REPAIR":
					var service_visible: bool = false
					for candidate: Dictionary in reachable_nodes():
						var candidate_info: Dictionary = route_intel().get("nodes", {}).get(str(candidate.get("id", "")), {})
						if bool(candidate_info.get("revealed", false)) and str(candidate_info.get("type", "")) == "REPAIR":
							service_visible = true
							break
					if not service_visible:
						return _autopilot_stop("PAUSED_FOR_RESOURCES", "HEALTH_THRESHOLD", "HP/щит ниже безопасного порога профиля, а известный маршрут не предлагает ремонт.", report)
				var edge_cost: int = 25000
				var known_choice: Dictionary = route_intel().get("nodes", {}).get(str(choice.get("id", "")), {})
				for edge: Dictionary in state.run.graph.get("edges", []):
					if str(edge.get("from", "")) == state.run.current_node_id and str(edge.get("to", "")) == str(choice.get("id", "")):
						edge_cost += int(edge.get("travelMs", 0))
						if state.run.escalation_ids.has("LONG_RUN"): edge_cost += 15000
						if bool(known_choice.get("revealed", false)) and str(known_choice.get("type", "")) == "CHECKPOINT": edge_cost += 8000
						break
				if edge_cost > budget - used_time:
					break
				if not travel_to(str(choice.get("id", ""))):
					return _autopilot_stop("PAUSED_FOR_RESOURCES", "TRAVEL_REJECTED", last_error, report)
				report["nodesVisited"] = int(report["nodesVisited"]) + 1
				var travelled_node: Dictionary = current_node()
				var travelled_id: String = str(travelled_node.get("id", choice.get("id", "")))
				_record_autopilot_event(report, "TRAVEL", action_snapshot, {"depth": state.run.depth, "fromNodeId": str(action_snapshot.get("currentNodeId", "")), "nodeId": travelled_id, "nodeType": str(travelled_node.get("type", "UNKNOWN")), "fuel": float(state.run.resources.get("fuel", 0.0))})
				(report["_routePath"] as Array).append(travelled_id)
			"NODE":
				var quest_stages: Array[Dictionary] = available_quest_stages()
				if not quest_stages.is_empty():
					if str(pilot_profile.get("chooseQuest", "PAUSE")) == "MATCH":
						var choice_map: Dictionary = pilot_profile.get("questChoiceMap", {})
						var resolved_named_choice: bool = false
						for opportunity: Dictionary in quest_stages:
							var quest_id: String = str(opportunity.get("quest", {}).get("id", ""))
							var quest_stage: int = int(opportunity.get("progress", {}).get("stage", 1))
							var choice_id: String = str(choice_map.get("%s:%d" % [quest_id, quest_stage], ""))
							if choice_id.is_empty():
								continue
							if not resolve_quest_choice(quest_id, choice_id):
								return _autopilot_stop("PAUSED_FOR_DECISION", "QUEST_NAMED_CHOICE_INVALID", last_error, report)
							_record_autopilot_event(report, "QUEST", action_snapshot, {"depth": state.run.depth, "nodeId": state.run.current_node_id, "questId": quest_id, "stage": quest_stage, "choiceId": choice_id})
							actions += 1
							resolved_named_choice = true
							break
						if resolved_named_choice:
							continue
						return _autopilot_stop("PAUSED_FOR_DECISION", "QUEST_NAMED_CHOICE_MISSING", "Для готового этапа нет совпадающего выбора в карте MATCH-политики.", report)
					var quest_reason: String = "Автопилот настроен никогда не выбирать квестовые варианты." if str(pilot_profile.get("chooseQuest", "PAUSE")) == "NEVER" else "Квестовое решение требует выбора игрока."
					var quest_code: String = "QUEST_NEVER" if str(pilot_profile.get("chooseQuest", "PAUSE")) == "NEVER" else "QUEST_CHOICE"
					return _autopilot_stop("PAUSED_FOR_DECISION", quest_code, quest_reason, report)
				var node: Dictionary = current_node()
				var kind: String = str(node.get("type", ""))
				var allowed_node_types: Array = pilot_profile.get("allowedNodeTypes", [])
				if not allowed_node_types.is_empty() and not allowed_node_types.has(kind):
					return _autopilot_stop("PAUSED_FOR_DECISION", "NODE_TYPE_RESTRICTED", "Тип %s не разрешён текущей политикой автопилота." % kind, report)
				if kind in ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"] and state.run.cleared_node_ids.has(str(node.get("id", ""))):
					if not resolve_service_node("LEAVE_NODE"):
						return _autopilot_stop("SAFE_ERROR_STOP", "NODE_EXIT", last_error, report)
				elif kind in ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"]:
					if not begin_combat():
						return _autopilot_stop("SAFE_ERROR_STOP", "COMBAT_START", last_error, report)
				elif kind == "QUEST":
					if not resolve_service_node("LEAVE_NODE"):
						return _autopilot_stop("SAFE_ERROR_STOP", "QUEST_NODE_EXIT", last_error, report)
				elif kind == "EVENT":
					var event: Dictionary = current_event()
					var event_choice: Dictionary = _autopilot_event_choice(event, pilot_profile)
					if event_choice.is_empty():
						return _autopilot_stop("PAUSED_FOR_DECISION", "EVENT_CHOICE", "Событие требует фракционного, сюжетного или рискованного выбора игрока.", report)
					if not resolve_event(str(event_choice.get("id", ""))):
						return _autopilot_stop("PAUSED_FOR_RESOURCES", "EVENT_UNAFFORDABLE", last_error, report)
				elif kind == "CACHE":
					if node.has("prototypeChoices"):
						return _autopilot_stop("PAUSED_FOR_DECISION", "CACHE_PROTOTYPE", "Обучающий тайник предлагает выбрать постоянный прототип.", report)
					if not resolve_service_node("OPEN_CACHE"):
						return _autopilot_stop("PAUSED_FOR_RESOURCES", "CACHE", last_error, report)
				elif kind == "FUEL":
					var resources: Dictionary = state.run.resources
					var fuel_action: String = "BUY_FUEL" if float(resources.get("fuel", 0.0)) < float(resources.get("maxFuel", 0.0)) else "LEAVE_NODE"
					if fuel_action == "BUY_FUEL" and float(state.run.wallet.credits) < ceili(3.0 * CydleFormula.new().reward_scale(float(state.run.depth))):
						fuel_action = "SCRAP_FUEL" if state.run.wallet.scrap >= 5.0 else ""
					if fuel_action.is_empty(): return _autopilot_stop("PAUSED_FOR_RESOURCES", "FUEL_UNAVAILABLE", "Нет доступных кредитов или лома для топлива.", report)
					if not resolve_service_node(fuel_action): return _autopilot_stop("PAUSED_FOR_RESOURCES", "FUEL_SERVICE", last_error, report)
				elif kind == "REPAIR":
					var resources: Dictionary = state.run.resources
					var repair_action: String = "REPAIR_HULL" if float(resources.get("hull", 0.0)) < float(resources.get("maxHull", 0.0)) else "REPAIR_HP" if float(resources.get("hp", 0.0)) < float(resources.get("maxHP", 0.0)) else "LEAVE_NODE"
					if repair_action != "LEAVE_NODE" and not resolve_service_node(repair_action, "", float(pilot_profile.get("maxSpendRepair", 0.0))): return _autopilot_stop("PAUSED_FOR_RESOURCES", "REPAIR_UNAVAILABLE", last_error, report)
					if repair_action == "LEAVE_NODE" and not resolve_service_node("LEAVE_NODE"): return _autopilot_stop("SAFE_ERROR_STOP", "NODE_EXIT", last_error, report)
				elif kind == "SHOP":
					if not resolve_service_node("LEAVE_NODE"): return _autopilot_stop("SAFE_ERROR_STOP", "NODE_EXIT", last_error, report)
				else:
					return _autopilot_stop("SAFE_ERROR_STOP", "UNSUPPORTED_NODE", "Узел %s не поддерживает автоматическое действие." % kind, report)
				_record_autopilot_event(report, "NODE_ACTION", action_snapshot, {"depth": state.run.depth, "nodeId": str(node.get("id", "")), "nodeType": kind, "eventId": str(node.get("eventId", ""))})
				actions += 1
			"CHECKPOINT":
				if state.run.depth == 12 and state.meta.campaign_flags.has("CAMPAIGN_COMPLETED") and not state.meta.campaign_flags.has("ENDING_SELECTED"):
					return _autopilot_stop("PAUSED_FOR_DECISION", "CAMPAIGN_ENDING", "Финал кампании требует выбора игрока; автопилот остановлен перед эндгеймом.", report)
				var hp_ratio: float = float(state.run.resources.get("hp", 0.0)) / maxf(1.0, float(state.run.resources.get("maxHP", 1.0)))
				var shield_ratio: float = float(state.run.resources.get("shield", 0.0)) / maxf(1.0, float(state.run.resources.get("maxShield", 1.0)))
				var hull_ratio: float = float(state.run.resources.get("hull", 0.0)) / maxf(1.0, float(state.run.resources.get("maxHull", 1.0)))
				var safe_to_continue: bool = hp_ratio >= float(pilot_profile.get("minHP", 0.35)) and shield_ratio >= float(pilot_profile.get("minShield", 0.15)) and hull_ratio > 0.35 and float(state.run.resources.get("fuel", 0.0)) > float(pilot_profile.get("reserveFuel", 1)) and state.run.wanted <= float(pilot_profile.get("maxWanted", 70))
				var checkpoint_action: String = str(pilot_profile.get("checkpointAction", "CONDITIONAL"))
				var should_extract: bool = checkpoint_action == "EXTRACT" or (checkpoint_action == "CONDITIONAL" and not safe_to_continue)
				if should_extract:
					var runs_started: int = maxi(1, state.run.autopilot_run_count)
					var max_runs: int = int(pilot_profile.get("maxRuns", 1))
					var restart_ready: bool = bool(pilot_profile.get("autoRestartAllowed", false)) and runs_started < max_runs
					var restart_repair_blocked: bool = false
					if restart_ready:
						var repair_guard: int = 0
						while float(state.run.resources.get("hull", 0.0)) + 0.001 < float(state.run.resources.get("maxHull", 0.0)) and repair_guard < 100:
							var repair_quote: Dictionary = checkpoint_repair_quote()
							if not bool(repair_quote.get("valid", false)) or not bool(repair_quote.get("affordable", false)) or not repair_checkpoint_hull(float(pilot_profile.get("maxSpendRepair", 0.0))):
								restart_ready = false
								restart_repair_blocked = true
								break
							repair_guard += 1
						if repair_guard >= 100:
							restart_ready = false
							restart_repair_blocked = true
					if not extract_run():
						return _autopilot_stop("SAFE_ERROR_STOP", "EXTRACTION", last_error, report)
					report["runsFinished"] = int(report.get("runsFinished", 0)) + 1
					_record_autopilot_event(report, "EXTRACTION", action_snapshot, {"depth": state.run.depth, "nodeId": state.run.current_node_id})
					actions += 1
					if restart_ready:
						var completed_run_time: int = maxi(0, roundi(float(state.run.resources.get("gameTimeMs", 0.0)) - float(report.get("_startingTime", 0.0))))
						report["_completedRunTime"] = int(report.get("_completedRunTime", 0)) + completed_run_time
						var restart_seed: String = "%s:autopilot:%d" % [str(state.run.seed), runs_started + 1]
						if not start_expedition(restart_seed, false, "", [], true):
							report["status"] = "EXTRACTED"
							report["reasonCode"] = "RESTART_REJECTED"
							report["reason"] = "Добыча сохранена, но новый выезд не начат: %s" % last_error
							break
						report["runsStarted"] = int(report.get("runsStarted", 1)) + 1
						_record_autopilot_event(report, "RUN_STARTED", _capture_autopilot_economy_snapshot(), {"depth": state.run.depth, "nodeId": state.run.current_node_id, "seed": state.run.seed})
						report["_startingTime"] = 0.0
						report["status"] = "RUNNING"
						report["reasonCode"] = "AUTO_RESTART"
						report["reason"] = "После успешной эвакуации начат выезд %d из %d." % [runs_started + 1, max_runs]
						continue
					report["status"] = "EXTRACTED"
					report["reasonCode"] = "MAX_RUNS" if bool(pilot_profile.get("autoRestartAllowed", false)) and runs_started >= max_runs else "RESTART_REPAIR_LIMIT" if restart_repair_blocked else "PROFILE_CHECKPOINT_EXTRACT"
					report["reason"] = "Добыча доставлена; достигнут предел %d выездов." % runs_started if report["reasonCode"] == "MAX_RUNS" else "Добыча сохранена; ремонт для следующего выезда не прошёл по средствам или бюджету." if restart_repair_blocked else "Профиль %s закрепил добычу на контрольной точке." % str(pilot_profile.get("name", pilot_profile_id))
					break
				var checkpoint_ship_id: String = "ship:%s:%s" % [state.run.seed, state.run.current_node_id]
				if checkpoint_action == "CONDITIONAL" and not state.run.shipped_checkpoint_ids.has(checkpoint_ship_id):
					var shipping_ids: Array[String] = _autopilot_checkpoint_cargo_ids(5, str(pilot_profile.get("cargoProtectionPriority", "RARITY")))
					var run_wallet: Dictionary = state.run.wallet.to_dictionary()
					var currency_to_ship: bool = float(run_wallet.get("CREDITS", 0.0)) > 0.0 or float(run_wallet.get("SCRAP", 0.0)) > 0.0 or float(run_wallet.get("DATA", 0.0)) > 0.0
					if not shipping_ids.is_empty() or currency_to_ship:
						var shipping_quote: Dictionary = checkpoint_shipping_quote(shipping_ids, 50)
						if not bool(shipping_quote.get("affordable", false)):
							return _autopilot_stop("PAUSED_FOR_RESOURCES", "CHECKPOINT_SHIPPING", str(shipping_quote.get("error", "Для закрепления груза не хватает ресурсов.")), report)
						if not ship_checkpoint_cargo(shipping_ids, 50):
							return _autopilot_stop("SAFE_ERROR_STOP", "CHECKPOINT_SHIPPING", last_error, report)
				if not safe_to_continue and checkpoint_action == "CONTINUE":
					return _autopilot_stop("PAUSED_FOR_RESOURCES", "CHECKPOINT_RESERVE", "Ресурсы ниже защитного резерва профиля; выезд оставлен на решающий выбор.", report)
				if not continue_campaign():
					if state.run.depth == 12 and not state.meta.campaign_flags.has("ENDING_SELECTED"):
						return _autopilot_stop("PAUSED_FOR_DECISION", "CAMPAIGN_ENDING", last_error, report)
					return _autopilot_stop("PAUSED_FOR_RESOURCES", "CONTINUE_REJECTED", last_error, report)
				_record_autopilot_event(report, "CHECKPOINT_CONTINUE", action_snapshot, {"depth": state.run.depth, "nodeId": state.run.current_node_id})
				actions += 1
			_:
				return _autopilot_stop("PAUSED_FOR_DECISION", "RUN_STATE", "Текущий этап выезда требует ручного решения.", report)
		if actions >= MAX_COMMANDS:
			break
	if report["status"] == "RUNNING":
		report["status"] = "OFFLINE_CAPPED"
		report["reasonCode"] = "COMMAND_LIMIT" if actions >= MAX_COMMANDS else "TIME_BUDGET"
		report["reason"] = "Автопилот остановлен по лимиту действий." if actions >= MAX_COMMANDS else "Симуляция приостановлена по бюджету времени; состояние выезда сохранено."
	return _finalize_autopilot_report(report)

func _autopilot_event_choice(event: Dictionary, profile: Dictionary = {}) -> Dictionary:
	for choice: Dictionary in event.get("choices", []):
		var preferred_mutation: bool = choice.has("grantMutation") and profile.get("preferMutations", []).has(str(choice.get("grantMutation", "")))
		if preferred_mutation and not choice.has("flag") and not choice.has("wanted"):
			var mutation_affordable: bool = true
			for currency: String in choice.get("cost", {}).keys():
				if float(state.run.wallet.to_dictionary().get(currency, 0.0)) < float(choice["cost"][currency]):
					mutation_affordable = false
			if mutation_affordable:
				return choice
		if choice.has("reputation") or choice.has("flag") or choice.has("wanted") or str(choice.get("special", "")) != "":
			continue
		var affordable: bool = true
		for currency: String in choice.get("cost", {}).keys():
			if float(state.run.wallet.to_dictionary().get(currency, 0.0)) < float(choice["cost"][currency]):
				affordable = false
		if affordable:
			return choice
	return {}

func _autopilot_checkpoint_cargo_ids(max_units: int, priority: String = "RARITY") -> Array[String]:
	var selected: Array[String] = []
	if state == null or state.run == null or max_units <= 0:
		return selected
	var catalog_result: Dictionary = _item_catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return selected
	var candidates: Array[Dictionary] = state.run.unsecured_cargo.duplicate(true)
	var rarity_rank: Dictionary = {"COMMON": 0, "MODIFIED": 1, "RARE": 2, "EXTRA_RARE": 3, "LEGENDARY": 4, "UNIQUE": 5}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rarity_a: int = int(rarity_rank.get(str(a.get("rarity", "COMMON")), 0))
		var rarity_b: int = int(rarity_rank.get(str(b.get("rarity", "COMMON")), 0))
		if priority == "QUEST":
			var quest_a: bool = bool(a.get("questTarget", false))
			var quest_b: bool = bool(b.get("questTarget", false))
			if quest_a != quest_b:
				return quest_a
		if priority == "VALUE":
			var value_a: float = float(a.get("sellValue", rarity_a * 100 + int(a.get("techLevel", 1)) * 10))
			var value_b: float = float(b.get("sellValue", rarity_b * 100 + int(b.get("techLevel", 1)) * 10))
			if not is_equal_approx(value_a, value_b):
				return value_a > value_b
		if rarity_a != rarity_b:
			return rarity_a > rarity_b
		return str(a.get("itemId", "")) < str(b.get("itemId", ""))
	)
	var used_units: int = 0
	for item: Dictionary in candidates:
		var units: int = int(_item_catalog.get_template(str(item.get("templateId", ""))).get("cargoUnits", 1))
		if used_units + units > max_units:
			continue
		used_units += units
		selected.append(str(item.get("itemId", "")))
	return selected

func _autopilot_stop(status: String, code: String, reason: String, report: Dictionary) -> Dictionary:
	report["status"] = status
	report["reasonCode"] = code
	report["reason"] = reason
	report["error"] = last_error if status == "SAFE_ERROR_STOP" else ""
	return _finalize_autopilot_report(report)

func _capture_autopilot_economy_snapshot() -> Dictionary:
	if state == null:
		return {}
	var currencies: Dictionary = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	for wallet: GameSaveState.WalletState in [state.meta.protected_bank, state.meta.unsecured_wallet]:
		var values: Dictionary = wallet.to_dictionary()
		for currency: String in currencies.keys():
			currencies[currency] = float(currencies[currency]) + float(values.get(currency, 0.0))
	if state.run != null:
		var run_wallet: Dictionary = state.run.wallet.to_dictionary()
		for currency: String in currencies.keys():
			currencies[currency] = float(currencies[currency]) + float(run_wallet.get(currency, 0.0))
	var items: Dictionary = {}
	for item: Dictionary in state.meta.inventory:
		var item_id: String = str(item.get("itemId", ""))
		if not item_id.is_empty(): items[item_id] = item.duplicate(true)
	if state.run != null:
		for item: Dictionary in state.run.unsecured_cargo:
			var item_id: String = str(item.get("itemId", ""))
			if not item_id.is_empty(): items[item_id] = item.duplicate(true)
	return {"currencies": currencies, "reputation": state.meta.reputation.duplicate(true), "items": items, "depth": state.run.depth if state.run != null else 0, "nodeId": state.run.current_node_id if state.run != null else ""}

func _record_autopilot_event(report: Dictionary, event_type: String, before: Dictionary, details: Dictionary = {}) -> void:
	if state == null:
		return
	var after: Dictionary = _capture_autopilot_economy_snapshot()
	var currency_delta: Dictionary = {}
	var currency_gains: Dictionary = {}
	var before_currencies: Dictionary = before.get("currencies", {})
	var after_currencies: Dictionary = after.get("currencies", {})
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var delta: float = float(after_currencies.get(currency, 0.0)) - float(before_currencies.get(currency, 0.0))
		currency_delta[currency] = delta
		currency_gains[currency] = maxf(0.0, delta)
	var reputation_delta: Dictionary = {}
	var before_reputation: Dictionary = before.get("reputation", {})
	var after_reputation: Dictionary = after.get("reputation", {})
	for faction: Variant in after_reputation.keys():
		var delta: int = int(after_reputation[faction]) - int(before_reputation.get(faction, 0))
		if delta != 0: reputation_delta[str(faction)] = delta
	var before_items: Dictionary = before.get("items", {})
	var after_items: Dictionary = after.get("items", {})
	var added_items: Array[Dictionary] = []
	var removed_items: Array[String] = []
	for item_id: Variant in after_items.keys():
		if not before_items.has(item_id):
			var item: Dictionary = after_items[item_id]
			added_items.append({"itemId": str(item_id), "templateId": str(item.get("templateId", "")), "rarity": str(item.get("rarity", "COMMON")), "techLevel": int(item.get("techLevel", 0)), "itemLevel": int(item.get("itemLevel", 0))})
	for item_id: Variant in before_items.keys():
		if not after_items.has(item_id): removed_items.append(str(item_id))
	var event: Dictionary = {"sequence": (report.get("eventLog", []) as Array).size(), "type": event_type, "gameTimeMs": int(state.run.resources.get("gameTimeMs", 0.0)) if state.run != null else 0, "depth": int(details.get("depth", state.run.depth if state.run != null else before.get("depth", 0))), "currencyDelta": currency_delta, "currencyGains": currency_gains, "reputationDelta": reputation_delta, "itemsAdded": added_items, "itemsRemoved": removed_items}
	for key: Variant in details.keys(): event[str(key)] = details[key]
	(report["eventLog"] as Array).append(event)

func _finalize_autopilot_report(report: Dictionary) -> Dictionary:
	if state != null:
		var start_time: float = float(report.get("_startingTime", state.run.resources.get("gameTimeMs", 0.0) if state.run != null else 0.0))
		var current_time: float = float(state.run.resources.get("gameTimeMs", start_time)) if state.run != null else start_time
		report["simulatedMs"] = int(report.get("_completedRunTime", 0)) + maxi(0, roundi(current_time - start_time)) + int(report.get("_combatTime", 0))
		var start_items: int = int(report.get("_startingItems", 0))
		var start_inventory: int = int(report.get("_startingInventory", state.meta.inventory.size()))
		var current_run_items: int = state.run.unsecured_cargo.size() if state.run != null else 0
		report["itemsFound"] = maxi(0, state.meta.inventory.size() + current_run_items - start_inventory - start_items)
		report["itemsSecured"] = maxi(0, state.meta.inventory.size() - start_inventory)
		var starting_snapshot: Dictionary = report.get("_startingSnapshot", {})
		var ending_snapshot: Dictionary = _capture_autopilot_economy_snapshot()
		var start_currencies: Dictionary = starting_snapshot.get("currencies", {})
		var end_currencies: Dictionary = ending_snapshot.get("currencies", {})
		var net_currency_delta: Dictionary = {}
		var raw_currency_gains: Dictionary = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
		for currency: String in ["CREDITS", "SCRAP", "DATA"]:
			net_currency_delta[currency] = float(end_currencies.get(currency, 0.0)) - float(start_currencies.get(currency, 0.0))
		for event: Dictionary in report.get("eventLog", []):
			for currency: String in ["CREDITS", "SCRAP", "DATA"]:
				raw_currency_gains[currency] = float(raw_currency_gains[currency]) + float(event.get("currencyGains", {}).get(currency, 0.0))
		report["rawCurrencyGains"] = raw_currency_gains
		report["netCurrencyDelta"] = net_currency_delta
		var faction_changes: Dictionary = {}
		var start_reputation: Dictionary = starting_snapshot.get("reputation", {})
		var end_reputation: Dictionary = ending_snapshot.get("reputation", {})
		for faction: Variant in end_reputation.keys():
			var delta: int = int(end_reputation[faction]) - int(start_reputation.get(faction, 0))
			if delta != 0: faction_changes[str(faction)] = delta
		report["factionChanges"] = faction_changes
		var starting_item_ids: Dictionary = starting_snapshot.get("items", {})
		var ending_item_ids: Dictionary = ending_snapshot.get("items", {})
		var event_found_items: Dictionary = {}
		var event_lost_items: Dictionary = {}
		var all_found_items: Array[Dictionary] = []
		for event: Dictionary in report.get("eventLog", []):
			for item: Dictionary in event.get("itemsAdded", []):
				var item_id: String = str(item.get("itemId", ""))
				if not item_id.is_empty() and not event_found_items.has(item_id):
					event_found_items[item_id] = true
					all_found_items.append(item)
			for item_id: Variant in event.get("itemsRemoved", []): event_lost_items[str(item_id)] = true
		for item_id: Variant in starting_item_ids.keys():
			if not ending_item_ids.has(item_id): event_lost_items[str(item_id)] = true
		report["itemsFound"] = event_found_items.size()
		report["itemsLost"] = event_lost_items.size()
		report["strongestDrop"] = _strongest_autopilot_drop(all_found_items)
		report["routeGraph"] = {"seed": str(report.get("seed", "")), "startDepth": int(report.get("_startingDepth", 0)), "startNodeId": str(report.get("_startingNodeId", "")), "visitedNodeIds": (report.get("_routePath", []) as Array).duplicate(), "endDepth": int(ending_snapshot.get("depth", 0)), "endNodeId": str(ending_snapshot.get("nodeId", ""))}
		report["finishedAtMs"] = int(Time.get_unix_time_from_system() * 1000.0)
		report["elapsedWallClockMs"] = int(report.get("_elapsedWallClockMs", -1)) if int(report.get("_elapsedWallClockMs", -1)) >= 0 else maxi(0, int(report["finishedAtMs"]) - int(report.get("_wallClockStartedAtMs", report["finishedAtMs"])))
	for internal_key: String in ["_startingTime", "_startingItems", "_startingInventory", "_startingSnapshot", "_startingNodeId", "_startingDepth", "_routePath", "_combatTime", "_completedRunTime", "_elapsedWallClockMs", "_wallClockStartedAtMs"]:
		report.erase(internal_key)
	last_autopilot_report = report.duplicate(true)
	if state != null:
		var history: Array[Dictionary] = state.meta.autopilot_report_history.duplicate(true)
		history.append(last_autopilot_report.duplicate(true))
		while history.size() > 20:
			history.pop_front()
		var payload: Dictionary = state.to_payload()
		payload["meta"]["autopilotReportHistory"] = history
		if not _commit_payload(payload):
			last_error = "Не удалось сохранить журнал автопилота: %s" % last_error
		else:
			last_autopilot_report = state.meta.autopilot_report_history.back().duplicate(true)
	return last_autopilot_report

func _strongest_autopilot_drop(items: Array[Dictionary]) -> Dictionary:
	var rarity_rank: Dictionary = {"COMMON": 0, "MODIFIED": 1, "RARE": 2, "UNIQUE": 3}
	var strongest: Dictionary = {}
	for item: Dictionary in items:
		var item_rank: int = int(rarity_rank.get(str(item.get("rarity", "COMMON")), 0)) * 100000 + int(item.get("techLevel", 0)) * 100 + int(item.get("itemLevel", 0))
		var strongest_rank: int = int(rarity_rank.get(str(strongest.get("rarity", "COMMON")), 0)) * 100000 + int(strongest.get("techLevel", 0)) * 100 + int(strongest.get("itemLevel", 0))
		if strongest.is_empty() or item_rank > strongest_rank:
			strongest = {"itemId": str(item.get("itemId", "")), "templateId": str(item.get("templateId", "")), "rarity": str(item.get("rarity", "COMMON")), "techLevel": int(item.get("techLevel", 0)), "itemLevel": int(item.get("itemLevel", 0))}
	return strongest

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
	var payload: Dictionary = state.to_payload()
	run_payload["resources"]["fuel"] = float(run_payload["resources"]["fuel"]) - cost
	var travel_time: int = 25000
	if state.run.escalation_ids.has("LONG_RUN"): travel_time += 15000
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"]["gameTimeMs"]) + travel_time
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
	if str(target_node.get("type", "")) == "ANOMALY" and _anomaly_preview_available():
		var preview_flag: String = "ANOMALY_PREVIEW_USED:QUEST" if state.meta.campaign_flags.has("quest-anomaly-preview") and not state.meta.campaign_flags.has("ANOMALY_PREVIEW_USED:QUEST") else "ANOMALY_PREVIEW_USED:EARLY"
		if not payload["meta"]["campaignFlags"].has(preview_flag):
			payload["meta"]["campaignFlags"].append(preview_flag)
	run_payload["combatResult"] = null
	payload["run"] = run_payload
	payload["meta"].erase("disassemblyUndo")
	if str(target_node.get("type", "")) == "CHECKPOINT":
		_settle_escort_contract(payload)
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
	var node_type: String = str(node.get("type", ""))
	if node_type == "QUEST":
		var catalog: QuestCatalog = QuestCatalog.new()
		if not bool(catalog.load_catalog().get("ok", false)):
			return {}
		var quest: Dictionary = catalog.get_quest(str(node.get("questId", "")))
		var stage_index: int = int(node.get("questStage", 1)) - 1
		if quest.is_empty() or stage_index < 0 or stage_index >= quest.get("stages", []).size():
			return {}
		var stage: Dictionary = quest["stages"][stage_index].duplicate(true)
		stage["id"] = str(stage.get("eventId", ""))
		stage["name"] = "%s · %s" % [str(quest.get("name", "ЗАДАНИЕ")), str(stage.get("name", "ЭТАП"))]
		stage["questId"] = str(quest.get("id", ""))
		stage["questStage"] = int(stage.get("stage", stage_index + 1))
		return stage
	if node_type != "EVENT":
		return {}
	return EventCatalog.new().get_event(str(node.get("eventId", "")))

func resolve_event(choice_id: String, cargo_item_id: String = "") -> bool:
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
	var surrender_count: int = maxi(0, int(choice.get("surrenderCargo", 0)))
	var surrendered_index: int = -1
	if surrender_count > 0:
		for index: int in range(run_payload["unsecuredCargo"].size()):
			var cargo_item: Dictionary = run_payload["unsecuredCargo"][index]
			if str(cargo_item.get("itemId", "")) == cargo_item_id:
				var equipped_in_run: bool = false
				for equipped_value: Variant in run_payload["equipment"].values():
					if str(equipped_value) == cargo_item_id:
						equipped_in_run = true
						break
				if not equipped_in_run:
					surrendered_index = index
					break
		if surrendered_index < 0:
			last_error = "Для сделки VANTA выберите незакреплённый предмет груза, не установленный в слот рейда."
			return false
	var costs: Dictionary = event_choice_costs(choice)
	var special: String = str(choice.get("special", ""))
	var affordability: Dictionary = _run_wallet_affordability(costs)
	if not bool(affordability.get("affordable", false)):
		last_error = str(affordability.get("reason", "Для выбора недостаточно незакреплённых средств."))
		return false
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var gain: float = float(choice.get("gains", {}).get(currency, 0.0))
		if bool(choice.get("scaled", false)):
			gain = ceili(gain * scale)
		if special == "dataForCredits" and currency == "CREDITS":
			gain = ceili(30.0 * scale)
		wallet[currency] = float(wallet.get(currency, 0.0)) - float(costs.get(currency, 0.0)) + gain
	if surrendered_index >= 0:
		run_payload["unsecuredCargo"].remove_at(surrendered_index)
	var resources: Dictionary = run_payload["resources"]
	if choice.has("wanted"):
		run_payload["wanted"] = clampf(float(run_payload["wanted"]) + float(choice["wanted"]), 0.0, 100.0)
	if choice.has("travelDelta"):
		run_payload["pendingTravelDeltaMs"] = clampi(int(run_payload.get("pendingTravelDeltaMs", 0)) + int(choice["travelDelta"]), -60000, 60000)
	if choice.has("fuel"):
		resources["fuel"] = clampf(float(resources["fuel"]) + float(choice["fuel"]), 0.0, float(resources["maxFuel"]))
	if choice.has("hull"):
		resources["hull"] = clampf(float(resources["hull"]) + float(choice["hull"]), 0.0, float(resources["maxHull"]))
	if choice.has("hullFraction"):
		resources["hull"] = clampf(float(resources["hull"]) + float(resources["maxHull"]) * float(choice["hullFraction"]), 0.0, float(resources["maxHull"]))
	if choice.has("healMissingFraction"):
		var hp: float = float(resources["hp"])
		resources["hp"] = minf(float(resources["maxHP"]), hp + (float(resources["maxHP"]) - hp) * float(choice["healMissingFraction"]))
	if bool(choice.get("refillEnergy", false)):
		var build: Dictionary = run_build_preview()
		if not bool(build.get("valid", false)):
			last_error = "Невозможно рассчитать энергию текущей сборки."
			return false
		resources["energy"] = float(build.get("stats", {}).get("maxEnergy", resources.get("energy", 0.0)))
	if choice.has("reputation"):
		for faction: Variant in choice["reputation"].keys():
			meta["reputation"][str(faction)] = clampi(int(meta["reputation"].get(str(faction), 0)) + int(choice["reputation"][faction]), -100, 100)
	var reveal_count: int = maxi(0, int(choice.get("reveal", 0)))
	if reveal_count > 0:
		var scouted_ids: Array = run_payload.get("scoutedNodeIds", [])
		for scouted_id: String in _next_route_nodes(node_id, reveal_count):
			if not scouted_ids.has(scouted_id):
				scouted_ids.append(scouted_id)
		run_payload["scoutedNodeIds"] = scouted_ids
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
		elif str(event.get("id", "")) == "EV05": pending_next["extraRareOnElite"] = true
		else: pending_next["extraRareItemRoll"] = true
	if next_combat.has("bountyCredits"):
		pending_next["bountyCreditsBonus"] = float(pending_next.get("bountyCreditsBonus", 0.0)) + float(next_combat["bountyCredits"])
	var flag: String = str(choice.get("flag", ""))
	if flag == "codexEntry":
		var codex_id: String = _roll_codex_enemy_id(run_payload)
		if not codex_id.is_empty() and not meta.get("codexEnemyIds", []).has(codex_id):
			meta["codexEnemyIds"] = meta.get("codexEnemyIds", [])
			meta["codexEnemyIds"].append(codex_id)
	if flag == "bossWeakness":
		var weakness_flag: String = _boss_weakness_flag(run_payload)
		if weakness_flag.is_empty():
			last_error = "В каталоге не удалось определить уязвимость босса этого биома."
			return false
		if not meta["campaignFlags"].has(weakness_flag):
			meta["campaignFlags"].append(weakness_flag)
	if flag == "bountyE21":
		pending_next["bountyEnemyId"] = "E21"
		pending_next["extraRareItemRoll"] = true
	if flag == "huntElite": pending_next["extraRareOnElite"] = true
	if not flag.is_empty(): meta["campaignFlags"].append("event-flag:%s:%s" % [flag, node_id])
	var grant: Dictionary = choice.get("grantItem", {}).duplicate(true)
	if special == "greyDealer": grant["rarity"] = "RARE"
	var item_values: Array[Dictionary] = []
	if not grant.is_empty():
		if not _item_catalog_loaded():
			return false
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
		var received: Dictionary = _receive_run_item(payload, item_values[0], "EVENT")
		if not bool(received.get("accepted", false)) and not bool(received.get("salvaged", false)):
			last_error = "Фильтр добычи пропустил предмет события, а груз не помещается."
			return false
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

func _roll_codex_enemy_id(run_payload: Dictionary) -> String:
	var catalog: EnemyCatalog = EnemyCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return ""
	var known: Array = state.meta.codex_enemy_ids
	var candidates: Array[String] = []
	for enemy_value: Variant in catalog.enemies.values():
		var enemy: Dictionary = enemy_value
		if int(enemy.get("unlockDepth", 1)) <= int(run_payload.get("depth", 1)) and (enemy.get("biomes", []) as Array).has(str(run_payload.get("biome", ""))) and not known.has(str(enemy.get("id", ""))):
			candidates.append(str(enemy.get("id", "")))
	if candidates.is_empty():
		for enemy_value: Variant in catalog.enemies.values():
			var enemy: Dictionary = enemy_value
			if int(enemy.get("unlockDepth", 1)) <= int(run_payload.get("depth", 1)) and not known.has(str(enemy.get("id", ""))):
				candidates.append(str(enemy.get("id", "")))
	if candidates.is_empty():
		return ""
	candidates.sort()
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("event-codex", "%s:%s" % [str(run_payload.get("seed", "")), str(run_payload.get("currentNodeId", ""))])
	return candidates[rng.int_range(0, candidates.size() - 1)]

func _boss_weakness_flag(run_payload: Dictionary) -> String:
	var boss_id: String = ""
	for layer: Array in run_payload.get("graph", {}).get("layers", []):
		for node: Dictionary in layer:
			if str(node.get("type", "")) == "BOSS":
				var enemies: Array = node.get("enemies", [])
				if not enemies.is_empty():
					boss_id = str(enemies[0].get("templateId", ""))
				break
		if not boss_id.is_empty():
			break
	var catalog: EnemyCatalog = EnemyCatalog.new()
	if boss_id.is_empty() or not bool(catalog.load_catalog().get("ok", false)):
		return ""
	var boss: Dictionary = catalog.get_template(boss_id)
	if boss.is_empty():
		return ""
	var weakness_tag: String = "DIGITAL" if float(boss.get("resD", 0.0)) <= float(boss.get("resE", 0.0)) else "ENERGY"
	return "BOSS_WEAKNESS:%d:%s:%s" % [int(run_payload.get("depth", 1)), boss_id, weakness_tag]

func _next_route_nodes(origin_id: String, limit: int) -> Array[String]:
	var selected: Array[String] = []
	if state == null or state.run == null or limit <= 0:
		return selected
	var adjacency: Dictionary = {}
	for edge_value: Variant in state.run.graph.get("edges", []):
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = edge_value
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not adjacency.has(from_id): adjacency[from_id] = []
		(adjacency[from_id] as Array).append(to_id)
	for from_id: String in adjacency.keys():
		(adjacency[from_id] as Array).sort()
	var seen: Dictionary = {origin_id: true}
	var queue: Array[String] = [origin_id]
	var cursor: int = 0
	while cursor < queue.size() and selected.size() < limit:
		var current_id: String = queue[cursor]
		cursor += 1
		for next_value: Variant in adjacency.get(current_id, []):
			var next_id: String = str(next_value)
			if seen.has(next_id):
				continue
			seen[next_id] = true
			queue.append(next_id)
			if not state.run.visited_node_ids.has(next_id) and not state.run.cleared_node_ids.has(next_id):
				selected.append(next_id)
				if selected.size() >= limit:
					break
	return selected

func quest_journal() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var catalog: QuestCatalog = QuestCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not bool(loaded.get("ok", false)) or state == null:
		return result
	for quest_id: String in catalog.quests.keys():
		var definition: Dictionary = catalog.get_quest(quest_id)
		var progress: Dictionary = state.meta.quest_progress.get(quest_id, {})
		definition["progress"] = progress.duplicate(true)
		definition["status"] = str(progress.get("status", "AVAILABLE"))
		definition["currentStage"] = int(progress.get("stage", 1))
		definition["available"] = state.meta.max_sector_cleared + 1 >= int(definition.get("minDepth", 1))
		result.append(definition)
	return result

func event_choice_costs(choice: Dictionary) -> Dictionary:
	var costs: Dictionary = choice.get("cost", {}).duplicate(true)
	var special: String = str(choice.get("special", ""))
	if state != null and state.run != null:
		var scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
		if special == "dataForCredits":
			costs["DATA"] = ceili(10.0 * scale)
		elif special == "greyDealer":
			# Master Spec prices EV13 at ceil(60% of the rounded rare shop price).
			var rare_shop_price: int = ceili((25.0 + 7.0 * state.run.depth) * 2.0 * scale)
			costs["CREDITS"] = ceili(float(rare_shop_price) * 0.6)
	return costs

func quest_choice_costs(choice: Dictionary) -> Dictionary:
	var costs: Dictionary = choice.get("cost", {}).duplicate(true)
	if state != null and state.run != null and str(choice.get("special", "")) == "buyEngine":
		costs["CREDITS"] = ceili(20.0 * CydleFormula.new().reward_scale(float(state.run.depth)))
	return costs

func event_choice_affordability(choice: Dictionary) -> Dictionary:
	return _run_wallet_affordability(event_choice_costs(choice))

func quest_choice_affordability(choice: Dictionary, quest_id: String = "") -> Dictionary:
	if not quest_id.is_empty() and state != null and state.run != null:
		var catalog: QuestCatalog = QuestCatalog.new()
		if bool(catalog.load_catalog().get("ok", false)):
			var quest: Dictionary = catalog.get_quest(quest_id)
			var progress: Dictionary = state.meta.quest_progress.get(quest_id, {})
			var stage_index: int = int(progress.get("stage", 1)) - 1
			if stage_index >= 0 and stage_index < quest.get("stages", []).size():
				if not _quest_stage_ready(quest, quest["stages"][stage_index], progress, bool(choice.get("bypassObjective", false))):
					return {"affordable": false, "reason": "Для этого решения сначала выполните цель этапа.", "costs": quest_choice_costs(choice)}
	return _run_wallet_affordability(quest_choice_costs(choice))

func _run_wallet_affordability(costs: Dictionary) -> Dictionary:
	if state == null or state.run == null:
		return {"affordable": false, "reason": "Для этого выбора нужен активный выезд.", "costs": costs}
	var wallet: Dictionary = state.run.to_dictionary().get("runWallet", {})
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var required: float = float(costs.get(currency, 0.0))
		var available: float = float(wallet.get(currency, 0.0))
		if available < required:
			return {"affordable": false, "reason": "Нужно %s %d; в выезде доступно %d." % [currency, ceili(required), floori(available)], "costs": costs}
	return {"affordable": true, "reason": "", "costs": costs}

func accept_quest(quest_id: String) -> bool:
	if state == null or not _garage_action_allowed():
		last_error = "Задание принимается в гараже между выездами."
		return false
	var catalog: QuestCatalog = QuestCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		last_error = str(loaded.get("error", "Каталог заданий недоступен."))
		return false
	var quest: Dictionary = catalog.get_quest(quest_id)
	if quest.is_empty():
		last_error = "Квест не найден."
		return false
	if state.meta.max_sector_cleared + 1 < int(quest.get("minDepth", 1)):
		last_error = "Квест откроется после сектора %d." % maxi(0, int(quest.get("minDepth", 1)) - 1)
		return false
	var previous: Dictionary = state.meta.quest_progress.get(quest_id, {})
	if str(previous.get("status", "")) in ["ACTIVE", "COMPLETE"]:
		last_error = "Этот квест уже принят или завершён."
		return false
	var payload: Dictionary = state.to_payload()
	var depth: int = state.meta.max_sector_cleared + 1
	var progress: Dictionary = previous.duplicate(true) if str(previous.get("status", "")) == "PAUSED" else {"stage": 1, "startedDepth": depth, "stageStartedDepth": depth, "completedStages": [], "choiceHistory": [], "flags": []}
	progress["status"] = "ACTIVE"
	if previous.is_empty():
		progress["stage"] = 1
		progress["startedDepth"] = depth
		progress["stageStartedDepth"] = depth
	var all_progress: Dictionary = payload["meta"].get("questProgress", {})
	all_progress[quest_id] = progress
	payload["meta"]["questProgress"] = all_progress
	return _commit_payload(payload)

func available_quest_stages() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or state.run == null or state.run.phase != "NODE":
		return result
	var catalog: QuestCatalog = QuestCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return result
	for quest_id: String in state.meta.quest_progress.keys():
		var progress: Dictionary = state.meta.quest_progress[quest_id]
		if str(progress.get("status", "")) != "ACTIVE":
			continue
		var definition: Dictionary = catalog.get_quest(quest_id)
		var stage_index: int = int(progress.get("stage", 1)) - 1
		if definition.is_empty() or stage_index < 0 or stage_index >= definition.get("stages", []).size():
			continue
		var stage: Dictionary = definition["stages"][stage_index]
		if (stage.get("choices", []) as Array).any(func(choice: Dictionary) -> bool: return _quest_stage_ready(definition, stage, progress, bool(choice.get("bypassObjective", false)))):
			result.append({"quest": definition, "stage": stage, "progress": progress.duplicate(true)})
	return result

func resolve_quest_choice(quest_id: String, choice_id: String) -> bool:
	if state == null or state.run == null or state.run.phase != "NODE":
		last_error = "Квестовое решение доступно только в дорожном узле."
		return false
	var opportunities: Array[Dictionary] = available_quest_stages()
	var opportunity: Dictionary = {}
	for candidate: Dictionary in opportunities:
		if str(candidate.get("quest", {}).get("id", "")) == quest_id:
			opportunity = candidate
			break
	if opportunity.is_empty():
		last_error = "Цель задания пока не выполнена или узел не подходит."
		return false
	var quest: Dictionary = opportunity["quest"]
	var stage: Dictionary = opportunity["stage"]
	var progress: Dictionary = opportunity["progress"]
	var choice: Dictionary = {}
	for candidate: Dictionary in stage.get("choices", []):
		if str(candidate.get("id", "")) == choice_id:
			choice = candidate
			break
	if choice.is_empty():
		last_error = "Выбор отсутствует в текущем этапе задания."
		return false
	if not _quest_stage_ready(quest, stage, progress, bool(choice.get("bypassObjective", false))):
		last_error = "Для этого решения сначала выполните цель этапа."
		return false
	var history_key: String = "%s:%d:%s" % [quest_id, int(progress.get("stage", 1)), choice_id]
	if progress.get("choiceHistory", []).any(func(entry: Dictionary) -> bool: return "%s:%d:%s" % [quest_id, int(entry.get("stage", 0)), str(entry.get("choiceId", ""))] == history_key):
		last_error = "Этот выбор задания уже был обработан."
		return false
	var payload: Dictionary = state.to_payload()
	var meta: Dictionary = payload["meta"]
	var run_payload: Dictionary = payload["run"]
	var wallet: Dictionary = run_payload["runWallet"]
	var scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
	var costs: Dictionary = quest_choice_costs(choice)
	var special: String = str(choice.get("special", ""))
	var affordability: Dictionary = _run_wallet_affordability(costs)
	if not bool(affordability.get("affordable", false)):
		last_error = str(affordability.get("reason", "Для квестового выбора недостаточно незакреплённых средств."))
		return false
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		wallet[currency] = float(wallet.get(currency, 0.0)) - float(costs.get(currency, 0.0))
		var gain: float = float(choice.get("gains", {}).get(currency, 0.0))
		wallet[currency] = maxf(0.0, float(wallet[currency]) + (ceili(gain * scale) if bool(choice.get("scaled", false)) else gain))
	if choice.has("reputation"):
		for faction: Variant in choice["reputation"].keys():
			meta["reputation"][str(faction)] = clampi(int(meta["reputation"].get(str(faction), 0)) + int(choice["reputation"][faction]), -100, 100)
	if choice.has("wanted"):
		run_payload["wanted"] = clampf(float(run_payload.get("wanted", 0.0)) + float(choice["wanted"]), 0.0, 100.0)
	if choice.has("hull"):
		run_payload["resources"]["hull"] = clampf(float(run_payload["resources"].get("hull", 0.0)) + float(choice["hull"]), 0.0, float(run_payload["resources"].get("maxHull", 0.0)))
	var grant: Dictionary = choice.get("grantItem", {}).duplicate(true)
	if special == "buyEngine":
		grant = {"templateId": "TR_ENGINE_1", "count": 1}
	if not grant.is_empty():
		var loaded_items: Dictionary = _item_catalog.load_catalog()
		if not bool(loaded_items.get("ok", false)):
			last_error = str(loaded_items.get("error", "Каталог предметов недоступен."))
			return false
		var loot: DeterministicRng = DeterministicRng.new()
		loot.restore(run_payload["lootRng"])
		for grant_index: int in range(maxi(1, int(grant.get("count", 1)))):
			var grant_id: String = "quest:%s:%s:%d" % [str(run_payload["seed"]), history_key, grant_index]
			var options: Dictionary = {"depth": state.run.depth, "biome": state.run.biome, "table": "ORDINARY", "secured": false, "grantId": grant_id, "origin": "quest", "acquiredAt": state.updated_at, "techOffsetOverride": 0}
			if grant.has("templateId"): options["forceTemplateId"] = grant["templateId"]
			if grant.has("templateIds"):
				var template_ids: Array = grant.get("templateIds", [])
				if template_ids.is_empty():
					last_error = "Квестовая награда содержит пустой список совместимых предметов."
					return false
				options["forceTemplateId"] = str(loot.pick(template_ids))
			if grant.has("category"): options["forceCategory"] = grant["category"]
			if grant.has("tag"): options["forceTag"] = grant["tag"]
			if grant.has("rarity"): options["forceRarity"] = grant["rarity"]
			var rolled: Dictionary = ItemFactory.new().roll_item(loot, _item_catalog, options)
			if not bool(rolled.get("ok", false)):
				last_error = str(rolled.get("error", "Квестовую награду нельзя создать."))
				return false
			var item: Dictionary = (rolled["item"] as ItemInstance).to_dictionary()
			var received: Dictionary = _receive_run_item(payload, item, "QUEST")
			if not bool(received.get("accepted", false)) and not bool(received.get("salvaged", false)):
				last_error = "Для квестовой награды нет места в грузовом отсеке или её отсёк фильтр."
				return false
			run_payload["grantIds"].append(grant_id)
			run_payload["lootRng"] = loot.serialize()
	var flags: Array = progress.get("flags", [])
	if choice.has("flag") and not flags.has(str(choice["flag"])): flags.append(str(choice["flag"]))
	if special.begins_with("schematic:") or special.begins_with("signalContract:"):
		var unlock: String = "quest-unlock:%s" % special
		if not meta["campaignFlags"].has(unlock): meta["campaignFlags"].append(unlock)
	if special == "serviceUpgrade": meta["campaignFlags"].append("quest-service-upgrade")
	if special == "anomalyPreview": meta["campaignFlags"].append("quest-anomaly-preview")
	if special == "grantCore":
		var core_rng: DeterministicRng = DeterministicRng.new()
		core_rng.seed("quest-core", "%s:%s" % [str(run_payload["seed"]), history_key])
		var core: Dictionary = ItemFactory.new().create_item(core_rng, _item_catalog, {"templateId": "MAT_CORE", "techLevel": state.run.depth, "rarity": "COMMON", "secured": false, "originGrantId": "quest:%s:%s:core" % [str(run_payload["seed"]), history_key], "origin": "quest", "acquiredAt": state.updated_at})
		if bool(core.get("ok", false)):
			var core_item: ItemInstance = core["item"] as ItemInstance
			core_item.core_group = clampi(int(ceil(float(state.run.depth) / 4.0)), 1, 4)
			var core_value: Dictionary = core_item.to_dictionary()
			var received_core: Dictionary = _receive_run_item(payload, core_value, "QUEST_CORE")
			if not bool(received_core.get("accepted", false)) and not bool(received_core.get("salvaged", false)):
				last_error = "Для калибровочного ядра нет места в грузовом отсеке или его отсёк фильтр."
				return false
			run_payload["grantIds"].append(str(core_value.get("originGrantId", "")))
	var choices: Array = progress.get("choiceHistory", [])
	choices.append({"stage": int(progress.get("stage", 1)), "choiceId": choice_id, "nodeId": state.run.current_node_id})
	progress["choiceHistory"] = choices
	if special == "questPause":
		progress["status"] = "PAUSED"
	else:
		var stage_key: String = "S%d" % int(progress.get("stage", 1))
		if not progress["completedStages"].has(stage_key): progress["completedStages"].append(stage_key)
		if bool(choice.get("questAdvance", false)):
			progress["stage"] = int(progress.get("stage", 1)) + 1
			progress["stageStartedDepth"] = state.run.depth
		else:
			progress["status"] = "COMPLETE" if int(progress.get("stage", 1)) >= 3 or special == "questAltComplete" else "ACTIVE"
			if progress["status"] == "ACTIVE":
				progress["stage"] = int(progress.get("stage", 1)) + 1
				progress["stageStartedDepth"] = state.run.depth
		var xp_milestone_flag: String = "xp-milestone:%s" % stage_key
		if not progress["flags"].has(xp_milestone_flag):
			_grant_experience(meta["operator"], ceili(60.0 * scale))
			progress["flags"].append(xp_milestone_flag)
	var all_progress: Dictionary = meta.get("questProgress", {})
	all_progress[quest_id] = progress
	meta["questProgress"] = all_progress
	run_payload["resources"]["gameTimeMs"] = float(run_payload["resources"].get("gameTimeMs", 0.0)) + 10000.0
	run_payload["lastCommandId"] = "quest:%s" % history_key
	if str(current_node().get("type", "")) == "QUEST":
		var cleared_nodes: Array = run_payload.get("clearedNodeIds", [])
		if not cleared_nodes.has(state.run.current_node_id):
			cleared_nodes.append(state.run.current_node_id)
		run_payload["clearedNodeIds"] = cleared_nodes
		run_payload["phase"] = "ROUTE"
	return _commit_payload(payload)

func _quest_stage_ready(quest: Dictionary, stage: Dictionary, progress: Dictionary, bypass_objective: bool = false) -> bool:
	var event_node: Dictionary = current_node()
	if str(event_node.get("type", "")) not in ["EVENT", "QUEST"]:
		return false
	if str(event_node.get("type", "")) == "QUEST" and (str(event_node.get("questId", "")) != str(quest.get("id", "")) or str(event_node.get("eventId", "")) != str(stage.get("eventId", ""))):
		return false
	if event_node.has("questEventIds") and not (event_node.get("questEventIds", []) as Array).has(str(stage.get("eventId", ""))):
		return false
	var history: Array = progress.get("choiceHistory", [])
	if not history.is_empty() and str(history[-1].get("nodeId", "")) == state.run.current_node_id:
		return false
	var required_biome: String = str(stage.get("biome", quest.get("biome", "")))
	if not required_biome.is_empty() and state.run.biome != required_biome:
		return false
	var deadline: int = int(stage.get("deadlineSectors", 0))
	if deadline > 0 and state.run.depth > int(progress.get("stageStartedDepth", progress.get("startedDepth", state.run.depth))) + deadline:
		return false
	var requirement: Dictionary = stage.get("requirement", {"kind": "none"})
	var requirement_kind: String = str(requirement.get("kind", "none"))
	var stage_started_depth: int = int(progress.get("stageStartedDepth", progress.get("startedDepth", state.run.depth)))
	if int(stage.get("stage", 1)) > 1 and requirement_kind == "visitBiome" and state.run.depth <= stage_started_depth:
		return false
	if str(quest.get("id", "")) == "Q04" and int(stage.get("stage", 0)) == 2 and state.run.depth <= stage_started_depth:
		return false
	if bypass_objective:
		return true
	match requirement_kind:
		"none": return true
		"visitBiome": return state.run.biome == str(requirement.get("biome", ""))
		"killElite":
			for layer: Array in state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) != "ELITE" or not state.run.cleared_node_ids.has(str(node.get("id", ""))): continue
					for enemy: Dictionary in node.get("enemies", []):
						if str(enemy.get("templateId", "")) == str(requirement.get("enemyId", "")): return true
			if str(quest.get("id", "")) == "Q05" and int(stage.get("stage", 0)) == 2 and state.run.biome == "B05":
				var survived_biome_combats: int = 0
				for layer: Array in state.run.graph.get("layers", []):
					for node: Dictionary in layer:
						if str(node.get("type", "")) in ["COMBAT", "ELITE", "BOUNTY", "ANOMALY"] and state.run.cleared_node_ids.has(str(node.get("id", ""))):
							survived_biome_combats += 1
				return survived_biome_combats >= 3
			return false
		"biomeCombat":
			var count: int = 0
			for layer: Array in state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) in ["COMBAT", "ELITE", "BOUNTY", "ANOMALY"] and state.run.cleared_node_ids.has(str(node.get("id", ""))): count += 1
			return state.run.biome == str(requirement.get("biome", "")) and count >= int(requirement.get("count", 1))
		"anomaly":
			var has_quest_anomaly: bool = false
			for layer: Array in state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "ANOMALY" and (node.get("questTargets", []) as Array).has(str(quest.get("id", ""))):
						has_quest_anomaly = true
						if state.run.cleared_node_ids.has(str(node.get("id", ""))): return true
			if has_quest_anomaly:
				return false
			for layer: Array in state.run.graph.get("layers", []):
				for node: Dictionary in layer:
					if str(node.get("type", "")) == "ANOMALY" and state.run.cleared_node_ids.has(str(node.get("id", ""))): return true
	return false

func _expire_quest_deadlines(meta: Dictionary, next_depth: int) -> void:
	var catalog: QuestCatalog = QuestCatalog.new()
	if not bool(catalog.load_catalog().get("ok", false)):
		return
	var all_progress: Dictionary = meta.get("questProgress", {})
	for quest_id: String in all_progress.keys():
		var progress: Dictionary = all_progress[quest_id]
		if str(progress.get("status", "")) != "ACTIVE":
			continue
		var quest: Dictionary = catalog.get_quest(quest_id)
		var stage_index: int = int(progress.get("stage", 1)) - 1
		if quest.is_empty() or stage_index < 0 or stage_index >= quest.get("stages", []).size():
			continue
		var deadline: int = int(quest["stages"][stage_index].get("deadlineSectors", 0))
		if deadline > 0 and next_depth > int(progress.get("stageStartedDepth", progress.get("startedDepth", next_depth))) + deadline:
			progress["status"] = "FAILED"
			if not progress["flags"].has("deadline-expired"): progress["flags"].append("deadline-expired")
			if quest_id == "Q02":
				meta["reputation"]["F_ECHO"] = maxi(-100, int(meta["reputation"].get("F_ECHO", 0)) - 3)
			all_progress[quest_id] = progress
	meta["questProgress"] = all_progress

func resolve_service_node(action: String, prototype_id: String = "", autopilot_repair_budget: float = -1.0) -> bool:
	if state == null or state.run == null or state.run.phase != "NODE":
		last_error = "Сервисное действие доступно только в дорожном узле."
		return false
	var node: Dictionary = current_node()
	var node_id: String = str(node.get("id", ""))
	var kind: String = str(node.get("type", ""))
	if action == "LEAVE_NODE":
		if kind == "ANOMALY" and not state.run.cleared_node_ids.has(node_id):
			last_error = "Сначала победите охрану аномалии."
			return false
		var leave_payload: Dictionary = state.to_payload()
		var leave_run: Dictionary = leave_payload["run"]
		if not leave_run["clearedNodeIds"].has(node_id):
			leave_run["clearedNodeIds"].append(node_id)
		leave_run["phase"] = "ROUTE"
		var leave_time: int = 5000 if kind == "CACHE" else 8000 if kind in ["SHOP", "REPAIR", "FUEL"] else 10000
		leave_run["resources"]["gameTimeMs"] = float(leave_run["resources"].get("gameTimeMs", 0.0)) + leave_time
		leave_run["lastCommandId"] = "node:%s:leave" % node_id
		return _commit_payload(leave_payload)
	if state.run.cleared_node_ids.has(node_id):
		last_error = "Этот узел уже использован."
		return false
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
			if autopilot_repair_budget >= 0.0 and float(state.run.autopilot_repair_spend) + float(credit_cost) > autopilot_repair_budget:
				last_error = "Лимит ремонта автопилота (%d ¤) исчерпан." % int(autopilot_repair_budget)
				return false
			wallet["CREDITS"] = float(wallet["CREDITS"]) - credit_cost
			if autopilot_repair_budget >= 0.0:
				run_payload["autopilotRepairSpend"] = float(state.run.autopilot_repair_spend) + float(credit_cost)
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
			if autopilot_repair_budget >= 0.0 and float(state.run.autopilot_repair_spend) + float(credit_cost) > autopilot_repair_budget:
				last_error = "Лимит ремонта автопилота (%d ¤) исчерпан." % int(autopilot_repair_budget)
				return false
			wallet["CREDITS"] = float(wallet["CREDITS"]) - credit_cost
			if autopilot_repair_budget >= 0.0:
				run_payload["autopilotRepairSpend"] = float(state.run.autopilot_repair_spend) + float(credit_cost)
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
			if not item_value.is_empty():
				_receive_run_item(payload, item_value, "CACHE")
			run_payload["grantIds"].append(grant_id)
			run_payload["lootRng"] = rng.serialize()
		if str(run_payload.get("contract", {}).get("status", "")) == "ACTIVE" and str(run_payload["contract"].get("kind", "")) == "TECH" and str(run_payload["contract"].get("targetNodeId", "")) == node_id:
			if not _complete_contract(payload, {"DATA": ceili(15.0 * scale)}, {"rarity": "MODIFIED", "tag": str(run_payload["contract"].get("targetTechTag", "tech"))}):
				return false
	else:
		last_error = "Сначала приобретите товар или выйдите из магазина."
		return false
	run_payload["clearedNodeIds"].append(node_id)
	run_payload["phase"] = "ROUTE"
	resources["gameTimeMs"] = float(resources.get("gameTimeMs", 0.0)) + elapsed
	run_payload["lastCommandId"] = "node:%s:%s" % [node_id, action]
	return _commit_payload(payload)

func _settle_escort_contract(payload: Dictionary) -> void:
	var run_payload: Dictionary = payload["run"]
	var contract: Dictionary = run_payload.get("contract", {})
	if str(contract.get("kind", "")) != "ESCORT" or str(contract.get("status", "")) != "ACTIVE":
		return
	var resources: Dictionary = run_payload.get("resources", {})
	if int(contract.get("combatNodes", 0)) >= 2 and float(run_payload.get("wanted", 0.0)) <= 40.0 and float(resources.get("fuel", 0.0)) >= 3.0:
		var rewards: Dictionary = {"CREDITS": ceili(50.0 * CydleFormula.new().reward_scale(float(run_payload.get("depth", 1))))}
		var faction_id: String = str(contract.get("factionId", "F_RUST"))
		var reputation: Dictionary = {faction_id: 8} if ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(faction_id) else {"F_RUST": 8}
		_complete_contract(payload, rewards, {}, reputation)
	else:
		contract["status"] = "FAILED"

func _complete_contract(payload: Dictionary, rewards: Dictionary, item_spec: Dictionary, reputation: Dictionary = {}) -> bool:
	var run_payload: Dictionary = payload["run"]
	var contract: Dictionary = run_payload.get("contract", {})
	if contract.is_empty() or str(contract.get("status", "")) != "ACTIVE":
		return true
	var completion_id: String = "%s:reward" % str(contract.get("instanceId", ""))
	if run_payload["grantIds"].has(completion_id):
		contract["status"] = "COMPLETE"
		contract["rewardClaimed"] = true
		return true
	var scale: float = CydleFormula.new().reward_scale(float(run_payload.get("depth", 1)))
	for currency: String in rewards.keys():
		var reward_amount: float = float(rewards[currency])
		if currency == "CREDITS" and run_payload.get("escalationIds", []).has("WANTED_PLUS"):
			reward_amount = ceili(reward_amount * 1.15)
		run_payload["runWallet"][currency] = float(run_payload["runWallet"].get(currency, 0.0)) + reward_amount
	var paid: Dictionary = {}
	if not item_spec.is_empty():
		var loaded: Dictionary = _item_catalog.load_catalog()
		if not bool(loaded.get("ok", false)):
			last_error = str(loaded.get("error", "Каталог предметов недоступен для награды контракта."))
			return false
		var rng: DeterministicRng = DeterministicRng.new()
		rng.restore(run_payload["lootRng"])
		var options: Dictionary = {"depth": int(run_payload["depth"]), "biome": str(run_payload["biome"]), "table": "ELITE" if str(contract.get("kind", "")) in ["HUNT", "SIGNAL"] else "ORDINARY", "secured": false, "grantId": completion_id + ":item", "origin": "contract", "acquiredAt": state.updated_at, "forceRarity": str(item_spec.get("rarity", "RARE")), "forceTag": str(item_spec.get("tag", ""))}
		if item_spec.has("templateId"):
			options["forceTemplateId"] = str(item_spec["templateId"])
		var rolled: Dictionary = ItemFactory.new().roll_item(rng, _item_catalog, options)
		if not bool(rolled.get("ok", false)):
			last_error = str(rolled.get("error", "Награду контракта нельзя создать."))
			return false
		paid = (rolled["item"] as ItemInstance).to_dictionary()
		var received: Dictionary = _receive_run_item(payload, paid, "CONTRACT")
		if not bool(received.get("accepted", false)) and not bool(received.get("salvaged", false)):
			last_error = "Для гарантированной награды контракта нет места в грузовом отсеке или её отсёк фильтр."
			return false
		run_payload["lootRng"] = rng.serialize()
	for faction: String in reputation.keys():
		payload["meta"]["reputation"][faction] = clampi(int(payload["meta"]["reputation"].get(faction, 0)) + int(reputation[faction]), -100, 100)
	if str(contract.get("kind", "")) == "TECH":
		var blueprint: String = "contract-blueprint:%s" % str(contract.get("id", ""))
		if not payload["meta"]["campaignFlags"].has(blueprint): payload["meta"]["campaignFlags"].append(blueprint)
		var template_id: String = str(paid.get("templateId", ""))
		var item_blueprint: String = "contract-blueprint:%s" % template_id
		if not template_id.is_empty() and not payload["meta"]["campaignFlags"].has(item_blueprint): payload["meta"]["campaignFlags"].append(item_blueprint)
	run_payload["grantIds"].append(completion_id)
	contract["status"] = "COMPLETE"
	contract["rewardClaimed"] = true
	return true

func continue_campaign(escalation_ids: Array[String] = []) -> bool:
	if state == null or state.run == null or state.run.phase != "CHECKPOINT":
		last_error = "Продолжить кампанию можно только с контрольного узла."
		return false
	if state.run.depth == 12 and state.meta.campaign_flags.has("CAMPAIGN_COMPLETED") and not state.meta.campaign_flags.has("ENDING_SELECTED"):
		last_error = "Перед эндгеймом необходимо выбрать исход кампании."
		return false
	var next_depth: int = state.run.depth + 1
	if not _validate_escalation_selection(escalation_ids, next_depth): return false
	var build: Dictionary = run_build_preview()
	var seed: String = "%s:sector:%d" % [state.run.seed, next_depth]
	var biome: String = _generator.campaign_biome(next_depth, seed, _campaign_biome_history(state.meta.campaign_flags))
	var generated: Dictionary = _generator.generate(seed, next_depth, biome, false, state.run.wanted, state.run.events_seen, escalation_ids, _last_boss_history(state.meta.campaign_flags))
	if not bool(generated.get("ok", false)):
		last_error = str(generated.get("error", "Не удалось создать следующий сектор."))
		return false
	_apply_active_quest_targets(generated["graph"], biome)
	_apply_active_quest_event_ids(generated["graph"], biome)
	_apply_faction_world_effects(generated["graph"], seed)
	var payload: Dictionary = state.to_payload()
	# A checkpoint is the sector-clear boundary even when the next boss gate is
	# several depths away. Persisting this lets depth-gated quests and garage
	# upgrades unlock on the authored d5/d6 progression rather than only on d8/d12.
	payload["meta"]["maxSectorCleared"] = maxi(int(payload["meta"].get("maxSectorCleared", 0)), int(state.run.depth))
	_expire_quest_deadlines(payload["meta"], next_depth)
	_record_campaign_biome(payload["meta"], next_depth, biome)
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
	run_payload["escalationIds"] = escalation_ids.duplicate()
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

func checkpoint_repair_quote() -> Dictionary:
	if state == null or state.run == null or state.run.phase != "CHECKPOINT":
		return {"valid": false, "affordable": false, "credits": 0, "repair": 0.0, "error": "Ремонт доступен только на контрольном узле."}
	var resources: Dictionary = state.run.resources
	var missing: float = float(resources.get("maxHull", 0.0)) - float(resources.get("hull", 0.0))
	if missing <= 0.0:
		return {"valid": false, "affordable": false, "credits": 0, "repair": 0.0, "error": "Корпус уже полностью восстановлен."}
	var credits: int = ceili(15.0 * CydleFormula.new().reward_scale(float(state.run.depth)))
	var repair_amount: float = 30.0 * (1.15 if state.meta.campaign_flags.has("quest-service-upgrade") else 1.0)
	return {"valid": true, "affordable": state.run.wallet.credits >= float(credits), "credits": credits, "repair": minf(missing, repair_amount), "error": "" if state.run.wallet.credits >= float(credits) else "Недостаточно незакреплённых кредитов."}

func repair_checkpoint_hull(autopilot_repair_budget: float = -1.0) -> bool:
	var quote: Dictionary = checkpoint_repair_quote()
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Ремонт корпуса недоступен."))
		return false
	if autopilot_repair_budget >= 0.0 and float(state.run.autopilot_repair_spend) + float(quote["credits"]) > autopilot_repair_budget:
		last_error = "Лимит ремонта автопилота (%d ¤) исчерпан." % int(autopilot_repair_budget)
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var wallet: Dictionary = run_payload["runWallet"]
	var resources: Dictionary = run_payload["resources"]
	wallet["CREDITS"] = float(wallet.get("CREDITS", 0.0)) - float(quote["credits"])
	resources["hull"] = minf(float(resources.get("maxHull", 0.0)), float(resources.get("hull", 0.0)) + float(quote["repair"]))
	if autopilot_repair_budget >= 0.0:
		run_payload["autopilotRepairSpend"] = float(run_payload.get("autopilotRepairSpend", 0.0)) + float(quote["credits"])
	resources["gameTimeMs"] = float(resources.get("gameTimeMs", 0.0)) + 8000.0
	run_payload["lastCommandId"] = "checkpoint:repair:%s:%d" % [str(run_payload.get("seed", "")), int(resources["gameTimeMs"])]
	return _commit_payload(payload)

func checkpoint_shipping_quote(item_ids: Array[String], currency_percent: int = 0) -> Dictionary:
	if state == null or state.run == null or state.run.phase != "CHECKPOINT":
		return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": 0, "items": [], "wallet": {}, "error": "Закрепить груз можно только на контрольном узле."}
	if currency_percent < 0 or currency_percent > 50:
		return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": 0, "items": [], "wallet": {}, "error": "За один выезд можно отправить не более половины незакреплённой валюты."}
	var checkpoint_id: String = "ship:%s:%s" % [state.run.seed, state.run.current_node_id]
	if state.run.shipped_checkpoint_ids.has(checkpoint_id):
		return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": 0, "items": [], "wallet": {}, "checkpointId": checkpoint_id, "error": "На этой контрольной точке груз уже отправлен."}
	var unique_ids: Dictionary = {}
	var catalog_result: Dictionary = _item_catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": 0, "items": [], "wallet": {}, "checkpointId": checkpoint_id, "error": str(catalog_result.get("error", "Каталог груза недоступен."))}
	for item_id: String in item_ids:
		if item_id.is_empty() or unique_ids.has(item_id):
			return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": 0, "items": [], "wallet": {}, "checkpointId": checkpoint_id, "error": "Список груза содержит пустой или повторяющийся ID."}
		unique_ids[item_id] = true
	var cargo_units: int = 0
	var selected_items: Array[Dictionary] = []
	var cargo: Array = state.run.unsecured_cargo
	for item_id: String in item_ids:
		var found: Dictionary = {}
		for candidate: Dictionary in cargo:
			if str(candidate.get("itemId", "")) == item_id:
				found = candidate
				break
		if found.is_empty():
			return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": cargo_units, "items": [], "wallet": {}, "checkpointId": checkpoint_id, "error": "Предмет %s отсутствует в незакреплённом грузе." % item_id}
		cargo_units += int(_item_catalog.get_template(str(found.get("templateId", ""))).get("cargoUnits", 1))
		selected_items.append(found.duplicate(true))
	if cargo_units > 5:
		return {"valid": false, "affordable": false, "credits": 0, "cargoUnits": cargo_units, "items": selected_items, "wallet": {}, "checkpointId": checkpoint_id, "error": "На один вывоз допускается не более 5 единиц груза."}
	var shipping_cost: int = ceili(10.0 * CydleFormula.new().reward_scale(float(state.run.depth)))
	var wallet: Dictionary = state.run.wallet.to_dictionary()
	var shipped_wallet: Dictionary = {}
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var balance: float = float(wallet.get(currency, 0.0))
		shipped_wallet[currency] = floorf(balance * float(currency_percent) / 100.0)
	var has_value: bool = not item_ids.is_empty() or float(shipped_wallet["CREDITS"]) > 0.0 or float(shipped_wallet["SCRAP"]) > 0.0 or float(shipped_wallet["DATA"]) > 0.0
	var affordable: bool = state.run.wallet.credits >= float(shipping_cost) + float(shipped_wallet["CREDITS"]) and has_value
	var error: String = "" if affordable else "Нужно %d незакреплённых кредитов и выбрать груз или валюту." % shipping_cost
	return {"valid": true, "affordable": affordable, "credits": shipping_cost, "cargoUnits": cargo_units, "items": selected_items, "wallet": shipped_wallet, "currencyPercent": currency_percent, "checkpointId": checkpoint_id, "error": error}

func ship_checkpoint_cargo(item_ids: Array[String], currency_percent: int = 0) -> bool:
	var quote: Dictionary = checkpoint_shipping_quote(item_ids, currency_percent)
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Отправка груза недоступна."))
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var meta: Dictionary = payload["meta"]
	var checkpoint_id: String = str(quote["checkpointId"])
	if run_payload["shippedCheckpointIds"].has(checkpoint_id):
		last_error = "Отправка с этой контрольной точки уже зарегистрирована."
		return false
	var selection: Dictionary = {}
	for item_id: String in item_ids:
		selection[item_id] = true
	var cargo: Array = run_payload["unsecuredCargo"]
	var remaining: Array[Dictionary] = []
	var shipped_items: Array[Dictionary] = []
	for value: Dictionary in cargo:
		var item_id: String = str(value.get("itemId", ""))
		if selection.has(item_id):
			var secured: Dictionary = value.duplicate(true)
			secured["secured"] = true
			secured["origin"] = "checkpoint-shipping"
			if not _inventory_has(meta["inventory"], item_id):
				meta["inventory"].append(secured)
			shipped_items.append(secured)
		else:
			remaining.append(value.duplicate(true))
	if shipped_items.size() != item_ids.size():
		last_error = "Состав груза изменился до завершения отправки."
		return false
	var wallet: Dictionary = run_payload["runWallet"]
	var bank: Dictionary = meta["protectedBank"]
	wallet["CREDITS"] = float(wallet.get("CREDITS", 0.0)) - float(quote["credits"])
	var shipped_wallet: Dictionary = quote["wallet"]
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var amount: float = float(shipped_wallet.get(currency, 0.0))
		wallet[currency] = float(wallet.get(currency, 0.0)) - amount
		bank[currency] = float(bank.get(currency, 0.0)) + amount
	run_payload["unsecuredCargo"] = remaining
	run_payload["shippedCargo"].append_array(shipped_items)
	run_payload["shippedCheckpointIds"].append(checkpoint_id)
	run_payload["lastCommandId"] = "checkpoint:ship:%s" % checkpoint_id
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
			var shop_faction: String = _world_faction(state.run.seed, node_id)
			var shop_reputation: int = int(state.meta.reputation.get(shop_faction, 0))
			var discount: float = 0.15 if shop_reputation >= 60 else 0.10 if shop_reputation >= 30 else 0.0
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
				var base_price: int = ceili((25.0 + 7.0 * tech) * multiplier * CydleFormula.new().reward_scale(float(tech)))
				var price: int = maxi(1, ceili(float(base_price) * (1.0 - discount)))
				stock.append({"item": item, "basePrice": base_price, "price": price, "purchased": false, "factionId": shop_faction, "discountPercent": int(round(discount * 100.0))})
			if stock.is_empty():
				last_error = "Не удалось сформировать ассортимент магазина."
				return []
			node["shopFactionId"] = shop_faction
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
	if not ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"].has(str(node.get("type", ""))):
		last_error = "Текущий узел не является боевым."
		return false
	if state.run.cleared_node_ids.has(str(node.get("id", ""))):
		last_error = "Этот боевой узел уже пройден."
		return false
	var build: Dictionary = run_build_preview()
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
	var enemy_specs: Array = _apply_wanted_elite_modifiers(node.get("enemies", []), state.run.seed, state.run.current_node_id, float(state.run.wanted))
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
		"coolingPenalty": 2.0 if state.run.escalation_ids.has("HEAT_FOG") else 0.0,
		"enemyWindupMult": 0.8 if state.run.escalation_ids.has("HUNT_FAST") else 1.0,
		"minimumEnemyTelegraphMs": 600 if state.run.escalation_ids.has("HUNT_FAST") else 0,
		"elitePen": 10.0 if state.run.escalation_ids.has("SHIELD_BREAK") and effective_type in ["ELITE", "ANOMALY", "BOUNTY"] else 0.0,
		"droneWar": state.run.escalation_ids.has("DRONE_WAR"),
	}
	if bool(pending_next.get("alliedTurret", false)):
		config["alliedEnemies"] = [{"templateId": "E08", "strength": 0.5}]
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

## Real-time playback advances in memory and writes the durable snapshot on a bounded
## cadence: the full transactional save protocol costs ~200 ms, far more than a 100 ms tick.
## Callers scale the interval with the playback speed so the crash-loss window stays about
## one second of wall-clock time at any speed multiplier.
func advance_combat_playback(delta_ms: int, persist_interval_ms: int = COMBAT_PLAYBACK_PERSIST_INTERVAL_MS) -> bool:
	if _combat == null:
		last_error = "Нет активного боя."
		return false
	var interval_ms: int = maxi(CombatSimulator.TICK_MS, persist_interval_ms)
	var remaining: int = maxi(0, delta_ms)
	while remaining >= CombatSimulator.TICK_MS and _combat.outcome.is_empty():
		var stepped: Dictionary = _simulator.step_combat(_combat)
		if not bool(stepped.get("ok", false)):
			last_error = str(stepped.get("error", "Боевой шаг отклонён."))
			return false
		_combat = stepped["state"] as CombatState
		remaining -= CombatSimulator.TICK_MS
		if not _combat.outcome.is_empty() or _combat_unpersisted_ms() >= interval_ms:
			if not _persist_combat_snapshot():
				return false
	last_error = ""
	return true

## Renders the rest of the battle without paying for a save on every tick.
func skip_combat_to_outcome(max_ticks: int = 1800) -> bool:
	if _combat == null:
		last_error = "Нет активного боя."
		return false
	var ticks: int = 0
	while ticks < max_ticks and _combat.outcome.is_empty():
		var stepped: Dictionary = _simulator.step_combat(_combat)
		if not bool(stepped.get("ok", false)):
			last_error = str(stepped.get("error", "Боевой шаг отклонён."))
			return false
		_combat = stepped["state"] as CombatState
		ticks += 1
	if ticks > 0 and not _persist_combat_snapshot():
		return false
	last_error = ""
	return true

## Writes any in-memory combat progress before leaving the battle or closing the app.
func flush_combat_snapshot() -> bool:
	if _combat == null or _combat_unpersisted_ms() <= 0:
		return true
	if not _persist_combat_snapshot():
		return false
	last_error = ""
	return true

func _combat_unpersisted_ms() -> int:
	if _combat == null:
		return 0
	var persisted_ms: int = 0
	if state != null and state.run != null and state.run.combat_snapshot != null:
		persisted_ms = state.run.combat_snapshot.sim_time_ms
	return maxi(0, _combat.time_ms - persisted_ms)

func resolve_active_combat() -> bool:
	if _combat == null or _combat.outcome.is_empty() or state == null or state.run == null:
		last_error = "Бой ещё не завершён."
		return false
	var run_payload: Dictionary = state.run.to_dictionary()
	var resources: Dictionary = run_payload["resources"]
	resources["hp"] = minf(_combat.operator.hp, float(resources.get("maxHP", _combat.operator.hp)))
	resources["shield"] = minf(_combat.operator.shield, float(resources.get("maxShield", _combat.operator.shield)))
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
	var encounter_faction: String = str(node.get("factionId", ""))
	if encounter_faction == "F_VANTA":
		var corporate_delta: float = 7.0 if _active_node_type in ["ELITE", "BOUNTY", "ANOMALY"] else 4.0
		run_payload["wanted"] = clampf(float(run_payload.get("wanted", 0.0)) + corporate_delta, 0.0, 100.0)
	if ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"].has(encounter_faction) and int(state.meta.reputation.get(encounter_faction, 0)) <= -30:
		run_payload["wanted"] = clampf(float(run_payload.get("wanted", 0.0)) + 3.0, 0.0, 100.0)
	if _active_node_type in ["ELITE", "ANOMALY", "BOUNTY"] and run_payload.get("escalationIds", []).has("WANTED_PLUS"):
		run_payload["wanted"] = clampf(float(run_payload.get("wanted", 0.0)) + 5.0, 0.0, 100.0)
	var escaped_cargo: int = 0
	for escape_value: Dictionary in _combat.metrics.get("escaped", []):
		escaped_cargo += int(escape_value.get("cargoItems", 1))
	var unsecured: Array = run_payload.get("unsecuredCargo", [])
	for _item_index: int in range(mini(escaped_cargo, unsecured.size())):
		unsecured.pop_back()
	run_payload["unsecuredCargo"] = unsecured
	var reward: Dictionary = _battle_reward(_active_node_type if not _active_node_type.is_empty() else str(node.get("type", "COMBAT")), state.run.depth, state.run.biome, node_id, run_payload, _active_reward_modifiers)
	run_payload["lootRng"] = reward["lootRng"]
	var payload: Dictionary = state.to_payload()
	payload["run"] = run_payload
	var contract: Dictionary = run_payload.get("contract", {})
	if not contract.is_empty() and str(contract.get("status", "")) == "ACTIVE":
		if str(contract.get("kind", "")) in ["HUNT", "SIGNAL"] and str(contract.get("targetNodeId", "")) == node_id and str(node.get("type", "")) == "ELITE":
			var target_scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
			var contract_item: Dictionary = {"rarity": str(contract.get("rewardItem", {}).get("rarity", "RARE")), "tag": str(contract.get("targetTechTag", "weapon"))}
			var credits_reward: Dictionary = {"CREDITS": ceili(30.0 * target_scale)}
			if str(contract.get("kind", "")) == "SIGNAL":
				contract_item = {"rarity": "UNIQUE", "templateId": str(contract.get("targetUniqueId", ""))}
				credits_reward = {}
			var contract_reputation: Dictionary = contract.get("rewardReputation", {})
			if not _complete_contract(payload, credits_reward, contract_item, contract_reputation):
				return false
		elif str(contract.get("kind", "")) == "TECH" and str(contract.get("targetNodeId", "")) == node_id and str(node.get("type", "")) == "ANOMALY":
			var target_scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
			if not _complete_contract(payload, {"DATA": ceili(15.0 * target_scale)}, {"rarity": "MODIFIED", "tag": str(contract.get("targetTechTag", "tech"))}):
				return false
		elif str(contract.get("kind", "")) in ["ESCORT", "HUNT", "TECH", "SIGNAL"] and str(node.get("type", "")) in ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"]:
			contract["combatNodes"] = int(contract.get("combatNodes", 0)) + 1
	var wallet: Dictionary = run_payload["runWallet"]
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		wallet[currency] = float(wallet.get(currency, 0.0)) + float(reward["wallet"].get(currency, 0.0))
	for item_value: Dictionary in reward["items"]:
		var received: Dictionary = _receive_run_item(payload, item_value, "COMBAT")
		if not bool(received.get("accepted", false)) and not bool(received.get("salvaged", false)):
			reward["discardedItems"] += 1
	run_payload["grantIds"].append_array(reward["grantIds"])
	var xp_grant_id: String = "combat:%s:%s:xp" % [state.run.seed, node_id]
	if not run_payload["grantIds"].has(xp_grant_id):
		_grant_experience(payload["meta"]["operator"], int(reward["xp"]))
		run_payload["grantIds"].append(xp_grant_id)
	if not run_payload["clearedNodeIds"].has(node_id):
		run_payload["clearedNodeIds"].append(node_id)
	run_payload["phase"] = "CHECKPOINT" if int(node.get("layer", 0)) == 5 else "NODE" if str(node.get("type", "")) == "ANOMALY" else "ROUTE"
	run_payload["combatResult"] = null
	run_payload["combatSnapshot"] = null
	run_payload["lastCommandId"] = "combat:%s" % node_id
	var retain_elite_contract: bool = bool(_active_reward_modifiers.get("extraRareOnElite", false)) and _active_node_type != "ELITE"
	run_payload["pendingCombatEffects"] = {"initialTempShield": 0.0, "extraHeat": 0.0}
	run_payload["pendingNextCombat"] = {"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false, "bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false, "alliedTurret": false, "extraRareOnElite": retain_elite_contract}
	if str(node.get("type", "")) == "BOSS":
		var depth: int = int(state.run.depth)
		var boss_enemies: Array = node.get("enemies", [])
		if not boss_enemies.is_empty():
			var previous_boss_flag: String = ""
			for campaign_flag: String in payload["meta"]["campaignFlags"]:
				if str(campaign_flag).begins_with("BOSS_LAST:"):
					previous_boss_flag = str(campaign_flag)
			if not previous_boss_flag.is_empty():
				payload["meta"]["campaignFlags"].erase(previous_boss_flag)
			payload["meta"]["campaignFlags"].append("BOSS_LAST:%s" % str(boss_enemies[0].get("templateId", "")))
		if depth % 4 == 0:
			payload["meta"]["unlockedForpost"] = maxi(int(payload["meta"]["unlockedForpost"]), depth)
			payload["meta"]["maxSectorCleared"] = maxi(int(payload["meta"]["maxSectorCleared"]), depth)
			var boss_flag: String = "SECTOR_BOSS_%d" % depth
			if not payload["meta"]["campaignFlags"].has(boss_flag):
				payload["meta"]["campaignFlags"].append(boss_flag)
			var milestones: Array[String] = []
			if depth == 4:
				milestones.append("ACT_I_ARCHIVE")
				milestones.append("FORPOST_4")
			elif depth == 8:
				milestones.append("ACT_II_DRONE_LINE")
				milestones.append("TARGET_HUNT_TOOLS")
				milestones.append("FORPOST_8")
			for milestone: String in milestones:
				if not payload["meta"]["campaignFlags"].has(milestone): payload["meta"]["campaignFlags"].append(milestone)
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
		"ELITE", "ANOMALY":
			credits = 28.0; scrap = 7.0; data = 3.0; xp = ceili(55.0 * scale)
			item_chance = 1.0; extra_item_chance = 0.25; core_chance = 0.15; table = "ELITE"
		"BOUNTY":
			credits = 35.0; scrap = 5.0; data = 3.0; xp = 0
			item_chance = 0.9; core_chance = 0.08; table = "ELITE"
		"BOSS":
			credits = 85.0; scrap = 18.0; data = 8.0; xp = ceili(160.0 * scale)
			item_chance = 1.0; extra_item_chance = 0.5; core_chance = 1.0; table = "BOSS"
	var escalation_ids: Array = run_payload.get("escalationIds", [])
	credits = ceili(credits * scale * (1.1 if biome == "B02" else 1.0) * (1.0 + float(modifiers.get("bountyCreditsBonus", 0.0))) * (1.15 if escalation_ids.has("WANTED_PLUS") else 1.0))
	data = ceili(data * scale * (1.2 if biome == "B04" else 1.0) * (1.1 if escalation_ids.has("SCAN_DARK") else 1.0))
	var scrap_reward: int = ceili(scrap * scale * (1.1 if escalation_ids.has("REPAIR_RARE") else 1.0))
	var wallet: Dictionary = {"CREDITS": credits, "SCRAP": scrap_reward, "DATA": data}
	var items: Array[Dictionary] = []
	var grant_ids: Array[String] = []
	var rng: DeterministicRng = DeterministicRng.new()
	rng.restore(run_payload["lootRng"])
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return {"wallet": wallet, "items": items, "grantIds": grant_ids, "lootRng": run_payload["lootRng"], "xp": xp, "discardedItems": 0}
	var grants: Array[float] = [item_chance, extra_item_chance]
	var forced_rarities: Array[String] = ["", ""]
	if node_type == "ELITE" and escalation_ids.has("DRONE_WAR"):
		grants.append(0.15)
		forced_rarities.append("")
	if node_type == "BOSS" and escalation_ids.has("LONG_RUN"):
		grants.append(0.25)
		forced_rarities.append("")
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
		if node_type == "ELITE" and escalation_ids.has("SHIELD_BREAK"): roll_options["rareShift"] = 0.1
		if escalation_ids.has("HEAT_FOG"): roll_options["energyWeightBonus"] = 0.1
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
	var contract: Dictionary = run_payload.get("contract", {})
	if str(contract.get("status", "")) == "ACTIVE":
		contract["status"] = "FAILED"
	var field_equipment: Dictionary = run_payload.get("equipment", {})
	var field_item_ids: Array[String] = _field_secured_equipped_ids(field_equipment, meta["inventory"])
	meta["equipment"] = _settled_field_equipment(field_equipment, meta["inventory"], meta.get("equipment", {}))
	for index: int in range(meta["inventory"].size()):
		var item: Dictionary = meta["inventory"][index]
		if field_item_ids.has(str(item.get("itemId", ""))):
			item["durability"] = maxf(0.0, float(item.get("durability", 100.0)) - 20.0)
		meta["inventory"][index] = item
	var revive_cost: int = 5 if int(meta.get("garage", {}).get("GARAGE_MED", 1)) >= 2 else 10
	var paid: bool = float(meta["protectedBank"].get("CREDITS", 0.0)) >= float(revive_cost)
	if paid:
		meta["protectedBank"]["CREDITS"] = float(meta["protectedBank"]["CREDITS"]) - float(revive_cost)
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
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Профиль восстановления после поражения повреждён."))
		return false
	var build: Dictionary = BuildResolver.new().resolve_build(_build_input(parsed["state"] as GameSaveState))
	var stats: Dictionary = build.get("stats", {})
	var resources: Dictionary = run_payload["resources"]
	resources["hp"] = float(stats.get("maxHP", 1.0)) * (1.0 if paid else 0.5)
	resources["maxHP"] = float(stats.get("maxHP", 1.0))
	resources["shield"] = float(stats.get("maxShield", 0.0)) if paid else 0.0
	resources["maxShield"] = float(stats.get("maxShield", 0.0))
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

func item_disposal_quote(item_id: String, method: String) -> Dictionary:
	if not _garage_action_allowed():
		return {"valid": false, "error": "Продажа и разбор доступны в гараже после завершения выезда."}
	if not ["SELL", "DISMANTLE"].has(method):
		return {"valid": false, "error": "Неизвестный способ утилизации предмета."}
	var item: Dictionary = _secured_inventory_item(item_id)
	if item.is_empty():
		return {"valid": false, "error": "Предмет отсутствует в постоянном складе."}
	if not equipped_slot(item_id).is_empty():
		return {"valid": false, "error": "Сначала снимите предмет со всех слотов."}
	if not _item_catalog_loaded():
		return {"valid": false, "error": last_error}
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	if template.is_empty():
		return {"valid": false, "error": "Шаблон предмета отсутствует в каталоге."}
	var tech: int = int(item.get("techLevel", 1))
	var scale: float = CydleFormula.new().reward_scale(float(tech))
	var rarity_multiplier: Dictionary = {"COMMON": 1.0, "MODIFIED": 1.3, "RARE": 2.0, "LEGENDARY": 4.0, "UNIQUE": 10.0}
	var price: int = ceili((25.0 + 7.0 * float(tech)) * float(rarity_multiplier.get(str(item.get("rarity", "COMMON")), 1.0)) * scale)
	if method == "SELL":
		return {"valid": true, "itemId": item_id, "method": method, "credits": floori(float(price) * 0.25), "scrap": 0, "data": 0, "error": ""}
	var scrap_cap: int = floori(18.0 * scale * 0.6)
	var data_cap: int = floori(10.0 * scale * 0.6)
	var scrap_gain: int = mini(ceili(3.0 * scale), scrap_cap)
	var digital: bool = (template.get("tags", []) as Array).has("digital")
	var data_gain: int = mini(1 if digital else 0, data_cap)
	return {"valid": true, "itemId": item_id, "method": method, "credits": 0, "scrap": scrap_gain, "data": data_gain, "error": ""}

func run_item_dismantle_quote(item_id: String) -> Dictionary:
	if state == null or state.run == null or not ["ROUTE", "CHECKPOINT"].has(state.run.phase):
		return {"valid": false, "scrap": 0, "data": 0, "error": "Разбор груза доступен между узлами или на контрольной точке."}
	if garage_level("WORKSHOP") < 1:
		return {"valid": false, "scrap": 0, "data": 0, "error": "Разбор груза требует WORKSHOP уровня 1."}
	var item: Dictionary = {}
	for candidate: Dictionary in state.run.unsecured_cargo:
		if str(candidate.get("itemId", "")) == item_id:
			item = candidate
			break
	if item.is_empty():
		return {"valid": false, "scrap": 0, "data": 0, "error": "Предмет отсутствует в незакреплённом грузе."}
	for equipped_id: Variant in state.run.equipment.values():
		if str(equipped_id) == item_id:
			return {"valid": false, "scrap": 0, "data": 0, "error": "Сначала снимите предмет со слота рейда."}
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return {"valid": false, "scrap": 0, "data": 0, "error": str(loaded.get("error", "Каталог предметов недоступен."))}
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	if template.is_empty():
		return {"valid": false, "scrap": 0, "data": 0, "error": "Шаблон предмета отсутствует в каталоге."}
	var scale: float = CydleFormula.new().reward_scale(float(item.get("techLevel", 1)))
	var scrap: int = mini(ceili(3.0 * scale), floori(18.0 * scale * 0.6))
	var data: int = 1 if (template.get("tags", []) as Array).has("digital") else 0
	return {"valid": true, "itemId": item_id, "scrap": scrap, "data": data, "item": item.duplicate(true), "error": ""}

func dismantle_run_item(item_id: String) -> bool:
	var quote: Dictionary = run_item_dismantle_quote(item_id)
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Разбор груза недоступен."))
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var item: Dictionary = quote["item"].duplicate(true)
	for index: int in range(run_payload["unsecuredCargo"].size()):
		if str(run_payload["unsecuredCargo"][index].get("itemId", "")) == item_id:
			run_payload["unsecuredCargo"].remove_at(index)
			break
	var scrap: int = int(quote["scrap"])
	var data: int = int(quote["data"])
	var wallet: Dictionary = run_payload["runWallet"]
	wallet["SCRAP"] = float(wallet.get("SCRAP", 0.0)) + float(scrap)
	wallet["DATA"] = float(wallet.get("DATA", 0.0)) + float(data)
	var history: Array = payload["meta"].get("disassemblyHistory", []).duplicate(true)
	history.append({"itemId": item_id, "templateId": str(item.get("templateId", "")), "seed": str(item.get("rollSeed", "")), "reason": "RUN_MANUAL", "scrap": scrap, "data": data, "createdAt": int(Time.get_unix_time_from_system()), "undone": false})
	while history.size() > 100:
		history.pop_front()
	payload["meta"]["disassemblyHistory"] = history
	payload["meta"]["disassemblyUndo"] = {"item": item, "scrap": scrap, "data": data, "createdAt": int(Time.get_unix_time_from_system()), "source": "RUN", "runSeed": str(run_payload.get("seed", "")), "nodeId": str(run_payload.get("currentNodeId", ""))}
	run_payload["lastCommandId"] = "cargo:dismantle:%s:%s" % [str(run_payload.get("currentNodeId", "")), item_id]
	return _commit_payload(payload)

func loot_filter_settings() -> Dictionary:
	if state == null:
		return {"preset": "ALL", "minimumRarity": "COMMON", "itemType": "ANY", "slot": "ANY", "requiredTags": [], "minimumAffixTier": 1, "affixId": "", "compareBuild": false, "comparisonStat": "", "autoDismantle": false}
	return state.meta.loot_filter.duplicate(true)

func set_loot_filter_settings(settings: Dictionary) -> bool:
	if state == null or not _garage_action_allowed():
		last_error = "Фильтр добычи настраивается в гараже между выездами."
		return false
	var candidate: Dictionary = settings.duplicate(true)
	if not GameSaveSchema.new()._validate_loot_filter(candidate):
		last_error = "Параметры фильтра добычи не прошли проверку."
		return false
	var payload: Dictionary = state.to_payload()
	payload["meta"]["lootFilter"] = candidate
	return _commit_payload(payload)

func auto_dismantle_available() -> bool:
	if state == null:
		return false
	if garage_level("WORKSHOP") >= 3:
		return true
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return false
	var scanner_id: String = str(state.meta.equipment.get("SCANNER", ""))
	if scanner_id.is_empty():
		return false
	var item: Dictionary = _secured_inventory_item(scanner_id)
	if item.is_empty():
		return false
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	return (template.get("tags", []) as Array).has("scanner")

func _loot_item_matches_filter(item: Dictionary, meta_payload: Dictionary, run_payload: Dictionary = {}) -> bool:
	var filter: Dictionary = meta_payload.get("lootFilter", {})
	var preset: String = str(filter.get("preset", "ALL"))
	var rarity_order: Array[String] = ["COMMON", "MODIFIED", "RARE", "LEGENDARY", "UNIQUE"]
	var rarity: String = str(item.get("rarity", "COMMON"))
	if item.has("uniqueEffectIds") and not (item.get("uniqueEffectIds", []) as Array).is_empty():
		var known: bool = false
		for secured_value: Dictionary in meta_payload.get("inventory", []):
			if bool(secured_value.get("secured", false)) and str(secured_value.get("templateId", "")) == str(item.get("templateId", "")):
				known = true
				break
		if not known:
			return true
	if preset == "ALL":
		return true
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return true
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	var item_tags: Array = template.get("tags", [])
	var category: String = str(template.get("category", ""))
	var selected_type: String = str(filter.get("itemType", "ANY"))
	if selected_type != "ANY" and category != selected_type:
		return false
	var selected_slot: String = str(filter.get("slot", "ANY"))
	if selected_slot != "ANY":
		var slots_by_category: Dictionary = {
			"MAIN": ["MAIN"], "OFFHAND": ["OFFHAND"], "ARMOR": ["ARMOR"], "IMPLANT": ["IMP_1", "IMP_2", "IMP_3", "IMP_4", "IMP_5", "IMP_6"],
			"DRONE": ["DRONE_1", "DRONE_2"], "ENGINE": ["ENGINE"], "CHASSIS": ["CHASSIS"], "SCANNER": ["SCANNER"], "SERVICE": ["SERVICE"], "CARGO": ["CARGO"], "SUPPORT": ["SUPPORT"]
		}
		if not (slots_by_category.get(category, []) as Array).has(selected_slot):
			return false
	if preset == "RARE_PLUS":
		return rarity_order.find(rarity) >= rarity_order.find("RARE")
	var required_tags: Array = filter.get("requiredTags", [])
	if preset == "TAGS":
		for tag_value: Variant in required_tags:
			if item_tags.has(str(tag_value)):
				return true
		return false
	if rarity_order.find(rarity) < rarity_order.find(str(filter.get("minimumRarity", "COMMON"))):
		return false
	if not required_tags.is_empty():
		var has_required_tag: bool = false
		for tag_value: Variant in required_tags:
			if item_tags.has(str(tag_value)):
				has_required_tag = true
				break
		if not has_required_tag:
			return false
	var affix_id: String = str(filter.get("affixId", ""))
	var min_tier: int = int(filter.get("minimumAffixTier", 1))
	var matching_affix: bool = affix_id.is_empty() and min_tier <= 1
	for affix_value: Dictionary in item.get("affixes", []):
		if int(affix_value.get("tier", 1)) >= min_tier and (affix_id.is_empty() or str(affix_value.get("affixId", "")) == affix_id):
			matching_affix = true
			break
	if not matching_affix:
		return false
	if bool(filter.get("compareBuild", false)):
		return _loot_item_improves_build(item, str(filter.get("comparisonStat", "")), str(filter.get("slot", "ANY")), run_payload)
	return true

func _loot_item_improves_build(item: Dictionary, stat_id: String, requested_slot: String, run_payload: Dictionary) -> bool:
	var stats: StatMath = StatMath.new()
	if not stats.stat_ids().has(stat_id):
		return false
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return false
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	var slots_by_category: Dictionary = {
		"MAIN": ["MAIN"], "OFFHAND": ["OFFHAND"], "ARMOR": ["ARMOR"], "IMPLANT": ["IMP_1", "IMP_2", "IMP_3", "IMP_4", "IMP_5", "IMP_6"],
		"DRONE": ["DRONE_1", "DRONE_2"], "ENGINE": ["ENGINE"], "CHASSIS": ["CHASSIS"], "SCANNER": ["SCANNER"], "SERVICE": ["SERVICE"], "CARGO": ["CARGO"], "SUPPORT": ["SUPPORT"]
	}
	var candidates: Array = slots_by_category.get(str(template.get("category", "")), [])
	if requested_slot != "ANY":
		if not candidates.has(requested_slot): return false
		candidates = [requested_slot]
	var base_input: Dictionary = _build_input(state)
	if not run_payload.is_empty():
		var current_equipment: Dictionary = {}
		var items_by_id: Dictionary = {}
		for owned_item: Dictionary in state.meta.inventory:
			items_by_id[str(owned_item.get("itemId", ""))] = owned_item
		for cargo_item: Dictionary in run_payload.get("unsecuredCargo", []):
			items_by_id[str(cargo_item.get("itemId", ""))] = cargo_item
		for slot_value: Variant in run_payload.get("equipment", {}).keys():
			var raw: Dictionary = items_by_id.get(str(run_payload["equipment"][slot_value]), {})
			if raw.is_empty(): continue
			var instance: ItemInstance = ItemInstance.new()
			if instance.instantiate_from_dictionary(raw): current_equipment[str(slot_value)] = instance
		base_input["equipment"] = current_equipment
	var current_result: Dictionary = BuildResolver.new().resolve_build(base_input)
	if not bool(current_result.get("valid", false)):
		return false
	var current_value: float = float(current_result.get("stats", {}).get(stat_id, 0.0))
	var candidate_item: ItemInstance = ItemInstance.new()
	if not candidate_item.instantiate_from_dictionary(item):
		return false
	for slot: String in candidates:
		var candidate_input: Dictionary = base_input.duplicate(true)
		var candidate_equipment: Dictionary = candidate_input.get("equipment", {}).duplicate(true)
		candidate_equipment[slot] = candidate_item
		candidate_input["equipment"] = candidate_equipment
		var candidate_result: Dictionary = BuildResolver.new().resolve_build(candidate_input)
		if bool(candidate_result.get("valid", false)) and float(candidate_result.get("stats", {}).get(stat_id, 0.0)) > current_value + 0.000001:
			return true
	return false

func _receive_run_item(payload: Dictionary, item_value: Dictionary, reason: String = "LOOT") -> Dictionary:
	var run_payload: Dictionary = payload.get("run", {})
	var meta_payload: Dictionary = payload.get("meta", {})
	if run_payload.is_empty() or item_value.is_empty():
		return {"accepted": false, "salvaged": false, "discarded": true}
	var item: Dictionary = item_value.duplicate(true)
	item["secured"] = false
	if _loot_item_matches_filter(item, meta_payload, run_payload):
		if _cargo_fits(run_payload, item):
			run_payload["unsecuredCargo"].append(item)
			return {"accepted": true, "salvaged": false, "discarded": false}
		return {"accepted": false, "salvaged": false, "discarded": true, "reason": "CARGO_FULL"}
	var filter: Dictionary = meta_payload.get("lootFilter", {})
	if not bool(filter.get("autoDismantle", false)) or not auto_dismantle_available():
		return {"accepted": false, "salvaged": false, "discarded": true, "reason": "FILTERED"}
	var loaded: Dictionary = _item_catalog.load_catalog()
	if not bool(loaded.get("ok", false)):
		return {"accepted": false, "salvaged": false, "discarded": true, "reason": "CATALOG_ERROR"}
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	var scale: float = CydleFormula.new().reward_scale(float(item.get("techLevel", 1)))
	var scrap_cap: int = floori(18.0 * scale * 0.6)
	var scrap_gain: int = mini(ceili(3.0 * scale), scrap_cap)
	var data_gain: int = 1 if (template.get("tags", []) as Array).has("digital") else 0
	var wallet: Dictionary = run_payload.get("runWallet", {})
	wallet["SCRAP"] = float(wallet.get("SCRAP", 0.0)) + float(scrap_gain)
	wallet["DATA"] = float(wallet.get("DATA", 0.0)) + float(data_gain)
	run_payload["runWallet"] = wallet
	var history: Array = meta_payload.get("disassemblyHistory", []).duplicate(true)
	history.append({"itemId": str(item.get("itemId", "")), "templateId": str(item.get("templateId", "")), "seed": str(item.get("rollSeed", "")), "reason": "AUTO_FILTER:%s" % reason, "scrap": scrap_gain, "data": data_gain, "createdAt": int(Time.get_unix_time_from_system()), "undone": false})
	while history.size() > 100:
		history.pop_front()
	meta_payload["disassemblyHistory"] = history
	meta_payload["disassemblyUndo"] = {"item": item, "scrap": scrap_gain, "data": data_gain, "createdAt": int(Time.get_unix_time_from_system()), "source": "RUN", "runSeed": str(run_payload.get("seed", "")), "nodeId": str(run_payload.get("currentNodeId", ""))}
	return {"accepted": false, "salvaged": true, "discarded": false, "scrap": scrap_gain, "data": data_gain}

func base_item_craft_quote(template_id: String, tech_level: int) -> Dictionary:
	if not _garage_action_allowed():
		return {"valid": false, "affordable": false, "error": "Изготовление доступно только в гараже между выездами."}
	if not _item_catalog_loaded():
		return {"valid": false, "affordable": false, "error": last_error}
	var template: Dictionary = _item_catalog.get_template(template_id)
	if template.is_empty() or not bool(template.get("craftable", false)) or template.has("uniqueEffectId") or str(template.get("category", "")) in ["MATERIAL", "SERVICE"]:
		return {"valid": false, "affordable": false, "error": "Этот шаблон нельзя изготовить как базовое снаряжение."}
	if not _has_item_blueprint(template_id):
		return {"valid": false, "affordable": false, "error": "Нужна постоянная схема %s." % template_id}
	var max_tech: int = maxi(4, state.meta.unlocked_forpost)
	if tech_level < 1 or tech_level > max_tech:
		return {"valid": false, "affordable": false, "error": "TechLevel должен быть от T1 до T%d, открытого гаражу." % max_tech}
	var scale: float = CydleFormula.new().reward_scale(float(tech_level))
	var scrap_cost: int = ceili(18.0 * scale)
	var data_cost: int = ceili(10.0 * scale)
	var scrap_available: float = state.meta.protected_bank.scrap
	var data_available: float = state.meta.protected_bank.data
	var affordable: bool = scrap_available >= scrap_cost and data_available >= data_cost
	var reason: String = ""
	if scrap_available < scrap_cost:
		reason = "Нужно %d SCRAP" % scrap_cost
	elif data_available < data_cost:
		reason = "Нужно %d DATA" % data_cost
	return {"valid": true, "affordable": affordable, "error": reason, "templateId": template_id, "techLevel": tech_level, "rarity": "COMMON", "scrap": scrap_cost, "data": data_cost, "blueprint": "quest-unlock:schematic:%s" % template_id}

func craft_base_item(template_id: String, tech_level: int) -> bool:
	var quote: Dictionary = base_item_craft_quote(template_id, tech_level)
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Рецепт недоступен."))
		return false
	var rng: DeterministicRng = DeterministicRng.new()
	var grant_id: String = "craft:%s:%d:%s:T%d" % [state.save_id, state.revision, template_id, tech_level]
	rng.seed(grant_id, state.revision)
	var created: Dictionary = ItemFactory.new().create_item(rng, _item_catalog, {"templateId": template_id, "techLevel": tech_level, "rarity": "COMMON", "secured": true, "originGrantId": grant_id, "origin": "craft", "acquiredAt": Time.get_unix_time_from_system()})
	if not bool(created.get("ok", false)):
		last_error = str(created.get("error", "Предмет не удалось изготовить."))
		return false
	var item: Dictionary = (created["item"] as ItemInstance).to_dictionary()
	var payload: Dictionary = state.to_payload()
	if _inventory_has(payload["meta"]["inventory"], str(item.get("itemId", ""))):
		last_error = "Повторный ID изготовления уже использован."
		return false
	payload["meta"]["inventory"].append(item)
	payload["meta"]["protectedBank"]["SCRAP"] = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0)) - float(quote["scrap"])
	payload["meta"]["protectedBank"]["DATA"] = float(payload["meta"]["protectedBank"].get("DATA", 0.0)) - float(quote["data"])
	return _commit_payload(payload)

func _has_item_blueprint(template_id: String) -> bool:
	if state == null:
		return false
	for flag_value: Variant in state.meta.campaign_flags:
		var flag: String = str(flag_value)
		if flag == "quest-unlock:schematic:%s" % template_id or flag == "item-blueprint:%s" % template_id or flag == "contract-blueprint:%s" % template_id:
			return true
	return false

func sell_item(item_id: String) -> bool:
	return _dispose_secured_item(item_id, "SELL")

func dismantle_item(item_id: String) -> bool:
	return _dispose_secured_item(item_id, "DISMANTLE")

func can_undo_last_dismantle() -> bool:
	if state == null or state.meta.disassembly_undo.is_empty():
		return false
	var source: String = str(state.meta.disassembly_undo.get("source", "SECURED"))
	if source == "RUN":
		if state.run == null or not ["ROUTE", "CHECKPOINT"].has(state.run.phase) or str(state.meta.disassembly_undo.get("runSeed", "")) != state.run.seed or str(state.meta.disassembly_undo.get("nodeId", "")) != state.run.current_node_id:
			return false
	else:
		if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
			if state.run.phase != "ROUTE" or not state.run.visited_node_ids.is_empty():
				return false
	var undo_item: Dictionary = state.meta.disassembly_undo.get("item", {})
	if undo_item.is_empty():
		return false
	if source == "RUN":
		for cargo_item: Dictionary in state.run.unsecured_cargo:
			if str(cargo_item.get("itemId", "")) == str(undo_item.get("itemId", "")):
				return false
		return float(state.run.wallet.scrap) >= float(state.meta.disassembly_undo.get("scrap", 0.0)) and float(state.run.wallet.data) >= float(state.meta.disassembly_undo.get("data", 0.0))
	return _secured_inventory_item(str(undo_item.get("itemId", ""))).is_empty()

func undo_last_dismantle() -> bool:
	if not can_undo_last_dismantle():
		last_error = "Отмена разбора доступна до входа в следующий дорожный узел."
		return false
	var payload: Dictionary = state.to_payload()
	var undo: Dictionary = payload["meta"].get("disassemblyUndo", {}).duplicate(true)
	var item: Dictionary = undo.get("item", {}).duplicate(true)
	var source: String = str(undo.get("source", "SECURED"))
	if item.is_empty() or (source == "SECURED" and _inventory_has(payload["meta"]["inventory"], str(item.get("itemId", "")))):
		last_error = "Предмет разбора уже присутствует в профиле."
		return false
	var scrap: float = float(undo.get("scrap", 0.0))
	var data: float = float(undo.get("data", 0.0))
	if source == "RUN":
		var run_payload: Dictionary = payload["run"]
		var wallet: Dictionary = run_payload["runWallet"]
		if float(wallet.get("SCRAP", 0.0)) < scrap or float(wallet.get("DATA", 0.0)) < data or not _cargo_fits(run_payload, item):
			last_error = "Груз или незакреплённые ресурсы изменились; отмена невозможна без потери предмета."
			return false
		wallet["SCRAP"] = float(wallet.get("SCRAP", 0.0)) - scrap
		wallet["DATA"] = float(wallet.get("DATA", 0.0)) - data
		run_payload["unsecuredCargo"].append(item)
	else:
		var bank: Dictionary = payload["meta"]["protectedBank"]
		if float(bank.get("SCRAP", 0.0)) < scrap or float(bank.get("DATA", 0.0)) < data:
			last_error = "Ресурсы разбора уже потрачены; отмена не может создать отрицательный баланс."
			return false
		bank["SCRAP"] = float(bank.get("SCRAP", 0.0)) - scrap
		bank["DATA"] = float(bank.get("DATA", 0.0)) - data
		payload["meta"]["inventory"].append(item)
		payload["meta"]["protectedBank"] = bank
	var history: Array = payload["meta"].get("disassemblyHistory", [])
	for index: int in range(history.size() - 1, -1, -1):
		if str(history[index].get("itemId", "")) == str(item.get("itemId", "")) and not bool(history[index].get("undone", false)):
			history[index]["undone"] = true
			break
	payload["meta"]["disassemblyHistory"] = history
	payload["meta"].erase("disassemblyUndo")
	return _commit_payload(payload)

func _dispose_secured_item(item_id: String, method: String) -> bool:
	var quote: Dictionary = item_disposal_quote(item_id, method)
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Операция с предметом недоступна."))
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	var item_found: bool = false
	var disposed_item: Dictionary = {}
	for index: int in range(inventory.size()):
		var item: Dictionary = inventory[index]
		if str(item.get("itemId", "")) == item_id and bool(item.get("secured", false)):
			disposed_item = item.duplicate(true)
			inventory.remove_at(index)
			item_found = true
			break
	if not item_found:
		last_error = "Предмет уже потрачен или отсутствует в профиле."
		return false
	payload["meta"]["inventory"] = inventory
	if method == "DISMANTLE":
		var history: Array = payload["meta"].get("disassemblyHistory", [])
		history.append({"itemId": item_id, "templateId": str(disposed_item.get("templateId", "")), "seed": str(disposed_item.get("rollSeed", "")), "reason": "MANUAL", "scrap": int(quote.get("scrap", 0)), "data": int(quote.get("data", 0)), "createdAt": int(Time.get_unix_time_from_system()), "undone": false})
		while history.size() > 100:
			history.pop_front()
		payload["meta"]["disassemblyHistory"] = history
		payload["meta"]["disassemblyUndo"] = {"item": disposed_item, "scrap": float(quote.get("scrap", 0)), "data": float(quote.get("data", 0)), "createdAt": int(Time.get_unix_time_from_system())}
	var currency: String = "CREDITS" if method == "SELL" else "SCRAP"
	payload["meta"]["protectedBank"][currency] = float(payload["meta"]["protectedBank"].get(currency, 0.0)) + float(quote.get("credits" if method == "SELL" else "scrap", 0))
	if method == "DISMANTLE":
		payload["meta"]["protectedBank"]["DATA"] = float(payload["meta"]["protectedBank"].get("DATA", 0.0)) + float(quote.get("data", 0))
	return _commit_payload(payload)

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

func affix_replacement_options(item_id: String, affix_index: int = -1) -> Dictionary:
	var required_tr: float = 10.0 if affix_index < 0 else 8.0
	if not _garage_action_allowed():
		return {"valid": false, "error": "Крафт доступен только в гараже между выездами."}
	if not _item_catalog_loaded():
		return {"valid": false, "error": last_error}
	var item: Dictionary = _secured_inventory_item(item_id)
	if item.is_empty():
		return {"valid": false, "error": "Предмет отсутствует в постоянном складе."}
	if str(item.get("rarity", "")) == "UNIQUE":
		return {"valid": false, "error": "Уникальный предмет нельзя произвольно редактировать."}
	var affixes: Array = item.get("affixes", [])
	var adding: bool = affix_index < 0
	if not adding and (affix_index >= affixes.size()):
		return {"valid": false, "error": "Выбранный слот аффикса не существует."}
	if adding:
		var range_value: Array = _item_catalog.get_rules().get("rarityAffixCount", {}).get(str(item.get("rarity", "")), [])
		if range_value.size() != 2 or affixes.size() >= int(range_value[1]):
			return {"valid": false, "error": "У предмета нет свободного аффиксного слота."}
	if float(item.get("tr", 0.0)) < required_tr:
		return {"valid": false, "error": "Операция требует %d TR; у предмета %d." % [int(required_tr), int(item.get("tr", 0.0))]}
	var tech_level: int = int(item.get("techLevel", 1))
	var scale: float = CydleFormula.new().reward_scale(float(tech_level))
	var scrap_cost: int = ceili((20.0 if adding else 0.0) * scale)
	var data_cost: int = ceili((10.0 if adding else 12.0) * scale)
	var bank: Variant = state.meta.protected_bank
	var template: Dictionary = _item_catalog.get_template(str(item.get("templateId", "")))
	if template.is_empty():
		return {"valid": false, "error": "Шаблон предмета отсутствует в каталоге."}
	var used_ids: Dictionary = {}
	var used_groups: Dictionary = {}
	for index: int in range(affixes.size()):
		if not adding and index == affix_index:
			continue
		var existing: Dictionary = affixes[index]
		var existing_id: String = str(existing.get("affixId", ""))
		used_ids[existing_id] = true
		var existing_definition: Dictionary = _item_catalog.get_affix(existing_id)
		if not existing_definition.is_empty():
			used_groups[str(existing_definition.get("group", ""))] = true
	var options: Array[Dictionary] = []
	for definition: Dictionary in _item_catalog.get_rules().get("affixes", []):
		var affix_id: String = str(definition.get("id", ""))
		var group: String = str(definition.get("group", ""))
		if affix_id.is_empty() or used_ids.has(affix_id) or used_groups.has(group):
			continue
		if not (definition.get("slots", []) as Array).has(str(template.get("category", ""))):
			continue
		options.append({"id": affix_id, "name": str(definition.get("name", affix_id)), "group": group})
	return {"valid": true, "affordable": int(bank.scrap) >= scrap_cost and int(bank.data) >= data_cost, "error": "" if int(bank.scrap) >= scrap_cost and int(bank.data) >= data_cost else "Недостаточно материалов.", "options": options, "scrap": scrap_cost, "data": data_cost, "tr": int(required_tr), "affixIndex": affix_index, "adding": adding}

func replace_item_affix(item_id: String, affix_index: int, new_affix_id: String) -> bool:
	return _craft_item_affix(item_id, affix_index, new_affix_id, false)

func add_item_affix(item_id: String, new_affix_id: String) -> bool:
	return _craft_item_affix(item_id, -1, new_affix_id, true)

func _craft_item_affix(item_id: String, affix_index: int, new_affix_id: String, adding: bool) -> bool:
	var quote: Dictionary = affix_replacement_options(item_id, -1 if adding else affix_index)
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Крафт недоступен."))
		return false
	if not bool(quote.get("affordable", false)):
		last_error = str(quote.get("error", "Недостаточно материалов."))
		return false
	var allowed: bool = false
	for option: Dictionary in quote.get("options", []):
		if str(option.get("id", "")) == new_affix_id:
			allowed = true
			break
	if not allowed:
		last_error = "Аффикс несовместим со слотом, предметом или уже установленной группой."
		return false
	var payload: Dictionary = state.to_payload()
	var inventory: Array = payload["meta"]["inventory"]
	for index: int in range(inventory.size()):
		var item: Dictionary = inventory[index]
		if str(item.get("itemId", "")) != item_id or not bool(item.get("secured", false)):
			continue
		var definition: Dictionary = _item_catalog.get_affix(new_affix_id)
		var tiers: Array = definition.get("tiers", [])
		var tier: int = _affix_tier_for_tech(int(item.get("techLevel", 1)))
		if tiers.size() < tier:
			last_error = "У аффикса нет значения для доступного TechLevel."
			return false
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed("affix:%s:%s:%d:%d:%s" % [state.save_id, item_id, state.revision, affix_index, new_affix_id], state.revision)
		var roll: Dictionary = _roll_affix(definition, tier, rng)
		if roll.is_empty():
			last_error = "Не удалось создать ролл нового аффикса."
			return false
		var affixes: Array = item.get("affixes", []).duplicate(true)
		if adding:
			affixes.append(roll)
		else:
			affixes[affix_index] = roll
		item["affixes"] = affixes
		item["tr"] = float(item.get("tr", 0.0)) - float(quote["tr"])
		item["rollSeed"] = "%s:%d" % [rng.stream, rng.calls]
		inventory[index] = item
		payload["meta"]["inventory"] = inventory
		payload["meta"]["protectedBank"]["SCRAP"] = float(payload["meta"]["protectedBank"].get("SCRAP", 0.0)) - float(quote["scrap"])
		payload["meta"]["protectedBank"]["DATA"] = float(payload["meta"]["protectedBank"].get("DATA", 0.0)) - float(quote["data"])
		var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
		if not bool(parsed.get("ok", false)):
			last_error = str(parsed.get("error", "Изменение аффикса не прошло проверку сохранения."))
			return false
		var candidate: GameSaveState = parsed["state"] as GameSaveState
		var resolved: Dictionary = BuildResolver.new().resolve_build(_build_input(candidate))
		if not bool(resolved.get("valid", false)):
			last_error = "Изменение аффикса отклонено BuildResolver: %s" % str(resolved.get("issues", []))
			return false
		return _commit(candidate)
	last_error = "Предмет не найден в постоянном складе."
	return false

func _item_catalog_loaded() -> bool:
	if _item_catalog_ready:
		return true
	var loaded: Dictionary = _item_catalog.load_catalog()
	if bool(loaded.get("ok", false)):
		_item_catalog_ready = true
		return true
	last_error = str(loaded.get("error", "Каталог предметов недоступен."))
	return false

func _secured_inventory_item(item_id: String) -> Dictionary:
	if state == null:
		return {}
	for item: Dictionary in state.meta.inventory:
		if str(item.get("itemId", "")) == item_id and bool(item.get("secured", false)):
			return item.duplicate(true)
	return {}

func _affix_tier_for_tech(tech_level: int) -> int:
	if tech_level <= 4:
		return 1
	if tech_level <= 8:
		return 2
	if tech_level <= 12:
		return 3
	return 4

func _roll_affix(definition: Dictionary, tier: int, rng: DeterministicRng) -> Dictionary:
	var tiers: Array = definition.get("tiers", [])
	if tier < 1 or tier > tiers.size():
		return {}
	var center: float = float(tiers[tier - 1])
	var raw: float = 1.0 if bool(definition.get("fixed", false)) else rng.range_float(0.8, 1.2)
	var integer_value: bool = bool(definition.get("integer", false))
	var value: float = maxf(1.0, roundf(center * raw)) if integer_value else floorf(center * raw * 100.0 + 0.5) / 100.0
	return {"affixId": str(definition.get("id", "")), "tier": tier, "value": value, "rawRoll": floorf(raw * 10000.0 + 0.5) / 10000.0, "tierBoosted": false, "center": center, "min": maxf(1.0, roundf(center * 0.8)) if integer_value else floorf(center * 0.8 * 100.0 + 0.5) / 100.0, "max": roundf(center * 1.2) if integer_value else floorf(center * 1.2 * 100.0 + 0.5) / 100.0}

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

func active_tactic() -> Dictionary:
	if state == null:
		return {}
	for profile: Dictionary in state.meta.tactics:
		if str(profile.get("id", "")) == state.meta.active_tactic_id:
			return profile.duplicate(true)
	return {}

func select_tactic(profile_id: String) -> bool:
	if not _tactic_edit_allowed():
		return false
	for profile: Dictionary in state.meta.tactics:
		if str(profile.get("id", "")) == profile_id:
			var payload: Dictionary = state.to_payload()
			payload["meta"]["activeTacticId"] = profile_id
			return _commit_tactic_payload(payload)
	last_error = "Профиль тактики не найден."
	return false

func duplicate_active_tactic() -> bool:
	if not _tactic_edit_allowed():
		return false
	if garage_level("SERVER") < 2:
		last_error = "Дополнительные профили требуют SERVER уровня 2."
		return false
	if state.meta.tactics.size() >= 5:
		last_error = "SERVER хранит не более пяти профилей тактики."
		return false
	var payload: Dictionary = state.to_payload()
	var profiles: Array = payload["meta"]["tactics"]
	var copy: Dictionary = active_tactic()
	var suffix: int = 1
	var new_id: String = "TACTIC_%02d" % suffix
	while _profile_exists(profiles, new_id):
		suffix += 1
		new_id = "TACTIC_%02d" % suffix
	copy["id"] = new_id
	copy["name"] = "Тактика %d" % suffix
	for rule_index: int in range(copy.get("rules", []).size()):
		copy["rules"][rule_index]["id"] = "%s:copy:%d" % [str(copy["rules"][rule_index].get("id", "rule")), suffix]
	profiles.append(copy)
	payload["meta"]["tactics"] = profiles
	payload["meta"]["activeTacticId"] = new_id
	return _commit_tactic_payload(payload)

func add_tactic_rule(skill_id: String) -> bool:
	if not _tactic_edit_allowed():
		return false
	if skill_id != "AUTO" and not state.meta.skill_ids.has(skill_id):
		last_error = "Тактика может использовать только экипированное умение."
		return false
	var payload: Dictionary = state.to_payload()
	var profile: Dictionary = _payload_tactic(payload)
	if profile.is_empty():
		last_error = "Активный профиль тактики не найден."
		return false
	var rules: Array = profile.get("rules", [])
	if rules.size() >= 12:
		last_error = "Тактильная программа ограничена двенадцатью правилами."
		return false
	var next_priority: int = 1
	var rule_id: String = "USER_%02d" % rules.size()
	while _rule_exists(rules, rule_id):
		next_priority += 1
		rule_id = "USER_%02d" % (rules.size() + next_priority)
	var lowest_priority: int = 1
	for rule_value: Variant in rules:
		if rule_value is Dictionary:
			lowest_priority = mini(lowest_priority, int(rule_value.get("priority", 0)) - 1)
	rules.append({"id": rule_id, "priority": lowest_priority, "enabled": true, "skillId": skill_id, "target": "self" if skill_id in ["SK_SHIELD", "SK_GUARD", "SK_VENT", "SK_HEAL"] else "nearest", "conditions": [{"kind": "always"}], "logic": "AND", "note": "Пользовательское правило"})
	profile["rules"] = rules
	return _commit_tactic_profile(payload, profile)

func set_tactic_rule_enabled(rule_id: String, enabled: bool) -> bool:
	return _update_tactic_rule(rule_id, func(rule: Dictionary) -> void: rule["enabled"] = enabled)

func set_tactic_rule_skill(rule_id: String, skill_id: String) -> bool:
	if skill_id != "AUTO" and (state == null or not state.meta.skill_ids.has(skill_id)):
		last_error = "Тактика может использовать только экипированное умение."
		return false
	return _update_tactic_rule(rule_id, func(rule: Dictionary) -> void: rule["skillId"] = skill_id)

func set_tactic_rule_target(rule_id: String, target: String) -> bool:
	if not ["self", "nearest", "lowestHPPercent", "imminentCast", "boss", "healer", "infected", "marked", "otherEnemy", "secondary"].has(target):
		last_error = "Неизвестный селектор цели."
		return false
	return _update_tactic_rule(rule_id, func(rule: Dictionary) -> void: rule["target"] = target)

func set_tactic_rule_condition(rule_id: String, condition: Dictionary) -> bool:
	var kind: String = str(condition.get("kind", ""))
	var simple_kinds: Array[String] = ["always", "hpBelow", "hpAbove", "shieldBelow", "energyAtLeast", "energyBelow", "heatAtLeast", "heatBelow", "heatLocked", "enemiesAtLeast", "enemiesAtMost", "enemyCasting", "droneAlive", "timeAtLeast"]
	if not simple_kinds.has(kind):
		last_error = "Этот тип условия пока нельзя редактировать в интерфейсе."
		return false
	if ["hpBelow", "hpAbove", "shieldBelow"].has(kind):
		var fraction: Variant = condition.get("value", 0.0)
		if not (fraction is int or fraction is float) or not is_finite(float(fraction)) or float(fraction) < 0.0 or float(fraction) > 1.0:
			last_error = "Порог доли должен находиться в диапазоне 0–1."
			return false
	elif ["energyAtLeast", "energyBelow", "heatAtLeast", "heatBelow", "enemiesAtLeast", "enemiesAtMost", "droneAlive", "timeAtLeast"].has(kind):
		var number: Variant = condition.get("value", 0.0)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0.0:
			last_error = "Порог условия должен быть конечным неотрицательным числом."
			return false
	return _update_tactic_rule(rule_id, func(rule: Dictionary) -> void:
		rule["conditions"] = [condition.duplicate(true)]
		rule["logic"] = "AND"
	)

func move_tactic_rule(rule_id: String, direction: int) -> bool:
	if direction != -1 and direction != 1:
		last_error = "Перемещение правила требует направления −1 или 1."
		return false
	if not _tactic_edit_allowed():
		return false
	var payload: Dictionary = state.to_payload()
	var profile: Dictionary = _payload_tactic(payload)
	var rules: Array = profile.get("rules", [])
	var index: int = -1
	for rule_index: int in range(rules.size()):
		if str(rules[rule_index].get("id", "")) == rule_id:
			index = rule_index
			break
	if index < 0:
		last_error = "Правило тактики не найдено."
		return false
	var ordered: Array = rules.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	var ordered_index: int = -1
	for rule_index: int in range(ordered.size()):
		if str(ordered[rule_index].get("id", "")) == rule_id:
			ordered_index = rule_index
			break
	var neighbor: int = ordered_index + direction
	if neighbor < 0 or neighbor >= ordered.size():
		last_error = "Правило уже находится на этом краю списка."
		return false
	var current_priority: int = int(ordered[ordered_index].get("priority", 0))
	ordered[ordered_index]["priority"] = int(ordered[neighbor].get("priority", 0))
	ordered[neighbor]["priority"] = current_priority
	profile["rules"] = rules
	return _commit_tactic_profile(payload, profile)

func _update_tactic_rule(rule_id: String, update: Callable) -> bool:
	if not _tactic_edit_allowed():
		return false
	var payload: Dictionary = state.to_payload()
	var profile: Dictionary = _payload_tactic(payload)
	for rule_value: Variant in profile.get("rules", []):
		if rule_value is Dictionary and str(rule_value.get("id", "")) == rule_id:
			update.call(rule_value)
			return _commit_tactic_profile(payload, profile)
	last_error = "Правило тактики не найдено."
	return false

func _tactic_edit_allowed() -> bool:
	if state == null or not _garage_action_allowed():
		last_error = "Тактику можно менять только в гараже между выездами."
		return false
	if garage_level("SERVER") < 1:
		last_error = "Редактор тактики требует SERVER уровня 1."
		return false
	return true

func _payload_tactic(payload: Dictionary) -> Dictionary:
	var meta: Dictionary = payload.get("meta", {})
	for profile: Dictionary in meta.get("tactics", []):
		if str(profile.get("id", "")) == str(meta.get("activeTacticId", "")):
			return profile
	return {}

func _commit_tactic_profile(payload: Dictionary, profile: Dictionary) -> bool:
	var meta: Dictionary = payload["meta"]
	for index: int in range(meta["tactics"].size()):
		if str(meta["tactics"][index].get("id", "")) == str(profile.get("id", "")):
			meta["tactics"][index] = profile
			return _commit_tactic_payload(payload)
	last_error = "Профиль тактики не найден."
	return false

func _commit_tactic_payload(payload: Dictionary) -> bool:
	var parsed: Dictionary = GameSaveState.new().parse_payload(payload)
	if not bool(parsed.get("ok", false)):
		last_error = str(parsed.get("error", "Тактильная программа не прошла проверку сохранения."))
		return false
	return _commit(parsed["state"] as GameSaveState)

func _profile_exists(profiles: Array, profile_id: String) -> bool:
	for profile_value: Variant in profiles:
		if profile_value is Dictionary and str(profile_value.get("id", "")) == profile_id:
			return true
	return false

func _rule_exists(rules: Array, rule_id: String) -> bool:
	for rule_value: Variant in rules:
		if rule_value is Dictionary and str(rule_value.get("id", "")) == rule_id:
			return true
	return false

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
	if state.run.depth == 12 and state.meta.campaign_flags.has("CAMPAIGN_COMPLETED") and not state.meta.campaign_flags.has("ENDING_SELECTED"):
		last_error = "Перед эвакуацией после финального босса выберите исход кампании."
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var meta: Dictionary = payload["meta"]
	run_payload.erase("autopilotEnabled")
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
	meta["equipment"] = run_payload["equipment"].duplicate(true)
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

func _field_secured_equipped_ids(field_equipment: Dictionary, inventory: Array) -> Array[String]:
	var secured_ids: Dictionary = {}
	for item: Dictionary in inventory:
		if bool(item.get("secured", false)):
			secured_ids[str(item.get("itemId", ""))] = true
	var result: Array[String] = []
	for value: Variant in field_equipment.values():
		var item_id: String = str(value)
		if secured_ids.has(item_id) and not result.has(item_id):
			result.append(item_id)
	return result

func _settled_field_equipment(field_equipment: Dictionary, inventory: Array, fallback_equipment: Dictionary) -> Dictionary:
	var owned_ids: Dictionary = {}
	for item: Dictionary in inventory:
		owned_ids[str(item.get("itemId", ""))] = true
	var result: Dictionary = {}
	var used_ids: Dictionary = {}
	for slot_value: Variant in field_equipment.keys():
		var slot: String = str(slot_value)
		var item_id: String = str(field_equipment[slot_value])
		if owned_ids.has(item_id) and not used_ids.has(item_id):
			result[slot] = item_id
			used_ids[item_id] = true
	for slot_value: Variant in fallback_equipment.keys():
		var slot: String = str(slot_value)
		var item_id: String = str(fallback_equipment[slot_value])
		if not result.has(slot) and owned_ids.has(item_id) and not used_ids.has(item_id):
			result[slot] = item_id
			used_ids[item_id] = true
	return result

func emergency_exit_quote() -> Dictionary:
	if not _emergency_exit_allowed():
		return {"valid": false, "towAffordable": false, "error": "Аварийный выход доступен на карте, когда топлива не хватает для любого перехода."}
	var scale: float = CydleFormula.new().reward_scale(float(state.run.depth))
	var tow_cost: int = ceili(30.0 * scale)
	var available_credits: float = float(state.run.wallet.credits) + float(state.meta.protected_bank.credits)
	return {
		"valid": true,
		"towCost": tow_cost,
		"towAffordable": available_credits >= float(tow_cost),
		"cargoItems": state.run.unsecured_cargo.size(),
		"wallet": state.run.wallet.to_dictionary(),
		"error": "",
	}

func call_evacuation_tow() -> bool:
	var quote: Dictionary = emergency_exit_quote()
	if not bool(quote.get("valid", false)):
		last_error = str(quote.get("error", "Тягач сейчас недоступен."))
		return false
	if not bool(quote.get("towAffordable", false)):
		last_error = "Для вызова тягача нужно %d CREDITS. Можно бросить выезд с потерей всего незакреплённого груза." % int(quote.get("towCost", 0))
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var meta: Dictionary = payload["meta"]
	var wallet: Dictionary = run_payload["runWallet"]
	var bank: Dictionary = meta["protectedBank"]
	var tow_cost: float = float(quote["towCost"])
	var run_credit_payment: float = minf(float(wallet.get("CREDITS", 0.0)), tow_cost)
	wallet["CREDITS"] = float(wallet.get("CREDITS", 0.0)) - run_credit_payment
	var protected_payment: float = tow_cost - run_credit_payment
	bank["CREDITS"] = float(bank.get("CREDITS", 0.0)) - protected_payment
	var rng: DeterministicRng = DeterministicRng.new()
	if not rng.restore(run_payload.get("lootRng", {})):
		last_error = "Состояние генератора добычи повреждено; тягач не вызван."
		return false
	var cargo: Array = run_payload.get("unsecuredCargo", []).duplicate(true)
	var dropped_item_id: String = ""
	var inventory: Array = meta["inventory"]
	if not cargo.is_empty():
		var dropped_index: int = rng.int_range(0, cargo.size() - 1)
		dropped_item_id = str(cargo[dropped_index].get("itemId", ""))
		cargo.remove_at(dropped_index)
		for item_value: Dictionary in cargo:
			var secured: Dictionary = item_value.duplicate(true)
			secured["secured"] = true
			secured["origin"] = "emergency-tow"
			if not _inventory_has(inventory, str(secured.get("itemId", ""))):
				inventory.append(secured)
	meta["inventory"] = inventory
	var lost_wallet: Dictionary = {}
	var banked_wallet: Dictionary = {}
	for currency: String in ["CREDITS", "SCRAP", "DATA"]:
		var amount: float = maxf(0.0, float(wallet.get(currency, 0.0)))
		var retained: float = floorf(amount * 0.7)
		lost_wallet[currency] = amount - retained
		banked_wallet[currency] = retained
		bank[currency] = float(bank.get(currency, 0.0)) + retained
	meta["equipment"] = _settled_field_equipment(run_payload.get("equipment", {}), inventory, meta.get("equipment", {}))
	run_payload["runWallet"] = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	run_payload["lootRng"] = rng.serialize()
	run_payload["unsecuredCargo"] = []
	run_payload["shippedCargo"] = []
	run_payload["temporaryMutationIds"] = []
	run_payload["combatResult"] = null
	run_payload["combatSnapshot"] = null
	run_payload["pendingCombatEffects"] = {"initialTempShield": 0.0, "extraHeat": 0.0}
	run_payload["equipment"] = meta["equipment"].duplicate(true)
	run_payload["phase"] = "TOWED"
	run_payload["lastCommandId"] = "emergency:tow:%s" % str(run_payload.get("seed", ""))
	if not _commit_payload(payload):
		return false
	last_emergency_report = {"type": "TOWED", "towCost": int(tow_cost), "droppedItemId": dropped_item_id, "cargoSecured": cargo.size(), "currencyLost": lost_wallet, "currencySecured": banked_wallet}
	_combat = null
	_active_node_type = ""
	_active_reward_modifiers = {}
	return true

func abandon_run() -> bool:
	if not _emergency_exit_allowed():
		last_error = "Выезд можно бросить только на карте, когда топлива не хватает для любого перехода."
		return false
	var payload: Dictionary = state.to_payload()
	var run_payload: Dictionary = payload["run"]
	var meta: Dictionary = payload["meta"]
	meta["equipment"] = _settled_field_equipment(run_payload.get("equipment", {}), meta["inventory"], meta.get("equipment", {}))
	var equipped_ids: Array[String] = _field_secured_equipped_ids(run_payload.get("equipment", {}), meta["inventory"])
	for index: int in range(meta["inventory"].size()):
		var item: Dictionary = meta["inventory"][index]
		if bool(item.get("secured", false)) and equipped_ids.has(str(item.get("itemId", ""))):
			item["durability"] = maxf(0.0, float(item.get("durability", 100.0)) - 10.0)
		meta["inventory"][index] = item
	run_payload["runWallet"] = {"CREDITS": 0.0, "SCRAP": 0.0, "DATA": 0.0}
	run_payload["unsecuredCargo"] = []
	run_payload["shippedCargo"] = []
	run_payload["temporaryMutationIds"] = []
	run_payload["combatResult"] = null
	run_payload["combatSnapshot"] = null
	run_payload["pendingCombatEffects"] = {"initialTempShield": 0.0, "extraHeat": 0.0}
	run_payload["equipment"] = meta["equipment"].duplicate(true)
	run_payload["phase"] = "ABANDONED"
	run_payload["lastCommandId"] = "emergency:abandon:%s" % str(run_payload.get("seed", ""))
	if not _commit_payload(payload):
		return false
	last_emergency_report = {"type": "ABANDONED", "currencyLost": true, "cargoLost": true, "equippedDurabilityLoss": 10.0}
	_combat = null
	_active_node_type = ""
	_active_reward_modifiers = {}
	return true

func _emergency_exit_allowed() -> bool:
	if state == null or state.run == null or state.run.phase != "ROUTE" or _combat != null:
		return false
	var available_fuel: float = float(state.run.resources.get("fuel", 0.0))
	for node: Dictionary in reachable_nodes():
		for edge: Dictionary in state.run.graph.get("edges", []):
			if str(edge.get("from", "")) == state.run.current_node_id and str(edge.get("to", "")) == str(node.get("id", "")) and available_fuel >= float(edge.get("fuelCost", 1)):
				return false
	return true

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
		"combatRulesVersion": _combat.combat_rules_version,
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
	if str(saved.get("combatRulesVersion", CombatState.LEGACY_RULES_VERSION)) != CombatSimulator.COMBAT_RULES_VERSION:
		last_error = "Версия сохранённого боя не поддерживается. Профиль сохранён; требуется совместимый движок."
		return false
	var serialized: Variant = saved.get("combatState")
	if not serialized is Dictionary:
		last_error = "В снимке отсутствует сериализованное состояние симулятора."
		return false
	var build: Dictionary = run_build_preview()
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
