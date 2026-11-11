class_name SaveValidator
extends RefCounted

const FORMAT: String = "CYDLE_SAVE_EXPORT_V1"
const SCHEMA_VERSION: int = 1
const BALANCE_VERSION: String = "1.0.0"
const GAME_VERSION: String = "1.0.0"

var _state_hash: StateHash = StateHash.new()

func create_document(payload: Dictionary, save_id: String, revision: int, updated_at: int, balance_version: String = BALANCE_VERSION, game_version: String = GAME_VERSION) -> Dictionary:
	var document: Dictionary = {
		"format": FORMAT,
		"schemaVersion": SCHEMA_VERSION,
		"balanceVersion": balance_version,
		"gameVersion": game_version,
		"saveId": save_id,
		"revision": revision,
		"updatedAt": updated_at,
		"payload": payload.duplicate(true),
	}
	document["checksum"] = checksum(document)
	return document

func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("Сохранение должно быть JSON-объектом.")
	var document: Dictionary = value
	if document.get("format") != FORMAT:
		return _failure("Неизвестный формат файла сохранения.")
	var schema_value: Variant = document.get("schemaVersion")
	if not _is_integer_number(schema_value):
		return _failure("schemaVersion: ожидалось целое число.")
	if int(schema_value) > SCHEMA_VERSION:
		return _failure("Сохранение использует будущую схему %d; поддерживается версия %d. Исходные данные не изменены." % [int(schema_value), SCHEMA_VERSION])
	if int(schema_value) != SCHEMA_VERSION:
		return _failure("Схема сохранения %d не поддерживается." % int(schema_value))
	for field_name: String in ["balanceVersion", "gameVersion", "saveId", "checksum"]:
		if not document.get(field_name) is String or str(document[field_name]).is_empty():
			return _failure("%s: ожидалась непустая строка." % field_name)
	if not _is_integer_number(document.get("revision")) or int(document["revision"]) < 1:
		return _failure("revision: ожидалось целое число не меньше 1.")
	var timestamp: Variant = document.get("updatedAt")
	if (not timestamp is int and not timestamp is float) or float(timestamp) < 0.0 or is_nan(float(timestamp)) or is_inf(float(timestamp)):
		return _failure("updatedAt: ожидалось конечное неотрицательное число.")
	if not document.get("payload") is Dictionary:
		return _failure("payload: ожидался JSON-объект.")
	if not _is_json_value(document["payload"]):
		return _failure("payload: содержит значение, которое нельзя безопасно сохранить в JSON.")
	for field_name: Variant in document.keys():
		if not ["format", "schemaVersion", "balanceVersion", "gameVersion", "saveId", "revision", "updatedAt", "payload", "checksum"].has(field_name):
			return _failure("Неизвестное поле сохранения: %s." % str(field_name))
	if checksum(document) != str(document["checksum"]):
		return _failure("Контрольная сумма не совпадает: файл повреждён.")
	return {"ok": true, "save": document.duplicate(true), "error": ""}

func checksum(document: Dictionary) -> String:
	var payload: Dictionary = document.duplicate(true)
	payload.erase("checksum")
	return _state_hash.state_hash(payload)

func parse_text(text: String) -> Dictionary:
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		return _failure("Файл не содержит корректный JSON: %s" % parser.get_error_message())
	return validate(parser.data)

func _failure(message: String) -> Dictionary:
	return {"ok": false, "save": {}, "error": message}

func _is_integer_number(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number)

func _is_json_value(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(float(value))
	if value is Array:
		for entry: Variant in value:
			if not _is_json_value(entry):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value.keys():
			if not key is String or not _is_json_value(value[key]):
				return false
		return true
	return false
