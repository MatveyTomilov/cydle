extends "res://tests/test_case.gd"

const RNG_PATH: String = "res://scripts/core/math/deterministic_rng.gd"
const RNG_BANK_PATH: String = "res://scripts/core/math/rng_bank.gd"
const STATE_HASH_PATH: String = "res://scripts/core/math/state_hash.gd"

func run(_tree: SceneTree) -> bool:
	var rng_script: Script = load(RNG_PATH) as Script
	if not check(rng_script != null, "rng_golden: deterministic RNG implementation is missing"):
		return false
	var bank_script: Script = load(RNG_BANK_PATH) as Script
	if not check(bank_script != null, "rng_golden: RNG bank implementation is missing"):
		return false
	var hash_script: Script = load(STATE_HASH_PATH) as Script
	if not check(hash_script != null, "rng_golden: stable state hash implementation is missing"):
		return false

	var rng: Object = rng_script.new()
	rng.call("seed", "combat", "cydle-seed")
	var expected_values: Array[float] = [
		0.18552030576393008,
		0.44487419025972486,
		0.37715937104076147,
		0.9668558049015701,
		0.8933838012162596,
		0.1938039162196219,
	]
	var actual_values: Array[float] = []
	for _index: int in range(expected_values.size()):
		actual_values.append(float(rng.call("next_float")))
	check(_float_arrays_close(actual_values, expected_values), "rng_golden: sfc32 output differs from TypeScript fixture")
	var expected_serialized: Dictionary = {
		"stream": "combat",
		"state": [904430034, 687993687, 1031648248, 2116174315],
		"calls": 6,
	}
	var serialized: Dictionary = rng.call("serialize")
	check(serialized == expected_serialized, "rng_golden: serialized state differs from TypeScript fixture")

	var restored: Object = rng_script.new()
	check(bool(restored.call("restore", serialized)), "rng_golden: valid serialized state was rejected")
	var expected_continuation: Array[float] = [
		0.8634752677753568,
		0.8149877381511033,
		0.8919947799295187,
	]
	var continuation: Array[float] = []
	for _step: int in range(expected_continuation.size()):
		continuation.append(float(rng.call("next_float")))
	check(_float_arrays_close(continuation, expected_continuation), "rng_golden: post-save continuation differs from TypeScript fixture")
	check(_nearly_equal(float(restored.call("next_float")), expected_continuation[0]), "rng_golden: restored RNG did not resume at the saved call")

	var numeric_rng: Object = rng_script.new()
	numeric_rng.call("seed", "loot", 4294967297)
	var expected_numeric: Array[float] = [
		0.9168248062487692,
		0.5482574780471623,
		0.23285901686176658,
		0.5703460988588631,
	]
	var numeric_values: Array[float] = []
	for _value: int in range(expected_numeric.size()):
		numeric_values.append(float(numeric_rng.call("next_float")))
	check(_float_arrays_close(numeric_values, expected_numeric), "rng_golden: unsigned numeric seed handling differs from TypeScript")
	var unicode_seed_rng: Object = rng_script.new()
	unicode_seed_rng.call("seed", "combat", "CYDLE 🚀")
	var unicode_seed_values: Array[float] = []
	for _unicode_index: int in range(3):
		unicode_seed_values.append(float(unicode_seed_rng.call("next_float")))
	check(_float_arrays_close(unicode_seed_values, [0.996749026235193, 0.6599915497936308, 0.8968749854248017]), "rng_golden: seed hashing differs for supplementary Unicode")

	var uint_rng: Object = rng_script.new()
	uint_rng.call("seed", "sim", "uint-fixture")
	var expected_uints: Array[int] = [3020789957, 877523754, 3804794673, 930287411, 48515781]
	var actual_uints: Array[int] = []
	for _uint_index: int in range(expected_uints.size()):
		actual_uints.append(int(uint_rng.call("next_uint32")))
	check(actual_uints == expected_uints, "rng_golden: unsigned integer outputs differ from TypeScript")

	var bank: Object = bank_script.new()
	bank.call("initialize", "root")
	var keyed_a: Object = bank.call("keyed", "combat", "scenario-4")
	var keyed_b: Object = bank.call("keyed", "combat", "scenario-4")
	check(_nearly_equal(float(keyed_a.call("next_float")), 0.9664274002425373), "rng_golden: keyed stream output differs from TypeScript")
	check(_nearly_equal(float(keyed_b.call("next_float")), 0.9664274002425373), "rng_golden: repeated keyed stream is not reproducible")
	var stream_values: Array = bank.call("serialize")
	check(stream_values == [], "rng_golden: unused lazy streams should not appear in the bank snapshot")
	var combat_stream: Object = bank.call("get_stream", "combat")
	var loot_stream: Object = bank.call("get_stream", "loot")
	check(not _nearly_equal(float(combat_stream.call("next_float")), float(loot_stream.call("next_float"))), "rng_golden: named streams should be independent")
	var serialized_bank: Array = bank.call("serialize")
	check(serialized_bank == [
		{"stream": "combat", "state": [3460487246, 3890381057, 544203716, 1560980039], "calls": 1},
		{"stream": "loot", "state": [1954280397, 4030353145, 1667554947, 4250059321], "calls": 1},
	], "rng_golden: named stream snapshot differs or is not sorted")
	var restored_bank: Object = bank_script.new()
	restored_bank.call("initialize", "root", serialized_bank)
	check(restored_bank.call("serialize") == serialized_bank, "rng_golden: named stream snapshot did not round-trip")

	var hash_service: Object = hash_script.new()
	check(String(hash_service.call("hash_string", "")) == "811c9dc5", "rng_golden: FNV-1a empty string hash differs from TypeScript")
	check(String(hash_service.call("hash_string", "Привет CYDLE ⚡")) == "889695b3", "rng_golden: UTF-16 string hashing differs from TypeScript")
	check(String(hash_service.call("hash_string", "CYDLE 🚀")) == "b621cb49", "rng_golden: supplementary Unicode hashing differs from TypeScript")
	var payload: Dictionary = {"z": 2, "a": {"y": 1, "x": [true, "cy"]}}
	check(String(hash_service.call("stable_stringify", payload)) == "{\"a\":{\"x\":[true,\"cy\"],\"y\":1},\"z\":2}", "rng_golden: object keys are not recursively sorted")
	check(String(hash_service.call("state_hash", payload)) == "0845ab78", "rng_golden: nested payload hash differs from TypeScript")
	check(String(hash_service.call("state_hash", {"faction": "Протокол Эхо", "label": "Привет CYDLE ⚡", "list": [1, 2]})) == "ddf1d6c0", "rng_golden: localized save payload hash differs from TypeScript")
	return failure_count == 0

func _float_arrays_close(actual: Array[float], expected: Array[float]) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in range(actual.size()):
		if not _nearly_equal(actual[index], expected[index]):
			return false
	return true

func _nearly_equal(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= 0.000000000000001
