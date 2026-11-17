class_name RngBank
extends RefCounted

var root_seed: String = ""
var _streams: Dictionary = {}

func initialize(seed_value: Variant, serialized_streams: Array = []) -> void:
	root_seed = str(seed_value)
	_streams.clear()
	for serialized_value: Variant in serialized_streams:
		if not serialized_value is Dictionary:
			continue
		var rng: DeterministicRng = DeterministicRng.new()
		if rng.restore(serialized_value):
			_streams[rng.stream] = rng

func get_stream(stream_name: String) -> DeterministicRng:
	if not _streams.has(stream_name):
		var rng: DeterministicRng = DeterministicRng.new()
		rng.seed(stream_name, root_seed)
		_streams[stream_name] = rng
	return _streams[stream_name] as DeterministicRng

func keyed(stream_name: String, key: String) -> DeterministicRng:
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("%s:%s" % [stream_name, key], root_seed)
	return rng

func serialize() -> Array[Dictionary]:
	var names: Array[String] = []
	for stream_name: Variant in _streams.keys():
		names.append(str(stream_name))
	names.sort()
	var result: Array[Dictionary] = []
	for stream_name: String in names:
		var rng: DeterministicRng = _streams[stream_name] as DeterministicRng
		result.append(rng.serialize())
	return result

func clone() -> RngBank:
	var copy: RngBank = RngBank.new()
	copy.initialize(root_seed, serialize())
	return copy
