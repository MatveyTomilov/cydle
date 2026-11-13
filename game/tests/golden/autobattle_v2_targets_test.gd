extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var state: CombatState = CombatState.new()
	state.operator = CombatActorState.new()
	state.operator.id = "operator"
	var low_abs: CombatActorState = _enemy("enemy:a", 30, 100)
	var low_pct: CombatActorState = _enemy("enemy:b", 60, 300)
	var boss: CombatActorState = _enemy("boss:z", 250, 500)
	boss.is_boss = true
	var infected: CombatActorState = _enemy("enemy:c", 90, 150)
	infected.statuses["VIRUS"] = [{"stacks": 1}]
	state.enemies = [low_abs, low_pct, boss, infected]
	var targeter: AutobattleV2Targets = AutobattleV2Targets.new()
	check(targeter.resolve(state, "LOWEST_HP")["targets"] == ["enemy:a"], "targets: absolute HP ordering lost")
	check(targeter.resolve(state, "LOWEST_HP_PERCENT")["targets"] == ["enemy:b"], "targets: HP percent conflated with absolute HP")
	check(targeter.resolve(state, "INFECTED")["targets"] == ["enemy:c"], "targets: infected doctrine selected the wrong actor")
	check(targeter.resolve(state, "BOSS")["targets"] == ["boss:z"], "targets: boss doctrine ignored boss flag")
	check(targeter.resolve(state, "NEAREST")["targets"] == ["boss:z"], "targets: nearest tie ordering is not stable")
	check(targeter.resolve(state, "ALL_ENEMIES")["targets"] == ["boss:z", "enemy:a", "enemy:b", "enemy:c"], "targets: multi target ordering is not stable")
	check(targeter.resolve(state, "SELF")["targets"] == ["operator"], "targets: self doctrine changed actor")
	var unsupported: Dictionary = targeter.resolve(state, "invented")
	check(not bool(unsupported["ok"]) and str(unsupported["error"]).contains("invented"), "targets: unknown doctrine was silently accepted")
	return failure_count == 0

func _enemy(id: String, hp: float, max_hp: float) -> CombatActorState:
	var actor: CombatActorState = CombatActorState.new()
	actor.id = id
	actor.alive = true
	actor.hp = hp
	actor.base_sheet = {"maxHP": max_hp}
	return actor
