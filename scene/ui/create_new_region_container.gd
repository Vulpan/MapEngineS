class_name CreateNewRegionContainer
extends CenterContainer


var blocked_adm_level: bool = false
var adm_level: int = 1

@onready var player: Player = get_tree().get_first_node_in_group("Player")
@onready var map: Map = get_tree().get_first_node_in_group("Map")

@onready var name_input_data_box: InputDataBox = $Panel/Margin/VBox/VBoxContainer/NameInputDataBox
@onready var amd_level_input_number_data_box: InputNumberDataBox = $Panel/Margin/VBox/VBoxContainer/AmdLevelInputNumberDataBox
@onready var color_picker_button: ColorPickerButton = $Panel/Margin/VBox/VBoxContainer/ColorBox/ColorPickerButton

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
	
	var color = color_picker_button.get_pick_color()
	
	if color.is_equal_approx(Color.BLACK) or color.is_equal_approx(Color.WHITE):
		return
	
	var reg_name = name_input_data_box.get_content()
	var level = amd_level_input_number_data_box.get_content()
	print(player.selected_cell_ids)
	map.create_region_for_selected_cell(
		player.selected_cell_ids,
		reg_name,
		level,
		-1, #TODO zrobić rodziców
		color.r,
		color.g,
		color.b
	)
	
	
	player.selected_cell_ids.clear() # TODO sprawdzić czy takie czyszczenie wystarczy aby przestały migać regiony
	player.set_state(Player.State.REGION_EDITING)
	hide()
	_clear()
