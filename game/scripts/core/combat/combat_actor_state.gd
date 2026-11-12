class_name CombatActorState
extends RefCounted

var id: String = ""
var kind: String = "enemy"
var side: String = "enemy"
var template_id: String = ""
var display_name: String = ""
var position_tag: String = "right"
var is_boss: bool = false
var is_mechanical: bool = false
var is_healer: bool = false
var hp: float = 1.0
var shield: float = 0.0
var temp_shields: Array[Dictionary] = []
var energy: float = 0.0
var heat: float = 0.0
var heat_lockout: bool = false
var lockout_until: int = 0
var statuses: Dictionary = {}
var buffs: Array[Dictionary] = []
var cooldowns: Dictionary = {}
var cast: Variant = null
var reaction_cast: Variant = null
var channel_busy: Dictionary = {}
var next_attack_at: float = 0.0
var flags: Dictionary = {"lastDamagedAt": -100000.0}
var counters: Dictionary = {}
var icds: Dictionary = {}
var once_per_combat: Dictionary = {}
var ability_next: Dictionary = {}
var alive: bool = true
var base_sheet: Dictionary = {}
var base_mods: Array[Dictionary] = []
var runtime_mods: Array[Dictionary] = []
var attack_damage: float = 0.0
var attack_interval_ms: float = 1000.0
var attack_type: String = "KINETIC"
var accuracy_base: float = 100.0
var proc_multiplier: float = 1.0
var threat_units: int = 1
var owner_id: String = ""
var elite_mod: String = ""
var no_loot: bool = false
var summoned: bool = false
var drone_role: String = ""
var drone_item_id: String = ""
var drone_pellets: int = 1
var last_main_attack_at: int = -100000
var last_target_id: String = ""
var same_target_hits: int = 0
var last_skill_id: String = ""
var same_skill_count: int = 0
var damage_dealt: float = 0.0
var damage_taken: float = 0.0

func to_dictionary() -> Dictionary:
	return {
		"id": id, "kind": kind, "side": side, "templateId": template_id, "name": display_name, "positionTag": position_tag,
		"isBoss": is_boss, "isMechanical": is_mechanical, "isHealer": is_healer,
		"hp": hp, "shield": shield, "tempShields": temp_shields.duplicate(true), "energy": energy, "heat": heat,
		"heatLockout": heat_lockout, "lockoutUntil": lockout_until, "statuses": statuses.duplicate(true), "buffs": buffs.duplicate(true),
		"cooldowns": cooldowns.duplicate(true), "cast": cast, "reactionCast": reaction_cast, "channelBusy": channel_busy.duplicate(true),
		"nextAttackAt": next_attack_at, "flags": flags.duplicate(true), "counters": counters.duplicate(true), "icds": icds.duplicate(true),
		"oncePerCombat": once_per_combat.duplicate(true), "abilityNext": ability_next.duplicate(true), "alive": alive,
		"baseSheet": base_sheet.duplicate(true), "baseMods": base_mods.duplicate(true), "runtimeMods": runtime_mods.duplicate(true),
		"attackDamage": attack_damage, "attackIntervalMs": attack_interval_ms, "attackType": attack_type,
		"accuracyBase": accuracy_base, "procMultiplier": proc_multiplier, "threatUnits": threat_units,
		"ownerId": owner_id, "eliteMod": elite_mod, "noLoot": no_loot, "summoned": summoned,
		"droneRole": drone_role, "droneItemId": drone_item_id, "dronePellets": drone_pellets,
		"lastMainAttackAt": last_main_attack_at, "lastTargetId": last_target_id, "sameTargetHits": same_target_hits,
		"lastSkillId": last_skill_id, "sameSkillCount": same_skill_count, "damageDealt": damage_dealt, "damageTaken": damage_taken,
	}

func clone() -> CombatActorState:
	var copy: CombatActorState = CombatActorState.new()
	for property: Dictionary in get_property_list():
		var property_name: String = str(property.get("name", ""))
		if property_name == "script" or property_name.is_empty():
			continue
		var value: Variant = get(property_name)
		if value is Dictionary or value is Array:
			copy.set(property_name, value.duplicate(true))
		else:
			copy.set(property_name, value)
	return copy
