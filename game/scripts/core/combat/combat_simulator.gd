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
	var requested_version: String = str(config.get("combatRulesVersion", COMBAT_RULES_VERSION))
	if requested_version not in [COMBAT_RULES_VERSION, CombatState.V2_RULES_VERSION]:
		return _failure("Неподдерживаемая версия боевых правил; требуется явная миграция.")
	# Incremental adapter: never silently drop unported authored abilities.
	if requested_version == CombatState.V2_RULES_VERSION:
		var v2_build: Dictionary = config.get("build", {})
		if not config.get("tactics", {}).is_empty() or not v2_build.get("triggerEffects", []).is_empty() or not v2_build.get("drones", []).is_empty():
			return _failure("V2 adapter: proc-эффекты и дроны ещё не подключены; тактики V1 запрещены.")
		for skill: Variant in v2_build.get("skills", []):
			if not skill is Dictionary or str(skill.get("channel", "main")) != "main" or not AutobattleV2Contract.SUPPORTED_MAIN_SKILLS.has(str(skill.get("id", ""))):
				return _failure("V2 adapter: неподдерживаемая способность отклонена явно (%s)." % str(skill.get("id", "unknown")) if skill is Dictionary else "V2 adapter: некорректная запись способности.")
			var compiled_target: Dictionary = AutobattleV2Contract.compile_target(str(skill.get("targetMode", "HIGHEST_THREAT")))
			if not bool(compiled_target.get("ok", false)):
				return _failure("V2 adapter: %s" % str(compiled_target.get("error", "UNSUPPORTED_TARGET_MODE")))
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
	state.combat_rules_version = requested_version
	if requested_version == CombatState.V2_RULES_VERSION:
		if _factory.compile_v2_weapon_action(build_value).is_empty():
			return _failure("V2 adapter: не удалось скомпилировать реальное оружие.")
		state.action_channel = AutobattleV2Channel.new().new_state()
	state.seed = str(seed_value)
	state.depth = int(depth_value)
	state.biome = str(config.get("biome", "B01"))
	state.node_type = str(config.get("nodeType", "COMBAT"))
	state.max_duration_ms = int(config.get("maxDurationMs", DEFAULT_MAX_DURATION_MS))
	state.operator = roster["operator"] as CombatActorState
	state.drones = roster["drones"]
	state.enemies = roster["enemies"]
	state.allies = roster.get("allies", [])
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
	state.rules_hash = _hash.hash_string(_hash.stable_stringify({"version": requested_version, "tactics": state.tactics}))
	if requested_version == CombatState.V2_RULES_VERSION:
		state.rules_hash = _factory.v2_build_rules_hash(state.build)
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
	var start_event: Dictionary = _emit(state, "COMBAT_START", "operator", {
		"text": "Бой начался: %s." % ", ".join(enemy_names),
		"data": {"initialTempShield": float(config.get("initialTempShield", 0.0)), "initialExtraHeat": float(config.get("initialExtraHeat", 0.0)), "alliedCount": state.allies.size()},
	})
	var start_rng: DeterministicRng = _new_rng(state.seed)
	_dispatch_authored_event(state, start_rng, "ON_COMBAT_START", state.operator, null, "combat-start", int(start_event.get("eventId", 0)))
	state.rng = start_rng.serialize()
	return {"ok": true, "state": state, "error": ""}

func step_combat(state: CombatState) -> Dictionary:
	if state == null:
		return _failure("Нельзя продвинуть пустое состояние боя.")
	if state.combat_rules_version not in [COMBAT_RULES_VERSION, CombatState.V2_RULES_VERSION]:
		return _failure("Версия снимка не соответствует боевому движку.")
	if not state.outcome.is_empty():
		return {"ok": true, "state": state, "error": ""}
	if not _supports_basic_auto_step(state):
		return _failure("Эта боевая конфигурация требует ещё не перенесённые способности, статусы, триггеры или тактические правила.")
	var next: CombatState = state.clone()
	var rng: DeterministicRng = DeterministicRng.new()
	if not rng.restore(next.rng):
		return _failure("Состояние боевого RNG повреждено.")
	next.time_ms += TICK_MS
	_apply_basic_continuous(next, rng)
	_tick_dot_statuses(next)
	_expire_dot_statuses(next, rng)
	_run_periodic_drone_triggers(next, rng)
	_advance_reaction_cast(next, rng)
	_advance_drone_skill_casts(next, rng)
	if next.combat_rules_version == COMBAT_RULES_VERSION:
		_advance_main_skill_cast(next, rng)
	_advance_enemy_ability_casts(next, rng)
	if next.combat_rules_version == COMBAT_RULES_VERSION:
		_choose_reaction_skill(next, rng)
	var ready: Array[CombatActorState] = next.all_actors()
	ready.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	for actor: CombatActorState in ready:
		if not actor.alive:
			continue
		if actor.kind == "operator" and next.combat_rules_version == CombatState.V2_RULES_VERSION:
			var v2_result: Dictionary = _step_v2_weapon_channel(next, rng)
			if not bool(v2_result.get("ok", false)):
				return v2_result
			continue
		if actor.side == "enemy" and actor.cast == null:
			var scheduled_ability: Dictionary = _ready_enemy_ability(next, actor)
			if not scheduled_ability.is_empty():
				_start_enemy_ability(next, rng, actor, scheduled_ability)
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
	_resolve_basic_deaths(next, rng)
	_resolve_boss_phases(next)
	_check_terminal(next)
	next.rng = rng.serialize()
	return {"ok": true, "state": next, "error": ""}

func _step_v2_weapon_channel(state: CombatState, rng: DeterministicRng) -> Dictionary:
	var channel: AutobattleV2Channel = AutobattleV2Channel.new()
	var actor: CombatActorState = state.operator
	if _has_status(actor, "STUN") and not state.action_channel.get("active", {}).is_empty():
		var interrupted: Dictionary = channel.interrupt(state.action_channel, state.time_ms)
		if not bool(interrupted.get("ok", false)):
			return _failure(str(interrupted.get("error", "INVALID_ACTION_CHANNEL")))
		state.action_channel = interrupted["state"]
		if bool(interrupted.get("interrupted", false)):
			_emit(state, "ACTION_INTERRUPTED", actor.id, {"data": {"reason": "STUN", "phase": "PREPARE"}})
	var context: Dictionary = state.action_channel.get("active", {}).duplicate(true)
	var advanced: Dictionary = channel.advance(state.action_channel, state.time_ms)
	if not bool(advanced.get("ok", false)):
		return _failure(str(advanced.get("error", "INVALID_ACTION_CHANNEL")))
	state.action_channel = advanced["state"]
	var captured_targets: Array = context.get("targetIds", context.get("action", {}).get("targetIds", []))
	var target_ids: Array[String] = []
	for captured_id: Variant in captured_targets:
		var captured_actor: CombatActorState = _actor_by_id(state, str(captured_id))
		if captured_actor != null and captured_actor.alive: target_ids.append(captured_actor.id)
	var target: CombatActorState = _actor_by_id(state, target_ids[0]) if not target_ids.is_empty() else null
	if not advanced["commit"].is_empty() and target == null:
		var doctrine: int = int(advanced["commit"].get("targetDoctrine", AutobattleV2Contract.Doctrine.HIGHEST_THREAT))
		var retargeted: Dictionary = _v2_resolve_targets(state, doctrine, actor.last_target_id, str(context.get("action", {}).get("actionId", "weapon:basic")))
		if bool(retargeted.get("ok", false)):
			for target_id: Variant in retargeted.get("targets", []): target_ids.append(str(target_id))
		target = _actor_by_id(state, target_ids[0]) if not target_ids.is_empty() else null
		if target != null:
			context["targetIds"] = target_ids.duplicate()
			_emit(state, "TARGET_REACQUIRED", actor.id, {"actionId": context.get("instanceId", ""), "targetId": target.id, "targetIds": target_ids.duplicate(), "reason": "PREPARED_TARGET_UNAVAILABLE"})
	elif not advanced["commit"].is_empty() and not target_ids.is_empty():
		context["targetIds"] = target_ids.duplicate()
	if not advanced["commit"].is_empty():
		var committed: Dictionary = advanced["commit"]
		var reason: String = ""
		if target == null:
			reason = "NO_TARGET"
		elif _has_status(actor, "STUN"):
			reason = "STUN"
		elif actor.energy < float(committed.get("energyCost", 0)):
			reason = "ENERGY_AT_COMMIT"
		elif actor.heat_lockout and float(committed.get("heatDelta", 0)) > 0:
			reason = "THERMAL_LOCK"
		elif str(committed.get("classId", "")) == "SPECIAL_ATTACK" and not _v2_requirements_pass(state, committed, target):
			reason = "REQUIREMENT_AT_COMMIT"
		if reason.is_empty():
			var applied: Dictionary = _resolve_v2_action(state, rng, actor, target, context)
			if not bool(applied.get("ok", false)):
				return applied
		else:
			state.action_channel.get("cooldowns", {}).erase(str(committed.get("actionId", "")))
			_emit(state, "ACTION_UNAVAILABLE", actor.id, {"data": {"reason": reason, "phase": "COMMIT", "sourceId": committed.get("sourceId", "")}})
	if state.action_channel["active"].is_empty():
		var actions: Array[Dictionary] = _factory.compile_v2_main_actions(state.build, _effective_sheet(state, actor), 1.0 / 0.7 if _has_status(actor, "SHOCK") else 1.0)
		var available: Array[Dictionary] = []
		for action: Dictionary in actions:
			if not str(action.get("targetError", "")).is_empty():
				return _failure(str(action["targetError"]))
			var action_skill: Dictionary = _v2_skill(state, str(action.get("skillId", "")))
			if action_skill.get("tags", []).has("D") and _has_status(actor, "JAM"):
				action["cooldownMs"] = int(ceili(float(action.get("cooldownMs", 0)) * 1.3 / 100.0)) * 100
			var resolved_targets: Dictionary = _v2_resolve_targets(state, int(action.get("targetDoctrine", -1)), actor.last_target_id, str(action.get("actionId", "")))
			if not bool(resolved_targets.get("ok", false)):
				return _failure(str(resolved_targets.get("error", "TARGET_RESOLUTION_FAILED")))
			var candidate_target_ids: Array[String] = []
			candidate_target_ids.assign(resolved_targets["targets"])
			var action_target: CombatActorState = _actor_by_id(state, candidate_target_ids[0]) if not candidate_target_ids.is_empty() else null
			action["hasValidTarget"] = not candidate_target_ids.is_empty()
			action["targetIds"] = candidate_target_ids.duplicate()
			if str(action.get("classId", "")) == "SPECIAL_ATTACK" and not _v2_requirements_pass(state, action, action_target):
				action["hasValidTarget"] = false
			if not action["hasValidTarget"]:
				_emit(state, "ACTION_UNAVAILABLE", actor.id, {"data": {"actionId": action["actionId"], "reason": "NO_TARGET"}})
				continue
			available.append(action)
		if _has_status(actor, "STUN"):
			return {"ok": true}
		var chosen: Dictionary = channel.start(state.action_channel, available, state.time_ms, actor.energy, actor.heat, float(actor.base_sheet.get("maxHeat", 100)), actor.heat_lockout)
		if not bool(chosen.get("ok", false)):
			return _failure(str(chosen.get("error", "INVALID_ACTION_CHANNEL")))
		state.action_channel = chosen["state"]
		for rejected: Dictionary in chosen["rejected"]:
			_emit(state, "ACTION_UNAVAILABLE", actor.id, {"data": rejected})
		if not chosen["action"].is_empty():
			var instance_id: String = "%s:v2:%d" % [actor.id, state.time_ms]
			var chosen_action: Dictionary = chosen["action"]
			var chosen_targets: Array = chosen_action.get("targetIds", [])
			var prepare_event: Dictionary = _emit(state, "ACTION_PREPARE", actor.id, {"actionId": instance_id, "sourceId": str(chosen_action["sourceId"]), "targetId": str(chosen_targets[0]) if not chosen_targets.is_empty() else "", "targetIds": chosen_targets.duplicate(), "data": chosen_action})
			state.action_channel["active"]["instanceId"] = instance_id
			state.action_channel["active"]["prepareEventId"] = int(prepare_event["eventId"])
			state.action_channel["active"]["targetIds"] = chosen_targets.duplicate()
	return {"ok": true}

func _v2_resolve_targets(state: CombatState, doctrine: int, focus_id: String, action_id: String) -> Dictionary:
	var seeded_roll: int = 0
	if doctrine == AutobattleV2Contract.Doctrine.RANDOM_SEEDED:
		var targeting_rng: DeterministicRng = _new_rng("v2-target:%s:%d:%s" % [state.seed, state.time_ms, action_id])
		seeded_roll = targeting_rng.int_range(0, 0x7FFFFFFF)
	return AutobattleV2Targets.new().resolve(state, doctrine, focus_id, seeded_roll)

func _v2_requirements_pass(state: CombatState, action: Dictionary, target: CombatActorState) -> bool:
	for requirement_value: Variant in action.get("requires", []):
		if not requirement_value is String:
			return false
		match str(requirement_value):
			"VIRUS":
				if target == null or not _has_status(target, "VIRUS"): return false
			"SIDEARM":
				if state.build.get("sidearm", {}).is_empty(): return false
			"MAIN_K":
				if str(state.build.get("mainWeapon", {}).get("type", "")) != "KINETIC": return false
			"DR_MED", "DR_EMP":
				return false
			_:
				return false
	return true

func _resolve_v2_action(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, context: Dictionary) -> Dictionary:
	var action: Dictionary = context.get("action", {})
	if str(action.get("classId", "")) == "BASIC_ATTACK":
		return _resolve_basic_attack(state, rng, actor, target, context)
	if str(action.get("classId", "")) != "SPECIAL_ATTACK":
		return _failure("V2 adapter: неизвестный класс действия %s." % str(action.get("classId", "")))
	var skill: Dictionary = _v2_skill(state, str(action.get("skillId", "")))
	if skill.is_empty():
		return _failure("V2 adapter: скомпилированная способность отсутствует в BuildResolver (%s)." % str(action.get("skillId", "")))
	var cost: float = float(action.get("energyCost", _main_skill_energy_cost(skill, _effective_sheet(state, actor))))
	if actor.energy < cost:
		return _failure("V2 adapter: энергия изменилась до атомарной фиксации способности.")
	actor.energy = clampf(actor.energy - cost, 0.0, float(actor.base_sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	_gain_basic_heat(state, actor, float(skill.get("heatDelta", 0.0)), rng)
	var sheet: Dictionary = _effective_sheet(state, actor)
	var cooldown: float = _formula.cooldown_ms(float(skill.get("cooldownMs", 0.0)), float(sheet.get("cooldownRecovery", 0.0)))
	if skill.get("tags", []).has("D") and _has_status(actor, "JAM"):
		cooldown *= 1.3
	actor.cooldowns[str(skill["id"])] = float(state.time_ms) + cooldown
	var channel_cooldowns: Dictionary = state.action_channel.get("cooldowns", {})
	var recovery_until: int = int(state.action_channel.get("active", {}).get("timeline", {}).get("recoveryUntilMs", state.time_ms))
	channel_cooldowns[str(action.get("actionId", ""))] = maxi(recovery_until, state.time_ms + int(ceili(cooldown / float(TICK_MS))) * TICK_MS)
	state.action_channel["cooldowns"] = channel_cooldowns
	actor.counters["casts"] = int(actor.counters.get("casts", 0)) + 1
	var cast: Dictionary = {
		"actionId": str(context.get("instanceId", "%s:v2:%d" % [actor.id, state.time_ms])),
		"skillId": str(skill["id"]), "targetId": target.id if target != null else "",
		"targetIds": context.get("targetIds", []), "startedAt": int(context.get("timeline", {}).get("commitAtMs", state.time_ms)),
		"resolveAt": state.time_ms, "endAt": int(context.get("timeline", {}).get("recoveryUntilMs", state.time_ms)),
		"interruptible": false, "resolved": true, "channel": "main", "causeId": int(context.get("prepareEventId", 0)),
	}
	actor.last_skill_id = str(skill["id"])
	actor.last_target_id = target.id if target != null else ""
	actor.last_main_attack_at = state.time_ms
	actor.next_attack_at = float(cast["endAt"])
	_record_enemy_judge_program(state, str(skill["id"]))
	_resolve_main_skill(state, rng, actor, cast)
	_consume_hit_buffs(actor)
	return {"ok": true, "error": ""}

func _v2_skill(state: CombatState, skill_id: String) -> Dictionary:
	for skill: Dictionary in state.build.get("skills", []):
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}

func _supports_basic_auto_step(state: CombatState) -> bool:
	if not _supports_skill_trigger_effects(state):
		return false
	for rule_value: Variant in state.tactics.get("rules", []):
		if not rule_value is Dictionary or not bool(rule_value.get("enabled", false)):
			continue
		if str(rule_value.get("skillId", "AUTO")) not in ["AUTO", "SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_BLADE", "SK_PLASMA", "SK_ARC", "SK_OVR", "SK_NEURO", "SK_SEED", "SK_DETONATE", "SK_BREAK", "SK_SCAN", "SK_LEECH", "SK_CHAIN", "SK_KINETIC", "SK_SIDE_FIRE", "SK_SHIELD", "SK_EMP", "SK_GUARD", "SK_VENT", "SK_HEAL", "SK_DRONE_MARK"]:
			return false
	if state.extra_enemy_digital_bonus != 0.0:
		return false
	for actor: CombatActorState in state.all_actors():
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
		var effect: Dictionary = trigger_value.get("effect", {})
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var effect_id: String = str(effect.get("id", ""))
		var skill_trigger: bool = source_id in ["SK_BLADE", "SK_NEURO", "SK_SEED", "SK_BREAK"]
		var periodic_item_trigger: bool = str(effect.get("event", "")) == "PERIODIC" and str(trigger_value.get("sourceKind", "")) in ["item", "tree"] and _supports_periodic_trigger(effect)
		var attack_counter_trigger: bool = str(effect.get("event", "")) == "ON_ATTACK_COUNTER" and str(trigger_value.get("sourceKind", "")) in ["item", "tree"] and _supports_attack_counter_trigger(effect)
		var direct_hit_trigger: bool = str(effect.get("event", "")) == "ON_HIT" and str(trigger_value.get("sourceKind", "")) != "skill" and _supports_direct_hit_trigger(effect)
		var kill_trigger: bool = str(effect.get("event", "")) == "ON_KILL" and _supports_kill_trigger(effect)
		var before_hit_trigger: bool = str(effect.get("event", "")) == "ON_BEFORE_HIT" and _supports_before_hit_trigger(effect)
		var shield_absorb_trigger: bool = str(effect.get("event", "")) == "ON_SHIELD_ABSORB" and _supports_shield_absorb_trigger(effect)
		var effect_shield_trigger: bool = str(effect.get("event", "")) == "ON_EFFECT_SHIELD_SPENT" and str(effect.get("action", {}).get("kind", "")) == "tempShield"
		var authored_event_trigger: bool = _supports_authored_event_trigger(effect)
		if not skill_trigger and not periodic_item_trigger and not attack_counter_trigger and not direct_hit_trigger and not kill_trigger and not before_hit_trigger and not shield_absorb_trigger and not effect_shield_trigger and not authored_event_trigger:
			return false
	return true

func _supports_periodic_trigger(effect: Dictionary) -> bool:
	if float(effect.get("periodMs", 0.0)) <= 0.0: return false
	var action: Dictionary = effect.get("action", {})
	match str(action.get("kind", "")):
		"flag": return not str(action.get("key", "")).is_empty()
		"interrupt": return true
		"repeatLastDigital": return float(action.get("coefficient", 0.0)) > 0.0
		"restoreShield": return float(action.get("amount", 0.0)) > 0.0
		"secondaryDamage": return float(action.get("coefficient", 0.0)) > 0.0 and str(action.get("damageType", "")) in ["KINETIC", "ENERGY", "DIGITAL"] and str(action.get("targeting", "")) in ["nearest", "target", "allEnemies"] and str(action.get("basis", "")) in ["flat", "techPower", "mainWeapon"]
		_: return false

func _supports_attack_counter_trigger(effect: Dictionary) -> bool:
	if int(effect.get("counterEvery", 0)) <= 0: return false
	var action: Dictionary = effect.get("action", {})
	match str(action.get("kind", "")):
		"applyStatus": return STEP_STATUS_IDS.has(str(action.get("status", ""))) and str(action.get("target", "target")) in ["target", "self", "otherEnemy", "allEnemies"]
		"secondaryDamage": return float(action.get("coefficient", 0.0)) > 0.0 and str(action.get("damageType", "")) in ["KINETIC", "ENERGY", "DIGITAL"] and str(action.get("targeting", "")) in ["secondary", "target", "otherEnemy", "allEnemies"] and str(action.get("basis", "")) in ["techPower", "mainWeapon", "flat"]
		"buff": return action.get("mods", []) is Array and not action.get("mods", []).is_empty() and float(action.get("durationMs", 0.0)) > 0.0
		_: return false

func _supports_authored_event_trigger(effect: Dictionary) -> bool:
	var event_name: String = str(effect.get("event", ""))
	var action: Dictionary = effect.get("action", {})
	var kind: String = str(action.get("kind", ""))
	match event_name:
		"ON_DODGE": return kind in ["restoreEnergy", "buff", "reduceCooldown", "flag"]
		"ON_CAST": return kind in ["changeHeat", "applyStatus", "control", "revealNodes", "wanted"]
		"ON_INTERRUPT": return kind in ["extraReaction", "restoreShield"]
		"ON_STATUS_EXPIRE": return kind == "reduceCooldown"
		"ON_TAKEN_DAMAGE", "ON_HEAT_LOCKOUT_END", "ON_ENEMY_TELEGRAPH": return kind == "buff"
		"ON_DRONE_DEATH": return kind in ["restoreEnergy", "secondaryDamage"]
		"ON_COMBAT_START": return kind == "flag"
		"ON_HEAT_FULL": return kind in ["tempShield", "secondaryDamage", "consumeShieldForDamage"]
		"ON_HP_THRESHOLD": return kind == "tempShield"
		_: return false

func _supports_before_hit_trigger(effect: Dictionary) -> bool:
	var action: Dictionary = effect.get("action", {})
	match str(action.get("kind", "")):
		"spendFlagForDamage": return not str(action.get("flag", "")).is_empty() and int(action.get("maxStacks", 0)) > 0
		"packetMod": return action.has("damageMultiplier") or action.has("penMultiplier") or float(action.get("consumeShield", 0.0)) > 0.0
		_: return false

func _supports_shield_absorb_trigger(effect: Dictionary) -> bool:
	var action: Dictionary = effect.get("action", {})
	match str(action.get("kind", "")):
		"restoreEnergy": return float(action.get("amount", 0.0)) > 0.0
		"charge": return float(action.get("amountFromAbsorbed", 0.0)) > 0.0
		"secondaryDamage": return str(action.get("basis", "")) == "consumedShield" and float(action.get("coefficient", 0.0)) > 0.0 and str(action.get("damageType", "")) in ["KINETIC", "ENERGY", "DIGITAL"] and str(action.get("targeting", "")) == "attacker"
		_: return false

func _dispatch_shield_absorb_triggers(state: CombatState, rng: DeterministicRng, attacker: CombatActorState, shield_owner: CombatActorState, damage_type: String, action_id: String, direct: bool, amount: float) -> void:
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary: continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "ON_SHIELD_ABSORB" or not _supports_shield_absorb_trigger(effect): continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var owner: CombatActorState = _trigger_owner(state, source_id)
		if not owner.alive or owner.id != shield_owner.id: continue
		if bool(effect.get("requireDirect", false)) and not direct: continue
		var type_filter: Array = effect.get("damageTypeFilter", [])
		if not type_filter.is_empty() and not type_filter.has(damage_type): continue
		if not _trigger_status_condition_passes(state, owner, attacker, effect.get("condition", {})): continue
		var trigger_id: String = str(effect.get("id", ""))
		var trigger_key: String = "%s:%s" % [source_id, trigger_id]
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(trigger_key, false)): continue
		if float(owner.icds.get(trigger_key, 0.0)) > float(state.time_ms): continue
		var chance: float = clampf(float(effect.get("chance", 1.0)) * float(_effective_sheet(state, owner, attacker).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(chance): continue
		if bool(effect.get("oncePerCombat", false)): owner.once_per_combat[trigger_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0: owner.icds[trigger_key] = float(state.time_ms) + icd_ms
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, trigger_id]
		_emit(state, "TRIGGER", owner.id, {"targetId": attacker.id, "actionId": trigger_action_id, "damageType": damage_type, "text": "%s: сработал эффект «%s» при поглощении урона щитом." % [owner.display_name, trigger_id], "data": {"sourceId": source_id, "amount": amount, "chance": chance}})
		var trigger_action: Dictionary = effect.get("action", {})
		match str(trigger_action.get("kind", "")):
			"restoreEnergy":
				_restore_trigger_energy(state, owner, trigger_action, trigger_action_id)
			"charge":
				var charge_cap: float = float(trigger_action.get("capFlat", 100.0))
				if str(trigger_action.get("capFormula", "")) == "H(T)":
					charge_cap = 100.0 * _formula.h_depth(float(_trigger_item_tech_level(state, source_id)))
				owner.flags["charge"] = minf(charge_cap, float(owner.flags.get("charge", 0.0)) + amount * float(trigger_action.get("amountFromAbsorbed", 0.0)))
			"secondaryDamage":
				if attacker.alive:
					var raw: float = amount * float(trigger_action.get("coefficient", 0.0))
					_resolve_basic_hit(state, rng, owner, attacker, raw, str(trigger_action.get("damageType", "DIGITAL")), trigger_action_id, false, "", 0.0, false, 0.0)

func _dispatch_before_hit_triggers(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, action_id: String, skill_id: String, damage_type: String, raw_amount: float, is_main: bool, direct: bool, proc_weight: float, penetration: Dictionary) -> Dictionary:
	if actor.side != "player" or not direct or (not is_main and actor.kind != "drone"):
		return {"raw": raw_amount, "penetration": penetration}
	var raw: float = raw_amount
	var initial_raw: float = raw_amount
	var pen: Dictionary = penetration.duplicate(true)
	var chain: Dictionary = state.trigger_chains.get(action_id, {"childEvents": 0, "seen": {}, "limitReported": false, "lastAt": state.time_ms, "packetMods": {}})
	var packet_mods: Dictionary = chain.get("packetMods", {})
	var packet_key: String = "%s:%s" % [action_id, target.id]
	if packet_mods.has(packet_key):
		var cached: Dictionary = packet_mods[packet_key]
		var cached_penetration: Dictionary = cached.get("penetration", penetration)
		return {"raw": raw_amount * float(cached.get("multiplier", 1.0)), "penetration": cached_penetration.duplicate(true)}
	state.trigger_chains[action_id] = chain
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary:
			continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "ON_BEFORE_HIT" or not _supports_before_hit_trigger(effect):
			continue
		if bool(effect.get("requireDirect", false)) and not direct:
			continue
		if bool(effect.get("requireDrone", false)) and actor.kind != "drone":
			continue
		var type_filter: Array = effect.get("damageTypeFilter", [])
		if not type_filter.is_empty() and not type_filter.has(damage_type):
			continue
		var skill_filter: Array = effect.get("skillFilter", [])
		if not skill_filter.is_empty() and not skill_filter.has(skill_id):
			continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var owner: CombatActorState = _trigger_owner(state, source_id)
		if not owner.alive or (owner.kind != "operator" and owner.id != actor.id):
			continue
		if not _trigger_status_condition_passes(state, owner, target, effect.get("condition", {})):
			continue
		var trigger_id: String = str(effect.get("id", ""))
		var key: String = "%s:%s" % [source_id, trigger_id]
		var visit_key: String = "%s:%s" % [key, target.id]
		var seen: Dictionary = chain.get("seen", {})
		if bool(seen.get(visit_key, false)):
			continue
		var instance_key: String = "%s:%s" % [key, actor.id] if bool(effect.get("oncePerDrone", false)) else key
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(key, false)):
			continue
		if bool(effect.get("oncePerDrone", false)) and bool(owner.once_per_combat.get(instance_key, false)):
			continue
		if float(owner.icds.get(instance_key, 0.0)) > float(state.time_ms):
			continue
		var chance: float = clampf(float(effect.get("chance", 1.0)) * proc_weight * float(_effective_sheet(state, owner, target).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(chance):
			continue
		seen[visit_key] = true
		chain["seen"] = seen
		chain["lastAt"] = state.time_ms
		chain["childEvents"] = int(chain.get("childEvents", 0)) + 1
		state.trigger_chains[action_id] = chain
		if bool(effect.get("oncePerCombat", false)):
			owner.once_per_combat[key] = true
		if bool(effect.get("oncePerDrone", false)):
			owner.once_per_combat[instance_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0: owner.icds[instance_key] = float(state.time_ms) + icd_ms
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, trigger_id]
		_emit(state, "TRIGGER", owner.id, {"targetId": target.id, "actionId": trigger_action_id, "skillId": skill_id, "text": "%s: подготовил эффект «%s» к попаданию." % [owner.display_name, trigger_id], "data": {"sourceId": source_id, "chance": chance}})
		var action: Dictionary = effect.get("action", {})
		match str(action.get("kind", "")):
			"spendFlagForDamage":
				var flag: String = str(action.get("flag", ""))
				var flag_amount: float = maxf(0.0, float(owner.flags.get(flag, 0.0)))
				var stacks: int = maxi(0, floori(flag_amount))
				var max_stacks: int = maxi(1, int(action.get("maxStacks", 1)))
				var used: int = mini(stacks, max_stacks)
				var interval: float = float(action.get("intervalMs", 0.0))
				var has_charge: bool = flag == "charge" and flag_amount > 0.0
				if (used <= 0 and not has_charge) or bool(action.get("onlyAtMax", false)) and used < max_stacks or interval > 0.0 and float(state.time_ms) - float(owner.flags.get("%sLastUsedAt" % flag, -interval)) < interval:
					continue
				if flag == "charge":
					var charge_amount: float = flag_amount
					owner.flags[flag] = 0.0
					owner.flags["%sLastUsedAt" % flag] = float(state.time_ms)
					_resolve_basic_hit(state, rng, owner, target, charge_amount, "ENERGY", "%s:charge" % trigger_action_id, false, "", 0.0, false, 0.0)
				else:
					owner.flags[flag] = float(stacks - used)
					owner.flags["%sLastUsedAt" % flag] = float(state.time_ms)
					if flag == "phase":
						for phase_slot: int in range(1, 4): owner.flags.erase("phaseExpiresAt%d" % phase_slot)
					raw *= 1.0 + float(action.get("perStack", 0.0)) * float(used)
			"packetMod":
				var required_shield: float = float(action.get("requireShield", 0.0))
				if owner.shield < required_shield:
					continue
				var consume_shield: float = float(action.get("consumeShield", 0.0))
				if consume_shield > 0.0:
					var spent: float = minf(owner.shield, consume_shield)
					if spent < required_shield:
						continue
					owner.shield -= spent
					_dispatch_effect_shield_spent(state, owner, target, trigger_action_id, spent)
				raw *= float(action.get("damageMultiplier", 1.0))
				if action.has("penMultiplier"):
					for stat: String in ["armorPen", "energyPen", "digitalPen"]: pen[stat] = float(pen.get(stat, 0.0)) * float(action.get("penMultiplier", 1.0))
	packet_mods[packet_key] = {"multiplier": raw / initial_raw if initial_raw > 0.0 else 1.0, "penetration": pen.duplicate(true)}
	chain["packetMods"] = packet_mods
	chain["lastAt"] = state.time_ms
	state.trigger_chains[action_id] = chain
	return {"raw": raw, "penetration": pen}

func _dispatch_effect_shield_spent(state: CombatState, owner: CombatActorState, target: CombatActorState, action_id: String, spent: float) -> void:
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary: continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "ON_EFFECT_SHIELD_SPENT" or str(effect.get("action", {}).get("kind", "")) != "tempShield": continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var trigger_owner: CombatActorState = _trigger_owner(state, source_id)
		if trigger_owner.id != owner.id: continue
		var action: Dictionary = effect.get("action", {})
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var amount: float = spent * float(action.get("ratio", 1.0))
		var cap: float = float(action.get("cap", amount))
		var effect_id: String = str(effect.get("id", ""))
		var shield_source_id: String = "trigger:%s:%s" % [source_id, effect_id]
		var existing: Dictionary = {}
		for pool: Dictionary in owner.temp_shields:
			if str(pool.get("sourceId", "")) == shield_source_id: existing = pool; break
		if existing.is_empty():
			owner.temp_shields.append({"sourceId": shield_source_id, "amount": minf(cap, amount), "cap": cap, "expiresAt": float(state.time_ms) + float(action.get("durationMs", 0.0))})
		else:
			existing["amount"] = minf(cap, float(existing.get("amount", 0.0)) + amount)
			existing["cap"] = cap
			existing["expiresAt"] = float(state.time_ms) + float(action.get("durationMs", 0.0))
		if amount > 0.0:
			_emit(state, "SHIELD_GAIN", owner.id, {"targetId": owner.id, "actionId": action_id, "text": "%s: временный щит +%s." % [owner.display_name, _one_decimal(minf(cap, amount))], "data": {"amount": minf(cap, amount), "durationMs": action.get("durationMs", 0.0)}})

func _dispatch_authored_event(state: CombatState, rng: DeterministicRng, event_name: String, actor: CombatActorState, target: CombatActorState, action_id: String, cause_id: int = 0, damage_type: String = "", skill_id: String = "", direct: bool = true, proc_weight: float = 1.0, amount: float = 0.0) -> void:
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary: continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != event_name or not _supports_authored_event_trigger(effect): continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var source_kind: String = str(trigger_value.get("sourceKind", ""))
		if source_kind == "skill" and str(effect.get("id", "")).begins_with("SK_") and skill_id != source_id: continue
		if source_kind == "skill" and event_name == "ON_HIT": continue
		var owner: CombatActorState = _trigger_owner(state, source_id)
		if not owner.alive: continue
		var global_owner_event: bool = event_name in ["ON_INTERRUPT", "ON_STATUS_EXPIRE", "ON_DRONE_DEATH", "ON_COMBAT_START", "ON_ENEMY_TELEGRAPH"]
		if global_owner_event:
			if owner.kind != "operator": continue
			if event_name == "ON_STATUS_EXPIRE" and (target == null or target.side != "enemy"): continue
		elif event_name == "ON_TAKEN_DAMAGE" or event_name == "ON_DODGE" or event_name == "ON_HP_THRESHOLD":
			if owner.id != actor.id: continue
		elif owner.id != actor.id:
			continue
		if bool(effect.get("requireDirect", false)) and not direct: continue
		if bool(effect.get("requireDrone", false)) and actor.kind != "drone": continue
		var type_filter: Array = effect.get("damageTypeFilter", [])
		if not type_filter.is_empty() and not type_filter.has(damage_type): continue
		var skill_filter: Array = effect.get("skillFilter", [])
		if not skill_filter.is_empty() and not skill_filter.has(skill_id): continue
		if not _trigger_status_condition_passes(state, owner, target, effect.get("condition", {})): continue
		if effect.has("minAmount") and amount < float(effect.get("minAmount", 0.0)): continue
		if effect.has("hpThreshold") and owner.hp / maxf(1.0, float(_effective_sheet(state, owner).get("maxHP", 1.0))) > float(effect.get("hpThreshold", 0.0)): continue
		var trigger_id: String = str(effect.get("id", ""))
		var key: String = "%s:%s" % [source_id, trigger_id]
		var instance_key: String = "%s:%s" % [key, actor.id] if bool(effect.get("oncePerDrone", false)) else key
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(key, false)): continue
		if bool(effect.get("oncePerDrone", false)) and bool(owner.once_per_combat.get(instance_key, false)): continue
		if float(owner.icds.get(instance_key, 0.0)) > float(state.time_ms): continue
		var chance: float = clampf(float(effect.get("chance", 1.0)) * proc_weight * float(_effective_sheet(state, owner, target).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(chance): continue
		if bool(effect.get("oncePerCombat", false)): owner.once_per_combat[key] = true
		if bool(effect.get("oncePerDrone", false)): owner.once_per_combat[instance_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0: owner.icds[instance_key] = float(state.time_ms) + icd_ms
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, trigger_id]
		_emit(state, "TRIGGER", owner.id, {"targetId": target.id if target != null else "", "actionId": trigger_action_id, "skillId": skill_id, "damageType": damage_type, "text": "%s: сработал эффект «%s»." % [owner.display_name, trigger_id], "data": {"sourceId": source_id, "event": event_name, "chance": chance, "amount": amount}})
		_execute_authored_trigger_action(state, rng, owner, target, actor, effect, source_id, trigger_action_id, amount)

func _execute_authored_trigger_action(state: CombatState, rng: DeterministicRng, owner: CombatActorState, target: CombatActorState, actor: CombatActorState, effect: Dictionary, source_id: String, action_id: String, event_amount: float) -> void:
	var action: Dictionary = effect.get("action", {})
	match str(action.get("kind", "")):
		"restoreEnergy": _restore_trigger_energy(state, owner, action, action_id)
		"restoreShield":
			var shield_target: CombatActorState = state.operator if owner.kind == "drone" and owner.drone_role == "medic" else owner
			var maximum: float = float(_effective_sheet(state, shield_target).get("maxShield", 0.0))
			var restored: float = minf(float(action.get("amount", 0.0)), maxf(0.0, maximum - shield_target.shield))
			shield_target.shield += restored
			if restored > 0.0: _emit(state, "SHIELD_GAIN", owner.id, {"targetId": shield_target.id, "actionId": action_id, "text": "%s: +%s щита." % [shield_target.display_name, _one_decimal(restored)], "data": {"amount": restored}})
		"changeHeat":
			var heat_delta: float = float(action.get("amount", 0.0))
			if heat_delta >= 0.0: _gain_basic_heat(state, owner, heat_delta, rng)
			else:
				var previous_heat: float = owner.heat
				owner.heat = maxf(0.0, owner.heat + heat_delta)
				_handle_heat_transition(state, rng, owner, previous_heat, float(owner.base_sheet.get("maxHeat", 0.0)))
		"applyStatus":
			var status_id: String = str(action.get("status", ""))
			var target_mode: String = str(action.get("target", "target"))
			var status_targets: Array[CombatActorState] = []
			if target_mode == "self":
				status_targets.append(owner)
			elif target_mode == "allEnemies":
				for enemy: CombatActorState in state.enemies:
					if enemy.alive: status_targets.append(enemy)
			elif target_mode == "otherEnemy":
				for enemy: CombatActorState in state.enemies:
					if enemy.alive and (target == null or enemy.id != target.id):
						status_targets.append(enemy)
						break
			elif target != null:
				status_targets.append(target)
			for status_target: CombatActorState in status_targets:
				_apply_authored_status(state, owner, status_target, status_id, int(action.get("stacks", 1)), float(action.get("durationMs", -1.0)), event_amount, action_id)
		"control":
			if target != null and target.alive:
				if target.is_boss: _add_simple_status(state, owner, target, "JAM", float(action.get("bossFallbackJamMs", 0.0)))
				elif rng.chance(float(action.get("chance", 0.0))):
					target.no_loot = true
					_add_simple_status(state, owner, target, "CONTROLLED", float(action.get("durationMs", 0.0)))
		"wanted": state.wanted_delta += int(action.get("amount", 0))
		"revealNodes": state.reveal_delta += int(action.get("amount", 0))
		"reduceCooldown":
			var skill_ids: Array[String] = []
			if not str(action.get("skillId", "")).is_empty(): skill_ids.append(str(action.get("skillId", "")))
			else:
				for cooldown_id: Variant in owner.cooldowns.keys(): skill_ids.append(str(cooldown_id))
			skill_ids.sort()
			for cooldown_id: String in skill_ids:
				if float(owner.cooldowns.get(cooldown_id, 0.0)) > float(state.time_ms):
					owner.cooldowns[cooldown_id] = maxf(float(state.time_ms), float(owner.cooldowns[cooldown_id]) - float(action.get("amountMs", 0.0)))
					break
		"extraReaction": owner.flags["extraReactionUntil"] = float(state.time_ms) + float(action.get("windowMs", 0.0))
		"flag": _apply_trigger_flag(state, owner, action)
		"buff": _apply_trigger_buff(state, owner, action, source_id, action_id)
		"tempShield": _apply_trigger_temp_shield(state, owner, action, source_id, action_id, event_amount)
		"consumeShieldForDamage":
			var consumed: float = minf(owner.shield, maxf(1.0 if owner.shield > 0.0 else 0.0, owner.shield * float(action.get("fraction", 0.0))))
			if consumed > 0.0:
				owner.shield -= consumed
				owner.flags["u01EnergyMultiplier"] = minf(float(action.get("maxMultiplier", 2.0)), 1.0 + consumed * 0.01)
				owner.flags["u01ExpiresAt"] = float(state.time_ms) + float(action.get("windowMs", 0.0))
				owner.heat_lockout = false
				_dispatch_effect_shield_spent(state, owner, target, action_id, consumed)
		"secondaryDamage": _apply_authored_secondary_damage(state, rng, owner, target, actor, action, action_id, event_amount)

func _apply_trigger_flag(state: CombatState, owner: CombatActorState, action: Dictionary) -> void:
	var key: String = str(action.get("key", ""))
	if key.is_empty(): return
	if key == "longPulse" and float(state.time_ms - owner.last_main_attack_at) < 1000.0: return
	if key == "phase" and float(action.get("durationMs", 0.0)) > 0.0:
		for slot: int in range(1, int(action.get("max", 3)) + 1):
			var expiry_key: String = "phaseExpiresAt%d" % slot
			if float(owner.flags.get(expiry_key, 0.0)) <= float(state.time_ms):
				owner.flags[expiry_key] = float(state.time_ms) + float(action.get("durationMs", 0.0))
				break
		var active: int = 0
		for slot: int in range(1, int(action.get("max", 3)) + 1):
			if float(owner.flags.get("phaseExpiresAt%d" % slot, 0.0)) > float(state.time_ms): active += 1
		owner.flags["phase"] = active
		return
	var value: float = float(owner.flags.get(key, 0.0)) + float(action.get("amount", 0.0))
	owner.flags[key] = minf(float(action.get("max", value)), value) if action.has("max") else value
	if float(action.get("durationMs", 0.0)) > 0.0: owner.flags["%sExpiresAt" % key] = float(state.time_ms) + float(action.get("durationMs", 0.0))

func _apply_trigger_buff(state: CombatState, owner: CombatActorState, action: Dictionary, source_id: String, action_id: String) -> void:
	var mods: Array[Dictionary] = []
	for index: int in range(action.get("mods", []).size()):
		var source_mod: Dictionary = action["mods"][index]
		mods.append({"id": "%s:%s:%d" % [source_id, str(source_mod.get("stat", "")), index], "sourceId": source_id, "sourceKind": "trigger", "stat": source_mod.get("stat", ""), "op": source_mod.get("op", "FLAT"), "value": source_mod.get("value", 0.0), "condition": source_mod.get("condition", {}), "stackGroup": source_mod.get("stackGroup", "")})
	var trigger_id: String = action_id.get_slice(":trigger:", 1)
	var buff_id: String = str(action.get("flag", "%s:%s" % [source_id, trigger_id]))
	var buff: Dictionary = {}
	for existing: Dictionary in owner.buffs:
		if str(existing.get("id", "")) == buff_id: buff = existing; break
	if buff.is_empty():
		owner.buffs.append({"id": buff_id, "sourceId": source_id, "name": trigger_id, "mods": mods, "expiresAt": float(state.time_ms) + float(action.get("durationMs", 0.0)), "consumeOnHit": bool(action.get("consumeOnHit", false)), "stacks": 1})
	else:
		buff["expiresAt"] = float(state.time_ms) + float(action.get("durationMs", 0.0))
		buff["mods"] = mods
		buff["stacks"] = mini(int(action.get("maxStacks", 2147483647)), int(buff.get("stacks", 1)) + 1)
	_emit(state, "BUFF", owner.id, {"actionId": action_id, "text": "%s: получен временный эффект." % owner.display_name, "data": {"durationMs": action.get("durationMs", 0.0), "consumeOnHit": action.get("consumeOnHit", false)}})

func _apply_trigger_temp_shield(state: CombatState, owner: CombatActorState, action: Dictionary, source_id: String, action_id: String, event_amount: float) -> void:
	var from_flag: String = str(action.get("fromFlag", ""))
	var base: float = event_amount if from_flag == "effectShieldSpent" else float(owner.flags.get(from_flag, 0.0)) if not from_flag.is_empty() else float(action.get("amount", 0.0))
	if not from_flag.is_empty() and from_flag != "effectShieldSpent": base *= float(action.get("ratio", 1.0))
	if bool(action.get("scaleWithArmorT", false)):
		var armor: Variant = state.build.get("equipment", {}).get("ARMOR")
		base *= _formula.d_depth(float(armor.tech_level if armor is ItemInstance else 1))
	var cap: float = float(action.get("cap", base))
	var trigger_id: String = action_id.get_slice(":trigger:", 1)
	var shield_source: String = "trigger:%s:%s" % [source_id, trigger_id]
	var pool: Dictionary = {}
	for existing: Dictionary in owner.temp_shields:
		if str(existing.get("sourceId", "")) == shield_source: pool = existing; break
	var shield: float = minf(cap, maxf(0.0, base))
	if pool.is_empty(): owner.temp_shields.append({"sourceId": shield_source, "amount": shield, "cap": cap, "expiresAt": float(state.time_ms) + float(action.get("durationMs", 0.0))})
	else:
		pool["amount"] = minf(cap, float(pool.get("amount", 0.0)) + shield)
		pool["cap"] = cap
		pool["expiresAt"] = float(state.time_ms) + float(action.get("durationMs", 0.0))
	if from_flag == "effectShieldSpent": owner.flags["effectShieldSpent"] = 0.0
	if shield > 0.0: _emit(state, "SHIELD_GAIN", owner.id, {"targetId": owner.id, "actionId": action_id, "text": "%s: временный щит +%s." % [owner.display_name, _one_decimal(shield)], "data": {"amount": shield, "cap": cap, "durationMs": action.get("durationMs", 0.0)}})

func _apply_authored_secondary_damage(state: CombatState, rng: DeterministicRng, owner: CombatActorState, target: CombatActorState, actor: CombatActorState, action: Dictionary, action_id: String, event_amount: float) -> void:
	var basis: float = float(_effective_sheet(state, owner).get("techPower", 0.0))
	match str(action.get("basis", "techPower")):
		"mainWeapon": basis = float(state.build.get("mainWeapon", {}).get("damage", 0.0))
		"droneTech": basis = target.attack_damage if target != null and target.kind == "drone" else actor.attack_damage if actor.kind == "drone" else float(state.drones[0].attack_damage) if not state.drones.is_empty() else 0.0
		"flat": basis = 1.0
		"consumedShield": basis = event_amount
		"virusRemaining": basis = float(_status_stacks(target, "VIRUS")) if target != null else 0.0
	var raw: float = basis * float(action.get("coefficient", 0.0))
	var targets: Array[CombatActorState] = []
	match str(action.get("targeting", "target")):
		"target":
			if target != null and target.alive: targets.append(target)
		"attacker":
			if target != null and target.alive and target.side == "enemy": targets.append(target)
			elif actor.side == "enemy" and actor.alive: targets.append(actor)
		"otherEnemy":
			for enemy: CombatActorState in state.enemies:
				if enemy.alive and (target == null or enemy.id != target.id): targets.append(enemy); break
		"allEnemies":
			for enemy: CombatActorState in state.enemies:
				if enemy.alive: targets.append(enemy)
	var limit: int = maxi(0, int(action.get("maxTargets", targets.size())))
	for index: int in range(mini(targets.size(), limit)):
		_resolve_basic_hit(state, rng, owner, targets[index], raw, str(action.get("damageType", "DIGITAL")), "%s:child:%d" % [action_id, index + 1], false, "", 0.0, false, 0.0)

func _supports_kill_trigger(effect: Dictionary) -> bool:
	var action: Dictionary = effect.get("action", {})
	var condition: Dictionary = effect.get("condition", {})
	if not condition.is_empty() and str(condition.get("kind", "")) not in ["targetStatus", "targetNoStatus", "heatAtLeast", "hpBelow"]:
		return false
	match str(action.get("kind", "")):
		"restoreEnergy": return float(action.get("amount", 0.0)) > 0.0
		"changeHeat": return true
		"transferVirus": return int(action.get("stacks", 0)) > 0
		"secondaryDamage": return float(action.get("coefficient", 0.0)) > 0.0 and str(action.get("targeting", "")) in ["target", "otherEnemy", "allEnemies"] and str(action.get("damageType", "ENERGY")) in ["KINETIC", "ENERGY", "DIGITAL"]
		_: return false

func _supports_direct_hit_trigger(effect: Dictionary) -> bool:
	var action: Dictionary = effect.get("action", {})
	var condition: Dictionary = effect.get("condition", {})
	if not condition.is_empty() and str(condition.get("kind", "")) not in ["targetStatus", "targetNoStatus", "heatAtLeast", "hpBelow"]:
		return false
	match str(action.get("kind", "")):
		"applyStatus": return STEP_STATUS_IDS.has(str(action.get("status", ""))) and str(action.get("target", "target")) in ["target", "self", "otherEnemy", "allEnemies"]
		"restoreEnergy", "restoreShield": return float(action.get("amount", 0.0)) > 0.0
		"extendStatus": return STEP_STATUS_IDS.has(str(action.get("status", ""))) and float(action.get("ms", 0.0)) > 0.0
		"secondaryDamage": return float(action.get("coefficient", 0.0)) > 0.0 and str(action.get("targeting", "")) in ["target", "otherEnemy", "allEnemies"] and str(action.get("damageType", "ENERGY")) in ["KINETIC", "ENERGY", "DIGITAL"]
		_: return false

func _trigger_owner(state: CombatState, source_id: String) -> CombatActorState:
	for drone: CombatActorState in state.drones:
		if drone.drone_item_id == source_id:
			return drone
	return state.operator

func _run_periodic_drone_triggers(state: CombatState, rng: DeterministicRng) -> void:
	for trigger_value: Dictionary in state.build.get("triggerEffects", []):
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "PERIODIC" or not _supports_periodic_trigger(effect):
			continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var owner: CombatActorState = _trigger_owner(state, source_id)
		var effect_id: String = str(effect.get("id", ""))
		var schedule_key: String = "periodic:%s" % effect_id
		var period_ms: float = float(effect.get("periodMs", 0.0))
		if not owner.alive or period_ms <= 0.0 or float(owner.ability_next.get(schedule_key, period_ms)) > float(state.time_ms):
			continue
		owner.ability_next[schedule_key] = float(owner.ability_next.get(schedule_key, period_ms)) + period_ms
		var trigger_key: String = "%s:%s" % [source_id, effect_id]
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(trigger_key, false)): continue
		if float(owner.icds.get(trigger_key, 0.0)) > float(state.time_ms): continue
		var proc_chance: float = clampf(float(effect.get("chance", 1.0)) * float(_effective_sheet(state, owner).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(proc_chance): continue
		if bool(effect.get("oncePerCombat", false)): owner.once_per_combat[trigger_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0: owner.icds[trigger_key] = float(state.time_ms) + icd_ms
		var action_id: String = "%s:periodic:%s:%d" % [owner.id, effect_id, int(owner.counters.get(effect_id, 0)) + 1]
		owner.counters[effect_id] = int(owner.counters.get(effect_id, 0)) + 1
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_event: Dictionary = _emit(state, "TRIGGER", owner.id, {"actionId": action_id, "text": "%s: периодический триггер %s." % [owner.display_name, effect_id], "data": {"periodMs": period_ms}})
		var action: Dictionary = effect.get("action", {})
		match str(action.get("kind", "")):
			"flag": _apply_trigger_flag(state, owner, action)
			"restoreShield":
				var shield_target: CombatActorState = state.operator if owner.kind == "drone" and owner.drone_role == "medic" else owner
				var max_shield: float = float(_effective_sheet(state, shield_target).get("maxShield", 0.0))
				var restored: float = minf(float(action.get("amount", 0.0)), maxf(0.0, max_shield - shield_target.shield))
				shield_target.shield += restored
				if restored > 0.0: _emit(state, "SHIELD_GAIN", owner.id, {"targetId": shield_target.id, "actionId": action_id, "causeId": int(trigger_event.get("eventId", 0)), "text": "%s: +%s щита." % [shield_target.display_name, _one_decimal(restored)], "data": {"amount": restored, "source": effect_id}})
			"interrupt":
				var interrupt_target: CombatActorState = null
				for enemy: CombatActorState in state.enemies:
					if enemy.alive and enemy.cast is Dictionary and bool(enemy.cast.get("interruptible", false)):
						interrupt_target = enemy
						break
				if interrupt_target != null:
					if owner.kind == "drone" and owner.drone_role == "emp" and owner.reaction_cast == null and not _equipped_skill(state, "SK_DRONE_EMP").is_empty():
						_try_start_drone_skill(state, owner)
					else:
						interrupt_target.cast = null
						state.metrics["interrupts"] = int(state.metrics.get("interrupts", 0)) + 1
						var interrupted: Dictionary = _emit(state, "CAST_INTERRUPT", owner.id, {"targetId": interrupt_target.id, "actionId": action_id, "text": "%s: каст прерван." % interrupt_target.display_name})
						_dispatch_authored_event(state, rng, "ON_INTERRUPT", state.operator, interrupt_target, action_id, int(interrupted.get("eventId", 0)), "", "", true, 1.0)
			"secondaryDamage":
				var damage_targets: Array[CombatActorState] = []
				if str(action.get("targeting", "nearest")) == "allEnemies":
					for enemy: CombatActorState in state.enemies:
						if enemy.alive: damage_targets.append(enemy)
					damage_targets.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
				else:
					var selected: CombatActorState = _pick_auto_target(state, owner)
					if selected != null: damage_targets.append(selected)
				if damage_targets.is_empty(): continue
				var tech_level: int = _trigger_item_tech_level(state, source_id)
				var raw: float = float(action.get("coefficient", 0.0))
				if str(action.get("basis", "")) == "flat": raw *= _formula.h_depth(float(tech_level))
				for target: CombatActorState in damage_targets:
					var target_raw: float = raw
					if str(action.get("basis", "")) == "techPower": target_raw *= float(_effective_sheet(state, owner, target).get("techPower", 0.0))
					var hit: Dictionary = _resolve_basic_hit(state, rng, owner, target, target_raw, str(action.get("damageType", "ENERGY")), action_id, false, "", 0.0, false, 0.0)
					if not bool(hit.get("ok", false)): push_error("CombatSimulator: periodic hit failed: %s" % str(hit.get("error", "unknown error")))
			"repeatLastDigital": _repeat_last_digital(state, rng, owner, action_id, action)

func _trigger_item_tech_level(state: CombatState, source_id: String) -> int:
	for item_value: Variant in state.build.get("equipment", {}).values():
		if item_value is ItemInstance and item_value.item_id == source_id:
			return maxi(1, item_value.tech_level)
	return 1

func _repeat_last_digital(state: CombatState, rng: DeterministicRng, actor: CombatActorState, action_id: String, action: Dictionary) -> void:
	var skill_id: String = str(actor.flags.get("lastDigitalSkillId", ""))
	var skill: Dictionary = _equipped_skill(state, skill_id)
	var target: CombatActorState = _actor_by_id(state, str(actor.flags.get("lastDigitalTargetId", "")))
	if skill.is_empty() or target == null or not target.alive or str(skill.get("basis", "")) != "TECH_D": return
	var effective: Dictionary = _effective_sheet(state, actor, target)
	var raw: float = _skill_raw_damage(skill, float(effective.get("techPower", 0.0)), effective, target) * float(action.get("coefficient", 0.0))
	var hit: Dictionary = _resolve_basic_hit(state, rng, actor, target, raw, "DIGITAL", action_id, false, skill_id, 0.0, false, 0.0)
	if not bool(hit.get("ok", false)): push_error("CombatSimulator: repeatLastDigital failed: %s" % str(hit.get("error", "unknown error")))

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
		if str(skill.get("channel", "main")) != "main":
			_record_rule_failure(state, rule_id, "wrong_channel")
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
		_start_main_skill(state, actor, skill, target, _rng)
		return {"started": true}
	return {"started": false}

func _main_skill_energy_cost(skill: Dictionary, sheet: Dictionary) -> float:
	return _factory.main_skill_energy_cost(skill, sheet)

func _choose_reaction_skill(state: CombatState, rng: DeterministicRng) -> void:
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
		var extra_reaction: bool = float(actor.flags.get("extraReactionUntil", 0.0)) >= float(state.time_ms)
		if skill.is_empty():
			_record_rule_failure(state, rule_id, "not_equipped")
			continue
		if float(actor.cooldowns.get(skill_id, 0.0)) > float(state.time_ms) and not extra_reaction:
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
		_start_reaction_skill(state, actor, skill, target, cost, sheet, rng)
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

func _start_reaction_skill(state: CombatState, actor: CombatActorState, skill: Dictionary, target: CombatActorState, cost: float, sheet: Dictionary, rng: DeterministicRng) -> void:
	var skill_id: String = str(skill.get("id", ""))
	var extra_reaction: bool = float(actor.flags.get("extraReactionUntil", 0.0)) >= float(state.time_ms)
	if extra_reaction: actor.flags["extraReactionUntil"] = 0.0
	actor.energy = clampf(actor.energy - cost, 0.0, float(sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	var heat_delta: float = float(skill.get("heatDelta", 0.0))
	if skill_id == "SK_VENT":
		var previous_heat: float = actor.heat
		actor.heat = maxf(0.0, actor.heat - 35.0)
		_handle_heat_transition(state, rng, actor, previous_heat, float(actor.base_sheet.get("maxHeat", 0.0)))
	else:
		_gain_basic_heat(state, actor, heat_delta, rng)
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
		"data": {"channel": "reaction", "windupMs": skill.get("windupMs", 0), "recoveryMs": skill.get("recoveryMs", 0), "cooldownMs": cooldown, "emergency": false, "extraReaction": extra_reaction},
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
		_consume_hit_buffs(actor)
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
			var interrupted: Dictionary = _emit(state, "CAST_INTERRUPT", drone.id, {"targetId": target.id, "actionId": action_id, "text": "%s: каст прерван." % target.display_name})
			_dispatch_authored_event(state, rng, "ON_INTERRUPT", state.operator, target, action_id, int(interrupted.get("eventId", 0)), "", skill_id, true, float(skill.get("procWeight", 1.0)))
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
	var cast_event: Dictionary = _emit(state, "REACTION", actor.id, {"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": cast.get("actionId", ""), "text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))], "data": {"channel": "reaction"}})
	_dispatch_authored_event(state, rng, "ON_CAST", actor, target, str(cast.get("actionId", "")), int(cast_event.get("eventId", 0)), "", skill_id, true, float(skill.get("procWeight", 1.0)))
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
				var interrupted: Dictionary = _emit(state, "CAST_INTERRUPT", actor.id, {"targetId": target.id, "actionId": cast.get("actionId", ""), "text": "%s: каст прерван." % target.display_name})
				_dispatch_authored_event(state, rng, "ON_INTERRUPT", state.operator, target, str(cast.get("actionId", "")), int(interrupted.get("eventId", 0)), "", skill_id, true, float(skill.get("procWeight", 1.0)))
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

func _apply_authored_status(state: CombatState, source: CombatActorState, target: CombatActorState, status_id: String, stacks: int, authored_duration: float, raw_snapshot: float, action_id: String) -> void:
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not target.alive or not _status_catalog_error.is_empty(): return
	var definition: Dictionary = _status_catalog.get_definition(status_id)
	if definition.is_empty(): return
	var source_sheet: Dictionary = _effective_sheet(state, source, target)
	var duration: float = authored_duration if authored_duration >= 0.0 else float(definition.get("durationMs", 0.0))
	if float(definition.get("tickMs", 0.0)) > 0.0:
		var duration_bonus: float = float(source_sheet.get("dotDuration", 0.0))
		if status_id == "VIRUS": duration_bonus += float(source_sheet.get("virusDuration", 0.0))
		duration *= 1.0 + duration_bonus / 100.0
	if status_id == "STUN":
		if float(target.icds.get("STUN", 0.0)) > float(state.time_ms): return
		target.icds["STUN"] = float(state.time_ms) + 3000.0
		if target.is_boss: duration *= 0.5
	var snapshot: float = 0.0
	match str(definition.get("snapshotFrom", "none")):
		"rawDamage": snapshot = raw_snapshot * (1.0 + (float(source_sheet.get("statusDamage", 0.0)) + (float(source_sheet.get("bleedDamage", 0.0)) if status_id == "BLEED" else 0.0)) / 100.0)
		"techPower": snapshot = float(source_sheet.get("techPower", 0.0)) * (1.0 + float(source_sheet.get("statusDamage", 0.0)) / 100.0) * (1.0 + float(source_sheet.get("virusDamage", 0.0)) / 100.0)
	var maximum: int = int(definition.get("maxStacks", 1))
	if status_id == "BLEED": maximum += floori(float(source_sheet.get("bleedStackCap", 0.0)))
	if status_id == "VIRUS": maximum += floori(float(source_sheet.get("virusStackCap", 0.0)))
	var entries: Array = target.statuses.get(status_id, [])
	var add_count: int = maxi(1, stacks)
	if bool(definition.get("independentStacks", false)):
		for _index: int in range(add_count):
			if entries.size() >= maximum: entries.pop_front()
			entries.append({"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration, "nextTickAt": float(state.time_ms) + (float(definition.get("tickMs", 0.0)) if float(definition.get("tickMs", 0.0)) > 0.0 else duration), "snapshot": snapshot, "stacks": 1})
	else:
		if entries.is_empty():
			entries.append({"sourceId": "%s:%s" % [source.id, status_id], "sourceActorId": source.id, "expiresAt": float(state.time_ms) + duration, "nextTickAt": float(state.time_ms) + (float(definition.get("tickMs", 0.0)) if float(definition.get("tickMs", 0.0)) > 0.0 else duration), "snapshot": snapshot, "stacks": mini(add_count, maximum)})
		else:
			entries[0]["stacks"] = clampi(int(entries[0].get("stacks", 1)) + add_count, 1, maximum)
			entries[0]["expiresAt"] = float(state.time_ms) + duration
			entries[0]["sourceActorId"] = source.id
			if float(definition.get("tickMs", 0.0)) > 0.0:
				entries[0]["snapshot"] = snapshot
	target.statuses[status_id] = entries
	_emit(state, "STATUS_APPLY", source.id, {"targetId": target.id, "statusId": status_id, "actionId": action_id, "text": "%s: %s." % [target.display_name, str(definition.get("name", status_id))], "data": {"stacks": _status_stack_count(entries), "snapshot": snapshot, "durationMs": duration}})

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
	if kind in ["hpBelow", "hpAbove", "shieldBelow"] and value > 1.0:
		value = clampf(value / 100.0, 0.0, 1.0) # Legacy save compatibility: old thresholds were stored as whole percentages.
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
			if target != null:
				return target.cast is Dictionary and (not bool(condition.get("interruptibleOnly", false)) or bool(target.cast.get("interruptible", false)))
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
	if mode == "healer":
		for enemy: CombatActorState in enemies:
			if enemy.is_healer:
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

func _start_main_skill(state: CombatState, actor: CombatActorState, skill: Dictionary, target: CombatActorState, rng: DeterministicRng) -> void:
	var skill_id: String = str(skill.get("id", ""))
	var cost: float = _main_skill_energy_cost(skill, _effective_sheet(state, actor))
	actor.energy = clampf(actor.energy - cost, 0.0, float(actor.base_sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	_gain_basic_heat(state, actor, float(skill.get("heatDelta", 0.0)), rng)
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
		_consume_hit_buffs(actor)
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
		if kind not in ["heavyAttack", "shieldBypass", "heal", "heat", "shieldRestore", "mark", "escape", "wantedBoost", "protectAlly", "summon"] and not scheduled_status:
			continue
		if float(actor.ability_next.get(str(ability.get("id", "")), 999999999.0)) <= float(state.time_ms):
			ready.append(ability)
	ready.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_at: float = float(actor.ability_next.get(str(left.get("id", "")), 0.0))
		var right_at: float = float(actor.ability_next.get(str(right.get("id", "")), 0.0))
		return left_at < right_at if not is_equal_approx(left_at, right_at) else str(left.get("id", "")) < str(right.get("id", "")))
	return ready[0] if not ready.is_empty() else {}

func _start_enemy_ability(state: CombatState, rng: DeterministicRng, actor: CombatActorState, ability: Dictionary) -> void:
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
		var telegraph: Dictionary = _emit(state, "TELEGRAPH", actor.id, {"targetId": actor.cast["targetId"], "actionId": action_id, "text": "%s: %s" % [actor.display_name, str(ability.get("desc", ability_id))], "data": {"abilityId": ability_id, "dangerTag": ability.get("kind", ""), "windupMs": windup}})
		_dispatch_authored_event(state, rng, "ON_ENEMY_TELEGRAPH", state.operator, actor, action_id, int(telegraph.get("eventId", 0)), "", "", false, 1.0)

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
				_gain_basic_heat(state, target, amount, rng)
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
		"summon":
			var summon_count: int = maxi(1, int(ability.get("summonCount", 1)))
			for _summon_index: int in range(summon_count):
				_spawn_summoned_enemy(state, actor, str(ability.get("summonId", "")))
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
	var skill_use_fields: Dictionary = {
		"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": action_id,
		"originActionId": action_id, "text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))],
		"data": {"channel": "main"},
	}
	if state.combat_rules_version == CombatState.V2_RULES_VERSION:
		skill_use_fields["sourceId"] = skill_id
		skill_use_fields["causeId"] = int(cast.get("causeId", 0))
		skill_use_fields["targetIds"] = cast.get("targetIds", [target.id] if target != null else []).duplicate()
	var cast_event: Dictionary = _emit(state, "SKILL_USE", actor.id, skill_use_fields)
	if skill.get("tags", []).has("D") and target != null and target.side == "enemy":
		actor.flags["lastDigitalSkillId"] = skill_id
		actor.flags["lastDigitalTargetId"] = target.id
	_dispatch_authored_event(state, rng, "ON_CAST", actor, target, action_id, int(cast_event.get("eventId", 0)), "", skill_id, true, float(skill.get("procWeight", 1.0)))
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
		if state.combat_rules_version == CombatState.V2_RULES_VERSION and cast.get("targetIds", []) is Array:
			for target_id: Variant in cast.get("targetIds", []):
				var captured: CombatActorState = _actor_by_id(state, str(target_id))
				if captured != null and captured.alive: targets.append(captured)
		else:
			for enemy: CombatActorState in state.enemies:
				if enemy.alive: targets.append(enemy)
			targets.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
		var limit: int = int(skill.get("maxTargets", targets.size()))
		for current_target: CombatActorState in targets.slice(0, limit):
			var raw_base: float = _skill_raw_damage(skill, base_damage, effective, current_target)
			var hit: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, raw_base, damage_type, action_id, is_main, skill_id, 0.0, true, float(skill.get("procWeight", 1.0)))
			if not bool(hit.get("ok", false)):
				return
		return
	if target == null or not target.alive:
		target = _pick_auto_target(state, actor)
	if target == null:
		return
	if skill_id == "SK_ARC":
		var primary_raw: float = _skill_raw_damage(skill, base_damage, effective, target)
		var primary_hit: Dictionary = _resolve_basic_hit(state, rng, actor, target, primary_raw, damage_type, action_id, is_main, skill_id, 0.0, true, float(skill.get("procWeight", 1.0)))
		if not bool(primary_hit.get("ok", false)):
			return
		var arc_others: Array[CombatActorState] = []
		for enemy: CombatActorState in state.enemies:
			if enemy.alive and enemy.id != target.id:
				arc_others.append(enemy)
		arc_others.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
		for secondary: CombatActorState in arc_others.slice(0, 2):
			var splash_raw: float = _skill_raw_damage(skill, base_damage, effective, secondary) * float(skill.get("splash", {}).get("coefficient", 0.5))
			var splash_hit: Dictionary = _resolve_basic_hit(state, rng, actor, secondary, splash_raw, damage_type, action_id, is_main, skill_id, 0.0, false, float(skill.get("procWeight", 1.0)))
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
		var hit: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, raw_base, damage_type, action_id, is_main, skill_id, 0.0, true, float(skill.get("procWeight", 1.0)))
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
	_resolve_basic_hit(state, rng, actor, target, raw, "DIGITAL", action_id, false, str(skill.get("id", "SK_DETONATE")), 0.0, false)

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
	var tick_event: Dictionary = _emit(state, "DOT_TICK", source_id, {
		"targetId": target.id, "actionId": "dot:%s:%s:%d" % [status_id, target.id, state.time_ms],
		"statusId": status_id, "damageType": damage_type,
		"amountBeforeDefense": raw, "amountAfterDefense": incoming,
		"shieldConsumed": partition["shieldConsumed"], "hpLost": partition["hpLost"],
		"text": "%s → %s: %s %s." % [status_name, target.display_name, _one_decimal(incoming), damage_type],
	})
	target.last_hit_by_id = source_id
	target.last_hit_target_id = target.id
	target.last_hit_action_id = str(tick_event.get("actionId", ""))
	target.last_hit_origin_action_id = str(tick_event.get("actionId", ""))
	target.last_hit_cause_id = int(tick_event.get("eventId", 0))
	target.last_hit_damage_type = damage_type
	target.last_hit_direct = false
	target.last_hit_can_proc = true
	target.last_hit_proc_weight = 1.0
	target.last_hit_event_source = "STATUS_TICK"

func _expire_dot_statuses(state: CombatState, rng: DeterministicRng) -> void:
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
				var expire_action_id: String = "%s:status-expire:%s:%d" % [actor.id, status_id, state.time_ms]
				var expired_event: Dictionary = _emit(state, "STATUS_EXPIRE", actor.id, {
					"statusId": status_id,
					"actionId": expire_action_id,
					"text": "%s: %s истёк." % [actor.display_name, str(_status_catalog.get_definition(status_id).get("name", status_id))],
				})
				_dispatch_authored_event(state, rng, "ON_STATUS_EXPIRE", state.operator, actor, expire_action_id, int(expired_event.get("eventId", 0)), "", "", false, 1.0)
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
	var modifiers: Array[Dictionary] = actor.base_mods.duplicate()
	for buff: Dictionary in actor.buffs:
		if float(buff.get("expiresAt", 0.0)) > float(state.time_ms):
			for modifier: Variant in buff.get("mods", []):
				if modifier is Dictionary:
					modifiers.append(modifier)
	for modifier: Dictionary in modifiers:
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
		var resolved: Dictionary = _stats.resolve_stats(_stats.bundle(modifiers), context)
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

func _apply_basic_continuous(state: CombatState, rng: DeterministicRng) -> void:
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
		var heat_before: float = operator.heat
		if state.combat_rules_version == CombatState.V2_RULES_VERSION and (operator.heat_lockout or state.time_ms - int(operator.flags.get("v2LastHeatGainAt", -100000)) < 500):
			cooling = 0.0
		operator.heat = clampf(operator.heat + (ambient - cooling) * 0.1, 0.0, float(sheet.get("maxHeat", 0.0)))
		_handle_heat_transition(state, rng, operator, heat_before, float(sheet.get("maxHeat", 0.0)))
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
	if state.combat_rules_version == CombatState.V2_RULES_VERSION and actor.kind == "operator":
		enemies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.threat_units > right.threat_units if left.threat_units != right.threat_units else left.id < right.id)
	if actor.kind == "drone" and actor.drone_role == "mark":
		for enemy: CombatActorState in enemies:
			if _has_status(enemy, "DRONE_MARK"):
				return enemy
	return enemies[0] if not enemies.is_empty() else null

func _resolve_basic_attack(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, context: Dictionary = {}) -> Dictionary:
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
		_gain_basic_heat(state, actor, heat_gain, rng)
	actor.counters["attacks"] = int(actor.counters.get("attacks", 0)) + 1
	var action_id: String = "%s:atk:%d" % [actor.id, int(actor.counters["attacks"])]
	if not context.is_empty():
		action_id = str(context.get("instanceId", action_id))
	actor.last_main_attack_at = state.time_ms
	var attack_fields: Dictionary = {"targetId": target.id, "actionId": action_id, "text": "%s атакует %s." % [actor.display_name, target.display_name]}
	if not context.is_empty():
		attack_fields["sourceId"] = str(context.get("action", {}).get("sourceId", ""))
		attack_fields["causeId"] = int(context.get("prepareEventId", 0))
	_emit(state, "ATTACK", actor.id, attack_fields)
	actor.last_target_id = target.id
	var packets: Array[Dictionary] = _attack_packets(actor, weapon)
	var locked_target: CombatActorState = target
	var landed: bool = false
	for packet: Dictionary in packets:
		var current_target: CombatActorState = locked_target if state.combat_rules_version == CombatState.V2_RULES_VERSION else _pick_auto_target(state, actor)
		if current_target == null:
			break
		var hit_result: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, float(packet["amount"]), str(packet["type"]), action_id, actor.kind == "operator")
		if not bool(hit_result.get("ok", false)):
			return hit_result
		landed = landed or bool(hit_result.get("hit", false))
	if actor.kind == "operator":
		actor.flags["firstAttack"] = 0.0
	_consume_hit_buffs(actor)
	if landed:
		_dispatch_attack_counter_triggers(state, rng, actor, target, action_id)
	return {"ok": true, "error": ""}

func _consume_hit_buffs(actor: CombatActorState) -> void:
	if float(actor.flags.get("consumeHitBuffs", 0.0)) <= 0.0:
		return
	actor.buffs = actor.buffs.filter(func(buff: Dictionary) -> bool: return not bool(buff.get("consumeOnHit", false)))
	actor.flags.erase("consumeHitBuffs")

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
		var source_kind: String = str(trigger_value.get("sourceKind", ""))
		var trigger_source_id: String = str(trigger_value.get("sourceId", ""))
		var is_item_trigger: bool = source_kind == "item" and trigger_source_id == source_item_id
		var is_tree_trigger: bool = source_kind == "tree" and actor.kind == "operator"
		if str(effect.get("event", "")) != "ON_ATTACK_COUNTER" or (not is_item_trigger and not is_tree_trigger):
			continue
		var every: int = int(effect.get("counterEvery", 0))
		var attack_count: int = int(actor.counters.get("attacks", 0))
		if is_tree_trigger:
			var target_key: String = "attackCounterTarget:%s:%s" % [trigger_source_id, effect_id]
			var count_key: String = "attackCounterCount:%s:%s" % [trigger_source_id, effect_id]
			var previous_target_id: String = str(actor.flags.get(target_key, ""))
			attack_count = int(actor.flags.get(count_key, 0)) + 1 if previous_target_id == target.id else 1
			actor.flags[target_key] = target.id
			actor.flags[count_key] = float(attack_count)
		if every <= 0 or attack_count <= 0 or attack_count % every != 0:
			continue
		if bool(effect.get("requireDrone", false)) and actor.kind != "drone": continue
		var action: Dictionary = effect.get("action", {})
		var trigger_owner: CombatActorState = actor if is_tree_trigger else _trigger_owner(state, source_item_id)
		var trigger_key: String = "%s:%s" % [trigger_source_id, effect_id]
		if bool(effect.get("oncePerCombat", false)) and bool(trigger_owner.once_per_combat.get(trigger_key, false)): continue
		if float(trigger_owner.icds.get(trigger_key, 0.0)) > float(state.time_ms): continue
		if not _trigger_status_condition_passes(state, trigger_owner, target, effect.get("condition", {})): continue
		var proc_chance: float = clampf(float(effect.get("chance", 1.0)) * float(_effective_sheet(state, trigger_owner, target).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(proc_chance): continue
		if bool(effect.get("oncePerCombat", false)): trigger_owner.once_per_combat[trigger_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0: trigger_owner.icds[trigger_key] = float(state.time_ms) + icd_ms
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, effect_id]
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		_emit(state, "TRIGGER", actor.id, {"targetId": target.id if target.alive else null, "actionId": trigger_action_id, "text": "%s: сработал триггер %s." % [actor.display_name, effect_id], "data": {"attackCounter": attack_count, "counterEvery": every}})
		match str(action.get("kind", "")):
			"applyStatus":
				var status_targets: Array[CombatActorState] = []
				var target_mode: String = str(action.get("target", "target"))
				if target_mode == "self": status_targets.append(trigger_owner)
				elif target_mode == "allEnemies":
					for enemy: CombatActorState in state.enemies:
						if enemy.alive: status_targets.append(enemy)
				elif target_mode == "otherEnemy":
					var other: CombatActorState = _counter_secondary_target(state, target.id)
					if other != null: status_targets.append(other)
				elif target.alive: status_targets.append(target)
				for status_target: CombatActorState in status_targets:
					_apply_authored_status(state, trigger_owner, status_target, str(action.get("status", "")), int(action.get("stacks", 1)), float(action.get("durationMs", -1.0)), 0.0, trigger_action_id)
			"secondaryDamage":
				var damage_targets: Array[CombatActorState] = []
				var targeting: String = str(action.get("targeting", "target"))
				if targeting == "allEnemies":
					for enemy: CombatActorState in state.enemies:
						if enemy.alive: damage_targets.append(enemy)
					damage_targets.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
				elif targeting in ["secondary", "otherEnemy"]:
					var other: CombatActorState = _counter_secondary_target(state, target.id)
					if other != null: damage_targets.append(other)
				elif target.alive: damage_targets.append(target)
				if damage_targets.is_empty(): continue
				var basis: float = float(_effective_sheet(state, trigger_owner).get("techPower", 0.0))
				if str(action.get("basis", "")) == "mainWeapon": basis = float(state.build.get("mainWeapon", {}).get("damage", 0.0))
				elif str(action.get("basis", "")) == "flat": basis = 1.0
				var raw: float = basis * float(action.get("coefficient", 0.0))
				for damage_target: CombatActorState in damage_targets:
					_resolve_basic_hit(state, rng, actor, damage_target, raw, str(action.get("damageType", "ENERGY")), trigger_action_id, false, "", 0.0, false, 0.0)
			"buff": _apply_trigger_buff(state, trigger_owner, action, trigger_source_id, trigger_action_id)

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

func _resolve_basic_hit(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, raw_base: float, damage_type: String, action_id: String, is_main: bool, skill_id: String = "", bypass_shield_ratio: float = 0.0, direct: bool = true, proc_weight: float = 1.0) -> Dictionary:
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
		if target.kind == "operator":
			_dispatch_authored_event(state, rng, "ON_DODGE", target, actor, action_id, int(state.next_event_id - 1), damage_type, skill_id, direct, 1.0)
		return {"ok": true, "hit": false, "error": ""}
	if direct and actor.buffs.any(func(buff: Dictionary) -> bool: return bool(buff.get("consumeOnHit", false))):
		actor.flags["consumeHitBuffs"] = 1.0
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
	var before_hit: Dictionary = _dispatch_before_hit_triggers(state, rng, actor, target, action_id, skill_id, damage_type, raw, is_main, direct, proc_weight, penetration)
	raw = float(before_hit.get("raw", raw))
	penetration = before_hit.get("penetration", penetration)
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
	var hp_before: float = target.hp
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
	var emitted_damage: Dictionary = _emit(state, "DAMAGE", actor.id, damage_event)
	_dispatch_authored_event(state, rng, "ON_TAKEN_DAMAGE", target, actor, action_id, int(emitted_damage.get("eventId", 0)), damage_type, skill_id, direct, 1.0, incoming)
	if target.kind == "operator":
		var max_hp: float = maxf(1.0, float(defender.get("maxHP", 1.0)))
		var crossed_threshold: bool = false
		for trigger_value: Variant in state.build.get("triggerEffects", []):
			if not trigger_value is Dictionary: continue
			var candidate_effect: Dictionary = trigger_value.get("effect", {})
			if str(candidate_effect.get("event", "")) != "ON_HP_THRESHOLD" or not candidate_effect.has("hpThreshold"): continue
			var threshold: float = float(candidate_effect.get("hpThreshold", 0.0))
			if hp_before / max_hp > threshold and target.hp / max_hp <= threshold:
				crossed_threshold = true
				break
		if crossed_threshold:
			_dispatch_authored_event(state, rng, "ON_HP_THRESHOLD", target, actor, action_id, int(emitted_damage.get("eventId", 0)), damage_type, skill_id, direct, proc_weight, float(partition["hpLost"]))
	target.last_hit_by_id = actor.id
	target.last_hit_target_id = target.id
	target.last_hit_action_id = action_id
	target.last_hit_origin_action_id = action_id
	target.last_hit_cause_id = int(emitted_damage.get("eventId", 0))
	target.last_hit_damage_type = damage_type
	target.last_hit_direct = direct
	target.last_hit_can_proc = true
	target.last_hit_proc_weight = proc_weight
	target.last_hit_event_source = "DIRECT" if direct else "SECONDARY"
	_dispatch_direct_status_triggers(state, rng, actor, target, damage_type, action_id, skill_id, direct, proc_weight)
	if float(partition["shieldConsumed"]) > 0.0:
		_dispatch_shield_absorb_triggers(state, rng, actor, target, damage_type, action_id, direct, float(partition["shieldConsumed"]))
	if actor.side == "enemy" and target.side == "player":
		_resolve_enemy_direct_hit_effects(state, actor, target, action_id, raw)
	if bulwark != null and redirected_raw > 0.0:
		_apply_redirected_damage(state, actor, bulwark, redirected_raw, damage_type, action_id, skill_id, penetration, crit)
	return {"ok": true, "hit": true, "damage": dealt, "raw": raw, "error": ""}

func _dispatch_direct_status_triggers(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, damage_type: String, action_id: String, skill_id: String, direct: bool, proc_weight: float) -> void:
	if not direct or actor.side != "player" or not actor.alive or not target.alive:
		return
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary:
			continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "ON_HIT" or not _supports_direct_hit_trigger(effect):
			continue
		if str(trigger_value.get("sourceKind", "")) == "skill":
			continue
		if bool(effect.get("requireDirect", false)) and not direct:
			continue
		var damage_type_filter: Array = effect.get("damageTypeFilter", [])
		if not damage_type_filter.is_empty() and not damage_type_filter.has(damage_type):
			continue
		var skill_filter: Array = effect.get("skillFilter", [])
		if not skill_filter.is_empty() and not skill_filter.has(skill_id):
			continue
		if bool(effect.get("requireDrone", false)) and actor.kind != "drone":
			continue
		if not _trigger_status_condition_passes(state, actor, target, effect.get("condition", {})):
			continue
		var trigger_id: String = str(effect.get("id", ""))
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var owner: CombatActorState = _trigger_owner(state, source_id)
		var trigger_key: String = "%s:%s" % [source_id, trigger_id]
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(trigger_key, false)):
			continue
		if bool(effect.get("oncePerDrone", false)) and bool(owner.once_per_combat.get("%s:%s" % [trigger_key, actor.id], false)):
			continue
		if float(owner.icds.get(trigger_key, 0.0)) > float(state.time_ms):
			continue
		var proc_chance: float = clampf(float(effect.get("chance", 1.0)) * proc_weight * float(_effective_sheet(state, owner, target).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(proc_chance):
			continue
		var action: Dictionary = effect.get("action", {})
		owner.icds[trigger_key] = float(state.time_ms) + float(effect.get("icdMs", 0.0))
		if bool(effect.get("oncePerCombat", false)):
			owner.once_per_combat[trigger_key] = true
		if bool(effect.get("oncePerDrone", false)):
			owner.once_per_combat["%s:%s" % [trigger_key, actor.id]] = true
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, trigger_id]
		_emit(state, "TRIGGER", owner.id, {"targetId": target.id, "actionId": trigger_action_id, "skillId": skill_id if not skill_id.is_empty() else "", "damageType": damage_type, "text": "%s: сработал эффект «%s» после попадания %s." % [owner.display_name, trigger_id, actor.display_name], "data": {"sourceId": source_id, "chance": proc_chance}})
		var action_target: CombatActorState = owner if str(action.get("target", "target")) == "self" else target
		match str(action.get("kind", "")):
			"applyStatus":
				var status_id: String = str(action.get("status", ""))
				var duration_ms: float = float(action.get("durationMs", _status_catalog.get_definition(status_id).get("durationMs", 0.0)))
				var status_target: String = str(action.get("target", "target"))
				if status_target == "allEnemies":
					for enemy: CombatActorState in state.enemies:
						if enemy.alive: _add_simple_status(state, owner, enemy, status_id, duration_ms)
				elif status_target == "otherEnemy":
					for enemy: CombatActorState in state.enemies:
						if enemy.alive and enemy.id != target.id:
							_add_simple_status(state, owner, enemy, status_id, duration_ms)
							break
				else:
					_add_simple_status(state, owner, action_target, status_id, duration_ms)
			"restoreEnergy":
				var bucket: int = floori(float(state.time_ms) / 1000.0)
				if int(owner.flags.get("energyGainSecond", -1)) != bucket:
					owner.flags["energyGainSecond"] = bucket
					owner.flags["energyGainInSecond"] = 0.0
				var cap: float = float(action.get("perSecondCap", 1.0e30))
				var gain: float = minf(float(action.get("amount", 0.0)), maxf(0.0, cap - float(owner.flags.get("energyGainInSecond", 0.0))))
				var before_energy: float = owner.energy
				owner.energy = minf(float(_effective_sheet(state, owner).get("maxEnergy", 0.0)), owner.energy + gain)
				var restored_energy: float = owner.energy - before_energy
				owner.flags["energyGainInSecond"] = float(owner.flags.get("energyGainInSecond", 0.0)) + restored_energy
				if restored_energy > 0.0:
					_emit(state, "ENERGY", owner.id, {"actionId": trigger_action_id, "text": "%s: +%s энергии." % [owner.display_name, _one_decimal(restored_energy)], "data": {"amount": restored_energy}})
			"restoreShield":
				var shield_target: CombatActorState = state.operator if owner.kind == "drone" and owner.drone_role == "medic" else owner
				var max_shield: float = float(_effective_sheet(state, shield_target).get("maxShield", 0.0))
				var restored_shield: float = minf(float(action.get("amount", 0.0)), maxf(0.0, max_shield - shield_target.shield))
				shield_target.shield += restored_shield
				if restored_shield > 0.0:
					_emit(state, "SHIELD_GAIN", owner.id, {"targetId": shield_target.id, "actionId": trigger_action_id, "text": "%s: +%s щита." % [shield_target.display_name, _one_decimal(restored_shield)], "data": {"amount": restored_shield}})
			"extendStatus":
				var entries: Array = target.statuses.get(str(action.get("status", "")), [])
				var stacks: int = maxi(1, int(action.get("stacks", 1)))
				for index: int in range(mini(stacks, entries.size())):
					entries[index]["expiresAt"] = float(entries[index].get("expiresAt", state.time_ms)) + float(action.get("ms", 0.0))
			"secondaryDamage":
				var basis: float = float(_effective_sheet(state, owner).get("techPower", 0.0))
				match str(action.get("basis", "techPower")):
					"mainWeapon": basis = float(state.build.get("mainWeapon", {}).get("damage", 0.0))
					"flat": basis = 1.0
				var raw: float = basis * float(action.get("coefficient", 0.0))
				var targets: Array[CombatActorState] = []
				match str(action.get("targeting", "target")):
					"target": targets.append(target)
					"otherEnemy":
						for enemy: CombatActorState in state.enemies:
							if enemy.alive and enemy.id != target.id:
								targets.append(enemy)
								break
					"allEnemies":
						for enemy: CombatActorState in state.enemies:
							if enemy.alive: targets.append(enemy)
				for secondary: CombatActorState in targets:
					_resolve_basic_hit(state, rng, owner, secondary, raw, str(action.get("damageType", "ENERGY")), "%s:secondary" % trigger_action_id, false, "", 0.0, false, 0.0)

func _trigger_status_condition_passes(state: CombatState, actor: CombatActorState, target: CombatActorState, condition_value: Variant) -> bool:
	if not condition_value is Dictionary or condition_value.is_empty():
		return true
	var condition_kind: String = str(condition_value.get("kind", ""))
	match condition_kind:
		"targetStatus":
			return _status_stacks(target, str(condition_value.get("status", ""))) >= int(condition_value.get("minStacks", 1))
		"targetNoStatus":
			return not _has_status(target, str(condition_value.get("status", "")))
		"heatAtLeast":
			return actor.heat >= float(condition_value.get("value", 0.0))
		"hpBelow":
			return actor.hp / maxf(1.0, float(_effective_sheet(state, actor).get("maxHP", 1.0))) <= float(condition_value.get("value", 0.0))
		_:
			return false

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

func _gain_basic_heat(state: CombatState, actor: CombatActorState, amount: float, rng: DeterministicRng) -> void:
	if amount <= 0.0:
		return
	var max_heat: float = float(actor.base_sheet.get("maxHeat", 0.0))
	var before: float = actor.heat
	actor.heat = clampf(actor.heat + amount, 0.0, max_heat)
	if state.combat_rules_version == CombatState.V2_RULES_VERSION:
		actor.flags["v2LastHeatGainAt"] = state.time_ms
	_handle_heat_transition(state, rng, actor, before, max_heat)

func _handle_heat_transition(state: CombatState, rng: DeterministicRng, actor: CombatActorState, heat_before: float, max_heat: float) -> void:
	if state.combat_rules_version == CombatState.V2_RULES_VERSION:
		if actor.heat_lockout and state.time_ms >= actor.lockout_until:
			actor.heat_lockout = false
			actor.heat = minf(max_heat, 65.0)
			_emit(state, "HEAT_LOCKOUT_END", actor.id, {"data": {"heat": actor.heat, "reason": "LOCK_DURATION_ELAPSED"}})
		elif not actor.heat_lockout and actor.heat >= max_heat:
			actor.heat_lockout = true
			actor.lockout_until = state.time_ms + 1500
			state.metrics["heatLockouts"] = int(state.metrics.get("heatLockouts", 0)) + 1
			_emit(state, "HEAT_LOCKOUT", actor.id, {"data": {"heat": actor.heat, "untilMs": actor.lockout_until}})
		return
	if not actor.heat_lockout and heat_before < max_heat and actor.heat >= max_heat:
		actor.heat_lockout = true
		_emit(state, "HEAT", actor.id, {"text": "Нагрев достиг максимума.", "data": {"heat": actor.heat, "threshold": max_heat}})
		state.metrics["heatLockouts"] = int(state.metrics.get("heatLockouts", 0)) + 1
		var full_event: Dictionary = _emit(state, "HEAT_LOCKOUT", actor.id, {"text": "Перегрев: main-канал заблокирован до охлаждения ≤ 80."})
		_dispatch_authored_event(state, rng, "ON_HEAT_FULL", actor, _pick_auto_target(state, actor), "heat-full:%d" % state.time_ms, int(full_event.get("eventId", 0)), "", "", false, 1.0, actor.heat)
	if actor.heat_lockout and actor.heat <= 80.0:
		actor.heat_lockout = false
		var released: Dictionary = _emit(state, "HEAT_LOCKOUT_END", actor.id, {"text": "Перегрев снят: нагрев вернулся к 80 или ниже.", "data": {"heat": actor.heat, "threshold": 80.0}})
		_dispatch_authored_event(state, rng, "ON_HEAT_LOCKOUT_END", actor, null, "heat-release:%d" % state.time_ms, int(released.get("eventId", 0)), "", "", false, 1.0, actor.heat)

func _resolve_basic_deaths(state: CombatState, rng: DeterministicRng) -> void:
	for actor: CombatActorState in state.all_actors():
		if not actor.alive or actor.hp > 0.0:
			continue
		actor.alive = false
		var death_event: Dictionary = _emit(state, "DEATH", actor.id, {"text": "%s уничтожен." % actor.display_name})
		if actor.side == "enemy":
			state.metrics["kills"] = int(state.metrics.get("kills", 0)) + 1
			var ttk: Array = state.metrics["ttk"]
			ttk.append({"enemyId": actor.id, "name": actor.display_name, "ms": state.time_ms})
			var killer: CombatActorState = _actor_by_id(state, actor.last_hit_by_id)
			if killer != null and actor.last_hit_can_proc:
				_dispatch_kill_triggers(state, rng, killer, actor, death_event)
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
					var telegraph: Dictionary = _emit(state, "TELEGRAPH", actor.id, {"targetId": actor.cast["targetId"], "actionId": action_id, "text": "%s: %s" % [actor.display_name, str(ability.get("desc", ""))], "data": {"abilityId": ability.get("id", ""), "dangerTag": "deathBurst", "windupMs": windup}})
					_dispatch_authored_event(state, rng, "ON_ENEMY_TELEGRAPH", state.operator, actor, action_id, int(telegraph.get("eventId", 0)), "", "", false, 1.0)
				break
			for ally: CombatActorState in state.enemies:
				if ally.alive and ally.template_id == "E23":
					_add_simple_status(state, ally, ally, "BERSERK", 999000.0)
		elif actor.kind == "drone":
			state.metrics["droneDeaths"] = int(state.metrics.get("droneDeaths", 0)) + 1
			_dispatch_authored_event(state, rng, "ON_DRONE_DEATH", state.operator, actor, str(actor.last_hit_action_id), int(death_event.get("eventId", 0)), "", "", false, 1.0)

func _dispatch_kill_triggers(state: CombatState, rng: DeterministicRng, killer: CombatActorState, dead_target: CombatActorState, death_event: Dictionary) -> void:
	if killer.side != "player":
		return
	var damage_type: String = dead_target.last_hit_damage_type
	var direct: bool = dead_target.last_hit_direct
	var event_source: String = dead_target.last_hit_event_source
	var origin_action_id: String = dead_target.last_hit_origin_action_id
	var action_id: String = dead_target.last_hit_action_id if not dead_target.last_hit_action_id.is_empty() else origin_action_id
	var cause_id: int = dead_target.last_hit_cause_id if dead_target.last_hit_cause_id > 0 else int(death_event.get("eventId", 0))
	var proc_weight: float = 1.0 if event_source == "STATUS_TICK" else dead_target.last_hit_proc_weight
	for trigger_value: Variant in state.build.get("triggerEffects", []):
		if not trigger_value is Dictionary:
			continue
		var effect: Dictionary = trigger_value.get("effect", {})
		if str(effect.get("event", "")) != "ON_KILL" or not _supports_kill_trigger(effect):
			continue
		var source_id: String = str(trigger_value.get("sourceId", ""))
		var owner: CombatActorState = _trigger_owner(state, source_id)
		if not owner.alive or (owner.kind != "operator" and owner.id != killer.id):
			continue
		if bool(effect.get("requireDirect", false)) and not direct:
			continue
		if not str(effect.get("requireKillType", "")).is_empty() and str(effect.get("requireKillType", "")) != damage_type:
			continue
		if event_source == "STATUS_TICK" and not bool(effect.get("allowStatusTick", false)):
			continue
		if event_source == "SECONDARY" and not bool(effect.get("allowSecondary", false)):
			continue
		var damage_type_filter: Array = effect.get("damageTypeFilter", [])
		if not damage_type_filter.is_empty() and not damage_type_filter.has(damage_type):
			continue
		if not _trigger_status_condition_passes(state, killer, dead_target, effect.get("condition", {})):
			continue
		var trigger_id: String = str(effect.get("id", ""))
		var trigger_key: String = "%s:%s" % [source_id, trigger_id]
		var instance_key: String = "%s:%s" % [trigger_key, killer.id] if bool(effect.get("oncePerDrone", false)) else trigger_key
		if bool(effect.get("oncePerCombat", false)) and bool(owner.once_per_combat.get(trigger_key, false)):
			continue
		if bool(effect.get("oncePerDrone", false)) and bool(owner.once_per_combat.get(instance_key, false)):
			continue
		if float(owner.icds.get(instance_key, 0.0)) > float(state.time_ms):
			continue
		var chance: float = clampf(float(effect.get("chance", 1.0)) * proc_weight * float(_effective_sheet(state, owner, dead_target).get("procMultiplier", 1.0)), 0.0, 1.0)
		if not rng.chance(chance):
			continue
		if bool(effect.get("oncePerCombat", false)):
			owner.once_per_combat[trigger_key] = true
		if bool(effect.get("oncePerDrone", false)):
			owner.once_per_combat[instance_key] = true
		var icd_ms: float = float(effect.get("icdMs", 0.0))
		if icd_ms > 0.0:
			owner.icds[instance_key] = float(state.time_ms) + icd_ms
		state.metrics["procsTriggered"] = int(state.metrics.get("procsTriggered", 0)) + 1
		var trigger_action_id: String = "%s:trigger:%s" % [action_id, trigger_id]
		var trigger_event: Dictionary = _emit(state, "TRIGGER", owner.id, {"targetId": dead_target.id, "actionId": trigger_action_id, "text": "%s: сработал эффект «%s» при убийстве." % [owner.display_name, trigger_id], "data": {"sourceId": source_id, "chance": chance, "damageType": damage_type, "eventSource": event_source}})
		var action: Dictionary = effect.get("action", {})
		match str(action.get("kind", "")):
			"restoreEnergy":
				_restore_trigger_energy(state, owner, action, trigger_action_id, int(trigger_event.get("eventId", 0)))
			"changeHeat":
				var amount: float = float(action.get("amount", 0.0))
				if amount >= 0.0:
					_gain_basic_heat(state, owner, amount, rng)
				else:
					owner.heat = maxf(0.0, owner.heat + amount)
					if bool(action.get("removeLockout", false)) and owner.heat <= 80.0:
						owner.heat_lockout = false
			"transferVirus":
				_transfer_kill_virus(state, owner, dead_target, int(action.get("stacks", 1)), trigger_action_id, int(trigger_event.get("eventId", 0)))
			"secondaryDamage":
				_apply_kill_secondary_damage(state, rng, owner, killer, dead_target, action, trigger_action_id)

func _restore_trigger_energy(state: CombatState, owner: CombatActorState, action: Dictionary, action_id: String, cause_id: int = 0) -> void:
	var bucket: int = floori(float(state.time_ms) / 1000.0)
	if int(owner.flags.get("energyGainSecond", -1)) != bucket:
		owner.flags["energyGainSecond"] = bucket
		owner.flags["energyGainInSecond"] = 0.0
	var cap: float = float(action.get("perSecondCap", 1.0e30))
	var gain: float = minf(float(action.get("amount", 0.0)), maxf(0.0, cap - float(owner.flags.get("energyGainInSecond", 0.0))))
	var before: float = owner.energy
	owner.energy = minf(float(_effective_sheet(state, owner).get("maxEnergy", 0.0)), owner.energy + gain)
	var restored: float = owner.energy - before
	owner.flags["energyGainInSecond"] = float(owner.flags.get("energyGainInSecond", 0.0)) + restored
	if restored > 0.0:
		_emit(state, "ENERGY", owner.id, {"actionId": action_id, "causeId": cause_id, "text": "%s: +%s энергии." % [owner.display_name, _one_decimal(restored)], "data": {"amount": restored}})

func _transfer_kill_virus(state: CombatState, owner: CombatActorState, dead_target: CombatActorState, requested: int, action_id: String, cause_id: int) -> void:
	if not _status_catalog_loaded:
		var loaded: Dictionary = _status_catalog.load_catalog()
		_status_catalog_loaded = true
		_status_catalog_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _status_catalog_error.is_empty():
		return
	var entries: Array = dead_target.statuses.get("VIRUS", [])
	var destination: CombatActorState = null
	for enemy: CombatActorState in state.enemies:
		if enemy.alive and enemy.id != dead_target.id:
			destination = enemy
			break
	if entries.is_empty() or destination == null or requested <= 0:
		return
	var max_stacks: int = int(_status_catalog.get_definition("VIRUS").get("maxStacks", 6)) + floori(float(_effective_sheet(state, owner).get("virusStackCap", 0.0)))
	var capacity: int = maxi(0, max_stacks - _status_stacks(destination, "VIRUS"))
	var count: int = mini(mini(requested, entries.size()), capacity)
	if count <= 0:
		return
	var moved: Array = entries.slice(0, count)
	dead_target.statuses["VIRUS"] = entries.slice(count)
	var destination_entries: Array = destination.statuses.get("VIRUS", [])
	for entry: Dictionary in moved:
		var transferred: Dictionary = entry.duplicate(true)
		transferred["sourceId"] = "%s:VIRUS" % owner.id
		transferred["sourceActorId"] = owner.id
		destination_entries.append(transferred)
	destination.statuses["VIRUS"] = destination_entries
	_emit(state, "STATUS_APPLY", owner.id, {"targetId": destination.id, "actionId": action_id, "causeId": cause_id, "statusId": "VIRUS", "text": "%s: VIRUS перенесён на %s." % [owner.display_name, destination.display_name], "data": {"stacks": _status_stacks(destination, "VIRUS"), "moved": count}})

func _apply_kill_secondary_damage(state: CombatState, rng: DeterministicRng, owner: CombatActorState, killer: CombatActorState, dead_target: CombatActorState, action: Dictionary, action_id: String) -> void:
	var basis: float = float(_effective_sheet(state, owner).get("techPower", 0.0))
	match str(action.get("basis", "techPower")):
		"mainWeapon": basis = float(state.build.get("mainWeapon", {}).get("damage", 0.0))
		"droneTech": basis = killer.attack_damage if killer.kind == "drone" else float(state.drones[0].attack_damage) if not state.drones.is_empty() else 0.0
		"flat": basis = 1.0
		"virusRemaining": basis = float(_status_stacks(dead_target, "VIRUS"))
	var raw: float = basis * float(action.get("coefficient", 0.0))
	var targets: Array[CombatActorState] = []
	match str(action.get("targeting", "otherEnemy")):
		"target":
			var primary: CombatActorState = _pick_auto_target(state, owner)
			if primary != null: targets.append(primary)
		"otherEnemy":
			for enemy: CombatActorState in state.enemies:
				if enemy.alive and enemy.id != dead_target.id:
					targets.append(enemy)
					break
		"allEnemies":
			for enemy: CombatActorState in state.enemies:
				if enemy.alive: targets.append(enemy)
	var max_targets: int = int(action.get("maxTargets", targets.size()))
	for index: int in range(mini(targets.size(), maxi(0, max_targets))):
		_resolve_basic_hit(state, rng, owner, targets[index], raw, str(action.get("damageType", "DIGITAL")), "%s:child:%d" % [action_id, index + 1], false, "", 0.0, false, 0.0)

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
