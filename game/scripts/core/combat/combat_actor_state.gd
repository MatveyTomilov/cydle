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

static func from_dictionary(value: Dictionary) -> CombatActorState:
	var actor: CombatActorState = CombatActorState.new()
	actor.id = str(value.get("id", ""))
	actor.kind = str(value.get("kind", "enemy"))
	actor.side = str(value.get("side", "enemy"))
	actor.template_id = str(value.get("templateId", ""))
	actor.display_name = str(value.get("name", ""))
	actor.position_tag = str(value.get("positionTag", "right"))
	actor.is_boss = bool(value.get("isBoss", false))
	actor.is_mechanical = bool(value.get("isMechanical", false))
	actor.is_healer = bool(value.get("isHealer", false))
	actor.hp = float(value.get("hp", 1.0))
	actor.shield = float(value.get("shield", 0.0))
	actor.temp_shields.assign(value.get("tempShields", []))
	actor.energy = float(value.get("energy", 0.0))
	actor.heat = float(value.get("heat", 0.0))
	actor.heat_lockout = bool(value.get("heatLockout", false))
	actor.lockout_until = int(value.get("lockoutUntil", 0))
	actor.statuses = value.get("statuses", {}).duplicate(true)
	actor.buffs.assign(value.get("buffs", []))
	actor.cooldowns = value.get("cooldowns", {}).duplicate(true)
	actor.cast = value.get("cast")
	actor.reaction_cast = value.get("reactionCast")
	actor.channel_busy = value.get("channelBusy", {}).duplicate(true)
	actor.next_attack_at = float(value.get("nextAttackAt", 0.0))
	actor.flags = value.get("flags", {}).duplicate(true)
	actor.counters = value.get("counters", {}).duplicate(true)
	actor.icds = value.get("icds", {}).duplicate(true)
	actor.once_per_combat = value.get("oncePerCombat", {}).duplicate(true)
	actor.ability_next = value.get("abilityNext", {}).duplicate(true)
	actor.alive = bool(value.get("alive", true))
	actor.base_sheet = value.get("baseSheet", {}).duplicate(true)
	actor.base_mods.assign(value.get("baseMods", []))
	actor.runtime_mods.assign(value.get("runtimeMods", []))
	actor.attack_damage = float(value.get("attackDamage", 0.0))
	actor.attack_interval_ms = float(value.get("attackIntervalMs", 1000.0))
	actor.attack_type = str(value.get("attackType", "KINETIC"))
	actor.accuracy_base = float(value.get("accuracyBase", 100.0))
	actor.proc_multiplier = float(value.get("procMultiplier", 1.0))
	actor.threat_units = int(value.get("threatUnits", 1))
	actor.owner_id = str(value.get("ownerId", ""))
	actor.elite_mod = str(value.get("eliteMod", ""))
	actor.no_loot = bool(value.get("noLoot", false))
	actor.summoned = bool(value.get("summoned", false))
	actor.drone_role = str(value.get("droneRole", ""))
	actor.drone_item_id = str(value.get("droneItemId", ""))
	actor.drone_pellets = int(value.get("dronePellets", 1))
	actor.last_main_attack_at = int(value.get("lastMainAttackAt", -100000))
	actor.last_target_id = str(value.get("lastTargetId", ""))
	actor.same_target_hits = int(value.get("sameTargetHits", 0))
	actor.last_skill_id = str(value.get("lastSkillId", ""))
	actor.same_skill_count = int(value.get("sameSkillCount", 0))
	actor.damage_dealt = float(value.get("damageDealt", 0.0))
	actor.damage_taken = float(value.get("damageTaken", 0.0))
	return actor
