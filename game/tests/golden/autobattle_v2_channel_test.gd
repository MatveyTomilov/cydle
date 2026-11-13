extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var channel: AutobattleV2Channel = AutobattleV2Channel.new()
	var attack: Dictionary = {"sourceId": "weapon:test", "actionId": "basic", "classId": "BASIC_ATTACK", "targetDoctrine": AutobattleV2Contract.Doctrine.HIGHEST_THREAT, "targetMode": "HIGHEST_THREAT", "prepareMs": 200, "recoveryMs": 100, "cooldownMs": 0}
	var defense: Dictionary = {"sourceId": "armor:test", "actionId": "shield", "classId": "DEFENSE", "targetDoctrine": AutobattleV2Contract.Doctrine.SELF, "targetMode": "SELF", "prepareMs": 100, "recoveryMs": 100, "cooldownMs": 8000}
	var started: Dictionary = channel.start(channel.new_state(), [attack, defense], 0, 100, 0, 100)
	check(str(started["action"]["actionId"]) == "shield", "channel: first defense not selected")
	check(int(started["state"]["active"]["timeline"]["readyAtMs"]) == 8000, "channel: cooldown did not start at PREPARE or outlast the recovery boundary")
	check(not bool(channel.start(started["state"], [attack], 0, 100, 0, 100)["ok"]), "channel: occupied channel overwritten")
	var advanced: Dictionary = channel.advance(started["state"], 100)
	check(str(advanced["commit"].get("actionId", "")) == "shield", "channel: defense commit missing")
	# Persist while recovering. Loading must not pay/apply the same action twice.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(advanced["state"]))
	var repeated: Dictionary = channel.advance(saved, 100)
	check(repeated["commit"].is_empty(), "channel: loaded commit replayed")
	advanced = channel.advance(saved, 200)
	check(bool(advanced["channelReady"]), "channel: cooldown retained main channel")
	started = channel.start(advanced["state"], [defense, attack], 200, 100, 0, 100)
	check(str(started["action"].get("actionId", "")) == "basic", "channel: defense cooldown suppressed basic")
	check(str(started["rejected"][0].get("reason", "")) == "COOLDOWN", "channel: missing cooldown diagnosis")
	var interrupted: Dictionary = channel.interrupt(started["state"], 300)
	check(bool(interrupted["interrupted"]) and interrupted["state"]["active"].is_empty(), "channel: preparation not interrupted")
	check(not interrupted["state"]["cooldowns"].has("basic"), "channel: interrupted preparation consumed cooldown")
	advanced = channel.advance(started["state"], 400)
	check(str(advanced["commit"].get("actionId", "")) == "basic", "channel: attack commit missing")
	interrupted = channel.interrupt(advanced["state"], 400)
	check(not bool(interrupted["interrupted"]), "channel: committed effect retroactively cancelled")
	check(started["state"]["active"]["timeline"]["committed"] == false, "channel: transition mutated source snapshot")
	# Several zero-cooldown defensive items must not starve a ready attack.
	defense["cooldownMs"] = 0
	started = channel.start(channel.new_state(), [defense, attack], 0, 100, 0, 100)
	advanced = channel.advance(started["state"], 100)
	advanced = channel.advance(advanced["state"], 200)
	started = channel.start(advanced["state"], [defense, attack], 200, 100, 0, 100)
	check(str(started["action"].get("actionId", "")) == "basic", "channel: support spam starved attack")
	check(str(started["rejected"][-1].get("reason", "")) == "OFFENSE_TURN", "channel: fairness decision unexplained")
	var costly_attack: Dictionary = attack.duplicate(true)
	costly_attack["actionId"] = "costly"
	costly_attack["energyCost"] = 200.0
	var diagnostic: Dictionary = channel.start(advanced["state"], [defense, attack, costly_attack], 200, 100, 0, 100)
	check(diagnostic["rejected"].any(func(value: Dictionary) -> bool: return str(value.get("actionId", "")) == "costly" and str(value.get("reason", "")) == "ENERGY"), "channel: fairness dropped unavailable offense diagnostics")
	check(not bool(channel.advance(started["state"], 100)["ok"]), "channel: clock rewound")
	check(not bool(channel.advance(started["state"], 250)["ok"]), "channel: off-tick timestamp accepted")
	check(not bool(channel.advance({}, 0)["ok"]), "channel: incompatible snapshot accepted")
	var corrupt: Dictionary = channel.new_state()
	corrupt["active"] = {"action": {}, "timeline": {}}
	check(not bool(channel.advance(corrupt, 0)["ok"]), "channel: malformed active action reached dispatch")
	corrupt = channel.new_state()
	corrupt["cooldowns"] = {"basic": "tomorrow"}
	check(not bool(channel.start(corrupt, [attack], 0, 100, 0, 100)["ok"]), "channel: invalid saved cooldown accepted")
	corrupt = channel.new_state()
	corrupt["supportStreak"] = -1
	check(not bool(channel.advance(corrupt, 0)["ok"]), "channel: invalid fairness state accepted")
	return failure_count == 0
