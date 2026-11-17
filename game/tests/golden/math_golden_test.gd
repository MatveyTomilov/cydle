extends "res://tests/test_case.gd"

const FORMULA_PATH: String = "res://scripts/core/math/formula.gd"
const DAMAGE_PATH: String = "res://scripts/core/math/damage.gd"

func run(_tree: SceneTree) -> bool:
	var formula_script: Script = load(FORMULA_PATH) as Script
	if not check(formula_script != null, "math_golden: scalar formula port is missing"):
		return false
	var damage_script: Script = load(DAMAGE_PATH) as Script
	if not check(damage_script != null, "math_golden: damage port is missing"):
		return false
	var formula: Object = formula_script.new()
	check(_near(float(formula.call("h_depth", 5)), 2.1296675679255226), "math_golden: H(T) differs from TypeScript")
	check(_near(float(formula.call("d_depth", 5)), 1.5165645386860396), "math_golden: D(T) differs from TypeScript")
	check(_near(float(formula.call("reward_scale", 13)), 2.1366816765699044), "math_golden: R(d) differs from TypeScript")
	check(int(formula.call("xp_required", 10)) == 2239, "math_golden: XP curve differs from TypeScript")
	check(_near(float(formula.call("tech_power", 80.0, 4)), 71.05809487057647), "math_golden: TechPower differs from TypeScript")
	check(_near(float(formula.call("attack_interval_ms", 1000.0, 50.0, 1.2)), 555.5555555555555), "math_golden: attack interval differs from TypeScript")
	check(float(formula.call("attack_interval_ms", 100.0, 0.0, 1.0)) == 150.0, "math_golden: minimum attack interval differs")
	check(float(formula.call("cooldown_ms", 1000.0, 25.0)) == 800.0, "math_golden: cooldown recovery differs")
	check(float(formula.call("cooldown_ms", 100.0, 0.0)) == 250.0, "math_golden: minimum cooldown differs")
	var wilson: Array[float] = formula.call("wilson_interval", 7, 10, 1.96)
	check(_near(wilson[0], 0.3967732199795652) and _near(wilson[1], 0.892210712513788), "math_golden: Wilson interval differs from TypeScript")
	var median_values: Array[float] = [9.0, 1.0, 5.0, 3.0]
	var quantile_values: Array[float] = [0.0, 10.0, 20.0]
	var mean_values: Array[float] = [2.0, 4.0, 8.0]
	check(float(formula.call("median", median_values)) == 4.0, "math_golden: median differs from TypeScript")
	check(float(formula.call("quantile", quantile_values, 0.25)) == 5.0, "math_golden: quantile differs from TypeScript")
	check(_near(float(formula.call("mean", mean_values)), 4.666666666666667), "math_golden: mean differs from TypeScript")

	var damage: Object = damage_script.new()
	check(_near(float(damage.call("hit_probability", 100.0, 20.0)), 100.0 / 120.0), "math_golden: hit chance differs from TypeScript")
	check(float(damage.call("crit_probability", 150.0)) == 0.95, "math_golden: critical chance cap differs")
	var penetration: Dictionary = {"armorPen": 0, "armorPenPercent": 0, "energyPen": 5, "energyPenPercent": 50, "digitalPen": 0, "digitalPenPercent": 0}
	var mitigated: Dictionary = damage.call("mitigate_packet", 100.0, "ENERGY", {"armor": 0, "energyRes": 50, "digitalRes": 0}, penetration)
	check(_near(float(mitigated["resistanceAfterPen"]), 0.2) and _near(float(mitigated["afterDefense"]), 80.0), "math_golden: resistance penetration differs from TypeScript")
	var partitioned: Dictionary = damage.call("partition_damage", 20.0, {
		"hp": 100.0,
		"shield": 10.0,
		"temp": [
			{"sourceId": "late", "amount": 4.0, "cap": 4.0, "expiresAt": 20},
			{"sourceId": "early", "amount": 5.0, "cap": 5.0, "expiresAt": 10},
		],
	}, 0.25, 2.0)
	check(_near(float(partitioned["bypassed"]), 5.0) and _near(float(partitioned["shieldConsumed"]), 19.0), "math_golden: shield partition differs from TypeScript")
	check(_near(float(partitioned["hpLost"]), 10.5) and float(partitioned["overkill"]) == 0.0, "math_golden: HP/overkill partition differs from TypeScript")
	var consumed: Array = partitioned["tempConsumed"]
	check(consumed.size() == 2 and consumed[0]["sourceId"] == "early" and consumed[1]["sourceId"] == "late", "math_golden: temporary shields were not consumed by expiry order")
	return failure_count == 0

func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= 0.000000000001
