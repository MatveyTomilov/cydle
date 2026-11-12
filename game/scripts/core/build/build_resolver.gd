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
var _stats: StatMath = StatMath.new()
var _formula: CydleFormula = CydleFormula.new()
var _catalog_loaded: bool = false
var _catalog_error: String = ""

func resolve_build(input: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	if not _catalog_loaded:
		var catalog_result: Dictionary = _catalog.load_catalog()
		_catalog_loaded = true
		_catalog_error = str(catalog_result.get("error", "")) if not bool(catalog_result.get("ok", false)) else ""
	if not _catalog_error.is_empty():
		_add_issue(issues, "DATA_CATALOG", "Каталог предметов не загружен: %s" % _catalog_error)
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
	for key: String in ["skillIds", "passiveIds", "treeNodeIds", "mutationIds"]:
		var selected: Variant = input.get(key, [])
		if not selected is Array:
			_add_issue(issues, "INVALID_SELECTION", "%s должен быть массивом." % key, key)
		elif not selected.is_empty():
			_add_issue(issues, "UNSUPPORTED_SELECTION", "Система %s ещё не перенесена в Godot." % key, str(selected[0]))
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
	return _result(issues, attributes, equipment, sheet, stat_results, modifiers, effects, trigger_effects, drones, [main_weapon, sidearm])

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
