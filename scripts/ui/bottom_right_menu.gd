extends MarginContainer
class_name BottomRightMenu

@onready var player: Player = get_tree().get_first_node_in_group("Player")
@onready var display_mode_manager: DisplayModeManager = get_tree().get_first_node_in_group("DisplayModeManager")

@onready var region_editing_button: Button = $VBox/VBoxTop/RegionEditingButton
@onready var current_state_label: Label = $VBox/VBoxBottom/CurrentStateLabel

## Region Editing Buttons
@onready var create_first_level_region_button: Button = $VBox/VBoxTop/RegionEditingButtonsBox/CreateFirstLevelRegionButton


@onready var create_new_region_container: CreateNewRegionContainer = $"../CreateNewRegionContainer"
@onready var region_editing_buttons_box: VBoxContainer = $VBox/VBoxTop/RegionEditingButtonsBox
@onready var add_new_cell_button: Button = $VBox/VBoxTop/AddNewCellButton
@onready var adm_level_spin_box: SpinBox = $VBox/AdmLevelSpinBox


func _ready() -> void:
	player.state_changed.connect(_on_player_state_change)
	region_editing_buttons_box.hide()
	display_mode_manager.mode_changed.connect(_on_display_mode_changed)
	
	if display_mode_manager.get_current_id() == &"administrative":
		adm_level_spin_box.show()
	else:
		adm_level_spin_box.hide()
	adm_level_spin_box.set_value(float(player.adm_level))


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


func _hide_ui() -> void:
	region_editing_buttons_box.hide()
	player.selected_cell_ids.clear()


func _on_region_editing_button_pressed() -> void:
	var st = player.get_state()
	if st == Player.State.REGION_EDITING:
		player.set_state(Player.State.IDLE)
		_hide_ui()
	else:
		player.set_state(Player.State.REGION_EDITING)
		region_editing_buttons_box.show()


func _on_create_first_level_region_button_pressed() -> void:
	player.set_state(Player.State.PAUSE)
	create_new_region_container.show_container(true, 1)


func _on_add_new_cell_button_pressed() -> void:
	var st = player.get_state()
	if st == Player.State.POLYGONS_EDITING:
		player.set_state(Player.State.IDLE)
		_hide_ui()
	else:
		player.set_state(Player.State.POLYGONS_EDITING)


func _on_display_mode_changed(id: StringName, _display_name: String) -> void:
	match id:
		&"administrative":
			adm_level_spin_box.show()
		_:
			adm_level_spin_box.hide()


func _on_adm_level_spin_box_value_changed(value: float) -> void:
	player.set_adm_level(int(value))
