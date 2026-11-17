class_name DamageMath
extends RefCounted

const ZERO_PENETRATION: Dictionary = {
	"armorPen": 0.0, "armorPenPercent": 0.0,
	"energyPen": 0.0, "energyPenPercent": 0.0,
	"digitalPen": 0.0, "digitalPenPercent": 0.0,
}

var _formula: CydleFormula = CydleFormula.new()
var _trace: CalcTrace = CalcTrace.new()

func hit_probability(accuracy: float, evasion: float) -> float:
	var safe_accuracy: float = maxf(0.000000001, accuracy)
	return _formula.clamp_value(safe_accuracy / (safe_accuracy + maxf(0.0, evasion)), 0.05, 0.99)

func crit_probability(crit_chance_points: float) -> float:
	return _formula.clamp_value(crit_chance_points / 100.0, 0.0, 0.95)

func armor_effective(armor: float, flat_penetration: float, percent_penetration_points: float) -> float:
	return maxf(0.0, (armor - flat_penetration) * (1.0 - _formula.clamp_value(percent_penetration_points / 100.0, 0.0, 1.0)))

func kinetic_reduction(effective_armor: float) -> float:
	return minf(0.85, effective_armor / (effective_armor + 100.0))

func resistance_after_penetration(resistance_points: float, percent_penetration_points: float, flat_penetration_points: float) -> float:
	var resistance: float = resistance_points / 100.0
	var percent: float = _formula.clamp_value(percent_penetration_points / 100.0, 0.0, 1.0)
	var after_penetration: float = resistance - maxf(0.0, resistance) * percent - flat_penetration_points / 100.0
	return clampf(after_penetration, -0.5, 0.75)

func mitigate_packet(raw_damage: float, damage_type: String, defense: Dictionary, penetration: Dictionary) -> Dictionary:
	var effective_armor: float = 0.0
	var reduction: float = 0.0
	var resistance_after: float = 0.0
	if damage_type == "KINETIC":
		effective_armor = armor_effective(float(defense.get("armor", 0.0)), float(penetration.get("armorPen", 0.0)), float(penetration.get("armorPenPercent", 0.0)))
		reduction = kinetic_reduction(effective_armor)
	elif damage_type == "ENERGY":
		resistance_after = resistance_after_penetration(float(defense.get("energyRes", 0.0)), float(penetration.get("energyPenPercent", 0.0)), float(penetration.get("energyPen", 0.0)))
		reduction = resistance_after
	else:
		resistance_after = resistance_after_penetration(float(defense.get("digitalRes", 0.0)), float(penetration.get("digitalPenPercent", 0.0)), float(penetration.get("digitalPen", 0.0)))
		reduction = resistance_after
	var after_defense: float = raw_damage * (1.0 - reduction)
	var selected_defense: float = effective_armor if damage_type == "KINETIC" else resistance_after
	var penetration_values: Array[float] = []
	if damage_type == "KINETIC":
		penetration_values = [float(defense.get("armor", 0.0)), float(penetration.get("armorPen", 0.0)), float(penetration.get("armorPenPercent", 0.0))]
	else:
		var key_prefix: String = "energy" if damage_type == "ENERGY" else "digital"
		penetration_values = [float(defense.get("energyRes" if damage_type == "ENERGY" else "digitalRes", 0.0)), float(penetration.get(key_prefix + "Pen", 0.0)), float(penetration.get(key_prefix + "PenPercent", 0.0))]
	var penetration_trace: Dictionary = _trace.make_node("DIVIDE", "пробитие", selected_defense, {
		"sourceId": "pen", "sourceName": "Пробитие", "unit": "ед." if damage_type == "KINETIC" else "доля",
		"inputs": penetration_values, "localizedExplanation": "Пробитие применяется один раз к защите пакета",
	})
	var defense_name: String = "Броня цели" if damage_type == "KINETIC" else "Сопротивление энергии" if damage_type == "ENERGY" else "Сопротивление цифре"
	var explanation: String
	if damage_type == "KINETIC":
		var flat_armor_penetration: float = float(penetration.get("armorPen", 0.0))
		var armor_percent_penetration: float = float(penetration.get("armorPenPercent", 0.0)) / 100.0
		explanation = "armorEff = max(0,(%s − %s) × (1 − %s)) = %s; снижение = %s/(%s+100) = %s; %s × (1 − %s) = %s" % [defense.get("armor", 0.0), flat_armor_penetration, armor_percent_penetration, effective_armor, effective_armor, effective_armor, reduction, raw_damage, reduction, after_defense]
	else:
		explanation = "res после пробития = %s; %s × (1 − %s) = %s" % [resistance_after, raw_damage, resistance_after, after_defense]
	var trace: Dictionary = _trace.make_node("MULTIPLY", "защита", after_defense, {
		"sourceId": "defense:%s" % damage_type, "sourceName": defense_name, "unit": "ед.",
		"inputs": [raw_damage, effective_armor, reduction, after_defense],
		"localizedExplanation": explanation,
		"children": [penetration_trace],
	})
	return {"type": damage_type, "raw": raw_damage, "armorEff": effective_armor, "reduction": reduction, "resistanceAfterPen": resistance_after, "afterDefense": after_defense, "trace": trace}

func partition_damage(incoming: float, pools: Dictionary, bypass_shield_ratio: float, incoming_shield_multiplier: float = 1.0) -> Dictionary:
	var amount: float = maxf(0.0, _formula.finite_value(incoming, 0.0))
	var bypassed: float = amount * _formula.clamp_value(bypass_shield_ratio, 0.0, 1.0)
	var remaining: float = amount - bypassed
	var shield_multiplier: float = maxf(0.0, _formula.finite_value(incoming_shield_multiplier, 1.0))
	var consumed: Array[Dictionary] = []
	var shield_consumed: float = 0.0
	var temporary_pools: Array[Dictionary] = []
	for pool_value: Variant in pools.get("temp", []):
		if pool_value is Dictionary:
			temporary_pools.append(pool_value.duplicate())
	temporary_pools.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_expiry: float = float(left.get("expiresAt", 0.0))
		var right_expiry: float = float(right.get("expiresAt", 0.0))
		if left_expiry == right_expiry:
			return str(left.get("sourceId", "")) < str(right.get("sourceId", ""))
		return left_expiry < right_expiry)
	for pool: Dictionary in temporary_pools:
		if remaining <= 0.0:
			break
		var taken: float = _absorb(float(pool.get("amount", 0.0)), remaining, shield_multiplier)
		remaining -= taken / shield_multiplier if shield_multiplier > 0.0 else 0.0
		shield_consumed += taken
		if taken > 0.0:
			consumed.append({"sourceId": str(pool.get("sourceId", "")), "amount": taken})
	var ordinary_taken: float = _absorb(float(pools.get("shield", 0.0)), remaining, shield_multiplier)
	remaining -= ordinary_taken / shield_multiplier if shield_multiplier > 0.0 else 0.0
	shield_consumed += ordinary_taken
	var hp_damage: float = bypassed + remaining
	var hp_available: float = maxf(0.0, _formula.finite_value(float(pools.get("hp", 0.0)), 0.0))
	var hp_lost: float = minf(hp_available, hp_damage)
	var overkill: float = maxf(0.0, hp_damage - hp_available)
	var trace: Dictionary = _trace.make_node("SUM", "щиты/HP", amount, {
		"sourceId": "partition", "sourceName": "Распределение урона", "unit": "ед.",
		"inputs": [amount, bypassed, shield_multiplier, shield_consumed, hp_lost, overkill],
		"localizedExplanation": "Обход щита %s, множитель урона по щиту ×%s, поглощено щитом %s, потеря HP %s%s" % [bypassed, shield_multiplier, shield_consumed, hp_lost, ", overkill %s" % overkill if overkill > 0.0 else ""],
	})
	return {"shieldConsumed": shield_consumed, "tempConsumed": consumed, "hpLost": hp_lost, "bypassed": bypassed, "overkill": overkill, "trace": trace}

func simple_ehp(hp: float, shield: float, defense: Dictionary, damage_type: String, penetration: Dictionary = ZERO_PENETRATION) -> float:
	var mitigation: Dictionary = mitigate_packet(1.0, damage_type, defense, penetration)
	var damage_factor: float = 1.0 - float(mitigation["reduction"])
	if damage_factor <= 0.0:
		return INF
	return (hp + shield) / damage_factor

func _absorb(available: float, remaining: float, multiplier: float) -> float:
	if remaining <= 0.0 or multiplier <= 0.0:
		return 0.0
	return minf(maxf(0.0, available), remaining * multiplier)
