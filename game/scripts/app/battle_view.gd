class_name BattleView
extends VBoxContainer

signal settlement_requested

const COLOR_TEXT: Color = Color("e4e8e8")
const COLOR_MUTED: Color = Color("a4afb9")
const COLOR_CYAN: Color = Color("56d5d0")
const COLOR_HP: Color = Color("4cc99b")
const COLOR_SHIELD: Color = Color("55b6f0")
const COLOR_ENERGY: Color = Color("4e97eb")
const COLOR_HEAT: Color = Color("ef9b42")
const COLOR_DANGER: Color = Color("ed6767")
const COLOR_WARNING: Color = Color("e7bc65")
const COLOR_VOID: Color = Color("090b10")
const COLOR_STEEL: Color = Color("252c35")
const COLOR_BORDER: Color = Color("344357")

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const MAX_FRAME_SIM_MS: float = 1000.0

var _session: GameSession
var _reduced_motion: bool
var _arena: BattleArena
var _speed: float = 1.0
var _paused: bool = false
var _pending_ms: float = 0.0
var _seen_event_id: int = 0
var _operator_label: Label
var _status_label: Label
var _time_label: Label
var _drone_label: Label
var _bars: Dictionary = {}
var _enemy_box: VBoxContainer
var _enemy_rows: Dictionary = {}
var _enemy_signature: String = ""
var _info_scroll: ScrollContainer
var _info_box: VBoxContainer
var _timeline_box: VBoxContainer
var _timeline_signature: int = -1
var _speed_buttons: Dictionary = {}
var _pause_button: Button
var _controls_row: HBoxContainer
var _action_box: HBoxContainer
var _settled: bool = false

func _init(session: GameSession, reduced_motion: bool = false) -> void:
	_session = session
	_reduced_motion = reduced_motion

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var combat: CombatState = _session.combat_state()
	_arena = BattleArena.new()
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_arena)
	_arena.setup(combat, _reduced_motion)
	_build_operator_hud()
	_info_scroll = ScrollContainer.new()
	_info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_scroll.custom_minimum_size = Vector2(0, 120)
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_info_scroll)
	_info_box = VBoxContainer.new()
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_box.add_theme_constant_override("separation", 4)
	_info_scroll.add_child(_info_box)
	_build_enemy_hud()
	_build_timeline()
	_build_controls()
	if combat != null and not combat.log.is_empty():
		_seen_event_id = int(combat.log[combat.log.size() - 1].get("eventId", 0))
	_refresh()

func _build_operator_hud() -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	add_child(panel)
	_operator_label = _label("ОПЕРАТОР", 14, COLOR_TEXT)
	panel.add_child(_operator_label)
	var bar_row: HBoxContainer = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	panel.add_child(bar_row)
	for entry: Array in [["hp", "HP", COLOR_HP], ["shield", "ЩИТ", COLOR_SHIELD], ["energy", "ЭНЕРГИЯ", COLOR_ENERGY], ["heat", "НАГРЕВ", COLOR_HEAT]]:
		var cell: VBoxContainer = VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		bar_row.add_child(cell)
		cell.add_child(_label(str(entry[1]), 10, COLOR_MUTED))
		var bar: ProgressBar = _bar(0.0, entry[2])
		bar.custom_minimum_size.y = 16
		cell.add_child(bar)
		_bars[str(entry[0])] = bar
	_status_label = _label("", 11, COLOR_WARNING)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status_label)
	_drone_label = _label("", 11, COLOR_MUTED)
	_drone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_drone_label)

func _build_enemy_hud() -> void:
	var heading: HBoxContainer = HBoxContainer.new()
	_info_box.add_child(heading)
	var title: Label = _label("ПРОТИВНИК", 12, COLOR_DANGER)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_child(title)
	_time_label = _label("", 12, COLOR_CYAN)
	_time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(_time_label)
	_enemy_box = VBoxContainer.new()
	_enemy_box.add_theme_constant_override("separation", 2)
	_info_box.add_child(_enemy_box)

func _build_timeline() -> void:
	var heading: Label = _label("ПОСЛЕДНИЕ СОБЫТИЯ", 12, COLOR_CYAN)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_box.add_child(heading)
	_timeline_box = VBoxContainer.new()
	_timeline_box.add_theme_constant_override("separation", 1)
	_info_box.add_child(_timeline_box)

func _build_controls() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_controls_row = row
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_pause_button = _button("ПАУЗА", false)
	_pause_button.custom_minimum_size = Vector2(110, 38)
	_pause_button.pressed.connect(_on_pause)
	row.add_child(_pause_button)
	for speed: float in SPEEDS:
		var button: Button = _button("×%d" % int(speed), false)
		button.custom_minimum_size = Vector2(64, 38)
		button.pressed.connect(_on_speed.bind(speed))
		row.add_child(button)
		_speed_buttons[speed] = button
	var skip: Button = _button("ПРОПУСК", false)
	skip.custom_minimum_size = Vector2(110, 38)
	skip.pressed.connect(_on_skip)
	row.add_child(skip)
	_action_box = HBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 8)
	add_child(_action_box)
	_sync_speed_buttons()

func _process(delta: float) -> void:
	var combat: CombatState = _session.combat_state()
	if combat == null:
		set_process(false)
		return
	if combat.outcome.is_empty() and not _paused:
		_pending_ms = minf(MAX_FRAME_SIM_MS, _pending_ms + delta * 1000.0 * _speed)
		var budget: int = int(_pending_ms)
		if budget >= CombatSimulator.TICK_MS:
			var interval: int = int(GameSession.COMBAT_PLAYBACK_PERSIST_INTERVAL_MS * maxf(1.0, _speed))
			if not _session.advance_combat_playback(budget, interval):
				_pending_ms = 0.0
				_time_label.text = _session.last_error
				set_process(false)
				return
			_pending_ms -= float(budget - budget % CombatSimulator.TICK_MS)
	combat = _session.combat_state()
	_consume_events(combat)
	_arena.sync(combat)
	_refresh()
	if not combat.outcome.is_empty() and not _settled:
		_settled = true
		_show_settlement()

func _consume_events(combat: CombatState) -> void:
	if combat == null:
		return
	var fresh: Array[Dictionary] = []
	for event: Dictionary in combat.log:
		if int(event.get("eventId", 0)) > _seen_event_id:
			fresh.append(event)
	if fresh.is_empty():
		return
	_seen_event_id = int(fresh[fresh.size() - 1].get("eventId", 0))
	_arena.consume(fresh)

func _refresh() -> void:
	var combat: CombatState = _session.combat_state()
	if combat == null:
		return
	var operator: CombatActorState = combat.operator
	var sheet: Dictionary = operator.base_sheet
	_operator_label.text = "ОПЕРАТОР · HP %d/%d · ЩИТ %d · ЭНЕРГИЯ %d · НАГРЕВ %d%s" % [
		int(operator.hp), int(float(sheet.get("maxHP", 0))), int(operator.shield), int(operator.energy), int(operator.heat),
		" · ПЕРЕГРЕВ" if operator.heat_lockout else "",
	]
	_bars["hp"].value = clampf(operator.hp / maxf(1.0, float(sheet.get("maxHP", 1.0))), 0.0, 1.0)
	_bars["shield"].value = clampf(operator.shield / maxf(1.0, float(sheet.get("maxShield", 1.0))), 0.0, 1.0)
	_bars["energy"].value = clampf(operator.energy / maxf(1.0, float(sheet.get("maxEnergy", 1.0))), 0.0, 1.0)
	_bars["heat"].value = clampf(operator.heat / maxf(1.0, float(sheet.get("maxHeat", 1.0))), 0.0, 1.0)
	_status_label.text = _status_text(operator)
	_drone_label.text = _drone_text(combat)
	_time_label.text = "ВРЕМЯ БОЯ %d:%02d.%d   ·   %s" % [
		int(combat.time_ms / 60000.0), int(combat.time_ms / 1000.0) % 60, int(combat.time_ms / 100.0) % 10,
		("ПАУЗА" if _paused else "×%d" % int(_speed)) if combat.outcome.is_empty() else combat.outcome,
	]
	_refresh_enemies(combat)
	_refresh_timeline(combat)

func _status_text(actor: CombatActorState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for status_id: String in actor.statuses:
		var entry: Variant = actor.statuses[status_id]
		var stacks: int = 1
		if entry is Dictionary:
			stacks = int(entry.get("stacks", 1))
		elif entry is Array:
			stacks = (entry as Array).size()
		parts.append("%s×%d" % [status_id, stacks] if stacks > 1 else status_id)
	for buff: Dictionary in actor.buffs:
		parts.append(str(buff.get("id", "БАФ")))
	return "СТАТУСЫ: %s" % (", ".join(parts) if not parts.is_empty() else "нет")

func _drone_text(combat: CombatState) -> String:
	if combat.drones.is_empty():
		return "ДРОНЫ: нет"
	var parts: PackedStringArray = PackedStringArray()
	for drone: CombatActorState in combat.drones:
		var cooldowns: PackedStringArray = PackedStringArray()
		for skill_id: String in drone.cooldowns:
			var ready_at: float = float(drone.cooldowns[skill_id])
			var remaining: float = maxf(0.0, ready_at - float(combat.time_ms))
			if remaining > 0.0:
				cooldowns.append("%s %.1fс" % [skill_id, remaining / 1000.0])
		var state: String = "УНИЧТОЖЕН" if not drone.alive else ("КАСТ" if drone.reaction_cast != null else "ГОТОВ")
		parts.append("%s [%s] %s%s" % [drone.display_name, drone.drone_role, state, (" · " + ", ".join(cooldowns)) if not cooldowns.is_empty() else ""])
	return "ДРОНЫ: %s" % " | ".join(parts)

func _refresh_enemies(combat: CombatState) -> void:
	var signature: String = ""
	for enemy: CombatActorState in combat.enemies:
		signature += enemy.id + ";"
	if signature != _enemy_signature:
		_enemy_signature = signature
		_enemy_rows.clear()
		for child: Node in _enemy_box.get_children():
			child.queue_free()
		for enemy: CombatActorState in combat.enemies:
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_enemy_box.add_child(row)
			var name_label: Label = _label("", 11, COLOR_DANGER if enemy.is_boss else COLOR_TEXT)
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_label.custom_minimum_size.x = 120
			row.add_child(name_label)
			var bar: ProgressBar = _bar(1.0, COLOR_DANGER)
			bar.custom_minimum_size = Vector2(90, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bar)
			var cast_label: Label = _label("", 10, COLOR_WARNING)
			cast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			cast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cast_label.custom_minimum_size.x = 150
			row.add_child(cast_label)
			_enemy_rows[enemy.id] = {"name": name_label, "bar": bar, "cast": cast_label}
	for enemy: CombatActorState in combat.enemies:
		var row: Dictionary = _enemy_rows.get(enemy.id, {})
		if row.is_empty():
			continue
		var max_hp: float = maxf(1.0, float(enemy.base_sheet.get("maxHP", 1.0)))
		var title: String = "%s%s · HP %d/%d · ЩИТ %d" % [
			enemy.display_name, " ★" if enemy.elite_mod != "" else "", int(enemy.hp), int(max_hp), int(enemy.shield),
		]
		if not enemy.alive:
			title += " · УНИЧТОЖЕН"
		(row["name"] as Label).text = title
		(row["bar"] as ProgressBar).value = clampf(enemy.hp / max_hp, 0.0, 1.0)
		(row["cast"] as Label).text = _cast_text(enemy, combat)

func _cast_text(enemy: CombatActorState, combat: CombatState) -> String:
	var cast: Variant = enemy.cast if enemy.cast != null else enemy.reaction_cast
	if not cast is Dictionary:
		return ""
	var data: Dictionary = cast
	var remaining: float = maxf(0.0, float(data.get("resolveAt", 0.0)) - float(combat.time_ms))
	var label: String = str(data.get("abilityId", data.get("skillId", "способность")))
	var danger: String = "ОПАСНЫЙ КАСТ" if bool(data.get("telegraph", false)) or enemy.is_boss else "КАСТ"
	return "%s · %s · %.1fс%s" % [danger, label, remaining / 1000.0, " · прерываемо" if bool(data.get("interruptible", false)) else ""]

func _refresh_timeline(combat: CombatState) -> void:
	var last_id: int = int(combat.log[combat.log.size() - 1].get("eventId", 0)) if not combat.log.is_empty() else 0
	if last_id == _timeline_signature:
		return
	_timeline_signature = last_id
	for child: Node in _timeline_box.get_children():
		child.queue_free()
	var events: Array[Dictionary] = combat.log.slice(maxi(0, combat.log.size() - 5))
	for event: Dictionary in events:
		var timestamp: float = float(event.get("timestamp", 0.0))
		var text: String = str(event.get("text", ""))
		if text.is_empty():
			text = str(event.get("kind", ""))
		var line: Label = _label("[%d.%d] %s" % [int(timestamp / 1000.0), int(timestamp / 100.0) % 10, text], 10, COLOR_MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_timeline_box.add_child(line)

func _show_settlement() -> void:
	_controls_row.visible = false
	for child: Node in _action_box.get_children():
		child.queue_free()
	var combat: CombatState = _session.combat_state()
	var victory: bool = combat != null and combat.outcome == "VICTORY"
	var outcome_label: Label = _label("ИСХОД: %s" % (combat.outcome if combat != null else ""), 16, COLOR_HP if victory else COLOR_DANGER)
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	outcome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_box.add_child(outcome_label)
	var settle: Button = _button("ЗАФИКСИРОВАТЬ РЕЗУЛЬТАТ", true)
	settle.custom_minimum_size = Vector2(240, 40)
	settle.pressed.connect(func() -> void: settlement_requested.emit())
	_action_box.add_child(settle)
	_pause_button.disabled = true
	for button: Button in _speed_buttons.values():
		button.disabled = true

func _on_pause() -> void:
	_paused = not _paused
	_pause_button.text = "ПРОДОЛЖИТЬ" if _paused else "ПАУЗА"
	_sync_speed_buttons()

func _on_speed(speed: float) -> void:
	_speed = speed
	_paused = false
	_pause_button.text = "ПАУЗА"
	_sync_speed_buttons()

func _sync_speed_buttons() -> void:
	for speed: float in _speed_buttons:
		var button: Button = _speed_buttons[speed]
		button.modulate = COLOR_CYAN if (not _paused and is_equal_approx(speed, _speed)) else Color(1, 1, 1, 1)

func _on_skip() -> void:
	if not _session.skip_combat_to_outcome():
		_time_label.text = _session.last_error
		return
	_pending_ms = 0.0
	var combat: CombatState = _session.combat_state()
	_consume_events(combat)
	_arena.sync(combat)
	_refresh()
	if combat != null and not combat.outcome.is_empty() and not _settled:
		_settled = true
		_show_settlement()

func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _bar(fraction: float, color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
	bar.add_theme_stylebox_override("background", _panel_style(COLOR_VOID, COLOR_VOID))
	bar.add_theme_stylebox_override("fill", _panel_style(color, color))
	return bar

func _button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_VOID if primary else COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_VOID if primary else COLOR_CYAN)
	button.add_theme_stylebox_override("normal", _panel_style(COLOR_CYAN if primary else COLOR_STEEL, COLOR_CYAN if primary else COLOR_BORDER))
	button.add_theme_stylebox_override("hover", _panel_style(Color("7de7df") if primary else Color("2b3947"), COLOR_CYAN))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("6488f2") if primary else Color("15191f"), Color("6488f2")))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("20262c"), Color("34393e")))
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	return button

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	return style