class_name StateHash
extends RefCounted

const UINT32_MASK: int = 0xffffffff

func hash_string(value: String) -> String:
	var hash_value: int = 2166136261
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint <= 0xffff:
			hash_value = _hash_code_unit(hash_value, codepoint)
		else:
			var scalar: int = codepoint - 0x10000
			hash_value = _hash_code_unit(hash_value, 0xd800 + (scalar >> 10))
			hash_value = _hash_code_unit(hash_value, 0xdc00 + (scalar & 0x3ff))
	return "%08x" % hash_value

func stable_stringify(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value), "", true, true)

func state_hash(value: Variant) -> String:
	return hash_string(stable_stringify(value))

func _hash_code_unit(current: int, code_unit: int) -> int:
	return ((current ^ code_unit) * 16777619) & UINT32_MASK

func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var result: Dictionary = {}
		for key: Variant in keys:
			result[key] = _canonicalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_canonicalize(entry))
		return result
	if value is float:
		var number: float = float(value)
		if is_nan(number) or is_inf(number):
			return null
		if number == 0.0:
			return 0
		if number == floor(number) and absf(number) <= 9007199254740991.0:
			return int(number)
	return value
