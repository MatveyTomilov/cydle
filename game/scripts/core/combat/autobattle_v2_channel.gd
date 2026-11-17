class_name AutobattleV2Channel
extends RefCounted

# Serializable action channel. Effects and resource payment are the caller's
# atomic responsibility when advance() returns commit; cooldowns never own it.
const VERSION: String = "cydle-action-channel-2.2"
const OFFENSIVE_CLASSES: Array[String] = ["BASIC_ATTACK", "SPECIAL_ATTACK"]
var _contract: AutobattleV2Contract = AutobattleV2Contract.new()

func new_state() -> Dictionary:
	return {"version": VERSION, "active": {}, "cooldowns": {}, "supportStreak": 0, "lastTimeMs": 0}

func advance(current: Dictionary, now_ms: int) -> Dictionary:
	var error: String = _validate(current, now_ms)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var state: Dictionary = current.duplicate(true)
	state["lastTimeMs"] = now_ms
	var active: Dictionary = state["active"]
	var commit: Dictionary = {}
	if not active.is_empty():
		var result: Dictionary = _contract.advance_action(active["timeline"], now_ms)
		active["timeline"] = result["timeline"]
		if bool(result["didCommit"]):
			commit = active["action"].duplicate(true)
			state["cooldowns"][str(commit["actionId"])] = int(active["timeline"]["readyAtMs"])
			state["supportStreak"] = 0 if str(commit["classId"]) in OFFENSIVE_CLASSES else int(state["supportStreak"]) + 1
		if bool(result["channelReady"]) or bool(active["timeline"].get("interrupted", false)):
			state["active"] = {}
	return {"ok": true, "state": state, "commit": commit, "channelReady": state["active"].is_empty()}

func start(current: Dictionary, authored_actions: Array[Dictionary], now_ms: int, energy: float, heat: float, max_heat: float, thermal_locked: bool = false) -> Dictionary:
	var error: String = _validate(current, now_ms)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if not current["active"].is_empty():
		return {"ok": false, "error": "CHANNEL_BUSY"}
	var state: Dictionary = current.duplicate(true)
	state["lastTimeMs"] = now_ms
	var candidates: Array[Dictionary] = []
	for authored: Dictionary in authored_actions:
		var candidate: Dictionary = authored.duplicate(true)
		candidate["cooldownUntilMs"] = maxi(int(candidate.get("cooldownUntilMs", 0)), int(state["cooldowns"].get(str(candidate.get("actionId", "")), 0)))
		candidates.append(candidate)
	var selection: Dictionary = _contract.select_action(candidates, now_ms, energy, heat, max_heat, thermal_locked)
	var chosen: Dictionary = selection["action"]
	# One supportive main action may precede an available attack. This bound is
	# channel policy, never a configurable priority or item-specific exception.
	if int(state["supportStreak"]) >= 1 and not chosen.is_empty() and not str(chosen.get("classId", "")) in OFFENSIVE_CLASSES:
		var offense: Array[Dictionary] = []
		for candidate: Dictionary in candidates:
			if str(candidate.get("classId", "")) in OFFENSIVE_CLASSES:
				offense.append(candidate)
		var attack_selection: Dictionary = _contract.select_action(offense, now_ms, energy, heat, max_heat, thermal_locked)
		if not attack_selection["action"].is_empty():
			selection["rejected"].append({"actionId": chosen["actionId"], "reason": "OFFENSE_TURN"})
			chosen = attack_selection["action"]
	if not chosen.is_empty():
		state["active"] = {"action": chosen.duplicate(true), "timeline": _contract.begin_action(chosen, now_ms)}
	return {"ok": true, "state": state, "action": chosen, "rejected": selection["rejected"]}

func interrupt(current: Dictionary, now_ms: int) -> Dictionary:
	var error: String = _validate(current, now_ms)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var state: Dictionary = current.duplicate(true)
	state["lastTimeMs"] = now_ms
	if state["active"].is_empty():
		return {"ok": true, "state": state, "interrupted": false}
	var result: Dictionary = _contract.interrupt_action(state["active"]["timeline"], now_ms)
	if bool(result["interrupted"]):
		state["active"] = {}
	return {"ok": true, "state": state, "interrupted": result["interrupted"]}

func _validate(state: Dictionary, now_ms: int) -> String:
	if str(state.get("version", "")) != VERSION:
		return "INCOMPATIBLE_ACTION_CHANNEL"
	if not _is_tick_value(state.get("lastTimeMs")) or not _is_nonnegative_integer(state.get("supportStreak")):
		return "INVALID_ACTION_CHANNEL"
	if now_ms < int(state.get("lastTimeMs", 0)) or now_ms < 0 or now_ms % AutobattleV2Contract.TICK_MS != 0:
		return "INVALID_CHANNEL_TIME"
	if not state.get("active") is Dictionary or not state.get("cooldowns") is Dictionary:
		return "INVALID_ACTION_CHANNEL"
	for action_id: Variant in state["cooldowns"]:
		if not action_id is String or str(action_id).is_empty() or not _is_tick_value(state["cooldowns"][action_id]):
			return "INVALID_ACTION_CHANNEL"
	var active: Dictionary = state["active"]
	if not active.is_empty() and (not active.get("action") is Dictionary or not active.get("timeline") is Dictionary):
		return "INVALID_ACTION_CHANNEL"
	if not active.is_empty():
		var action: Dictionary = active["action"]
		var timeline: Dictionary = active["timeline"]
		if str(action.get("actionId", "")).is_empty() or str(action.get("sourceId", "")).is_empty() or not str(action.get("classId", "")) in AutobattleV2Contract.CLASS_ORDER:
			return "INVALID_ACTION_CHANNEL"
		var doctrine: int = int(action.get("targetDoctrine", -1))
		if doctrine < 0 or doctrine >= AutobattleV2Contract.DOCTRINE_NAMES.size() or str(action.get("targetMode", "")) != AutobattleV2Contract.target_name(doctrine):
			return "INVALID_ACTION_TARGET_DOCTRINE"
		if str(timeline.get("actionId", "")) != str(action["actionId"]) or not timeline.get("committed") is bool or not timeline.get("interrupted") is bool:
			return "INVALID_ACTION_CHANNEL"
		for field: String in ["commitAtMs", "recoveryUntilMs", "readyAtMs"]:
			var value: Variant = timeline.get(field)
			if not _is_tick_value(value):
				return "INVALID_ACTION_CHANNEL"
		if int(timeline["commitAtMs"]) > int(timeline["recoveryUntilMs"]) or int(timeline["recoveryUntilMs"]) > int(timeline["readyAtMs"]):
			return "INVALID_ACTION_CHANNEL"
	return ""

func _is_tick_value(value: Variant) -> bool:
	return _is_nonnegative_integer(value) and int(value) % AutobattleV2Contract.TICK_MS == 0

func _is_nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value))
