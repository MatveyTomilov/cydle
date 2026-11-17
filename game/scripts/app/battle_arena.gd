class_name BattleArena
extends Control

const COLOR_BG: Color = Color("0b111a")
const COLOR_SURFACE: Color = Color("121c29")
const COLOR_ELEVATED: Color = Color("1b293b")
const COLOR_BORDER: Color = Color("344357")
const COLOR_HP: Color = Color("4cc99b")
const COLOR_SHIELD: Color = Color("55b6f0")
const COLOR_DANGER: Color = Color("ed6767")
const COLOR_WARNING: Color = Color("e7bc65")
const COLOR_ACCENT: Color = Color("58a6ff")
const COLOR_TEXT: Color = Color("e4e8e8")
const COLOR_MUTED: Color = Color("a4afb9")
const COLOR_UNIQUE: Color = Color("c38ef2")

const OPERATOR_HEIGHT: float = 104.0
const DRONE_HEIGHT: float = 48.0
const ENEMY_HEIGHT: float = 96.0
const BOSS_HEIGHT: float = 176.0
const MAX_EFFECTS: int = 120
const BEAST_TEMPLATES: Array[String] = ["E14", "E20"]

var _combat: CombatState
var _reduced_motion: bool = false
var _positions: Dictionary = {}
var _effects: Array[Dictionary] = []
var _recoil: Dictionary = {}
var _hit_flash: Dictionary = {}
var _shield_flash: Dictionary = {}
var _clock: float = 0.0
var _placeholders: Dictionary = {}
var _font: Font = ThemeDB.fallback_font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(640, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_placeholders = _load_placeholders()
	clip_contents = true

func setup(combat: CombatState, reduced_motion: bool) -> void:
	_reduced_motion = reduced_motion
	sync(combat)

func sync(combat: CombatState) -> void:
	_combat = combat
	_layout()
	queue_redraw()

func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	queue_redraw()

## Visual reactions are derived from the simulator's own event log; the arena never
## writes combat state, so rendering cannot change an outcome.
func consume(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		_spawn(str(event.get("kind", "")), event)
	if _effects.size() > MAX_EFFECTS:
		_effects = _effects.slice(_effects.size() - MAX_EFFECTS)
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	var expired: Array[Dictionary] = []
	for effect: Dictionary in _effects:
		effect["age"] = float(effect.get("age", 0.0)) + delta
		if float(effect["age"]) >= float(effect.get("ttl", 0.0)):
			expired.append(effect)
	for effect: Dictionary in expired:
		_effects.erase(effect)
	for table: Dictionary in [_recoil, _hit_flash, _shield_flash]:
		for key: String in table.keys():
			table[key] = maxf(0.0, float(table[key]) - delta)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()

func _layout() -> void:
	_positions.clear()
	if _combat == null or size.x <= 0.0:
		return
	var ground: float = size.y * 0.82
	var operator_x: float = size.x * 0.16
	_positions[_combat.operator.id] = Vector2(operator_x, ground)
	var drone_count: int = _combat.drones.size()
	for index: int in range(drone_count):
		var spread: float = float(index) - float(drone_count - 1) * 0.5
		_positions[_combat.drones[index].id] = Vector2(operator_x + spread * 74.0 - 26.0, ground - 118.0 - absf(spread) * 20.0)
	for index: int in range(_combat.allies.size()):
		_positions[_combat.allies[index].id] = Vector2(size.x * 0.30 + float(index) * 60.0, ground)
	var enemy_count: int = _combat.enemies.size()
	for index: int in range(enemy_count):
		var column: int = index % 3
		var row: int = index / 3
		var boss_offset: float = 0.06 if _combat.enemies[index].is_boss else 0.0
		_positions[_combat.enemies[index].id] = Vector2(size.x * (0.60 + boss_offset + float(column) * 0.13), ground - float(row) * 52.0)

func _spawn(kind: String, event: Dictionary) -> void:
	var source_id: String = str(event.get("actorId", ""))
	var target_id: String = str(event.get("targetId", ""))
	var from: Vector2 = _positions.get(source_id, Vector2.ZERO)
	var to: Vector2 = _positions.get(target_id, from)
	match kind:
		"ATTACK", "SKILL_USE":
			_recoil[source_id] = 0.18
			if from != Vector2.ZERO and to != Vector2.ZERO and from != to:
				_effects.append({"kind": "tracer", "from": from + Vector2(0, -50), "to": to + Vector2(0, -46), "age": 0.0, "ttl": 0.20, "color": _damage_color(str(event.get("damageType", "")))})
		"DAMAGE":
			var amount: float = float(event.get("hpLost", 0.0)) + float(event.get("shieldConsumed", 0.0))
			_hit_flash[target_id] = 0.22
			if to != Vector2.ZERO:
				_effects.append({"kind": "impact", "at": to + Vector2(0, -46), "age": 0.0, "ttl": 0.34, "color": _damage_color(str(event.get("damageType", ""))), "crit": bool(event.get("crit", false))})
				_effects.append({"kind": "number", "at": to + Vector2(0, -84), "age": 0.0, "ttl": 0.85, "text": "-%d" % int(round(amount)), "color": COLOR_DANGER if float(event.get("hpLost", 0.0)) > 0.0 else COLOR_SHIELD})
		"MISS":
			_effects.append({"kind": "number", "at": to + Vector2(0, -84), "age": 0.0, "ttl": 0.7, "text": "ПРОМАХ", "color": COLOR_MUTED})
			_effects.append({"kind": "dodge", "at": to + Vector2(0, -46), "age": 0.0, "ttl": 0.4})
		"SHIELD_GAIN":
			_shield_flash[target_id] = 0.5
			_effects.append({"kind": "ring", "at": to + Vector2(0, -46), "age": 0.0, "ttl": 0.5, "color": COLOR_SHIELD})
		"HEAL":
			_effects.append({"kind": "ring", "at": to + Vector2(0, -46), "age": 0.0, "ttl": 0.55, "color": COLOR_HP})
			_effects.append({"kind": "number", "at": to + Vector2(0, -84), "age": 0.0, "ttl": 0.85, "text": "+%d" % int(round(float(event.get("data", {}).get("amount", 0.0)))), "color": COLOR_HP})
		"STATUS_APPLY":
			_effects.append({"kind": "number", "at": to + Vector2(0, -100), "age": 0.0, "ttl": 0.9, "text": str(event.get("statusId", "")), "color": COLOR_UNIQUE})
		"DEATH":
			_effects.append({"kind": "burst", "at": from + Vector2(0, -46), "age": 0.0, "ttl": 0.75, "color": COLOR_DANGER})
		"CAST_INTERRUPT":
			_effects.append({"kind": "number", "at": to + Vector2(0, -100), "age": 0.0, "ttl": 0.9, "text": "ПРЕРВАНО", "color": COLOR_WARNING})
			_effects.append({"kind": "burst", "at": to + Vector2(0, -60), "age": 0.0, "ttl": 0.45, "color": COLOR_WARNING})
		"TELEGRAPH":
			_effects.append({"kind": "ring", "at": from + Vector2(0, -50), "age": 0.0, "ttl": 0.8, "color": COLOR_DANGER})
		"HEAT_LOCKOUT":
			_effects.append({"kind": "number", "at": from + Vector2(0, -100), "age": 0.0, "ttl": 1.0, "text": "ПЕРЕГРЕВ", "color": COLOR_WARNING})

func _damage_color(damage_type: String) -> Color:
	match damage_type:
		"ENERGY": return COLOR_ACCENT
		"DIGITAL": return COLOR_UNIQUE
	return COLOR_WARNING

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if _combat == null:
		return
	_draw_backdrop()
	for actor: CombatActorState in _combat.allies:
		_draw_actor(actor)
	_draw_actor(_combat.operator)
	for actor: CombatActorState in _combat.drones:
		_draw_actor(actor)
	for actor: CombatActorState in _combat.enemies:
		_draw_actor(actor)
	_draw_effects()
	if not _combat.outcome.is_empty():
		_draw_outcome()

func _draw_backdrop() -> void:
	var ground: float = size.y * 0.82
	var horizon: Color = COLOR_SURFACE
	horizon.a = 0.85
	draw_rect(Rect2(Vector2(0, ground - 132.0), Vector2(size.x, 132.0)), horizon)
	for index: int in range(9):
		var x: float = size.x * (0.06 + float(index) * 0.11)
		var height: float = 40.0 + float((index * 37) % 61)
		draw_rect(Rect2(Vector2(x, ground - 132.0 - height), Vector2(26.0, height)), COLOR_ELEVATED)
		draw_rect(Rect2(Vector2(x + 6.0, ground - 126.0 - height), Vector2(4.0, 4.0)), Color(COLOR_ACCENT, 0.35))
	draw_rect(Rect2(Vector2(0, ground), Vector2(size.x, size.y - ground)), COLOR_ELEVATED)
	draw_line(Vector2(0, ground), Vector2(size.x, ground), COLOR_BORDER, 2.0)
	for index: int in range(14):
		var x: float = size.x * float(index) / 13.0
		draw_line(Vector2(x, ground), Vector2(x * 0.82 + size.x * 0.09, size.y), Color(COLOR_BORDER, 0.35), 1.0)
	if _reduced_motion:
		return
	for index: int in range(46):
		var seed_x: float = float((index * 97) % 1000) / 1000.0
		var speed: float = 260.0 + float((index * 53) % 180)
		var y: float = fmod(_clock * speed + float(index * 71), size.y + 40.0) - 20.0
		var x: float = seed_x * size.x
		draw_line(Vector2(x, y), Vector2(x - 3.0, y + 13.0), Color(COLOR_ACCENT, 0.10), 1.0)

func _actor_height(actor: CombatActorState) -> float:
	if actor.is_boss:
		return BOSS_HEIGHT
	match actor.kind:
		"drone": return DRONE_HEIGHT
		"operator": return OPERATOR_HEIGHT
	return ENEMY_HEIGHT

func _actor_texture(actor: CombatActorState) -> Texture2D:
	var key: String = ""
	match actor.kind:
		"operator": key = "actor_operator_base"
		"drone": key = _drone_placeholder(actor.drone_role)
		"ally": key = "enemy_sentry"
		_:
			if actor.is_boss: key = "boss_core12"
			elif actor.is_mechanical: key = "enemy_sentry"
			elif BEAST_TEMPLATES.has(actor.template_id): key = "enemy_scrap_hound"
			else: key = "enemy_raider_gunner"
	return _placeholders.get(key) as Texture2D

func _drone_placeholder(role: String) -> String:
	match role:
		"bulwark": return "drone_shield_base"
		"shock", "swarm": return "drone_gun_base"
	return "drone_support_base"

func _draw_actor(actor: CombatActorState) -> void:
	var position: Vector2 = _positions.get(actor.id, Vector2.ZERO)
	if position == Vector2.ZERO:
		return
	var height: float = _actor_height(actor)
	var centered: bool = actor.kind == "drone"
	var recoil: float = float(_recoil.get(actor.id, 0.0))
	var direction: float = -1.0 if actor.side == "player" else 1.0
	var bob: float = 0.0 if _reduced_motion else sin(_clock * 2.2 + float(actor.id.hash() % 100) * 0.07) * (3.0 if centered else 1.2)
	var origin: Vector2 = position + Vector2(recoil * 7.0 * direction, bob)
	var alpha: float = 1.0 if actor.alive else 0.26
	var texture: Texture2D = _actor_texture(actor)
	var body: Rect2
	if texture != null:
		var source_size: Vector2 = texture.get_size()
		var draw_size: Vector2 = source_size * (height / maxf(1.0, source_size.y))
		var top_left: Vector2 = origin - Vector2(draw_size.x * 0.5, draw_size.y if not centered else draw_size.y * 0.5)
		body = Rect2(top_left, draw_size)
		draw_texture_rect(texture, body, false, Color(1.0, 1.0, 1.0, alpha))
		var flash: float = float(_hit_flash.get(actor.id, 0.0))
		if flash > 0.0 and actor.alive:
			draw_texture_rect(texture, body, false, Color(2.4, 1.5, 1.5, flash * 2.2))
	else:
		body = Rect2(origin - Vector2(height * 0.28, height if not centered else height * 0.5), Vector2(height * 0.56, height))
		draw_rect(body, Color(COLOR_BORDER, alpha))
	if not actor.alive:
		draw_line(body.position + Vector2(4, 4), body.position + body.size - Vector2(4, 4), Color(COLOR_DANGER, 0.5), 2.0)
		draw_line(body.position + Vector2(body.size.x - 4, 4), body.position + Vector2(4, body.size.y - 4), Color(COLOR_DANGER, 0.5), 2.0)
		_draw_name(actor, body, alpha)
		return
	if actor.shield > 0.0:
		var pulse: float = 0.30 + float(_shield_flash.get(actor.id, 0.0))
		draw_arc(body.get_center(), maxf(body.size.x, body.size.y) * 0.56, 0.0, TAU, 28, Color(COLOR_SHIELD, clampf(pulse, 0.0, 0.85)), 2.0)
	if actor.heat_lockout:
		draw_arc(body.get_center(), maxf(body.size.x, body.size.y) * 0.62, 0.0, TAU, 24, Color(COLOR_WARNING, 0.6), 2.0)
	_draw_actor_bars(actor, body)
	_draw_cast(actor, body)
	_draw_statuses(actor, body)
	_draw_name(actor, body, alpha)

func _draw_name(actor: CombatActorState, body: Rect2, alpha: float) -> void:
	var label: String = actor.display_name
	if actor.elite_mod != "":
		label += " ★"
	var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var origin: Vector2 = Vector2(body.get_center().x - text_size.x * 0.5, body.position.y - 26.0)
	draw_string(_font, origin + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, alpha))
	draw_string(_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(COLOR_TEXT, alpha))

func _draw_actor_bars(actor: CombatActorState, body: Rect2) -> void:
	var max_hp: float = maxf(1.0, float(actor.base_sheet.get("maxHP", 1.0)))
	var width: float = maxf(46.0, body.size.x * 0.8)
	var origin: Vector2 = Vector2(body.get_center().x - width * 0.5, body.position.y - 18.0)
	draw_rect(Rect2(origin, Vector2(width, 5.0)), COLOR_BG)
	draw_rect(Rect2(origin, Vector2(width * clampf(actor.hp / max_hp, 0.0, 1.0), 5.0)), COLOR_HP)
	draw_rect(Rect2(origin, Vector2(width, 5.0)), COLOR_BORDER, false, 1.0)
	var max_shield: float = maxf(1.0, float(actor.base_sheet.get("maxShield", 0.0)))
	if actor.shield > 0.0 and max_shield > 0.0:
		draw_rect(Rect2(origin + Vector2(0, -4), Vector2(width * clampf(actor.shield / max_shield, 0.0, 1.0), 2.0)), COLOR_SHIELD)

func _draw_cast(actor: CombatActorState, body: Rect2) -> void:
	var cast: Variant = actor.cast if actor.cast != null else actor.reaction_cast
	if not cast is Dictionary or _combat == null:
		return
	var data: Dictionary = cast
	var started: float = float(data.get("startedAt", 0.0))
	var resolve_at: float = float(data.get("resolveAt", started))
	var span: float = maxf(1.0, resolve_at - started)
	var progress: float = clampf((float(_combat.time_ms) - started) / span, 0.0, 1.0)
	var width: float = maxf(52.0, body.size.x * 0.9)
	var origin: Vector2 = Vector2(body.get_center().x - width * 0.5, body.position.y - 34.0)
	var danger: bool = bool(data.get("telegraph", false)) or actor.is_boss
	var color: Color = COLOR_DANGER if danger else COLOR_WARNING
	draw_rect(Rect2(origin, Vector2(width, 6.0)), COLOR_BG)
	draw_rect(Rect2(origin, Vector2(width * progress, 6.0)), color)
	draw_rect(Rect2(origin, Vector2(width, 6.0)), color, false, 1.0)
	var label: String = "КАСТ" if not danger else "ОПАСНО"
	if bool(data.get("interruptible", false)):
		label += " · ПРЕРЫВАЕМО"
	draw_string(_font, origin + Vector2(0, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)

func _draw_statuses(actor: CombatActorState, body: Rect2) -> void:
	var index: int = 0
	for status_id: String in actor.statuses:
		var entry: Variant = actor.statuses[status_id]
		var stacks: int = 1
		if entry is Dictionary:
			stacks = int(entry.get("stacks", 1))
		elif entry is Array:
			stacks = (entry as Array).size()
		var origin: Vector2 = Vector2(body.position.x + float(index) * 15.0, body.position.y + body.size.y + 4.0)
		draw_rect(Rect2(origin, Vector2(13.0, 13.0)), COLOR_SURFACE)
		draw_rect(Rect2(origin, Vector2(13.0, 13.0)), COLOR_UNIQUE, false, 1.0)
		draw_string(_font, origin + Vector2(2.0, 10.0), status_id.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_UNIQUE)
		if stacks > 1:
			draw_string(_font, origin + Vector2(7.0, 10.0), str(mini(9, stacks)), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT)
		index += 1
		if index >= 6:
			return

func _draw_effects() -> void:
	for effect: Dictionary in _effects:
		var age: float = float(effect.get("age", 0.0))
		var ttl: float = maxf(0.01, float(effect.get("ttl", 0.0)))
		var life: float = clampf(1.0 - age / ttl, 0.0, 1.0)
		var color: Color = effect.get("color", COLOR_TEXT)
		match str(effect.get("kind", "")):
			"tracer":
				var from: Vector2 = effect["from"]
				var to: Vector2 = effect["to"]
				var head: Vector2 = from.lerp(to, clampf(age / ttl * 1.6, 0.0, 1.0))
				draw_line(from.lerp(to, clampf(age / ttl * 1.6 - 0.35, 0.0, 1.0)), head, Color(color, life), 2.0)
			"impact":
				var at: Vector2 = effect["at"]
				var radius: float = (6.0 + 16.0 * (1.0 - life)) * (1.5 if bool(effect.get("crit", false)) else 1.0)
				draw_arc(at, radius, 0.0, TAU, 18, Color(color, life), 2.0)
				if not _reduced_motion:
					for spoke: int in range(6):
						var angle: float = TAU * float(spoke) / 6.0 + age * 3.0
						draw_line(at + Vector2(cos(angle), sin(angle)) * radius * 0.5, at + Vector2(cos(angle), sin(angle)) * radius, Color(color, life * 0.8), 1.0)
			"ring":
				draw_arc(effect["at"], 10.0 + 34.0 * (1.0 - life), 0.0, TAU, 26, Color(color, life * 0.9), 2.0)
			"burst":
				var at: Vector2 = effect["at"]
				for shard: int in range(9):
					var angle: float = TAU * float(shard) / 9.0
					var distance: float = 40.0 * (1.0 - life)
					draw_line(at + Vector2(cos(angle), sin(angle)) * distance * 0.4, at + Vector2(cos(angle), sin(angle)) * distance, Color(color, life), 2.0)
			"dodge":
				var at: Vector2 = effect["at"]
				draw_arc(at + Vector2(-14.0 * (1.0 - life), 0), 18.0, -0.9, 0.9, 12, Color(COLOR_MUTED, life), 2.0)
			"number":
				var at: Vector2 = effect["at"] + Vector2(0, -22.0 * (1.0 - life))
				var text: String = str(effect.get("text", ""))
				var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
				var origin: Vector2 = at - Vector2(text_size.x * 0.5, 0.0)
				draw_string(_font, origin + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, life))
				draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(color, life))

func _draw_outcome() -> void:
	var victory: bool = _combat.outcome == "VICTORY"
	var color: Color = COLOR_HP if victory else COLOR_DANGER
	var text: String = "ПОБЕДА" if victory else ("ПОРАЖЕНИЕ" if _combat.outcome == "DEFEAT" else _combat.outcome)
	var banner: Color = Color(COLOR_BG, 0.82)
	draw_rect(Rect2(Vector2(0, size.y * 0.42), Vector2(size.x, 52.0)), banner)
	draw_line(Vector2(0, size.y * 0.42), Vector2(size.x, size.y * 0.42), color, 2.0)
	draw_line(Vector2(0, size.y * 0.42 + 52.0), Vector2(size.x, size.y * 0.42 + 52.0), color, 2.0)
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string(_font, Vector2(size.x * 0.5 - text_size.x * 0.5, size.y * 0.42 + 35.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)

static func _load_placeholders() -> Dictionary:
	var result: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/alpha_visual_fallbacks.json"))
	if not parsed is Dictionary:
		return result
	var entries: Dictionary = (parsed as Dictionary).get("placeholders", {})
	for key: String in entries:
		var entry: Dictionary = entries[key]
		var texture: Texture2D = load(str(entry.get("source", ""))) as Texture2D
		if texture != null:
			result[key] = texture
	return result