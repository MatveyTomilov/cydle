extends SceneTree

const TEST_PATHS: Array[String] = [
	"res://tests/test_app_boot.gd",
	"res://tests/golden/rng_golden_test.gd",
	"res://tests/golden/save_repository_test.gd",
	"res://tests/golden/game_save_state_test.gd",
	"res://tests/golden/initial_save_factory_test.gd",
	"res://tests/golden/sector_generator_test.gd",
	"res://tests/golden/game_session_test.gd",
	"res://tests/golden/item_catalog_test.gd",
	"res://tests/golden/item_factory_test.gd",
	"res://tests/golden/build_resolver_test.gd",
	"res://tests/golden/enemy_catalog_test.gd",
	"res://tests/golden/combat_factory_test.gd",
	"res://tests/golden/combat_step_test.gd",
	"res://tests/golden/status_catalog_test.gd",
	"res://tests/golden/dot_status_replay_test.gd",
	"res://tests/golden/status_effect_replay_test.gd",
	"res://tests/golden/weapon_packet_replay_test.gd",
	"res://tests/golden/main_skill_replay_test.gd",
	"res://tests/golden/math_golden_test.gd",
	"res://tests/golden/stats_golden_test.gd",
	"res://tests/golden/math_differential_test.gd",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var passed: int = 0
	var failed: int = 0
	var assertions: int = 0
	var assertion_failures: int = 0
	for test_path: String in TEST_PATHS:
		var test_script: Script = load(test_path) as Script
		if test_script == null:
			push_error("Cannot load test script: %s" % test_path)
			failed += 1
			continue
		var test_case: RefCounted = test_script.new() as RefCounted
		if test_case == null:
			push_error("Test does not extend RefCounted: %s" % test_path)
			failed += 1
			continue
		var test_result: Variant = await test_case.call("run", self)
		assertions += int(test_case.get("assertion_count"))
		assertion_failures += int(test_case.get("failure_count"))
		if test_result is bool and test_result and int(test_case.get("failure_count")) == 0:
			passed += 1
			print("PASS %s" % test_path.get_file().get_basename())
		else:
			failed += 1
			if int(test_case.get("failure_count")) == 0:
				assertion_failures += 1
	print("CYDLE headless tests: %d tests passed, %d tests failed; %d assertions, %d assertion failures" % [passed, failed, assertions, assertion_failures])
	quit(1 if failed > 0 else 0)
