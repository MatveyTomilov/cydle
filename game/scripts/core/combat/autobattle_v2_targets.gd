class_name AutobattleV2Targets
extends RefCounted

func resolve(state: CombatState, doctrine: AutobattleV2Contract.Doctrine, focus_id: String = "", seeded_roll: int = 0) -> Dictionary:
	var name: String = AutobattleV2Contract.target_name(doctrine)
	if name.is_empty():
		return {"ok": false, "error": "UNSUPPORTED_TARGET_DOCTRINE:%s" % str(doctrine), "targets": []}
	if doctrine == AutobattleV2Contract.Doctrine.SELF: return {"ok": true, "error": "", "targets": [state.operator.id]}
	if doctrine == AutobattleV2Contract.Doctrine.ALLY:
		var allies: Array[String] = []
		for ally: CombatActorState in state.allies:
			if ally.alive: allies.append(ally.id)
		allies.sort()
		return {"ok": true, "error": "", "targets": allies}
	var living: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive: living.append(enemy)
	living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.id < b.id)
	var fallback_living: Array[CombatActorState] = living.duplicate()
	if doctrine == AutobattleV2Contract.Doctrine.INFECTED:
		living = living.filter(func(e: CombatActorState) -> bool: return e.statuses.has("VIRUS"))
	elif doctrine == AutobattleV2Contract.Doctrine.BOSS:
		living = living.filter(func(e: CombatActorState) -> bool: return e.is_boss)
	elif doctrine == AutobattleV2Contract.Doctrine.MARKED:
		living = living.filter(func(e: CombatActorState) -> bool: return e.statuses.has("MARK") or e.statuses.has("SCAN_MARK") or e.statuses.has("DRONE_MARK"))
	if living.is_empty() and doctrine in [AutobattleV2Contract.Doctrine.INFECTED, AutobattleV2Contract.Doctrine.BOSS, AutobattleV2Contract.Doctrine.MARKED]:
		living = fallback_living
	if living.is_empty(): return {"ok": true, "error": "", "targets": []}
	if doctrine in [AutobattleV2Contract.Doctrine.ALL_ENEMIES, AutobattleV2Contract.Doctrine.ALL]:
		var ids: Array[String] = []
		for enemy: CombatActorState in living: ids.append(enemy.id)
		return {"ok": true, "error": "", "targets": ids}
	if doctrine == AutobattleV2Contract.Doctrine.FOCUS:
		for enemy: CombatActorState in living:
			if enemy.id == focus_id: return {"ok": true, "error": "", "targets": [enemy.id]}
	if doctrine == AutobattleV2Contract.Doctrine.RANDOM_SEEDED:
		return {"ok": true, "error": "", "targets": [living[posmod(seeded_roll, living.size())].id]}
	if doctrine == AutobattleV2Contract.Doctrine.LOWEST_HP:
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.hp < b.hp if not is_equal_approx(a.hp, b.hp) else a.id < b.id)
	elif doctrine == AutobattleV2Contract.Doctrine.LOWEST_HP_PERCENT:
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool:
			var x: float = a.hp / maxf(1.0, float(a.base_sheet.get("maxHP", 1.0)))
			var y: float = b.hp / maxf(1.0, float(b.base_sheet.get("maxHP", 1.0)))
			return x < y if not is_equal_approx(x, y) else a.id < b.id)
	elif doctrine in [AutobattleV2Contract.Doctrine.HIGHEST_THREAT, AutobattleV2Contract.Doctrine.FOCUS]:
		living.sort_custom(func(a: CombatActorState, b: CombatActorState) -> bool: return a.threat_units > b.threat_units if a.threat_units != b.threat_units else a.id < b.id)
	return {"ok": true, "error": "", "targets": [living[0].id]}
