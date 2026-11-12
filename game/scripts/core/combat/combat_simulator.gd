class_name CombatSimulator
extends RefCounted

const COMBAT_RULES_VERSION: String = "cydle-combat-1.0"
const MAX_LOG_EVENTS: int = 5000
const DEFAULT_MAX_DURATION_MS: int = 180000

var _factory: CombatFactory = CombatFactory.new()
var _hash: StateHash = StateHash.new()

func create_state(config: Dictionary) -> Dictionary:
	var seed_value: Variant = config.get("seed", "")
	var depth_value: Variant = config.get("depth", 0)
	var enemy_value: Variant = config.get("enemies", [])
	var build_value: Variant = config.get("build", {})
	var tactics_value: Variant = config.get("tactics", {})
	if not seed_value is String or str(seed_value).is_empty():
		return _failure("Для боя требуется непустой seed.")
	if not _is_integer(depth_value) or int(depth_value) < 1:
		return _failure("Глубина должна быть целым числом не меньше 1.")
	if not enemy_value is Array or enemy_value.is_empty():
		return _failure("Бой должен содержать хотя бы одного врага.")
	if not build_value is Dictionary or not tactics_value is Dictionary:
		return _failure("Бою требуются рассчитанная сборка и профиль тактики.")
	var specs: Array[Dictionary] = []
	for entry: Variant in enemy_value:
		if not entry is Dictionary:
			return _failure("Спецификация врага должна быть объектом.")
		specs.append(entry)
	var roster: Dictionary = _factory.create_roster(build_value, specs, int(depth_value), config)
	if not bool(roster.get("ok", false)):
		return roster
	var state: CombatState = CombatState.new()
	state.seed = str(seed_value)
	state.depth = int(depth_value)
	state.biome = str(config.get("biome", "B01"))
	state.node_type = str(config.get("nodeType", "COMBAT"))
	state.max_duration_ms = int(config.get("maxDurationMs", DEFAULT_MAX_DURATION_MS))
	state.operator = roster["operator"] as CombatActorState
	state.drones = roster["drones"]
	state.enemies = roster["enemies"]
	state.build = build_value.duplicate(true)
	state.tactics = tactics_value.duplicate(true)
	state.record_log = bool(config.get("recordLog", true))
	state.ambient_heat_per_sec = float(config.get("ambientHeatPerSec", 0.0))
	state.cooling_penalty = float(config.get("coolingPenalty", 0.0))
	state.enemy_windup_mult = float(config.get("enemyWindupMult", 1.0))
	state.elite_pen = float(config.get("elitePen", 0.0))
	state.extra_enemy_digital_bonus = float(config.get("extraEnemyDigitalBonus", 0.0))
	state.metrics = _empty_metrics()
	state.rng = _new_rng(state.seed).serialize()
	state.rules_hash = _hash.hash_string(_hash.stable_stringify({"version": COMBAT_RULES_VERSION, "tactics": state.tactics}))
	state.next_event_id = 1
	var enemy_names: PackedStringArray = PackedStringArray()
	for enemy: CombatActorState in state.enemies:
		enemy_names.append(enemy.display_name)
	_emit(state, "COMBAT_START", "operator", {
		"text": "Бой начался: %s." % ", ".join(enemy_names),
		"data": {"initialTempShield": float(config.get("initialTempShield", 0.0)), "initialExtraHeat": float(config.get("initialExtraHeat", 0.0)), "alliedCount": 0},
	})
	return {"ok": true, "state": state, "error": ""}

func _new_rng(seed_value: String) -> DeterministicRng:
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("combat", seed_value)
	return rng

func _emit(state: CombatState, kind: String, actor_id: String, fields: Dictionary = {}) -> Dictionary:
	var event: Dictionary = {
		"eventId": state.next_event_id, "timestamp": state.time_ms, "kind": kind, "actorId": actor_id,
		"incomingTags": [], "producedTags": [], "chainDepth": 0, "text": "",
	}
	state.next_event_id += 1
	for key: Variant in fields.keys():
		event[key] = fields[key]
	if state.record_log:
		state.log.append(event)
		if state.log.size() > MAX_LOG_EVENTS:
			state.log.pop_front()
			state.log_truncated = true
	return event

func _empty_metrics() -> Dictionary:
	return {
		"damageDealt": 0.0, "damageTaken": 0.0,
		"damageByType": {"KINETIC": 0.0, "ENERGY": 0.0, "DIGITAL": 0.0},
		"damageBySource": {}, "takenBySource": {}, "hits": 0, "misses": 0, "crits": 0, "dodgesTaken": 0, "kills": 0,
		"skillUses": {}, "ruleFailures": [], "energySpent": 0.0, "energyStarvedMs": 0, "heatLockouts": 0, "heatLockoutMs": 0,
		"shieldAbsorbed": 0.0, "hpLost": 0.0, "healingDone": 0.0, "statusTicks": 0, "procsTriggered": 0,
		"interrupts": 0, "chainLimitHits": 0, "ttk": [], "droneDeaths": 0, "escaped": [],
		"lowestHpFraction": 1.0, "timeWithoutShieldMs": 0,
	}

func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _failure(message: String) -> Dictionary:
	return {"ok": false, "state": null, "error": message}
