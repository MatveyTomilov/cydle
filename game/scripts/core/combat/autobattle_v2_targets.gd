class_name AutobattleV2Targets
extends RefCounted

const DOCTRINES: Array[String] = ["NEAREST", "LOWEST_HP", "LOWEST_HP_PERCENT", "INFECTED", "BOSS", "ALL_ENEMIES", "SELF"]

func resolve(state: CombatState, doctrine: String) -> Dictionary:
	if not DOCTRINES.has(doctrine):
		return {"ok": false, "error": "UNSUPPORTED_TARGET_DOCTRINE:%s" % doctrine, "targets": []}
	if doctrine == "SELF": return {"ok": true, "error": "", "targets": [state.operator.id]}
	var living: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive: living.append(enemy)
	living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.id < b.id)
	if doctrine == "INFECTED":
		living = living.filter(func(e: CombatActorState) -> bool: return e.statuses.has("VIRUS"))
	elif doctrine == "BOSS":
		living = living.filter(func(e: CombatActorState) -> bool: return e.is_boss)
	if living.is_empty(): return {"ok": true, "error": "", "targets": []}
	if doctrine == "ALL_ENEMIES":
		var ids: Array[String] = []
		for enemy: CombatActorState in living: ids.append(enemy.id)
		return {"ok": true, "error": "", "targets": ids}
	if doctrine == "LOWEST_HP":
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.hp < b.hp if not is_equal_approx(a.hp, b.hp) else a.id < b.id)
	elif doctrine == "LOWEST_HP_PERCENT":
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool:
			var x: float = a.hp / maxf(1.0, float(a.base_sheet.get("maxHP", 1.0)))
			var y: float = b.hp / maxf(1.0, float(b.base_sheet.get("maxHP", 1.0)))
			return x < y if not is_equal_approx(x, y) else a.id < b.id)
	elif doctrine == "BOSS":
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.threat_units > b.threat_units if a.threat_units != b.threat_units else a.id < b.id)
	return {"ok": true, "error": "", "targets": [living[0].id]}
