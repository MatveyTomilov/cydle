class_name SaveRepository
extends RefCounted

var _directory: String = "user://saves"
var _validator: SaveValidator = SaveValidator.new()

func configure_directory(directory_path: String) -> void:
	_directory = directory_path.trim_suffix("/")

func snapshot_path(slot_id: String, snapshot_index: int) -> String:
	var suffix: String = ""
	match snapshot_index:
		0:
			suffix = ".json"
		1:
			suffix = ".bak1"
		2:
			suffix = ".bak2"
		-1:
			suffix = ".tmp"
		-2:
			suffix = ".swap_prev"
		_:
			return ""
	return "%s/%s%s" % [_directory, slot_id, suffix]

func save(slot_id: String, payload: Dictionary, updated_at: int, requested_save_id: String = "") -> Dictionary:
	if not _valid_slot_id(slot_id):
		return _failure("Недопустимый идентификатор слота сохранения.")
	var current: Dictionary = self.load(slot_id)
	if not bool(current.get("ok", false)) and not bool(current.get("empty", false)):
		return _failure("Текущий слот повреждён. Экспортируйте исходные файлы или восстановите копию перед записью: %s" % str(current.get("error", "неизвестная ошибка")))
	var revision: int = 1
	var save_id: String = requested_save_id
	if bool(current.get("ok", false)):
		var previous: Dictionary = current["save"]
		revision = int(previous["revision"]) + 1
		if save_id.is_empty():
			save_id = str(previous["saveId"])
	if save_id.is_empty():
		save_id = "save-%d-%d" % [updated_at, Time.get_ticks_usec()]
	var document: Dictionary = _validator.create_document(payload, save_id, revision, maxi(0, updated_at))
	var previous_document: Dictionary = current.get("save", {})
	return _commit(slot_id, document, previous_document)

func save_game(slot_id: String, state: GameSaveState, updated_at: int) -> Dictionary:
	if state == null:
		return _failure("Нельзя сохранить пустое состояние игры.")
	var payload: Dictionary = state.to_payload()
	var validation: Dictionary = GameSaveSchema.new().validate_payload(payload)
	if not bool(validation.get("ok", false)):
		return _failure("Игровое состояние не прошло проверку: %s" % str(validation.get("error", "неизвестная ошибка")))
	return save(slot_id, payload, updated_at, state.save_id)

func load(slot_id: String) -> Dictionary:
	if not _valid_slot_id(slot_id):
		return _failure("Недопустимый идентификатор слота сохранения.")
	var candidates: Array[Dictionary] = []
	var invalid_paths: Array[String] = []
	for index: int in [0, 1, 2, -2]:
		var path: String = snapshot_path(slot_id, index)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Dictionary = _read_snapshot(path)
		if bool(parsed.get("ok", false)):
			parsed["path"] = path
			parsed["index"] = index
			candidates.append(parsed)
		else:
			invalid_paths.append(path)
	if candidates.is_empty():
		if invalid_paths.is_empty():
			return {"ok": false, "empty": true, "recovered": false, "save": {}, "error": ""}
		return _failure("Не найден валидный снимок. Повреждённые файлы сохранены: %s" % ", ".join(invalid_paths))
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_save: Dictionary = left["save"]
		var right_save: Dictionary = right["save"]
		if int(left_save["revision"]) == int(right_save["revision"]):
			return int(left["index"]) < int(right["index"])
		return int(left_save["revision"]) > int(right_save["revision"]))
	var selected: Dictionary = candidates[0]
	var selected_save: Dictionary = selected["save"]
	var recovered: bool = int(selected["index"]) != 0
	var recovery_paths: Array[String] = []
	for candidate: Dictionary in candidates:
		recovery_paths.append(str(candidate["path"]))
	return {"ok": true, "empty": false, "recovered": recovered, "save": selected_save, "error": "", "available_recovery": recovery_paths}

func load_game(slot_id: String) -> Dictionary:
	var loaded: Dictionary = self.load(slot_id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var state_result: Dictionary = GameSaveState.new().parse_payload(loaded["save"]["payload"])
	if not bool(state_result.get("ok", false)):
		return _failure("Снимок найден, но данные игры повреждены; исходный файл сохранён: %s" % str(state_result.get("error", "неизвестная ошибка")))
	return {"ok": true, "empty": false, "recovered": bool(loaded.get("recovered", false)), "state": state_result["state"], "save": loaded["save"], "error": ""}

func list_snapshots(slot_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_slot_id(slot_id):
		return result
	for index: int in [0, 1, 2]:
		var path: String = snapshot_path(slot_id, index)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Dictionary = _read_snapshot(path)
		if not bool(parsed.get("ok", false)):
			continue
		var save: Dictionary = parsed["save"]
		result.append({
			"index": index,
			"path": path,
			"revision": int(save["revision"]),
			"save_id": str(save["saveId"]),
			"updated_at": int(save["updatedAt"]),
		})
	return result

func restore_snapshot(slot_id: String, snapshot_index: int) -> Dictionary:
	if not _valid_slot_id(slot_id):
		return _failure("Недопустимый идентификатор слота сохранения.")
	if not [1, 2].has(snapshot_index):
		return _failure("Восстановить можно только резервную копию (.bak1/.bak2).")
	var source: Dictionary = _read_snapshot(snapshot_path(slot_id, snapshot_index))
	if not bool(source.get("ok", false)):
		return _failure("Резервная копия повреждена: %s" % str(source.get("error", "неизвестная ошибка")))
	var current: Dictionary = self.load(slot_id)
	if not bool(current.get("ok", false)) and not bool(current.get("empty", false)):
		return _failure("Текущий слот повреждён; восстановление не выполнено: %s" % str(current.get("error", "")))
	var document: Dictionary = source["save"]
	var revision: int = int(document["revision"]) + 1
	var save_id: String = str(document["saveId"])
	if bool(current.get("ok", false)):
		revision = maxi(revision, int(current["save"]["revision"]) + 1)
		save_id = str(current["save"]["saveId"])
	var replacement: Dictionary = _validator.create_document(document["payload"], save_id, revision, maxi(0, int(document["updatedAt"])), str(document["balanceVersion"]), str(document["gameVersion"]))
	return _commit(slot_id, replacement, current.get("save", {}))

func export_text(slot_id: String) -> Dictionary:
	var loaded: Dictionary = self.load(slot_id)
	if not bool(loaded.get("ok", false)):
		return _failure("Экспорт недоступен: %s" % str(loaded.get("error", "сохранение не найдено")))
	return {"ok": true, "text": JSON.stringify(loaded["save"], "  ", true, true), "error": ""}

func import_text(slot_id: String, text: String, updated_at: int) -> Dictionary:
	if not _valid_slot_id(slot_id):
		return _failure("Недопустимый идентификатор слота сохранения.")
	var imported: Dictionary = _validator.parse_text(text)
	if not bool(imported.get("ok", false)):
		return imported
	var current: Dictionary = self.load(slot_id)
	if not bool(current.get("ok", false)) and not bool(current.get("empty", false)):
		return _failure("Целевой слот повреждён и не был изменён: %s" % str(current.get("error", "неизвестная ошибка")))
	var source: Dictionary = imported["save"]
	var revision: int = 1
	var save_id: String = str(source["saveId"])
	if bool(current.get("ok", false)):
		var destination: Dictionary = current["save"]
		revision = int(destination["revision"]) + 1
		save_id = str(destination["saveId"])
	var replacement: Dictionary = _validator.create_document(source["payload"], save_id, revision, maxi(0, updated_at), str(source["balanceVersion"]), str(source["gameVersion"]))
	return _commit(slot_id, replacement, current.get("save", {}))

func _commit(slot_id: String, document: Dictionary, previous_document: Dictionary) -> Dictionary:
	var validation: Dictionary = _validator.validate(document)
	if not bool(validation.get("ok", false)):
		return _failure("Сохранение не прошло проверку: %s" % str(validation.get("error", "неизвестная ошибка")))
	if not _ensure_directory():
		return _failure("Не удалось создать каталог сохранений.")
	var temporary_path: String = snapshot_path(slot_id, -1)
	if not _write_json(temporary_path, document):
		return _failure("Не удалось записать временный файл сохранения.")
	var staged: Dictionary = _read_snapshot(temporary_path)
	if not bool(staged.get("ok", false)):
		return _failure("Временный файл сохранения не прошёл проверку: %s" % str(staged.get("error", "неизвестная ошибка")))
	if not _rotate_backups(slot_id, previous_document):
		return _failure("Не удалось подготовить резервные копии; основной сейв не изменён.")
	if not _promote_temp(slot_id):
		return _failure("Не удалось заменить основной сейв; сохранён предыдущий валидный снимок.")
	return {"ok": true, "empty": false, "recovered": false, "save": document, "error": ""}

func _rotate_backups(slot_id: String, previous_document: Dictionary) -> bool:
	var first_backup: Dictionary = _read_snapshot(snapshot_path(slot_id, 1))
	if bool(first_backup.get("ok", false)):
		if not _write_json(snapshot_path(slot_id, 2), first_backup["save"]):
			return false
	if not previous_document.is_empty():
		var checked: Dictionary = _validator.validate(previous_document)
		if bool(checked.get("ok", false)) and not _write_json(snapshot_path(slot_id, 1), checked["save"]):
			return false
	return true

func _promote_temp(slot_id: String) -> bool:
	var main_path: String = snapshot_path(slot_id, 0)
	var temporary_path: String = snapshot_path(slot_id, -1)
	var previous_path: String = snapshot_path(slot_id, -2)
	if FileAccess.file_exists(previous_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	var had_main: bool = FileAccess.file_exists(main_path)
	if had_main and DirAccess.rename_absolute(ProjectSettings.globalize_path(main_path), ProjectSettings.globalize_path(previous_path)) != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(main_path)) != OK:
		if had_main:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(previous_path), ProjectSettings.globalize_path(main_path))
		return false
	if FileAccess.file_exists(previous_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	return true

func _read_snapshot(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "save": {}, "error": "Не удалось прочитать файл."}
	var text: String = file.get_as_text()
	file.close()
	return _validator.parse_text(text)

func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK

func _ensure_directory() -> bool:
	var absolute_directory: String = ProjectSettings.globalize_path(_directory)
	return DirAccess.make_dir_recursive_absolute(absolute_directory) == OK or DirAccess.dir_exists_absolute(absolute_directory)

func _valid_slot_id(slot_id: String) -> bool:
	var expression: RegEx = RegEx.new()
	if expression.compile("^[A-Za-z0-9_-]{1,48}$") != OK:
		return false
	return expression.search(slot_id) != null

func _failure(message: String) -> Dictionary:
	return {"ok": false, "empty": false, "recovered": false, "save": {}, "error": message}
