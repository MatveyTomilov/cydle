class_name CombatSimulator
extends RefCounted

const COMBAT_RULES_VERSION: String = "cydle-combat-1.0"
const MAX_LOG_EVENTS: int = 5000
const DEFAULT_MAX_DURATION_MS: int = 180000
const STEP_STATUS_IDS: Array[String] = [
	"BLEED", "BURN", "VIRUS", "ARMOR_BREAK", "SHOCK", "DRONE_JAM", "SHIELD_LEAK",
	"MARK", "SCAN_MARK", "DRONE_MARK", "CONTROLLED", "GUARD", "OVERCLOCK",
	"ACC_BUFF", "EVASION_BUFF", "SHIELD_REGEN_BUFF", "BERSERK",
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

func step_combat(state: CombatState) -> Dictionary:
	if state == null:
		return _failure("Нельзя продвинуть пустое состояние боя.")
	if not state.outcome.is_empty():
		return {"ok": true, "state": state, "error": ""}
	if not _supports_basic_auto_step(state):
		return _failure("Эта боевая конфигурация требует ещё не перенесённые способности, статусы, триггеры или тактические правила.")
	var next: CombatState = state.clone()
	var rng: DeterministicRng = DeterministicRng.new()
	if not rng.restore(next.rng):
		return _failure("Состояние боевого RNG повреждено.")
	next.time_ms += TICK_MS
	_apply_basic_continuous(next)
	_tick_dot_statuses(next)
	_expire_dot_statuses(next)
	_advance_main_skill_cast(next, rng)
	var ready: Array[CombatActorState] = next.all_actors()
	ready.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool: return left.id < right.id)
	for actor: CombatActorState in ready:
		if not actor.alive or actor.next_attack_at > float(next.time_ms):
			continue
		if actor.kind == "operator":
			if actor.cast != null:
				continue
			var chosen: Dictionary = _choose_main_skill(next, rng, actor)
			if bool(chosen.get("started", false)):
				continue
		var target: CombatActorState = _pick_auto_target(next, actor)
		if target == null:
			continue
		var attack: Dictionary = _resolve_basic_attack(next, rng, actor, target)
		if not bool(attack.get("ok", false)):
			return _failure(str(attack.get("error", "Автоатака не разрешилась.")))
		_schedule_next_attack(next, actor)
	_resolve_basic_deaths(next)
	_check_terminal(next)
	next.rng = rng.serialize()
	return {"ok": true, "state": next, "error": ""}

func _supports_basic_auto_step(state: CombatState) -> bool:
	if not state.build.get("triggerEffects", []).is_empty():
		return false
	for rule_value: Variant in state.tactics.get("rules", []):
		if not rule_value is Dictionary or not bool(rule_value.get("enabled", false)):
			continue
		if str(rule_value.get("skillId", "AUTO")) not in ["AUTO", "SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_PLASMA"]:
			return false
		if str(rule_value.get("skillId", "AUTO")) == "SK_BURST" and str(rule_value.get("target", "nearest")) not in ["nearest", "lowestHPPercent"]:
			return false
	if state.extra_enemy_digital_bonus != 0.0:
		return false
	for actor: CombatActorState in state.all_actors():
		if not actor.elite_mod.is_empty() or not actor.ability_next.is_empty() or not actor.buffs.is_empty() or actor.reaction_cast != null:
			return false
		if actor.cast != null and (actor.kind != "operator" or not actor.cast is Dictionary or str(actor.cast.get("skillId", "")) not in ["SK_BURST", "SK_PIERCE", "SK_EXEC", "SK_PLASMA"]):
			return false
		for status_id: Variant in actor.statuses.keys():
			if not STEP_STATUS_IDS.has(str(status_id)):
				return false
		if actor.side == "enemy":
			var template: Dictionary = _factory._enemy_catalog.get_template(actor.template_id)
			if not template.get("passives", []).is_empty() or not template.get("rotating", []).is_empty():
				return false
	return true

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
		var energy_cost: float = float(skill.get("energyCost", 0.0))
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
		if not _rule_conditions_pass(state, actor, rule, target):
			_record_rule_failure(state, rule_id, "conditions")
			continue
		_start_main_skill(state, actor, skill, target)
		return {"started": true}
	return {"started": false}

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
	if mode == "lowestHPPercent":
		enemies.sort_custom(func(left: CombatActorState, right: CombatActorState) -> bool:
			var left_fraction: float = left.hp / maxf(1.0, float(left.base_sheet.get("maxHP", 1.0)))
			var right_fraction: float = right.hp / maxf(1.0, float(right.base_sheet.get("maxHP", 1.0)))
			return left_fraction < right_fraction if not is_equal_approx(left_fraction, right_fraction) else left.id < right.id)
	return enemies[0]

func _start_main_skill(state: CombatState, actor: CombatActorState, skill: Dictionary, target: CombatActorState) -> void:
	var skill_id: String = str(skill.get("id", ""))
	var cost: float = float(skill.get("energyCost", 0.0))
	actor.energy = clampf(actor.energy - cost, 0.0, float(actor.base_sheet.get("maxEnergy", 0.0)))
	state.metrics["energySpent"] = float(state.metrics.get("energySpent", 0.0)) + cost
	_gain_basic_heat(state, actor, float(skill.get("heatDelta", 0.0)))
	var cooldown: float = _formula.cooldown_ms(float(skill.get("cooldownMs", 0.0)), float(_effective_sheet(state, actor).get("cooldownRecovery", 0.0)))
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

func _resolve_main_skill(state: CombatState, rng: DeterministicRng, actor: CombatActorState, cast: Dictionary) -> void:
	var skill_id: String = str(cast.get("skillId", ""))
	var skill: Dictionary = _equipped_skill(state, skill_id)
	if skill.is_empty():
		return
	var target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
	state.metrics["skillUses"][skill_id] = int(state.metrics["skillUses"].get(skill_id, 0)) + 1
	_emit(state, "SKILL_USE", actor.id, {
		"skillId": skill_id, "targetId": target.id if target != null else "", "actionId": str(cast.get("actionId", "")),
		"originActionId": str(cast.get("actionId", "")), "text": "%s: %s." % [actor.display_name, str(skill.get("name", skill_id))],
		"data": {"channel": "main"},
	})
	var weapon: Dictionary = state.build.get("mainWeapon", {})
	var sidearm: Dictionary = state.build.get("sidearm", {})
	var basis: String = str(skill.get("basis", ""))
	var effective: Dictionary = _effective_sheet(state, actor)
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
	var coefficient: float = float(skill.get("hitCoefficient", skill.get("coefficient", 1.0)))
	var hits: int = maxi(1, int(skill.get("hits", 1)))
	for hit_index: int in range(hits):
		var current_target: CombatActorState = _actor_by_id(state, str(cast.get("targetId", "")))
		if current_target == null or not current_target.alive:
			current_target = _pick_auto_target(state, actor)
		if current_target == null:
			break
		var raw_base: float = base_damage * coefficient
		var tags: Array = skill.get("tags", [])
		if tags.has("E"):
			raw_base *= float(effective.get("moreSkillEnergy", 1.0))
		if tags.has("D"):
			raw_base *= float(effective.get("moreSkillDigital", 1.0))
		if skill_id == "SK_EXEC" and current_target.hp / maxf(1.0, float(current_target.base_sheet.get("maxHP", 1.0))) < 0.3:
			raw_base *= 1.4 * float(_effective_sheet(state, actor, current_target).get("moreExecute", 1.0))
		var hit: Dictionary = _resolve_basic_hit(
			state, rng, actor, current_target, raw_base,
			damage_type, str(cast.get("actionId", "")), is_main, skill_id,
		)
		if not bool(hit.get("ok", false)):
			return

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
	return enemies[0] if not enemies.is_empty() else null

func _resolve_basic_attack(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState) -> Dictionary:
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
	for packet: Dictionary in packets:
		var current_target: CombatActorState = _pick_auto_target(state, actor)
		if current_target == null:
			break
		var hit_result: Dictionary = _resolve_basic_hit(state, rng, actor, current_target, float(packet["amount"]), str(packet["type"]), action_id, actor.kind == "operator")
		if not bool(hit_result.get("ok", false)):
			return hit_result
	if actor.kind == "operator":
		actor.flags["firstAttack"] = 0.0
	return {"ok": true, "error": ""}

func _attack_packets(actor: CombatActorState, weapon: Dictionary) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	if actor.kind == "operator" and weapon.get("packets", []) is Array and not weapon.get("packets", []).is_empty():
		for packet: Dictionary in weapon["packets"]:
			packets.append({"type": packet["type"], "amount": packet["amount"]})
	elif actor.kind == "operator":
		var count: int = int(weapon.get("pelletCount", 1))
		for _index: int in range(count):
			packets.append({"type": actor.attack_type, "amount": actor.attack_damage})
	else:
		packets.append({"type": actor.attack_type, "amount": actor.attack_damage})
	return packets

func _resolve_basic_hit(state: CombatState, rng: DeterministicRng, actor: CombatActorState, target: CombatActorState, raw_base: float, damage_type: String, action_id: String, is_main: bool, skill_id: String = "") -> Dictionary:
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
		return {"ok": true, "error": ""}
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
		"armorPen": float(attacker.get("armorPen", 0.0)) + state.elite_pen + (10.0 if actor.elite_mod == "EL_PEN" else 0.0),
		"armorPenPercent": float(attacker.get("armorPenPercent", 0.0)),
		"energyPen": float(attacker.get("energyPen", 0.0)), "energyPenPercent": float(attacker.get("energyPenPercent", 0.0)),
		"digitalPen": float(attacker.get("digitalPen", 0.0)), "digitalPenPercent": float(attacker.get("digitalPenPercent", 0.0)),
	}
	if skill_id == "SK_PIERCE":
		penetration["armorPen"] = float(penetration["armorPen"]) + 20.0
	var mitigation: Dictionary = _damage.mitigate_packet(raw, damage_type, {"armor": defender.get("armor", 0.0), "energyRes": defender.get("energyRes", 0.0), "digitalRes": defender.get("digitalRes", 0.0)}, penetration)
	var incoming: float = float(mitigation["afterDefense"]) * float(defender.get("incomingAll", 1.0)) * float(defender.get("incomingKinetic" if damage_type == "KINETIC" else "incomingEnergy" if damage_type == "ENERGY" else "incomingDigital", 1.0))
	if _has_status(target, "MARK"):
		incoming *= 1.3
		target.statuses.erase("MARK")
	var partition: Dictionary = _damage.partition_damage(incoming, {"hp": target.hp, "shield": target.shield, "temp": target.temp_shields}, 0.0, float(defender.get("incomingShield", 1.0)))
	_apply_partition(target, partition)
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
	return {"ok": true, "error": ""}

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
		elif actor.kind == "drone":
			state.metrics["droneDeaths"] = int(state.metrics.get("droneDeaths", 0)) + 1

func _check_terminal(state: CombatState) -> void:
	if not state.operator.alive:
		state.outcome = "DEFEAT"
	elif not state.enemies.any(func(enemy: CombatActorState) -> bool: return enemy.alive):
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
