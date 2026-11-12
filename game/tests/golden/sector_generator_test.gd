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
		var expected_boss: String = "BOSS_A" if depth == 4 else "BOSS_B" if depth == 8 else "BOSS_CORE"
		check(str(boss_graph["layers"][5][0]["enemies"][0].get("templateId", "")) == expected_boss, "sector_generator: campaign depth %d selected the wrong authored boss" % depth)
	var endgame_boss: Dictionary = generator.generate("endgame-boss-seed", 16, "B04", false, 0.0, [], [], ["BOSS_B"])["graph"]["layers"][5][0]
	var repeated_endgame_boss: Dictionary = generator.generate("endgame-boss-seed", 16, "B04", false, 0.0, [], [], ["BOSS_B"])["graph"]["layers"][5][0]
	check(str(endgame_boss.get("enemies", [])[0].get("templateId", "")) == "BOSS_C" and endgame_boss == repeated_endgame_boss, "sector_generator: endgame boss selection ignored biome, previous boss, or deterministic seed")
	check(generator.campaign_biome(13, "endgame-repeat-seed", ["B06", "B06"]) != "B06", "sector_generator: endgame allowed three identical biomes in sequence")
	var campaign_graph: Dictionary = generator.generate("event-seed", 2, "B03", false)["graph"]
	var event_node: Dictionary = campaign_graph["layers"][3][0]
	check(str(event_node.get("type", "")) == "EVENT", "sector_generator: canonical layer-three event node is missing")
	check(EventCatalog.new().get_event(str(event_node.get("eventId", ""))).size() > 0, "sector_generator: generated event id is not in the event catalog")
	var zero_zone: Dictionary = generator.generate("zero-zone-seed", 9, "B06", false)["graph"]
	var anomaly: Dictionary = zero_zone["layers"][1][1]
	check(str(anomaly.get("type", "")) == "ANOMALY", "sector_generator: B06 did not generate its guaranteed anomaly route")
	var anomaly_protocol: String = str(anomaly.get("anomalyProtocol", ""))
	var anomaly_enemies: Array = anomaly.get("enemies", [])
	check(["EL_SHIELD", "EL_FAST", "EL_VIRUS", "EL_ANTI_DRONE", "EL_PEN", "EL_SPLIT"].has(anomaly_protocol), "sector_generator: anomaly protocol is outside the existing elite modifier catalog")
	check(anomaly_enemies.size() == 1 and str(anomaly_enemies[0].get("elite", "")) == anomaly_protocol, "sector_generator: anomaly protocol is not applied to its combat encounter")
	check(str(anomaly.get("threat", "")) == "high" and str(anomaly.get("lootHint", "")) == "аномальная добыча", "sector_generator: anomaly route risk and reward band are missing")
	var ordinary_graph: Dictionary = generator.generate("ordinary-sector-seed", 8, "B04", false)["graph"]
	var ordinary_anomaly_count: int = 0
	for layer_value: Variant in ordinary_graph.get("layers", []):
		for node: Dictionary in layer_value:
			if str(node.get("type", "")) == "ANOMALY": ordinary_anomaly_count += 1
	check(ordinary_anomaly_count == 0, "sector_generator: a Zero Zone anomaly appeared outside B06")
	_check_combat_rosters(generator)
	var invalid: Dictionary = generator.generate("bad-biome", 1, "B99")
	check(not bool(invalid.get("ok", true)), "sector_generator: invalid biome was accepted")
	_check_graph(graph)
	return failure_count == 0

func _check_combat_rosters(generator: SectorGenerator) -> void:
	var enemy_catalog: EnemyCatalog = EnemyCatalog.new()
	if not check(bool(enemy_catalog.load_catalog().get("ok", false)), "sector_generator: enemy templates could not load for roster verification"):
		return
	var depth_cases: Array[Dictionary] = [
		{"depth": 1, "biome": "B01"}, {"depth": 2, "biome": "B03"}, {"depth": 3, "biome": "B02"},
		{"depth": 4, "biome": "B01"}, {"depth": 5, "biome": "B04"}, {"depth": 6, "biome": "B03"},
		{"depth": 7, "biome": "B05"}, {"depth": 8, "biome": "B04"}, {"depth": 9, "biome": "B06"},
		{"depth": 10, "biome": "B02"}, {"depth": 11, "biome": "B05"}, {"depth": 12, "biome": "B06"},
		{"depth": 20, "biome": "B01"}, {"depth": 20, "biome": "B02"}, {"depth": 20, "biome": "B03"},
		{"depth": 20, "biome": "B04"}, {"depth": 20, "biome": "B05"}, {"depth": 20, "biome": "B06"},
	]
	var multi_unit_seen: bool = false
	for encounter_case: Dictionary in depth_cases:
		var depth: int = int(encounter_case["depth"])
		var biome: String = str(encounter_case["biome"])
		var generated: Dictionary = generator.generate("roster:%s:%d" % [biome, depth], depth, biome, false)
		if not check(bool(generated.get("ok", false)), "sector_generator: normal roster graph failed for %s d%d" % [biome, depth]):
			continue
		var budget: int = mini(6, 2 + floori(float(depth) / 4.0))
		for layer: Array in generated["graph"].get("layers", []):
			for node: Dictionary in layer:
				if str(node.get("type", "")) != "COMBAT":
					continue
				var enemies: Array = node.get("enemies", [])
				var threat_total: int = 0
				var counted_templates: Dictionary = {}
				var swarm_members: int = 0
				check(not enemies.is_empty() and enemies.size() <= 6, "sector_generator: combat roster size is outside 1..6 at %s d%d" % [biome, depth])
				if enemies.size() > 1:
					multi_unit_seen = true
				for enemy_spec: Dictionary in enemies:
					var template_id: String = str(enemy_spec.get("templateId", ""))
					var template: Dictionary = enemy_catalog.get_template(template_id)
					check(not template.is_empty() and int(template.get("unlockDepth", 999)) <= depth and (template.get("biomes", []) as Array).has(biome), "sector_generator: roster selected a locked or biome-incompatible enemy %s in %s d%d" % [template_id, biome, depth])
					if template_id == "E20":
						swarm_members += 1
						if not counted_templates.has("E20"):
							threat_total += int(template.get("threatUnits", 0))
							counted_templates["E20"] = true
					elif not counted_templates.has(template_id):
						threat_total += int(template.get("threatUnits", 0))
						counted_templates[template_id] = true
				check(threat_total <= budget, "sector_generator: combat roster exceeded %d threat units in %s d%d" % [budget, biome, depth])
				if swarm_members > 0:
					check(swarm_members >= 2 and swarm_members <= 4, "sector_generator: E20 was not generated as a bounded 2..4 unit swarm")
				if depth == 1:
					check(enemies.size() <= 2 and enemies.all(func(enemy_spec: Dictionary) -> bool: return str(enemy_spec.get("templateId", "")).begins_with("E0")), "sector_generator: d1 roster exceeded its starter enemy clamp")
	check(multi_unit_seen, "sector_generator: campaign combat routes still contain only single-enemy encounters")

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
