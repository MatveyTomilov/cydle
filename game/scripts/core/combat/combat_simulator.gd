class_name CombatSimulator
extends RefCounted

const COMBAT_RULES_VERSION: String = "cydle-combat-1.0"
const MAX_LOG_EVENTS: int = 5000
const DEFAULT_MAX_DURATION_MS: int = 180000
const STEP_STATUS_IDS: Array[String] = [
	"BLEED", "BURN", "VIRUS", "ARMOR_BREAK", "JAM", "SHOCK", "DRONE_JAM", "SHIELD_LEAK", "STUN",
	"MARK", "SCAN_MARK", "DRONE_MARK", "CONTROLLED", "GUARD", "OVERCLOCK",
	"ACC_BUFF", "EVASION_BUFF", "SHIELD_REGEN_BUFF", "BERSERK", "REGEN_BUFF", "DMG_BUFF",
]
const TICK_MS: int = 100
const SHIELD_REGEN_DELAY_MS: int = 4000

var _factory: CombatFactory = CombatFactory.new()
var _hash: StateHash = StateHash.new()
var _damage: DamageMath = DamageMath.new()
var _formula: CydleFormula = CydleFormula.new()
var _stats: StatMath = StatMath.new()
var _status_catalog: StatusCatalog = StatusCatalog.new()
var _status_catalog_loaded: bool = false
var _status_catalog_error: String = ""

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
	state.minimum_enemy_telegraph_ms = int(config.get("minimumEnemyTelegraphMs", 0))
	state.drone_war = bool(config.get("droneWar", false))
	state.extra_enemy_digital_bonus = float(config.get("extraEnemyDigitalBonus", 0.0))
	state.metrics = _empty_metrics()
	state.rng = _new_rng(state.seed).serialize()
	state.rules_hash = _hash.hash_string(_hash.stable_stringify({"version": COMBAT_RULES_VERSION, "tactics": state.tactics}))
	state.next_event_id = 1
	for trigger_value: Dictionary in state.build.get("triggerEffects", []):
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "PERIODIC" or float(effect.get("periodMs", 0.0)) <= 0.0:
			continue
		var owner: CombatActorState = _trigger_owner(state, str(trigger_value.get("sourceId", "")))
		owner.ability_next["periodic:%s" % str(effect.get("id", ""))] = float(effect.get("periodMs", 0.0))
	var enemy_names: PackedStringArray = PackedStringArray()
	for enemy: CombatActorState in state.enemies:
		enemy_names.append(enemy.display_name)
	_emit(state, "COMBAT_START", "operator", {
		"text": "Бой начался: %s." % ", ".join(enemy_names),
		"data": {"initialTempShield": float(config.get("initialTempShield", 0.0)), "initialExtraHeat": float(config.get("initialExtraHeat", 0.0)), "alliedCount": 0},
	})
	return {"ok": true, "state": state, "error": ""}

func step_combat(state: CombatState) -> Dictionary:
	if state == null:
		return _failure("Нельзя продвинуть пустое состояние боя.")
	if not state.outcome.is_empty():
		return {"ok": true, "state": state, "error": ""}
	if not _supports_basic_auto_step(state):
		for actor: CombatActorState in state.all_actors():
			if actor.cast != null or actor.reaction_cast != null: print("UNSUPPORTED_CAST actor=", actor.id, " kind=", actor.kind, " cast=", actor.cast, " reaction=", actor.reaction_cast)
		if not _supports_skill_trigger_effects(state): print("UNSUPPORTED_TRIGGERS ", state.build.get("triggerEffects", []))
		return _failure("Эта боевая конфигурация требует ещё не перенесённые способности, статусы, триггеры или тактические правила.")
	var next: CombatState = state.clone()
	var rng: DeterministicRng = DeterministicRng.new()
	if not rng.restore(next.rng):
		return _failure("Состояние боевого RNG повреждено.")
	next.time_ms += TICK_MS
	_apply_basic_continuous(next)
	_tick_dot_statuses(next)
	_expire_dot_statuses(next)
	_run_periodic_drone_triggers(next, rng)
	_advance_reaction_cast(next, rng)
	_advance_drone_skill_casts(next, rng)
	_advance_main_skill_cast(next, rng)
	_advance_enemy_ability_casts(next, rng)
	_choose_reaction_skill(next)
	var ready: Array[CombatActorState] = next.all_actors()
	ready.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	for actor: CombatActorState in ready:
		if not actor.alive:
			continue
		if actor.side == "enemy" and actor.cast == null:
			var scheduled_ability: Dictionary = _ready_enemy_ability(next, actor)
			if not scheduled_ability.is_empty():
				_start_enemy_ability(next, actor, scheduled_ability)
				continue
		if actor.kind == "drone" and actor.reaction_cast == null and _try_start_drone_skill(next, actor):
			continue
		if actor.next_attack_at > float(next.time_ms):
			continue
		if actor.side == "enemy" and actor.cast != null:
			continue
		if actor.kind == "operator":
			if actor.cast != null:
				continue
			var chosen: Dictionary = _choose_main_skill(next, rng, actor)
			if bool(chosen.get("started", false)):
				continue
		elif actor.side == "enemy":
			if actor.cast != null:
				continue
		var target: CombatActorState = _pick_auto_target(next, actor)
		if target == null:
			continue
		var attack: Dictionary = _resolve_basic_attack(next, rng, actor, target)
		if not bool(attack.get("ok", false)):
			return _failure(str(attack.get("error", "Автоатака не разрешилась.")))
		_schedule_next_attack(next, actor)
	_resolve_basic_deaths(next)
	_resolve_boss_phases(next)
	_check_terminal(next)
	next.rng = rng.serialize()
	return {"ok": true, "state": next, "error": ""}

func _supports_basic_auto_step(state: CombatState) -> bool:
	if not _supports_skill_trigger_effects(state):
		return false
	for rule_value: Variant in state.tactics.get("rules", []):
		if not rule_value is Dictionary or not bool(rule_value.get("enabled", false)):
			continue
		if str(rule_value.get("skillId", "AUTO")) not in ["AUTO", "SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_BLADE", "SK_PLASMA", "SK_ARC", "SK_OVR", "SK_NEURO", "SK_SEED", "SK_DETONATE", "SK_BREAK", "SK_SCAN", "SK_LEECH", "SK_CHAIN", "SK_KINETIC", "SK_SIDE_FIRE", "SK_SHIELD", "SK_EMP", "SK_GUARD", "SK_VENT", "SK_HEAL", "SK_DRONE_MARK"]:
			return false
		if str(rule_value.get("skillId", "AUTO")) == "SK_BURST" and str(rule_value.get("target", "nearest")) not in ["nearest", "lowestHPPercent"]:
			return false
	if state.extra_enemy_digital_bonus != 0.0:
		return false
	for actor: CombatActorState in state.all_actors():
		if not actor.buffs.is_empty():
			return false
		if actor.reaction_cast != null:
			if not actor.reaction_cast is Dictionary:
				return false
			var reaction_id: String = str(actor.reaction_cast.get("skillId", ""))
			if actor.kind == "operator" and reaction_id not in ["SK_SHIELD", "SK_EMP", "SK_GUARD", "SK_VENT", "SK_HEAL", "SK_DRONE_MARK"]:
				return false
			if actor.kind == "drone" and reaction_id not in ["SK_DRONE_REPAIR", "SK_DRONE_EMP"]:
				return false
			if actor.kind not in ["operator", "drone"]:
				return false
		if actor.cast != null:
			if actor.kind == "operator":
				if not actor.cast is Dictionary or str(actor.cast.get("skillId", "")) not in ["SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_BLADE", "SK_PLASMA", "SK_ARC", "SK_OVR", "SK_NEURO", "SK_SEED", "SK_DETONATE", "SK_BREAK", "SK_SCAN", "SK_LEECH", "SK_CHAIN", "SK_KINETIC", "SK_SIDE_FIRE"]:
					return false
			elif actor.side == "enemy":
				if not actor.cast is Dictionary or str(actor.cast.get("abilityId", "")).is_empty() and (not bool(actor.cast.get("interruptible", false)) or not _has_enabled_tactic(state, "SK_EMP")):
					return false
			elif actor.side != "enemy":
				return false
		for status_id: Variant in actor.statuses.keys():
			if not STEP_STATUS_IDS.has(str(status_id)):
				return false
		if actor.side == "enemy":
			var template: Dictionary = _factory._enemy_catalog.get_template(actor.template_id)
			if not template.get("passives", []).is_empty():
				return false
	return true

func _supports_skill_trigger_effects(state: CombatState) -> bool:
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary:
			return false
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var effect: Dictionary = trigger_value.get("effect", {})
		var effect_id: String = str(effect.get("id", ""))
		var skill_trigger: bool = source_id in ["SK_BLADE", "SK_NEURO", "SK_SEED", "SK_BREAK"]
		var periodic_item_trigger: bool = effect_id in ["DR_MED_heal", "DR_EMP_interrupt", "TR_SUPPORT_blast"] and str(effect.get("event", "")) == "PERIODIC" and str(trigger_value.get("sourceKind", "")) == "item"
		var attack_counter_trigger: bool = effect_id in ["ARC_E2_splash", "FOCUS_D1_virus", "DR_ARC_shock"] and str(effect.get("event", "")) == "ON_ATTACK_COUNTER" and str(trigger_value.get("sourceKind", "")) == "item"
		if not skill_trigger and not periodic_item_trigger and not attack_counter_trigger:
			return false
	return true

func _trigger_owner(state: CombatState, source_id: String) -> CombatActorState:
	for drone: CombatActorState in state.drones:
		if drone.drone_item_id == source_id:
			return drone
	return state.operator

func _run_periodic_drone_triggers(state: CombatState, rng: DeterministicRng) -> void:
	for trigger_value: Dictionary in state.build.get("triggerEffects", []):
		var effect: Dictionary = trigger_value.get("effect", {})
		var effect_id: String = str(effect.get("id", ""))
		if effect_id not in ["DR_MED_heal", "DR_EMP_interrupt", "TR_SUPPORT_blast"]:
			continue
		var owner: CombatActorState = _trigger_owner(state, str(trigger_value.get("sourceId", "")))
		var schedule_key: String = "periodic:%s" % effect_id
		var period_ms: float = float(effect.get("periodMs", 0.0))
		if not owner.alive or period_ms <= 0.0 or float(owner.ability_next.get(schedule_key, period_ms)) > float(state.time_ms):
			continue
		owner.ability_next[schedule_key] = float(owner.ability_next.get(schedule_key, period_ms)) + period_ms
		var action_id: String = "%s:periodic:%s:%d" % [owner.id, effect_id, int(owner.counters.get(effect_id, 0)) + 1]
		owner.counters[effect_id] = int(owner.counters.get(effect_id, 0)) + 1
		_emit(state, "TRIGGER", owner.id, {"actionId": action_id, "text": "%s: периодический триггер %s." % [owner.display_name, effect_id], "data": {"periodMs": period_ms}})
		if effect_id == "DR_MED_heal":
			var max_shield: float = float(_effective_sheet(state, state.operator).get("maxShield", 0.0))
			var restored: float = minf(float(effect.get("action", {}).get("amount", 18.0)), maxf(0.0, max_shield - state.operator.shield))
			state.operator.shield += restored
			if restored > 0.0:
				_emit(state, "SHIELD_GAIN", owner.id, {"targetId": state.operator.id, "actionId": action_id, "text": "%s: оператору +%s щита." % [owner.display_name, _one_decimal(restored)], "data": {"amount": restored, "source": effect_id}})
		elif effect_id == "DR_EMP_interrupt":
			var target: CombatActorState = null
			for enemy: CombatActorState in state.enemies:
				if enemy.alive and enemy.cast is Dictionary and bool(enemy.cast.get("interruptible", false)):
					target = enemy
					break
			if target != null:
				var emp_available: bool = false
				for skill: Dictionary in state.build.get("skills", []):
					if str(skill.get("special", "")) == "DRONE_EMP":
						emp_available = true
						break
				if emp_available and owner.reaction_cast == null:
					_try_start_drone_skill(state, owner)
				else:
					target.cast = null
					state.metrics["interrupts"] = int(state.metrics.get("interrupts", 0)) + 1
					_emit(state, "CAST_INTERRUPT", owner.id, {"targetId": target.id, "actionId": action_id, "text": "%s: каст прерван." % target.display_name})
		elif effect_id == "TR_SUPPORT_blast":
			var target: CombatActorState = _pick_auto_target(state, owner)
			if target == null:
				continue
			var tech_level: int = _trigger_item_tech_level(state, str(trigger_value.get("sourceId", "")))
			var coefficient: float = float(effect.get("action", {}).get("coefficient", 40.0))
			var raw: float = coefficient * _formula.h_depth(float(tech_level))
			var hit: Dictionary = _resolve_basic_hit(state, rng, owner, target, raw, "ENERGY", action_id, false)
			if not bool(hit.get("ok", false)):
				push_error("CombatSimulator: support relay hit failed: %s" % str(hit.get("error", "unknown error")))

func _trigger_item_tech_level(state: CombatState, source_id: String) -> int:
	for item_value: Variant in state.build.get("equipment", {}).values():
		if item_value is ItemInstance and item_value.item_id == source_id:
			return maxi(1, item_value.tech_level)
	return 1

func _has_enabled_tactic(state: CombatState, skill_id: String) -> bool:
	for rule_value: Variant in state.tactics.get("rules", []):
		if rule_value is Dictionary and bool(rule_value.get("enabled", false)) and str(rule_value.get("skillId", "")) == skill_id:
			return true
	return false

func _choose_main_skill(state: CombatState, _rng: DeterministicRng, actor: CombatActorState) -> Dictionary:
	var rules: Array = state.tactics.get("rules", []).duplicate(true)
	rules = rules.filter(func(rule: Variant) -> bool: return rule is Dictionary and bool(rule.get("enabled", false)))
	rules.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority: int = int(left.get("priority", 0))
		var right_priority: int = int(right.get("priority", 0))
		return left_priority > right_priority if left_priority != right_priority else str(left.get("id", "")) < str(right.get("id", "")))
	for rule: Dictionary in rules:
		var skill_id: String = str(rule.get("skillId", "AUTO"))
		if skill_id == "AUTO":
			if _rule_conditions_pass(state, actor, rule, null):
				return {"started": false}
			_record_rule_failure(state, str(rule.get("id", "")), "conditions")
			continue
		var skill: Dictionary = _equipped_skill(state, skill_id)
		var rule_id: String = str(rule.get("id", ""))
		if skill.is_empty():
			_record_rule_failure(state, rule_id, "not_equipped")
			continue
		if float(actor.cooldowns.get(skill_id, 0.0)) > float(state.time_ms):
			_record_rule_failure(state, rule_id, "cooldown")
			continue
		var energy_cost: float = _main_skill_energy_cost(skill, _effective_sheet(state, actor))
		if float(actor.energy) < energy_cost:
			_record_rule_failure(state, rule_id, "energy")
			continue
		var target: CombatActorState = _pick_rule_target(state, actor, str(rule.get("target", skill.get("targetMode", "nearest"))))
		if target == null and str(skill.get("targetMode", "")) != "self":
			_record_rule_failure(state, rule_id, "no_target")
			continue
		if skill.get("requires", []).has("VIRUS") and (target == null or not _has_status(target, "VIRUS")):
			_record_rule_failure(state, rule_id, "requirement")
			continue
		if skill.get("requires", []).has("SIDEARM") and state.build.get("sidearm", {}).is_empty():
			_record_rule_failure(state, rule_id, "requirement")
			continue
		if not _rule_conditions_pass(state, actor, rule, target):
			_record_rule_failure(state, rule_id, "conditions")
			continue
		_start_main_skill(state, actor, skill, target)
		return {"started": true}
	return {"started": false}

func _main_skill_energy_cost(skill: Dictionary, sheet: Dictionary) -> float:
	var cost: float = float(skill.get("energyCost", 0.0))
	if cost <= 0.0:
		return 0.0
	if str(skill.get("basis", "")) == "TECH_E":
		cost = maxf(1.0, cost - float(sheet.get("energySkillCostFlat", 0.0)))
	cost *= 1.0 - clampf(float(sheet.get("skillEnergyCostLess", 0.0)), 0.0, 60.0) / 100.0
	return maxf(0.0, cost)

func _choose_reaction_skill(state: CombatState) -> void:
	var actor: CombatActorState = state.operator
	if not actor.alive or actor.reaction_cast != null:
		return
	var rules: Array = state.tactics.get("rules", []).duplicate(true)
	rules = rules.filter(func(rule: Variant) -> bool:
		return rule is Dictionary and bool(rule.get("enabled", false)) and str(rule.get("skillId", "")) in ["SK_SHIELD", "SK_EMP", "SK_GUARD", "SK_VENT", "SK_HEAL", "SK_DRONE_MARK"])
	rules.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority: int = int(left.get("priority", 0))
		var right_priority: int = int(right.get("priority", 0))
		return left_priority > right_priority if left_priority != right_priority else str(left.get("id", "")) < str(right.get("id", "")))
	for rule: Dictionary in rules:
		var skill_id: String = str(rule.get("skillId", ""))
		var skill: Dictionary = _equipped_skill(state, skill_id)
		var rule_id: String = str(rule.get("id", ""))
		if skill.is_empty():
			_record_rule_failure(state, rule_id, "not_equipped")
			continue
		if float(actor.cooldowns.get(skill_id, 0.0)) > float(state.time_ms):
			_record_rule_failure(state, rule_id, "cooldown")
			continue
		var target: CombatActorState = _pick_rule_target(state, actor, str(rule.get("target", skill.get("targetMode", "nearest"))))
		if target == null and str(skill.get("targetMode", "")) != "self":
			_record_rule_failure(state, rule_id, "no_target")
			continue
		if skill_id == "SK_EMP" and (target == null or target.cast == null or not bool(target.cast.get("interruptible", false))):
			_record_rule_failure(state, rule_id, "no_interruptible")
			continue
		if not _rule_conditions_pass(state, actor, rule, target):
			_record_rule_failure(state, rule_id, "conditions")
			continue
		var sheet: Dictionary = _effective_sheet(state, actor)
		var cost: float = _reaction_energy_cost(skill, sheet)
		if actor.energy < cost:
			_record_rule_failure(state, rule_id, "energy")
			continue
		_start_reaction_skill(state, actor, skill, target, cost, sheet)
		return

func _reaction_energy_cost(skill: Dictionary, sheet: Dictionary) -> float:
	var cost: float = float(skill.get("energyCost", 0.0))
	if skill.get("id", "") == "SK_EMP":
		cost = maxf(1.0, cost - float(sheet.get("empCostFlat", 0.0)))
	elif skill.get("id", "") == "SK_SHIELD":
		cost = maxf(1.0, cost - float(sheet.get("shieldCostFlat", 0.0)))
	if cost > 0.0:
		cost *= 1.0 - clampf(float(sheet.get("skillEnergyCostLess", 0.0)), 0.0, 60.0) / 100.0
		cost *= 1.0 + float(sheet.get("reactionCostMore", 0.0)) / 100.0
	return maxf(0.0, cost)

func _start_reaction_skill(state: CombatState, actor: CombatActorState, skill: Dictionary, target: CombatActorState, cost: float, sheet: Dictionary) -> void:
	var skill_id: String = str(skill.get("id", ""))
	actor.energy = clampf(actor.energy - cost, 0.0, float(sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	var heat_delta: float = float(skill.get("heatDelta", 0.0))
	if skill_id == "SK_VENT":
		actor.heat = maxf(0.0, actor.heat - 35.0)
		if actor.heat <= 80.0:
			actor.heat_lockout = false
	else:
		_gain_basic_heat(state, actor, heat_delta)
	var cd_base: float = float(skill.get("cooldownMs", 0.0)) * (1.0 - clampf(float(sheet.get("reactionCooldownLess", 0.0)), 0.0, 80.0) / 100.0)
	var cooldown: float = _formula.cooldown_ms(cd_base, float(sheet.get("cooldownRecovery", 0.0)))
	actor.cooldowns[skill_id] = float(state.time_ms) + cooldown
	actor.counters["casts"] = int(actor.counters.get("casts", 0)) + 1
	var action_id: String = "%s:skill:%s:%d" % [actor.id, skill_id, int(actor.counters["casts"])]
	actor.reaction_cast = {
		"actionId": action_id, "skillId": skill_id, "startedAt": state.time_ms,
		"resolveAt": float(state.time_ms) + float(skill.get("windupMs", 0.0)),
		"endAt": float(state.time_ms) + float(skill.get("windupMs", 0.0)) + float(skill.get("recoveryMs", 0.0)),
		"targetId": target.id if target != null else "", "interruptible": false,
		"telegraph": false, "channel": "reaction",
	}
	actor.last_skill_id = skill_id
	_record_enemy_judge_program(state, skill_id)
	if target != null:
		actor.last_target_id = target.id
	_emit(state, "CAST_START", actor.id, {
		"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": action_id,
		"text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))],
		"data": {"channel": "reaction", "windupMs": skill.get("windupMs", 0), "recoveryMs": skill.get("recoveryMs", 0), "cooldownMs": cooldown, "emergency": false},
	})

func _advance_reaction_cast(state: CombatState, rng: DeterministicRng) -> void:
	var actor: CombatActorState = state.operator
	if actor.reaction_cast == null or not actor.reaction_cast is Dictionary:
		return
	var cast: Dictionary = actor.reaction_cast
	if _has_status(actor, "STUN"):
		cast["resolveAt"] = float(cast.get("resolveAt", 0.0)) + TICK_MS
		cast["endAt"] = float(cast.get("endAt", 0.0)) + TICK_MS
		return
	if not bool(cast.get("resolved", false)) and state.time_ms >= float(cast.get("resolveAt", 0.0)):
		cast["resolved"] = true
		_resolve_reaction_skill(state, rng, actor, cast)
	if state.time_ms >= float(cast.get("endAt", 0.0)):
		actor.reaction_cast = null

func _advance_drone_skill_casts(state: CombatState, rng: DeterministicRng) -> void:
	for drone: CombatActorState in state.drones:
		if drone.reaction_cast == null or not drone.reaction_cast is Dictionary:
			continue
		var cast: Dictionary = drone.reaction_cast
		if _has_status(drone, "STUN"):
			cast["resolveAt"] = float(cast.get("resolveAt", 0.0)) + TICK_MS
			cast["endAt"] = float(cast.get("endAt", 0.0)) + TICK_MS
			continue
		if not bool(cast.get("resolved", false)) and state.time_ms >= float(cast.get("resolveAt", 0.0)):
			cast["resolved"] = true
			_resolve_drone_skill(state, rng, drone, cast)
		if state.time_ms >= float(cast.get("endAt", 0.0)):
			drone.reaction_cast = null

func _try_start_drone_skill(state: CombatState, drone: CombatActorState) -> bool:
	var skill: Dictionary = {}
	var target: CombatActorState = null
	if drone.drone_role == "medic" and state.operator.alive:
		for candidate: Dictionary in state.build.get("skills", []):
			if str(candidate.get("special", "")) == "DRONE_REPAIR":
				skill = candidate
				break
		if not skill.is_empty():
			var drone_hp: float = float(_effective_sheet(state, drone).get("maxHP", 0.0))
			var operator_shield: float = float(_effective_sheet(state, state.operator).get("maxShield", 0.0))
			if drone.hp >= drone_hp and state.operator.shield >= operator_shield:
				skill = {}
	elif drone.drone_role == "emp":
			for enemy: CombatActorState in state.enemies:
				if enemy.alive and enemy.cast is Dictionary and bool(enemy.cast.get("interruptible", false)):
					target = enemy
					break
			if target != null:
				for candidate: Dictionary in state.build.get("skills", []):
					if str(candidate.get("special", "")) == "DRONE_EMP":
						skill = candidate
						break
	if skill.is_empty() or float(drone.cooldowns.get(str(skill.get("id", "")), 0.0)) > float(state.time_ms):
		return false
	var skill_id: String = str(skill.get("id", ""))
	drone.cooldowns[skill_id] = float(state.time_ms) + float(skill.get("cooldownMs", 0.0))
	drone.counters["casts"] = int(drone.counters.get("casts", 0)) + 1
	var action_id: String = "%s:skill:%s:%d" % [drone.id, skill_id, int(drone.counters["casts"])]
	var windup: float = float(skill.get("windupMs", 0.0))
	drone.reaction_cast = {"actionId": action_id, "skillId": skill_id, "startedAt": state.time_ms, "resolveAt": float(state.time_ms) + windup, "endAt": float(state.time_ms) + windup + float(skill.get("recoveryMs", 0.0)), "targetId": target.id if target != null else drone.id, "interruptible": false, "telegraph": false, "channel": str(skill.get("channel", "droneA"))}
	_emit(state, "CAST_START", drone.id, {"skillId": skill_id, "targetId": drone.reaction_cast["targetId"], "actionId": action_id, "text": "%s: %s." % [drone.display_name, str(skill.get("name", skill_id))], "data": {"channel": drone.reaction_cast["channel"], "windupMs": windup, "recoveryMs": skill.get("recoveryMs", 0), "cooldownMs": skill.get("cooldownMs", 0)}})
	return true

func _resolve_drone_skill(state: CombatState, rng: DeterministicRng, drone: CombatActorState, cast: Dictionary) -> void:
	var skill_id: String = str(cast.get("skillId", ""))
	var skill: Dictionary = _equipped_skill(state, skill_id)
	if skill.is_empty():
		return
	state.metrics["skillUses"][skill_id] = int(state.metrics["skillUses"].get(skill_id, 0)) + 1
	var action_id: String = str(cast.get("actionId", ""))
	if str(skill.get("special", "")) == "DRONE_REPAIR":
		var max_hp: float = float(_effective_sheet(state, drone).get("maxHP", 0.0))
		var healed: float = minf(25.0, maxf(0.0, max_hp - drone.hp))
		drone.hp += healed
		if healed > 0.0:
			state.metrics["healingDone"] = float(state.metrics.get("healingDone", 0.0)) + healed
			_emit(state, "HEAL", drone.id, {"targetId": drone.id, "actionId": action_id, "text": "%s: восстановлено %s HP." % [drone.display_name, _one_decimal(healed)], "data": {"amount": healed, "source": skill_id}})
		var max_shield: float = float(_effective_sheet(state, state.operator).get("maxShield", 0.0))
		var restored: float = minf(20.0, maxf(0.0, max_shield - state.operator.shield))
		state.operator.shield += restored
		if restored > 0.0:
			_emit(state, "SHIELD_GAIN", drone.id, {"targetId": state.operator.id, "actionId": action_id, "text": "%s: оператору +%s щита." % [drone.display_name, _one_decimal(restored)], "data": {"amount": restored, "source": skill_id}})
		return
	if str(skill.get("special", "")) == "DRONE_EMP":
		var target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
		if target == null or not target.alive:
			return
		if target.cast is Dictionary and bool(target.cast.get("interruptible", false)):
			target.cast = null
			state.metrics["interrupts"] = int(state.metrics.get("interrupts", 0)) + 1
			_emit(state, "CAST_INTERRUPT", drone.id, {"targetId": target.id, "actionId": action_id, "text": "%s: каст прерван." % target.display_name})
		var hit: Dictionary = _resolve_basic_hit(state, rng, drone, target, drone.attack_damage * float(skill.get("coefficient", 0.75)), "DIGITAL", action_id, false, skill_id)
		if bool(hit.get("ok", false)) and bool(hit.get("hit", false)):
			_add_simple_status(state, drone, target, "JAM", 2000.0)

func _resolve_reaction_skill(state: CombatState, rng: DeterministicRng, actor: CombatActorState, cast: Dictionary) -> void:
	var skill_id: String = str(cast.get("skillId", ""))
	var skill: Dictionary = _equipped_skill(state, skill_id)
	if skill.is_empty():
		return
	var target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
	state.metrics["skillUses"][skill_id] = int(state.metrics["skillUses"].get(skill_id, 0)) + 1
	_emit(state, "REACTION", actor.id, {"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": cast.get("actionId", ""), "text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))], "data": {"channel": "reaction"}})
	var sheet: Dictionary = _effective_sheet(state, actor)
	match str(skill.get("special", "")):
		"TEMP_SHIELD":
			var pool: Dictionary = {}
			for existing: Dictionary in actor.temp_shields:
				if str(existing.get("sourceId", "")) == "SK_SHIELD":
					pool = existing
					break
			var before: float = float(pool.get("amount", 0.0))
			if pool.is_empty():
				pool = {"sourceId": "SK_SHIELD", "amount": 0.0, "cap": 90.0, "expiresAt": 0.0}
				actor.temp_shields.append(pool)
			pool["amount"] = minf(90.0, before + 60.0)
			pool["cap"] = 90.0
			pool["expiresAt"] = float(state.time_ms) + 5000.0
			_emit(state, "SHIELD_GAIN", actor.id, {"actionId": cast.get("actionId", ""), "text": "%s: аварийный щит +%s." % [actor.display_name, _one_decimal(float(pool["amount"]) - before)], "data": {"amount": float(pool["amount"]) - before, "total": pool["amount"], "cap": 90.0}})
		"EMP":
			if target == null or not target.alive:
				return
			if target.cast is Dictionary and bool(target.cast.get("interruptible", false)):
				target.cast = null
				state.metrics["interrupts"] = int(state.metrics.get("interrupts", 0)) + 1
				_emit(state, "CAST_INTERRUPT", actor.id, {"targetId": target.id, "actionId": cast.get("actionId", ""), "text": "%s: каст прерван." % target.display_name})
			var effective: Dictionary = _effective_sheet(state, actor, target)
			var hit: Dictionary = _resolve_basic_hit(state, rng, actor, target, float(effective.get("techPower", 0.0)) * float(skill.get("coefficient", 0.6)) * float(effective.get("moreSkillDigital", 1.0)), "DIGITAL", str(cast.get("actionId", "")), false, skill_id)
			if not bool(hit.get("ok", false)):
				state.outcome = "ERROR"
		"GUARD":
			_add_simple_status(state, actor, actor, "GUARD", 2000)
		"VENT":
			_emit(state, "HEAT", actor.id, {"actionId": cast.get("actionId", ""), "text": "%s: продувка, нагрев %s." % [actor.display_name, _one_decimal(actor.heat)], "data": {"heat": actor.heat}})
		"HEAL":
			var max_hp: float = float(sheet.get("maxHP", 1.0))
			var healing: float = minf(30.0 + minf(0.10 * max_hp, 0.12 * max_hp), 0.22 * max_hp) * (1.0 + float(sheet.get("healing", 0.0)) / 100.0)
			var before_hp: float = actor.hp
			actor.hp = clampf(actor.hp + healing, 0.0, max_hp)
			var actual: float = actor.hp - before_hp
			state.metrics["healingDone"] = float(state.metrics.get("healingDone", 0.0)) + actual
			_emit(state, "HEAL", actor.id, {"actionId": cast.get("actionId", ""), "text": "%s: ремодуль +%s HP." % [actor.display_name, _one_decimal(actual)], "data": {"amount": actual, "overheal": healing - actual}})
		"DRONE_MARK":
			if target != null and target.alive:
				_add_simple_status(state, actor, target, "DRONE_MARK", 5000.0 + float(sheet.get("droneMarkBonusMs", 0.0)))

func _add_simple_status(state: CombatState, source: CombatActorState, target: CombatActorState, status_id: String, duration_ms: float) -> void:
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return
	if not STEP_STATUS_IDS.has(status_id) or not target.alive:
		return
	var definition: Dictionary = _status_catalog.get_definition(status_id)
	if definition.is_empty():
		return
	if status_id == "STUN":
		if float(target.icds.get("STUN", 0.0)) > float(state.time_ms):
			return
		target.icds["STUN"] = float(state.time_ms) + 3000.0
		if target.is_boss:
			duration_ms *= 0.5
	var entries: Array = target.statuses.get(status_id, [])
	if entries.is_empty():
		entries.append({"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration_ms, "nextTickAt": float(state.time_ms) + duration_ms, "snapshot": 0.0, "stacks": 1})
	else:
		entries[0]["stacks"] = mini(int(definition.get("maxStacks", 1)), int(entries[0].get("stacks", 1)) + 1)
		entries[0]["expiresAt"] = float(state.time_ms) + duration_ms
	target.statuses[status_id] = entries
	_emit(state, "STATUS_APPLY", source.id, {"targetId": target.id, "statusId": status_id, "text": "%s: %s." % [target.display_name, str(definition.get("name", status_id))], "data": {"stacks": int(entries[0].get("stacks", 1)), "durationMs": duration_ms}})

func _rule_conditions_pass(state: CombatState, actor: CombatActorState, rule: Dictionary, target: CombatActorState) -> bool:
	var conditions: Array = rule.get("conditions", [])
	if conditions.is_empty():
		return true
	var logic: String = str(rule.get("logic", "AND"))
	for condition_value: Variant in conditions:
		var passed: bool = condition_value is Dictionary and _eval_tactic_condition(state, actor, condition_value, target)
		if logic == "OR" and passed:
			return true
		if logic != "OR" and not passed:
			return false
	return logic == "OR" if logic == "OR" else true

func _eval_tactic_condition(state: CombatState, actor: CombatActorState, condition: Dictionary, target: CombatActorState) -> bool:
	var kind: String = str(condition.get("kind", "always"))
	var value: float = float(condition.get("value", 0.0))
	var max_hp: float = maxf(1.0, float(actor.base_sheet.get("maxHP", 1.0)))
	var max_shield: float = float(actor.base_sheet.get("maxShield", 0.0))
	var living: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive:
			living.append(enemy)
	match kind:
		"always": return true
		"hpBelow": return actor.hp / max_hp < value
		"hpAbove": return actor.hp / max_hp > value
		"shieldBelow": return max_shield <= 0.0 or actor.shield / max_shield < value
		"energyAtLeast": return actor.energy >= value
		"energyBelow": return actor.energy < value
		"heatAtLeast": return actor.heat >= value
		"heatBelow": return actor.heat < value
		"heatLocked": return actor.heat_lockout
		"enemiesAtLeast": return living.size() >= int(value)
		"enemiesAtMost": return living.size() <= int(value)
		"enemyCasting":
			for enemy: CombatActorState in living:
				if enemy.cast != null and (not bool(condition.get("interruptibleOnly", false)) or bool(enemy.cast.get("interruptible", false))):
					return true
			return false
		"enemyType":
			for enemy: CombatActorState in living:
				match str(condition.get("value", "")):
					"boss": if enemy.is_boss: return true
					"healer": if enemy.is_healer: return true
					"mechanical": if enemy.is_mechanical: return true
					"elite": if not enemy.elite_mod.is_empty(): return true
			return false
		"targetStatus": return target != null and int(target.statuses.get(str(condition.get("status", "")), {}).get("stacks", 0)) >= int(condition.get("minStacks", 1))
		"droneAlive":
			var alive_count: int = 0
			for drone: CombatActorState in state.drones:
				if drone.alive: alive_count += 1
			return alive_count >= int(value)
		"cooldownReady": return float(actor.cooldowns.get(str(condition.get("skillId", "")), 0.0)) <= float(state.time_ms)
		"effectUptime": return actor.statuses.has(str(condition.get("status", "")))
		"timeAtLeast": return float(state.time_ms) >= value
		"not": return not _eval_tactic_condition(state, actor, condition.get("inner", {}), target)
		"any":
			for inner: Variant in condition.get("inner", []):
				if inner is Dictionary and _eval_tactic_condition(state, actor, inner, target): return true
			return false
		"all":
			for inner: Variant in condition.get("inner", []):
				if inner is Dictionary and not _eval_tactic_condition(state, actor, inner, target): return false
			return true
	return false

func _equipped_skill(state: CombatState, skill_id: String) -> Dictionary:
	for skill: Variant in state.build.get("skills", []):
		if skill is Dictionary and str(skill.get("id", "")) == skill_id:
			return skill
	return {}

func _pick_rule_target(state: CombatState, actor: CombatActorState, mode: String) -> CombatActorState:
	if mode == "self":
		return actor
	var enemies: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive:
			enemies.append(enemy)
	enemies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	if enemies.is_empty():
		return null
	if mode == "imminentCast":
		for enemy: CombatActorState in enemies:
			if enemy.cast is Dictionary and bool(enemy.cast.get("interruptible", false)):
				return enemy
		return null
	if mode == "boss":
		for enemy: CombatActorState in enemies:
			if enemy.is_boss:
				return enemy
	if mode == "lowestHPPercent":
		enemies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool:
			var left_fraction: float = left.hp / maxf(1.0, float(left.base_sheet.get("maxHP", 1.0)))
			var right_fraction: float = right.hp / maxf(1.0, float(right.base_sheet.get("maxHP", 1.0)))
			return left_fraction < right_fraction if not is_equal_approx(left_fraction, right_fraction) else left.id < right.id)
	if mode == "infected":
		for enemy: CombatActorState in enemies:
			if _has_status(enemy, "VIRUS"):
				return enemy
	if mode == "marked":
		for enemy: CombatActorState in enemies:
			if _has_status(enemy, "MARK") or _has_status(enemy, "SCAN_MARK") or _has_status(enemy, "DRONE_MARK"):
				return enemy
	if mode in ["otherEnemy", "secondary"]:
		for enemy: CombatActorState in enemies:
			if enemy.id != actor.last_target_id:
				return enemy
	return enemies[0]

func _record_enemy_judge_program(state: CombatState, skill_id: String) -> void:
	for judge: CombatActorState in state.enemies:
		if not judge.alive or judge.template_id != "E24":
			continue
		var punish: Dictionary = {}
		for ability: Dictionary in _enemy_ability_definitions(judge, state):
			if str(ability.get("kind", "")) == "jamPunish":
				punish = ability
				break
		if punish.is_empty():
			continue
		if skill_id.is_empty():
			judge.flags["observedProgramId"] = ""
			judge.flags["observedProgramCount"] = 0
			continue
		var count: int = int(judge.flags.get("observedProgramCount", 0)) + 1 if str(judge.flags.get("observedProgramId", "")) == skill_id else 1
		judge.flags["observedProgramId"] = skill_id
		judge.flags["observedProgramCount"] = count
		if count >= 3:
			_add_simple_status(state, judge, state.operator, str(punish.get("status", "JAM")), float(punish.get("statusDurationMs", 2000.0)))
			judge.flags["observedProgramCount"] = 0

func _start_main_skill(state: CombatState, actor: CombatActorState, skill: Dictionary, target: CombatActorState) -> void:
	var skill_id: String = str(skill.get("id", ""))
	var cost: float = _main_skill_energy_cost(skill, _effective_sheet(state, actor))
	actor.energy = clampf(actor.energy - cost, 0.0, float(actor.base_sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	_gain_basic_heat(state, actor, float(skill.get("heatDelta", 0.0)))
	var cooldown: float = _formula.cooldown_ms(float(skill.get("cooldownMs", 0.0)), float(_effective_sheet(state, actor).get("cooldownRecovery", 0.0)))
	if skill.get("tags", []).has("D") and _has_status(actor, "JAM"):
		cooldown *= 1.3
	actor.cooldowns[skill_id] = float(state.time_ms) + cooldown
	actor.counters["casts"] = int(actor.counters.get("casts", 0)) + 1
	var action_id: String = "%s:skill:%s:%d" % [actor.id, skill_id, int(actor.counters["casts"])]
	var windup: float = float(skill.get("windupMs", 0.0))
	var recovery: float = float(skill.get("recoveryMs", 0.0))
	var end_at: float = float(state.time_ms) + windup + recovery
	actor.cast = {
		"actionId": action_id, "skillId": skill_id, "startedAt": state.time_ms,
		"resolveAt": float(state.time_ms) + windup, "endAt": end_at,
		"targetId": target.id if target != null else "", "interruptible": bool(skill.get("interruptible", false)),
		"telegraph": false, "channel": "main",
	}
	actor.last_skill_id = skill_id
	_record_enemy_judge_program(state, skill_id)
	if target != null:
		actor.last_target_id = target.id
	actor.next_attack_at = end_at
	actor.last_main_attack_at = state.time_ms
	_emit(state, "CAST_START", actor.id, {
		"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": action_id,
		"text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))],
		"data": {"channel": "main", "windupMs": windup, "recoveryMs": recovery, "cooldownMs": cooldown, "emergency": false},
	})

func _advance_main_skill_cast(state: CombatState, rng: DeterministicRng) -> void:
	var actor: CombatActorState = state.operator
	if actor.cast == null or not actor.cast is Dictionary:
		return
	var cast: Dictionary = actor.cast
	if _has_status(actor, "STUN"):
		cast["resolveAt"] = float(cast.get("resolveAt", 0.0)) + TICK_MS
		cast["endAt"] = float(cast.get("endAt", 0.0)) + TICK_MS
		actor.next_attack_at += TICK_MS
		return
	if not bool(cast.get("resolved", false)) and state.time_ms >= float(cast.get("resolveAt", 0.0)):
		cast["resolved"] = true
		_resolve_main_skill(state, rng, actor, cast)
	if state.time_ms >= float(cast.get("endAt", 0.0)):
		actor.cast = null

func _enemy_ability_definitions(actor: CombatActorState, state: CombatState = null) -> Array[Dictionary]:
	var template: Dictionary = _enemy_ability_template(actor)
	var abilities: Array[Dictionary] = []
	for field: String in ["abilities", "rotating"]:
		for value: Variant in template.get(field, []):
			if value is Dictionary:
				abilities.append(value)
	if actor.elite_mod == "EL_ANTI_DRONE" or state != null and state.drone_war and not actor.elite_mod.is_empty():
		abilities.append({"id": "EL_ANTI_DRONE_jam", "kind": "applyStatus", "firstAtMs": 8000, "everyMs": 8000, "windupMs": 1200, "telegraphMs": 1200, "interruptible": true, "status": "DRONE_JAM", "statusDurationMs": 2000, "desc": "Элитная помеха дронам"})
	return abilities

func _ready_enemy_ability(state: CombatState, actor: CombatActorState) -> Dictionary:
	var ready: Array[Dictionary] = []
	for ability: Dictionary in _enemy_ability_definitions(actor, state):
		var kind: String = str(ability.get("kind", ""))
		var scheduled_status: bool = kind == "applyStatus" and (float(ability.get("firstAtMs", 0.0)) > 0.0 or float(ability.get("everyMs", 0.0)) > 0.0)
		if kind not in ["heavyAttack", "shieldBypass", "heal", "heat", "shieldRestore", "mark", "escape", "wantedBoost", "protectAlly"] and not scheduled_status:
			continue
		if float(actor.ability_next.get(str(ability.get("id", "")), 999999999.0)) <= float(state.time_ms):
			ready.append(ability)
	ready.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_at: float = float(actor.ability_next.get(str(left.get("id", "")), 0.0))
		var right_at: float = float(actor.ability_next.get(str(right.get("id", "")), 0.0))
		return left_at < right_at if not is_equal_approx(left_at, right_at) else str(left.get("id", "")) < str(right.get("id", "")))
	return ready[0] if not ready.is_empty() else {}

func _start_enemy_ability(state: CombatState, actor: CombatActorState, ability: Dictionary) -> void:
	var ability_id: String = str(ability.get("id", ""))
	var cast_speed: float = maxf(0.0, float(actor.flags.get("bossCastSpeedIncrease", 0.0)))
	var elite_windup: float = 200.0 if actor.elite_mod == "EL_PEN" else 0.0
	var windup: float = maxf(0.0, (float(ability.get("windupMs", 0.0)) * state.enemy_windup_mult + elite_windup) / (1.0 + cast_speed))
	if float(ability.get("telegraphMs", 0.0)) > 0.0:
		windup = maxf(windup, float(state.minimum_enemy_telegraph_ms))
	actor.counters["abilities"] = int(actor.counters.get("abilities", 0)) + 1
	var action_id: String = "%s:ability:%s:%d" % [actor.id, ability_id, int(actor.counters["abilities"])]
	var target: CombatActorState = state.operator if state.operator.alive else null
	actor.cast = {
		"actionId": action_id, "skillId": "", "abilityId": ability_id,
		"startedAt": state.time_ms, "resolveAt": float(state.time_ms) + windup,
		"endAt": float(state.time_ms) + windup, "targetId": target.id if target != null else "",
		"interruptible": bool(ability.get("interruptible", false)),
		"telegraph": float(ability.get("telegraphMs", 0.0)) > 0.0,
		"dangerTag": str(ability.get("kind", "")), "channel": "main",
	}
	var every_ms: float = float(ability.get("everyMs", 0.0))
	var interval_multiplier: float = maxf(0.01, float(actor.flags.get("bossAbilityIntervalMultiplier", 1.0)))
	actor.ability_next[ability_id] = float(state.time_ms) + every_ms * interval_multiplier if every_ms > 0.0 else 999999999.0
	actor.next_attack_at = maxf(actor.next_attack_at, float(actor.cast["endAt"]))
	_emit(state, "CAST_START", actor.id, {
		"targetId": actor.cast["targetId"], "actionId": action_id,
		"text": "%s готовит: %s" % [actor.display_name, str(ability.get("desc", ability_id))],
		"data": {"abilityId": ability_id, "windupMs": windup, "interruptible": actor.cast["interruptible"]},
	})
	if bool(actor.cast["telegraph"]):
		_emit(state, "TELEGRAPH", actor.id, {"targetId": actor.cast["targetId"], "actionId": action_id, "text": "%s: %s" % [actor.display_name, str(ability.get("desc", ability_id))], "data": {"abilityId": ability_id, "dangerTag": ability.get("kind", ""), "windupMs": windup}})

func _advance_enemy_ability_casts(state: CombatState, rng: DeterministicRng) -> void:
	for actor: CombatActorState in state.enemies:
		if actor.cast == null or not actor.cast is Dictionary:
			continue
		var cast: Dictionary = actor.cast
		if _has_status(actor, "STUN"):
			cast["resolveAt"] = float(cast.get("resolveAt", 0.0)) + TICK_MS
			cast["endAt"] = float(cast.get("endAt", 0.0)) + TICK_MS
			continue
		if not bool(cast.get("resolved", false)) and state.time_ms >= float(cast.get("resolveAt", 0.0)):
			cast["resolved"] = true
			_resolve_enemy_ability(state, rng, actor, cast)
		if state.time_ms >= float(cast.get("endAt", 0.0)):
			actor.cast = null

func _resolve_enemy_ability(state: CombatState, rng: DeterministicRng, actor: CombatActorState, cast: Dictionary) -> void:
	var ability: Dictionary = {}
	for candidate: Dictionary in _enemy_ability_definitions(actor, state):
		if str(candidate.get("id", "")) == str(cast.get("abilityId", "")):
			ability = candidate
			break
	if ability.is_empty():
		_emit(state, "CAST_FIZZLE", actor.id, {"actionId": cast.get("actionId", ""), "reason": "unknown_ability", "text": "%s: неизвестное действие." % actor.display_name})
		return
	var ability_id: String = str(ability.get("id", ""))
	var ability_kind: String = str(ability.get("kind", ""))
	var action_id: String = str(cast.get("actionId", ""))
	var target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
	if target == null or not target.alive:
		target = state.operator if state.operator.alive else null
	match ability_kind:
		"heavyAttack", "shieldBypass", "deathBurst":
			if target == null:
				return
			var damage_type: String = str(ability.get("damageType", actor.attack_type))
			var raw: float = float(ability.get("damage", actor.attack_damage))
			var bypass: float = float(ability.get("bypassShieldRatio", ability.get("amount", 0.0) if ability_kind == "shieldBypass" else 0.0))
			if damage_type == "DIGITAL":
				bypass += float(actor.flags.get("digitalShieldBypassBonus", 0.0))
			var hit: Dictionary = _resolve_basic_hit(state, rng, actor, target, raw, damage_type, action_id, false, "", bypass)
			if bool(hit.get("ok", false)) and ability.has("status"):
				_add_simple_status(state, actor, target, str(ability["status"]), float(ability.get("statusDurationMs", 4000.0)))
		"applyStatus", "mark":
			var status_id: String = str(ability.get("status", ""))
			var targets: Array[CombatActorState] = []
			if status_id == "DRONE_JAM":
				for drone: CombatActorState in state.drones:
					if drone.alive: targets.append(drone)
			elif target != null:
				targets.append(target)
			for status_target: CombatActorState in targets:
				_add_simple_status(state, actor, status_target, status_id, float(ability.get("statusDurationMs", _status_catalog.get_definition(status_id).get("durationMs", 3000.0))))
			if not targets.is_empty():
				_emit(state, "TRIGGER", actor.id, {"targetId": targets[0].id, "actionId": action_id, "text": "%s: %s" % [actor.display_name, ability.get("desc", ability_id)], "data": {"abilityId": ability_id, "abilityKind": ability_kind}})
		"heat":
			if target != null:
				var amount: float = float(ability.get("amount", 0.0))
				_gain_basic_heat(state, target, amount)
				_emit(state, "HEAT", actor.id, {"targetId": target.id, "actionId": action_id, "text": "%s: нагрев +%s." % [target.display_name, _one_decimal(amount)], "data": {"abilityId": ability_id, "amount": amount}})
		"heal":
			var allies: Array[CombatActorState] = []
			for enemy: CombatActorState in state.enemies:
				if enemy.alive: allies.append(enemy)
			allies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool:
				var left_ratio: float = left.hp / maxf(1.0, float(_effective_sheet(state, left).get("maxHP", 1.0)))
				var right_ratio: float = right.hp / maxf(1.0, float(_effective_sheet(state, right).get("maxHP", 1.0)))
				return left_ratio < right_ratio if not is_equal_approx(left_ratio, right_ratio) else left.id < right.id)
			if not allies.is_empty():
				var ally: CombatActorState = allies[0]
				var before: float = ally.hp
				ally.hp = minf(float(_effective_sheet(state, ally).get("maxHP", 1.0)), ally.hp + float(ability.get("amount", 0.0)))
				_emit(state, "HEAL", actor.id, {"targetId": ally.id, "actionId": action_id, "text": "%s восстанавливает %s HP: %s." % [actor.display_name, _one_decimal(ally.hp - before), ally.display_name], "data": {"abilityId": ability_id, "amount": ally.hp - before}})
		"shieldRestore":
			var before_shield: float = actor.shield
			actor.shield = minf(float(_effective_sheet(state, actor).get("maxShield", 0.0)), actor.shield + float(ability.get("amount", 0.0)))
			_emit(state, "SHIELD_GAIN", actor.id, {"actionId": action_id, "text": "%s: щит +%s." % [actor.display_name, _one_decimal(actor.shield - before_shield)], "data": {"abilityId": ability_id, "amount": actor.shield - before_shield}})
		"escape":
			actor.alive = false
			actor.flags["escaped"] = true
			var escaped: Array = state.metrics.get("escaped", [])
			escaped.append({"enemyId": actor.id, "templateId": actor.template_id, "cargoItems": 1, "timeMs": state.time_ms})
			state.metrics["escaped"] = escaped
			_emit(state, "ESCAPE", actor.id, {"actionId": action_id, "text": "%s скрылся, прихватив груз." % actor.display_name, "data": {"abilityId": ability_id, "cargoItems": 1}})
		"wantedBoost":
			if not bool(actor.flags.get("wantedBoostApplied", false)):
				actor.flags["wantedBoostApplied"] = true
				state.wanted_delta += int(ability.get("amount", 0))
				actor.ability_next[ability_id] = 999999999.0
				_emit(state, "WANTED", actor.id, {"actionId": action_id, "text": "%s сообщил о вас властям: розыск +%d." % [actor.display_name, int(ability.get("amount", 0))], "data": {"abilityId": ability_id, "amount": int(ability.get("amount", 0))}})
		"protectAlly":
			var weakest: CombatActorState = null
			for ally: CombatActorState in state.enemies:
				if not ally.alive:
					continue
				if weakest == null or ally.hp / maxf(1.0, float(_effective_sheet(state, ally).get("maxHP", 1.0))) < weakest.hp / maxf(1.0, float(_effective_sheet(state, weakest).get("maxHP", 1.0))):
					weakest = ally
			if weakest != null:
				weakest.flags["protectedBy"] = actor.id
				_emit(state, "GUARD", actor.id, {"targetId": weakest.id, "actionId": action_id, "text": "%s прикрывает %s: получаемый урон −15%%." % [actor.display_name, weakest.display_name], "data": {"abilityId": ability_id, "reduction": 0.15}})
	_emit(state, "TRIGGER", actor.id, {"targetId": target.id if target != null else "", "actionId": action_id, "text": "%s: %s." % [actor.display_name, str(ability.get("desc", ability_id))], "data": {"abilityId": ability_id, "abilityKind": ability_kind}})

func _resolve_main_skill(state: CombatState, rng: DeterministicRng, actor: CombatActorState, cast: Dictionary) -> void:
	var skill_id: String = str(cast.get("skillId", ""))
	var skill: Dictionary = _equipped_skill(state, skill_id)
	if skill.is_empty():
		return
	var target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
	state.metrics["skillUses"][skill_id] = int(state.metrics["skillUses"].get(skill_id, 0)) + 1
	var action_id: String = str(cast.get("actionId", ""))
	_emit(state, "SKILL_USE", actor.id, {
		"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": action_id,
		"originActionId": action_id, "text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))],
		"data": {"channel": "main"},
	})
	var effective: Dictionary = _effective_sheet(state, actor, target)
	match str(skill.get("special", "")):
		"OVERCLOCK":
			_add_simple_status(state, actor, actor, "OVERCLOCK", 8000.0)
			return
		"SCAN":
			if target != null and target.alive:
				_add_simple_status(state, actor, target, "SCAN_MARK", 6000.0 + float(effective.get("scanMarkBonusMs", 0.0)))
			return
		"DETONATE":
			if target != null:
				_resolve_virus_detonation(state, rng, actor, target, skill, action_id)
			return
	var weapon: Dictionary = state.build.get("mainWeapon", {})
	var sidearm: Dictionary = state.build.get("sidearm", {})
	var basis: String = str(skill.get("basis", ""))
	var base_damage: float = float(weapon.get("damage", 0.0))
	var damage_type: String = str(weapon.get("type", "KINETIC"))
	var is_main: bool = basis in ["MAIN_K", "MAIN_ANY"]
	match basis:
		"MAIN_K":
			damage_type = "KINETIC"
		"TECH_E":
			base_damage = float(effective.get("techPower", 0.0))
			damage_type = "ENERGY"
		"TECH_D":
			base_damage = float(effective.get("techPower", 0.0))
			damage_type = "DIGITAL"
		"OFFHAND":
			base_damage = float(sidearm.get("damage", 0.0))
			damage_type = str(sidearm.get("type", "KINETIC"))
	if basis == "NONE":
		return
	if skill_id == "SK_KINETIC" or str(skill.get("targetMode", "")) == "allEnemies":
		var targets: Array[CombatActorState] = []
		for enemy: CombatActorState in state.enemies:
			if enemy.alive:
				targets.append(enemy)
		targets.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
		var limit: int = int(skill.get("maxTargets", targets.size()))
		for current_target: CombatActorState in targets.slice(0, limit):
			var raw_base: float = _skill_raw_damage(skill, base_damage, effective, current_target)
			var hit: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, raw_base, damage_type, action_id, is_main, skill_id)
			if not bool(hit.get("ok", false)):
				return
		return
	if target == null or not target.alive:
		target = _pick_auto_target(state, actor)
	if target == null:
		return
	if skill_id == "SK_ARC":
		var primary_raw: float = _skill_raw_damage(skill, base_damage, effective, target)
		var primary_hit: Dictionary = _resolve_basic_hit(state, rng, actor, target, primary_raw, damage_type, action_id, is_main, skill_id)
		if not bool(primary_hit.get("ok", false)):
			return
		var arc_others: Array[CombatActorState] = []
		for enemy: CombatActorState in state.enemies:
			if enemy.alive and enemy.id != target.id:
				arc_others.append(enemy)
		arc_others.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
		for secondary: CombatActorState in arc_others.slice(0, 2):
			var splash_raw: float = _skill_raw_damage(skill, base_damage, effective, secondary) * float(skill.get("splash", {}).get("coefficient", 0.5))
			var splash_hit: Dictionary = _resolve_basic_hit(state, rng, actor, secondary, splash_raw, damage_type, action_id, is_main, skill_id)
			if bool(splash_hit.get("hit", false)):
				_add_simple_status(state, actor, secondary, "SHOCK", 1000.0)
		return
	var hits: int = maxi(1, int(skill.get("hits", 1)))
	var coefficient: float = float(skill.get("hitCoefficient", skill.get("coefficient", 1.0)))
	for hit_index: int in range(hits):
		var current_target: CombatActorState = target if target.alive else _pick_auto_target(state, actor)
		if current_target == null:
			break
		var raw_base: float = _skill_raw_damage(skill, base_damage, effective, current_target, coefficient)
		if skill_id == "SK_EXEC" and current_target.hp / maxf(1.0, float(current_target.base_sheet.get("maxHP", 1.0))) < 0.3:
			raw_base *= 1.4 * float(_effective_sheet(state, actor, current_target).get("moreExecute", 1.0))
		if skill_id == "SK_CHAIN" and actor.heat >= 80.0:
			raw_base *= 1.25
		var hit: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, raw_base, damage_type, action_id, is_main, skill_id)
		if not bool(hit.get("ok", false)):
			return
		if not bool(hit.get("hit", false)):
			continue
		match skill_id:
			"SK_BLADE":
				if hit_index == hits - 1:
					_add_dot_status(state, actor, current_target, "BLEED", raw_base, action_id)
			"SK_NEURO": _add_dot_status(state, actor, current_target, "VIRUS", raw_base, action_id)
			"SK_SEED": _add_dot_status(state, actor, current_target, "VIRUS", raw_base, action_id, 2)
			"SK_BREAK": _add_simple_status(state, actor, current_target, "ARMOR_BREAK", 5000.0)
			"SK_LEECH":
				if _has_status(current_target, "VIRUS"):
					var before_energy: float = actor.energy
					actor.energy = minf(float(effective.get("maxEnergy", 0.0)), actor.energy + 8.0)
					_emit(state, "ENERGY", actor.id, {"actionId": action_id, "text": "%s: +%s энергии (Паразит)." % [actor.display_name, _one_decimal(actor.energy - before_energy)], "data": {"amount": actor.energy - before_energy}})

func _skill_raw_damage(skill: Dictionary, base_damage: float, effective: Dictionary, target: CombatActorState, coefficient_override: float = -1.0) -> float:
	var coefficient: float = float(skill.get("coefficient", 1.0)) if coefficient_override < 0.0 else coefficient_override
	var raw: float = base_damage * coefficient
	var tags: Array = skill.get("tags", [])
	if tags.has("E"):
		raw *= float(effective.get("moreSkillEnergy", 1.0))
	if tags.has("D"):
		raw *= float(effective.get("moreSkillDigital", 1.0))
	return raw

func _add_dot_status(state: CombatState, source: CombatActorState, target: CombatActorState, status_id: String, raw_snapshot: float, action_id: String, stacks: int = 1) -> void:
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return
	var definition: Dictionary = _status_catalog.get_definition(status_id)
	var sheet: Dictionary = _effective_sheet(state, source, target)
	var duration: float = float(definition.get("durationMs", 0.0)) * (1.0 + (float(sheet.get("dotDuration", 0.0)) + (float(sheet.get("virusDuration", 0.0)) if status_id == "VIRUS" else 0.0)) / 100.0)
	var snapshot: float = raw_snapshot * (1.0 + (float(sheet.get("statusDamage", 0.0)) + (float(sheet.get("bleedDamage", 0.0)) if status_id == "BLEED" else 0.0)) / 100.0)
	if str(definition.get("snapshotFrom", "")) == "techPower":
		snapshot = float(sheet.get("techPower", 0.0)) * (1.0 + float(sheet.get("statusDamage", 0.0)) / 100.0) * (1.0 + float(sheet.get("virusDamage", 0.0)) / 100.0)
	var entries: Array = target.statuses.get(status_id, [])
	var max_stacks: int = int(definition.get("maxStacks", 1)) + floori(float(sheet.get("bleedStackCap", 0.0)) if status_id == "BLEED" else float(sheet.get("virusStackCap", 0.0)) if status_id == "VIRUS" else 0.0)
	if bool(definition.get("independentStacks", false)):
		for _index: int in range(stacks):
			if entries.size() >= max_stacks: entries.pop_front()
			entries.append({"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration, "nextTickAt": float(state.time_ms) + float(definition.get("tickMs", duration)), "snapshot": snapshot, "stacks": 1})
	else:
		if entries.is_empty():
			entries.append({"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration, "nextTickAt": float(state.time_ms) + float(definition.get("tickMs", duration)), "snapshot": snapshot, "stacks": mini(max_stacks, stacks)})
		else:
			entries[0]["stacks"] = mini(max_stacks, int(entries[0].get("stacks", 1)) + stacks)
			entries[0]["expiresAt"] = float(state.time_ms) + duration
			entries[0]["sourceActorId"] = source.id
	target.statuses[status_id] = entries
	_emit(state, "STATUS_APPLY", source.id, {"targetId": target.id, "actionId": action_id, "statusId": status_id, "text": "%s: %s." % [target.display_name, str(definition.get("name", status_id))], "data": {"stacks": _status_stack_count(entries), "snapshot": snapshot, "durationMs": duration}})

func _resolve_virus_detonation(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, skill: Dictionary, action_id: String) -> void:
	var entries: Array = target.statuses.get("VIRUS", [])
	if entries.is_empty():
		return
	var definition: Dictionary = _status_catalog.get_definition("VIRUS")
	var tick_ms: float = float(definition.get("tickMs", 1000.0))
	var tick_fraction: float = float(definition.get("tickFraction", 0.0))
	var consume_count: int = mini(3, entries.size())
	var potential: float = 0.0
	for index: int in range(consume_count):
		var entry: Dictionary = entries[index]
		var remaining_ticks: int = maxi(0, ceili((float(entry.get("expiresAt", 0.0)) - float(state.time_ms)) / tick_ms))
		potential += float(entry.get("snapshot", 0.0)) * tick_fraction * remaining_ticks * int(entry.get("stacks", 1))
	target.statuses["VIRUS"] = entries.slice(consume_count)
	if target.statuses["VIRUS"].is_empty(): target.statuses.erase("VIRUS")
	var sheet: Dictionary = _effective_sheet(state, actor, target)
	var raw: float = potential * float(sheet.get("detonateCoefficient", 0.6)) * float(sheet.get("moreSkillDigital", 1.0))
	_resolve_basic_hit(state, rng, actor, target, raw, "DIGITAL", action_id, false, str(skill.get("id", "SK_DETONATE")))

func _record_rule_failure(state: CombatState, rule_id: String, reason: String) -> void:
	var failures: Array = state.metrics.get("ruleFailures", [])
	for entry: Dictionary in failures:
		if str(entry.get("ruleId", "")) == rule_id and str(entry.get("reason", "")) == reason:
			entry["count"] = int(entry.get("count", 0)) + 1
			return
	failures.append({"ruleId": rule_id, "reason": reason, "count": 1, "firstAt": state.time_ms})
	state.metrics["ruleFailures"] = failures
	_emit(state, "RULE_FAIL", "operator", {"reason": reason, "text": "Правило %s: %s." % [rule_id, reason], "data": {"ruleId": rule_id}})

func apply_status(state: CombatState, source_id: String, target_id: String, status_id: String, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return _failure("Для наложения статуса требуется состояние боя.")
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return _failure("Каталог статусов недоступен: %s" % _status_catalog_error)
	if not STEP_STATUS_IDS.has(status_id):
		return _failure("Статус %s загружен из каталога, но его действие ещё не поддерживается этим срезом симулятора." % status_id)
	var source: CombatActorState = _actor_by_id(state, source_id)
	var target: CombatActorState = _actor_by_id(state, target_id)
	if source == null or target == null or not target.alive:
		return _failure("Источник или активная цель статуса не найдены.")
	var definition: Dictionary = _status_catalog.get_definition(status_id)
	if definition.is_empty():
		return _failure("Неизвестный статус %s." % status_id)
	var next: CombatState = state.clone()
	var next_source: CombatActorState = _actor_by_id(next, source_id)
	var next_target: CombatActorState = _actor_by_id(next, target_id)
	if next_source == null or next_target == null:
		return _failure("Источник или цель статуса отсутствуют в копии состояния.")
	var stacks: int = maxi(1, int(options.get("stacks", 1)))
	var source_sheet: Dictionary = _effective_sheet(next, next_source)
	var duration: float = float(options.get("durationMs", definition["durationMs"]))
	if definition.has("tickMs"):
		duration *= 1.0 + (float(source_sheet.get("dotDuration", 0.0)) + (float(source_sheet.get("virusDuration", 0.0)) if status_id == "VIRUS" else 0.0)) / 100.0
	var snapshot: float = 0.0
	match str(definition["snapshotFrom"]):
		"rawDamage":
			snapshot = float(options.get("snapshot", 0.0)) * (1.0 + (float(source_sheet.get("statusDamage", 0.0)) + (float(source_sheet.get("bleedDamage", 0.0)) if status_id == "BLEED" else 0.0)) / 100.0)
		"techPower":
			snapshot = float(source_sheet.get("techPower", 0.0)) * (1.0 + float(source_sheet.get("statusDamage", 0.0)) / 100.0) * (1.0 + float(source_sheet.get("virusDamage", 0.0)) / 100.0)
	var max_stacks: int = int(definition["maxStacks"])
	if status_id == "STUN":
		var stun_ready_at: float = float(next_target.icds.get("STUN", 0.0))
		if stun_ready_at > next.time_ms:
			return {"ok": true, "state": state, "error": ""}
		next_target.icds["STUN"] = next.time_ms + 3000
		if next_target.is_boss:
			duration *= 0.5
	if status_id == "BLEED":
		max_stacks += floori(float(source_sheet.get("bleedStackCap", 0.0)))
	elif status_id == "VIRUS":
		max_stacks += floori(float(source_sheet.get("virusStackCap", 0.0)))
	var entries: Array = next_target.statuses.get(status_id, [])
	if bool(definition["independentStacks"]):
		for _index: int in range(stacks):
			if entries.size() >= max_stacks:
				entries.pop_front()
			entries.append({
				"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id,
				"expiresAt": float(next.time_ms) + duration,
				"nextTickAt": float(next.time_ms) + float(definition.get("tickMs", duration)),
				"snapshot": snapshot, "stacks": 1,
			})
	else:
		var existing: Dictionary = entries[0] if not entries.is_empty() else {}
		if not existing.is_empty():
			existing["stacks"] = clampi(int(existing.get("stacks", 1)) + stacks, 1, max_stacks)
			existing["expiresAt"] = float(next.time_ms) + duration
			existing["sourceActorId"] = source.id
			if definition.has("tickMs"):
				existing["snapshot"] = snapshot
		else:
			entries.append({
				"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id,
				"expiresAt": float(next.time_ms) + duration,
				"nextTickAt": float(next.time_ms) + float(definition.get("tickMs", duration)),
				"snapshot": snapshot, "stacks": clampi(stacks, 1, max_stacks),
			})
	next_target.statuses[status_id] = entries
	_emit(next, "STATUS_APPLY", source.id, {
		"targetId": target.id, "statusId": status_id,
		"text": "%s: %s%s." % [target.display_name, str(definition["name"]), " ×%d" % entries.size() if bool(definition["independentStacks"]) else ""],
		"data": {"stacks": _status_stack_count(entries), "snapshot": snapshot, "durationMs": duration},
	})
	return {"ok": true, "state": next, "error": ""}

func _tick_dot_statuses(state: CombatState) -> void:
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return
	for target: CombatActorState in state.all_actors():
		if not target.alive:
			continue
		for status_id: String in ["BLEED", "BURN", "VIRUS"]:
			var entries: Array = target.statuses.get(status_id, [])
			var definition: Dictionary = _status_catalog.get_definition(status_id)
			if entries.is_empty() or definition.is_empty():
				continue
			for entry: Dictionary in entries:
				if float(entry.get("nextTickAt", 0.0)) > float(state.time_ms):
					continue
				entry["nextTickAt"] = float(entry.get("nextTickAt", 0.0)) + float(definition["tickMs"])
				var raw: float = float(entry.get("snapshot", 0.0)) * float(definition.get("tickFraction", 0.0)) * float(entry.get("stacks", 1))
				if raw <= 0.0:
					continue
				_apply_dot_damage(state, target, str(entry.get("sourceActorId", "")), status_id, raw, str(definition["damageType"]), str(definition["name"]))

func _apply_dot_damage(state: CombatState, target: CombatActorState, source_id: String, status_id: String, raw: float, damage_type: String, status_name: String) -> void:
	var source: CombatActorState = _actor_by_id(state, source_id)
	var defender: Dictionary = _effective_sheet(state, target, source)
	var mitigation: Dictionary = _damage.mitigate_packet(raw, damage_type, {"armor": defender.get("armor", 0.0), "energyRes": defender.get("energyRes", 0.0), "digitalRes": defender.get("digitalRes", 0.0)}, DamageMath.ZERO_PENETRATION)
	var incoming: float = float(mitigation["afterDefense"]) * float(defender.get("incomingAll", 1.0)) * float(defender.get("incomingKinetic" if damage_type == "KINETIC" else "incomingEnergy" if damage_type == "ENERGY" else "incomingDigital", 1.0))
	if target.side == "enemy" and not str(target.flags.get("protectedBy", "")).is_empty():
		var protector: CombatActorState = _actor_by_id(state, str(target.flags["protectedBy"]))
		if protector != null and protector.alive and protector.template_id == "E12":
			incoming *= 0.85
	var partition: Dictionary = _damage.partition_damage(incoming, {"hp": target.hp, "shield": target.shield, "temp": target.temp_shields}, 0.0, float(defender.get("incomingShield", 1.0)))
	_apply_partition(target, partition)
	target.flags["lastDamagedAt"] = float(state.time_ms)
	state.metrics["statusTicks"] = int(state.metrics.get("statusTicks", 0)) + 1
	var dealt: float = float(partition["shieldConsumed"]) + float(partition["hpLost"])
	target.damage_taken += dealt
	if source != null:
		source.damage_dealt += dealt
	if source != null and source.side == "player":
		state.metrics["damageDealt"] = float(state.metrics.get("damageDealt", 0.0)) + dealt
		var by_type: Dictionary = state.metrics["damageByType"]
		by_type[damage_type] = float(by_type.get(damage_type, 0.0)) + incoming
		var by_source: Dictionary = state.metrics["damageBySource"]
		by_source[source_id] = float(by_source.get(source_id, 0.0)) + dealt
		state.metrics["shieldAbsorbed"] = float(state.metrics.get("shieldAbsorbed", 0.0)) + float(partition["shieldConsumed"])
	else:
		state.metrics["damageTaken"] = float(state.metrics.get("damageTaken", 0.0)) + dealt
		var by_source: Dictionary = state.metrics["takenBySource"]
		by_source[source_id] = float(by_source.get(source_id, 0.0)) + dealt
		if target.kind == "operator":
			state.metrics["hpLost"] = float(state.metrics.get("hpLost", 0.0)) + float(partition["hpLost"])
	_emit(state, "DOT_TICK", source_id, {
		"targetId": target.id, "actionId": "dot:%s:%s:%d" % [status_id, target.id, state.time_ms],
		"statusId": status_id, "damageType": damage_type,
		"amountBeforeDefense": raw, "amountAfterDefense": incoming,
		"shieldConsumed": partition["shieldConsumed"], "hpLost": partition["hpLost"],
		"text": "%s → %s: %s %s." % [status_name, target.display_name, _one_decimal(incoming), damage_type],
	})

func _expire_dot_statuses(state: CombatState) -> void:
	if not _status_catalog_loaded:
		return
	for actor: CombatActorState in state.all_actors():
		for status_id: String in actor.statuses.keys():
			var entries: Array = actor.statuses.get(status_id, [])
			if entries.is_empty():
				continue
			var kept: Array = []
			for entry: Dictionary in entries:
				if float(entry.get("expiresAt", 0.0)) > float(state.time_ms):
					kept.append(entry)
			if kept.size() != entries.size():
				_emit(state, "STATUS_EXPIRE", actor.id, {
					"statusId": status_id,
					"actionId": "%s:status-expire:%s:%d" % [actor.id, status_id, state.time_ms],
					"text": "%s: %s истёк." % [actor.display_name, str(_status_catalog.get_definition(status_id).get("name", status_id))],
				})
			if kept.is_empty():
				actor.statuses.erase(status_id)
			else:
				actor.statuses[status_id] = kept

func _actor_by_id(state: CombatState, actor_id: String) -> CombatActorState:
	for actor: CombatActorState in state.all_actors():
		if actor.id == actor_id:
			return actor
	return null

func _status_stack_count(entries: Array) -> int:
	var count: int = 0
	for entry: Dictionary in entries:
		count += int(entry.get("stacks", 0))
	return count

func _status_stacks(actor: CombatActorState, status_id: String) -> int:
	return _status_stack_count(actor.statuses.get(status_id, []))

func _has_status(actor: CombatActorState, status_id: String) -> bool:
	return not actor.statuses.get(status_id, []).is_empty()

func _effective_sheet(state: CombatState, actor: CombatActorState, target: CombatActorState = null) -> Dictionary:
	var sheet: Dictionary = actor.base_sheet.duplicate(true)
	var has_conditions: bool = false
	for modifier: Dictionary in actor.base_mods:
		if modifier.has("condition"):
			has_conditions = true
			break
	if has_conditions:
		var self_view: Dictionary = {
			"hp": actor.hp, "maxHP": actor.base_sheet.get("maxHP", 0.0),
			"shield": actor.shield, "maxShield": actor.base_sheet.get("maxShield", 0.0),
			"energy": actor.energy, "heat": actor.heat,
			"statuses": _status_counts(actor), "isBoss": actor.is_boss,
			"isMechanical": actor.is_mechanical, "isDrone": actor.kind == "drone",
		}
		var context: Dictionary = {
			"self": self_view,
			"enemiesAlive": _living_count(state.enemies) if actor.side == "player" else _living_player_count(state),
			"dronesAlive": _living_count(state.drones), "timeMs": state.time_ms,
			"heatLockout": actor.heat_lockout, "flags": actor.flags,
			"otherDroneDead": state.drones.any(func(drone: CombatActorState) -> bool: return not drone.alive and drone.id != actor.id),
			"bothDronesSameTarget": state.drones.size() >= 2 and state.drones.all(func(drone: CombatActorState) -> bool: return drone.alive) and not state.drones[0].last_target_id.is_empty() and state.drones[0].last_target_id == state.drones[1].last_target_id,
		}
		if target != null:
			context["target"] = {
				"hp": target.hp, "maxHP": target.base_sheet.get("maxHP", 0.0),
				"shield": target.shield, "maxShield": target.base_sheet.get("maxShield", 0.0),
				"energy": target.energy, "heat": target.heat,
				"statuses": _status_counts(target), "isBoss": target.is_boss,
				"isMechanical": target.is_mechanical, "isDrone": target.kind == "drone",
			}
		var uniques: Array[String] = []
		for equipped: Variant in state.build.get("equipment", {}).values():
			if equipped is Dictionary:
				for unique_id: Variant in equipped.get("uniqueEffectIds", []):
					if not uniques.has(str(unique_id)):
						uniques.append(str(unique_id))
		context["uniques"] = uniques
		var resolved: Dictionary = _stats.resolve_stats(_stats.bundle(actor.base_mods), context)
		if not resolved.has("_error") and not resolved.is_empty():
			sheet = _stats.sheet_of(resolved)
	var armor_break: int = _status_stacks(actor, "ARMOR_BREAK")
	if armor_break > 0:
		sheet["armor"] = float(sheet.get("armor", 0.0)) - 10.0 * armor_break
	if _has_status(actor, "GUARD"):
		sheet["incomingKinetic"] = float(sheet.get("incomingKinetic", 1.0)) * 0.8
	if _has_status(actor, "ACC_BUFF"):
		sheet["accuracy"] = float(sheet.get("accuracy", 100.0)) + 8.0
	if _has_status(actor, "EVASION_BUFF"):
		sheet["evasion"] = float(sheet.get("evasion", 0.0)) * 1.2
	if _has_status(actor, "SHIELD_REGEN_BUFF"):
		sheet["shieldRegen"] = float(sheet.get("shieldRegen", 0.0)) + 10.0
	var overclock_stacks: int = _status_stacks(actor, "OVERCLOCK")
	if overclock_stacks > 0:
		sheet["attackSpeed"] = float(sheet.get("attackSpeed", 0.0)) + 20.0 * overclock_stacks
	return sheet

func _status_counts(actor: CombatActorState) -> Dictionary:
	var counts: Dictionary = {}
	for status_id: Variant in actor.statuses.keys():
		counts[str(status_id)] = _status_stacks(actor, str(status_id))
	return counts

func _living_count(actors: Array[CombatActorState]) -> int:
	var count: int = 0
	for actor: CombatActorState in actors:
		if actor.alive:
			count += 1
	return count

func _living_player_count(state: CombatState) -> int:
	return int(state.operator.alive) + _living_count(state.drones) + _living_count(state.allies)

func _apply_basic_continuous(state: CombatState) -> void:
	for actor: CombatActorState in state.all_actors():
		actor.temp_shields = actor.temp_shields.filter(func(pool: Dictionary) -> bool:
			return float(pool.get("expiresAt", 0.0)) > float(state.time_ms) and float(pool.get("amount", 0.0)) > 0.0
		)
	var operator: CombatActorState = state.operator
	if operator.alive:
		var sheet: Dictionary = _effective_sheet(state, operator)
		operator.energy = clampf(operator.energy + float(sheet.get("energyRegen", 0.0)) * 0.1, 0.0, float(sheet.get("maxEnergy", 0.0)))
		var ambient: float = state.ambient_heat_per_sec
		for enemy: CombatActorState in state.enemies:
			if enemy.alive:
				ambient += float(_factory._enemy_catalog.get_template(enemy.template_id).get("ambientHeatPerSec", 0.0))
		var cooling: float = maxf(0.0, float(sheet.get("heatCooling", 0.0)) - state.cooling_penalty)
		operator.heat = clampf(operator.heat + (ambient - cooling) * 0.1, 0.0, float(sheet.get("maxHeat", 0.0)))
		if operator.heat <= 25.0:
			operator.flags["coldStreak"] = float(operator.flags.get("coldStreak", 0.0)) + 100.0
		else:
			operator.flags["coldStreak"] = 0.0
		var since_hit: float = float(state.time_ms) - float(operator.flags.get("lastDamagedAt", -100000.0))
		if since_hit >= SHIELD_REGEN_DELAY_MS and operator.shield < float(sheet.get("maxShield", 0.0)):
			var regen_mult: float = 0.7 if _has_status(operator, "SHIELD_LEAK") else 1.0
			operator.shield = clampf(operator.shield + float(sheet.get("shieldRegen", 0.0)) * regen_mult * 0.1, 0.0, float(sheet.get("maxShield", 0.0)))
		if operator.shield <= 0.0:
			state.metrics["timeWithoutShieldMs"] = int(state.metrics.get("timeWithoutShieldMs", 0)) + TICK_MS
		state.metrics["lowestHpFraction"] = minf(float(state.metrics.get("lowestHpFraction", 1.0)), operator.hp / maxf(1.0, float(sheet.get("maxHP", 1.0))))
	for actor: CombatActorState in state.drones + state.enemies + state.allies:
		if not actor.alive:
			continue
		var sheet: Dictionary = _effective_sheet(state, actor)
		var since_hit: float = float(state.time_ms) - float(actor.flags.get("lastDamagedAt", -100000.0))
		if since_hit >= SHIELD_REGEN_DELAY_MS and actor.shield < float(sheet.get("maxShield", 0.0)):
			var regen_mult: float = 0.7 if _has_status(actor, "SHIELD_LEAK") else 1.0
			actor.shield = clampf(actor.shield + float(sheet.get("shieldRegen", 0.0)) * regen_mult * 0.1, 0.0, float(sheet.get("maxShield", 0.0)))

func _pick_auto_target(state: CombatState, actor: CombatActorState) -> CombatActorState:
	if actor.side == "enemy":
		if state.operator.alive:
			return state.operator
		for ally: CombatActorState in [state.operator] + state.drones + state.allies:
			if ally.alive:
				return ally
		return null
	var enemies: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive:
			enemies.append(enemy)
	enemies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	if actor.kind == "drone" and actor.drone_role == "mark":
		for enemy: CombatActorState in enemies:
			if _has_status(enemy, "DRONE_MARK"):
				return enemy
	return enemies[0] if not enemies.is_empty() else null

func _resolve_basic_attack(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState) -> Dictionary:
	if actor.kind == "operator":
		_record_enemy_judge_program(state, "")
	var weapon: Dictionary = state.build.get("mainWeapon", {}) if actor.kind == "operator" else {}
	if actor.kind == "operator":
		var energy_cost: float = float(weapon.get("energyPerAttack", 0.0))
		if energy_cost > 0.0 and actor.energy < energy_cost:
			state.metrics["energyStarvedMs"] = int(state.metrics.get("energyStarvedMs", 0)) + TICK_MS
			return {"ok": true, "error": ""}
		if energy_cost > 0.0:
			actor.energy = maxf(0.0, actor.energy - energy_cost)
			state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + energy_cost
		var heat_gain: float = float(weapon.get("heatPerAttack", 0.0))
		if _has_status(actor, "OVERCLOCK"):
			heat_gain += 5.0
		_gain_basic_heat(state, actor, heat_gain)
	actor.counters["attacks"] = int(actor.counters.get("attacks", 0)) + 1
	var action_id: String = "%s:atk:%d" % [actor.id, int(actor.counters["attacks"])]
	actor.last_main_attack_at = state.time_ms
	_emit(state, "ATTACK", actor.id, {"targetId": target.id, "actionId": action_id, "text": "%s атакует %s." % [actor.display_name, target.display_name]})
	actor.last_target_id = target.id
	var packets: Array[Dictionary] = _attack_packets(actor, weapon)
	var landed: bool = false
	for packet: Dictionary in packets:
		var current_target: CombatActorState = _pick_auto_target(state, actor)
		if current_target == null:
			break
		var hit_result: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, float(packet["amount"]), str(packet["type"]), action_id, actor.kind == "operator")
		if not bool(hit_result.get("ok", false)):
			return hit_result
		landed = landed or bool(hit_result.get("hit", false))
	if actor.kind == "operator":
		actor.flags["firstAttack"] = 0.0
	if landed:
		_dispatch_attack_counter_triggers(state, rng, actor, target, action_id)
	return {"ok": true, "error": ""}

func _dispatch_attack_counter_triggers(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, action_id: String) -> void:
	if actor.kind != "operator" and actor.kind != "drone":
		return
	var attack_action: bool = action_id.begins_with("%s:atk:" % actor.id)
	if actor.kind == "drone" and not attack_action:
		return
	var source_item_id: String = ""
	if actor.kind == "operator":
		var main_item: Variant = state.build.get("equipment", {}).get("MAIN")
		if main_item is ItemInstance: source_item_id = main_item.item_id
	else:
		source_item_id = actor.drone_item_id
	for trigger_value: Dictionary in state.build.get("triggerEffects", []):
		var effect: Dictionary = trigger_value.get("effect", {})
		var effect_id: String = str(effect.get("id", ""))
		if str(effect.get("event", "")) != "ON_ATTACK_COUNTER" or str(trigger_value.get("sourceKind", "")) != "item" or str(trigger_value.get("sourceId", "")) != source_item_id:
			continue
		var every: int = int(effect.get("counterEvery", 0))
		var attack_count: int = int(actor.counters.get("attacks", 0))
		if every <= 0 or attack_count <= 0 or attack_count % every != 0:
			continue
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, effect_id]
		_emit(state, "TRIGGER", actor.id, {"targetId": target.id if target.alive else null, "actionId": trigger_action_id, "text": "%s: сработал триггер %s." % [actor.display_name, effect_id], "data": {"attackCounter": attack_count, "counterEvery": every}})
		match effect_id:
			"ARC_E2_splash":
				var secondary: CombatActorState = _counter_secondary_target(state, target.id)
				if secondary != null:
					var main_weapon: Dictionary = state.build.get("mainWeapon", {})
					var raw: float = float(main_weapon.get("damage", 0.0)) * float(effect.get("action", {}).get("coefficient", 0.25))
					_resolve_basic_hit(state, rng, actor, secondary, raw, str(effect.get("action", {}).get("damageType", "ENERGY")), trigger_action_id, false)
			"FOCUS_D1_virus":
				if target.alive:
					_add_dot_status(state, actor, target, "VIRUS", 0.0, trigger_action_id, int(effect.get("action", {}).get("stacks", 1)))
			"DR_ARC_shock":
				if target.alive:
					var definition: Dictionary = _status_catalog.get_definition("SHOCK")
					_add_simple_status(state, actor, target, "SHOCK", float(definition.get("durationMs", 1000.0)))

func _counter_secondary_target(state: CombatState, excluded_id: String) -> CombatActorState:
	var targets: Array[CombatActorState] = []
	for enemy: CombatActorState in state.enemies:
		if enemy.alive and enemy.id != excluded_id:
			targets.append(enemy)
	targets.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	return targets[0] if not targets.is_empty() else null

func _attack_packets(actor: CombatActorState, weapon: Dictionary) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	if actor.kind == "operator" and weapon.get("packets", []) is Array and not weapon.get("packets", []).is_empty():
		for packet: Dictionary in weapon["packets"]:
			packets.append({"type": packet["type"], "amount": packet["amount"]})
	elif actor.kind == "operator":
		var count: int = int(weapon.get("pelletCount", 1))
		for _index: int in range(count):
			packets.append({"type": actor.attack_type, "amount": actor.attack_damage})
	elif actor.kind == "drone" and actor.drone_role == "swarm":
		for _index: int in range(maxi(1, actor.drone_pellets)):
			packets.append({"type": actor.attack_type, "amount": actor.attack_damage})
	else:
		packets.append({"type": actor.attack_type, "amount": actor.attack_damage})
	return packets

func _resolve_basic_hit(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, raw_base: float, damage_type: String, action_id: String, is_main: bool, skill_id: String = "", bypass_shield_ratio: float = 0.0) -> Dictionary:
	var attacker: Dictionary = _effective_sheet(state, actor, target)
	var defender: Dictionary = _effective_sheet(state, target, actor)
	var accuracy: float = float(attacker.get("accuracy", 100.0))
	if actor.kind == "drone" and _has_status(target, "DRONE_MARK"):
		accuracy += 15.0
	var chance_to_hit: float = _damage.hit_probability(accuracy, float(defender.get("evasion", 0.0)))
	if not rng.chance(chance_to_hit):
		state.metrics["misses"] = int(state.metrics.get("misses", 0)) + 1
		if target.kind == "operator":
			state.metrics["dodgesTaken"] = int(state.metrics.get("dodgesTaken", 0)) + 1
		var miss_event: Dictionary = {
			"targetId": target.id, "actionId": action_id, "damageType": damage_type,
			"originActionId": action_id, "text": "%s: промах по %s." % [actor.display_name, target.display_name], "roll": chance_to_hit,
		}
		if not skill_id.is_empty():
			miss_event["skillId"] = skill_id
		_emit(state, "MISS", actor.id, miss_event)
		return {"ok": true, "hit": false, "error": ""}
	var crit: bool = rng.chance(_damage.crit_probability(float(attacker.get("critChance", 0.0))))
	var raw: float = raw_base * _outgoing_multiplier(attacker, damage_type, is_main)
	var berserk_stacks: int = _status_stacks(actor, "BERSERK")
	if berserk_stacks > 0:
		raw *= 1.0 + 0.15 * berserk_stacks
	if _has_status(actor, "CONTROLLED"):
		raw *= 0.4
	if actor.kind == "drone" and _has_status(actor, "DRONE_JAM"):
		raw *= 0.5
	if _has_status(target, "SCAN_MARK"):
		raw *= 1.12
	if crit:
		raw *= float(attacker.get("critMultiplier", 1.5)) * float(attacker.get("moreCritDamage", 1.0))
		state.metrics["crits"] = int(state.metrics.get("crits", 0)) + 1
	var penetration: Dictionary = {
		"armorPen": float(attacker.get("armorPen", 0.0)) + (state.elite_pen if actor.side == "enemy" else 0.0) + (10.0 if actor.elite_mod == "EL_PEN" else 0.0),
		"armorPenPercent": float(attacker.get("armorPenPercent", 0.0)),
		"energyPen": float(attacker.get("energyPen", 0.0)), "energyPenPercent": float(attacker.get("energyPenPercent", 0.0)),
		"digitalPen": float(attacker.get("digitalPen", 0.0)), "digitalPenPercent": float(attacker.get("digitalPenPercent", 0.0)),
	}
	if skill_id == "SK_PIERCE":
		penetration["armorPen"] = float(penetration["armorPen"]) + 20.0
	var redirected_raw: float = 0.0
	var bulwark: CombatActorState = null
	if actor.side == "enemy" and target.kind == "operator":
		for drone: CombatActorState in state.drones:
			if drone.alive and drone.drone_role == "bulwark":
				bulwark = drone
				break
		if bulwark != null:
			redirected_raw = minf(raw * 0.1, 20.0)
			raw -= redirected_raw
	var mitigation: Dictionary = _damage.mitigate_packet(raw, damage_type, {"armor": defender.get("armor", 0.0), "energyRes": defender.get("energyRes", 0.0), "digitalRes": defender.get("digitalRes", 0.0)}, penetration)
	var incoming: float = float(mitigation["afterDefense"]) * float(defender.get("incomingAll", 1.0)) * float(defender.get("incomingKinetic" if damage_type == "KINETIC" else "incomingEnergy" if damage_type == "ENERGY" else "incomingDigital", 1.0))
	if target.side == "enemy" and not str(target.flags.get("protectedBy", "")).is_empty():
		var protector: CombatActorState = _actor_by_id(state, str(target.flags["protectedBy"]))
		if protector != null and protector.alive and protector.template_id == "E12":
			incoming *= 0.85
	if _has_status(target, "MARK"):
		incoming *= 1.3
		target.statuses.erase("MARK")
	var partition: Dictionary = _damage.partition_damage(incoming, {"hp": target.hp, "shield": target.shield, "temp": target.temp_shields}, clampf(bypass_shield_ratio, 0.0, 1.0), float(defender.get("incomingShield", 1.0)))
	_apply_partition(target, partition)
	_restore_elite_shield(state, target)
	target.flags["lastDamagedAt"] = float(state.time_ms)
	state.metrics["hits"] = int(state.metrics.get("hits", 0)) + 1
	var dealt: float = float(partition["shieldConsumed"]) + float(partition["hpLost"])
	actor.damage_dealt += dealt
	target.damage_taken += dealt
	if actor.side == "player":
		state.metrics["damageDealt"] = float(state.metrics.get("damageDealt", 0.0)) + dealt
		var by_type: Dictionary = state.metrics["damageByType"]
		by_type[damage_type] = float(by_type.get(damage_type, 0.0)) + incoming
		var by_source: Dictionary = state.metrics["damageBySource"]
		by_source[actor.id] = float(by_source.get(actor.id, 0.0)) + dealt
		state.metrics["shieldAbsorbed"] = float(state.metrics.get("shieldAbsorbed", 0.0)) + float(partition["shieldConsumed"])
	else:
		state.metrics["damageTaken"] = float(state.metrics.get("damageTaken", 0.0)) + dealt
		var taken_by_source: Dictionary = state.metrics["takenBySource"]
		taken_by_source[actor.id] = float(taken_by_source.get(actor.id, 0.0)) + dealt
		if target.kind == "operator":
			state.metrics["hpLost"] = float(state.metrics.get("hpLost", 0.0)) + float(partition["hpLost"])
	var damage_event: Dictionary = {
		"targetId": target.id, "actionId": action_id, "damageType": damage_type, "crit": crit,
		"originActionId": action_id, "amountBeforeDefense": raw, "amountAfterDefense": incoming,
		"shieldConsumed": partition["shieldConsumed"], "hpLost": partition["hpLost"], "bypassed": partition["bypassed"],
		"text": "%s → %s: %s %s%s, щит −%s, HP −%s." % [actor.display_name, target.display_name, _one_decimal(incoming), damage_type, " (крит)" if crit else "", _one_decimal(float(partition["shieldConsumed"])), _one_decimal(float(partition["hpLost"]))],
		"data": {"overkill": partition["overkill"]},
	}
	if not skill_id.is_empty():
		damage_event["skillId"] = skill_id
	_emit(state, "DAMAGE", actor.id, damage_event)
	if actor.side == "enemy" and target.side == "player":
		_resolve_enemy_direct_hit_effects(state, actor, target, action_id, raw)
	if bulwark != null and redirected_raw > 0.0:
		_apply_redirected_damage(state, actor, bulwark, redirected_raw, damage_type, action_id, skill_id, penetration, crit)
	return {"ok": true, "hit": true, "damage": dealt, "raw": raw, "error": ""}

func _apply_redirected_damage(state: CombatState, source: CombatActorState, target: CombatActorState, raw: float, damage_type: String, action_id: String, skill_id: String, penetration: Dictionary, crit: bool) -> void:
	var defender: Dictionary = _effective_sheet(state, target, source)
	var mitigation: Dictionary = _damage.mitigate_packet(raw, damage_type, {"armor": defender.get("armor", 0.0), "energyRes": defender.get("energyRes", 0.0), "digitalRes": defender.get("digitalRes", 0.0)}, penetration)
	var incoming: float = float(mitigation["afterDefense"]) * float(defender.get("incomingAll", 1.0)) * float(defender.get("incomingKinetic" if damage_type == "KINETIC" else "incomingEnergy" if damage_type == "ENERGY" else "incomingDigital", 1.0))
	var partition: Dictionary = _damage.partition_damage(incoming, {"hp": target.hp, "shield": target.shield, "temp": target.temp_shields}, 0.0, float(defender.get("incomingShield", 1.0)))
	_apply_partition(target, partition)
	target.flags["lastDamagedAt"] = float(state.time_ms)
	var dealt: float = float(partition["shieldConsumed"]) + float(partition["hpLost"])
	source.damage_dealt += dealt
	target.damage_taken += dealt
	state.metrics["damageTaken"] = float(state.metrics.get("damageTaken", 0.0)) + dealt
	var taken_by_source: Dictionary = state.metrics.get("takenBySource", {})
	taken_by_source[source.id] = float(taken_by_source.get(source.id, 0.0)) + dealt
	state.metrics["takenBySource"] = taken_by_source
	_emit(state, "DAMAGE", source.id, {"targetId": target.id, "actionId": action_id, "skillId": skill_id if not skill_id.is_empty() else "", "damageType": damage_type, "crit": crit, "amountBeforeDefense": raw, "amountAfterDefense": incoming, "shieldConsumed": partition["shieldConsumed"], "hpLost": partition["hpLost"], "bypassed": 0.0, "text": "%s → %s: %s перенаправленного урона." % [source.display_name, target.display_name, _one_decimal(incoming)], "data": {"overkill": partition["overkill"], "redirected": true}})

func _restore_elite_shield(state: CombatState, target: CombatActorState) -> void:
	if target.side != "enemy" or target.elite_mod != "EL_SHIELD" or target.hp <= 0.0 or target.hp / maxf(1.0, float(target.base_sheet.get("maxHP", 1.0))) >= 0.5 or bool(target.flags.get("eliteShieldRestored", false)):
		return
	target.flags["eliteShieldRestored"] = true
	var before: float = target.shield
	target.shield = minf(float(_effective_sheet(state, target).get("maxShield", target.base_sheet.get("maxShield", 0.0))), target.shield + 20.0)
	_emit(state, "SHIELD_GAIN", target.id, {"text": "%s: элитный щит +%s." % [target.display_name, _one_decimal(target.shield - before)], "data": {"amount": target.shield - before, "trigger": "EL_SHIELD"}})

func _resolve_enemy_direct_hit_effects(state: CombatState, actor: CombatActorState, target: CombatActorState, action_id: String, raw_damage: float) -> void:
	var definitions: Array[Dictionary] = _enemy_ability_definitions(actor, state)
	if actor.template_id == "E18" and not bool(actor.flags.get("E18_leak_triggered", false)):
		for ability: Dictionary in definitions:
			if str(ability.get("id", "")) == "E18_leak":
				actor.flags["E18_leak_triggered"] = true
				_add_simple_status(state, actor, target, str(ability.get("status", "SHIELD_LEAK")), float(ability.get("statusDurationMs", 4000.0)))
				break
	if actor.template_id == "E14" or actor.elite_mod == "EL_VIRUS":
		var hit_count: int = int(actor.flags.get("virusDirectHitCount", 0)) + 1
		actor.flags["virusDirectHitCount"] = hit_count
		if hit_count % 3 == 0:
			_add_virus_status(state, actor, target, raw_damage, action_id)

func _add_virus_status(state: CombatState, source: CombatActorState, target: CombatActorState, raw_damage: float, action_id: String) -> void:
	var definition: Dictionary = _status_catalog.get_definition("VIRUS")
	var source_sheet: Dictionary = _effective_sheet(state, source, target)
	var duration: float = float(definition.get("durationMs", 6000.0)) * (1.0 + (float(source_sheet.get("dotDuration", 0.0)) + float(source_sheet.get("virusDuration", 0.0))) / 100.0)
	var snapshot: float = float(source_sheet.get("techPower", 0.0)) * (1.0 + float(source_sheet.get("statusDamage", 0.0)) / 100.0) * (1.0 + float(source_sheet.get("virusDamage", 0.0)) / 100.0)
	var entries: Array = target.statuses.get("VIRUS", [])
	var max_stacks: int = int(definition.get("maxStacks", 6)) + floori(float(source_sheet.get("virusStackCap", 0.0)))
	if entries.size() >= max_stacks:
		entries.pop_front()
	entries.append({"sourceId": "%s:VIRUS" % source.id, "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration, "nextTickAt": float(state.time_ms) + float(definition.get("tickMs", 1000.0)), "snapshot": snapshot, "stacks": 1})
	target.statuses["VIRUS"] = entries
	_emit(state, "STATUS_APPLY", source.id, {"targetId": target.id, "actionId": action_id, "statusId": "VIRUS", "text": "%s: %s." % [target.display_name, str(definition.get("name", "VIRUS"))], "data": {"stacks": entries.size(), "snapshot": snapshot, "durationMs": duration}})

func _outgoing_multiplier(sheet: Dictionary, damage_type: String, is_main: bool) -> float:
	var type_stat: String = "kineticDamage" if damage_type == "KINETIC" else "energyDamage" if damage_type == "ENERGY" else "digitalDamage"
	var more_type: String = "moreKinetic" if damage_type == "KINETIC" else "moreEnergy" if damage_type == "ENERGY" else "moreDigital"
	var multiplier: float = (1.0 + float(sheet.get(type_stat, 0.0)) / 100.0) * (1.0 + float(sheet.get("allDamage", 0.0)) / 100.0)
	if is_main:
		multiplier *= 1.0 + float(sheet.get("mainDamage", 0.0)) / 100.0
	multiplier *= float(sheet.get(more_type, 1.0)) * float(sheet.get("moreDirect", 1.0))
	if is_main:
		multiplier *= float(sheet.get("moreMain", 1.0))
	return multiplier

func _apply_partition(actor: CombatActorState, result: Dictionary) -> void:
	var regular_consumed: float = float(result["shieldConsumed"])
	for consumed: Dictionary in result["tempConsumed"]:
		regular_consumed -= float(consumed["amount"])
		for pool: Dictionary in actor.temp_shields:
			if str(pool.get("sourceId", "")) == str(consumed["sourceId"]):
				pool["amount"] = maxf(0.0, float(pool.get("amount", 0.0)) - float(consumed["amount"]))
	actor.temp_shields = actor.temp_shields.filter(func(pool: Dictionary) -> bool: return float(pool.get("amount", 0.0)) > 0.0)
	actor.shield = maxf(0.0, actor.shield - regular_consumed)
	actor.hp = maxf(0.0, actor.hp - float(result["hpLost"]))

func _schedule_next_attack(state: CombatState, actor: CombatActorState) -> void:
	var interval: float = actor.attack_interval_ms
	if actor.kind == "operator":
		var sheet: Dictionary = _effective_sheet(state, actor)
		var weapon: Dictionary = state.build.get("mainWeapon", {})
		interval = _formula.attack_interval_ms(float(weapon.get("intervalMs", 1000.0)), float(sheet.get("attackSpeed", 0.0)), float(sheet.get("moreAttackSpeed", 1.0)))
	if actor.is_boss:
		interval /= 1.0 + maxf(0.0, float(actor.flags.get("bossAttackSpeedBonus", 0.0)))
	if _has_status(actor, "SHOCK"):
		interval /= 0.7
	if actor.kind == "drone" and _has_status(actor, "DRONE_JAM"):
		interval /= 0.5
	actor.next_attack_at += interval
	if actor.next_attack_at <= float(state.time_ms):
		actor.next_attack_at = float(state.time_ms) + interval

func _gain_basic_heat(state: CombatState, actor: CombatActorState, amount: float) -> void:
	if amount <= 0.0:
		return
	var max_heat: float = float(actor.base_sheet.get("maxHeat", 0.0))
	var before: float = actor.heat
	actor.heat = clampf(actor.heat + amount, 0.0, max_heat)
	if not actor.heat_lockout and before < max_heat and actor.heat >= max_heat:
		actor.heat_lockout = true
		_emit(state, "HEAT", actor.id, {"text": "Нагрев достиг максимума.", "data": {"heat": actor.heat, "threshold": max_heat}})
		state.metrics["heatLockouts"] = int(state.metrics.get("heatLockouts", 0)) + 1
		_emit(state, "HEAT_LOCKOUT", actor.id, {"text": "Перегрев: main-канал заблокирован до охлаждения ≤ 80."})

func _resolve_basic_deaths(state: CombatState) -> void:
	for actor: CombatActorState in state.all_actors():
		if not actor.alive or actor.hp > 0.0:
			continue
		actor.alive = false
		_emit(state, "DEATH", actor.id, {"text": "%s уничтожен." % actor.display_name})
		if actor.side == "enemy":
			state.metrics["kills"] = int(state.metrics.get("kills", 0)) + 1
			var ttk: Array = state.metrics["ttk"]
			ttk.append({"enemyId": actor.id, "name": actor.display_name, "ms": state.time_ms})
			if actor.elite_mod == "EL_SPLIT":
				_spawn_summoned_enemy(state, actor, "E20", 0.5)
				_spawn_summoned_enemy(state, actor, "E20", 0.5)
			for ability: Dictionary in _enemy_ability_definitions(actor, state):
				if str(ability.get("kind", "")) != "deathBurst":
					continue
				var action_id: String = "%s:death:%s" % [actor.id, str(ability.get("id", ""))]
				var windup: float = maxf(float(ability.get("windupMs", 0.0)), float(ability.get("telegraphMs", 0.0)))
				actor.cast = {"actionId": action_id, "skillId": "", "abilityId": str(ability.get("id", "")), "startedAt": state.time_ms, "resolveAt": float(state.time_ms) + windup, "endAt": float(state.time_ms) + windup, "targetId": state.operator.id if state.operator.alive else "", "interruptible": false, "telegraph": float(ability.get("telegraphMs", 0.0)) > 0.0, "dangerTag": "deathBurst", "channel": "main"}
				_emit(state, "CAST_START", actor.id, {"targetId": actor.cast["targetId"], "actionId": action_id, "text": "%s: %s" % [actor.display_name, str(ability.get("desc", ""))], "data": {"abilityId": ability.get("id", ""), "windupMs": windup, "interruptible": false}})
				if bool(actor.cast["telegraph"]):
					_emit(state, "TELEGRAPH", actor.id, {"targetId": actor.cast["targetId"], "actionId": action_id, "text": "%s: %s" % [actor.display_name, str(ability.get("desc", ""))], "data": {"abilityId": ability.get("id", ""), "dangerTag": "deathBurst", "windupMs": windup}})
				break
			for ally: CombatActorState in state.enemies:
				if ally.alive and ally.template_id == "E23":
					_add_simple_status(state, ally, ally, "BERSERK", 999000.0)
		elif actor.kind == "drone":
			state.metrics["droneDeaths"] = int(state.metrics.get("droneDeaths", 0)) + 1

func _resolve_boss_phases(state: CombatState) -> void:
	for boss: CombatActorState in state.enemies:
		if not boss.alive or not boss.is_boss or boss.hp <= 0.0:
			continue
		var template: Dictionary = _enemy_ability_template(boss)
		var phases: Array[Dictionary] = []
		for phase_index: int in range(template.get("phases", []).size()):
			phases.append({"phase": template["phases"][phase_index], "index": phase_index})
		phases.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left["phase"].get("hpFraction", 0.0)) > float(right["phase"].get("hpFraction", 0.0)))
		var hp_fraction: float = boss.hp / maxf(1.0, float(boss.base_sheet.get("maxHP", 1.0)))
		for indexed_phase: Dictionary in phases:
			var phase: Dictionary = indexed_phase["phase"]
			var phase_index: int = int(indexed_phase["index"])
			var flag: String = "bossPhase:%d" % phase_index
			if bool(boss.flags.get(flag, false)) or hp_fraction > float(phase.get("hpFraction", 0.0)):
				continue
			boss.flags[flag] = true
			_apply_boss_phase(state, boss, phase, phase_index)

func _enemy_ability_template(actor: CombatActorState) -> Dictionary:
	if _factory._enemy_catalog.enemies.is_empty():
		_factory._enemy_catalog.load_catalog()
	return _factory._enemy_catalog.get_template(actor.template_id)

func _apply_boss_phase(state: CombatState, boss: CombatActorState, phase: Dictionary, phase_index: int) -> void:
	var kind: String = str(phase.get("kind", ""))
	_emit(state, "PHASE", boss.id, {"text": "%s: %s" % [boss.display_name, str(phase.get("desc", "Фаза босса"))], "data": {"phaseIndex": phase_index, "hpFraction": phase.get("hpFraction", 0.0), "phaseKind": kind}})
	var amount: float = float(phase.get("amount", 0.0))
	match kind:
		"summon":
			_spawn_summoned_enemy(state, boss, str(phase.get("summonId", "")))
		"attackSpeed":
			_add_boss_attack_speed(state, boss, amount)
		"intervalReduce":
			if str(phase.get("target", "attacks")) == "abilities":
				var previous: float = maxf(0.01, float(boss.flags.get("bossAbilityIntervalMultiplier", 1.0)))
				var current: float = maxf(0.01, previous * (1.0 - clampf(amount, 0.0, 0.95)))
				boss.flags["bossAbilityIntervalMultiplier"] = current
				for ability_id: Variant in boss.ability_next.keys():
					var next_at: float = float(boss.ability_next[ability_id])
					if next_at > float(state.time_ms) and next_at < 999999999.0:
						boss.ability_next[ability_id] = float(state.time_ms) + (next_at - float(state.time_ms)) * current / previous
			else:
				_add_boss_attack_speed(state, boss, amount)
		"castSpeed":
			var previous: float = maxf(0.0, float(boss.flags.get("bossCastSpeedIncrease", 0.0)))
			var current: float = previous + amount
			boss.flags["bossCastSpeedIncrease"] = current
			if boss.cast is Dictionary and not bool(boss.cast.get("resolved", false)) and float(boss.cast.get("resolveAt", 0.0)) > float(state.time_ms):
				var factor: float = (1.0 + previous) / (1.0 + current)
				boss.cast["resolveAt"] = float(state.time_ms) + (float(boss.cast["resolveAt"]) - float(state.time_ms)) * factor
				boss.cast["endAt"] = float(state.time_ms) + (float(boss.cast["endAt"]) - float(state.time_ms)) * factor
		"bypassUpgrade":
			boss.flags["digitalShieldBypassBonus"] = float(boss.flags.get("digitalShieldBypassBonus", 0.0)) + amount
		"cleanse":
			if not _status_catalog_loaded:
				var loaded: Dictionary = _status_catalog.load_catalog()
				_status_catalog_loaded = true
				_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
			if _status_catalog_error.is_empty():
				for status_id: Variant in boss.statuses.keys().duplicate():
					if bool(_status_catalog.get_definition(str(status_id)).get("harmful", false)):
						boss.statuses.erase(status_id)
						_emit(state, "STATUS_EXPIRE", boss.id, {"statusId": status_id, "text": "%s: %s очищен фазой." % [boss.display_name, str(status_id)]})

func _add_boss_attack_speed(state: CombatState, boss: CombatActorState, amount: float) -> void:
	var previous: float = float(boss.flags.get("bossAttackSpeedBonus", 0.0))
	var current: float = previous + amount
	boss.flags["bossAttackSpeedBonus"] = current
	if boss.next_attack_at > float(state.time_ms):
		boss.next_attack_at = float(state.time_ms) + (boss.next_attack_at - float(state.time_ms)) * (1.0 + previous) / (1.0 + current)

func _spawn_summoned_enemy(state: CombatState, owner: CombatActorState, template_id: String, hp_mult: float = 1.0) -> void:
	var living_summons: int = 0
	for enemy: CombatActorState in state.enemies:
		if enemy.alive and enemy.summoned:
			living_summons += 1
	if living_summons >= 2:
		_emit(state, "CAST_FIZZLE", owner.id, {"reason": "summon_cap", "text": "%s: лимит призывов достигнут." % owner.display_name, "data": {"templateId": template_id, "summonCap": 2}})
		return
	var created: Dictionary = _factory._create_enemy({"templateId": template_id, "hpMult": hp_mult, "summoned": true, "noLoot": true}, state.enemies.size(), state.depth, state.extra_enemy_digital_bonus)
	if not bool(created.get("ok", false)):
		_emit(state, "CAST_FIZZLE", owner.id, {"reason": "unknown_summon", "text": "%s: неизвестный призыв %s." % [owner.display_name, template_id]})
		return
	var summon: CombatActorState = created["actor"] as CombatActorState
	summon.owner_id = owner.id
	summon.next_attack_at = float(state.time_ms) + summon.attack_interval_ms
	state.enemies.append(summon)
	_emit(state, "SUMMON", owner.id, {"targetId": summon.id, "text": "%s вызывает %s." % [owner.display_name, summon.display_name], "data": {"templateId": template_id, "hp": summon.hp, "noLoot": true}})

func _check_terminal(state: CombatState) -> void:
	if not state.operator.alive:
		state.outcome = "DEFEAT"
	elif not state.enemies.any(func(enemy: CombatActorState) -> bool: return enemy.alive) and not state.enemies.any(func(enemy: CombatActorState) -> bool: return enemy.cast is Dictionary and str(enemy.cast.get("abilityId", "")) == "E19_death" and not bool(enemy.cast.get("resolved", false))):
		state.outcome = "VICTORY"
	elif state.time_ms >= state.max_duration_ms:
		state.outcome = "TIMEOUT"
	if not state.outcome.is_empty():
		_emit(state, "COMBAT_END", "operator", {"text": "Бой завершён: %s." % state.outcome, "data": {"outcome": state.outcome}})

func _one_decimal(value: float) -> String:
	return "%.1f" % value

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
