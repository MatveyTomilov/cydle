class_name CydleFormula
extends RefCounted

const MIN_ATTACK_INTERVAL_MS: float = 150.0
const MIN_COOLDOWN_MS: float = 250.0
const TICK_MS: int = 100
const MAX_OFFLINE_MS: int = 43200000

func h_depth(tech_level: float) -> float:
	return pow(1.0 + 0.14 * maxf(0.0, tech_level - 1.0), 1.7)

func d_depth(tech_level: float) -> float:
	return pow(1.0 + 0.08 * maxf(0.0, tech_level - 1.0), 1.5)

func reward_scale(depth: float) -> float:
	return pow(1.0 + 0.06 * maxf(0.0, depth - 1.0), 1.4)

func xp_required(level: int) -> int:
	return floori(100.0 * pow(float(level), 1.35) + 0.5)

func tech_power(weapon_base_damage_at_tech: float, tech_level: float) -> float:
	return 0.65 * weapon_base_damage_at_tech + 0.35 * 30.0 * h_depth(tech_level)

func attack_interval_ms(base_interval: float, increased_percent: float, more_product: float) -> float:
	var value: float = base_interval / (1.0 + increased_percent / 100.0) / maxf(0.000000001, more_product)
	return maxf(MIN_ATTACK_INTERVAL_MS, value)

func cooldown_ms(base_cooldown: float, recovery_rate_percent: float) -> float:
	return maxf(MIN_COOLDOWN_MS, base_cooldown / (1.0 + recovery_rate_percent / 100.0))

func clamp_value(value: float, minimum: float, maximum: float) -> float:
	if not is_finite(value):
		return minimum
	return clampf(value, minimum, maximum)

func finite_value(value: float, fallback: float = 0.0) -> float:
	return value if is_finite(value) else fallback

func wilson_interval(successes: float, sample_count: float, z_score: float = 1.96) -> Array[float]:
	if sample_count == 0.0:
		return [0.0, 1.0]
	var proportion: float = successes / sample_count
	var denominator: float = 1.0 + z_score * z_score / sample_count
	var center: float = proportion + z_score * z_score / (2.0 * sample_count)
	var margin: float = z_score * sqrt(proportion * (1.0 - proportion) / sample_count + z_score * z_score / (4.0 * sample_count * sample_count))
	return [clamp_value((center - margin) / denominator, 0.0, 1.0), clamp_value((center + margin) / denominator, 0.0, 1.0)]

func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle: int = floori(float(sorted_values.size()) / 2.0)
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) / 2.0

func quantile(values: Array[float], quantile_value: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var position: float = clamp_value(quantile_value, 0.0, 1.0) * float(sorted_values.size() - 1)
	var low: int = floori(position)
	var high: int = ceili(position)
	return sorted_values[low] + (sorted_values[high] - sorted_values[low]) * (position - float(low))

func mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())
