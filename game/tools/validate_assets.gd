extends SceneTree

const MANIFEST_RELATIVE_PATH: String = "docs/godot/ASSET_MANIFEST.csv"
const VALID_STATUSES: Array[String] = ["PLANNED", "CONCEPT", "INTEGRATED"]
const REQUIRED_COLUMNS: Array[String] = [
	"asset_id",
	"runtime_path",
	"status",
	"source_or_provenance",
	"license",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repository_dir: String = project_dir.get_base_dir()
	var manifest_path: String = repository_dir.path_join(MANIFEST_RELATIVE_PATH)
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		_fail("Asset manifest is missing or unreadable: %s" % manifest_path)
		return

	var headers: PackedStringArray = file.get_csv_line(",")
	var indexes: Dictionary = {}
	for index: int in range(headers.size()):
		indexes[headers[index].strip_edges()] = index
	for column: String in REQUIRED_COLUMNS:
		if not indexes.has(column):
			file.close()
			_fail("Asset manifest is missing required column '%s'." % column)
			return

	var seen_ids: Dictionary = {}
	var planned_count: int = 0
	var integrated_count: int = 0
	var row_number: int = 1
	var failures: Array[String] = []
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line(",")
		row_number += 1
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue
		if row.size() != headers.size():
			failures.append("row %d has %d columns; expected %d" % [row_number, row.size(), headers.size()])
			continue

		var asset_id: String = row[int(indexes["asset_id"])].strip_edges()
		var status: String = row[int(indexes["status"])].strip_edges()
		var runtime_path: String = row[int(indexes["runtime_path"])].strip_edges()
		if asset_id.is_empty() or not asset_id.is_valid_identifier():
			failures.append("row %d has an invalid asset_id '%s'" % [row_number, asset_id])
		elif seen_ids.has(asset_id):
			failures.append("row %d duplicates asset_id '%s'" % [row_number, asset_id])
		else:
			seen_ids[asset_id] = true
		if not VALID_STATUSES.has(status):
			failures.append("row %d has unknown status '%s'" % [row_number, status])
			continue

		if status == "INTEGRATED":
			integrated_count += 1
			var provenance: String = row[int(indexes["source_or_provenance"])].strip_edges()
			var license: String = row[int(indexes["license"])].strip_edges()
			if provenance.is_empty() or provenance.to_lower() in ["not created", "unknown", "tbd"]:
				failures.append("integrated asset '%s' has no recorded provenance" % asset_id)
			if license.is_empty() or license.to_lower() in ["unknown", "tbd", "original required"]:
				failures.append("integrated asset '%s' has no verified license/provenance note" % asset_id)
			if not runtime_path.begins_with("game/") or runtime_path.contains(".."):
				failures.append("integrated asset '%s' has an invalid repository path" % asset_id)
			else:
				var asset_path: String = repository_dir.path_join(runtime_path.trim_prefix("game/"))
				if not FileAccess.file_exists(asset_path) and not DirAccess.dir_exists_absolute(asset_path):
					failures.append("integrated asset '%s' is missing: %s" % [asset_id, asset_path])
		else:
			planned_count += 1

	file.close()
	if not failures.is_empty():
		for failure: String in failures:
			push_error("Asset manifest: %s" % failure)
		quit(1)
		return
	print("Asset manifest valid: %d entries (%d planned/concept, %d integrated)." % [seen_ids.size(), planned_count, integrated_count])
	quit(0)

func _fail(message: String) -> void:
	push_error("Asset manifest validation failed: %s" % message)
	quit(1)
