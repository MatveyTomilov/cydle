extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var duel: AutobattleV2Duel = AutobattleV2Duel.new()
	var initial: Dictionary = duel.new_duel("v2-duel-heat-001")
	if not check(not initial.is_empty(), "v2_duel: initial state was rejected"):
		return false
	check(str(initial.get("rulesVersion", "")).begins_with("cydle-combat-2"), "v2_duel: wrong combat version")
	check(not initial.has("tactics"), "v2_duel: player tactics leaked into versioned V2 state")
	var initial_hash: String = duel.state_hash(initial)
	var one_tick: Dictionary = duel.step(initial)
	if not check(bool(one_tick.get("ok", false)), "v2_duel: first step failed"):
		return false
	check(int(one_tick["state"].get("timeMs", 0)) == 100, "v2_duel: fixed tick did not advance 100ms")
	check(str(one_tick["state"].get("activeAction", {}).get("actionId", "")) == "ARC-9:basic", "v2_duel: ARC-9 was not started automatically")
	check(duel.state_hash(initial) == initial_hash, "v2_duel: step mutated its input snapshot")
	var first: Dictionary = duel.run_until(initial, 350)
	var second: Dictionary = duel.run_until(initial, 350)
	if not check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "v2_duel: repeated replay failed"):
		return false
	var final_state: Dictionary = first["state"]
	check(str(first.get("stateHash", "")) == str(second.get("stateHash", "")), "v2_duel: same seed produced different final state hash")
	check(int(final_state.get("timeMs", 0)) > 0, "v2_duel: simulation never advanced")
	check(float(final_state.get("metrics", {}).get("operatorDamage", 0.0)) > 0.0, "v2_duel: no actual damage dealt")
	check(float(final_state.get("metrics", {}).get("operatorHits", 0)) > 0.0, "v2_duel: no ARC-9 attacks connected")
	check(int(final_state.get("metrics", {}).get("ventUses", 0)) >= 1, "v2_duel: authored Heat>=85 Vent did not activate")
	check(float(final_state.get("metrics", {}).get("shieldFromVent", 0.0)) > 0.0, "v2_duel: Heat-to-Shield synergy did not convert heat")
	var seen_prepare: bool = false
	var seen_damage_trace: bool = false
	var seen_vent: bool = false
	for event: Dictionary in final_state.get("log", []):
		if str(event.get("kind", "")) == "ACTION_PREPARE" and str(event.get("actionId", "")) == "ARC-9:basic":
			seen_prepare = true
		if str(event.get("kind", "")) == "ATTACK_COMMIT" and bool(event.get("hit", false)):
			seen_damage_trace = seen_damage_trace or (event.get("mitigationTrace", {}) is Dictionary and not event.get("mitigationTrace", {}).is_empty())
		if str(event.get("kind", "")) == "HEAT_VENT" and str(event.get("reason", "")) == "AUTHORED_HEAT_AT_LEAST_85":
			seen_vent = true
	check(seen_prepare, "v2_duel: missing action preparation")
	check(seen_damage_trace, "v2_duel: damage event omitted canonical mitigation trace")
	check(seen_vent, "v2_duel: Vent did not explain its authored trigger")

	var first_half: Dictionary = duel.run_until(initial, 175)
	var resumed: Dictionary = duel.run_until(first_half.get("state", {}), 175)
	check(bool(resumed.get("ok", false)), "v2_duel: snapshot resume failed")
	if bool(resumed.get("ok", false)):
		check(str(resumed.get("stateHash", "")) == str(first.get("stateHash", "")), "v2_duel: snapshot resume diverged from uninterrupted run")
	var incompatible: Dictionary = initial.duplicate(true)
	incompatible["rulesVersion"] = "cydle-combat-1.0"
	var rejected: Dictionary = duel.step(incompatible)
	check(not bool(rejected.get("ok", true)) and str(rejected.get("error", "")) == "INCOMPATIBLE_COMBAT_VERSION",
		"v2_duel: V1 save could enter V2 without migration")
	var tank: Dictionary = duel.run_until(duel.new_duel("v2-duel-heat-001", 900.0, 200.0), 100)
	var normal: Dictionary = duel.run_until(initial, 100)
	check(float(tank.get("state", {}).get("metrics", {}).get("operatorDamage", 0.0)) < float(normal.get("state", {}).get("metrics", {}).get("operatorDamage", 0.0)),
		"v2_duel: canonical armor mitigation is not effective")
	return failure_count == 0
