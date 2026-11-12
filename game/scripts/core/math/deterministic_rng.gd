class_name DeterministicRng
extends RefCounted

const UINT32_MASK: int = 0xffffffff
const UINT32_RANGE: float = 4294967296.0

var stream: String = ""
var _state: Array[int] = [0, 0, 0, 0]
var calls: int = 0

func seed(stream_name: String, seed_value: Variant) -> void:
	stream = stream_name
	var base: int = int(seed_value) & UINT32_MASK if seed_value is int or seed_value is float else _hash_seed(str(seed_value))
	_state = [
		(base ^ _hash_seed(stream + ":a")) & UINT32_MASK,
		(base ^ _hash_seed(stream + ":b")) & UINT32_MASK,
		(base ^ _hash_seed(stream + ":c")) & UINT32_MASK,
		(base ^ _hash_seed(stream + ":d")) & UINT32_MASK,
	]
	calls = 0
	for _index: int in range(12):
		next_float()
	calls = 0

func restore(serialized: Dictionary) -> bool:
	if not serialized.has("stream") or not serialized.has("state") or not serialized.has("calls"):
		return false
	var state_value: Variant = serialized["state"]
	if not state_value is Array or state_value.size() != 4:
		return false
	var restored_state: Array[int] = []
	for word: Variant in state_value:
		if not word is int and not word is float:
			return false
		restored_state.append(int(word) & UINT32_MASK)
	var calls_value: Variant = serialized["calls"]
	if (not calls_value is int and not calls_value is float) or not is_finite(float(calls_value)) or float(calls_value) < 0.0 or float(calls_value) != floor(float(calls_value)):
		return false
	stream = str(serialized["stream"])
	_state = restored_state
	calls = int(calls_value)
	return true

func serialize() -> Dictionary:
	return {"stream": stream, "state": _state.duplicate(), "calls": calls}

func clone() -> DeterministicRng:
	var copy: DeterministicRng = DeterministicRng.new()
	copy.restore(serialize())
	return copy

func next_float() -> float:
	calls += 1
	var a: int = _state[0]
	var b: int = _state[1]
	var c: int = _state[2]
	var d: int = _state[3]
	var value: int = (a + b + d) & UINT32_MASK
	d = (d + 1) & UINT32_MASK
	a = (b ^ (b >> 9)) & UINT32_MASK
	b = (c + (c << 3)) & UINT32_MASK
	c = ((c << 21) | (c >> 11)) & UINT32_MASK
	c = (c + value) & UINT32_MASK
	_state = [a, b, c, d]
	return float(value) / UINT32_RANGE

func next_uint32() -> int:
	return int(floor(next_float() * UINT32_RANGE)) & UINT32_MASK

func int_range(minimum: int, maximum: int) -> int:
	if maximum < minimum:
		return minimum
	return minimum + int(floor(next_float() * float(maximum - minimum + 1)))

func range_float(minimum: float, maximum: float) -> float:
	return minimum + next_float() * (maximum - minimum)

func chance(probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return next_float() < probability

func pick(values: Array) -> Variant:
	if values.is_empty():
		push_error("DeterministicRng.pick: empty array")
		return null
	return values[int(floor(next_float() * values.size()))]

func weighted(entries: Array[Dictionary]) -> Variant:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += maxf(0.0, float(entry.get("weight", 0.0)))
	if total <= 0.0:
		return entries[0].get("item") if not entries.is_empty() else null
	var roll: float = next_float() * total
	for entry: Dictionary in entries:
		roll -= maxf(0.0, float(entry.get("weight", 0.0)))
		if roll <= 0.0:
			return entry.get("item")
	return entries[entries.size() - 1].get("item") if not entries.is_empty() else null

func shuffle(values: Array) -> Array:
	var result: Array = values.duplicate()
	for index: int in range(result.size() - 1, 0, -1):
		var swap_index: int = int(floor(next_float() * (index + 1)))
		var temporary: Variant = result[index]
		result[index] = result[swap_index]
		result[swap_index] = temporary
	return result

func _hash_seed(value: String) -> int:
	var hash_value: int = 2166136261
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint <= 0xffff:
			hash_value = ((hash_value ^ codepoint) * 16777619) & UINT32_MASK
		else:
			var scalar: int = codepoint - 0x10000
			var high_surrogate: int = 0xd800 + (scalar >> 10)
			var low_surrogate: int = 0xdc00 + (scalar & 0x3ff)
			hash_value = ((hash_value ^ high_surrogate) * 16777619) & UINT32_MASK
			hash_value = ((hash_value ^ low_surrogate) * 16777619) & UINT32_MASK
	return hash_value
