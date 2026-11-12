extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var generator: SectorGenerator = SectorGenerator.new()
	var first: Dictionary = generator.generate("sector-seed-01", 1, "B01", true)
	var repeat: Dictionary = generator.generate("sector-seed-01", 1, "B01", true)
	if not check(bool(first.get("ok", false)), "sector_generator: tutorial sector failed: %s" % first.get("error", "")):
		return false
	check(first["graph"] == repeat["graph"], "sector_generator: same seed generated a different graph")
	var graph: Dictionary = first["graph"]
	check(graph["layers"].size() == 6, "sector_generator: sector does not have six layers")
	check((graph["layers"] as Array)[0].size() == 1 and (graph["layers"] as Array)[5].size() == 1, "sector_generator: start/end layer widths are incorrect")
	check(str(graph["layers"][0][0]["type"]) == "COMBAT", "sector_generator: tutorial starts without combat")
	check(str(graph["layers"][1][0]["type"]) == "CACHE", "sector_generator: tutorial cache is missing")
	check(str(graph["layers"][1][0]["prototypeChoices"][0]) == "IMP_HEAT", "sector_generator: guaranteed prototype choices are incorrect")
	for depth: int in [4, 8, 12]:
		var boss_graph: Dictionary = generator.generate("boss-seed-%d" % depth, depth, generator.campaign_biome(depth, "boss"), false)["graph"]
		check(str(boss_graph["layers"][5][0]["type"]) == "BOSS", "sector_generator: depth %d has no boss endpoint" % depth)
	check(generator.campaign_biome(13, "endgame-repeat-seed", ["B06", "B06"]) != "B06", "sector_generator: endgame allowed three identical biomes in sequence")
	var campaign_graph: Dictionary = generator.generate("event-seed", 2, "B03", false)["graph"]
	var event_node: Dictionary = campaign_graph["layers"][3][0]
	check(str(event_node.get("type", "")) == "EVENT", "sector_generator: canonical layer-three event node is missing")
	check(EventCatalog.new().get_event(str(event_node.get("eventId", ""))).size() > 0, "sector_generator: generated event id is not in the event catalog")
	var invalid: Dictionary = generator.generate("bad-biome", 1, "B99")
	check(not bool(invalid.get("ok", true)), "sector_generator: invalid biome was accepted")
	_check_graph(graph)
	return failure_count == 0

func _check_graph(graph: Dictionary) -> void:
	var nodes: Dictionary = {}
	for layer_value: Variant in graph["layers"]:
		for node: Dictionary in layer_value:
			nodes[str(node["id"])] = node
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	for edge: Dictionary in graph["edges"]:
		var from_id: String = str(edge["from"])
		var to_id: String = str(edge["to"])
		outgoing[from_id] = int(outgoing.get(from_id, 0)) + 1
		incoming[to_id] = int(incoming.get(to_id, 0)) + 1
		check(int(edge["toLayer"]) == int(edge["fromLayer"]) + 1, "sector_generator: edge skips a layer")
		check(int(edge["fuelCost"]) in [1, 2], "sector_generator: invalid edge fuel cost")
	check(int(outgoing.get("START", 0)) > 0, "sector_generator: start has no outgoing edge")
	var seen: Dictionary = {}
	var queue: Array[String] = ["START"]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for edge: Dictionary in graph["edges"]:
			if str(edge["from"]) == current and not seen.has(str(edge["to"])):
				seen[str(edge["to"])] = true
				queue.append(str(edge["to"]))
	for node_id: Variant in nodes.keys():
		check(incoming.has(str(node_id)), "sector_generator: node has no incoming path")
		check(seen.has(str(node_id)), "sector_generator: node is unreachable")
	for node_id: Variant in outgoing.keys():
		check(int(outgoing[node_id]) <= 3, "sector_generator: node has more than three exits")
	for last_node: Dictionary in graph["layers"][5]:
		check(not outgoing.has(str(last_node["id"])), "sector_generator: final layer has outgoing edges")
