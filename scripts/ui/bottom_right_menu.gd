extends MarginContainer
class_name BottomRightMenu

@onready var player: Player = get_tree().get_first_node_in_group("Player")

@onready var region_editing_button: Button = $VBox/RegionEditingButton

func _on_region_editing_button_pressed() -> void:
	player.set_state(Player.State.REGION_EDITING)
