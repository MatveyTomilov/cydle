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
	var start_button: Button = _button("НАЧАТЬ ВЫЕЗД", true)
	start_button.pressed.connect(_on_start_expedition)
	actions.add_child(start_button)
	var build_button: Button = _button("БИЛДИНГ · 85 ХАРАКТЕРИСТИК", false)
	build_button.pressed.connect(_show_build)
	actions.add_child(build_button)
	var inventory_button: Button = _button("СКЛАД · %d ПРЕДМЕТОВ" % meta.inventory.size(), false)
	inventory_button.pressed.connect(_show_inventory)
	actions.add_child(inventory_button)
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
	var back: Button = _button("НАЗАД В ГАРАЖ", false)
	back.pressed.connect(_show_garage)
	_body.add_child(back)
	_footer.text = "CALCTRACE · %d СТАТОВ · ИСТОЧНИКИ, УСЛОВИЯ И ПРОМЕЖУТОЧНЫЕ ЭТАПЫ" % stat_ids.size()

func _show_inventory() -> void:
	_screen = "inventory"
	_clear_body()
	_body.add_child(_label("СКЛАД   /   ПОСТОЯННАЯ СОБСТВЕННОСТЬ", 12, COLOR_CYAN))
	_body.add_child(_label("Инвентарь", 28, COLOR_TEXT))
	if _session.state == null:
		return
	for item_value: Dictionary in _session.state.meta.inventory:
		var template: Dictionary = ItemCatalog.new().get_template(str(item_value.get("templateId", "")))
		var name: String = str(template.get("name", item_value.get("templateId", "Предмет")))
		var row: HBoxContainer = HBoxContainer.new()
		_body.add_child(row)
		row.add_child(_label("%s  ·  T%d  ·  %s  ·  прочность %d%%" % [name, int(item_value.get("techLevel", 1)), str(item_value.get("rarity", "COMMON")), int(item_value.get("durability", 100))], 13, COLOR_TEXT))
		var slot: String = _compatible_slot(str(template.get("category", "")))
		if not slot.is_empty() and bool(item_value.get("secured", false)):
			var equip_button: Button = _button("НАДЕТЬ %s" % slot, false)
			equip_button.pressed.connect(_on_equip_item.bind(slot, str(item_value.get("itemId", ""))))
			row.add_child(equip_button)
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
		var start: Button = _button("НАЧАТЬ ВЫЕЗД", true)
		start.pressed.connect(_on_start_expedition)
		_body.add_child(start)
		return
	var run: GameSaveState.RunState = _session.state.run
	_body.add_child(_label("СЕКТОР %02d   /   %s   /   %s" % [run.depth, run.biome, run.phase], 12, COLOR_CYAN))
	_body.add_child(_label("Маршрут", 27, COLOR_TEXT))
	var resources: Dictionary = run.resources
	_body.add_child(_label("ТОПЛИВО %d/%d   ·   КОРПУС %d/%d   ·   РОЗЫСК %d" % [int(resources.get("fuel", 0)), int(resources.get("maxFuel", 0)), int(resources.get("hull", 0)), int(resources.get("maxHull", 0)), int(run.wanted)], 13, COLOR_AMBER))
	if run.phase == "NODE":
		_show_current_node(run)
	elif run.phase == "CHECKPOINT":
		_show_checkpoint(run)
	else:
		var graph: Dictionary = run.graph
		for layer_index: int in range(graph.get("layers", []).size()):
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_body.add_child(row)
			row.add_child(_label("L%d" % (layer_index + 1), 10, COLOR_MUTED))
			for node: Dictionary in graph["layers"][layer_index]:
				var node_id: String = str(node.get("id", ""))
				var reachable: bool = _contains_node(_session.reachable_nodes(), node_id)
				var visited: bool = run.visited_node_ids.has(node_id)
				var button: Button = _button("%s\n%s" % [str(node.get("type", "?")), str(node.get("lootHint", ""))], reachable)
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
	if ["COMBAT", "ELITE", "BOUNTY", "BOSS"].has(str(node.get("type", ""))):
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
	if not ["COMBAT", "ELITE", "BOUNTY", "BOSS"].has(str(node.get("type", ""))):
		var leave: Button = _button("ПОКИНУТЬ УЗЕЛ", false)
		leave.pressed.connect(_on_service_action.bind("LEAVE_NODE", ""))
		_body.add_child(leave)

func _show_checkpoint(_run: GameSaveState.RunState) -> void:
	var completed: bool = _session.state.meta.campaign_flags.has("CAMPAIGN_COMPLETED")
	_body.add_child(_label("КАМПАНИЯ ПРОЙДЕНА" if completed else "КОНТРОЛЬНЫЙ УЗЕЛ", 20, COLOR_CYAN if completed else COLOR_TEXT))
	_body.add_child(_label("Сектор 12 открыт для бесконечной глубины." if completed else "Выберите: закрепить добычу и выйти или продолжить в следующий сектор с текущими ресурсами и незакреплённым грузом.", 14, COLOR_MUTED))
	var continue_button: Button = _button("ВОЙТИ В ЭНДГЕЙМ · СЕКТОР %02d" % (_run.depth + 1) if completed else "ПРОДОЛЖИТЬ КАМПАНИЮ · СЕКТОР %02d" % (_run.depth + 1), false)
	continue_button.pressed.connect(_on_continue_campaign)
	_body.add_child(continue_button)
	var exit_button: Button = _button("ЭВАКУИРОВАТЬСЯ С ГРУЗОМ", true)
	exit_button.pressed.connect(_on_exit_run)
	_body.add_child(exit_button)

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
	if _session.start_new_game():
		_show_garage()
	else:
		_footer.text = _session.last_error

func _on_continue() -> void:
	if _session.state != null and _session.state.run != null and not ["EXTRACTED", "DEFEATED", "ABANDONED", "TOWED"].has(_session.state.run.phase):
		_show_road()
	else:
		_show_garage()

func _on_start_expedition() -> void:
	if _session.start_expedition():
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
	if _session.continue_campaign():
		_show_road()
	else:
		_footer.text = _session.last_error

func _on_save() -> void:
	if _session.save():
		_footer.text = "СОХРАНЕНО · РЕВИЗИЯ %d" % _session.state.revision
	else:
		_footer.text = _session.last_error

func _on_equip_item(slot: String, item_id: String) -> void:
	if _session.equip_item(slot, item_id):
		_show_inventory()
	else:
		_footer.text = _session.last_error

func _compatible_slot(category: String) -> String:
	match category:
		"MAIN": return "MAIN"
		"OFFHAND": return "OFFHAND"
		"ARMOR": return "ARMOR"
		"IMPLANT": return "IMP_4"
		"DRONE": return "DRONE_1"
	return ""

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
