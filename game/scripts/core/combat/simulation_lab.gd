class_name SimulationLab
extends RefCounted

const MAX_BATCH_RUNS: int = 20
const TICK_MS: int = 100

func compare_builds(build_a: Dictionary, build_b: Dictionary, enemy_specs: Array, tactics: Dictionary, depth: int, biome: String, runs: int, seed: String) -> Dictionary:
	if build_a.is_empty() or build_b.is_empty() or enemy_specs.is_empty() or tactics.is_empty():
		return _failure("Симуляции нужны две сборки, сценарий врагов и профиль тактики.")
	if depth < 1 or runs < 1 or runs > MAX_BATCH_RUNS or seed.is_empty():
		return _failure("Параметры лаборатории вне допустимых границ.")
	var totals: Array[Dictionary] = [_empty_totals(), _empty_totals()]
	for run_index: int in range(runs):
		var scenario_seed: String = "%s:%s:%d" % [seed, str(enemy_specs), run_index]
		for build_index: int in range(2):
			var build: Dictionary = build_a if build_index == 0 else build_b
			var simulator: CombatSimulator = CombatSimulator.new()
			var initialized: Dictionary = simulator.create_state({
				"seed": scenario_seed, "depth": depth, "biome": biome, "nodeType": "COMBAT",
				"build": build, "enemies": enemy_specs.duplicate(true), "tactics": tactics.duplicate(true),
				"recordLog": false,
			})
			if not bool(initialized.get("ok", false)):
				return _failure("Симуляция %d/%d не запустилась: %s" % [run_index + 1, build_index + 1, str(initialized.get("error", "unknown"))])
			var combat: CombatState = initialized["state"] as CombatState
			var steps: int = 0
			while combat.outcome.is_empty() and steps < int(ceil(float(combat.max_duration_ms) / float(TICK_MS))):
				var advanced: Dictionary = simulator.step_combat(combat)
				if not bool(advanced.get("ok", false)):
					return _failure("Симуляция %d/%d остановилась на %d мс: %s (триггеры=%s; enabled rules=%s)" % [run_index + 1, build_index + 1, combat.time_ms, str(advanced.get("error", "unknown")), str(build.get("triggerEffects", [])), str(tactics.get("rules", []))])
				combat = advanced["state"] as CombatState
				steps += 1
			if combat.outcome.is_empty():
				return _failure("Симуляция не достигла результата за установленный лимит.")
			_accumulate(totals[build_index], combat)
	return {"ok": true, "runs": runs, "results": [_finish(totals[0], runs), _finish(totals[1], runs)], "error": ""}

func _empty_totals() -> Dictionary:
	return {"wins": 0, "defeats": 0, "timeouts": 0, "damageDealt": 0.0, "damageTaken": 0.0, "timeMs": 0.0, "hpFraction": 0.0, "lowHpFraction": 0.0}

func _accumulate(totals: Dictionary, combat: CombatState) -> void:
	match combat.outcome:
		"VICTORY": totals["wins"] += 1
		"DEFEAT": totals["defeats"] += 1
		_: totals["timeouts"] += 1
	totals["damageDealt"] = float(totals["damageDealt"]) + float(combat.metrics.get("damageDealt", 0.0))
	totals["damageTaken"] = float(totals["damageTaken"]) + float(combat.metrics.get("damageTaken", 0.0))
	totals["timeMs"] = float(totals["timeMs"]) + float(combat.time_ms)
	var max_hp: float = maxf(1.0, float(combat.operator.base_sheet.get("maxHP", 1.0)))
	totals["hpFraction"] = float(totals["hpFraction"]) + combat.operator.hp / max_hp
	totals["lowHpFraction"] = float(totals["lowHpFraction"]) + float(combat.metrics.get("lowestHpFraction", 1.0))

func _finish(totals: Dictionary, runs: int) -> Dictionary:
	return {
		"winRate": float(totals["wins"]) / float(runs), "defeats": int(totals["defeats"]), "timeouts": int(totals["timeouts"]),
		"averageDamageDealt": float(totals["damageDealt"]) / float(runs), "averageDamageTaken": float(totals["damageTaken"]) / float(runs),
		"averageTimeMs": float(totals["timeMs"]) / float(runs), "averageHpFraction": float(totals["hpFraction"]) / float(runs),
		"averageLowHpFraction": float(totals["lowHpFraction"]) / float(runs),
	}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "runs": 0, "results": [], "error": message}
