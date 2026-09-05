extends Control
class_name MainUI

@onready var base_data_panel: BaseDataPanel = $RightMenu/RightMenuBox/BaseDataPanel

func _ready() -> void:
	_hide_panels()


func _hide_panels() -> void:
	base_data_panel.hide()


func _on_base_data_button_pressed() -> void:
	if base_data_panel.is_visible():
		base_data_panel.hide()
	else:
		base_data_panel.show()
