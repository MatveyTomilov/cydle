class_name CombatFactory
extends RefCounted

const COMBAT_RULES_VERSION: String = "cydle-combat-1.0"

var _enemy_catalog: EnemyCatalog = EnemyCatalog.new()
var _item_catalog: ItemCatalog = ItemCatalog.new()
var _stats: StatMath = StatMath.new()
var _formula: CydleFormula = CydleFormula.new()
var _catalog_loaded: bool = false
var _catalog_error: String = ""

func create_roster(build: Dictionary, enemy_specs: Array[Dictionary], depth: int, options: Dictionary = {}) -> Dictionary:
	if not bool(build.get("valid", false)) or not build.get("mainWeapon") is Dictionary or build.get("mainWeapon", {}).is_empty():
		return _failure("Для боя требуется валидная сборка с основным оружием.")
	if depth < 1 or enemy_specs.is_empty():
		return _failure("Глубина должна быть не меньше 1 и бой должен содержать врага.")
	if not _catalog_loaded:
		var loaded: Dictionary = _enemy_catalog.load_catalog()
		_catalog_loaded = true
		_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _catalog_error.is_empty():
		return _failure("Каталог врагов недоступен: %s" % _catalog_error)
	var item_catalog_result: Dictionary = _item_catalog.load_catalog()
	if not bool(item_catalog_result.get("ok", false)):
		return _failure("Каталог предметов недоступен при создании боевого состава.")
	var operator: CombatActorState = _create_operator(build, options)
	if operator == null:
		return _failure("Не удалось создать оператора из валидной сборки.")
	var drones: Array[CombatActorState] = []
	var build_drones: Array = build.get("drones", [])
	for index: int in range(build_drones.size()):
		var drone: CombatActorState = _create_drone(build, build_drones[index], index, options)
		if drone != null:
			drones.append(drone)
	var enemies: Array[CombatActorState] = []
	for index: int in range(enemy_specs.size()):
		var result: Dictionary = _create_enemy(enemy_specs[index], index, depth, float(options.get("extraEnemyDigitalBonus", 0.0)))
		if not bool(result.get("ok", false)):
			return _failure(str(result.get("error", "Не удалось создать врага.")))
		enemies.append(result["actor"] as CombatActorState)
	return {"ok": true, "operator": operator, "drones": drones, "enemies": enemies, "error": ""}

func _create_operator(build: Dictionary, options: Dictionary) -> CombatActorState:
	var weapon: Dictionary = build.get("mainWeapon", {})
	var sheet: Dictionary = build.get("stats", {}).duplicate(true)
	var interval: float = _formula.attack_interval_ms(float(weapon.get("intervalMs", 1000.0)), float(sheet.get("attackSpeed", 0.0)), float(sheet.get("moreAttackSpeed", 1.0)))
	var hp_fraction: float = clampf(float(options.get("startHpFraction", 1.0)), 0.0, 1.0)
	var shield_fraction: float = clampf(float(options.get("startShieldFraction", 1.0)), 0.0, 1.0)
	var actor: CombatActorState = _base_actor("operator", "operator", "player", str(weapon.get("templateId", "")), "Оператор")
	actor.position_tag = "left"
	actor.hp = float(sheet.get("maxHP", 0.0)) * hp_fraction
	actor.shield = float(sheet.get("maxShield", 0.0)) * shield_fraction
	actor.energy = clampf(float(options.get("startEnergy", 0.0)), 0.0, float(sheet.get("maxEnergy", 0.0)))
	actor.heat = clampf(float(options.get("startHeat", 0.0)) + float(options.get("initialExtraHeat", 0.0)), 0.0, float(sheet.get("maxHeat", 0.0)))
	actor.base_sheet = sheet
	actor.base_mods = build.get("modifiers", []).duplicate(true)
	actor.attack_damage = float(weapon.get("damage", 0.0))
	actor.attack_interval_ms = interval
	actor.attack_type = str(weapon.get("type", "KINETIC"))
	actor.accuracy_base = float(sheet.get("accuracy", 100.0))
	actor.proc_multiplier = float(sheet.get("procMultiplier", 1.0))
	actor.next_attack_at = interval
	actor.flags["firstAttack"] = 1.0
	if actor.attack_type == "KINETIC":
		actor.flags["mainKinetic"] = 1.0
	var pellet_count: int = int(weapon.get("pelletCount", weapon.get("packets", []).size() if weapon.get("packets", []) is Array else 1))
	if pellet_count > 1:
		actor.flags["weaponShotgun"] = 1.0
	var temp_shield: float = float(options.get("initialTempShield", 0.0))
	if temp_shield > 0.0:
		actor.temp_shields.append({"sourceId": "initial", "amount": temp_shield, "cap": temp_shield, "expiresAt": 60000})
	return actor

func _create_drone(build: Dictionary, drone: Variant, index: int, options: Dictionary) -> CombatActorState:
	if not drone is Dictionary:
		return null
	var owner_stats: Dictionary = build.get("stats", {})
	var item_id: String = str(drone.get("itemId", ""))
	var hp_max: float = float(drone.get("hp", 0.0)) * (1.0 + float(owner_stats.get("droneHP", 0.0)) / 100.0) * float(owner_stats.get("moreDroneHP", 1.0))
	var sheet: Dictionary = _stats.empty_sheet()
	sheet["maxHP"] = hp_max
	sheet["maxShield"] = float(drone.get("shield", 0.0)) * (1.0 + float(owner_stats.get("droneShield", 0.0)) / 100.0)
	sheet["armor"] = float(drone.get("armor", 0.0))
	sheet["evasion"] = 0.0
	sheet["accuracy"] = 100.0 + float(owner_stats.get("droneAccuracy", 0.0))
	sheet["critChance"] = 0.0
	sheet["procMultiplier"] = float(owner_stats.get("procMultiplier", 1.0))
	var interval: float = _formula.attack_interval_ms(float(drone.get("intervalMs", 1000.0)), float(owner_stats.get("droneAttackSpeed", 0.0)), 1.0)
	var drone_template_id: String = str(drone.get("templateId", ""))
	var drone_template: Dictionary = _item_catalog.get_template(drone_template_id)
	var drone_name: String = str(drone_template.get("name", drone_template_id))
	var actor: CombatActorState = _base_actor("drone:%d" % index, "drone", "player", drone_template_id, drone_name)
	actor.position_tag = "left"
	actor.owner_id = "operator"
	actor.hp = clampf(float(options.get("droneHp", {}).get(item_id, hp_max)), 0.0, hp_max)
	actor.shield = float(sheet["maxShield"])
	actor.base_sheet = sheet
	actor.base_mods = _override_modifiers(sheet, {"id": "drone:%s" % str(drone.get("templateId", "")), "name": actor.display_name, "kind": "item"})
	actor.attack_damage = float(drone.get("damage", 0.0))
	actor.attack_interval_ms = interval
	actor.attack_type = str(drone.get("type", "KINETIC"))
	actor.accuracy_base = float(sheet["accuracy"])
	actor.proc_multiplier = float(sheet["procMultiplier"])
	actor.next_attack_at = interval
	actor.flags["lastDamagedAt"] = -100000.0
	actor.flags["droneIndex"] = float(index)
	actor.drone_role = str(drone.get("role", ""))
	actor.drone_item_id = item_id
	actor.drone_pellets = int(drone.get("pellets", 1))
	return actor

func _create_enemy(spec: Dictionary, index: int, depth: int, _extra_digital_bonus: float) -> Dictionary:
	var template_id: String = str(spec.get("templateId", ""))
	var template: Dictionary = _enemy_catalog.get_template(template_id)
	if template.is_empty():
		return {"ok": false, "actor": null, "error": "Неизвестный шаблон врага %s." % template_id}
	var elite_id: String = str(spec.get("elite", ""))
	var elite: Dictionary = {}
	if not elite_id.is_empty():
		elite = _enemy_catalog.elite_mods.get(elite_id, {})
		if elite.is_empty():
			return {"ok": false, "actor": null, "error": "Неизвестный элитный модификатор %s." % elite_id}
	var sheet: Dictionary = _stats.empty_sheet()
	sheet["maxHP"] = float(template["hp"]) * _formula.h_depth(float(depth))
	sheet["maxShield"] = float(template["shield"]) * _formula.h_depth(float(depth))
	sheet["armor"] = float(template["armor"])
	sheet["energyRes"] = float(template["resE"])
	sheet["digitalRes"] = float(template["resD"])
	sheet["evasion"] = float(template["evasion"])
	sheet["accuracy"] = float(template.get("accuracy", 100.0))
	sheet["critChance"] = 0.0
	sheet["critMultiplier"] = 1.5
	if not elite.is_empty():
		sheet["maxHP"] = float(sheet["maxHP"]) * 1.75
		if elite_id == "EL_FAST":
			sheet["maxHP"] = float(sheet["maxHP"]) * 0.9
		elif elite_id == "EL_SHIELD":
			sheet["maxShield"] = float(sheet["maxShield"]) * 1.3
		elif elite_id == "EL_VIRUS":
			sheet["digitalRes"] = float(sheet["digitalRes"]) + 10.0
	var interval: float = float(template["intervalMs"]) / (1.2 if elite_id == "EL_FAST" else 1.0)
	var actor: CombatActorState = _base_actor("enemy:%d" % index, "boss" if str(template["role"]) == "boss" else "enemy", "enemy", template_id, str(template["name"]))
	actor.is_boss = str(template["role"]) == "boss"
	actor.is_mechanical = bool(template["mechanical"])
	actor.is_healer = bool(template["healer"])
	actor.hp = float(sheet["maxHP"]) * float(spec.get("hpMult", 1.0))
	actor.shield = float(sheet["maxShield"])
	actor.base_sheet = sheet
	actor.base_mods = _override_modifiers(sheet, {"id": "enemy:%s" % template_id, "name": str(template["name"]), "kind": "enemy"})
	actor.attack_damage = float(template["damage"]) * _formula.d_depth(float(depth)) * float(spec.get("damageMult", 1.0)) * (1.25 if not elite.is_empty() else 1.0)
	actor.attack_interval_ms = interval
	actor.attack_type = str(template["type"])
	actor.accuracy_base = float(sheet["accuracy"])
	actor.threat_units = int(template["threatUnits"])
	actor.next_attack_at = interval
	actor.summoned = bool(spec.get("summoned", false))
	actor.no_loot = bool(spec.get("noLoot", false))
	actor.elite_mod = elite_id
	for ability: Dictionary in template.get("abilities", []):
		actor.ability_next[str(ability["id"])] = float(ability["firstAtMs"])
	for ability: Dictionary in template.get("rotating", []):
		actor.ability_next[str(ability["id"])] = float(ability["firstAtMs"])
	return {"ok": true, "actor": actor, "error": ""}

func _base_actor(actor_id: String, kind: String, side: String, template_id: String, actor_name: String) -> CombatActorState:
	var actor: CombatActorState = CombatActorState.new()
	actor.id = actor_id
	actor.kind = kind
	actor.side = side
	actor.template_id = template_id
	actor.display_name = actor_name
	actor.position_tag = "left" if side == "player" else "right"
	actor.base_sheet = _stats.empty_sheet()
	return actor

func _override_modifiers(sheet: Dictionary, source: Dictionary) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	for stat: String in ["maxHP", "maxShield", "armor", "energyRes", "digitalRes", "evasion", "accuracy", "critChance", "critMultiplier"]:
		modifiers.append(_stats.make_modifier(stat, "OVERRIDE", float(sheet.get(stat, 0.0)), source, {"id": "%s:base:%s" % [str(source["id"]), stat]}))
	return modifiers

func _failure(message: String) -> Dictionary:
	return {"ok": false, "operator": null, "drones": [], "enemies": [], "error": message}
