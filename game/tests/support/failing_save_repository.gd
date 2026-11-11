extends "res://scripts/core/persistence/save_repository.gd"

func _promote_temp(slot_id: String) -> bool:
	var main_path: String = snapshot_path(slot_id, 0)
	var swap_path: String = snapshot_path(slot_id, -2)
	if FileAccess.file_exists(main_path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(main_path), ProjectSettings.globalize_path(swap_path))
	return false
