class_name ItemFactory
extends RefCounted

const RARITIES: Array[String] = ["COMMON", "MODIFIED", "RARE", "LEGENDARY", "UNIQUE"]
const BIOME_TAGS: Dictionary = {
	"B01": ["weapon", "speed", "pistol", "smg"],
	"B02": ["armor", "shield"],
	"B03": ["drone", "craft", "transport"],
	"B04": ["digital", "virus"],
	"B05": ["heat", "energy"],
	"B06": ["unique", "conversion", "hybrid", "heavy"],
}
func create_item(rng: DeterministicRng, catalog: ItemCatalog, options: Dictionary) -> Dictionary:
	if rng == null or catalog == null:
		return _failure("Для создания предмета нужны RNG и каталог.")
	var template_id: String = str(options.get("templateId", ""))
	var template: Dictionary = catalog.get_template(template_id)
	if template.is_empty():
		return _failure("Неизвестный шаблон предмета: %s" % template_id)
	var tech_value: Variant = options.get("techLevel", 1)
	if not _finite_number(tech_value) or float(tech_value) < 0.0:
		return _failure("TechLevel должен быть конечным неотрицательным числом.")
	var rarity: String = str(options.get("rarity", "COMMON"))
	if not RARITIES.has(rarity):
		return _failure("Неизвестная редкость предмета: %s" % rarity)
	var grant_id: String = str(options.get("originGrantId", ""))
	var item_origin: String = str(options.get("origin", ""))
	var acquired_at: Variant = options.get("acquiredAt", 0.0)
	if grant_id.is_empty() or item_origin.is_empty() or not options.get("secured") is bool or not _finite_number(acquired_at) or float(acquired_at) < 0.0:
		return _failure("Для предмета нужны originGrantId, origin и secured.")
	var count_result: Dictionary = _affix_count(rng, rarity, options, catalog)
	if not bool(count_result.get("ok", false)):
		return count_result
	var item: ItemInstance = ItemInstance.new()
	item.template_id = template_id
	item.tech_level = maxi(1, roundi(float(tech_value)))
	item.rarity = rarity
	item.item_id = "it:%s:%s" % [_encode_component(grant_id), _encode_component(template_id)]
	if template.has("uniqueEffectId"):
		item.unique_effect_ids.append(str(template["uniqueEffectId"]))
	item.neural_cost = float(template.get("neuralCost", 0.0))
	item.durability = 100.0
	item.secured = bool(options.get("secured", false))
	item.origin_grant_id = grant_id
	item.acquired_at = float(acquired_at)
	item.origin = item_origin
	var affix_pool: Array[Dictionary] = _affixes_for_slot(catalog, str(template["category"]))
	var rules: Dictionary = catalog.get_rules()
	var weights: Dictionary = rules.get("slotGroupWeights", {}).get(str(template["category"]), {})
	var used: Dictionary = {}
	for index: int in range(int(count_result["count"])):
		var candidates: Array[Dictionary] = []
		var candidates_weights: Array[Dictionary] = []
		for candidate: Dictionary in affix_pool:
			if used.has(str(candidate["id"])):
				continue
			candidates.append(candidate)
			var weight: float = float(weights.get(str(candidate["group"]), 1.0))
			candidates_weights.append({"item": candidate, "weight": weight})
		if candidates.is_empty():
			break
		var chosen: Dictionary = rng.weighted(candidates_weights) as Dictionary
		if chosen.is_empty():
			return _failure("Для шаблона %s не осталось доступных аффиксов." % template_id)
		used[str(chosen["id"])] = true
		var tier: int = _tier_for_tech(item.tech_level)
		var boosted: bool = false
		if (rarity == "RARE" or rarity == "LEGENDARY") and tier < 4 and rng.chance(0.2):
			tier += 1
			boosted = true
		var tiers: Array = chosen["tiers"]
		var center: float = float(tiers[tier - 1])
		var raw: float = 1.0 if bool(chosen.get("fixed", false)) else rng.range_float(0.8, 1.2)
		var integer: bool = bool(chosen.get("integer", false))
		var value: float = maxf(1.0, roundf(center * raw)) if integer else _round_to(center * raw, 2)
		var roll: ItemInstance.AffixRoll = ItemInstance.AffixRoll.new()
		roll.affix_id = str(chosen["id"])
		roll.tier = tier
		roll.value = value
		roll.raw_roll = _round_to(raw, 4)
		roll.tier_boosted = boosted
		roll.center = center
		roll.minimum = maxf(1.0, roundf(center * 0.8)) if integer else _round_to(center * 0.8, 2)
		roll.maximum = roundf(center * 1.2) if integer else _round_to(center * 1.2, 2)
		item.affixes.append(roll)
	var tr_ranges: Dictionary = rules.get("trRanges", {})
	var tr_range: Array = tr_ranges.get(rarity, [0, 0])
	item.tr = float(int(tr_range[0])) if int(tr_range[0]) == int(tr_range[1]) else float(rng.int_range(int(tr_range[0]), int(tr_range[1])))
	item.roll_seed = "%s:%d" % [rng.stream, rng.calls]
	return {"ok": true, "item": item, "error": ""}

func roll_rarity(rng: DeterministicRng, catalog: ItemCatalog, table: String, rare_shift: float = 0.0) -> String:
	var base: Array = catalog.get_rules().get("rarityTables", {}).get(table, [])
	if base.is_empty():
		return "COMMON"
	var weights: Array = base.duplicate()
	if rare_shift > 0.0:
		var shift: float = minf(float(weights[0]), rare_shift * 100.0)
		weights[0] = float(weights[0]) - shift
		weights[2] = float(weights[2]) + shift
	var roll: float = rng.next_float() * 100.0
	var cumulative: float = 0.0
	for index: int in range(RARITIES.size()):
		cumulative += float(weights[index])
		if roll < cumulative:
			return RARITIES[index]
	return "COMMON"

func roll_item(rng: DeterministicRng, catalog: ItemCatalog, options: Dictionary) -> Dictionary:
	if rng == null or catalog == null:
		return _failure("Для выдачи предмета нужны RNG и каталог.")
	var biome: String = str(options.get("biome", ""))
	var depth: int = int(options.get("depth", 1))
	var table: String = str(options.get("table", "ORDINARY"))
	var rarity: String = str(options["forceRarity"]) if options.has("forceRarity") else roll_rarity(rng, catalog, table, float(options.get("rareShift", 0.0)))
	if not ["B01", "B02", "B03", "B04", "B05", "B06"].has(biome) or depth < 1:
		return _failure("Для розыгрыша предмета нужны корректные глубина и биом.")
	if not RARITIES.has(rarity):
		return _failure("Неизвестная редкость предмета: %s" % rarity)
	var offset_roll: float = rng.next_float()
	var offset: int = int(options["techOffsetOverride"]) if options.has("techOffsetOverride") else (-1 if offset_roll < 0.2 else 0 if offset_roll < 0.85 else 1)
	var tech_level: int = maxi(1, depth + offset)
	var template_id: String = str(options.get("forceTemplateId", ""))
	var fallback_from_unique: bool = false
	if template_id.is_empty():
		if rarity == "UNIQUE":
			var unique_pool: Array[Dictionary] = []
			for template: Dictionary in catalog.all_templates():
				if not template.has("uniqueEffectId") or not (template.get("biomes", []) as Array).has(biome):
					continue
				if options.has("forceTag") and not (template["tags"] as Array).has(str(options["forceTag"])):
					continue
				if options.has("forceCategory") and str(template["category"]) != str(options["forceCategory"]):
					continue
				unique_pool.append(template)
			if unique_pool.is_empty():
				rarity = "LEGENDARY"
				fallback_from_unique = true
			else:
				template_id = str((rng.pick(unique_pool) as Dictionary)["id"])
		if template_id.is_empty():
			var pool: Array[Dictionary] = _biome_item_pool(catalog, biome, float(options.get("energyWeightBonus", 0.0)))
			if options.has("forceCategory"):
				pool = pool.filter(func(candidate: Dictionary) -> bool: return str(candidate["item"]["category"]) == str(options["forceCategory"]))
			if options.has("forceTag"):
				pool = pool.filter(func(candidate: Dictionary) -> bool: return (candidate["item"]["tags"] as Array).has(str(options["forceTag"])))
			if pool.is_empty():
				pool = _biome_item_pool(catalog, biome, 0.0)
			if pool.is_empty():
				return _failure("Для биома %s не найден пул предметов." % biome)
			var selected: Variant = rng.weighted(pool)
			template_id = str((selected as Dictionary)["id"])
	var create_options: Dictionary = {
		"templateId": template_id,
		"techLevel": tech_level,
		"rarity": rarity,
		"secured": bool(options.get("secured", false)),
		"originGrantId": str(options.get("grantId", "")),
		"origin": str(options.get("origin", "")),
	}
	if options.has("acquiredAt"):
		create_options["acquiredAt"] = options["acquiredAt"]
	var created: Dictionary = create_item(rng, catalog, create_options)
	if not bool(created.get("ok", false)):
		return created
	return {"ok": true, "item": created["item"], "fallbackFromUnique": fallback_from_unique, "rarity": rarity, "error": ""}

func _biome_item_pool(catalog: ItemCatalog, biome: String, energy_weight_bonus: float) -> Array[Dictionary]:
	var tags: Array = BIOME_TAGS.get(biome, [])
	var pool: Array[Dictionary] = []
	for template: Dictionary in catalog.all_templates():
		if not bool(template["craftable"]) or str(template["category"]) == "MATERIAL" or template.has("uniqueEffectId"):
			continue
		var weight: float = 1.0
		for tag: Variant in template["tags"]:
			if tags.has(tag):
				weight += 3.0
				break
		if energy_weight_bonus > 0.0 and (template["tags"] as Array).has("energy"):
			weight *= 1.0 + energy_weight_bonus
		pool.append({"item": template, "weight": weight})
	return pool

func _affix_count(rng: DeterministicRng, rarity: String, options: Dictionary, catalog: ItemCatalog) -> Dictionary:
	var ranges: Dictionary = catalog.get_rules().get("rarityAffixCount", {})
	var range_value: Array = ranges.get(rarity, [])
	if range_value.size() != 2:
		return _failure("Не заданы правила количества аффиксов редкости %s." % rarity)
	var minimum: int = int(range_value[0])
	var maximum: int = int(range_value[1])
	if rarity == "COMMON":
		return {"ok": true, "count": 0}
	if options.has("affixCount"):
		var requested: int = int(options["affixCount"])
		if requested < minimum or requested > maximum:
			return _failure("Число аффиксов выходит за пределы редкости %s." % rarity)
		return {"ok": true, "count": requested}
	return {"ok": true, "count": minimum if minimum == maximum or rng.chance(0.5) else maximum}

func _affixes_for_slot(catalog: ItemCatalog, category: String) -> Array[Dictionary]:
	var affixes: Array[Dictionary] = []
	var entries: Array = catalog.get_rules().get("affixes", [])
	for value: Variant in entries:
		if value is Dictionary and (value["slots"] as Array).has(category):
			affixes.append(value)
	return affixes

func _tier_for_tech(tech_level: int) -> int:
	if tech_level <= 4:
		return 1
	if tech_level <= 8:
		return 2
	if tech_level <= 12:
		return 3
	return 4

func _round_to(value: float, digits: int) -> float:
	var factor: float = pow(10.0, float(digits))
	return floorf(value * factor + 0.5) / factor

func _encode_component(value: String) -> String:
	var result: String = ""
	for byte: int in value.to_utf8_buffer():
		var character: String = String.chr(byte)
		var unreserved: bool = byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122 or byte >= 48 and byte <= 57 or "-_.!~*'()".contains(character)
		result += character if unreserved else "%%%02X" % byte
	return result

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "item": null, "error": message}
