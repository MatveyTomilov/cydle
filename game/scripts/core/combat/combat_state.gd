class_name CombatState
extends RefCounted

const LEGACY_RULES_VERSION: String = "cydle-combat-1.0"
const V2_RULES_VERSION: String = "cydle-combat-2.1-development"
var combat_rules_version: String = LEGACY_RULES_VERSION
var action_channel: Dictionary = {}
var seed: String = ""
var depth: int = 1
var biome: String = "B01"
var node_type: String = "COMBAT"
var time_ms: int = 0
var max_duration_ms: int = 180000
var operator: CombatActorState
var drones: Array[CombatActorState] = []
var enemies: Array[CombatActorState] = []
var allies: Array[CombatActorState] = []
var rng: Dictionary = {}
var next_event_id: int = 1
var log: Array[Dictionary] = []
var log_truncated: bool = false
var metrics: Dictionary = {}
var outcome: String = ""
var build: Dictionary = {}
var tactics: Dictionary = {}
var rules_hash: String = ""
var wanted_delta: int = 0
var reveal_delta: int = 0
var record_log: bool = true
var ambient_heat_per_sec: float = 0.0
var cooling_penalty: float = 0.0
var enemy_windup_mult: float = 1.0
var elite_pen: float = 0.0
var minimum_enemy_telegraph_ms: int = 0
var drone_war: bool = false
var extra_enemy_digital_bonus: float = 0.0
var trigger_chains: Dictionary = {}

func all_actors() -> Array[CombatActorState]:
	var result: Array[CombatActorState] = [operator]
	result.append_array(drones)
	result.append_array(allies)
	result.append_array(enemies)
	return result

func to_dictionary() -> Dictionary:
	var drone_values: Array[Dictionary] = []
	for actor: CombatActorState in drones:
		drone_values.append(actor.to_dictionary())
	var enemy_values: Array[Dictionary] = []
	for actor: CombatActorState in enemies:
		enemy_values.append(actor.to_dictionary())
	var ally_values: Array[Dictionary] = []
	for actor: CombatActorState in allies:
		ally_values.append(actor.to_dictionary())
	var result: Dictionary = {
		"seed": seed, "depth": depth, "biome": biome, "nodeType": node_type, "timeMs": time_ms,
		"maxDurationMs": max_duration_ms, "operator": operator.to_dictionary(), "drones": drone_values,
		"enemies": enemy_values, "allies": ally_values, "rng": rng.duplicate(true), "nextEventId": next_event_id,
		"log": log.duplicate(true), "logTruncated": log_truncated, "metrics": metrics.duplicate(true),
		"outcome": outcome if not outcome.is_empty() else null, "tactics": tactics.duplicate(true), "rulesHash": rules_hash,
		"wantedDelta": wanted_delta, "revealDelta": reveal_delta, "recordLog": record_log,
		"ambientHeatPerSec": ambient_heat_per_sec, "coolingPenalty": cooling_penalty,
		"enemyWindupMult": enemy_windup_mult, "elitePen": elite_pen,
		"minimumEnemyTelegraphMs": minimum_enemy_telegraph_ms, "droneWar": drone_war,
		"extraEnemyDigitalBonus": extra_enemy_digital_bonus, "triggerChains": trigger_chains.duplicate(true),
	}
	# Preserve the historical V1 hash representation used by golden fixtures.
	if combat_rules_version != LEGACY_RULES_VERSION:
		result["combatRulesVersion"] = combat_rules_version
		result["actionChannel"] = action_channel.duplicate(true)
	return result

static func from_dictionary(value: Dictionary, resolved_build: Dictionary) -> CombatState:
	# Untagged historical snapshots are V1. V2 requires a validated explicit
	# channel; unknown versions never enter either runtime.
	var version: String = str(value.get("combatRulesVersion", LEGACY_RULES_VERSION))
	if version not in [LEGACY_RULES_VERSION, V2_RULES_VERSION]:
		return null
	if version == V2_RULES_VERSION:
		if str(value.get("rulesHash", "")) != CombatFactory.new().v2_build_rules_hash(resolved_build):
			return null
		if not value.get("tactics", {}).is_empty() or not resolved_build.get("triggerEffects", []).is_empty() or not resolved_build.get("drones", []).is_empty():
			return null
		for skill: Variant in resolved_build.get("skills", []):
			if not skill is Dictionary or str(skill.get("channel", "main")) != "main" or not AutobattleV2Contract.SUPPORTED_MAIN_SKILLS.has(str(skill.get("id", ""))):
				return null
		if not value.get("actionChannel") is Dictionary or not AutobattleV2Channel.new()._validate(value["actionChannel"], int(value.get("timeMs", 0))).is_empty():
			return null
		var active: Dictionary = value["actionChannel"].get("active", {})
		if not active.is_empty():
			var canonical_actions: Array[Dictionary] = CombatFactory.new().compile_v2_main_actions(resolved_build, resolved_build.get("stats", {}))
			var canonical: Dictionary = {}
			for candidate: Dictionary in canonical_actions:
				if str(candidate.get("actionId", "")) == str(active["action"].get("actionId", "")):
					canonical = candidate
					break
			if canonical.is_empty(): return null
			for field: Variant in canonical.keys():
				# Timing is captured from effective runtime buffs at preparation;
				# those buffs can expire before this snapshot is resumed.
				if str(field) in ["prepareMs", "recoveryMs", "cooldownMs"]:
					continue
				if active["action"].get(field) != canonical[field]:
					return null
	if not value.get("operator") is Dictionary or resolved_build.is_empty():
		return null
	var state: CombatState = CombatState.new()
	state.combat_rules_version = version
	state.action_channel = value.get("actionChannel", {}).duplicate(true)
	state.seed = str(value.get("seed", ""))
	state.depth = int(value.get("depth", 1))
	state.biome = str(value.get("biome", "B01"))
	state.node_type = str(value.get("nodeType", "COMBAT"))
	state.time_ms = int(value.get("timeMs", 0))
	state.max_duration_ms = int(value.get("maxDurationMs", 180000))
	state.operator = CombatActorState.from_dictionary(value["operator"])
	for actor_value: Variant in value.get("drones", []):
		if actor_value is Dictionary: state.drones.append(CombatActorState.from_dictionary(actor_value))
	for actor_value: Variant in value.get("enemies", []):
		if actor_value is Dictionary: state.enemies.append(CombatActorState.from_dictionary(actor_value))
	for actor_value: Variant in value.get("allies", []):
		if actor_value is Dictionary: state.allies.append(CombatActorState.from_dictionary(actor_value))
	if version == V2_RULES_VERSION:
		var active: Dictionary = state.action_channel.get("active", {})
		if not active.is_empty():
			for target_id: Variant in active.get("targetIds", active.get("action", {}).get("targetIds", [])):
				if _actor_by_id(state, str(target_id)) == null: return null
	var rng_value: Variant = value.get("rng", {})
	if not rng_value is Dictionary:
		return null
	var restored_rng: DeterministicRng = DeterministicRng.new()
	if not restored_rng.restore(rng_value):
		return null
	state.rng = restored_rng.serialize()
	state.next_event_id = int(value.get("nextEventId", 1))
	state.log.assign(value.get("log", []))
	state.log_truncated = bool(value.get("logTruncated", false))
	state.metrics = value.get("metrics", {}).duplicate(true)
	state.outcome = str(value.get("outcome", "")) if value.get("outcome") != null else ""
	state.build = resolved_build.duplicate(true)
	state.tactics = value.get("tactics", {}).duplicate(true)
	state.rules_hash = str(value.get("rulesHash", ""))
	state.wanted_delta = int(value.get("wantedDelta", 0))
	state.reveal_delta = int(value.get("revealDelta", 0))
	state.record_log = bool(value.get("recordLog", true))
	state.ambient_heat_per_sec = float(value.get("ambientHeatPerSec", 0.0))
	state.cooling_penalty = float(value.get("coolingPenalty", 0.0))
	state.enemy_windup_mult = float(value.get("enemyWindupMult", 1.0))
	state.elite_pen = float(value.get("elitePen", 0.0))
	state.minimum_enemy_telegraph_ms = int(value.get("minimumEnemyTelegraphMs", 0))
	state.drone_war = bool(value.get("droneWar", false))
	state.extra_enemy_digital_bonus = float(value.get("extraEnemyDigitalBonus", 0.0))
	state.trigger_chains = value.get("triggerChains", {}).duplicate(true)
	return state if state.operator != null and not state.rng.is_empty() else null

static func _actor_by_id(state: CombatState, actor_id: String) -> CombatActorState:
	for actor: CombatActorState in state.all_actors():
		if actor.id == actor_id: return actor
	return null

func clone() -> CombatState:
	var copy: CombatState = CombatState.new()
	for property: Dictionary in get_property_list():
		var property_name: String = str(property.get("name", ""))
		if property_name in ["script", "operator", "drones", "enemies", "allies", "build", "tactics"] or property_name.is_empty():
			continue
		var value: Variant = get(property_name)
		if value is Dictionary or value is Array:
			copy.set(property_name, value.duplicate(true))
		else:
			copy.set(property_name, value)
	copy.operator = operator.clone()
	for actor: CombatActorState in drones:
		copy.drones.append(actor.clone())
	for actor: CombatActorState in enemies:
		copy.enemies.append(actor.clone())
	for actor: CombatActorState in allies:
		copy.allies.append(actor.clone())
	copy.build = build.duplicate(true)
	copy.tactics = tactics.duplicate(true)
	return copy
