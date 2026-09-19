extends MarginContainer
class_name BottomRightMenu

@onready var player: Player = get_tree().get_first_node_in_group("Player")


@onready var region_editing_button: Button = $VBox/VBoxTop/RegionEditingButton
@onready var current_state_label: Label = $VBox/VBoxBottom/CurrentStateLabel

## Region Editing Buttons
@onready var create_first_level_region_button: Button = $VBox/VBoxTop/RegionEditingButtonsBox/CreateFirstLevelRegionButton


@onready var create_new_region_container: CreateNewRegionContainer = $"../CreateNewRegionContainer"
@onready var region_editing_buttons_box: VBoxContainer = $VBox/VBoxTop/RegionEditingButtonsBox


func _ready() -> void:
	player.state_changed.connect(_on_player_state_change)
	region_editing_buttons_box.hide()


func _process(_delta: float) -> void:
	if player.get_state() == Player.State.REGION_EDITING:
		if player.selected_cell_ids.size() > 0:
			if create_first_level_region_button.is_disabled():
				create_first_level_region_button.set_disabled(false)
		else:
			if not create_first_level_region_button.is_disabled():
				create_first_level_region_button.set_disabled(true)


func _on_player_state_change() -> void:
	var st = player.get_state()
	if st == Player.State.REGION_EDITING:
		current_state_label.set_text(tr('region_editing'))
	elif st == Player.State.STATE_EDITING:
		current_state_label.set_text(tr('state_editing'))
	elif st == Player.State.POLYGONS_EDITING:
		current_state_label.set_text(tr('polygon_editing'))
	else:
		current_state_label.set_text("")


func _on_region_editing_button_pressed() -> void:
	var st = player.get_state()
	if st == Player.State.REGION_EDITING:
		player.set_state(Player.State.IDLE)
		region_editing_buttons_box.hide()
		player.selected_cell_ids.clear()
	else:
		player.set_state(Player.State.REGION_EDITING)
		region_editing_buttons_box.show()


func _on_create_first_level_region_button_pressed() -> void:
	player.set_state(Player.State.PAUSE)
	create_new_region_container.show_container(true, 1)
