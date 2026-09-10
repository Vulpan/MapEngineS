class_name CreateNewRegionContainer
extends CenterContainer


var blocked_adm_level: bool = false
var adm_level: int = 1

@onready var player: Player = get_tree().get_first_node_in_group("Player")


@onready var name_input_data_box: InputDataBox = $Panel/Margin/VBox/VBoxContainer/NameInputDataBox
@onready var amd_level_input_number_data_box: InputNumberDataBox = $Panel/Margin/VBox/VBoxContainer/AmdLevelInputNumberDataBox


func _ready() -> void:
	hide()


func show_container(_blocked: bool, _level: int) -> void:
	blocked_adm_level = _blocked
	adm_level = _level
	
	if blocked_adm_level:
		amd_level_input_number_data_box.set_blockade(blocked_adm_level)
		amd_level_input_number_data_box.set_content(adm_level)
	else:
		amd_level_input_number_data_box.set_blockade(blocked_adm_level)
		amd_level_input_number_data_box.set_content(adm_level)
	
	show()


func _clear() -> void:
	blocked_adm_level = false
	adm_level = 1
	name_input_data_box.set_content("")
	amd_level_input_number_data_box.set_blockade(false)
	amd_level_input_number_data_box.set_content(1)


func _on_cancel_button_pressed() -> void:
	player.set_state(Player.State.REGION_EDITING)
	hide()
	_clear()


func _on_confirm_button_pressed() -> void:
	# TODO dodać tworzenie regionu. Pamietoj że komórka moze byc przypisana tylko do jednego regionu
	if name_input_data_box.get_content().is_empty() or amd_level_input_number_data_box.get_content() <= 0:
		return
	
	
	player.selected_cell_ids.clear() # TODO sprawdzić czy takie czyszczenie wystarczy aby przestały igać regiony
	player.set_state(Player.State.REGION_EDITING)
	hide()
	_clear()
