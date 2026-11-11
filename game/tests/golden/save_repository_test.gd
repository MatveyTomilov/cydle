extends "res://tests/test_case.gd"

const VALIDATOR_PATH: String = "res://scripts/core/persistence/save_validator.gd"
const REPOSITORY_PATH: String = "res://scripts/core/persistence/save_repository.gd"
const FAILING_REPOSITORY_PATH: String = "res://tests/support/failing_save_repository.gd"

func run(_tree: SceneTree) -> bool:
	var validator_script: Script = load(VALIDATOR_PATH) as Script
	if not check(validator_script != null, "save_repository: validator implementation is missing"):
		return false
	var repository_script: Script = load(REPOSITORY_PATH) as Script
	if not check(repository_script != null, "save_repository: repository implementation is missing"):
		return false
	var failing_repository_script: Script = load(FAILING_REPOSITORY_PATH) as Script
	if not check(failing_repository_script != null, "save_repository: fault-injection repository is missing"):
		return false
	var validator: Object = validator_script.new()
	var repository: Object = repository_script.new()
	var test_directory: String = "user://save_test_%d" % Time.get_ticks_usec()
	repository.call("configure_directory", test_directory)

	var payload: Dictionary = {"profile": {"level": 1, "credits": 120}, "items": ["starter"]}
	var first_result: Dictionary = repository.call("save", "slot_a", payload, 100)
	check(bool(first_result.get("ok", false)), "save_repository: first snapshot was not saved")
	var first: Dictionary = first_result.get("save", {})
	check(int(first.get("revision", 0)) == 1, "save_repository: first revision should be one")
	check(bool(validator.call("validate", first).get("ok", false)), "save_repository: saved snapshot failed validation")

	var second_result: Dictionary = repository.call("save", "slot_a", {"profile": {"level": 2, "credits": 135}, "items": ["starter"]}, 200)
	var third_result: Dictionary = repository.call("save", "slot_a", {"profile": {"level": 3, "credits": 150}, "items": ["starter"]}, 300)
	check(int(second_result.get("save", {}).get("revision", 0)) == 2, "save_repository: second revision is incorrect")
	check(int(third_result.get("save", {}).get("revision", 0)) == 3, "save_repository: third revision is incorrect")
	check(FileAccess.file_exists(repository.call("snapshot_path", "slot_a", 1)), "save_repository: newest valid backup is missing")
	check(FileAccess.file_exists(repository.call("snapshot_path", "slot_a", 2)), "save_repository: second valid backup is missing")

	var main_path: String = repository.call("snapshot_path", "slot_a", 0)
	var main_file: FileAccess = FileAccess.open(main_path, FileAccess.WRITE)
	if main_file != null:
		main_file.store_string("{broken-json")
		main_file.close()
	var recovered: Dictionary = repository.call("load", "slot_a")
	check(bool(recovered.get("ok", false)), "save_repository: a valid backup was not recoverable")
	check(bool(recovered.get("recovered", false)), "save_repository: backup recovery was not reported")
	check(int(recovered.get("save", {}).get("revision", 0)) == 2, "save_repository: recovery did not select the newest valid backup")

	var exported: Dictionary = repository.call("export_text", "slot_a")
	check(bool(exported.get("ok", false)), "save_repository: valid save export failed")
	var export_text: String = str(exported.get("text", ""))
	var imported: Dictionary = repository.call("import_text", "slot_b", export_text, 400)
	check(bool(imported.get("ok", false)), "save_repository: verified export did not import")
	check(imported.get("save", {}).get("payload") == recovered.get("save", {}).get("payload"), "save_repository: imported payload changed")
	var before_invalid_import: Dictionary = repository.call("load", "slot_b")
	var invalid_import: Dictionary = repository.call("import_text", "slot_b", export_text.replace("CYDLE_SAVE_EXPORT_V1", "BAD"), 500)
	check(not bool(invalid_import.get("ok", false)), "save_repository: invalid export was accepted")
	check(repository.call("load", "slot_b").get("save") == before_invalid_import.get("save"), "save_repository: invalid import changed the destination slot")

	var future_document: Dictionary = first.duplicate(true)
	future_document["schemaVersion"] = 99
	future_document["checksum"] = "00000000"
	var future_validation: Dictionary = validator.call("validate", future_document)
	check(not bool(future_validation.get("ok", false)), "save_repository: future schema was accepted")
	var unsafe_payload: Dictionary = validator.call("create_document", {"bad": NAN}, "unsafe", 1, 1)
	check(not bool(validator.call("validate", unsafe_payload).get("ok", false)), "save_repository: non-finite payload was accepted")
	var unsafe_slot: Dictionary = repository.call("save", "../outside", payload, 600)
	check(not bool(unsafe_slot.get("ok", false)), "save_repository: path traversal slot was accepted")
	var interrupted_temp: FileAccess = FileAccess.open(repository.call("snapshot_path", "slot_b", -1), FileAccess.WRITE)
	if interrupted_temp != null:
		interrupted_temp.store_string("partial")
		interrupted_temp.close()
	check(int(repository.call("load", "slot_b").get("save", {}).get("revision", 0)) == 1, "save_repository: interrupted temp file displaced committed data")

	var failure_directory: String = "%s/fault_injection" % test_directory
	var stable_repository: Object = repository_script.new()
	stable_repository.call("configure_directory", failure_directory)
	var stable_save: Dictionary = stable_repository.call("save", "slot", {"value": "committed"}, 700)
	var failing_repository: Object = failing_repository_script.new()
	failing_repository.call("configure_directory", failure_directory)
	var failed_commit: Dictionary = failing_repository.call("save", "slot", {"value": "uncommitted"}, 800)
	check(not bool(failed_commit.get("ok", false)), "save_repository: injected promotion failure was reported as success")
	var recovered_interrupted_commit: Dictionary = stable_repository.call("load", "slot")
	check(bool(recovered_interrupted_commit.get("ok", false)) and bool(recovered_interrupted_commit.get("recovered", false)), "save_repository: interrupted promotion did not report a recoverable snapshot")
	check(recovered_interrupted_commit.get("save", {}).get("payload") == stable_save.get("save", {}).get("payload"), "save_repository: interrupted promotion lost the last committed payload")

	_cleanup_directory(test_directory)
	return failure_count == 0

func _cleanup_directory(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
