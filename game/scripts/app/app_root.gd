extends Control

@onready var _quit_button: Button = $SafeMargin/Content/QuitButton

func _ready() -> void:
	_quit_button.grab_focus()

func _on_quit_button_pressed() -> void:
	get_tree().quit()
