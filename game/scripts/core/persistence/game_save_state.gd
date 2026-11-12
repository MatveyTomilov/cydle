class_name GameSaveState
extends RefCounted

const SAVE_SCHEMA_VERSION: int = 1
const BALANCE_VERSION: String = "1.0.0"
const GAME_VERSION: String = "1.0.0"

class WalletState:
	extends RefCounted
	var credits: float = 0.0
	var scrap: float = 0.0
	var data: float = 0.0

	func to_dictionary() -> Dictionary:
		return {"CREDITS": credits, "SCRAP": scrap, "DATA": data}

class OperatorState:
	extends RefCounted
	var level: int = 1
	var xp: int = 0
	var attributes: Dictionary = {"POW": 5, "REF": 5, "INT": 5, "ENG": 5, "SYN": 5}
	var attribute_points: int = 0
	var tree_points: int = 0

	func to_dictionary() -> Dictionary:
		return {"level": level, "xp": xp, "attributes": attributes.duplicate(true), "attributePoints": attribute_points, "treePoints": tree_points}

class TransportState:
	extends RefCounted
	var fuel: float = 24.0
	var fuel_max: float = 24.0
	var hull: float = 100.0
	var hull_max: float = 100.0
	var cargo_capacity: float = 20.0

	func to_dictionary() -> Dictionary:
		return {"fuel": fuel, "fuelMax": fuel_max, "hull": hull, "hullMax": hull_max, "cargoCapacity": cargo_capacity}

class CombatSnapshotState:
	extends RefCounted
	var sim_time_ms: int = 0
	var actors: Array[Dictionary] = []
	var event_queue: Array[Dictionary] = []
	var rng_streams: Array[Dictionary] = []
	var event_log: Array[Dictionary] = []
	var next_sequence_id: int = 1
	var rules_hash: String = ""

	func to_dictionary() -> Dictionary:
		return {
			"simTimeMs": sim_time_ms,
			"actors": actors.duplicate(true),
			"eventQueue": event_queue.duplicate(true),
			"rngStreams": rng_streams.duplicate(true),
			"eventLog": event_log.duplicate(true),
			"nextSequenceId": next_sequence_id,
			"rulesHash": rules_hash,
		}

class RunState:
	extends RefCounted
	var seed: String = ""
	var depth: int = 1
	var biome: String = "B01"
	var graph: Dictionary = {}
	var equipment: Dictionary = {}
	var current_node_id: String = "START"
	var visited_node_ids: Array[String] = []
	var cleared_node_ids: Array[String] = []
	var events_seen: Array[String] = []
	var temporary_mutation_ids: Array[String] = []
	var phase: String = "ROUTE"
	var wanted: float = 0.0
	var reveal_level: int = 0
	var resources: Dictionary = {}
	var wallet: WalletState = WalletState.new()
	var unsecured_cargo: Array[Dictionary] = []
	var shipped_cargo: Array[Dictionary] = []
	var grant_ids: Array[String] = []
	var command_ids: Array[String] = []
	var service_scrap_fuel_counts: Dictionary = {}
	var shipped_checkpoint_ids: Array[String] = []
	var pending_travel_delta_ms: int = 0
	var pending_combat_effects: Dictionary = {"initialTempShield": 0.0, "extraHeat": 0.0}
	var pending_next_combat: Dictionary = {
		"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false,
		"bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false,
		"alliedTurret": false, "extraRareOnElite": false,
	}
	var contract: Dictionary = {}
	var autopilot_enabled: bool = false
	var combat_result: Variant = null
	var last_command_id: Variant = null
	var world_rng: Dictionary = {}
	var loot_rng: Dictionary = {}
	var combat_snapshot: CombatSnapshotState = null

	func to_dictionary() -> Dictionary:
		var result: Dictionary = {
			"seed": seed,
			"depth": depth,
			"biome": biome,
			"graph": graph.duplicate(true),
			"equipment": equipment.duplicate(true),
			"currentNodeId": current_node_id,
			"visitedNodeIds": visited_node_ids.duplicate(),
			"clearedNodeIds": cleared_node_ids.duplicate(),
			"eventsSeen": events_seen.duplicate(),
			"temporaryMutationIds": temporary_mutation_ids.duplicate(),
			"phase": phase,
			"wanted": wanted,
			"revealLevel": reveal_level,
			"resources": resources.duplicate(true),
			"runWallet": wallet.to_dictionary(),
			"unsecuredCargo": unsecured_cargo.duplicate(true),
			"shippedCargo": shipped_cargo.duplicate(true),
			"grantIds": grant_ids.duplicate(),
			"commandIds": command_ids.duplicate(),
			"serviceScrapFuelCounts": service_scrap_fuel_counts.duplicate(true),
			"shippedCheckpointIds": shipped_checkpoint_ids.duplicate(),
			"pendingTravelDeltaMs": pending_travel_delta_ms,
			"pendingCombatEffects": pending_combat_effects.duplicate(true),
			"pendingNextCombat": pending_next_combat.duplicate(true),
			"combatResult": combat_result,
			"lastCommandId": last_command_id,
			"worldRng": world_rng.duplicate(true),
			"lootRng": loot_rng.duplicate(true),
			"combatSnapshot": null,
		}
		if not contract.is_empty():
			result["contract"] = contract.duplicate(true)
		if autopilot_enabled:
			result["autopilotEnabled"] = true
		if combat_snapshot != null:
			result["combatSnapshot"] = combat_snapshot.to_dictionary()
		return result

class MetaState:
	extends RefCounted
	var operator: OperatorState = OperatorState.new()
	var tutorial: Dictionary = {"firstSectorCompleted": false, "starterPrototypeSecured": false}
	var reputation: Dictionary = {"F_VANTA": 0, "F_RUST": 0, "F_CHOIR": 0, "F_ECHO": 0}
	var campaign_flags: Array[String] = []
	var transport: TransportState = TransportState.new()
	var protected_bank: WalletState = WalletState.new()
	var unsecured_wallet: WalletState = WalletState.new()
	var inventory: Array[Dictionary] = []
	var equipment: Dictionary = {}
	var garage: Dictionary = {}
	var unlocked_forpost: int = 0
	var max_sector_cleared: int = 0
	var unlocked_biomes: Array[String] = ["B01"]
	var skill_ids: Array[String] = []
	var passive_ids: Array[String] = []
	var tree_node_ids: Array[String] = []
	var unlocked_implant_slots: int = 4
	var unlocked_drone_slots: int = 1
	var tactics: Array[Dictionary] = []
	var active_tactic_id: String = ""
	var autopilot_profiles: Array[Dictionary] = []
	var quest_progress: Dictionary = {}
	var disassembly_history: Array[Dictionary] = []
	var disassembly_undo: Dictionary = {}

	func to_dictionary() -> Dictionary:
		var result: Dictionary = {
			"operator": operator.to_dictionary(),
			"tutorial": tutorial.duplicate(true),
			"reputation": reputation.duplicate(true),
			"campaignFlags": campaign_flags.duplicate(),
			"transport": transport.to_dictionary(),
			"protectedBank": protected_bank.to_dictionary(),
			"unsecuredWallet": unsecured_wallet.to_dictionary(),
			"inventory": inventory.duplicate(true),
			"equipment": equipment.duplicate(true),
			"garage": garage.duplicate(true),
			"unlockedForpost": unlocked_forpost,
			"maxSectorCleared": max_sector_cleared,
			"unlockedBiomes": unlocked_biomes.duplicate(),
			"skillIds": skill_ids.duplicate(),
			"passiveIds": passive_ids.duplicate(),
			"treeNodeIds": tree_node_ids.duplicate(),
			"unlockedImplantSlots": unlocked_implant_slots,
			"unlockedDroneSlots": unlocked_drone_slots,
			"tactics": tactics.duplicate(true),
			"activeTacticId": active_tactic_id,
			"autopilotProfiles": autopilot_profiles.duplicate(true),
			"questProgress": quest_progress.duplicate(true),
		}
		if not disassembly_history.is_empty():
			result["disassemblyHistory"] = disassembly_history.duplicate(true)
		if not disassembly_undo.is_empty():
			result["disassemblyUndo"] = disassembly_undo.duplicate(true)
		if quest_progress.is_empty():
			result.erase("questProgress")
		return result

var schema_version: int = SAVE_SCHEMA_VERSION
var balance_version: String = BALANCE_VERSION
var game_version: String = GAME_VERSION
var save_id: String = ""
var created_at: int = 0
var updated_at: int = 0
var revision: int = 1
var meta: MetaState = MetaState.new()
var run: RunState = null

func to_payload() -> Dictionary:
	return {
		"schemaVersion": schema_version,
		"balanceVersion": balance_version,
		"gameVersion": game_version,
		"saveId": save_id,
		"createdAt": created_at,
		"updatedAt": updated_at,
		"revision": revision,
		"meta": meta.to_dictionary(),
		"run": run.to_dictionary() if run != null else null,
	}

func parse_payload(value: Variant) -> Dictionary:
	var schema: GameSaveSchema = GameSaveSchema.new()
	var checked: Dictionary = schema.validate_payload(value)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "state": null, "error": str(checked.get("error", "Некорректное сохранение."))}
	var payload: Dictionary = value
	var parsed: GameSaveState = GameSaveState.new()
	parsed.schema_version = int(payload["schemaVersion"])
	parsed.balance_version = str(payload["balanceVersion"])
	parsed.game_version = str(payload["gameVersion"])
	parsed.save_id = str(payload["saveId"])
	parsed.created_at = int(payload["createdAt"])
	parsed.updated_at = int(payload["updatedAt"])
	parsed.revision = int(payload["revision"])
	parsed.meta = _meta_from_dictionary(payload["meta"])
	if payload["run"] is Dictionary:
		parsed.run = _run_from_dictionary(payload["run"])
	return {"ok": true, "state": parsed, "error": ""}

func _meta_from_dictionary(value: Dictionary) -> MetaState:
	var result: MetaState = MetaState.new()
	var operator_value: Dictionary = value["operator"]
	result.operator.level = int(operator_value["level"])
	result.operator.xp = int(operator_value["xp"])
	result.operator.attributes = operator_value["attributes"].duplicate(true)
	result.operator.attribute_points = int(operator_value["attributePoints"])
	result.operator.tree_points = int(operator_value["treePoints"])
	result.tutorial = value["tutorial"].duplicate(true)
	result.reputation = value["reputation"].duplicate(true)
	result.campaign_flags.assign(value["campaignFlags"])
	var transport_value: Dictionary = value["transport"]
	result.transport.fuel = float(transport_value["fuel"])
	result.transport.fuel_max = float(transport_value["fuelMax"])
	result.transport.hull = float(transport_value["hull"])
	result.transport.hull_max = float(transport_value["hullMax"])
	result.transport.cargo_capacity = float(transport_value["cargoCapacity"])
	result.protected_bank = _wallet_from_dictionary(value["protectedBank"])
	result.unsecured_wallet = _wallet_from_dictionary(value["unsecuredWallet"])
	result.inventory.assign(value["inventory"])
	result.equipment = value["equipment"].duplicate(true)
	result.garage = value["garage"].duplicate(true)
	result.unlocked_forpost = int(value["unlockedForpost"])
	result.max_sector_cleared = int(value["maxSectorCleared"])
	result.unlocked_biomes.assign(value["unlockedBiomes"])
	result.skill_ids.assign(value["skillIds"])
	result.passive_ids.assign(value["passiveIds"])
	result.tree_node_ids.assign(value["treeNodeIds"])
	result.unlocked_implant_slots = int(value["unlockedImplantSlots"])
	result.unlocked_drone_slots = int(value["unlockedDroneSlots"])
	result.tactics.assign(value["tactics"])
	result.active_tactic_id = str(value["activeTacticId"])
	result.autopilot_profiles.assign(value["autopilotProfiles"])
	result.quest_progress = value.get("questProgress", {}).duplicate(true)
	result.disassembly_history.assign(value.get("disassemblyHistory", []))
	result.disassembly_undo = value.get("disassemblyUndo", {}).duplicate(true)
	return result

func _run_from_dictionary(value: Dictionary) -> RunState:
	var result: RunState = RunState.new()
	result.seed = str(value["seed"])
	result.depth = int(value["depth"])
	result.biome = str(value["biome"])
	result.graph = value["graph"].duplicate(true)
	result.equipment = value.get("equipment", {}).duplicate(true)
	result.current_node_id = str(value["currentNodeId"])
	result.visited_node_ids.assign(value.get("visitedNodeIds", []))
	result.cleared_node_ids.assign(value.get("clearedNodeIds", []))
	result.events_seen.assign(value.get("eventsSeen", []))
	result.temporary_mutation_ids.assign(value.get("temporaryMutationIds", []))
	result.phase = str(value["phase"])
	result.wanted = float(value["wanted"])
	result.reveal_level = int(value["revealLevel"])
	result.resources = value.get("resources", {}).duplicate(true)
	result.wallet = _wallet_from_dictionary(value["runWallet"])
	result.unsecured_cargo.assign(value["unsecuredCargo"])
	result.shipped_cargo.assign(value.get("shippedCargo", []))
	result.grant_ids.assign(value["grantIds"])
	result.command_ids.assign(value["commandIds"])
	result.service_scrap_fuel_counts = value.get("serviceScrapFuelCounts", {}).duplicate(true)
	result.shipped_checkpoint_ids.assign(value.get("shippedCheckpointIds", []))
	result.pending_travel_delta_ms = int(value.get("pendingTravelDeltaMs", 0))
	result.pending_combat_effects = value.get("pendingCombatEffects", {"initialTempShield": 0.0, "extraHeat": 0.0}).duplicate(true)
	result.pending_next_combat = value.get("pendingNextCombat", {
		"skipOrdinary": false, "forceElite": false, "extraItemRoll": false, "forceBounty": false,
		"bountyCreditsBonus": 0.0, "bountyEnemyId": null, "extraRareItemRoll": false,
		"alliedTurret": false, "extraRareOnElite": false,
	}).duplicate(true)
	result.contract = value.get("contract", {}).duplicate(true)
	result.autopilot_enabled = bool(value.get("autopilotEnabled", false))
	result.combat_result = value.get("combatResult")
	result.last_command_id = value.get("lastCommandId")
	result.world_rng = value["worldRng"].duplicate(true)
	result.loot_rng = value["lootRng"].duplicate(true)
	if value.get("combatSnapshot") is Dictionary:
		result.combat_snapshot = _combat_from_dictionary(value["combatSnapshot"])
	return result

func _combat_from_dictionary(value: Dictionary) -> CombatSnapshotState:
	var result: CombatSnapshotState = CombatSnapshotState.new()
	result.sim_time_ms = int(value["simTimeMs"])
	result.actors.assign(value["actors"])
	result.event_queue.assign(value["eventQueue"])
	result.rng_streams.assign(value["rngStreams"])
	result.event_log.assign(value["eventLog"])
	result.next_sequence_id = int(value["nextSequenceId"])
	result.rules_hash = str(value["rulesHash"])
	return result

func _wallet_from_dictionary(value: Dictionary) -> WalletState:
	var result: WalletState = WalletState.new()
	result.credits = float(value["CREDITS"])
	result.scrap = float(value["SCRAP"])
	result.data = float(value["DATA"])
	return result
