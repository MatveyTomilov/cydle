class_name CombatState
extends RefCounted

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
	return {
		"seed": seed, "depth": depth, "biome": biome, "nodeType": node_type, "timeMs": time_ms,
		"maxDurationMs": max_duration_ms, "operator": operator.to_dictionary(), "drones": drone_values,
		"enemies": enemy_values, "allies": ally_values, "rng": rng.duplicate(true), "nextEventId": next_event_id,
		"log": log.duplicate(true), "logTruncated": log_truncated, "metrics": metrics.duplicate(true),
		"outcome": outcome if not outcome.is_empty() else null, "tactics": tactics.duplicate(true), "rulesHash": rules_hash,
		"wantedDelta": wanted_delta, "revealDelta": reveal_delta, "recordLog": record_log,
		"ambientHeatPerSec": ambient_heat_per_sec, "coolingPenalty": cooling_penalty,
		"enemyWindupMult": enemy_windup_mult, "elitePen": elite_pen,
		"extraEnemyDigitalBonus": extra_enemy_digital_bonus, "triggerChains": trigger_chains.duplicate(true),
	}
