extends Control

const COLOR_VOID: Color = Color("090b10")
const COLOR_COAL: Color = Color("15191f")
const COLOR_STEEL: Color = Color("252c35")
const COLOR_CYAN: Color = Color("56d5d0")
const COLOR_BLUE: Color = Color("6488f2")
const COLOR_AMBER: Color = Color("e5a34b")
const COLOR_RED: Color = Color("d75a55")
const COLOR_TEXT: Color = Color("e4e8e8")
const COLOR_MUTED: Color = Color("a4afb9")

var _session: GameSession = GameSession.new()
var _body: VBoxContainer
var _footer: Label
var _screen: String = "menu"
var _combat_timer: Timer
var _settings: ConfigFile = ConfigFile.new()
var _muted: bool = false
var _reduced_motion: bool = false
var _medical_restore_next_run: bool = false
var _simulation_slot: String = ""
var _simulation_item_id: String = ""
var _simulation_enemy_id: String = "E01"
var _simulation_report: Dictionary = {}
var _selected_escalations: Array[String] = []

func _ready() -> void:
	_session.load_saved_game()
	_settings.load("user://settings.cfg")
	_muted = bool(_settings.get_value("audio", "muted", false))
	_reduced_motion = bool(_settings.get_value("accessibility", "reduced_motion", false))
	_build_shell()
	_show_menu()

func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.color = COLOR_VOID
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var texture: Texture2D = load("res://assets/source/placeholders/biome_b01_placeholder.svg") as Texture2D
	if texture != null:
		var backdrop: TextureRect = TextureRect.new()
		backdrop.texture = texture
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.modulate = Color(0.38, 0.48, 0.56, 0.28)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.035, 0.043, 0.058, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	var shell: VBoxContainer = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 14)
	margin.add_child(shell)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	shell.add_child(header)
	var brand: Label = _label("CYDLE", 30, COLOR_TEXT)
	brand.custom_minimum_size.x = 160
	header.add_child(brand)
	var chapter: Label = _label("НУЛЕВОЙ ТРАКТ   /   ЛОКАЛЬНАЯ ЭКСПЕДИЦИЯ", 12, COLOR_CYAN)
	chapter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chapter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(chapter)
	var saved_badge: Label = _label("СЕЙВ · %s" % ("ЗАГРУЖЕН" if _session.state != null else "НОВЫЙ ПРОФИЛЬ"), 11, COLOR_MUTED)
	header.add_child(saved_badge)
	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color(0.34, 0.82, 0.77, 0.7)
	shell.add_child(divider)
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	shell.add_child(content)
	var sidebar: VBoxContainer = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 190
	sidebar.add_theme_constant_override("separation", 8)
	content.add_child(sidebar)
	for entry: Array in [["ГАРАЖ", "garage"], ["ДОРОГА", "road"], ["БИЛДИНГ", "build"], ["СКЛАД", "inventory"], ["НАСТРОЙКИ", "settings"]]:
		var nav: Button = _button(str(entry[0]), false)
		nav.custom_minimum_size.y = 42
		nav.pressed.connect(_navigate.bind(str(entry[1])))
		sidebar.add_child(nav)
	var sidebar_spacer: Control = Control.new()
	sidebar_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(sidebar_spacer)
	var quit: Button = _button("ЗАВЕРШИТЬ СМЕНУ", true)
	quit.pressed.connect(func() -> void: get_tree().quit())
	sidebar.add_child(quit)
	var frame: PanelContainer = PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.075, 0.095, 0.94), Color(0.20, 0.31, 0.38, 1.0)))
	content.add_child(frame)
	var inner: MarginContainer = MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 22)
	inner.add_theme_constant_override("margin_top", 18)
	inner.add_theme_constant_override("margin_right", 22)
	inner.add_theme_constant_override("margin_bottom", 18)
	frame.add_child(inner)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_body)
	_footer = _label("СИСТЕМА ГОТОВА", 11, COLOR_MUTED)
	shell.add_child(_footer)

func _show_menu() -> void:
	_screen = "menu"
	_clear_body()
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 45
	_body.add_child(spacer)
	_body.add_child(_label("ПРОТОКОЛ ЭВАКУАЦИИ", 12, COLOR_CYAN))
	_body.add_child(_label("Нулевой тракт", 36, COLOR_TEXT))
	_body.add_child(_label("Автономная экспедиция через руины корпоративной сети.\nСнаряжение и решения сохраняются локально.", 16, COLOR_MUTED))
	var image: TextureRect = TextureRect.new()
	image.texture = load("res://assets/source/placeholders/garage_main_placeholder.svg") as Texture2D
	image.custom_minimum_size = Vector2(0, 235)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.modulate = Color(0.9, 1.0, 1.0, 0.9)
	_body.add_child(image)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_body.add_child(actions)
	var new_game: Button = _button("НОВАЯ ИГРА", true)
	new_game.pressed.connect(_on_new_game)
	actions.add_child(new_game)
	var continue_game: Button = _button("ПРОДОЛЖИТЬ", false)
	continue_game.disabled = _session.state == null
	continue_game.pressed.connect(_on_continue)
	actions.add_child(continue_game)
	var settings_button: Button = _button("НАСТРОЙКИ", false)
	settings_button.pressed.connect(_show_settings)
	actions.add_child(settings_button)
	_footer.text = _session.last_error if not _session.last_error.is_empty() else "ОДИН ОПЕРАТОР · ДВА СЛОТА ДРОНОВ · ОДИН НУЛЕВОЙ ТРАКТ"
	new_game.grab_focus()

func _show_garage() -> void:
	_screen = "garage"
	_clear_body()
	if _session.state == null:
		_body.add_child(_label("Гараж пока пуст", 28, COLOR_TEXT))
		var new_button: Button = _button("СОЗДАТЬ ОПЕРАТОРА", true)
		new_button.pressed.connect(_on_new_game)
		_body.add_child(new_button)
		return
	var state: GameSaveState = _session.state
	var meta: GameSaveState.MetaState = state.meta
	var act: int = 1 if meta.max_sector_cleared < 4 else 2 if meta.max_sector_cleared < 8 else 3
	_body.add_child(_label("ГАРАЖ   /   АКТ %d · %s" % [act, ["Прорыв", "Перехват", "Сердце"][act - 1]], 12, COLOR_CYAN))
	if meta.campaign_flags.has("ACT_I_ARCHIVE"):
		_body.add_child(_label("АРХИВ ПЕРВОГО КОРИДОРА ДОСТУПЕН", 11, COLOR_MUTED))
	if meta.campaign_flags.has("ACT_II_DRONE_LINE"):
		_body.add_child(_label("ЛИНИЯ УСИЛЕННЫХ ДРОНОВ · ИНСТРУМЕНТЫ ЦЕЛЕВОЙ ОХОТЫ ОТКРЫТЫ", 11, COLOR_CYAN))
	if meta.campaign_flags.has("ENDING_SELECTED"):
		var ending_label: String = "СВОБОДНЫЙ КОРИДОР" if meta.campaign_flags.has("ENDING_FREE_CORRIDOR") else "КОНТРОЛЬ ФРАКЦИИ"
		for campaign_flag: String in meta.campaign_flags:
			if campaign_flag.begins_with("ENDING_FACTION:"):
				ending_label = "КОНТРОЛЬ %s" % campaign_flag.trim_prefix("ENDING_FACTION:")
		_body.add_child(_label("ФИНАЛ · %s" % ending_label, 11, COLOR_AMBER))
	_body.add_child(_label("Цель оператора", 28, COLOR_TEXT))
	var hero_row: HBoxContainer = HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 18)
	_body.add_child(hero_row)
	var operator_art: TextureRect = TextureRect.new()
	operator_art.texture = load("res://assets/source/placeholders/actor_operator_base.svg") as Texture2D
	operator_art.custom_minimum_size = Vector2(150, 175)
	operator_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	operator_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_row.add_child(operator_art)
	var summary: VBoxContainer = VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(summary)
	var build: Dictionary = _session.build_preview()
	if not bool(build.get("valid", false)):
		summary.add_child(_label("СБОРКА ТРЕБУЕТ ВНИМАНИЯ", 16, COLOR_RED))
	else:
		var sheet: Dictionary = build.get("stats", {})
		summary.add_child(_label("ОПЕРАТОР · УРОВЕНЬ %d" % meta.operator.level, 16, COLOR_TEXT))
		summary.add_child(_label("HP %s     ЩИТ %s     ЭНЕРГИЯ %s" % [_fmt(sheet.get("maxHP", 0)), _fmt(sheet.get("maxShield", 0)), _fmt(sheet.get("maxEnergy", 0))], 15, Color("4cc99b")))
		summary.add_child(_label("УРОН K %s   E %s   D %s     БРОНЯ %s" % [_fmt(sheet.get("kineticDamage", 0)), _fmt(sheet.get("energyDamage", 0)), _fmt(sheet.get("digitalDamage", 0)), _fmt(sheet.get("armor", 0))], 14, COLOR_TEXT))
		summary.add_child(_label("ЗАЩИЩЁННЫЙ СЧЁТ   ¤ %d   ·   scrap %d   ·   data %d" % [int(meta.protected_bank.credits), int(meta.protected_bank.scrap), int(meta.protected_bank.data)], 13, COLOR_AMBER))
		summary.add_child(_label("ФОРПОСТ %d   ·   МАКСИМАЛЬНЫЙ СЕКТОР %d" % [meta.unlocked_forpost, meta.max_sector_cleared], 12, COLOR_MUTED))
	var points_available: int = _session.attribute_points_available()
	_body.add_child(_label("АТРИБУТЫ   ·   %d ОЧК. ДОСТУПНО" % points_available, 13, COLOR_CYAN))
	var attribute_row: HBoxContainer = HBoxContainer.new()
	attribute_row.add_theme_constant_override("separation", 7)
	_body.add_child(attribute_row)
	var attribute_names: Dictionary = {"POW": "МОЩЬ", "REF": "РЕАКЦИЯ", "INT": "ИНТЕЛЛЕКТ", "ENG": "ИНЖЕНЕРИЯ", "SYN": "СИНХРОНИЗАЦИЯ"}
	for attribute_id: String in ["POW", "REF", "INT", "ENG", "SYN"]:
		var attribute_button: Button = _button("%s  %d  +1" % [str(attribute_names[attribute_id]), int(meta.operator.attributes.get(attribute_id, 5))], false)
		attribute_button.disabled = points_available <= 0
		attribute_button.pressed.connect(_on_allocate_attribute.bind(attribute_id))
		attribute_row.add_child(attribute_button)
	var spent_points: int = int(meta.operator.attribute_points) - points_available
	var respec_button: Button = _button("СБРОСИТЬ · %d ¤" % (spent_points * 10), false)
	respec_button.disabled = spent_points <= 0 or meta.protected_bank.credits < spent_points * 10
	respec_button.pressed.connect(_on_respec_attributes)
	attribute_row.add_child(respec_button)
	_body.add_child(_label("ОБЪЕКТЫ ГАРАЖА · МАКСИМУМ L3", 15, COLOR_CYAN))
	var garage_descriptions: Dictionary = {
		"WORKSHOP": "L1 ремонт · L2 калибровка ролла · L3 повышение tier",
		"NEUROLAB": "L2: пятый имплантный слот после сектора 5 · L3: шестой после сектора 9",
		"SERVER": "Редактор тактики · профили и архивы открываются по уровню",
		"HANGAR": "L1 стартовый дрон · L2 второй слот после сектора 6 · L3 дешевле ремонт дронов",
		"MARKET": "L1 три предложения · L2 пять · L3 тематическое предложение",
		"INTEL": "L1 типы соседних узлов · L2 диапазон угрозы и добычи · L3 ещё один слой",
		"GARAGE_MED": "Стабилизация после поражения · L3 платное полное восстановление при старте",
		"CALIBRATOR": "Калибровка TechLevel · L2 снижает расход SCRAP · L3 пакетная калибровка",
	}
	for object_id: String in ["WORKSHOP", "NEUROLAB", "SERVER", "HANGAR", "MARKET", "INTEL", "GARAGE_MED", "CALIBRATOR"]:
		var upgrade_row: HBoxContainer = HBoxContainer.new()
		_body.add_child(upgrade_row)
		var upgrade_info: VBoxContainer = VBoxContainer.new()
		upgrade_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upgrade_row.add_child(upgrade_info)
		var object_level: int = _session.garage_level(object_id)
		upgrade_info.add_child(_label("%s · L%d / 3" % [object_id, object_level], 12, COLOR_TEXT))
		var object_description: Label = _label(str(garage_descriptions[object_id]), 10, COLOR_MUTED)
		object_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		upgrade_info.add_child(object_description)
		if object_level >= 3:
			upgrade_row.add_child(_button("МАКСИМУМ", true))
			continue
		var upgrade_quote: Dictionary = _session.garage_upgrade_quote(object_id)
		if bool(upgrade_quote.get("valid", false)):
			var cost_text: String = "%d ¤ · %d SCRAP" % [int(upgrade_quote["credits"]), int(upgrade_quote["scrap"])]
			if int(upgrade_quote.get("data", 0)) > 0:
				cost_text += " · %d DATA" % int(upgrade_quote["data"])
			var upgrade_button: Button = _button("УЛУЧШИТЬ · %s" % cost_text, false)
			upgrade_button.disabled = not bool(upgrade_quote.get("affordable", false))
			upgrade_button.tooltip_text = str(upgrade_quote.get("error", ""))
			upgrade_button.pressed.connect(_on_upgrade_garage_object.bind(object_id))
			upgrade_row.add_child(upgrade_button)
		else:
			var locked_upgrade: Button = _button("ЗАКРЫТО", true)
			locked_upgrade.disabled = true
			locked_upgrade.tooltip_text = str(upgrade_quote.get("error", ""))
			upgrade_row.add_child(locked_upgrade)
	var equipped: HBoxContainer = HBoxContainer.new()
	equipped.add_theme_constant_override("separation", 8)
	_body.add_child(equipped)
	for slot_value: Variant in meta.equipment.keys():
		var item_value: Dictionary = _item_by_id(str(meta.equipment[slot_value]))
		var item_name: String = str(item_value.get("templateId", "—"))
		var template: Dictionary = ItemCatalog.new().get_template(str(item_value.get("templateId", "")))
		if not template.is_empty():
			item_name = str(template.get("name", item_name))
		var chip: Label = _label("%s · %s" % [str(slot_value), item_name], 11, COLOR_TEXT)
		chip.add_theme_stylebox_override("normal", _panel_style(COLOR_STEEL, Color(0.25, 0.38, 0.43, 1)))
		equipped.add_child(chip)
	var actions: HFlowContainer = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	_body.add_child(actions)
	if _session.garage_level("GARAGE_MED") >= 3:
		var start_depth: int = maxi(1, meta.unlocked_forpost + 1)
		var medical_cost: int = ceili(8.0 * CydleFormula.new().reward_scale(float(start_depth)))
		var medical_toggle: CheckButton = CheckButton.new()
		medical_toggle.text = "Медблок · полное восстановление перед выездом · %d ¤" % medical_cost
		medical_toggle.button_pressed = _medical_restore_next_run
		medical_toggle.disabled = meta.protected_bank.credits < float(medical_cost)
		medical_toggle.toggled.connect(func(value: bool) -> void: _medical_restore_next_run = value)
		_body.add_child(medical_toggle)
	_add_escalation_selector()
	var start_button: Button = _button("НАЧАТЬ ВЫЕЗД", true)
	start_button.pressed.connect(_on_start_expedition)
	actions.add_child(start_button)
	for offer: Dictionary in _session.available_contract_offers():
		var contract_button: Button = _button("КОНТРАКТ · %s" % str(offer.get("name", offer.get("id", ""))), false)
		contract_button.tooltip_text = str(offer.get("desc", ""))
		contract_button.pressed.connect(_on_start_expedition.bind(str(offer.get("id", ""))))
		actions.add_child(contract_button)
	var build_button: Button = _button("БИЛДИНГ · 85 ХАРАКТЕРИСТИК", false)
	build_button.pressed.connect(_show_build)
	actions.add_child(build_button)
	var inventory_button: Button = _button("СКЛАД · %d ПРЕДМЕТОВ" % meta.inventory.size(), false)
	inventory_button.pressed.connect(_show_inventory)
	actions.add_child(inventory_button)
	var tactics_button: Button = _button("ТАКТИКА · %d ПРОФИЛЬ(Я)" % meta.tactics.size(), false)
	tactics_button.pressed.connect(_show_tactics)
	actions.add_child(tactics_button)
	var simulation_button: Button = _button("SIMULATION LAB", false)
	simulation_button.pressed.connect(_show_simulation_lab)
	actions.add_child(simulation_button)
	var journal_button: Button = _button("ЖУРНАЛ ЗАДАНИЙ", false)
	journal_button.pressed.connect(_show_quest_journal)
	actions.add_child(journal_button)
	var save_button: Button = _button("СОХРАНИТЬ", false)
	save_button.pressed.connect(_on_save)
	actions.add_child(save_button)
	if state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(state.run.phase):
		var road_button: Button = _button("ВЕРНУТЬСЯ НА ДОРОГУ", false)
		road_button.pressed.connect(_show_road)
		actions.add_child(road_button)
	_footer.text = "СЕЙВ %s · РЕВИЗИЯ %d" % [state.save_id, state.revision]

func _show_build() -> void:
	_screen = "build"
	_clear_body()
	_body.add_child(_label("BUILD LAB   /   ТЕКУЩАЯ СБОРКА", 12, COLOR_CYAN))
	_body.add_child(_label("Билдинг", 28, COLOR_TEXT))
	var build: Dictionary = _session.build_preview()
	if not bool(build.get("valid", false)):
		_body.add_child(_label("Сборка невалидна: %s" % str(build.get("issues", [])), 14, COLOR_RED))
		return
	var stat_ids: Array[String] = StatMath.new().stat_ids()
	var selector: OptionButton = OptionButton.new()
	selector.custom_minimum_size.x = 340
	for stat_id: String in stat_ids:
		var definition: Dictionary = StatMath.new().stat_definition(stat_id)
		selector.add_item("%s · %s" % [stat_id, str(definition.get("name", stat_id))])
		selector.set_item_metadata(selector.item_count - 1, stat_id)
	_body.add_child(selector)
	var value_label: Label = _label("", 22, COLOR_CYAN)
	_body.add_child(value_label)
	var note: Label = _label("Расчёт рассчитан тем же BuildResolver/StatMath, который передаёт характеристики в CombatSimulator.", 12, COLOR_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(note)
	var trace_view: RichTextLabel = RichTextLabel.new()
	trace_view.bbcode_enabled = true
	trace_view.fit_content = true
	trace_view.scroll_active = false
	trace_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(trace_view)
	var results: Dictionary = build.get("statResults", {})
	var render_stat: Callable = func(index: int) -> void:
		var stat_id: String = str(selector.get_item_metadata(index))
		var result: Dictionary = results.get(stat_id, {})
		var definition: Dictionary = StatMath.new().stat_definition(stat_id)
		value_label.text = "%s · %s %s" % [stat_id, _fmt(result.get("value", build["stats"].get(stat_id, 0.0))), str(result.get("unit", definition.get("unit", "")))]
		trace_view.clear()
		trace_view.append_text(_trace_text(result.get("trace", {}), 0))
	selector.item_selected.connect(render_stat)
	if selector.item_count > 0:
		selector.select(0)
		render_stat.call(0)
	_body.add_child(_label("АКТИВНЫЕ УМЕНИЯ · %d / 3" % _session.state.meta.skill_ids.size(), 16, COLOR_CYAN))
	var skill_catalog: BuildCatalog = BuildCatalog.new()
	if bool(skill_catalog.load_catalog().get("ok", false)):
		var skill_ids: Array = skill_catalog.skills.keys()
		skill_ids.sort()
		for skill_id_value: Variant in skill_ids:
			var skill_id: String = str(skill_id_value)
			var skill: Dictionary = skill_catalog.skills[skill_id]
			var skill_row: HBoxContainer = HBoxContainer.new()
			skill_row.add_theme_constant_override("separation", 10)
			_body.add_child(skill_row)
			var skill_info: VBoxContainer = VBoxContainer.new()
			skill_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			skill_row.add_child(skill_info)
			skill_info.add_child(_label("%s · %s · %s" % [skill_id, str(skill.get("name", skill_id)), str(skill.get("channel", "main")).to_upper()], 13, COLOR_TEXT))
			var description: Label = _label(str(skill.get("desc", "")), 11, COLOR_MUTED)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			skill_info.add_child(description)
			var is_equipped: bool = _session.state.meta.skill_ids.has(skill_id)
			var skill_button: Button = _button("СНЯТЬ" if is_equipped else "УСТАНОВИТЬ", is_equipped)
			skill_button.disabled = not is_equipped and _session.state.meta.skill_ids.size() >= 3
			skill_button.pressed.connect(_on_set_skill_equipped.bind(skill_id, not is_equipped))
			skill_row.add_child(skill_button)
	_body.add_child(_label("ПАССИВНЫЕ ПРОТОКОЛЫ · %d / 3" % _session.state.meta.passive_ids.size(), 16, COLOR_CYAN))
	var passive_ids: Array = skill_catalog.passives.keys()
	passive_ids.sort()
	for passive_id_value: Variant in passive_ids:
		var passive_id: String = str(passive_id_value)
		var passive: Dictionary = skill_catalog.passives[passive_id]
		var passive_row: HBoxContainer = HBoxContainer.new()
		passive_row.add_theme_constant_override("separation", 10)
		_body.add_child(passive_row)
		var passive_info: VBoxContainer = VBoxContainer.new()
		passive_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		passive_row.add_child(passive_info)
		passive_info.add_child(_label("%s · %s" % [passive_id, str(passive.get("name", passive_id))], 13, COLOR_TEXT))
		var passive_description: Label = _label(str(passive.get("desc", "")), 11, COLOR_MUTED)
		passive_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive_info.add_child(passive_description)
		var passive_equipped: bool = _session.state.meta.passive_ids.has(passive_id)
		var passive_button: Button = _button("СНЯТЬ" if passive_equipped else "УСТАНОВИТЬ", passive_equipped)
		passive_button.disabled = not passive_equipped and _session.state.meta.passive_ids.size() >= 3
		passive_button.pressed.connect(_on_set_passive_equipped.bind(passive_id, not passive_equipped))
		passive_row.add_child(passive_button)
	var tree_points: int = _session.tree_points_available()
	_body.add_child(_label("ДЕРЕВО СПЕЦИАЛИЗАЦИИ · %d / 60 ОЧКОВ · %d СВОБОДНО" % [_session.state.meta.tree_node_ids.size(), tree_points], 16, COLOR_CYAN))
	var tree_note: Label = _label("Один узел стоит 1 очко. Снятие узла стоит 10 кредитов за каждый снимаемый узел; зависимые узлы, теряющие требования, снимаются вместе.", 11, COLOR_MUTED)
	tree_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(tree_note)
	var branch_names: Dictionary = {"K": "КИНЕТИКА", "H": "ЭНЕРГИЯ И НАГРЕВ", "N": "НЕТРАННЕР", "D": "ДРОНЫ", "S": "ЗАЩИТА", "R": "РЕАКЦИЯ И ТАКТИКА", "X": "МЕЖВЕТОЧНЫЕ УЗЛЫ"}
	var branch_order: Array[String] = ["K", "H", "N", "D", "S", "R", "X"]
	var tree_resolver: BuildResolver = BuildResolver.new()
	var selected_tree: Array[String] = _session.state.meta.tree_node_ids
	var can_edit_tree: bool = _session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase)
	for branch: String in branch_order:
		_body.add_child(_label("%s · %s" % [branch, str(branch_names[branch])], 15, COLOR_TEXT))
		for tier: int in range(1, 5):
			var tier_nodes: Array[Dictionary] = []
			for node_value: Variant in skill_catalog.tree_nodes.values():
				var node: Dictionary = node_value
				if str(node.get("branch", "")) == branch and int(node.get("tier", 0)) == tier:
					tier_nodes.append(node)
			tier_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("pos", "")) < str(b.get("pos", "")))
			if tier_nodes.is_empty():
				continue
			_body.add_child(_label("T%d" % tier if branch != "X" else "МЕЖВЕТОЧНЫЙ", 11, COLOR_CYAN))
			var tree_grid: GridContainer = GridContainer.new()
			tree_grid.columns = 2
			tree_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tree_grid.add_theme_constant_override("h_separation", 12)
			tree_grid.add_theme_constant_override("v_separation", 8)
			_body.add_child(tree_grid)
			for node: Dictionary in tier_nodes:
				var node_card: PanelContainer = PanelContainer.new()
				node_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				tree_grid.add_child(node_card)
				var node_row: HBoxContainer = HBoxContainer.new()
				node_row.add_theme_constant_override("separation", 8)
				node_card.add_child(node_row)
				var node_info: VBoxContainer = VBoxContainer.new()
				node_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				node_row.add_child(node_info)
				var node_id: String = str(node.get("id", ""))
				var is_allocated: bool = selected_tree.has(node_id)
				var keystone_tag: String = " · KEYSTONE" if bool(node.get("keystone", false)) else ""
				node_info.add_child(_label("%s · %s%s" % [node_id, str(node.get("name", node_id)), keystone_tag], 12, COLOR_TEXT))
				var node_desc: Label = _label(str(node.get("desc", "")), 10, COLOR_MUTED)
				node_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				node_info.add_child(node_desc)
				var lock_reason: String = "ИЗУЧЕН" if is_allocated else tree_resolver.tree_node_lock_reason(node_id, selected_tree, _session.state.meta.operator.tree_points)
				var status: Label = _label(lock_reason if not lock_reason.is_empty() else "ДОСТУПЕН · 1 ОЧКО", 9, COLOR_CYAN if is_allocated or lock_reason.is_empty() else COLOR_MUTED)
				status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				node_info.add_child(status)
				var node_button: Button = _button("СНЯТЬ" if is_allocated else "ИЗУЧИТЬ", is_allocated)
				node_button.disabled = not can_edit_tree or (not is_allocated and not lock_reason.is_empty()) or (is_allocated and _session.state.meta.protected_bank.credits < 10.0)
				node_button.pressed.connect(_on_set_tree_node.bind(node_id, not is_allocated))
				node_row.add_child(node_button)
	var back: Button = _button("НАЗАД В ГАРАЖ", false)
	back.pressed.connect(_show_garage)
	_body.add_child(back)
	_footer.text = "CALCTRACE · %d СТАТОВ · ИСТОЧНИКИ, УСЛОВИЯ И ПРОМЕЖУТОЧНЫЕ ЭТАПЫ" % stat_ids.size()

func _show_tactics() -> void:
	_screen = "tactics"
	_clear_body()
	_body.add_child(_label("SERVER · РЕДАКТОР ТАКТИКИ", 12, COLOR_CYAN))
	_body.add_child(_label("Боевой профиль", 27, COLOR_TEXT))
	if _session.state == null:
		return
	if _session.garage_level("SERVER") < 1:
		_body.add_child(_label("Редактор требует SERVER уровня 1.", 13, COLOR_AMBER))
	else:
		var profiles_row: HFlowContainer = HFlowContainer.new()
		_body.add_child(profiles_row)
		for profile: Dictionary in _session.state.meta.tactics:
			var selected: bool = str(profile.get("id", "")) == _session.state.meta.active_tactic_id
			var profile_button: Button = _button("%s%s" % [str(profile.get("name", profile.get("id", ""))), " · АКТИВЕН" if selected else ""], selected)
			profile_button.disabled = selected
			profile_button.pressed.connect(_on_select_tactic.bind(str(profile.get("id", ""))))
			profiles_row.add_child(profile_button)
		if _session.garage_level("SERVER") >= 2:
			var duplicate_button: Button = _button("КОПИРОВАТЬ ПРОФИЛЬ", false)
			duplicate_button.disabled = _session.state.meta.tactics.size() >= 5
			duplicate_button.pressed.connect(_on_duplicate_tactic)
			profiles_row.add_child(duplicate_button)
		var tactic: Dictionary = _session.active_tactic()
		var rules: Array = tactic.get("rules", []).duplicate(true)
		rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority", 0)) > int(b.get("priority", 0)))
		_body.add_child(_label("АКТИВНЫЙ ПРОФИЛЬ · %d / 12 ПРАВИЛ" % rules.size(), 14, COLOR_CYAN))
		for rule_value: Variant in rules:
			if not rule_value is Dictionary:
				continue
			var rule: Dictionary = rule_value
			var rule_id: String = str(rule.get("id", ""))
			var card: PanelContainer = PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_body.add_child(card)
			var content: VBoxContainer = VBoxContainer.new()
			card.add_child(content)
			var order_row: HBoxContainer = HBoxContainer.new()
			content.add_child(order_row)
			var enabled: CheckButton = CheckButton.new()
			enabled.text = "P%d · %s" % [int(rule.get("priority", 0)), str(rule.get("note", rule.get("skillId", "Правило")))]
			enabled.button_pressed = bool(rule.get("enabled", false))
			enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			enabled.toggled.connect(_on_tactic_rule_enabled.bind(rule_id))
			order_row.add_child(enabled)
			var up: Button = _button("↑", false)
			up.custom_minimum_size.x = 45
			up.pressed.connect(_on_move_tactic_rule.bind(rule_id, -1))
			order_row.add_child(up)
			var down: Button = _button("↓", false)
			down.custom_minimum_size.x = 45
			down.pressed.connect(_on_move_tactic_rule.bind(rule_id, 1))
			order_row.add_child(down)
			var editors: HBoxContainer = HBoxContainer.new()
			content.add_child(editors)
			var skill_selector: OptionButton = OptionButton.new()
			skill_selector.custom_minimum_size.x = 220
			var available_skills: Array[String] = ["AUTO"]
			available_skills.append_array(_session.state.meta.skill_ids)
			for skill_id: String in available_skills:
				skill_selector.add_item(skill_id)
				skill_selector.set_item_metadata(skill_selector.item_count - 1, skill_id)
				if skill_id == str(rule.get("skillId", "AUTO")):
					skill_selector.select(skill_selector.item_count - 1)
			skill_selector.item_selected.connect(_on_tactic_skill_selected.bind(rule_id, skill_selector))
			editors.add_child(skill_selector)
			var target_selector: OptionButton = OptionButton.new()
			target_selector.custom_minimum_size.x = 190
			var targets: Dictionary = {"nearest": "Ближайшая", "lowestHPPercent": "Мало HP %", "self": "Себя", "imminentCast": "Кастует", "boss": "Босс", "infected": "Заражённая", "marked": "Помеченная", "otherEnemy": "Другая цель", "secondary": "Вторичная"}
			for target_id: String in ["nearest", "lowestHPPercent", "self", "imminentCast", "boss", "infected", "marked", "otherEnemy", "secondary"]:
				target_selector.add_item(str(targets[target_id]))
				target_selector.set_item_metadata(target_selector.item_count - 1, target_id)
				if target_id == str(rule.get("target", "nearest")):
					target_selector.select(target_selector.item_count - 1)
			target_selector.item_selected.connect(_on_tactic_target_selected.bind(rule_id, target_selector))
			editors.add_child(target_selector)
			var condition: Dictionary = rule.get("conditions", [{}])[0] if not rule.get("conditions", []).is_empty() else {"kind": "always"}
			var condition_row: HBoxContainer = HBoxContainer.new()
			content.add_child(condition_row)
			condition_row.add_child(_label("ЕСЛИ", 11, COLOR_MUTED))
			var condition_selector: OptionButton = OptionButton.new()
			condition_selector.custom_minimum_size.x = 220
			var condition_kinds: Dictionary = {"always": "Всегда", "hpBelow": "HP ниже доли", "hpAbove": "HP выше доли", "shieldBelow": "Щит ниже доли", "energyAtLeast": "Энергия ≥", "energyBelow": "Энергия <", "heatAtLeast": "Нагрев ≥", "heatBelow": "Нагрев <", "heatLocked": "Перегрев блокирует", "enemiesAtLeast": "Врагов ≥", "enemiesAtMost": "Врагов ≤", "enemyCasting": "Враг кастует", "droneAlive": "Дронов активно ≥", "timeAtLeast": "Время боя ≥ мс"}
			var condition_order: Array[String] = ["always", "hpBelow", "hpAbove", "shieldBelow", "energyAtLeast", "energyBelow", "heatAtLeast", "heatBelow", "heatLocked", "enemiesAtLeast", "enemiesAtMost", "enemyCasting", "droneAlive", "timeAtLeast"]
			for condition_kind: String in condition_order:
				condition_selector.add_item(str(condition_kinds[condition_kind]))
				condition_selector.set_item_metadata(condition_selector.item_count - 1, condition_kind)
				if condition_kind == str(condition.get("kind", "always")):
					condition_selector.select(condition_selector.item_count - 1)
			condition_selector.item_selected.connect(_on_tactic_condition_selected.bind(rule_id, condition_selector, condition))
			condition_row.add_child(condition_selector)
			if condition.has("value"):
				var threshold: SpinBox = SpinBox.new()
				threshold.min_value = 0.0
				threshold.max_value = 100000.0
				threshold.step = 0.05 if str(condition.get("kind", "")) in ["hpBelow", "hpAbove", "shieldBelow"] else 1.0
				threshold.value = float(condition.get("value", 0.0))
				threshold.value_changed.connect(_on_tactic_condition_value.bind(rule_id, condition_selector, threshold))
				condition_row.add_child(threshold)
			var details: Label = _label("Примечание: %s" % str(rule.get("note", "нет")), 10, COLOR_MUTED)
			details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(details)
		var add_row: HBoxContainer = HBoxContainer.new()
		_body.add_child(add_row)
		var add_selector: OptionButton = OptionButton.new()
		add_selector.add_item("AUTO")
		add_selector.set_item_metadata(0, "AUTO")
		for skill_id: String in _session.state.meta.skill_ids:
			add_selector.add_item(skill_id)
			add_selector.set_item_metadata(add_selector.item_count - 1, skill_id)
		add_row.add_child(add_selector)
		var add_rule: Button = _button("ДОБАВИТЬ ПРАВИЛО", false)
		add_rule.disabled = rules.size() >= 12
		add_rule.pressed.connect(_on_add_tactic_rule.bind(add_selector))
		add_row.add_child(add_rule)
	_body.add_child(_button("НАЗАД В ГАРАЖ", false))
	var back_button: Button = _body.get_child(_body.get_child_count() - 1) as Button
	back_button.pressed.connect(_show_garage)
	_footer.text = "ПРИОРИТЕТЫ · ЭКИПИРОВАННЫЕ УМЕНИЯ · СЕЛЕКТОРЫ ЦЕЛИ · УСЛОВИЯ"

func _on_select_tactic(profile_id: String) -> void:
	if _session.select_tactic(profile_id):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_duplicate_tactic() -> void:
	if _session.duplicate_active_tactic():
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_tactic_rule_enabled(enabled: bool, rule_id: String) -> void:
	if _session.set_tactic_rule_enabled(rule_id, enabled):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_move_tactic_rule(rule_id: String, direction: int) -> void:
	if _session.move_tactic_rule(rule_id, direction):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_tactic_skill_selected(index: int, rule_id: String, selector: OptionButton) -> void:
	var skill_id: String = str(selector.get_item_metadata(index))
	if _session.set_tactic_rule_skill(rule_id, skill_id):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_tactic_target_selected(index: int, rule_id: String, selector: OptionButton) -> void:
	var target_id: String = str(selector.get_item_metadata(index))
	if _session.set_tactic_rule_target(rule_id, target_id):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_tactic_condition_selected(index: int, rule_id: String, selector: OptionButton, previous: Dictionary) -> void:
	var kind: String = str(selector.get_item_metadata(index))
	var condition: Dictionary = {"kind": kind}
	if kind in ["hpBelow", "hpAbove", "shieldBelow"]:
		condition["value"] = float(previous.get("value", 0.5))
	elif kind in ["energyAtLeast", "energyBelow", "heatAtLeast", "heatBelow", "enemiesAtLeast", "enemiesAtMost", "droneAlive", "timeAtLeast"]:
		condition["value"] = float(previous.get("value", 1.0))
	if _session.set_tactic_rule_condition(rule_id, condition):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_tactic_condition_value(value: float, rule_id: String, selector: OptionButton, _spinbox: SpinBox) -> void:
	var kind: String = str(selector.get_item_metadata(selector.selected))
	if _session.set_tactic_rule_condition(rule_id, {"kind": kind, "value": value}):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _on_add_tactic_rule(selector: OptionButton) -> void:
	var skill_id: String = str(selector.get_item_metadata(selector.selected))
	if _session.add_tactic_rule(skill_id):
		_show_tactics()
	else:
		_footer.text = _session.last_error

func _show_simulation_lab() -> void:
	_screen = "simulation_lab"
	_clear_body()
	_body.add_child(_label("ГАРАЖ · ДЕТЕРМИНИРОВАННЫЕ ПРОГОНЫ", 12, COLOR_CYAN))
	_body.add_child(_label("Simulation Lab", 28, COLOR_TEXT))
	_body.add_child(_label("Сравнение текущего снаряжения с кандидатом на одинаковых seed через боевой CombatSimulator (шаг 100 мс). Предмет в игре не меняется.", 12, COLOR_MUTED))
	if _session.state == null:
		return
	if _session.state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase):
		_body.add_child(_label("Лаборатория доступна только между выездами.", 13, COLOR_AMBER))
	else:
		var row: HBoxContainer = HBoxContainer.new()
		_body.add_child(row)
		var slot_selector: OptionButton = OptionButton.new()
		for slot_value: Variant in _session.state.meta.equipment.keys():
			slot_selector.add_item(str(slot_value))
			slot_selector.set_item_metadata(slot_selector.item_count - 1, str(slot_value))
			if _simulation_slot.is_empty():
				_simulation_slot = str(slot_value)
				_simulation_item_id = ""
			if _simulation_slot == str(slot_value):
				slot_selector.select(slot_selector.item_count - 1)
		slot_selector.item_selected.connect(_on_simulation_slot_selected.bind(slot_selector))
		row.add_child(slot_selector)
		var item_selector: OptionButton = OptionButton.new()
		var candidates: Array[Dictionary] = _session.simulation_equipment_candidates(_simulation_slot)
		for candidate: Dictionary in candidates:
			item_selector.add_item(str(candidate.get("label", candidate.get("itemId", "Предмет"))))
			item_selector.set_item_metadata(item_selector.item_count - 1, str(candidate.get("itemId", "")))
			if _simulation_item_id.is_empty():
				_simulation_item_id = str(candidate.get("itemId", ""))
			if _simulation_item_id == str(candidate.get("itemId", "")):
				item_selector.select(item_selector.item_count - 1)
		item_selector.disabled = item_selector.item_count == 0
		item_selector.item_selected.connect(_on_simulation_item_selected.bind(item_selector))
		row.add_child(item_selector)
		var enemy_selector: OptionButton = OptionButton.new()
		var enemy_catalog: EnemyCatalog = EnemyCatalog.new()
		var catalog_result: Dictionary = enemy_catalog.load_catalog()
		if bool(catalog_result.get("ok", false)):
			for enemy_id: String in enemy_catalog.enemies.keys():
				var enemy: Dictionary = enemy_catalog.get_template(enemy_id)
				enemy_selector.add_item("ВРАГ · %s" % str(enemy.get("name", enemy_id)))
				enemy_selector.set_item_metadata(enemy_selector.item_count - 1, enemy_id)
			for boss_id: String in enemy_catalog.bosses.keys():
				var boss: Dictionary = enemy_catalog.get_template(boss_id)
				enemy_selector.add_item("БОСС · %s" % str(boss.get("name", boss_id)))
				enemy_selector.set_item_metadata(enemy_selector.item_count - 1, boss_id)
		for index: int in range(enemy_selector.item_count):
			if str(enemy_selector.get_item_metadata(index)) == _simulation_enemy_id:
				enemy_selector.select(index)
		enemy_selector.item_selected.connect(_on_simulation_enemy_selected.bind(enemy_selector))
		row.add_child(enemy_selector)
		var runs: SpinBox = SpinBox.new()
		runs.min_value = 1
		runs.max_value = SimulationLab.MAX_BATCH_RUNS
		runs.step = 1
		runs.value = 3
		row.add_child(runs)
		var compare: Button = _button("ЗАПУСТИТЬ ПАРНОЕ СРАВНЕНИЕ", true)
		compare.disabled = _simulation_item_id.is_empty() or not bool(catalog_result.get("ok", false))
		compare.pressed.connect(_on_simulation_compare.bind(runs))
		_body.add_child(compare)
		if not _simulation_report.is_empty():
			if not bool(_simulation_report.get("ok", false)):
				_body.add_child(_label("Симуляция остановлена: %s" % str(_simulation_report.get("error", "ошибка")), 13, COLOR_RED))
			else:
				var results: Array = _simulation_report.get("results", [])
				if results.size() == 2:
					_body.add_child(_label("СЦЕНАРИЙ %s · ГЛУБИНА %d · %d ПАРНЫХ ПРОГОНА" % [str(_simulation_report.get("enemyId", "")), int(_simulation_report.get("depth", 1)), int(_simulation_report.get("runs", 0))], 13, COLOR_CYAN))
					_body.add_child(_simulation_result_card("ТЕКУЩАЯ СБОРКА", results[0]))
					_body.add_child(_simulation_result_card("КАНДИДАТ · %s" % _simulation_item_id, results[1]))
	_body.add_child(_button("НАЗАД В ГАРАЖ", false))
	var back: Button = _body.get_child(_body.get_child_count() - 1) as Button
	back.pressed.connect(_show_garage)
	_footer.text = "ПАРНЫЕ SEED · ТОТ ЖЕ СИМУЛЯТОР, ЧТО И В ИГРЕ · 100 МС"

func _simulation_result_card(title: String, result: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var content: VBoxContainer = VBoxContainer.new()
	card.add_child(content)
	content.add_child(_label(title, 14, COLOR_TEXT))
	content.add_child(_label("Победы %.0f%% · среднее время %.1f с · урон нанесён %.1f · получен %.1f" % [100.0 * float(result.get("winRate", 0.0)), float(result.get("averageTimeMs", 0.0)) / 1000.0, float(result.get("averageDamageDealt", 0.0)), float(result.get("averageDamageTaken", 0.0))], 11, COLOR_MUTED))
	content.add_child(_label("Среднее HP в конце %.1f%% · минимум HP %.1f%% · поражения %d · таймауты %d" % [100.0 * float(result.get("averageHpFraction", 0.0)), 100.0 * float(result.get("averageLowHpFraction", 0.0)), int(result.get("defeats", 0)), int(result.get("timeouts", 0))], 11, COLOR_MUTED))
	return card

func _on_simulation_slot_selected(index: int, selector: OptionButton) -> void:
	_simulation_slot = str(selector.get_item_metadata(index))
	_simulation_item_id = ""
	_simulation_report.clear()
	_show_simulation_lab()

func _on_simulation_item_selected(index: int, selector: OptionButton) -> void:
	_simulation_item_id = str(selector.get_item_metadata(index))
	_simulation_report.clear()
	_show_simulation_lab()

func _on_simulation_enemy_selected(index: int, selector: OptionButton) -> void:
	_simulation_enemy_id = str(selector.get_item_metadata(index))
	_simulation_report.clear()
	_show_simulation_lab()

func _on_simulation_compare(runs: SpinBox) -> void:
	_simulation_report = _session.simulate_equipment_comparison(_simulation_slot, _simulation_item_id, _simulation_enemy_id, int(runs.value))
	_show_simulation_lab()

func _show_quest_journal() -> void:
	_screen = "quest_journal"
	_clear_body()
	_body.add_child(_label("КАМПАНИЯ · ФРАКЦИИ · ЗАДАНИЯ", 12, COLOR_CYAN))
	_body.add_child(_label("Журнал", 28, COLOR_TEXT))
	if _session.state == null:
		return
	var can_accept: bool = _session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase)
	_body.add_child(_label("VANTA %d · RUST %d · CHOIR %d · ECHO %d" % [int(_session.state.meta.reputation.get("F_VANTA", 0)), int(_session.state.meta.reputation.get("F_RUST", 0)), int(_session.state.meta.reputation.get("F_CHOIR", 0)), int(_session.state.meta.reputation.get("F_ECHO", 0))], 13, COLOR_AMBER))
	for quest: Dictionary in _session.quest_journal():
		var status: String = str(quest.get("status", "AVAILABLE"))
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(card)
		var content: VBoxContainer = VBoxContainer.new()
		card.add_child(content)
		content.add_child(_label("%s · %s · СЕКТОР %d+" % [str(quest.get("name", quest.get("id", "Квест"))), status, int(quest.get("minDepth", 1))], 15, COLOR_CYAN if status == "ACTIVE" else COLOR_TEXT))
		content.add_child(_label(str(quest.get("desc", "")), 11, COLOR_MUTED))
		if status in ["ACTIVE", "PAUSED"]:
			var stage_index: int = clampi(int(quest.get("currentStage", 1)) - 1, 0, 2)
			var stage: Dictionary = quest.get("stages", [])[stage_index]
			content.add_child(_label("ЭТАП %d · %s" % [stage_index + 1, str(stage.get("name", ""))], 12, COLOR_AMBER))
			content.add_child(_label(str(stage.get("text", "")), 11, COLOR_MUTED))
		elif status in ["AVAILABLE", "PAUSED", "FAILED"] and bool(quest.get("available", false)) and can_accept:
			var accept: Button = _button("ВОЗОБНОВИТЬ ЗАДАНИЕ" if status == "PAUSED" else "НАЧАТЬ ЗАНОВО" if status == "FAILED" else "ПРИНЯТЬ ЗАДАНИЕ", false)
			accept.pressed.connect(_on_accept_quest.bind(str(quest.get("id", ""))))
			content.add_child(accept)
	_body.add_child(_button("НАЗАД В ГАРАЖ", false))
	var back: Button = _body.get_child(_body.get_child_count() - 1) as Button
	back.pressed.connect(_show_garage)
	_footer.text = "РЕШЕНИЯ И РЕПУТАЦИЯ СОХРАНЯЮТСЯ В META"

func _on_accept_quest(quest_id: String) -> void:
	if not _session.accept_quest(quest_id):
		_footer.text = _session.last_error
	_show_quest_journal()

func _on_resolve_quest_choice(quest_id: String, choice_id: String) -> void:
	if not _session.resolve_quest_choice(quest_id, choice_id):
		_footer.text = _session.last_error
	_show_road()

func _show_inventory() -> void:
	_screen = "inventory"
	_clear_body()
	_body.add_child(_label("СКЛАД   /   ПОСТОЯННАЯ СОБСТВЕННОСТЬ", 12, COLOR_CYAN))
	_body.add_child(_label("Инвентарь", 28, COLOR_TEXT))
	if _session.state == null:
		return
	var inventory_catalog: ItemCatalog = ItemCatalog.new()
	var inventory_catalog_result: Dictionary = inventory_catalog.load_catalog()
	if not bool(inventory_catalog_result.get("ok", false)):
		_body.add_child(_label("Каталог предметов недоступен: %s" % str(inventory_catalog_result.get("error", "")), 13, COLOR_RED))
		return
	var can_edit_items: bool = _session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase)
	var reward_formula: CydleFormula = CydleFormula.new()
	for item_value: Dictionary in _session.state.meta.inventory:
		var template: Dictionary = inventory_catalog.get_template(str(item_value.get("templateId", "")))
		var name: String = str(template.get("name", item_value.get("templateId", "Предмет")))
		var row: HBoxContainer = HBoxContainer.new()
		_body.add_child(row)
		var item_info: VBoxContainer = VBoxContainer.new()
		item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_info)
		var item_actions: VBoxContainer = VBoxContainer.new()
		row.add_child(item_actions)
		item_info.add_child(_label("%s  ·  T%d  ·  %s  ·  прочность %d%%  ·  TR %d" % [name, int(item_value.get("techLevel", 1)), str(item_value.get("rarity", "COMMON")), int(item_value.get("durability", 100)), int(item_value.get("tr", 0))], 13, COLOR_TEXT))
		for affix_index: int in range(item_value.get("affixes", []).size()):
			var affix: Dictionary = item_value["affixes"][affix_index]
			var affix_label: Label = _label("%s T%d · %s (%.2f; диапазон %.2f–%.2f)" % [str(affix.get("affixId", "?")), int(affix.get("tier", 1)), str(inventory_catalog.get_affix(str(affix.get("affixId", ""))).get("name", "Аффикс")), float(affix.get("value", 0.0)), float(affix.get("min", 0.0)), float(affix.get("max", 0.0))], 10, COLOR_MUTED)
			affix_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item_info.add_child(affix_label)
		var item_id: String = str(item_value.get("itemId", ""))
		var active_slot: String = _session.equipped_slot(item_id)
		if not active_slot.is_empty():
			item_info.add_child(_label("УСТАНОВЛЕН · %s" % active_slot, 10, COLOR_CYAN))
			var unequip_button: Button = _button("СНЯТЬ %s" % active_slot, false)
			unequip_button.disabled = not can_edit_items
			unequip_button.pressed.connect(_on_unequip_item.bind(active_slot))
			item_actions.add_child(unequip_button)
		if bool(item_value.get("secured", false)):
			for slot: String in _session.valid_equipment_slots(item_id):
				if slot == active_slot:
					continue
				var equip_button: Button = _button("НАДЕТЬ · %s" % slot, false)
				equip_button.disabled = not can_edit_items
				equip_button.pressed.connect(_on_equip_item.bind(slot, item_id))
				item_actions.add_child(equip_button)
		if bool(item_value.get("secured", false)) and active_slot.is_empty():
			var sell_quote: Dictionary = _session.item_disposal_quote(item_id, "SELL")
			if bool(sell_quote.get("valid", false)):
				var sell_button: Button = _button("ПРОДАТЬ · %d CREDITS" % int(sell_quote.get("credits", 0)), false)
				sell_button.disabled = not can_edit_items
				sell_button.tooltip_text = "Цена составляет 25%% от стоимости покупки по TechLevel и редкости."
				sell_button.pressed.connect(_confirm_item_disposal.bind(item_id, "SELL", int(sell_quote.get("credits", 0)), 0, 0))
				item_actions.add_child(sell_button)
			var dismantle_quote: Dictionary = _session.item_disposal_quote(item_id, "DISMANTLE")
			if bool(dismantle_quote.get("valid", false)):
				var dismantle_button: Button = _button("РАЗОБРАТЬ · %d SCR / %d DATA" % [int(dismantle_quote.get("scrap", 0)), int(dismantle_quote.get("data", 0))], false)
				dismantle_button.disabled = not can_edit_items
				dismantle_button.tooltip_text = "Вернуть материалы по лимиту стоимости изготовления."
				dismantle_button.pressed.connect(_confirm_item_disposal.bind(item_id, "DISMANTLE", 0, int(dismantle_quote.get("scrap", 0)), int(dismantle_quote.get("data", 0))))
				item_actions.add_child(dismantle_button)
		if bool(item_value.get("secured", false)):
			if float(item_value.get("durability", 100.0)) < 100.0:
				var repair_tech: int = int(item_value.get("techLevel", 1))
				var repair_cost: int = mini(ceili((100.0 - float(item_value.get("durability", 100.0))) / 10.0 * (2.0 + float(repair_tech) / 5.0)), ceili((25.0 + 7.0 * float(repair_tech)) * reward_formula.reward_scale(float(repair_tech))))
				if str(template.get("category", "")) == "DRONE" and _session.garage_level("HANGAR") >= 3:
					repair_cost = ceili(float(repair_cost) * 0.8)
				var repair_button: Button = _button("РЕМОНТ · %d SCRAP" % repair_cost, false)
				repair_button.disabled = not can_edit_items
				repair_button.pressed.connect(_on_repair_item.bind(str(item_value.get("itemId", ""))))
				item_actions.add_child(repair_button)
			for affix_index: int in range(item_value.get("affixes", []).size()):
				var affix: Dictionary = item_value["affixes"][affix_index]
				var item_tech: int = int(item_value.get("techLevel", 1))
				var max_affix_tier: int = clampi(int(ceil(float(item_tech) / 4.0)), 1, 4)
				var replace_quote: Dictionary = _session.affix_replacement_options(item_id, affix_index)
				var replace_button: Button = _button("ЗАМЕНИТЬ %s · 8 TR / %d DATA" % [str(affix.get("affixId", "АФФИКС")), int(replace_quote.get("data", 0))], false)
				replace_button.disabled = not can_edit_items or not bool(replace_quote.get("valid", false)) or not bool(replace_quote.get("affordable", false)) or replace_quote.get("options", []).is_empty()
				replace_button.tooltip_text = str(replace_quote.get("error", "Выбрать другой совместимый аффикс"))
				replace_button.pressed.connect(_show_affix_picker.bind(item_id, affix_index))
				item_actions.add_child(replace_button)
				if _session.garage_level("WORKSHOP") >= 3 and str(item_value.get("rarity", "")) != "UNIQUE" and int(affix.get("tier", 1)) < max_affix_tier:
					var tier_scrap: int = ceili(20.0 * reward_formula.reward_scale(float(item_tech)))
					var tier_data: int = ceili(5.0 * reward_formula.reward_scale(float(item_tech)))
					var tier_button: Button = _button("TIER UP · 6 TR / %d SCR / %d DATA" % [tier_scrap, tier_data], false)
					tier_button.disabled = not can_edit_items or float(item_value.get("tr", 0.0)) < 6.0 or _session.state.meta.protected_bank.scrap < tier_scrap or _session.state.meta.protected_bank.data < tier_data
					tier_button.pressed.connect(_on_upgrade_item_affix_tier.bind(item_id, affix_index))
					item_actions.add_child(tier_button)
				var calibration_cost: int = ceili(10.0 * reward_formula.reward_scale(float(item_value.get("techLevel", 1))))
				var calibrate_button: Button = _button("%s · 3 TR / %d SCRAP" % [str(affix.get("affixId", "AF")), calibration_cost], false)
				calibrate_button.disabled = not can_edit_items or _session.garage_level("WORKSHOP") < 2 or str(item_value.get("rarity", "")) == "UNIQUE" or float(item_value.get("tr", 0.0)) < 3.0
				calibrate_button.pressed.connect(_on_calibrate_item_affix.bind(str(item_value.get("itemId", "")), affix_index))
				item_actions.add_child(calibrate_button)
			var add_quote: Dictionary = _session.affix_replacement_options(item_id)
			if bool(add_quote.get("valid", false)):
				var add_button: Button = _button("ДОБАВИТЬ АФФИКС · 10 TR / %d SCR / %d DATA" % [int(add_quote.get("scrap", 0)), int(add_quote.get("data", 0))], false)
				add_button.disabled = not can_edit_items or not bool(add_quote.get("affordable", false)) or add_quote.get("options", []).is_empty()
				add_button.tooltip_text = str(add_quote.get("error", "Добавить аффикс в свободный слот"))
				add_button.pressed.connect(_show_affix_picker.bind(item_id, -1))
				item_actions.add_child(add_button)
			var current_tech: int = int(item_value.get("techLevel", 1))
			var max_tech: int = maxi(4, _session.state.meta.unlocked_forpost)
			for target_tech: int in range(current_tech + 1, max_tech + 1):
				var quote: Dictionary = _session.tech_calibration_quote(item_id, target_tech)
				if not bool(quote.get("valid", false)):
					continue
				var tech_button: Button = _button("TECH · T%d · %d SCR / %d DATA / %d CORE" % [target_tech, int(quote["scrap"]), int(quote["data"]), int(quote["coreCount"])], false)
				tech_button.disabled = not can_edit_items or not bool(quote.get("affordable", false))
				tech_button.tooltip_text = str(quote.get("error", "CalibrationCore group %d" % int(quote["coreGroup"])))
				tech_button.pressed.connect(_on_calibrate_item_tech.bind(item_id, target_tech))
				item_actions.add_child(tech_button)
	_body.add_child(_label("ЧЕРТЕЖИ   /   ИЗГОТОВЛЕНИЕ БАЗОВОГО СНАРЯЖЕНИЯ", 12, COLOR_CYAN))
	var blueprint_count: int = 0
	var craft_max_tech: int = maxi(4, _session.state.meta.unlocked_forpost)
	for craft_template: Dictionary in inventory_catalog.all_templates():
		var template_id: String = str(craft_template.get("id", ""))
		var quote: Dictionary = _session.base_item_craft_quote(template_id, 1)
		if not bool(quote.get("valid", false)):
			continue
		blueprint_count += 1
		var craft_row: HBoxContainer = HBoxContainer.new()
		_body.add_child(craft_row)
		var craft_name: Label = _label("%s · %s" % [str(craft_template.get("name", template_id)), template_id], 11, COLOR_TEXT)
		craft_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		craft_row.add_child(craft_name)
		var tech_picker: OptionButton = OptionButton.new()
		for tech: int in range(1, craft_max_tech + 1):
			tech_picker.add_item("T%d" % tech, tech)
		craft_row.add_child(tech_picker)
		var craft_button: Button = _button("ИЗГОТОВИТЬ · %d SCR / %d DATA" % [int(quote.get("scrap", 0)), int(quote.get("data", 0))], true)
		craft_button.disabled = not can_edit_items or not bool(quote.get("affordable", false))
		craft_button.tooltip_text = str(quote.get("error", "COMMON · требуется постоянный чертёж"))
		craft_row.add_child(craft_button)
		craft_button.pressed.connect(_on_craft_base_item.bind(template_id, tech_picker))
		tech_picker.item_selected.connect(_refresh_base_craft_button.bind(template_id, tech_picker, craft_button, can_edit_items))
	if blueprint_count == 0:
		_body.add_child(_label("Постоянные чертежи выдаются решениями квестов и завершением технических контрактов.", 11, COLOR_MUTED))
	if not _session.state.meta.disassembly_history.is_empty():
		_body.add_child(_label("ИСТОРИЯ РАЗБОРА · %d / 100" % _session.state.meta.disassembly_history.size(), 12, COLOR_CYAN))
		if _session.can_undo_last_dismantle():
			var undo: Button = _button("ОТМЕНИТЬ ПОСЛЕДНИЙ РАЗБОР", true)
			undo.tooltip_text = "Вернёт тот же предмет и спишет полученные материалы. Доступно до входа в следующий узел."
			undo.pressed.connect(_on_undo_last_dismantle)
			_body.add_child(undo)
		var history: Array = _session.state.meta.disassembly_history.duplicate(true)
		history.reverse()
		for record: Dictionary in history:
			_body.add_child(_label("%s · %s · %s · +%d SCR / +%d DATA · seed %s" % [str(record.get("itemId", "")), str(record.get("reason", "MANUAL")), "ОТМЕНЕНО" if bool(record.get("undone", false)) else "РАЗОБРАН", int(record.get("scrap", 0)), int(record.get("data", 0)), str(record.get("seed", "—"))], 10, COLOR_MUTED))
	var back: Button = _button("НАЗАД В ГАРАЖ", false)
	back.pressed.connect(_show_garage)
	_body.add_child(back)
	_footer.text = "ПРЕДМЕТЫ ХРАНЯТСЯ В ЛОКАЛЬНОМ ПРОФИЛЕ"

func _show_road() -> void:
	_screen = "road"
	_clear_body()
	if _session.state == null:
		_body.add_child(_label("Создайте профиль в гараже, чтобы начать выезд.", 16, COLOR_TEXT))
		return
	if _session.state.run == null or ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase):
		_body.add_child(_label("ДОРОГА   /   ВЫЕЗД НЕ НАЧАТ", 12, COLOR_CYAN))
		_body.add_child(_label("Сформируйте маршрут", 27, COLOR_TEXT))
		_add_escalation_selector()
		var start: Button = _button("НАЧАТЬ ВЫЕЗД", true)
		start.pressed.connect(_on_start_expedition)
		_body.add_child(start)
		for offer: Dictionary in _session.available_contract_offers():
			var contract_button: Button = _button("ВЫЕЗД ПО КОНТРАКТУ · %s" % str(offer.get("name", offer.get("id", ""))), false)
			contract_button.tooltip_text = str(offer.get("desc", ""))
			contract_button.pressed.connect(_on_start_expedition.bind(str(offer.get("id", ""))))
			_body.add_child(contract_button)
		return
	var run: GameSaveState.RunState = _session.state.run
	_body.add_child(_label("СЕКТОР %02d   /   %s   /   %s" % [run.depth, run.biome, run.phase], 12, COLOR_CYAN))
	_body.add_child(_label("Маршрут", 27, COLOR_TEXT))
	var resources: Dictionary = run.resources
	_body.add_child(_label("ТОПЛИВО %d/%d   ·   КОРПУС %d/%d   ·   РОЗЫСК %d" % [int(resources.get("fuel", 0)), int(resources.get("maxFuel", 0)), int(resources.get("hull", 0)), int(resources.get("maxHull", 0)), int(run.wanted)], 13, COLOR_AMBER))
	var autopilot_button: Button = _button("АВТОПИЛОТ · ДО БЕЗОПАСНОЙ ОСТАНОВКИ · ЛИМИТ 12 ЧАСОВ", true)
	autopilot_button.pressed.connect(_on_autopilot)
	_body.add_child(autopilot_button)
	var offline_toggle: CheckButton = CheckButton.new()
	offline_toggle.text = "Продолжать автопилот в офлайне (реальное время, максимум 12 часов)"
	offline_toggle.button_pressed = run.autopilot_enabled
	offline_toggle.toggled.connect(_on_toggle_offline_autopilot)
	_body.add_child(offline_toggle)
	if not _session.last_autopilot_report.is_empty():
		var report: Dictionary = _session.last_autopilot_report
		var report_label: Label = _label("АВТОПИЛОТ · %s · %s · узлов %d · боёв %d · симуляция %s" % [str(report.get("status", "")), str(report.get("reason", "")), int(report.get("nodesVisited", 0)), int(report.get("battles", 0)), _fmt(float(report.get("simulatedMs", 0.0)) / 1000.0) + " с"], 12, COLOR_CYAN)
		report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(report_label)
	var active_contract: Dictionary = run.contract
	if not active_contract.is_empty():
		_body.add_child(_label("КОНТРАКТ %s · %s · БОЕВЫХ УЗЛОВ %d" % [str(active_contract.get("id", "")), str(active_contract.get("status", "")), int(active_contract.get("combatNodes", 0))], 12, COLOR_CYAN))
	if not run.escalation_ids.is_empty():
		_body.add_child(_label("ЭСКАЛАЦИЯ · %s" % " · ".join(run.escalation_ids), 11, COLOR_AMBER))
	if run.phase == "NODE":
		_show_current_node(run)
	elif run.phase == "CHECKPOINT":
		_show_checkpoint(run)
	else:
		var graph: Dictionary = run.graph
		var map_intel: Dictionary = _session.route_intel().get("nodes", {})
		for layer_index: int in range(graph.get("layers", []).size()):
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_body.add_child(row)
			row.add_child(_label("L%d" % (layer_index + 1), 10, COLOR_MUTED))
			for node: Dictionary in graph["layers"][layer_index]:
				var node_id: String = str(node.get("id", ""))
				var reachable: bool = _contains_node(_session.reachable_nodes(), node_id)
				var visited: bool = run.visited_node_ids.has(node_id)
				var intel: Dictionary = map_intel.get(node_id, {})
				var node_type: String = str(intel.get("type", "НЕИЗВЕСТНО"))
				var secondary: String = "%s · %s" % [str(intel.get("threat", "")), str(intel.get("lootHint", ""))] if intel.has("threat") else ("УЖЕ ПОСЕЩЁН" if visited else "РАЗВЕДДАННЫХ НЕТ")
				if bool(intel.get("preview", false)):
					secondary = "ПРЕДВАРИТЕЛЬНЫЙ СКАН · %s" % str(intel.get("anomalyProtocol", ""))
				elif bool(intel.get("scouted", false)) and not visited:
					secondary = "РАЗВЕДАНО СОБЫТИЕМ"
				var button: Button = _button("%s\n%s" % [node_type, secondary], reachable)
				button.custom_minimum_size = Vector2(145, 58)
				button.disabled = not reachable
				if visited:
					button.text = "✓  " + button.text
				if reachable:
					button.pressed.connect(_on_travel.bind(node_id))
				row.add_child(button)
	var back: Button = _button("В ГАРАЖ", false)
	back.pressed.connect(_show_garage)
	_body.add_child(back)
	_footer.text = "ПЕРЕХОДЫ РАСХОДУЮТ ТОПЛИВО И 25 СЕКУНД ИГРОВОГО ВРЕМЕНИ"

func _show_current_node(run: GameSaveState.RunState) -> void:
	var node: Dictionary = _session.current_node()
	_body.add_child(_label("УЗЕЛ · %s" % str(node.get("type", "UNKNOWN")), 20, COLOR_TEXT))
	_body.add_child(_label("Угроза: %s     ·     %s" % [str(node.get("threat", "?")), str(node.get("lootHint", ""))], 13, COLOR_MUTED))
	var node_type: String = str(node.get("type", ""))
	if ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"].has(node_type):
		if node_type == "ANOMALY":
			_body.add_child(_label("НУЛЕВАЯ ЗОНА · ПРОТОКОЛ %s" % str(node.get("anomalyProtocol", "UNKNOWN")), 13, COLOR_AMBER))
			_body.add_child(_label("Элитная охрана связана с аномальным модификатором. Победа открывает узел для дальнейшего маршрута.", 12, COLOR_MUTED))
		if run.cleared_node_ids.has(str(node.get("id", ""))) and node_type == "ANOMALY":
			_body.add_child(_label("ОХРАНА УСТРАНЕНА · НАГРАДА ДОБАВЛЕНА В ГРУЗ", 13, COLOR_CYAN))
			var leave_anomaly: Button = _button("ПОКИНУТЬ АНОМАЛЬНЫЙ УЗЕЛ", true)
			leave_anomaly.pressed.connect(_on_service_action.bind("LEAVE_NODE", ""))
			_body.add_child(leave_anomaly)
		elif _session.has_active_combat():
			var resume: Button = _button("ПРОДОЛЖИТЬ СОХРАНЁННЫЙ БОЙ", true)
			resume.pressed.connect(_show_battle)
			_body.add_child(resume)
		else:
			var begin: Button = _button("НАЧАТЬ АВТОБОЙ", true)
			begin.pressed.connect(_on_begin_combat)
			_body.add_child(begin)
	elif str(node.get("type", "")) == "FUEL":
		var buy: Button = _button("КУПИТЬ 1 ТОПЛИВО · КРЕДИТЫ", true)
		buy.pressed.connect(_on_service_action.bind("BUY_FUEL"))
		_body.add_child(buy)
		var scrap: Button = _button("АВАРИЙНАЯ ЗАПРАВКА · 5 SCRAP", false)
		scrap.pressed.connect(_on_service_action.bind("SCRAP_FUEL"))
		_body.add_child(scrap)
	elif str(node.get("type", "")) == "REPAIR":
		var hull: Button = _button("ВОССТАНОВИТЬ 30 КОРПУСА", true)
		hull.pressed.connect(_on_service_action.bind("REPAIR_HULL"))
		_body.add_child(hull)
		var hp: Button = _button("ЛЕЧЕНИЕ ОПЕРАТОРА · 30% УТРАЧЕННОГО HP", false)
		hp.pressed.connect(_on_service_action.bind("REPAIR_HP"))
		_body.add_child(hp)
	elif str(node.get("type", "")) == "CACHE":
		var choices: Array = node.get("prototypeChoices", [])
		if choices.is_empty():
			var open: Button = _button("ОТКРЫТЬ ТАЙНИК", true)
			open.pressed.connect(_on_service_action.bind("OPEN_CACHE", ""))
			_body.add_child(open)
		else:
			_body.add_child(_label("Выберите один постоянный прототип. Он станет вашим после успешной эвакуации.", 12, COLOR_AMBER))
			for prototype: Variant in choices:
				var choice: Button = _button("ЗАБРАТЬ · %s" % str(prototype), true)
				choice.pressed.connect(_on_service_action.bind("OPEN_CACHE", str(prototype)))
				_body.add_child(choice)
	elif str(node.get("type", "")) == "SHOP":
		_body.add_child(_label("Ассортимент этого магазина закреплён за узлом и не меняется при перезагрузке.", 12, COLOR_MUTED))
		var offers: Array[Dictionary] = _session.shop_offers()
		for index: int in range(offers.size()):
			var offer: Dictionary = offers[index]
			var item: Dictionary = offer.get("item", {})
			var template: Dictionary = ItemCatalog.new().get_template(str(item.get("templateId", "")))
			var buy: Button = _button("%s · %s · %d ¤" % [str(template.get("name", item.get("templateId", "ПРЕДМЕТ"))), str(item.get("rarity", "COMMON")), int(offer.get("price", 0))], true)
			buy.disabled = bool(offer.get("purchased", false))
			buy.pressed.connect(_on_buy_shop_item.bind(index))
			_body.add_child(buy)
	elif str(node.get("type", "")) == "EVENT":
		var event: Dictionary = _session.current_event()
		if event.is_empty():
			_body.add_child(_label("Событие отсутствует в каталоге; выезд остановлен безопасно.", 14, COLOR_RED))
		else:
			_body.add_child(_label(str(event.get("name", "СОБЫТИЕ")), 22, COLOR_TEXT))
			_body.add_child(_label(str(event.get("text", "")), 14, COLOR_MUTED))
			for choice: Dictionary in event.get("choices", []):
				var choose: Button = _button("%s · %s" % [str(choice.get("id", "")), str(choice.get("label", "Выбрать"))], str(choice.get("id", "")) == "A")
				choose.custom_minimum_size.x = 370
				choose.pressed.connect(_on_event_choice.bind(str(choice.get("id", ""))))
				_body.add_child(choose)
				var description: Label = _label(str(choice.get("desc", "")), 11, COLOR_MUTED)
				_body.add_child(description)
	else:
		_body.add_child(_label("Этот дорожный узел ещё не получил игровое действие.", 13, COLOR_AMBER))
	for opportunity: Dictionary in _session.available_quest_stages():
		var quest: Dictionary = opportunity["quest"]
		var stage: Dictionary = opportunity["stage"]
		_body.add_child(_label("ЗАДАНИЕ · %s · ЭТАП %d: %s" % [str(quest.get("name", "")), int(stage.get("stage", 1)), str(stage.get("name", ""))], 16, COLOR_CYAN))
		_body.add_child(_label(str(stage.get("text", "")), 12, COLOR_MUTED))
		for choice: Dictionary in stage.get("choices", []):
			var quest_choice: Button = _button("%s · %s" % [str(choice.get("id", "")), str(choice.get("label", "Решить"))], false)
			quest_choice.custom_minimum_size.x = 370
			quest_choice.pressed.connect(_on_resolve_quest_choice.bind(str(quest.get("id", "")), str(choice.get("id", ""))))
			_body.add_child(quest_choice)
			_body.add_child(_label(str(choice.get("desc", "")), 11, COLOR_MUTED))
	if not ["COMBAT", "ELITE", "BOUNTY", "BOSS", "ANOMALY"].has(node_type):
		var leave: Button = _button("ПОКИНУТЬ УЗЕЛ", false)
		leave.pressed.connect(_on_service_action.bind("LEAVE_NODE", ""))
		_body.add_child(leave)

func _show_checkpoint(_run: GameSaveState.RunState) -> void:
	var completed: bool = _session.state.meta.campaign_flags.has("CAMPAIGN_COMPLETED")
	_body.add_child(_label("КАМПАНИЯ ПРОЙДЕНА" if completed else "КОНТРОЛЬНЫЙ УЗЕЛ", 20, COLOR_CYAN if completed else COLOR_TEXT))
	if completed and not _session.state.meta.campaign_flags.has("ENDING_SELECTED"):
		_body.add_child(_label("Коридор свободных поселений останется нейтральным — или выбранная фракция получит контроль, не закрывая доступ к другим.", 14, COLOR_MUTED))
		var free_ending: Button = _button("СОЗДАТЬ СВОБОДНЫЙ КОРИДОР", true)
		free_ending.pressed.connect(_on_campaign_ending.bind("FREE_CORRIDOR", ""))
		_body.add_child(free_ending)
		for faction_id: String in ["F_VANTA", "F_RUST", "F_CHOIR", "F_ECHO"]:
			var faction_ending: Button = _button("ПЕРЕДАТЬ КОНТРОЛЬ · %s" % faction_id, false)
			faction_ending.pressed.connect(_on_campaign_ending.bind("FACTION_CONTROL", faction_id))
			_body.add_child(faction_ending)
		return
	_body.add_child(_label("Сектор 12 открыт для бесконечной глубины." if completed else "Выберите: закрепить добычу и выйти или продолжить в следующий сектор с текущими ресурсами и незакреплённым грузом.", 14, COLOR_MUTED))
	_add_escalation_selector()
	var continue_button: Button = _button("ВОЙТИ В ЭНДГЕЙМ · СЕКТОР %02d" % (_run.depth + 1) if completed else "ПРОДОЛЖИТЬ КАМПАНИЮ · СЕКТОР %02d" % (_run.depth + 1), false)
	continue_button.pressed.connect(_on_continue_campaign)
	_body.add_child(continue_button)
	var exit_button: Button = _button("ЭВАКУИРОВАТЬСЯ С ГРУЗОМ", true)
	exit_button.pressed.connect(_on_exit_run)
	_body.add_child(exit_button)

func _add_escalation_selector() -> void:
	if _session.state == null or not _session.state.meta.campaign_flags.has("ENDGAME_UNLOCKED"):
		return
	var next_depth: int = _session.state.run.depth + 1 if _session.state.run != null and _session.state.run.phase == "CHECKPOINT" else _session.state.meta.unlocked_forpost + 1
	if next_depth < 13:
		return
	_body.add_child(_label("ДОГОВОРЫ ЭСКАЛАЦИИ · ВЫБЕРИТЕ ДО ТРЁХ", 12, COLOR_AMBER))
	var options: Array[Dictionary] = [
		{"id": "WANTED_PLUS", "desc": "+5 розыска за элиту, +15% кредитов"},
		{"id": "HUNT_FAST", "desc": "Телеграфы тяжёлых приёмов быстрее, минимум 0,6 с"},
		{"id": "REPAIR_RARE", "desc": "Меньше ремонтных узлов, +10% лома"},
		{"id": "SCAN_DARK", "desc": "−1 уровень разведки, +10% данных"},
		{"id": "DRONE_WAR", "desc": "Элиты могут глушить дронов, +15% количества добычи"},
		{"id": "HEAT_FOG", "desc": "Охлаждение боя −2/с, +10% шанс ENERGY-предметов"},
		{"id": "SHIELD_BREAK", "desc": "+10 пробивания брони элит, +10% шанса RARE"},
		{"id": "LONG_RUN", "desc": "+15 с переходы, +25% количества добычи босса"},
	]
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	_body.add_child(row)
	for option: Dictionary in options:
		var escalation_id: String = str(option["id"])
		var toggle: CheckButton = CheckButton.new()
		toggle.text = escalation_id
		toggle.tooltip_text = str(option["desc"])
		toggle.button_pressed = _selected_escalations.has(escalation_id)
		toggle.toggled.connect(_on_escalation_toggled.bind(escalation_id, toggle))
		row.add_child(toggle)

func _on_escalation_toggled(enabled: bool, escalation_id: String, toggle: CheckButton) -> void:
	if enabled:
		if _selected_escalations.size() >= 3:
			toggle.set_pressed_no_signal(false)
			_footer.text = "Допускается выбрать не более трёх договоров эскалации."
			return
		if not _selected_escalations.has(escalation_id): _selected_escalations.append(escalation_id)
	else:
		_selected_escalations.erase(escalation_id)

func _show_settings() -> void:
	_screen = "settings"
	_clear_body()
	_body.add_child(_label("НАСТРОЙКИ   /   ЛОКАЛЬНЫЙ ПРОФИЛЬ", 12, COLOR_CYAN))
	_body.add_child(_label("Параметры доступности", 26, COLOR_TEXT))
	var mute: CheckButton = CheckButton.new()
	mute.text = "Отключить звук"
	mute.button_pressed = _muted
	mute.toggled.connect(func(value: bool) -> void:
		_muted = value
		_settings.set_value("audio", "muted", value)
		_settings.save("user://settings.cfg"))
	_body.add_child(mute)
	var motion: CheckButton = CheckButton.new()
	motion.text = "Уменьшенное движение"
	motion.button_pressed = _reduced_motion
	motion.toggled.connect(func(value: bool) -> void:
		_reduced_motion = value
		_settings.set_value("accessibility", "reduced_motion", value)
		_settings.save("user://settings.cfg"))
	_body.add_child(motion)
	_body.add_child(_label("Настройки сохраняются отдельно от игрового слота. Звук пока не интегрирован; отключение действует заранее для следующих аудиосистем.", 12, COLOR_MUTED))
	var back: Button = _button("В ГАРАЖ", false)
	back.pressed.connect(_navigate.bind("garage"))
	_body.add_child(back)

func _show_battle() -> void:
	_screen = "battle"
	_clear_body()
	var combat: CombatState = _session.combat_state()
	if combat == null:
		_show_road()
		return
	_body.add_child(_label("АВТОБОЙ   /   СИМУЛЯЦИЯ 100 МС", 12, COLOR_CYAN))
	if not _session.combat_notice.is_empty():
		var notice: Label = _label(_session.combat_notice, 12, COLOR_AMBER)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(notice)
	_body.add_child(_label("Оператор vs %s" % ", ".join(_enemy_names(combat.enemies)), 24, COLOR_TEXT))
	var operator_bar: ProgressBar = _bar(combat.operator.hp / maxf(1.0, float(combat.operator.base_sheet.get("maxHP", 1.0))), Color("4cc99b"))
	_body.add_child(_label("ОПЕРАТОР · HP %d / %d · ЩИТ %d · ЭНЕРГИЯ %d · НАГРЕВ %d" % [int(combat.operator.hp), int(combat.operator.base_sheet.get("maxHP", 0)), int(combat.operator.shield), int(combat.operator.energy), int(combat.operator.heat)], 12, COLOR_TEXT))
	_body.add_child(operator_bar)
	for enemy: CombatActorState in combat.enemies:
		_body.add_child(_label("%s · HP %d / %d" % [enemy.display_name, int(enemy.hp), int(enemy.base_sheet.get("maxHP", 0))], 13, COLOR_RED))
		_body.add_child(_bar(enemy.hp / maxf(1.0, float(enemy.base_sheet.get("maxHP", 1.0))), COLOR_RED))
	_body.add_child(_label("ВРЕМЯ БОЯ %d:%02d" % [int(combat.time_ms / 60000.0), int(combat.time_ms / 1000.0) % 60], 13, COLOR_AMBER))
	var events: Array[Dictionary] = combat.log.slice(maxi(0, combat.log.size() - 8))
	for event: Dictionary in events:
		_body.add_child(_label("[%d.%d] %s" % [int(float(event.get("timestamp", 0.0)) / 1000.0), int(float(event.get("timestamp", 0.0)) / 100.0) % 10, str(event.get("text", event.get("kind", "")))], 11, COLOR_MUTED))
	if not combat.outcome.is_empty():
		_body.add_child(_label("ИСХОД: %s" % combat.outcome, 18, COLOR_CYAN if combat.outcome == "VICTORY" else COLOR_RED))
		var settle: Button = _button("ЗАФИКСИРОВАТЬ РЕЗУЛЬТАТ", true)
		settle.pressed.connect(_on_resolve_combat)
		_body.add_child(settle)
	else:
		var step: Button = _button("СЛЕДУЮЩИЙ ТИК · 100 МС", true)
		step.pressed.connect(_on_combat_tick)
		_body.add_child(step)
		var skip: Button = _button("ПРОСЧИТАТЬ ДО ИСХОДА", false)
		skip.pressed.connect(_on_combat_skip)
		_body.add_child(skip)
	var status: Label = _label(_session.last_error, 12, COLOR_RED)
	if not _session.last_error.is_empty():
		_body.add_child(status)
	_footer.text = "ОДИН ДЕТЕРМИНИРОВАННЫЙ COMBATSIMULATOR · %d МС" % combat.time_ms

func _trace_text(node_value: Variant, depth: int) -> String:
	if not node_value is Dictionary:
		return ""
	var node: Dictionary = node_value
	var indent: String = "  ".repeat(depth)
	var line: String = "%s%s · %s = %s" % [indent, str(node.get("operation", "")), str(node.get("stage", "")), _fmt(node.get("exactValue", 0.0))]
	var source: String = str(node.get("sourceName", ""))
	var explanation: String = str(node.get("localizedExplanation", ""))
	if not source.is_empty():
		line += "  ← " + source
	if not explanation.is_empty():
		line += "  ·  " + explanation
	line += "\n"
	for child: Variant in node.get("children", []):
		line += _trace_text(child, depth + 1)
	return line

func _navigate(destination: String) -> void:
	match destination:
		"garage": _show_garage()
		"road": _show_road()
		"build": _show_build()
		"inventory": _show_inventory()
		"settings": _show_settings()

func _on_new_game() -> void:
	_selected_escalations.clear()
	if _session.start_new_game():
		_show_garage()
	else:
		_footer.text = _session.last_error

func _on_continue() -> void:
	if _session.state != null and _session.state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase):
		_show_road()
	else:
		_show_garage()

func _on_start_expedition(contract_id: String = "") -> void:
	if _session.start_expedition("", _medical_restore_next_run, contract_id, _selected_escalations):
		_medical_restore_next_run = false
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_travel(node_id: String) -> void:
	if _session.travel_to(node_id):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_begin_combat() -> void:
	if _session.begin_combat():
		_show_battle()
	else:
		_footer.text = _session.last_error

func _on_combat_tick() -> void:
	if _session.advance_combat_step():
		_show_battle()
	else:
		_footer.text = _session.last_error

func _on_combat_skip() -> void:
	var steps: int = 0
	while steps < 1800 and _session.combat_state() != null and _session.combat_state().outcome.is_empty():
		if not _session.advance_combat_step():
			_footer.text = _session.last_error
			break
		steps += 1
	_show_battle()

func _on_resolve_combat() -> void:
	if _session.resolve_active_combat():
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_exit_run() -> void:
	if _session.extract_run():
		_show_garage()
	else:
		_footer.text = _session.last_error

func _on_service_action(action: String, prototype_id: String = "") -> void:
	if _session.resolve_service_node(action, prototype_id):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_buy_shop_item(index: int) -> void:
	if _session.buy_shop_item(index):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_event_choice(choice_id: String) -> void:
	if _session.resolve_event(choice_id):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_continue_campaign() -> void:
	if _session.continue_campaign(_selected_escalations):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_campaign_ending(ending_id: String, faction_id: String) -> void:
	if _session.resolve_campaign_ending(ending_id, faction_id):
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_autopilot() -> void:
	var report: Dictionary = _session.simulate_autopilot()
	if not bool(report.get("ok", false)):
		_footer.text = str(report.get("error", "Автопилот остановлен."))
	_show_road()

func _on_toggle_offline_autopilot(enabled: bool) -> void:
	if _session.set_autopilot_enabled(enabled):
		_footer.text = "ОФЛАЙН-АВТОПИЛОТ ВКЛЮЧЁН · ПРОФИЛЬ СОХРАНЁН" if enabled else "ОФЛАЙН-АВТОПИЛОТ ВЫКЛЮЧЁН"
	else:
		_footer.text = _session.last_error
	_show_road()

func _on_save() -> void:
	if _session.save():
		_footer.text = "СОХРАНЕНО · РЕВИЗИЯ %d" % _session.state.revision
	else:
		_footer.text = _session.last_error

func _on_allocate_attribute(attribute_id: String) -> void:
	var allocated: bool = _session.allocate_attribute(attribute_id)
	_show_garage()
	_footer.text = "АТРИБУТ РАСПРЕДЕЛЁН · BUILD RESOLVER ПЕРЕСЧИТАН" if allocated else _session.last_error

func _on_respec_attributes() -> void:
	var reset: bool = _session.respec_attributes()
	_show_garage()
	_footer.text = "АТРИБУТЫ СБРОШЕНЫ · ОЧКИ ВОЗВРАЩЕНЫ" if reset else _session.last_error

func _on_upgrade_garage_object(object_id: String) -> void:
	var upgraded: bool = _session.upgrade_garage_object(object_id)
	_show_garage()
	_footer.text = "%s УЛУЧШЕН · L%d" % [object_id, _session.garage_level(object_id)] if upgraded else _session.last_error

func _on_set_skill_equipped(skill_id: String, equipped: bool) -> void:
	var changed: bool = _session.set_skill_equipped(skill_id, equipped)
	_show_build()
	_footer.text = "АКТИВНЫЕ УМЕНИЯ ОБНОВЛЕНЫ · %d / 3" % _session.state.meta.skill_ids.size() if changed else _session.last_error

func _on_set_passive_equipped(passive_id: String, equipped: bool) -> void:
	var changed: bool = _session.set_passive_equipped(passive_id, equipped)
	_show_build()
	_footer.text = "ПАССИВНЫЕ ПРОТОКОЛЫ ОБНОВЛЕНЫ · %d / 3" % _session.state.meta.passive_ids.size() if changed else _session.last_error

func _on_set_tree_node(node_id: String, allocated: bool) -> void:
	var changed: bool = _session.set_tree_node_allocated(node_id, allocated)
	_show_build()
	_footer.text = "УЗЕЛ %s · СВОБОДНО %d" % [node_id, _session.tree_points_available()] if changed else _session.last_error

func _on_equip_item(slot: String, item_id: String) -> void:
	if _session.equip_item(slot, item_id):
		_show_inventory()
	else:
		_footer.text = _session.last_error

func _on_unequip_item(slot: String) -> void:
	if _session.unequip_item(slot):
		_show_inventory()
	else:
		_footer.text = _session.last_error

func _on_repair_item(item_id: String) -> void:
	var repaired: bool = _session.repair_item(item_id)
	_show_inventory()
	_footer.text = "ПРЕДМЕТ ОТРЕМОНТИРОВАН" if repaired else _session.last_error

func _confirm_item_disposal(item_id: String, method: String, credits: int, scrap: int, data: int) -> void:
	var title: String = "ПРОДАЖА ПРЕДМЕТА" if method == "SELL" else "РАЗБОР ПРЕДМЕТА"
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = "Предмет %s будет удалён из постоянного склада. Вы получите: %d CREDITS · %d SCRAP · %d DATA." % [item_id, credits, scrap, data]
	dialog.ok_button_text = "ПОДТВЕРДИТЬ"
	dialog.cancel_button_text = "ОТМЕНА"
	dialog.confirmed.connect(_on_confirm_item_disposal.bind(item_id, method))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _on_confirm_item_disposal(item_id: String, method: String) -> void:
	var disposed: bool = _session.sell_item(item_id) if method == "SELL" else _session.dismantle_item(item_id)
	_show_inventory()
	_footer.text = "ПРЕДМЕТ %s · ПРОФИЛЬ СОХРАНЁН" % ("ПРОДАН" if method == "SELL" else "РАЗОБРАН") if disposed else _session.last_error

func _on_undo_last_dismantle() -> void:
	var restored: bool = _session.undo_last_dismantle()
	_show_inventory()
	_footer.text = "РАЗБОР ОТМЕНЁН · ПРЕДМЕТ ВОССТАНОВЛЕН" if restored else _session.last_error

func _refresh_base_craft_button(_index: int, template_id: String, tech_picker: OptionButton, craft_button: Button, can_edit: bool) -> void:
	var tech_level: int = tech_picker.get_selected_id()
	var quote: Dictionary = _session.base_item_craft_quote(template_id, tech_level)
	craft_button.text = "ИЗГОТОВИТЬ · %d SCR / %d DATA" % [int(quote.get("scrap", 0)), int(quote.get("data", 0))]
	craft_button.disabled = not can_edit or not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false))
	craft_button.tooltip_text = str(quote.get("error", "COMMON · требуется постоянный чертёж"))

func _on_craft_base_item(template_id: String, tech_picker: OptionButton) -> void:
	var tech_level: int = tech_picker.get_selected_id()
	var crafted: bool = _session.craft_base_item(template_id, tech_level)
	_show_inventory()
	_footer.text = "ИЗГОТОВЛЕНО · %s T%d" % [template_id, tech_level] if crafted else _session.last_error

func _on_calibrate_item_affix(item_id: String, affix_index: int) -> void:
	var calibrated: bool = _session.calibrate_item_affix(item_id, affix_index)
	_show_inventory()
	_footer.text = "АФФИКС ПЕРЕКАЛИБРОВАН · BUILD LAB ПЕРЕСЧИТАН" if calibrated else _session.last_error

func _show_affix_picker(item_id: String, affix_index: int) -> void:
	var quote: Dictionary = _session.affix_replacement_options(item_id, affix_index)
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		_footer.text = str(quote.get("error", "Операция недоступна."))
		_show_inventory()
		return
	_screen = "affix_picker"
	_clear_body()
	var adding: bool = affix_index < 0
	_body.add_child(_label("МАСТЕРСКАЯ   /   %s" % ("НОВЫЙ АФФИКС" if adding else "ЗАМЕНА АФФИКСА"), 12, COLOR_CYAN))
	_body.add_child(_label("Выберите совместимый эффект", 25, COLOR_TEXT))
	_body.add_child(_label("При подтверждении: %d TR · %d SCRAP · %d DATA. Все списания и предмет сохранятся одной транзакцией." % [int(quote.get("tr", 0)), int(quote.get("scrap", 0)), int(quote.get("data", 0))], 12, COLOR_MUTED))
	var catalog: ItemCatalog = ItemCatalog.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		_body.add_child(_label(str(catalog_result.get("error", "Каталог аффиксов недоступен.")), 13, COLOR_RED))
	else:
		for option: Dictionary in quote.get("options", []):
			var definition: Dictionary = catalog.get_affix(str(option.get("id", "")))
			var button: Button = _button("%s  ·  %s" % [str(option.get("id", "")), str(option.get("name", "Аффикс"))], false)
			button.tooltip_text = "%s · %s · tiers: %s" % [str(definition.get("stat", "")), str(definition.get("unit", "")), str(definition.get("tiers", []))]
			button.pressed.connect(_on_choose_affix.bind(item_id, affix_index, str(option.get("id", ""))))
			_body.add_child(button)
	var cancel: Button = _button("ОТМЕНА", true)
	cancel.pressed.connect(_show_inventory)
	_body.add_child(cancel)

func _on_choose_affix(item_id: String, affix_index: int, affix_id: String) -> void:
	var applied: bool = _session.add_item_affix(item_id, affix_id) if affix_index < 0 else _session.replace_item_affix(item_id, affix_index, affix_id)
	_show_inventory()
	_footer.text = "АФФИКС УСТАНОВЛЕН · BUILD LAB ПЕРЕСЧИТАН" if applied else _session.last_error

func _on_calibrate_item_tech(item_id: String, target_level: int) -> void:
	var calibrated: bool = _session.calibrate_item_tech_level(item_id, target_level)
	_show_inventory()
	_footer.text = "TECHLEVEL T%d · BUILD LAB ПЕРЕСЧИТАН" % target_level if calibrated else _session.last_error

func _on_upgrade_item_affix_tier(item_id: String, affix_index: int) -> void:
	var upgraded: bool = _session.upgrade_item_affix_tier(item_id, affix_index)
	_show_inventory()
	_footer.text = "TIER АФФИКСА ПОВЫШЕН · BUILD LAB ПЕРЕСЧИТАН" if upgraded else _session.last_error

func _contains_node(nodes: Array[Dictionary], node_id: String) -> bool:
	for node: Dictionary in nodes:
		if str(node.get("id", "")) == node_id:
			return true
	return false

func _item_by_id(item_id: String) -> Dictionary:
	if _session.state == null:
		return {}
	for item: Dictionary in _session.state.meta.inventory:
		if str(item.get("itemId", "")) == item_id:
			return item
	return {}

func _enemy_names(enemies: Array[CombatActorState]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for enemy: CombatActorState in enemies:
		result.append(enemy.display_name)
	return result

func _bar(fraction: float, color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 13
	bar.add_theme_stylebox_override("background", _panel_style(COLOR_VOID, COLOR_VOID))
	bar.add_theme_stylebox_override("fill", _panel_style(color, color))
	return bar

func _clear_body() -> void:
	if _body == null:
		return
	for child: Node in _body.get_children():
		child.queue_free()

func _label(text: String, size: int = 14, color: Color = COLOR_TEXT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 38)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_VOID if primary else COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_VOID if primary else COLOR_CYAN)
	button.add_theme_stylebox_override("normal", _panel_style(COLOR_CYAN if primary else COLOR_STEEL, COLOR_CYAN if primary else Color("344357")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("7de7df") if primary else Color("2b3947"), COLOR_CYAN))
	button.add_theme_stylebox_override("pressed", _panel_style(COLOR_BLUE if primary else COLOR_COAL, COLOR_BLUE))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("20262c"), Color("34393e")))
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	return button

func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_top = 7
	style.content_margin_right = 12
	style.content_margin_bottom = 7
	return style

func _fmt(value: Variant) -> String:
	return "%.2f" % float(value)
