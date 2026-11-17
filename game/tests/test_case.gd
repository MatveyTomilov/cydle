extends RefCounted

var assertion_count: int = 0
var failure_count: int = 0

func run(_tree: SceneTree) -> bool:
	return false

func check(condition: bool, failure_message: String) -> bool:
	assertion_count += 1
	if not condition:
		failure_count += 1
		push_error(failure_message)
	return condition
