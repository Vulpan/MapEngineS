extends Control
class_name MainUI

@onready var base_data_panel: BaseDataPanel = $RightMenu/RightMenuBox/BaseDataPanel
@onready var bottom_right_menu: BottomRightMenu = $BottomRightMenu

func _ready() -> void:
	_hide_panels()
	var map = get_tree().get_first_node_in_group("Map") as Map
	if map.map_data != null:
		bottom_right_menu.show()
	else:
		bottom_right_menu.hide()


func _hide_panels() -> void:
	base_data_panel.hide()


func _on_base_data_button_pressed() -> void:
	if base_data_panel.is_visible():
		base_data_panel.hide()
	else:
		base_data_panel.show()


func _on_map_initialized() -> void:
	bottom_right_menu.show()
