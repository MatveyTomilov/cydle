class_name SectorGenerator
extends RefCounted

const BASE_WIDTHS: Array[int] = [1, 2, 3, 3, 2, 1]
const CAMPAIGN_BIOMES: Dictionary = {
	1: "B01", 2: "B03", 3: "B02", 4: "B01",
	5: "B04", 6: "B03", 7: "B05", 8: "B04",
	9: "B06", 10: "B02", 11: "B05", 12: "B06",
}

var _enemies: EnemyCatalog = EnemyCatalog.new()
var _events: EventCatalog = EventCatalog.new()
var _loaded: bool = false
var _load_error: String = ""

func campaign_biome(depth: int, seed_value: String, previous_biomes: Array[String] = []) -> String:
	if CAMPAIGN_BIOMES.has(depth):
		return str(CAMPAIGN_BIOMES[depth])
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("world:biome", seed_value)
	var biomes: Array[String] = ["B01", "B02", "B03", "B04", "B05", "B06"]
	var selected: String = biomes[rng.int_range(0, biomes.size() - 1)]
	if previous_biomes.size() >= 2 and previous_biomes[-1] == previous_biomes[-2] and selected == previous_biomes[-1]:
		var reroll: Array[String] = biomes.filter(func(value: String) -> bool: return value != previous_biomes[-1])
		selected = str(rng.pick(reroll))
	return selected

func generate(seed_value: String, depth: int, biome: String, tutorial: bool = false, wanted: float = 0.0, used_event_ids: Array[String] = []) -> Dictionary:
	if seed_value.strip_edges().is_empty() or depth < 1:
		return {"ok": false, "graph": {}, "error": "Для маршрута требуется seed и положительная глубина."}
	if not ["B01", "B02", "B03", "B04", "B05", "B06"].has(biome):
		return {"ok": false, "graph": {}, "error": "Неизвестный биом %s." % biome}
	if not _loaded:
		var loaded: Dictionary = _enemies.load_catalog()
		_loaded = true
		_load_error = str(loaded.get("error", "")) if not bool(loaded.get("ok", false)) else ""
	if not _load_error.is_empty():
		return {"ok": false, "graph": {}, "error": _load_error}
	var events_loaded: Dictionary = _events.load_catalog()
	if not bool(events_loaded.get("ok", false)):
		return {"ok": false, "graph": {}, "error": str(events_loaded.get("error", "Каталог событий недоступен."))}
	var rng: DeterministicRng = DeterministicRng.new()
	rng.seed("world", seed_value)
	var widths: Array[int] = BASE_WIDTHS.duplicate()
	var is_tutorial: bool = depth == 1 and tutorial
	if not is_tutorial:
		widths[3] += rng.int_range(0, 3)
	var layers: Array = []
	for layer: int in range(widths.size()):
		var nodes: Array[Dictionary] = []
		for index: int in range(widths[layer]):
			var node_type: String = "COMBAT"
			var fixed_enemies: Array[String] = []
			var extras: Dictionary = {}
			if is_tutorial and layer == 0:
				node_type = "COMBAT"
				fixed_enemies = ["E01"]
			elif is_tutorial and layer == 1:
				node_type = "CACHE"
				extras["prototypeChoices"] = ["IMP_HEAT", "IMP_VIRUS", "IMP_SHIELD"]
			elif is_tutorial and layer == 2:
				node_type = "COMBAT"
				fixed_enemies = ["E01", "E02"]
			elif layer == 5:
				node_type = "BOSS" if depth % 4 == 0 else "CHECKPOINT"
			elif layer == 0 or layer == 2:
				node_type = "COMBAT"
				fixed_enemies = [_enemy_for(biome, depth, rng)]
			elif layer == 4:
				node_type = "REPAIR" if index % 2 == 0 else "FUEL"
			elif not is_tutorial and layer == 3 and index == 0:
				var available_events: Array[String] = _events.available_ids(used_event_ids)
				if not available_events.is_empty():
					node_type = "EVENT"
					extras["eventId"] = str(rng.pick(available_events))
				else:
					node_type = "CACHE"
			elif not is_tutorial and layer == 1 and index == 0 and rng.chance(0.22):
				node_type = "ELITE"
			elif not is_tutorial and biome == "B06" and layer == 1 and index == 1:
				# The Zero Zone always contains its defining encounter; this is the dangerous
				# route branch the B06 quest and TECH contracts can actually target.
				node_type = "ANOMALY"
			elif not is_tutorial and layer == 1 and index == 1 and wanted >= 50.0 and rng.chance(0.25):
				node_type = "BOUNTY"
			elif layer == 3 and index == 1:
				node_type = "SHOP"
			elif is_tutorial and layer == 3:
				node_type = ["REPAIR", "FUEL", "COMBAT"][index]
			elif is_tutorial and layer == 4:
				node_type = "FUEL" if index == 0 else "REPAIR"
			else:
				node_type = str(rng.pick(["COMBAT", "REPAIR", "FUEL", "CACHE"]))
			nodes.append(_create_node(seed_value, depth, biome, layer, index, node_type, fixed_enemies, rng, extras))
		layers.append(nodes)
	var edges: Array[Dictionary] = _link_layers(layers, rng)
	return {"ok": true, "graph": {"seed": seed_value, "depth": depth, "biome": biome, "startNodeId": "START", "layers": layers, "edges": edges}, "error": ""}

func reachable_nodes(graph: Dictionary, current_node_id: String) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for layer_value: Variant in graph.get("layers", []):
		for node: Dictionary in layer_value:
			by_id[str(node.get("id", ""))] = node
	var outgoing: Array[String] = []
	for edge: Dictionary in graph.get("edges", []):
		if str(edge.get("from", "")) == current_node_id:
			outgoing.append(str(edge.get("to", "")))
	outgoing.sort()
	var result: Array[Dictionary] = []
	for node_id: String in outgoing:
		if by_id.has(node_id):
			result.append(by_id[node_id])
	return result

func _create_node(seed_value: String, depth: int, biome: String, layer: int, index: int, node_type: String, fixed_enemies: Array[String], rng: DeterministicRng, extras: Dictionary) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for template_id: String in fixed_enemies:
		enemies.append({"templateId": template_id})
	if node_type == "COMBAT" and enemies.is_empty():
		enemies.append({"templateId": _enemy_for(biome, depth, rng)})
	elif node_type == "ELITE":
		var elite_enemy: String = fixed_enemies[0] if not fixed_enemies.is_empty() else _enemy_for(biome, depth, rng)
		enemies = [{"templateId": elite_enemy, "elite": str(rng.pick(["EL_SHIELD", "EL_FAST", "EL_VIRUS", "EL_ANTI_DRONE", "EL_PEN", "EL_SPLIT"]))}]
	elif node_type == "BOUNTY":
		var bounty_enemy: String = fixed_enemies[0] if not fixed_enemies.is_empty() else _enemy_for(biome, depth, rng)
		enemies = [{"templateId": bounty_enemy, "elite": "EL_PEN"}]
	elif node_type == "ANOMALY":
		var anomaly_enemy: String = fixed_enemies[0] if not fixed_enemies.is_empty() else _enemy_for(biome, depth, rng)
		var protocol: String = str(rng.pick(["EL_SHIELD", "EL_FAST", "EL_VIRUS", "EL_ANTI_DRONE", "EL_PEN", "EL_SPLIT"]))
		enemies = [{"templateId": anomaly_enemy, "elite": protocol}]
		extras["anomalyProtocol"] = protocol
	elif node_type == "BOSS":
		enemies = [{"templateId": _boss_for_depth(depth)}]
	var threat: String = "boss" if node_type == "BOSS" else "high" if node_type in ["ELITE", "BOUNTY", "ANOMALY"] else "medium" if node_type in ["COMBAT", "EVENT", "QUEST"] else "low"
	var loot_hint: String = "аномальная добыча" if node_type == "ANOMALY" else "добыча после боя" if node_type in ["COMBAT", "ELITE", "BOUNTY", "BOSS"] else "три прототипа" if node_type == "CACHE" else "восстановление ресурсов" if node_type in ["REPAIR", "FUEL"] else "5 товаров по биому" if node_type == "SHOP" else "неизвестно"
	var node: Dictionary = {
		"id": "d%d-l%d-n%d-%s" % [depth, layer, index, seed_value.substr(0, mini(5, seed_value.length()))],
		"layer": layer, "type": node_type, "threat": threat, "enemies": enemies,
		"revealLevel": 1, "lootHint": loot_hint,
	}
	for key: Variant in extras.keys():
		node[str(key)] = extras[key]
	return node

func _enemy_for(biome: String, depth: int, rng: DeterministicRng) -> String:
	var pool: Array[String] = []
	for enemy_value: Variant in _enemies.enemies.values():
		var enemy: Dictionary = enemy_value
		if int(enemy.get("unlockDepth", 1)) <= depth and (enemy.get("biomes", []) as Array).has(biome):
			pool.append(str(enemy["id"]))
	pool.sort()
	return str(rng.pick(pool)) if not pool.is_empty() else "E01"

func _boss_for_depth(depth: int) -> String:
	var eligible: Array[Dictionary] = []
	for boss_value: Variant in _enemies.bosses.values():
		var boss: Dictionary = boss_value
		if int(boss.get("unlockDepth", 1)) <= depth:
			eligible.append(boss)
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_depth: int = int(left.get("unlockDepth", 0))
			var right_depth: int = int(right.get("unlockDepth", 0))
			return left_depth < right_depth if left_depth != right_depth else str(left.get("id", "")) < str(right.get("id", "")))
	return str(eligible.back().get("id", "CORE_12")) if not eligible.is_empty() else "CORE_12"

func _link_layers(layers: Array, rng: DeterministicRng) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for node: Dictionary in layers[0]:
		edges.append({"from": "START", "to": node["id"], "fromLayer": -1, "toLayer": 0, "fuelCost": 1})
	for layer_index: int in range(layers.size() - 1):
		var from_nodes: Array = layers[layer_index]
		var to_nodes: Array = layers[layer_index + 1]
		for destination_index: int in range(to_nodes.size()):
			var source_index: int = int(floor(float(destination_index * from_nodes.size()) / float(to_nodes.size())))
			_add_edge(edges, from_nodes[source_index], to_nodes[destination_index], layer_index, rng)
		for source_index: int in range(from_nodes.size()):
			var destination_index: int = int(floor(float(source_index * to_nodes.size()) / float(from_nodes.size())))
			_add_edge(edges, from_nodes[source_index], to_nodes[destination_index], layer_index, rng)
			if to_nodes.size() > 1:
				_add_edge(edges, from_nodes[source_index], to_nodes[(destination_index + 1) % to_nodes.size()], layer_index, rng)
	return edges

func _add_edge(edges: Array[Dictionary], from_node: Dictionary, to_node: Dictionary, from_layer: int, rng: DeterministicRng) -> void:
	for existing: Dictionary in edges:
		if str(existing["from"]) == str(from_node["id"]) and str(existing["to"]) == str(to_node["id"]):
			return
	edges.append({
		"from": from_node["id"], "to": to_node["id"], "fromLayer": from_layer, "toLayer": from_layer + 1,
		"fuelCost": 2 if from_layer >= 2 and rng.chance(0.08) else 1,
	})
