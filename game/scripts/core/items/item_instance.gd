class_name ItemInstance
extends RefCounted

class AffixRoll:
	extends RefCounted
	var affix_id: String = ""
	var tier: int = 1
	var value: float = 0.0
	var raw_roll: float = 1.0
	var tier_boosted: bool = false
	var center: float = 0.0
	var minimum: float = 0.0
	var maximum: float = 0.0

	func to_dictionary() -> Dictionary:
		return {"affixId": affix_id, "tier": tier, "value": value, "rawRoll": raw_roll, "tierBoosted": tier_boosted, "center": center, "min": minimum, "max": maximum}

var item_id: String = ""
var template_id: String = ""
var tech_level: int = 1
var rarity: String = "COMMON"
var affixes: Array[AffixRoll] = []
var unique_effect_ids: Array[String] = []
var neural_cost: float = 0.0
var durability: float = 100.0
var secured: bool = false
var origin_grant_id: String = ""
var roll_seed: String = ""
var tr: float = 0.0
var core_group: int = 0
var acquired_at: float = 0.0
var origin: String = ""
var label: String = ""

func to_dictionary() -> Dictionary:
	var affix_values: Array[Dictionary] = []
	for affix: AffixRoll in affixes:
		affix_values.append(affix.to_dictionary())
	var result: Dictionary = {
		"itemId": item_id,
		"templateId": template_id,
		"techLevel": tech_level,
		"rarity": rarity,
		"affixes": affix_values,
		"uniqueEffectIds": unique_effect_ids.duplicate(),
		"neuralCost": neural_cost,
		"durability": durability,
		"secured": secured,
		"originGrantId": origin_grant_id,
		"rollSeed": roll_seed,
		"tr": tr,
		"acquiredAt": acquired_at,
		"origin": origin,
	}
	if core_group > 0:
		result["coreGroup"] = core_group
	if not label.is_empty():
		result["label"] = label
	return result

func instantiate_from_dictionary(value: Dictionary) -> bool:
	if not _valid_item_dictionary(value):
		return false
	item_id = str(value["itemId"])
	template_id = str(value["templateId"])
	tech_level = int(value["techLevel"])
	rarity = str(value["rarity"])
	affixes.clear()
	for entry: Variant in value["affixes"]:
		var parsed: AffixRoll = AffixRoll.new()
		parsed.affix_id = str(entry["affixId"])
		parsed.tier = int(entry["tier"])
		parsed.value = float(entry["value"])
		parsed.raw_roll = float(entry["rawRoll"])
		parsed.tier_boosted = bool(entry["tierBoosted"])
		parsed.center = float(entry["center"])
		parsed.minimum = float(entry["min"])
		parsed.maximum = float(entry["max"])
		affixes.append(parsed)
	unique_effect_ids.assign(value["uniqueEffectIds"])
	neural_cost = float(value["neuralCost"])
	durability = float(value["durability"])
	secured = bool(value["secured"])
	origin_grant_id = str(value["originGrantId"])
	roll_seed = str(value["rollSeed"])
	tr = float(value["tr"])
	core_group = int(value.get("coreGroup", 0))
	acquired_at = float(value["acquiredAt"])
	origin = str(value["origin"])
	label = str(value.get("label", ""))
	return true

func _valid_item_dictionary(value: Dictionary) -> bool:
	for key: String in ["itemId", "templateId", "techLevel", "rarity", "affixes", "uniqueEffectIds", "neuralCost", "durability", "secured", "originGrantId", "rollSeed", "tr", "acquiredAt", "origin"]:
		if not value.has(key):
			return false
	if not _is_nonempty_string(value["itemId"]) or not _is_nonempty_string(value["templateId"]) or not _is_integer(value["techLevel"]) or int(value["techLevel"]) < 1:
		return false
	if not ["COMMON", "MODIFIED", "RARE", "LEGENDARY", "UNIQUE"].has(str(value["rarity"])):
		return false
	if not value["affixes"] is Array or not value["uniqueEffectIds"] is Array or not value["secured"] is bool:
		return false
	if not _is_finite_number(value["neuralCost"]) or float(value["neuralCost"]) < 0.0 or not _is_finite_number(value["durability"]) or float(value["durability"]) < 0.0 or float(value["durability"]) > 100.0:
		return false
	if not _is_finite_number(value["tr"]) or not _is_finite_number(value["acquiredAt"]) or float(value["acquiredAt"]) < 0.0:
		return false
	if not _is_nonempty_string(value["originGrantId"]) or not value["rollSeed"] is String or not value["origin"] is String:
		return false
	if value.has("coreGroup") and not _is_integer(value["coreGroup"]):
		return false
	if value.has("label") and not value["label"] is String:
		return false
	for effect_id: Variant in value["uniqueEffectIds"]:
		if not effect_id is String:
			return false
	for affix_value: Variant in value["affixes"]:
		if not affix_value is Dictionary:
			return false
		for key: String in ["affixId", "tier", "value", "rawRoll", "tierBoosted", "center", "min", "max"]:
			if not affix_value.has(key):
				return false
		if not _is_nonempty_string(affix_value["affixId"]) or not _is_integer(affix_value["tier"]) or int(affix_value["tier"]) < 1 or int(affix_value["tier"]) > 4:
			return false
		if not affix_value["tierBoosted"] is bool:
			return false
		for key: String in ["value", "rawRoll", "center", "min", "max"]:
			if not _is_finite_number(affix_value[key]):
				return false
	return true

func _is_nonempty_string(value: Variant) -> bool:
	return value is String and not str(value).is_empty()

func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floor(float(value))

func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
