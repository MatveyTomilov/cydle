extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var state: CombatState = CombatState.new()
	state.operator = CombatActorState.new()
	state.operator.id = "operator"
	var low_abs: CombatActorState = _enemy("enemy:a", 30, 100)
	var low_pct: CombatActorState = _enemy("enemy:b", 60, 300)
	var boss: CombatActorState = _enemy("boss:z", 250, 500)
	boss.is_boss = true
	boss.threat_units = 9
	var low_threat_boss: CombatActorState = _enemy("boss:a", 400, 500)
	low_threat_boss.is_boss = true
	var infected: CombatActorState = _enemy("enemy:c", 90, 150)
	infected.statuses["VIRUS"] = [{"stacks": 1}]
	state.enemies = [low_abs, low_pct, boss, low_threat_boss, infected]
	var targeter: AutobattleV2Targets = AutobattleV2Targets.new()
	check(_resolve(targeter, state, "lowestHP")["targets"] == ["enemy:a"], "targets: absolute HP ordering lost")
	check(_resolve(targeter, state, "lowestHPPercent")["targets"] == ["enemy:b"], "targets: HP percent conflated with absolute HP")
	check(_resolve(targeter, state, "infected")["targets"] == ["enemy:c"], "targets: infected doctrine selected the wrong actor")
	check(_resolve(targeter, state, "boss")["targets"] == ["boss:a"], "targets: boss doctrine changed the stable ID ordering")
	check(_resolve(targeter, state, "nearest")["targets"] == ["boss:a"], "targets: nearest tie ordering is not stable")
	check(_resolve(targeter, state, "highestThreat")["targets"] == ["boss:z"], "targets: highest threat is unsupported")
	check(_resolve(targeter, state, "allEnemies")["targets"] == ["boss:a", "boss:z", "enemy:a", "enemy:b", "enemy:c"], "targets: multi target ordering is not stable")
	check(_resolve(targeter, state, "self")["targets"] == ["operator"], "targets: self doctrine changed actor")
	state.enemies = [low_abs, low_pct, infected]
	check(_resolve(targeter, state, "boss")["targets"] == ["enemy:a"] and _resolve(targeter, state, "infected")["targets"] == ["enemy:c"], "targets: legacy selector fallback changed when the preferred target category is missing")
	infected.statuses.clear()
	check(_resolve(targeter, state, "infected")["targets"] == ["enemy:a"], "targets: missing status lost the legacy stable fallback")
	var unsupported: Dictionary = AutobattleV2Contract.compile_target("invented")
	check(not bool(unsupported["ok"]) and str(unsupported["error"]).contains("invented"), "targets: unknown doctrine was silently accepted")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/catalog/build_definitions.json"))
	for skill: Dictionary in catalog.get("skills", []):
		if str(skill.get("channel", "main")) != "main": continue
		var catalog_target: Dictionary = AutobattleV2Contract.compile_target(str(skill.get("targetMode", "")))
		check(bool(catalog_target.get("ok", false)), "targets: authored main skill %s uses unsupported doctrine %s" % [skill.get("id", ""), skill.get("targetMode", "")])
	var reaction_target: Dictionary = AutobattleV2Contract.compile_target("imminentCast")
	check(not bool(reaction_target.get("ok", true)) and str(reaction_target.get("error", "")).contains("imminentCast"), "targets: unported reaction target did not retain explicit unsupported diagnostic")
	var authored: Array[Dictionary] = []
	for mode: String in ["lowestHP", "lowestHPPercent", "infected", "boss", "nearest", "allEnemies", "self", "highestThreat"]:
		authored.append({"id": "SK_%s" % mode, "channel": "main", "targetMode": mode, "windupMs": 350, "recoveryMs": 250, "cooldownMs": 1700, "energyCost": 9, "heatDelta": 4, "requires": ["VIRUS"], "basis": "TECH_E"})
	var compiled: Array[Dictionary] = CombatFactory.new().compile_v2_main_actions({"mainWeapon": {}, "skills": authored}, {"energySkillCostFlat": 2, "skillEnergyCostLess": 10})
	var expected: Array[String] = ["LOWEST_HP", "LOWEST_HP_PERCENT", "INFECTED", "BOSS", "NEAREST", "ALL_ENEMIES", "SELF", "HIGHEST_THREAT"]
	check(compiled.size() == expected.size(), "targets: compiler dropped an authored skill")
	for index: int in range(mini(compiled.size(), expected.size())):
		check(str(compiled[index]["targetMode"]) == expected[index], "targets: compiler changed %s doctrine" % authored[index]["targetMode"])
		check(int(compiled[index]["targetDoctrine"]) == int(AutobattleV2Contract.compile_target(str(authored[index]["targetMode"]))["doctrine"]), "targets: compiler lost typed doctrine")
		check(compiled[index]["requires"] == ["VIRUS"] and float(compiled[index]["energyCost"]) == 6.3 and float(compiled[index]["heatDelta"]) == 4, "targets: compiler lost skill requirements or resources")
		check(int(compiled[index]["prepareMs"]) == 400 and int(compiled[index]["recoveryMs"]) == 300 and int(compiled[index]["cooldownMs"]) == 1700 and str(compiled[index]["sourceId"]) == str(authored[index]["id"]), "targets: compiler lost timing or source identity")
	var invalid: Array[Dictionary] = CombatFactory.new().compile_v2_main_actions({"mainWeapon": {}, "skills": [{"id": "SK_BAD", "channel": "main", "targetMode": "invented"}]}, {})
	check(invalid.size() == 1 and not str(invalid[0].get("targetError", "")).is_empty(), "targets: compiler did not report unsupported target mode")
	return failure_count == 0

func _enemy(id: String, hp: float, max_hp: float) -> CombatActorState:
	var actor: CombatActorState = CombatActorState.new()
	actor.id = id
	actor.alive = true
	actor.hp = hp
	actor.base_sheet = {"maxHP": max_hp}
	return actor

func _resolve(targeter: AutobattleV2Targets, state: CombatState, authored_mode: String) -> Dictionary:
	var compiled: Dictionary = AutobattleV2Contract.compile_target(authored_mode)
	return targeter.resolve(state, int(compiled["doctrine"])) if bool(compiled["ok"]) else compiled
