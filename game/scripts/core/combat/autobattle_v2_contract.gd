class_name AutobattleV2Contract
extends RefCounted

# Isolated V2 primitive. It is NOT a replacement for CombatSimulator until
# a versioned CombatState adapter, item-authored actions, and replay tests exist.
# Runtime/UI integration must not silently reuse editable v1 tactics.
const TICK_MS: int = 100
const MIN_REACTION_INTERVAL_MS: int = 500
const MAX_CHAIN_DEPTH: int = 6
const MAX_DERIVED_EFFECTS: int = 16
const CLASS_ORDER: Array[String] = [
	"EMERGENCY_DEFENSE", "CONTROL", "DEFENSE",
	"SPECIAL_ATTACK", "BASIC_ATTACK", "UTILITY",
]
const TARGET_DOCTRINES: Array[String] = [
	"FOCUS", "NEAREST", "LOWEST_HP", "HIGHEST_THREAT",
	"LOWEST_HP_PERCENT", "INFECTED", "BOSS", "ALL_ENEMIES",
	"MARKED", "RANDOM_SEEDED", "ALL", "SELF", "ALLY",
]
const FORBIDDEN_EDITABLE_FIELDS: Array[String] = [
	"priority", "conditions", "logic", "targetPriority",
	"userRule", "when", "script", "ruleId",
]

# Candidates must already be compiled from canonical equipment/ability definitions.
# No user-defined predicates or player priority values are ever evaluated.
# Both the selected action and reasons for unavailable candidates are returned.
func select_action(actions: Array[Dictionary], now_ms: int, energy: float, heat: float, heat_max: float, thermal_locked: bool = false) -> Dictionary:
	var eligible: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for action: Dictionary in actions:
		var reason: String = _candidate_rejection(action, now_ms, energy, heat, heat_max, thermal_locked)
		if reason.is_empty():
			eligible.append(action)
		else:
			rejected.append({"actionId": str(action.get("actionId", "")), "reason": reason})
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_class: int = CLASS_ORDER.find(str(left.get("classId", "")))
		var right_class: int = CLASS_ORDER.find(str(right.get("classId", "")))
		if left_class != right_class:
			return left_class < right_class
		var left_ready: int = int(left.get("readyAtMs", 0))
		var right_ready: int = int(right.get("readyAtMs", 0))
		if left_ready != right_ready:
			return left_ready < right_ready
		return str(left.get("actionId", "")) < str(right.get("actionId", ""))
	)
	return {"action": eligible[0].duplicate(true) if not eligible.is_empty() else {}, "rejected": rejected}


func _candidate_rejection(action: Dictionary, now_ms: int, energy: float, heat: float, heat_max: float, thermal_locked: bool) -> String:
	for field: String in FORBIDDEN_EDITABLE_FIELDS:
		if action.has(field):
			return "PLAYER_RULE_FORBIDDEN"
	if str(action.get("sourceId", "")).is_empty() or str(action.get("actionId", "")).is_empty():
		return "MISSING_AUTHORED_SOURCE"
	if not str(action.get("classId", "")) in CLASS_ORDER:
		return "UNKNOWN_ACTION_CLASS"
	if not str(action.get("targetMode", "")) in TARGET_DOCTRINES:
		return "UNKNOWN_TARGET_DOCTRINE"
	if int(action.get("readyAtMs", 0)) > now_ms or int(action.get("cooldownUntilMs", 0)) > now_ms:
		return "COOLDOWN"
	if not bool(action.get("hasValidTarget", true)):
		return "NO_TARGET"
	if float(action.get("energyCost", 0.0)) > energy:
		return "ENERGY"
	if float(action.get("heatDelta", 0.0)) > 0.0:
		if thermal_locked:
			return "THERMAL_LOCK"
		# Crossing the cap commits and causes THERMAL_LOCK in the resource
		# transition. Rejecting projected heat here makes overheat unreachable.
		if heat >= heat_max:
			return "THERMAL_LOCK"
	return ""


# Actions enter PREPARE on a 100 ms boundary; cost and effects belong exclusively
# to the first COMMIT event. The caller must apply cost atomically on didCommit.
func begin_action(action: Dictionary, now_ms: int) -> Dictionary:
	var commit_at: int = now_ms + _ceil_tick(maxi(0, int(action.get("prepareMs", 0))))
	var recover_at: int = commit_at + _ceil_tick(maxi(0, int(action.get("recoveryMs", 0))))
	var ready_at: int = recover_at + _ceil_tick(maxi(0, int(action.get("cooldownMs", 0))))
	return {
		"actionId": str(action.get("actionId", "")), "phase": "PREPARE",
		"commitAtMs": commit_at, "recoveryUntilMs": recover_at,
		"readyAtMs": ready_at, "committed": false, "interrupted": false,
	}


func advance_action(timeline: Dictionary, now_ms: int) -> Dictionary:
	var next: Dictionary = timeline.duplicate(true)
	var did_commit: bool = false
	if bool(next.get("interrupted", false)):
		next["phase"] = "INTERRUPTED"
	elif not bool(next.get("committed", false)) and now_ms >= int(next.get("commitAtMs", 0)):
		next["committed"] = true
		next["phase"] = "COMMIT"
		did_commit = true
	elif not bool(next.get("committed", false)):
		next["phase"] = "PREPARE"
	elif now_ms < int(next.get("recoveryUntilMs", 0)):
		next["phase"] = "RECOVERY"
	elif now_ms < int(next.get("readyAtMs", 0)):
		next["phase"] = "COOLDOWN"
	else:
		next["phase"] = "READY"
	# The main channel is free after recovery even if this ability is cooling down.
	return {"timeline": next, "didCommit": did_commit,
		"channelReady": bool(next.get("committed", false)) and now_ms >= int(next.get("recoveryUntilMs", 0))}


func interrupt_action(timeline: Dictionary, now_ms: int) -> Dictionary:
	var next: Dictionary = timeline.duplicate(true)
	var allowed: bool = not bool(next.get("committed", false)) and not bool(next.get("interrupted", false)) and now_ms < int(next.get("commitAtMs", 0))
	if allowed:
		next["interrupted"] = true
		next["phase"] = "INTERRUPTED"
	return {"timeline": next, "interrupted": allowed}


func reaction_ready(now_ms: int, last_reaction_ms: int, internal_ready_at_ms: int) -> bool:
	return now_ms >= internal_ready_at_ms and (last_reaction_ms < 0 or now_ms - last_reaction_ms >= MIN_REACTION_INTERVAL_MS)


func new_root_ledger(root_event_id: int) -> Dictionary:
	return {"rootEventId": root_event_id, "derivedCount": 0, "firedInstances": {}}


func try_derive(ledger: Dictionary, effect_instance_id: String, parent_depth: int, repeatable: bool = false, parent_effect_instance_id: String = "") -> Dictionary:
	var next: Dictionary = ledger.duplicate(true)
	if int(next.get("rootEventId", 0)) <= 0 or effect_instance_id.is_empty():
		return {"ok": false, "reason": "INVALID_PROC_SOURCE", "ledger": next}
	if effect_instance_id == parent_effect_instance_id:
		return {"ok": false, "reason": "RECURSIVE_PROC_FORBIDDEN", "ledger": next}
	if parent_depth + 1 > MAX_CHAIN_DEPTH or int(next.get("derivedCount", 0)) >= MAX_DERIVED_EFFECTS:
		return {"ok": false, "reason": "PROC_BUDGET_EXHAUSTED", "ledger": next}
	var fired: Dictionary = next.get("firedInstances", {})
	if fired.has(effect_instance_id) and not repeatable:
		return {"ok": false, "reason": "INSTANCE_ALREADY_FIRED", "ledger": next}
	fired[effect_instance_id] = int(fired.get(effect_instance_id, 0)) + 1
	next["firedInstances"] = fired
	next["derivedCount"] = int(next.get("derivedCount", 0)) + 1
	return {"ok": true, "reason": "", "chainDepth": parent_depth + 1, "ledger": next}


func can_emit_on_hit(event_kind: String, explicitly_allowed: bool = false) -> bool:
	return explicitly_allowed or not event_kind in ["REFLECT", "DOT_TICK", "PROC_DAMAGE"]


# The supplied roll is from the combat named RNG stream, never from visual state.
# Targeting remains an immutable attribute of the authored item/ability.
func select_targets(doctrine: String, enemies: Array[Dictionary], focus_id: String, seeded_roll: int = 0) -> PackedStringArray:
	var living: Array[Dictionary] = []
	for enemy: Dictionary in enemies:
		if bool(enemy.get("alive", false)) and not str(enemy.get("id", "")).is_empty():
			living.append(enemy)
	living.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	var ids: PackedStringArray = PackedStringArray()
	if living.is_empty() or not doctrine in TARGET_DOCTRINES:
		return ids
	if doctrine == "SELF" or doctrine == "ALLY":
		return ids # The caller resolves friendly actors, not the enemy roster.
	if doctrine == "ALL":
		for enemy: Dictionary in living:
			ids.append(str(enemy.get("id", "")))
		return ids
	if doctrine == "FOCUS":
		for enemy: Dictionary in living:
			if str(enemy.get("id", "")) == focus_id:
				ids.append(focus_id)
				return ids
	if doctrine == "MARKED":
		for enemy: Dictionary in living:
			if bool(enemy.get("marked", false)):
				ids.append(str(enemy.get("id", "")))
				return ids
	if doctrine == "LOWEST_HP":
		living.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var a: float = float(left.get("hp", 0.0))
			var b: float = float(right.get("hp", 0.0))
			return a < b if not is_equal_approx(a, b) else str(left.get("id", "")) < str(right.get("id", ""))
		)
	elif doctrine == "NEAREST":
		living.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var a: float = float(left.get("distance", 0.0))
			var b: float = float(right.get("distance", 0.0))
			return a < b if not is_equal_approx(a, b) else str(left.get("id", "")) < str(right.get("id", ""))
		)
	elif doctrine == "RANDOM_SEEDED":
		ids.append(str(living[posmod(seeded_roll, living.size())].get("id", "")))
		return ids
	else:
		# FOCUS/MARKED fallback and HIGHEST_THREAT use a stable actorId tie.
		living.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var a: float = float(left.get("threat", 0.0))
			var b: float = float(right.get("threat", 0.0))
			return a > b if not is_equal_approx(a, b) else str(left.get("id", "")) < str(right.get("id", ""))
		)
	ids.append(str(living[0].get("id", "")))
	return ids


func _ceil_tick(ms: int) -> int:
	return int(ceili(float(ms) / float(TICK_MS))) * TICK_MS
