class_name CalcTrace
extends RefCounted

const FORMULA_VERSION: String = "cydle-math-1.0"
var _counter: int = 0

func next_trace_id(prefix: String = "t") -> String:
	_counter = (_counter + 1) % 1000000
	return "%s%d" % [prefix, _counter]

func make_node(operation: String, stage: String, exact_value: float, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"id": str(options.get("id", next_trace_id())),
		"operation": operation,
		"stage": stage,
		"inputs": options.get("inputs", []),
		"exactValue": exact_value,
		"sourceId": str(options.get("sourceId", "engine")),
		"sourceName": str(options.get("sourceName", "Движок")),
		"sourceKind": str(options.get("sourceKind", "base")),
		"unit": str(options.get("unit", "")),
		"localizedExplanation": str(options.get("localizedExplanation", "")),
		"formulaVersion": FORMULA_VERSION,
	}
	for optional_key: String in ["conditionPredicate", "conditionActive", "tags", "children", "snapshot"]:
		if options.has(optional_key):
			result[optional_key] = options[optional_key]
	return result

func format_value(value: float, exact: bool = false, decimals: int = 2) -> String:
	if not is_finite(value):
		return "—"
	if exact:
		return str(value)
	var multiplier: float = pow(10.0, float(decimals))
	var rounded: float = floor(value * multiplier + 0.5) / multiplier
	return str(rounded)

func format_percent(value: float, exact: bool = false) -> String:
	return "%s%%" % format_value(value * 100.0, exact)
