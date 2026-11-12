class_name BuildResolver
extends RefCounted

const ATTRIBUTE_IDS: Array[String] = ["POW", "REF", "INT", "ENG", "SYN"]
const EQUIPMENT_SLOTS: Array[String] = ["MAIN", "OFFHAND", "ARMOR", "IMP_1", "IMP_2", "IMP_3", "IMP_4", "IMP_5", "IMP_6", "DRONE_1", "DRONE_2", "ENGINE", "CHASSIS", "SCANNER", "SERVICE", "CARGO", "SUPPORT"]
const SLOT_CATEGORY: Dictionary = {
	"MAIN": "MAIN", "OFFHAND": "OFFHAND", "ARMOR": "ARMOR",
	"IMP_1": "IMPLANT", "IMP_2": "IMPLANT", "IMP_3": "IMPLANT", "IMP_4": "IMPLANT", "IMP_5": "IMPLANT", "IMP_6": "IMPLANT",
	"DRONE_1": "DRONE", "DRONE_2": "DRONE", "ENGINE": "ENGINE", "CHASSIS": "CHASSIS", "SCANNER": "SCANNER", "SERVICE": "SERVICE", "CARGO": "CARGO", "SUPPORT": "SUPPORT",
}
const IMPLANT_SOCKET: Dictionary = {"IMP_1": "HEAD", "IMP_2": "CHEST", "IMP_3": "ARMS", "IMP_4": "UNIVERSAL", "IMP_5": "NEURAL", "IMP_6": "UNIVERSAL"}
const ATTRIBUTE_EFFECTS: Array[Dictionary] = [
	{"attribute": "POW", "stat": "kineticDamage", "op": "INCREASED", "perPoint": 2.0},
	{"attribute": "POW", "stat": "armorPen", "op": "FLAT", "perPoint": 0.5},
	{"attribute": "REF", "stat": "attackSpeed", "op": "INCREASED", "perPoint": 1.5},
	{"attribute": "REF", "stat": "evasion", "op": "FLAT", "perPoint": 1.5},
	{"attribute": "REF", "stat": "accuracy", "op": "FLAT", "perPoint": 0.3},
	{"attribute": "INT", "stat": "digitalDamage", "op": "INCREASED", "perPoint": 2.5},
	{"attribute": "INT", "stat": "energyDamage", "op": "INCREASED", "perPoint": 1.0},
	{"attribute": "INT", "stat": "digitalPenPercent", "op": "FLAT", "perPoint": 0.5},
	{"attribute": "ENG", "stat": "droneDamage", "op": "INCREASED", "perPoint": 2.5},
	{"attribute": "ENG", "stat": "droneHP", "op": "INCREASED", "perPoint": 2.0},
	{"attribute": "ENG", "stat": "repairPower", "op": "INCREASED", "perPoint": 1.0},
	{"attribute": "SYN", "stat": "neuralCapacity", "op": "FLAT", "perPoint": 2.0},
]

var _catalog: ItemCatalog = ItemCatalog.new()
var _build_catalog: BuildCatalog = BuildCatalog.new()
var _stats: StatMath = StatMath.new()
var _formula: CydleFormula = CydleFormula.new()
var _catalog_loaded: bool = false
var _catalog_error: String = ""
var _build_catalog_loaded: bool = false
var _build_catalog_error: String = ""

func resolve_build(input: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	if not _catalog_loaded:
		var catalog_result: Dictionary = _catalog.load_catalog()
		_catalog_loaded = true
		_catalog_error = str(catalog_result.get("error", "")) if not bool(catalog_result.get("ok", false)) else ""
	if not _catalog_error.is_empty():
		_add_issue(issues, "DATA_CATALOG", "Каталог предметов не загружен: %s" % _catalog_error)
		return _result(issues, {}, {}, {}, {}, [], [], [], [], [])
	if not _build_catalog_loaded:
		var build_catalog_result: Dictionary = _build_catalog.load_catalog()
		_build_catalog_loaded = true
		_build_catalog_error = str(build_catalog_result.get("error", "")) if not bool(build_catalog_result.get("ok", false)) else ""
	if not _build_catalog_error.is_empty():
		_add_issue(issues, "BUILD_CATALOG", "Каталог умений/пассивов не загружен: %s" % _build_catalog_error)
		return _result(issues, {}, {}, {}, {}, [], [], [], [], [])
	var equipment_input: Variant = input.get("equipment", {})
	var equipment: Dictionary = equipment_input.duplicate(true) if equipment_input is Dictionary else {}
	if not equipment_input is Dictionary:
		_add_issue(issues, "INVALID_EQUIPMENT", "equipment должен быть объектом.")
	for slot_value: Variant in equipment.keys():
		if not EQUIPMENT_SLOTS.has(str(slot_value)):
			_add_issue(issues, "INVALID_SLOT", "Неизвестный слот экипировки %s." % str(slot_value), str(slot_value))
	var attributes: Dictionary = {}
	var input_attributes: Dictionary = input.get("attributes", {}) if input.get("attributes", {}) is Dictionary else {}
	for attribute: String in ATTRIBUTE_IDS:
		attributes[attribute] = input_attributes.get(attribute, 5)
	_validate_attributes(input, attributes, issues)
	var skill_ids: Array[String] = _read_selection(input, "skillIds", issues)
	var passive_ids: Array[String] = _read_selection(input, "passiveIds", issues)
	var tree_node_ids: Array[String] = _read_selection(input, "treeNodeIds", issues)
	var mutation_ids: Array[String] = _read_selection(input, "mutationIds", issues)
	if skill_ids.size() > 3:
		_add_issue(issues, "SKILL_LIMIT", "Можно установить не более трёх активных умений.")
	if passive_ids.size() > 3:
		_add_issue(issues, "PASSIVE_LIMIT", "Можно установить не более трёх пассивных протоколов.")
	if mutation_ids.size() > 2:
		_add_issue(issues, "MUTATION_LIMIT", "Одновременно доступны не более двух мутаций.")
	var resolved_skills: Array[Dictionary] = []
	var resolved_passives: Array[Dictionary] = []
	var resolved_tree_nodes: Array[Dictionary] = []
	var resolved_mutations: Array[Dictionary] = []
	var tree_points_earned: Variant = input.get("treePointsEarned", 0)
	var safe_tree_points: int = int(tree_points_earned) if _is_integer(tree_points_earned) else 0
	if not _is_integer(tree_points_earned) or int(tree_points_earned) < 0:
		_add_issue(issues, "TREE_POINTS", "Полученные очки дерева должны быть целыми и неотрицательными.")
	if _is_integer(tree_points_earned) and int(tree_points_earned) > 60:
		_add_issue(issues, "TREE_POINTS_CAP", "Нельзя получить более 60 силовых очков дерева.")
	if tree_node_ids.size() > 60 or _is_integer(tree_points_earned) and tree_node_ids.size() > int(tree_points_earned):
		_add_issue(issues, "TREE_POINTS", "Распределено %d узлов при %s полученных очках." % [tree_node_ids.size(), str(tree_points_earned)])
	for skill_id: String in skill_ids:
		if not _build_catalog.skills.has(skill_id):
			_add_issue(issues, "UNKNOWN_SKILL", "Неизвестное умение %s." % skill_id, skill_id)
		else:
			resolved_skills.append(_build_catalog.skills[skill_id])
	for passive_id: String in passive_ids:
		if not _build_catalog.passives.has(passive_id):
			_add_issue(issues, "UNKNOWN_PASSIVE", "Неизвестный пассивный протокол %s." % passive_id, passive_id)
		else:
			resolved_passives.append(_build_catalog.passives[passive_id])
	var selected_tree_ids: Array[String] = []
	var unresolved_tree_ids: Dictionary = {}
	for tree_id: String in tree_node_ids:
		if not _build_catalog.tree_nodes.has(tree_id):
			_add_issue(issues, "UNKNOWN_TREE_NODE", "Неизвестный узел дерева %s." % tree_id, tree_id)
			unresolved_tree_ids[tree_id] = true
	var tree_progress: bool = true
	while tree_progress:
		tree_progress = false
		for tree_id: String in tree_node_ids:
			if selected_tree_ids.has(tree_id) or unresolved_tree_ids.has(tree_id):
				continue
			if _tree_lock_reason(tree_id, selected_tree_ids, safe_tree_points - selected_tree_ids.size()).is_empty():
				selected_tree_ids.append(tree_id)
				tree_progress = true
	for tree_id: String in tree_node_ids:
		if selected_tree_ids.has(tree_id) or unresolved_tree_ids.has(tree_id):
			continue
		var tree_reason: String = _tree_lock_reason(tree_id, selected_tree_ids, safe_tree_points - selected_tree_ids.size())
		var tree_node: Dictionary = _build_catalog.tree_nodes.get(tree_id, {})
		if bool(tree_node.get("keystone", false)) and _keystone_count(selected_tree_ids) >= 2:
			_add_issue(issues, "KEYSTONE_LIMIT", "%s: %s." % [tree_id, tree_reason if not tree_reason.is_empty() else "достигнут лимит двух keystone"], tree_id)
		else:
			_add_issue(issues, "TREE_LOCKED", "%s: %s." % [tree_id, tree_reason if not tree_reason.is_empty() else "не выполнены требования дерева"], tree_id)
	for tree_id: String in selected_tree_ids:
		resolved_tree_nodes.append(_build_catalog.tree_nodes[tree_id])
	for mutation_id: String in mutation_ids:
		if not _build_catalog.mutations.has(mutation_id):
			_add_issue(issues, "UNKNOWN_MUTATION", "Неизвестная мутация %s." % mutation_id, mutation_id)
		else:
			resolved_mutations.append(_build_catalog.mutations[mutation_id])
	var unlocked_implants: int = clampi(int(input.get("unlockedImplantSlots", 4)), 0, 6)
	var unlocked_drones: int = clampi(int(input.get("unlockedDroneSlots", 1)), 0, 2)
	var valid_templates: Dictionary = {}
	var seen_item_ids: Dictionary = {}
	var implant_cost: float = 0.0
	var main_weapon: Dictionary = {}
	var sidearm: Dictionary = {}
	var drones: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var trigger_effects: Array[Dictionary] = []
	var modifiers: Array[Dictionary] = []
	_add_attribute_modifiers(attributes, modifiers)
	var attribute_modifier_count: int = modifiers.size()
	for slot: String in EQUIPMENT_SLOTS:
		if not equipment.has(slot):
			continue
		var item: ItemInstance = _as_item_instance(equipment[slot])
		if item == null:
			_add_issue(issues, "INVALID_ITEM", "Слот %s содержит повреждённый экземпляр." % slot, slot)
			continue
		equipment[slot] = item
		var template: Dictionary = _catalog.get_template(item.template_id)
		if template.is_empty():
			_add_issue(issues, "UNKNOWN_ITEM", "Неизвестный шаблон предмета %s." % item.template_id, item.item_id)
			continue
		valid_templates[slot] = template
		if seen_item_ids.has(item.item_id):
			_add_issue(issues, "DUPLICATE_ITEM", "Предмет %s установлен более одного раза." % item.item_id, item.item_id)
		seen_item_ids[item.item_id] = true
		if not _slot_allows(slot, template):
			_add_issue(issues, "INVALID_SLOT", "%s нельзя установить в слот %s." % [str(template["name"]), slot], item.item_id)
		if slot.begins_with("IMP_") and int(slot.substr(4)) > unlocked_implants:
			_add_issue(issues, "LOCKED_SLOT", "Слот %s ещё не открыт." % slot, item.item_id)
		if slot.begins_with("DRONE_") and int(slot.substr(6)) > unlocked_drones:
			_add_issue(issues, "LOCKED_SLOT", "Слот %s ещё не открыт." % slot, item.item_id)
		if item.tech_level < 1:
			_add_issue(issues, "INVALID_TECH_LEVEL", "TechLevel должен быть целым числом не меньше 1.", item.item_id)
		if not is_finite(item.durability) or item.durability < 0.0 or item.durability > 100.0:
			_add_issue(issues, "INVALID_DURABILITY", "Износ должен находиться в диапазоне 0–100.", item.item_id)
		var expected_neural_cost: float = float(template.get("neuralCost", 0.0))
		if item.neural_cost != expected_neural_cost:
			_add_issue(issues, "NEURAL_COST_MISMATCH", "Нейростоимость экземпляра не совпадает с шаблоном.", item.item_id)
		if slot.begins_with("IMP_"):
			implant_cost += item.neural_cost
		_validate_affixes(item, template, issues)
		var source_kind: String = "unique" if template.has("uniqueEffectId") else "item"
		var source: Dictionary = {"id": item.item_id, "name": str(template["name"]), "kind": source_kind}
		if slot == "ARMOR" and template.has("armorBlock"):
			_add_armor_modifiers(item, template, source, modifiers)
		for effect_index: int in range((template.get("effects", []) as Array).size()):
			var effect: Dictionary = template["effects"][effect_index]
			_add_effect(effect, source, "%s:effect:%d" % [item.item_id, effect_index], template, item, int(attributes["SYN"]), effects, trigger_effects, modifiers)
		for affix: ItemInstance.AffixRoll in item.affixes:
			var definition: Dictionary = _catalog.get_affix(affix.affix_id)
			if definition.is_empty():
				continue
			var affix_effect: Dictionary = {
				"type": "stat", "stat": str(definition["stat"]), "op": str(definition.get("op", "FLAT")), "value": affix.value,
				"note": "%s T%d%s" % [str(definition["name"]), affix.tier, " ×D(T)" if bool(definition.get("scaleD", false)) else ""],
			}
			var affix_source: Dictionary = {"id": "%s:%s" % [item.item_id, affix.affix_id], "name": str(definition["name"]), "kind": "affix"}
			_add_effect(affix_effect, affix_source, "%s:%d" % [affix_source["id"], affix.tier], template, item, int(attributes["SYN"]), effects, trigger_effects, modifiers)
		if slot == "MAIN":
			main_weapon = _resolve_weapon(item, template)
		elif slot == "OFFHAND" and template.has("weapon") and bool(template["weapon"].get("sidearmOnly", false)):
			sidearm = _resolve_weapon(item, template)
		if slot.begins_with("DRONE_"):
			var drone: Dictionary = _resolve_drone(item, template)
			if drone.is_empty():
				_add_issue(issues, "MISSING_WEAPON_BLOCK", "У дрона %s отсутствуют параметры." % str(template["name"]), item.item_id)
			else:
				drones.append(drone)
	if not equipment.has("MAIN"):
		_add_issue(issues, "MISSING_MAIN", "Для боя требуется основное оружие.")
	elif not valid_templates.get("MAIN", {}).has("weapon"):
		_add_issue(issues, "MISSING_WEAPON_BLOCK", "У основного предмета отсутствуют параметры оружия.", str((equipment["MAIN"] as ItemInstance).item_id))
	elif not main_weapon.is_empty():
		var main_item: ItemInstance = equipment["MAIN"] as ItemInstance
		var main_source: Dictionary = {"id": "%s:tech-power" % main_item.item_id, "name": str(valid_templates["MAIN"]["name"]), "kind": "item"}
		var tech_power_modifier: Dictionary = _stats.make_modifier("techPower", "FLAT", _formula.tech_power(float(main_weapon["damage"]), main_item.tech_level), main_source)
		modifiers.insert(attribute_modifier_count, tech_power_modifier)
	for skill: Dictionary in resolved_skills:
		for requirement: Variant in skill.get("requires", []):
			if not _skill_requirement_met(str(requirement), valid_templates):
				_add_issue(issues, "SKILL_REQUIREMENT", "%s: не выполнено требование %s." % [str(skill["name"]), str(requirement)], str(skill["id"]))
	for skill: Dictionary in resolved_skills:
		for effect_index: int in range((skill.get("extraEffects", []) as Array).size()):
			var effect: Dictionary = skill["extraEffects"][effect_index]
			_add_static_effect(effect, {"id": skill["id"], "name": skill["name"], "kind": "skill"}, "%s:effect:%d" % [skill["id"], effect_index], effects, trigger_effects, modifiers)
	for passive: Dictionary in resolved_passives:
		for effect_index: int in range((passive.get("effects", []) as Array).size()):
			_add_static_effect(passive["effects"][effect_index], {"id": passive["id"], "name": passive["name"], "kind": "passive"}, "%s:effect:%d" % [passive["id"], effect_index], effects, trigger_effects, modifiers)
	for tree_node: Dictionary in resolved_tree_nodes:
		for effect_index: int in range((tree_node.get("effects", []) as Array).size()):
			_add_static_effect(tree_node["effects"][effect_index], {"id": tree_node["id"], "name": tree_node["name"], "kind": "tree"}, "%s:effect:%d" % [tree_node["id"], effect_index], effects, trigger_effects, modifiers)
	for mutation: Dictionary in resolved_mutations:
		for required_mutation: Variant in mutation.get("requires", []):
			if not mutation_ids.has(str(required_mutation)):
				_add_issue(issues, "MUTATION_REQUIREMENT", "%s требует %s." % [str(mutation["name"]), str(required_mutation)], str(mutation["id"]))
		for effect_index: int in range((mutation.get("effects", []) as Array).size()):
			_add_static_effect(mutation["effects"][effect_index], {"id": mutation["id"], "name": mutation["name"], "kind": "mutation"}, "%s:effect:%d" % [mutation["id"], effect_index], effects, trigger_effects, modifiers)
	var unique_ids: Array[String] = []
	for item_value: Variant in equipment.values():
		if item_value is ItemInstance:
			for unique_id: String in item_value.unique_effect_ids:
				if not unique_ids.has(unique_id):
					unique_ids.append(unique_id)
	var context: Dictionary = input.get("context", {}).duplicate(true) if input.get("context", {}) is Dictionary else {}
	var flags: Dictionary = context.get("flags", {}).duplicate(true) if context.get("flags", {}) is Dictionary else {}
	var main_template: Dictionary = valid_templates.get("MAIN", {})
	var weapon_type: String = str(main_template.get("weapon", {}).get("type", ""))
	flags["mainKinetic"] = 1.0 if weapon_type == "KINETIC" else 0.0
	flags["weaponShotgun"] = 1.0 if (main_template.get("tags", []) as Array).has("shotgun") else 0.0
	context["flags"] = flags
	var context_uniques: Array = context.get("uniques", []).duplicate()
	for unique_id: String in unique_ids:
		if not context_uniques.has(unique_id):
			context_uniques.append(unique_id)
	context["uniques"] = context_uniques
	var stat_results: Dictionary = _stats.resolve_stats(_stats.bundle(modifiers), context)
	var sheet: Dictionary = _stats.sheet_of(stat_results)
	if implant_cost > float(sheet.get("neuralCapacity", 0.0)):
		_add_issue(issues, "NEURAL_CAPACITY", "Импланты требуют %s нейроёмкости при лимите %s." % [implant_cost, sheet.get("neuralCapacity", 0.0)])
	var result: Dictionary = _result(issues, attributes, equipment, sheet, stat_results, modifiers, effects, trigger_effects, drones, [main_weapon, sidearm])
	result["skills"] = resolved_skills
	result["skillIds"] = skill_ids
	result["passives"] = resolved_passives
	result["passiveIds"] = passive_ids
	result["treeNodes"] = resolved_tree_nodes
	result["treeNodeIds"] = selected_tree_ids
	result["mutationIds"] = mutation_ids
	return result

func _read_selection(input: Dictionary, key: String, issues: Array[Dictionary]) -> Array[String]:
	var output: Array[String] = []
	var raw: Variant = input.get(key, [])
	if not raw is Array:
		_add_issue(issues, "INVALID_SELECTION", "%s должен быть массивом." % key, key)
		return output
	var seen: Dictionary = {}
	for value: Variant in raw:
		if not value is String or str(value).is_empty():
			_add_issue(issues, "INVALID_SELECTION", "В списке %s есть пустой или неверный ID." % key, key)
			continue
		var id: String = str(value)
		if seen.has(id):
			_add_issue(issues, "DUPLICATE_SELECTION", "Повторяется выбор %s." % id, id)
		seen[id] = true
		output.append(id)
	return output

func _skill_requirement_met(requirement: String, valid_templates: Dictionary) -> bool:
	match requirement:
		"MAIN_K":
			return str(valid_templates.get("MAIN", {}).get("weapon", {}).get("type", "")) == "KINETIC"
		"SIDEARM":
			return bool(valid_templates.get("OFFHAND", {}).get("weapon", {}).get("sidearmOnly", false))
		"DR_MED":
			return _has_drone_role(valid_templates, "medic")
		"DR_EMP":
			return _has_drone_role(valid_templates, "emp")
		"VIRUS":
			return true
	return false

func _has_drone_role(valid_templates: Dictionary, role: String) -> bool:
	for slot: String in ["DRONE_1", "DRONE_2"]:
		if str(valid_templates.get(slot, {}).get("drone", {}).get("role", "")) == role:
			return true
	return false

func _add_static_effect(effect: Dictionary, source: Dictionary, modifier_id: String, effects: Array[Dictionary], trigger_effects: Array[Dictionary], modifiers: Array[Dictionary]) -> void:
	effects.append(effect.duplicate(true))
	if str(effect.get("type", "")) == "trigger":
		trigger_effects.append({"effect": effect.duplicate(true), "sourceId": source["id"], "sourceName": source["name"], "sourceKind": source["kind"]})
	elif str(effect.get("type", "")) == "stat":
		var extra: Dictionary = {"id": modifier_id}
		for field: String in ["condition", "stackGroup", "synScalable", "note"]:
			if effect.has(field):
				extra[field] = effect[field]
		modifiers.append(_stats.make_modifier(str(effect["stat"]), str(effect["op"]), float(effect["value"]), source, extra))

func _tree_lock_reason(node_id: String, allocated: Array[String], available_points: int) -> String:
	var node: Dictionary = _build_catalog.tree_nodes.get(node_id, {})
	if node.is_empty():
		return "Неизвестный узел"
	if allocated.has(node_id):
		return "Уже изучен"
	if available_points <= 0:
		return "Нет свободных очков"
	var branch: String = str(node["branch"])
	if branch == "X":
		for requirement: Dictionary in node.get("requires", []):
			if _branch_points(allocated, str(requirement["branch"])) < int(requirement["points"]):
				return "Нужно %d очков в ветви %s" % [int(requirement["points"]), str(requirement["branch"])]
		return ""
	var tier: int = int(node["tier"])
	var points: int = _branch_points(allocated, branch)
	if tier == 2 and (points < 2 or not _has_branch_tier(allocated, branch, 1)):
		return "Нужно ≥2 очков в ветви и один узел T1"
	if tier == 3 and (points < 5 or not _has_branch_tier(allocated, branch, 2)):
		return "Нужно ≥5 очков в ветви и один узел T2"
	if tier == 4 and (points < 9 or not _has_branch_tier(allocated, branch, 3)):
		return "Нужно ≥9 очков в ветви и один узел T3"
	if bool(node["keystone"]) and _keystone_count(allocated) >= 2:
		return "Достигнут лимит двух keystone"
	return ""

func _branch_points(allocated: Array[String], branch: String) -> int:
	var total: int = 0
	for node_id: String in allocated:
		if str(_build_catalog.tree_nodes.get(node_id, {}).get("branch", "")) == branch:
			total += 1
	return total

func _has_branch_tier(allocated: Array[String], branch: String, tier: int) -> bool:
	for node_id: String in allocated:
		var node: Dictionary = _build_catalog.tree_nodes.get(node_id, {})
		if str(node.get("branch", "")) == branch and int(node.get("tier", 0)) == tier:
			return true
	return false

func _keystone_count(allocated: Array[String]) -> int:
	var total: int = 0
	for node_id: String in allocated:
		if bool(_build_catalog.tree_nodes.get(node_id, {}).get("keystone", false)):
			total += 1
	return total

func _validate_attributes(input: Dictionary, attributes: Dictionary, issues: Array[Dictionary]) -> void:
	var earned: Variant = input.get("attributePointsEarned", 0)
	var allocated: float = 0.0
	for attribute: String in ATTRIBUTE_IDS:
		var value: Variant = attributes[attribute]
		if not _is_finite_number(value) or float(value) < 1.0:
			_add_issue(issues, "INVALID_ATTRIBUTE", "Атрибут %s должен быть конечным числом не меньше 1." % attribute, attribute)
		else:
			allocated += maxf(0.0, float(value) - 5.0)
	if not _is_integer(earned) or int(earned) < 0:
		_add_issue(issues, "ATTRIBUTE_POINTS", "Число полученных очков атрибутов должно быть целым и неотрицательным.")
	if _is_integer(earned) and int(earned) > 12:
		_add_issue(issues, "ATTRIBUTE_POINTS_CAP", "За уровни доступно не более 12 очков атрибутов.")
	if _is_integer(earned) and allocated > float(earned):
		_add_issue(issues, "ATTRIBUTE_POINTS", "Распределено %s очков атрибутов, получено %s." % [allocated, earned])

func _add_attribute_modifiers(attributes: Dictionary, modifiers: Array[Dictionary]) -> void:
	for effect: Dictionary in ATTRIBUTE_EFFECTS:
		var raw_attribute: Variant = attributes[effect["attribute"]]
		if not _is_finite_number(raw_attribute):
			continue
		var delta: float = float(raw_attribute) - 5.0
		if is_zero_approx(delta):
			continue
		var source: Dictionary = {"id": "attribute:%s" % effect["attribute"], "name": str(effect["attribute"]), "kind": "attribute"}
		modifiers.append(_stats.make_modifier(str(effect["stat"]), str(effect["op"]), delta * float(effect["perPoint"]), source))

func _slot_allows(slot: String, template: Dictionary) -> bool:
	if str(SLOT_CATEGORY.get(slot, "")) != str(template.get("category", "")):
		return false
	if not slot.begins_with("IMP_"):
		return true
	var implant_slot: String = str(template.get("implantSlot", ""))
	var socket: String = str(IMPLANT_SOCKET.get(slot, ""))
	return not implant_slot.is_empty() and (socket == "UNIVERSAL" or implant_slot == "UNIVERSAL" or implant_slot == socket)

func _validate_affixes(item: ItemInstance, template: Dictionary, issues: Array[Dictionary]) -> void:
	var groups: Dictionary = {}
	for roll: ItemInstance.AffixRoll in item.affixes:
		var definition: Dictionary = _catalog.get_affix(roll.affix_id)
		if definition.is_empty():
			_add_issue(issues, "INVALID_AFFIX", "Неизвестный аффикс %s." % roll.affix_id, item.item_id)
			continue
		if not (definition.get("slots", []) as Array).has(str(template["category"])) or roll.tier < 1 or roll.tier > 4 or not is_finite(roll.value):
			_add_issue(issues, "INVALID_AFFIX", "Аффикс %s несовместим с предметом или содержит неверный ролл." % roll.affix_id, item.item_id)
		var group_id: String = str(definition["group"])
		if groups.has(group_id):
			_add_issue(issues, "INVALID_AFFIX_GROUP", "Повторяется группа аффиксов %s." % group_id, item.item_id)
		groups[group_id] = true

func _add_armor_modifiers(item: ItemInstance, template: Dictionary, source: Dictionary, modifiers: Array[Dictionary]) -> void:
	var armor: Dictionary = template["armorBlock"]
	var condition: float = 0.75 if item.durability < 25.0 else 1.0
	modifiers.append(_stats.make_modifier("maxHP", "FLAT", float(armor["hp"]) * _formula.d_depth(item.tech_level), source, {"id": "%s:armor-hp" % item.item_id}))
	modifiers.append(_stats.make_modifier("maxShield", "FLAT", float(armor["shield"]) * _formula.d_depth(item.tech_level) * condition, source, {"id": "%s:armor-shield" % item.item_id}))
	modifiers.append(_stats.make_modifier("armor", "FLAT", float(armor["armor"]) * condition, source, {"id": "%s:armor-flat" % item.item_id}))

func _add_effect(effect: Dictionary, source: Dictionary, modifier_id: String, template: Dictionary, item: ItemInstance, syn: int, effects: Array[Dictionary], trigger_effects: Array[Dictionary], modifiers: Array[Dictionary]) -> void:
	effects.append(effect.duplicate(true))
	if str(effect.get("type", "")) == "trigger":
		trigger_effects.append({"effect": effect.duplicate(true), "sourceId": source["id"], "sourceName": source["name"], "sourceKind": source["kind"]})
		return
	if str(effect.get("type", "")) != "stat":
		return
	var value: float = float(effect.get("value", 0.0))
	var note: String = str(effect.get("note", ""))
	if note.contains("×D(T)"):
		value *= _formula.d_depth(item.tech_level)
	if note.contains("×H(T)"):
		value *= _formula.h_depth(item.tech_level)
	if str(template["category"]) == "IMPLANT" and bool(effect.get("synScalable", false)):
		value *= maxf(0.0, 1.0 + 0.015 * float(syn - 5))
	if item.durability < 25.0:
		value *= 0.9
	var extra: Dictionary = {"id": modifier_id}
	for field: String in ["condition", "stackGroup", "synScalable", "note"]:
		if effect.has(field):
			extra[field] = effect[field]
	modifiers.append(_stats.make_modifier(str(effect["stat"]), str(effect["op"]), value, source, extra))

func _resolve_weapon(item: ItemInstance, template: Dictionary) -> Dictionary:
	if not template.has("weapon"):
		return {}
	var weapon: Dictionary = template["weapon"].duplicate(true)
	var scale: float = _formula.h_depth(item.tech_level) * (0.9 if item.durability < 25.0 else 1.0)
	weapon["itemId"] = item.item_id
	weapon["templateId"] = item.template_id
	weapon["techLevel"] = item.tech_level
	weapon["damage"] = float(weapon["damage"]) * scale
	if weapon.get("packets") is Array:
		for packet: Dictionary in weapon["packets"]:
			packet["amount"] = float(packet["amount"]) * scale
	return weapon

func _resolve_drone(item: ItemInstance, template: Dictionary) -> Dictionary:
	if not template.has("drone"):
		return {}
	var drone: Dictionary = template["drone"].duplicate(true)
	var condition: float = 0.9 if item.durability < 25.0 else 1.0
	var d_scale: float = _formula.d_depth(item.tech_level) * condition
	var h_scale: float = _formula.h_depth(item.tech_level) * condition
	drone["itemId"] = item.item_id
	drone["templateId"] = item.template_id
	drone["techLevel"] = item.tech_level
	drone["hp"] = float(drone["hp"]) * d_scale
	drone["shield"] = float(drone["shield"]) * d_scale
	drone["damage"] = float(drone["damage"]) * h_scale
	return drone

func _as_item_instance(value: Variant) -> ItemInstance:
	if value is ItemInstance:
		return value
	if value is Dictionary:
		var item: ItemInstance = ItemInstance.new()
		return item if item.instantiate_from_dictionary(value) else null
	return null

func _result(issues: Array[Dictionary], attributes: Dictionary, equipment: Dictionary, sheet: Dictionary, stat_results: Dictionary, modifiers: Array[Dictionary], effects: Array[Dictionary], trigger_effects: Array[Dictionary], drones: Array[Dictionary], weapons: Array) -> Dictionary:
	return {
		"valid": issues.is_empty(), "attributes": attributes, "equipment": equipment, "stats": sheet, "statResults": stat_results,
		"mainWeapon": weapons[0] if weapons.size() > 0 else {}, "sidearm": weapons[1] if weapons.size() > 1 else {},
		"drones": drones, "skills": [], "skillIds": [], "passives": [], "passiveIds": [], "treeNodes": [], "treeNodeIds": [],
		"mutationIds": [], "effects": effects, "triggerEffects": trigger_effects, "modifiers": modifiers, "issues": issues,
	}

func _add_issue(issues: Array[Dictionary], code: String, message: String, source_id: String = "") -> void:
	var issue: Dictionary = {"code": code, "message": message}
	if not source_id.is_empty():
		issue["sourceId"] = source_id
	issues.append(issue)

func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floor(float(value))
