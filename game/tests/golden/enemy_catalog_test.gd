extends "res://tests/test_case.gd"

func run(_tree: SceneTree) -> bool:
	var catalog: EnemyCatalog = EnemyCatalog.new()
	var loaded: Dictionary = catalog.load_catalog()
	if not check(bool(loaded.get("ok", false)), "enemy_catalog: generated catalog failed validation: %s" % str(loaded.get("error", ""))):
		return false
	check(loaded.get("counts", {}) == {"enemies": 24, "bosses": 6, "eliteMods": 6}, "enemy_catalog: source counts changed")
	var artillery: Dictionary = catalog.get_template("E07")
	check(str(artillery.get("name", "")) == "Артиллерист", "enemy_catalog: E07 source data changed")
	check(artillery.get("abilities", []).size() == 1, "enemy_catalog: E07 heavy attack was not exported")
	var boss: Dictionary = catalog.get_template("BOSS_CORE")
	check(bool(boss.get("isBoss", false)) and boss.get("phases", []).size() > 0, "enemy_catalog: final boss phase data is missing")
	check(catalog.elite_mods.has("EL_SPLIT"), "enemy_catalog: elite modifiers are missing")
	return failure_count == 0
