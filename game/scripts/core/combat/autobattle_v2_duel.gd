class_name AutobattleV2Duel
extends RefCounted

# Executable, deterministic first V2 duel: ARC-9 vs a single enemy.
# This is a headless proving slice, not the GameSession runtime.
# Future phases replace these fixed authored prototypes with BuildResolver data.
const VERSION: String = "cydle-combat-2.0-prototype"
const TICK_MS: int = 100
const ARC_DAMAGE: float = 22.0
const ARC_ENERGY_COST: float = 4.0
const ARC_HEAT_GAIN: float = 9.0
const HOT_THRESHOLD: float = 70.0
const VENT_THRESHOLD: float = 85.0
const VENT_COOLDOWN_MS: int = 8000

var _actions: AutobattleV2Contract = AutobattleV2Contract.new()
var _damage: DamageMath = DamageMath.new()
var _hash: StateHash = StateHash.new()

func new_duel(seed_value: String, enemy_hp: float = 900.0, enemy_armor: float = 4.0) -> Dictionary:
	if seed_value.is_empty() or enemy_hp <= 0.0 or not is_finite(enemy_hp) or enemy_armor < 0.0 or not is_finite(enemy_armor):
		return {}
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("combat", seed_value)
	return {
		"rulesVersion": VERSION, "seed": seed_value, "timeMs": 0, "rng": rng.serialize(),
		"operator": {"hp": 320.0, "maxHp": 320.0, "shield": 120.0, "maxShield": 120.0,
			"energy": 100.0, "maxEnergy": 100.0, "heat": 0.0, "maxHeat": 100.0,
			"lastHeatGainAtMs": -100000, "lastDamagedAtMs": -100000,
			"lastTargetId": "enemy:0", "thermalLocked": false},
		"enemy": {"id": "enemy:0", "hp": enemy_hp, "maxHp": enemy_hp,
			"armor": enemy_armor, "shield": 0.0, "maxShield": 0.0,
			"accuracy": 100.0, "evasion": 0.0, "threat": 10.0,
			"damage": 6.0, "nextAttackAtMs": 2500, "attackIntervalMs": 2500},
		"activeAction": {}, "ventReadyAtMs": 0, "nextEventId": 1, "log": [],
		"metrics": {"operatorDamage": 0.0, "operatorHits": 0, "operatorMisses": 0,
			"ventUses": 0, "shieldFromVent": 0.0, "enemyHits": 0},
		"outcome": "",
	}


func step(current: Dictionary) -> Dictionary:
	if str(current.get("rulesVersion", "")) != VERSION:
		return {"ok": false, "error": "INCOMPATIBLE_COMBAT_VERSION"}
	if not str(current.get("outcome", "")).is_empty():
		return {"ok": true, "state": current.duplicate(true)}
	var rng: DeterministicRng = DeterministicRng.new()
	if not rng.restore(current.get("rng", {})):
		return {"ok": false, "error": "INVALID_RNG_STATE"}
	var state: Dictionary = current.duplicate(true)
	state["timeMs"] = int(state["timeMs"]) + TICK_MS
	_regenerate(state)
	var operator: Dictionary = state["operator"]
	var enemy: Dictionary = state["enemy"]
	var active: Dictionary = state["activeAction"]
	if not active.is_empty():
		var advanced: Dictionary = _actions.advance_action(active["timeline"], int(state["timeMs"]))
		active["timeline"] = advanced["timeline"]
		if bool(advanced["didCommit"]):
			if str(active.get("actionId", "")) == "ARC-9:basic":
				_commit_arc(state, rng)
			elif str(active.get("actionId", "")) == "thermal-vent":
				_commit_vent(state)
			else:
				return {"ok": false, "error": "UNKNOWN_ACTION"}
		if str(active["timeline"].get("phase", "")) == "READY":
			state["activeAction"] = {}
		else:
			state["activeAction"] = active
	# This prototype enemy has a direct basic attack; telegraphs and its own
	# five-phase action channel are intentionally separate future work.
	if float(enemy.get("hp", 0.0)) > 0.0 and float(operator.get("hp", 0.0)) > 0.0 and int(state["timeMs"]) >= int(enemy["nextAttackAtMs"]):
		_commit_enemy_attack(state, rng)
		enemy["nextAttackAtMs"] = int(enemy["nextAttackAtMs"]) + int(enemy["attackIntervalMs"])
	if float(operator.get("hp", 0.0)) <= 0.0:
		state["outcome"] = "DEFEAT"
	elif float(enemy.get("hp", 0.0)) <= 0.0:
		state["outcome"] = "VICTORY"
	elif state["activeAction"].is_empty():
		_begin_next_action(state)
	state["rng"] = rng.serialize()
	return {"ok": true, "state": state}


func run_until(current: Dictionary, max_ticks: int) -> Dictionary:
	var state: Dictionary = current.duplicate(true)
	for _tick: int in range(maxi(0, max_ticks)):
		var result: Dictionary = step(state)
		if not bool(result.get("ok", false)):
			return result
		state = result["state"]
		if not str(state.get("outcome", "")).is_empty():
			break
	return {"ok": true, "state": state, "stateHash": state_hash(state)}


func state_hash(state: Dictionary) -> String:
	return _hash.state_hash(state)


func _regenerate(state: Dictionary) -> void:
	var op: Dictionary = state["operator"]
	var now: int = int(state["timeMs"])
	op["energy"] = minf(float(op["maxEnergy"]), float(op["energy"]) + 0.8)
	if now - int(op["lastHeatGainAtMs"]) >= 500:
		op["heat"] = maxf(0.0, float(op["heat"]) - 0.6)
	if now - int(op["lastDamagedAtMs"]) >= 4000:
		op["shield"] = minf(float(op["maxShield"]), float(op["shield"]) + float(op["maxShield"]) * 0.008)


func _begin_next_action(state: Dictionary) -> void:
	var op: Dictionary = state["operator"]
	var now: int = int(state["timeMs"])
	var candidates: Array[Dictionary] = [
		{"sourceId": "weapon:ARC-9", "actionId": "ARC-9:basic",
			"classId": "BASIC_ATTACK", "targetMode": "HIGHEST_THREAT",
			"readyAtMs": 0, "cooldownUntilMs": 0,
			"hasValidTarget": float(state["enemy"].get("hp", 0.0)) > 0.0,
			"energyCost": ARC_ENERGY_COST, "heatDelta": ARC_HEAT_GAIN,
			"prepareMs": 600, "recoveryMs": 200, "cooldownMs": 0},
	]
	# This threshold belongs to the authored Vent ability, not a player rule.
	if float(op["heat"]) >= VENT_THRESHOLD:
		candidates.append({
			"sourceId": "ability:thermal-vent", "actionId": "thermal-vent",
			"classId": "DEFENSE", "targetMode": "SELF",
			"readyAtMs": 0, "cooldownUntilMs": int(state["ventReadyAtMs"]),
			"energyCost": 0.0, "heatDelta": -45.0,
			"prepareMs": 400, "recoveryMs": 0, "cooldownMs": VENT_COOLDOWN_MS,
		})
	var selected: Dictionary = _actions.select_action(
		candidates, now, float(op["energy"]), float(op["heat"]), float(op["maxHeat"]),
		bool(op["thermalLocked"])
	)
	for denied: Dictionary in selected.get("rejected", []):
		_emit(state, "ACTION_UNAVAILABLE", {
			"actionId": denied.get("actionId", ""), "reason": denied.get("reason", ""),
		})
	var authored: Dictionary = selected.get("action", {})
	if authored.is_empty():
		return
	if str(authored["targetMode"]) == "HIGHEST_THREAT":
		var targets: Array[Dictionary] = [
			{"id": str(state["enemy"]["id"]), "alive": float(state["enemy"]["hp"]) > 0.0,
				"hp": float(state["enemy"]["hp"]), "threat": float(state["enemy"]["threat"])},
		]
		var selected_ids: PackedStringArray = _actions.select_targets("HIGHEST_THREAT", targets, str(op.get("lastTargetId", "")))
		if selected_ids.is_empty():
			return
		op["lastTargetId"] = selected_ids[0]
	state["activeAction"] = {"actionId": str(authored["actionId"]), "sourceId": str(authored["sourceId"]),
		"timeline": _actions.begin_action(authored, now)}
	_emit(state, "ACTION_PREPARE", {
		"sourceId": str(authored["sourceId"]), "actionId": str(authored["actionId"]),
		"commitAtMs": state["activeAction"]["timeline"]["commitAtMs"],
		"targetId": str(op.get("lastTargetId", "")) if str(authored["targetMode"]) != "SELF" else "operator",
		"reason": "ITEM_AUTHORED_ACTION",
	})


func _commit_arc(state: Dictionary, rng: DeterministicRng) -> void:
	var op: Dictionary = state["operator"]
	var enemy: Dictionary = state["enemy"]
	if float(op["energy"]) < ARC_ENERGY_COST:
		_emit(state, "ACTION_INTERRUPTED", {"sourceId": "weapon:ARC-9", "reason": "ENERGY_AT_COMMIT"})
		return
	var before: Dictionary = {"energy": op["energy"], "heat": op["heat"], "enemyHp": enemy["hp"], "enemyShield": enemy["shield"]}
	op["energy"] = float(op["energy"]) - ARC_ENERGY_COST
	var was_hot: bool = float(op["heat"]) >= HOT_THRESHOLD
	op["heat"] = minf(float(op["maxHeat"]), float(op["heat"]) + ARC_HEAT_GAIN)
	op["lastHeatGainAtMs"] = int(state["timeMs"])
	if float(op["heat"]) >= HOT_THRESHOLD and not was_hot:
		_emit(state, "HOT_START", {"sourceId": "weapon:ARC-9", "heat": op["heat"]})
	var chance: float = _damage.hit_probability(100.0, float(enemy.get("evasion", 0.0)))
	var hit: bool = rng.chance(chance)
	var applied: float = 0.0
	var mitigation_trace: Dictionary = {}
	var partition_trace: Dictionary = {}
	if hit:
		var base_damage: float = ARC_DAMAGE * (1.3 if float(op["heat"]) >= HOT_THRESHOLD else 1.0)
		var mitigation: Dictionary = _damage.mitigate_packet(base_damage, "KINETIC",
			{"armor": enemy["armor"]}, DamageMath.ZERO_PENETRATION)
		var partition: Dictionary = _damage.partition_damage(float(mitigation["afterDefense"]),
			{"hp": enemy["hp"], "shield": enemy["shield"], "temp": []}, 0.0)
		enemy["shield"] = maxf(0.0, float(enemy["shield"]) - float(partition["shieldConsumed"]))
		enemy["hp"] = maxf(0.0, float(enemy["hp"]) - float(partition["hpLost"]))
		applied = float(partition["shieldConsumed"]) + float(partition["hpLost"])
		mitigation_trace = mitigation["trace"]
		partition_trace = partition["trace"]
		state["metrics"]["operatorDamage"] = float(state["metrics"]["operatorDamage"]) + applied
		state["metrics"]["operatorHits"] = int(state["metrics"]["operatorHits"]) + 1
	else:
		state["metrics"]["operatorMisses"] = int(state["metrics"]["operatorMisses"]) + 1
	_emit(state, "ATTACK_COMMIT", {
		"sourceId": "weapon:ARC-9", "actionId": "ARC-9:basic",
		"targetId": str(enemy["id"]), "reason": "READY_AND_HIGHEST_THREAT",
		"cost": {"energy": ARC_ENERGY_COST, "heatGain": ARC_HEAT_GAIN},
		"hit": hit, "hitChance": chance, "damageApplied": applied,
		"preState": before, "postState": {
			"energy": op["energy"], "heat": op["heat"], "enemyHp": enemy["hp"], "enemyShield": enemy["shield"],
		}, "mitigationTrace": mitigation_trace, "partitionTrace": partition_trace,
	})


func _commit_vent(state: Dictionary) -> void:
	var op: Dictionary = state["operator"]
	var before: Dictionary = {"heat": op["heat"], "shield": op["shield"], "energy": op["energy"]}
	var removed: float = minf(45.0, float(op["heat"]))
	op["heat"] = maxf(0.0, float(op["heat"]) - removed)
	op["energy"] = minf(float(op["maxEnergy"]), float(op["energy"]) + 15.0)
	var gained: float = minf(float(op["maxShield"]) - float(op["shield"]), 0.6 * removed)
	op["shield"] = float(op["shield"]) + gained
	state["ventReadyAtMs"] = int(state["timeMs"]) + VENT_COOLDOWN_MS
	state["metrics"]["ventUses"] = int(state["metrics"]["ventUses"]) + 1
	state["metrics"]["shieldFromVent"] = float(state["metrics"]["shieldFromVent"]) + gained
	_emit(state, "HEAT_VENT", {
		"sourceId": "ability:thermal-vent", "actionId": "thermal-vent",
		"targetId": "operator", "reason": "AUTHORED_HEAT_AT_LEAST_85",
		"heatRemoved": removed, "shieldGained": gained, "energyGained": 15.0,
		"preState": before, "postState": {
			"heat": op["heat"], "shield": op["shield"], "energy": op["energy"],
		},
	})


func _commit_enemy_attack(state: Dictionary, rng: DeterministicRng) -> void:
	var op: Dictionary = state["operator"]
	var enemy: Dictionary = state["enemy"]
	var hit: bool = rng.chance(_damage.hit_probability(float(enemy["accuracy"]), 0.0))
	var applied: float = 0.0
	var mitigation_trace: Dictionary = {}
	if hit:
		var packet: Dictionary = _damage.mitigate_packet(float(enemy["damage"]), "KINETIC",
			{"armor": 0.0}, DamageMath.ZERO_PENETRATION)
		var partition: Dictionary = _damage.partition_damage(float(packet["afterDefense"]),
			{"hp": op["hp"], "shield": op["shield"], "temp": []}, 0.0)
		op["shield"] = maxf(0.0, float(op["shield"]) - float(partition["shieldConsumed"]))
		op["hp"] = maxf(0.0, float(op["hp"]) - float(partition["hpLost"]))
		op["lastDamagedAtMs"] = int(state["timeMs"])
		applied = float(partition["shieldConsumed"]) + float(partition["hpLost"])
		mitigation_trace = packet["trace"]
		state["metrics"]["enemyHits"] = int(state["metrics"]["enemyHits"]) + 1
	_emit(state, "ENEMY_ATTACK", {
		"sourceId": "enemy:0", "actionId": "enemy:basic", "targetId": "operator",
		"hit": hit, "damageApplied": applied, "mitigationTrace": mitigation_trace,
		"postState": {"hp": op["hp"], "shield": op["shield"]},
	})


func _emit(state: Dictionary, event_type: String, fields: Dictionary) -> void:
	var event: Dictionary = {
		"eventId": int(state["nextEventId"]), "rootEventId": int(state["nextEventId"]),
		"chainDepth": 0, "timestamp": int(state["timeMs"]), "kind": event_type,
		"actorId": "operator" if not event_type.begins_with("ENEMY") else "enemy:0",
	}
	for key: Variant in fields.keys():
		event[key] = fields[key]
	state["nextEventId"] = int(state["nextEventId"]) + 1
	state["log"].append(event)
