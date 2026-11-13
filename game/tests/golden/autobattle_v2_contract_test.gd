extends "res://tests/test_case.gd"

const CONTRACT: Script = preload("res://scripts/core/combat/autobattle_v2_contract.gd")

func run(_tree: SceneTree) -> bool:
	var contract: AutobattleV2Contract = CONTRACT.new() as AutobattleV2Contract
	var weapon: Dictionary = {
		"sourceId": "weapon:ARC-9", "actionId": "ARC-9:basic",
		"classId": "BASIC_ATTACK", "targetMode": "HIGHEST_THREAT",
		"readyAtMs": 0, "cooldownUntilMs": 0, "energyCost": 4.0, "heatDelta": 9.0,
		"prepareMs": 600, "recoveryMs": 200, "cooldownMs": 0,
	}
	var special: Dictionary = {
		"sourceId": "ability:vent", "actionId": "vent",
		"classId": "DEFENSE", "targetMode": "SELF",
		"readyAtMs": 0, "cooldownUntilMs": 0, "energyCost": 0.0, "heatDelta": -45.0,
	}
	var actions: Array[Dictionary] = [weapon, special]
	var picked: Dictionary = contract.select_action(actions, 0, 100.0, 80.0, 100.0)
	check(str(picked.get("action", {}).get("actionId", "")) == "vent", "autobattle_v2: action class order ignored")
	picked = contract.select_action([special, weapon], 0, 100.0, 80.0, 100.0)
	check(str(picked.get("action", {}).get("actionId", "")) == "vent", "autobattle_v2: inventory reorder changed the selected action")
	var early: Dictionary = special.duplicate(true)
	early["readyAtMs"] = 100
	picked = contract.select_action([early, weapon], 0, 100.0, 10.0, 100.0)
	check(str(picked.get("action", {}).get("actionId", "")) == "ARC-9:basic", "autobattle_v2: unready action was selected")
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "COOLDOWN", "autobattle_v2: missing cooldown reason")
	picked = contract.select_action([weapon], 0, 2.0, 10.0, 100.0)
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "ENERGY", "autobattle_v2: missing energy reason")
	picked = contract.select_action([weapon], 0, 100.0, 96.0, 100.0)
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "HEAT_CAP", "autobattle_v2: heat limit ignored")
	picked = contract.select_action([weapon], 0, 100.0, 20.0, 100.0, true)
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "THERMAL_LOCK", "autobattle_v2: thermal lock ignored")
	var injected: Dictionary = special.duplicate(true)
	injected["priority"] = 9999
	picked = contract.select_action([injected, weapon], 0, 100.0, 20.0, 100.0)
	check(str(picked.get("action", {}).get("actionId", "")) == "ARC-9:basic", "autobattle_v2: programmable priority entered the selector")
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "PLAYER_RULE_FORBIDDEN", "autobattle_v2: player rule rejection reason missing")
	injected = special.duplicate(true)
	injected["conditions"] = [{"kind": "hpBelow", "value": 0.3}]
	picked = contract.select_action([injected], 0, 100.0, 20.0, 100.0)
	check(str(picked.get("rejected", [])[0].get("reason", "")) == "PLAYER_RULE_FORBIDDEN", "autobattle_v2: programmable conditions accepted")

	var timeline: Dictionary = contract.begin_action(weapon, 0)
	check(str(timeline.get("phase", "")) == "PREPARE" and int(timeline.get("commitAtMs", -1)) == 600, "autobattle_v2: wrong prepare timestamp")
	var progressed: Dictionary = contract.advance_action(timeline, 500)
	check(str(progressed.get("timeline", {}).get("phase", "")) == "PREPARE" and not bool(progressed.get("didCommit", true)), "autobattle_v2: premature commit")
	progressed = contract.advance_action(timeline, 600)
	check(bool(progressed.get("didCommit", false)) and str(progressed.get("timeline", {}).get("phase", "")) == "COMMIT", "autobattle_v2: commit missing on timestamp")
	timeline = progressed["timeline"]
	progressed = contract.advance_action(timeline, 600)
	check(not bool(progressed.get("didCommit", true)), "autobattle_v2: same commit charged twice")
	progressed = contract.advance_action(progressed["timeline"], 700)
	check(str(progressed.get("timeline", {}).get("phase", "")) == "RECOVERY", "autobattle_v2: recovery phase lost")
	progressed = contract.advance_action(progressed["timeline"], 800)
	check(str(progressed.get("timeline", {}).get("phase", "")) == "READY", "autobattle_v2: zero cooldown still blocked")
	var interruption: Dictionary = contract.interrupt_action(contract.begin_action(weapon, 0), 500)
	check(bool(interruption.get("interrupted", false)), "autobattle_v2: PREPARE should be interruptible")
	interruption = contract.interrupt_action(timeline, 700)
	check(not bool(interruption.get("interrupted", true)), "autobattle_v2: committed action was interrupted")
	check(not contract.reaction_ready(1400, 1000, 1200), "autobattle_v2: reaction budget was bypassed")
	check(contract.reaction_ready(1500, 1000, 1200), "autobattle_v2: reaction did not resume at 500ms")
	check(not contract.reaction_ready(1500, 1000, 1600), "autobattle_v2: internal reaction cooldown was bypassed")

	var ledger: Dictionary = contract.new_root_ledger(42)
	var admitted: Dictionary = contract.try_derive(ledger, "implant:vent", 0)
	check(bool(admitted.get("ok", false)) and int(admitted.get("chainDepth", -1)) == 1, "autobattle_v2: first derived proc failed")
	ledger = admitted["ledger"]
	admitted = contract.try_derive(ledger, "implant:vent", 0)
	check(str(admitted.get("reason", "")) == "INSTANCE_ALREADY_FIRED", "autobattle_v2: same effect fired twice for one root")
	admitted = contract.try_derive(ledger, "implant:vent", 1, true, "implant:vent")
	check(str(admitted.get("reason", "")) == "RECURSIVE_PROC_FORBIDDEN", "autobattle_v2: identical proc recursion accepted")
	admitted = contract.try_derive(ledger, "impl:deep", 6)
	check(str(admitted.get("reason", "")) == "PROC_BUDGET_EXHAUSTED", "autobattle_v2: chain depth exceeded limit")
	for i: int in range(15):
		admitted = contract.try_derive(ledger, "instance:%d" % i, 1)
		check(bool(admitted.get("ok", false)), "autobattle_v2: valid derived effect rejected at index %d" % i)
		ledger = admitted["ledger"]
	admitted = contract.try_derive(ledger, "instance:17", 1)
	check(str(admitted.get("reason", "")) == "PROC_BUDGET_EXHAUSTED", "autobattle_v2: derived-effect budget exceeded")
	check(not contract.can_emit_on_hit("DOT_TICK") and not contract.can_emit_on_hit("PROC_DAMAGE") and not contract.can_emit_on_hit("REFLECT"), "autobattle_v2: secondary damage generated on-hit")
	check(contract.can_emit_on_hit("DAMAGE") and contract.can_emit_on_hit("DOT_TICK", true), "autobattle_v2: direct hit/explicit exception incorrectly blocked")

	var enemies: Array[Dictionary] = [
		{"id": "z", "alive": true, "hp": 50.0, "threat": 9.0, "distance": 2.0, "marked": false},
		{"id": "a", "alive": true, "hp": 70.0, "threat": 9.0, "distance": 9.0, "marked": true},
		{"id": "b", "alive": true, "hp": 15.0, "threat": 3.0, "distance": 3.0, "marked": false},
	]
	check(contract.select_targets("HIGHEST_THREAT", enemies, "") == PackedStringArray(["a"]), "autobattle_v2: threat tie breaker unstable")
	check(contract.select_targets("LOWEST_HP", enemies, "") == PackedStringArray(["b"]), "autobattle_v2: low-hp doctrine wrong")
	check(contract.select_targets("NEAREST", enemies, "") == PackedStringArray(["z"]), "autobattle_v2: nearest doctrine wrong")
	check(contract.select_targets("MARKED", enemies, "") == PackedStringArray(["a"]), "autobattle_v2: marked doctrine wrong")
	check(contract.select_targets("FOCUS", enemies, "b") == PackedStringArray(["b"]), "autobattle_v2: focused target ignored")
	check(contract.select_targets("FOCUS", enemies, "gone") == PackedStringArray(["a"]), "autobattle_v2: focus fallback wrong")
	check(contract.select_targets("RANDOM_SEEDED", enemies, "", 2) == PackedStringArray(["z"]), "autobattle_v2: random seeded index not deterministic")
	check(contract.select_targets("ALL", enemies, "") == PackedStringArray(["a", "b", "z"]), "autobattle_v2: ALL target order unstable")
	return failure_count == 0
