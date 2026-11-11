class_name StatMath
extends RefCounted

const STAT_REGISTRY_PATH: String = "res://data/core/stat_registry.json"

var _registry: Dictionary = {}
var _ids: Array[String] = []
var _trace: CalcTrace = CalcTrace.new()
var _formula: CydleFormula = CydleFormula.new()

func _init() -> void:
	var file: FileAccess = FileAccess.open(STAT_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read stat registry: %s" % STAT_REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("registry") is Dictionary or not parsed.get("ids") is Array:
		push_error("Invalid stat registry JSON")
		return
	_registry = parsed["registry"]
	for stat_id: Variant in parsed["ids"]:
		_ids.append(str(stat_id))

func stat_ids() -> Array[String]:
	return _ids.duplicate()

func stat_definition(stat_id: String) -> Dictionary:
	return _registry.get(stat_id, {}).duplicate(true)

func make_modifier(stat_id: String, operation: String, value: float, source: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var stage: int = int(extra.get("stage", 0))
	var modifier: Dictionary = {
		"id": str(extra.get("id", "%s:%s:%s:%d" % [source.get("id", ""), stat_id, operation, stage])),
		"sourceId": str(source.get("id", "")),
		"sourceName": str(source.get("name", "")),
		"sourceKind": str(source.get("kind", "base")),
		"stat": stat_id,
		"op": operation,
		"value": value,
	}
	for key: Variant in extra.keys():
		modifier[key] = extra[key]
	return modifier

func bundle(modifiers: Array[Dictionary], conversions: Array[Dictionary] = []) -> Dictionary:
	var by_stat: Dictionary = {}
	for modifier: Dictionary in modifiers:
		var stat_id: String = str(modifier.get("stat", ""))
		if not by_stat.has(stat_id):
			by_stat[stat_id] = []
		var list: Array = by_stat[stat_id]
		list.append(modifier)
		by_stat[stat_id] = list
	return {"mods": modifiers.duplicate(), "byStat": by_stat, "conversions": conversions.duplicate()}

func condition_text(condition: Dictionary) -> String:
	var kind: String = str(condition.get("kind", "always"))
	var value: float = float(condition.get("value", 0.0))
	match kind:
		"always": return "всегда"
		"hpBelow": return "HP < %d%%" % roundi(value * 100.0)
		"hpAbove": return "HP > %d%%" % roundi(value * 100.0)
		"shieldBelow": return "щит < %d%%" % roundi(value * 100.0)
		"energyAtLeast": return "энергия ≥ %s" % value
		"energyBelow": return "энергия < %s" % value
		"heatAtLeast": return "нагрев ≥ %s" % value
		"heatAtMost": return "нагрев ≤ %s" % value
		"heatLockout": return "перегрев (lockout)"
		"targetStatus": return "цель имеет %s%s" % [condition.get("status", ""), " ≥%d" % int(condition.get("minStacks", 1)) if int(condition.get("minStacks", 1)) > 0 else ""]
		"targetNoStatus": return "цель без %s" % condition.get("status", "")
		"targetHpBelow": return "HP цели < %d%%" % roundi(value * 100.0)
		"targetHpAbove": return "HP цели > %d%%" % roundi(value * 100.0)
		"targetIsBoss": return "цель — босс"
		"targetNotBoss": return "цель не босс"
		"targetMechanical": return "цель механическая"
		"targetAlone": return "цель одна"
		"enemiesAtLeast": return "врагов ≥ %s" % value
		"dronesAlive": return "живых дронов ≥ %s" % value
		"otherDroneDead": return "второй дрон мёртв/отсутствует"
		"bothDronesSameTarget": return "оба дрона бьют одну цель"
		"firstSeconds": return "первые %s с боя" % value
		"afterSeconds": return "после %s с боя" % value
		"flagAtLeast": return "%s ≥ %s" % [condition.get("key", ""), value]
		"flagTrue": return "%s активно" % condition.get("key", "")
		"hasUnique": return "экипирован %s" % condition.get("id", "")
		"not": return "НЕ (%s)" % condition_text(condition.get("inner", {}))
		"all", "any":
			var parts: Array[String] = []
			for inner_value: Variant in condition.get("inner", []):
				if inner_value is Dictionary:
					parts.append(condition_text(inner_value))
			return (" И " if kind == "all" else " ИЛИ ").join(parts)
	return "неизвестное условие"

func eval_condition(condition: Dictionary, context: Dictionary = {}) -> bool:
	var kind: String = str(condition.get("kind", "always"))
	if condition.is_empty() or kind == "always":
		return true
	var self_view: Dictionary = context.get("self", {})
	var target_view: Dictionary = context.get("target", {})
	var threshold: float = float(condition.get("value", 0.0))
	var self_max_hp: float = float(self_view.get("maxHP", 0.0))
	var target_max_hp: float = float(target_view.get("maxHP", 0.0))
	var self_max_shield: float = float(self_view.get("maxShield", 0.0))
	var self_statuses: Dictionary = self_view.get("statuses", {})
	var target_statuses: Dictionary = target_view.get("statuses", {})
	var flags: Dictionary = context.get("flags", {})
	var uniques: Array = context.get("uniques", [])
	match kind:
		"hpBelow": return not self_view.is_empty() and self_max_hp > 0.0 and float(self_view.get("hp", 0.0)) / self_max_hp < threshold
		"hpAbove": return not self_view.is_empty() and self_max_hp > 0.0 and float(self_view.get("hp", 0.0)) / self_max_hp > threshold
		"shieldBelow": return not self_view.is_empty() and (self_max_shield <= 0.0 or float(self_view.get("shield", 0.0)) / self_max_shield < threshold)
		"energyAtLeast": return not self_view.is_empty() and float(self_view.get("energy", 0.0)) >= threshold
		"energyBelow": return not self_view.is_empty() and float(self_view.get("energy", 0.0)) < threshold
		"heatAtLeast": return not self_view.is_empty() and float(self_view.get("heat", 0.0)) >= threshold
		"heatAtMost": return not self_view.is_empty() and float(self_view.get("heat", 0.0)) <= threshold
		"heatLockout": return bool(context.get("heatLockout", false))
		"targetStatus": return not target_view.is_empty() and int(target_statuses.get(str(condition.get("status", "")), 0)) >= int(condition.get("minStacks", 1))
		"targetNoStatus": return not target_view.is_empty() and int(target_statuses.get(str(condition.get("status", "")), 0)) == 0
		"targetHpBelow": return not target_view.is_empty() and target_max_hp > 0.0 and float(target_view.get("hp", 0.0)) / target_max_hp < threshold
		"targetHpAbove": return not target_view.is_empty() and target_max_hp > 0.0 and float(target_view.get("hp", 0.0)) / target_max_hp > threshold
		"targetIsBoss": return bool(target_view.get("isBoss", false))
		"targetNotBoss": return not target_view.is_empty() and not bool(target_view.get("isBoss", false))
		"targetMechanical": return bool(target_view.get("isMechanical", false))
		"targetAlone": return int(context.get("enemiesAlive", 1)) <= 1
		"enemiesAtLeast": return int(context.get("enemiesAlive", 0)) >= threshold
		"dronesAlive": return int(context.get("dronesAlive", 0)) >= threshold
		"otherDroneDead": return bool(context.get("otherDroneDead", false))
		"bothDronesSameTarget": return bool(context.get("bothDronesSameTarget", false))
		"firstSeconds": return float(context.get("timeMs", 0.0)) <= threshold * 1000.0
		"afterSeconds": return float(context.get("timeMs", 0.0)) >= threshold * 1000.0
		"flagAtLeast": return float(flags.get(str(condition.get("key", "")), 0.0)) >= threshold
		"flagTrue": return float(flags.get(str(condition.get("key", "")), 0.0)) > 0.0
		"hasUnique": return uniques.has(str(condition.get("id", "")))
		"not": return not eval_condition(condition.get("inner", {}), context)
		"all":
			for inner_value: Variant in condition.get("inner", []):
				if inner_value is Dictionary and not eval_condition(inner_value, context):
					return false
			return true
		"any":
			for inner_value: Variant in condition.get("inner", []):
				if inner_value is Dictionary and eval_condition(inner_value, context):
					return true
			return false
	return false

func condition_signature(modifiers: Array[Dictionary], context: Dictionary = {}) -> String:
	var signature: String = ""
	for modifier: Dictionary in modifiers:
		var condition: Dictionary = modifier.get("condition", {})
		if condition.is_empty() or condition.get("kind") == "always":
			continue
		if eval_condition(condition, context):
			signature += str(modifier.get("id", "")) + ";"
	return signature

func compute_stat(stat_id: String, mod_bundle: Dictionary, context: Dictionary = {}, precomputed: Dictionary = {}, fingerprint: String = "") -> Dictionary:
	var definition: Dictionary = _registry.get(stat_id, {})
	if definition.is_empty():
		return {}
	var list: Array = mod_bundle.get("byStat", {}).get(stat_id, [])
	var children: Array[Dictionary] = []
	var base: float = float(definition.get("base", 0.0))
	var active_overrides: Array[Dictionary] = []
	for modifier_value: Variant in list:
		if modifier_value is Dictionary and modifier_value.get("op") == "OVERRIDE" and eval_condition(modifier_value.get("condition", {}), context):
			active_overrides.append(modifier_value)
	if not active_overrides.is_empty():
		var chosen: Dictionary = active_overrides[active_overrides.size() - 1]
		base = float(chosen.get("value", base))
		children.append(_trace.make_node("BASE", "база (override)", base, {
			"sourceId": chosen.get("sourceId", ""), "sourceName": chosen.get("sourceName", ""), "sourceKind": chosen.get("sourceKind", "base"),
			"unit": definition.get("unit", ""), "localizedExplanation": "База переопределена: %s" % chosen.get("sourceName", ""), "inputs": [base],
		}))
	else:
		children.append(_trace.make_node("BASE", "база", base, {
			"sourceId": "base:%s" % stat_id, "sourceName": definition.get("name", stat_id), "sourceKind": "base", "unit": definition.get("unit", ""),
			"localizedExplanation": definition.get("desc", ""), "inputs": [base],
		}))
	for modifier_value: Variant in list:
		if not modifier_value is Dictionary or modifier_value.get("op") != "BASE" or not eval_condition(modifier_value.get("condition", {}), context):
			continue
		var modifier: Dictionary = modifier_value
		base += float(modifier.get("value", 0.0))
		children.append(_trace.make_node("ADD", "база", base, {
			"sourceId": modifier.get("sourceId", ""), "sourceName": modifier.get("sourceName", ""), "sourceKind": modifier.get("sourceKind", "base"),
			"unit": definition.get("unit", ""), "inputs": [modifier.get("value", 0.0)], "conditionPredicate": condition_text(modifier.get("condition", {})) if modifier.has("condition") else null,
			"conditionActive": true, "localizedExplanation": "%s: +%s к базе" % [modifier.get("sourceName", ""), modifier.get("value", 0.0)],
		}))
	var flat_sum: float = 0.0
	for modifier_value: Variant in list:
		if not modifier_value is Dictionary or modifier_value.get("op") != "FLAT":
			continue
		var modifier: Dictionary = modifier_value
		var active: bool = eval_condition(modifier.get("condition", {}), context)
		var amount: float = float(modifier.get("value", 0.0))
		if active:
			flat_sum += amount
		var flat_options: Dictionary = {
			"sourceId": modifier.get("sourceId", ""), "sourceName": modifier.get("sourceName", ""), "sourceKind": modifier.get("sourceKind", "base"),
			"unit": definition.get("unit", ""), "inputs": [amount], "conditionActive": active,
			"localizedExplanation": "%s: %s%s %s%s" % [modifier.get("sourceName", ""), "+" if amount >= 0.0 else "", amount, definition.get("unit", ""), " (%s)" % modifier["note"] if modifier.has("note") else ""],
		}
		if modifier.has("condition"):
			flat_options["conditionPredicate"] = condition_text(modifier["condition"])
		if bool(modifier.get("synScalable", false)):
			flat_options["tags"] = ["SYN_SCALABLE"]
		children.append(_trace.make_node("ADD", "плоские", amount, flat_options))
	var value: float = base + flat_sum
	children.append(_trace.make_node("SUM", "плоские", value, {
		"sourceId": "sum:%s" % stat_id, "sourceName": "База + плоские", "unit": definition.get("unit", ""), "inputs": [base, flat_sum],
		"localizedExplanation": "%s + %s = %s" % [base, flat_sum, value],
	}))
	var operation: String = ""
	for modifier_value: Variant in list:
		if modifier_value is Dictionary and modifier_value.get("op") == "INCREASED":
			operation = "INCREASED"
			break
	if bool(definition.get("increasedAsValue", false)):
		var groups: Dictionary = _increased_groups(list, context, stat_id, children)
		var factor: float = 1.0 + value / 100.0
		for group_key: Variant in groups.keys():
			var entry: Dictionary = groups[group_key]
			var group_factor: float = 1.0 + float(entry["sum"]) / 100.0
			factor *= group_factor
			value = (factor - 1.0) * 100.0
			children.append(_trace.make_node("MULTIPLY", "эффективный %s" % _group_label(group_key), value, {
				"sourceId": "group:%s" % group_key, "sourceName": "Группа %s" % group_key, "unit": "%", "inputs": [entry["sum"], group_factor],
				"localizedExplanation": "Группа %s: %s%% → ×%s; эффективный бонус %s%%" % [group_key, entry["sum"], group_factor, value],
			}))
	elif not bool(definition.get("additiveOnly", false)) and not bool(definition.get("multiplier", false)):
		var groups: Dictionary = _increased_groups(list, context, stat_id, children)
		for group_key: Variant in groups.keys():
			var entry: Dictionary = groups[group_key]
			var group_factor: float = 1.0 + float(entry["sum"]) / 100.0
			value *= group_factor
			children.append(_trace.make_node("MULTIPLY", "складывающиеся %% %s" % _group_label(group_key), value, {
				"sourceId": "group:%s" % group_key, "sourceName": "Группа %s" % group_key, "unit": "×", "inputs": [entry["sum"], group_factor],
				"localizedExplanation": "Сумма группы %s: %s%% → ×%s" % [group_key, entry["sum"], group_factor],
			}))
		for modifier_value: Variant in list:
			if not modifier_value is Dictionary or not ["MORE", "LESS"].has(modifier_value.get("op")):
				continue
			var modifier: Dictionary = modifier_value
			var active: bool = eval_condition(modifier.get("condition", {}), context)
			var factor: float = float(modifier.get("value", 1.0)) if modifier.get("op") == "MORE" else 1.0 - _formula.clamp_value(float(modifier.get("value", 0.0)), 0.0, 1.0)
			if active:
				value *= factor
			children.append(_multiplier_trace(modifier, active, factor, "независимые множители"))
	elif bool(definition.get("multiplier", false)):
		for modifier_value: Variant in list:
			if not modifier_value is Dictionary or not ["MORE", "LESS", "INCREASED"].has(modifier_value.get("op")):
				continue
			var modifier: Dictionary = modifier_value
			var active: bool = eval_condition(modifier.get("condition", {}), context)
			var factor: float = _modifier_factor(modifier)
			if active:
				value *= factor
			children.append(_multiplier_trace(modifier, active, factor, "независимые множители"))
		for modifier_value: Variant in list:
			if not modifier_value is Dictionary or modifier_value.get("op") != "FLAT":
				continue
			var modifier: Dictionary = modifier_value
			var active: bool = eval_condition(modifier.get("condition", {}), context)
			var amount: float = float(modifier.get("value", 0.0))
			if active:
				value += amount
			children.append(_trace.make_node("ADD", "плоские", amount, {
					"sourceId": modifier.get("sourceId", ""), "sourceName": modifier.get("sourceName", ""), "sourceKind": modifier.get("sourceKind", "base"), "unit": definition.get("unit", ""),
					"conditionPredicate": condition_text(modifier["condition"]) if modifier.has("condition") else null, "conditionActive": active,
					"localizedExplanation": "%s: +%s" % [modifier.get("sourceName", ""), amount],
				}))
	for conversion_value: Variant in mod_bundle.get("conversions", []):
		if not conversion_value is Dictionary or conversion_value.get("to") != stat_id:
			continue
		var conversion: Dictionary = conversion_value
		var active: bool = eval_condition(conversion.get("condition", {}), context)
		var source_stat: String = str(conversion.get("from", ""))
		var source_value: float = float(precomputed[source_stat]) if precomputed.has(source_stat) else float(compute_stat(source_stat, mod_bundle, context, {}, fingerprint).get("value", 0.0))
		var added: float = source_value * float(conversion.get("ratio", 0.0)) if active else 0.0
		value += added
		var conversion_options: Dictionary = {
			"sourceId": conversion.get("sourceId", ""), "sourceName": conversion.get("sourceName", ""), "sourceKind": conversion.get("sourceKind", "base"),
			"unit": definition.get("unit", ""), "inputs": [source_value, conversion.get("ratio", 0.0), added],
			"conditionActive": active, "snapshot": conversion.get("policy") == "snapshot",
			"localizedExplanation": "%s: %s × %s (%s) = %s" % [conversion.get("sourceName", ""), conversion.get("ratio", 0.0), source_stat, source_value, added],
		}
		if conversion.has("condition"):
			conversion_options["conditionPredicate"] = condition_text(conversion["condition"])
		children.append(_trace.make_node("CONVERT", "конверсия", added, conversion_options))
	var before_clamp: float = value
	var lower: float = float(definition.get("min", -INF))
	var upper: float = float(definition.get("max", INF))
	for modifier_value: Variant in list:
		if not modifier_value is Dictionary or not eval_condition(modifier_value.get("condition", {}), context):
			continue
		if modifier_value.get("op") == "CAP":
			upper = minf(upper, float(modifier_value.get("value", upper)))
		elif modifier_value.get("op") == "FLOOR":
			lower = maxf(lower, float(modifier_value.get("value", lower)))
	value = _formula.clamp_value(value, lower, upper)
	if bool(definition.get("integer", false)):
		value = floor(value + 0.5)
	value = _formula.finite_value(value, float(definition.get("base", 0.0)))
	if before_clamp != value or lower != -INF or upper != INF:
		children.append(_trace.make_node("CLAMP", "ограничение", value, {
			"sourceId": "cap:%s" % stat_id, "sourceName": "Пределы реестра", "unit": definition.get("unit", ""), "inputs": [before_clamp, lower, upper],
			"localizedExplanation": "Ограничение [%s; %s] → %s" % [_bound_text(lower, "−∞"), _bound_text(upper, "∞"), value],
		}))
	var trace: Dictionary = _trace.make_node("SUM", "итог", value, {
		"id": "stat:%s" % stat_id, "sourceId": stat_id, "sourceName": definition.get("name", stat_id), "unit": definition.get("unit", ""),
		"inputs": [base, flat_sum], "children": children, "localizedExplanation": "%s = %s %s" % [definition.get("name", stat_id), value, definition.get("unit", "")],
	})
	return {"statId": stat_id, "value": value, "unit": definition.get("unit", ""), "trace": trace, "contextFingerprint": fingerprint}

func conversion_order(conversions: Array[Dictionary]) -> Dictionary:
	var dependencies: Dictionary = {}
	for conversion: Dictionary in conversions:
		var destination: String = str(conversion.get("to", ""))
		var source: String = str(conversion.get("from", ""))
		if not dependencies.has(destination):
			dependencies[destination] = []
		var sources: Array = dependencies[destination]
		if not sources.has(source):
			sources.append(source)
		dependencies[destination] = sources
	var order: Array[String] = []
	var visiting: Array[String] = []
	var visited: Dictionary = {}
	for stat_id: String in _ids:
		var result: Dictionary = _visit_conversion(stat_id, dependencies, visiting, visited, order)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true, "order": order, "error": ""}

func resolve_stats(mod_bundle: Dictionary, context: Dictionary = {}, requested_order: Array[String] = []) -> Dictionary:
	var mods: Array[Dictionary] = _dictionary_array(mod_bundle.get("mods", []))
	var fingerprint: String = condition_signature(mods, context)
	var sequence: Array[String] = requested_order
	if sequence.is_empty():
		var ordering: Dictionary = conversion_order(_dictionary_array(mod_bundle.get("conversions", [])))
		if not bool(ordering.get("ok", false)):
			return {"_error": ordering.get("error", "conversion order failed")}
		sequence = ordering["order"]
	var sheet: Dictionary = {}
	var results: Dictionary = {}
	for stat_id: String in sequence:
		var computed: Dictionary = compute_stat(stat_id, mod_bundle, context, sheet, fingerprint)
		if computed.is_empty():
			continue
		sheet[stat_id] = computed["value"]
		results[stat_id] = computed
	return results

func sheet_of(results: Dictionary) -> Dictionary:
	var sheet: Dictionary = {}
	for stat_id: String in _ids:
		sheet[stat_id] = results[stat_id]["value"] if results.has(stat_id) else float(_registry[stat_id].get("base", 0.0))
	return sheet

func empty_sheet() -> Dictionary:
	var sheet: Dictionary = {}
	for stat_id: String in _ids:
		sheet[stat_id] = float(_registry[stat_id].get("base", 0.0))
	return sheet

func _increased_groups(modifiers: Array, context: Dictionary, stat_id: String, children: Array[Dictionary]) -> Dictionary:
	var groups: Dictionary = {}
	for modifier_value: Variant in modifiers:
		if not modifier_value is Dictionary or modifier_value.get("op") != "INCREASED":
			continue
		var modifier: Dictionary = modifier_value
		var group_key: String = str(modifier.get("stackGroup", stat_id))
		if not groups.has(group_key):
			groups[group_key] = {"sum": 0.0, "members": []}
		var entry: Dictionary = groups[group_key]
		var active: bool = eval_condition(modifier.get("condition", {}), context)
		if active:
			entry["sum"] = float(entry["sum"]) + float(modifier.get("value", 0.0))
		entry["members"].append(modifier)
		groups[group_key] = entry
		var options: Dictionary = {
			"sourceId": modifier.get("sourceId", ""), "sourceName": modifier.get("sourceName", ""), "sourceKind": modifier.get("sourceKind", "base"), "unit": "%",
			"inputs": [modifier.get("value", 0.0)], "conditionActive": active,
			"localizedExplanation": "%s: %s%% к группе %s" % [modifier.get("sourceName", ""), modifier.get("value", 0.0), group_key],
		}
		if modifier.has("condition"):
			options["conditionPredicate"] = condition_text(modifier["condition"])
		children.append(_trace.make_node("ADD", "складывающиеся %s [%s]" % ["%", group_key], float(modifier.get("value", 0.0)), options))
	return groups

func _multiplier_trace(modifier: Dictionary, active: bool, factor: float, stage: String) -> Dictionary:
	var operation: String = str(modifier.get("op", ""))
	var amount: float = float(modifier.get("value", 0.0))
	var explanation: String = "%s: ×%s MORE" % [modifier.get("sourceName", ""), amount] if operation == "MORE" else "%s: −%s%% LESS" % [modifier.get("sourceName", ""), amount * 100.0]
	var options: Dictionary = {
		"sourceId": modifier.get("sourceId", ""), "sourceName": modifier.get("sourceName", ""), "sourceKind": modifier.get("sourceKind", "base"), "unit": "×",
		"inputs": [amount, factor], "conditionActive": active, "localizedExplanation": explanation,
	}
	if modifier.has("condition"):
		options["conditionPredicate"] = condition_text(modifier["condition"])
	return _trace.make_node("MULTIPLY", stage, factor, options)

func _modifier_factor(modifier: Dictionary) -> float:
	var amount: float = float(modifier.get("value", 0.0))
	match str(modifier.get("op", "")):
		"MORE": return amount
		"LESS": return 1.0 - _formula.clamp_value(amount, 0.0, 1.0)
		"INCREASED": return 1.0 + amount / 100.0
	return 1.0

func _visit_conversion(stat_id: String, dependencies: Dictionary, visiting: Array[String], visited: Dictionary, order: Array[String]) -> Dictionary:
	if visited.has(stat_id):
		return {"ok": true}
	if visiting.has(stat_id):
		var cycle: Array[String] = visiting.duplicate()
		cycle.append(stat_id)
		return {"ok": false, "error": "Цикл конверсий: %s" % " → ".join(cycle)}
	visiting.append(stat_id)
	for dependency_value: Variant in dependencies.get(stat_id, []):
		var dependency_result: Dictionary = _visit_conversion(str(dependency_value), dependencies, visiting, visited, order)
		if not bool(dependency_result.get("ok", false)):
			return dependency_result
	visiting.pop_back()
	visited[stat_id] = true
	order.append(stat_id)
	return {"ok": true}

func _dictionary_array(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				result.append(value)
	return result

func _group_label(group_key: Variant) -> String:
	return "[%s]" % group_key

func _bound_text(value: float, fallback: String) -> String:
	return fallback if is_inf(value) else str(value)
