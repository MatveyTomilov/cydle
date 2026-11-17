extends "res://tests/test_case.gd"

const STATS_PATH: String = "res://scripts/core/math/stats.gd"

func run(_tree: SceneTree) -> bool:
	var stats_script: Script = load(STATS_PATH) as Script
	if not check(stats_script != null, "stats_golden: stat resolver implementation is missing"):
		return false
	var stats: Object = stats_script.new()
	var source: Dictionary = {"id": "test", "name": "Тест", "kind": "base"}
	check(stats.call("stat_ids").size() == 85, "stats_golden: legacy stat registry is incomplete")

	var armor_modifiers: Array[Dictionary] = [
		stats.call("make_modifier", "armor", "FLAT", 2.0, source),
		stats.call("make_modifier", "armor", "INCREASED", 20.0, {"id": "implant", "name": "Имплант", "kind": "implant"}),
		stats.call("make_modifier", "armor", "MORE", 1.1, {"id": "more", "name": "Усиление", "kind": "item"}),
	]
	var armor_results: Dictionary = stats.call("resolve_stats", stats.call("bundle", armor_modifiers))
	check(_near(float(armor_results["armor"]["value"]), 9.24), "stats_golden: base + flat + increased + more differs from TypeScript")
	check(_near(float(armor_results["armor"]["trace"]["exactValue"]), 9.24), "stats_golden: final stat trace differs from resolved value")

	var damage_modifiers: Array[Dictionary] = [
		stats.call("make_modifier", "kineticDamage", "INCREASED", 20.0, {"id": "attribute", "name": "Атрибут", "kind": "attribute"}),
		stats.call("make_modifier", "kineticDamage", "INCREASED", 30.0, {"id": "tree", "name": "Древо", "kind": "tree"}),
	]
	var damage_results: Dictionary = stats.call("resolve_stats", stats.call("bundle", damage_modifiers))
	check(float(damage_results["kineticDamage"]["value"]) == 50.0, "stats_golden: percentage-valued stat differs from TypeScript")

	var grouped_modifiers: Array[Dictionary] = [
		stats.call("make_modifier", "kineticDamage", "INCREASED", 20.0, source, {"stackGroup": "A"}),
		stats.call("make_modifier", "kineticDamage", "INCREASED", 30.0, source, {"stackGroup": "B"}),
	]
	var grouped_results: Dictionary = stats.call("resolve_stats", stats.call("bundle", grouped_modifiers))
	check(_near(float(grouped_results["kineticDamage"]["value"]), 56.0), "stats_golden: independent increased groups should multiply")

	var context: Dictionary = {
		"self": {"hp": 40.0, "maxHP": 100.0, "shield": 10.0, "maxShield": 50.0, "energy": 25.0, "heat": 90.0, "statuses": {}},
		"target": {"hp": 20.0, "maxHP": 100.0, "shield": 0.0, "maxShield": 0.0, "energy": 0.0, "heat": 0.0, "statuses": {"BURN": 2}, "isBoss": true},
		"enemiesAlive": 2, "dronesAlive": 1, "timeMs": 3000, "heatLockout": true,
		"flags": {"hot": 1}, "uniques": ["U01"],
	}
	check(bool(stats.call("eval_condition", {"kind": "hpBelow", "value": 0.5}, context)), "stats_golden: HP threshold condition differs")
	check(bool(stats.call("eval_condition", {"kind": "targetStatus", "status": "BURN", "minStacks": 2}, context)), "stats_golden: target status condition differs")
	check(bool(stats.call("eval_condition", {"kind": "targetHpBelow", "value": 0.3}, context)), "stats_golden: target HP condition differs")
	check(bool(stats.call("eval_condition", {"kind": "heatLockout"}, context)), "stats_golden: heat lockout condition differs")
	check(bool(stats.call("eval_condition", {"kind": "firstSeconds", "value": 3.0}, context)), "stats_golden: time boundary condition differs")
	check(String(stats.call("condition_text", {"kind": "all", "inner": [{"kind": "hpBelow", "value": 0.5}, {"kind": "hasUnique", "id": "U01"}]})) == "HP < 50% И экипирован U01", "stats_golden: localized condition explanation differs")

	var conversion: Dictionary = {"id": "c1", "from": "armor", "to": "evasion", "ratio": 0.5, "sourceId": "conversion", "sourceName": "Armor link", "sourceKind": "unique", "policy": "snapshot", "stage": 0}
	var no_modifiers: Array[Dictionary] = []
	var conversions: Array[Dictionary] = [conversion]
	var converted: Dictionary = stats.call("resolve_stats", stats.call("bundle", no_modifiers, conversions))
	check(float(converted["evasion"]["value"]) == 22.5, "stats_golden: conversion graph resolution differs from TypeScript")
	check(failure_count == 0, "stats_golden: one or more legacy fixtures failed")
	return failure_count == 0

func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= 0.000000000001
