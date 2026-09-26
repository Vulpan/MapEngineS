extends Node2D
class_name Player

enum State {IDLE, REGION_EDITING, STATE_EDITING, POLYGONS_EDITING, PAUSE}

signal state_changed

var current_state: State = State.IDLE : set = set_state, get = get_state

var selected_cell_ids: Array[int] = []
var capital_id: int = -1

var adm_level: int = 1 : set = set_adm_level, get = get_adm_level

@onready var map: Map = get_tree().get_first_node_in_group("Map")
@onready var display_mode_manager: DisplayModeManager = get_tree().get_first_node_in_group("DisplayModeManager")


func _unhandled_input(event: InputEvent) -> void:
	if get_state() != Player.State.PAUSE:
		if event is InputEventMouseButton and event.pressed:
			var mouse_pos := get_local_mouse_position()
			if event.button_index == MOUSE_BUTTON_LEFT:
				if current_state == State.REGION_EDITING:
					if Input.is_key_pressed(KEY_SHIFT):
						var id = map.find_cell_id_at_position(mouse_pos)
						if not selected_cell_ids.has(id):
							selected_cell_ids.append(id)
					else:
						var id = map.find_cell_id_at_position(mouse_pos)
						if id != -1:
							selected_cell_ids.clear()
							selected_cell_ids.append(id)
				if current_state == State.POLYGONS_EDITING:
					map.add_point_at(mouse_pos)
				
			if event.button_index == MOUSE_BUTTON_RIGHT:
				var id = map.find_cell_id_at_position(mouse_pos)
				selected_cell_ids.erase(id)
				
				#if Input.is_key_pressed(KEY_SHIFT):
					#move_nearest_point_to(mouse_pos)
				#elif Input.is_key_pressed(KEY_CTRL):
					#selected_cell_id = find_cell_id_at_position(mouse_pos)
					#update_layers()
				#else:
					#add_point_at(mouse_pos)
				#print(mouse_pos)
				#print(map.find_cell_id_at_position(mouse_pos))

			#elif event.button_index == MOUSE_BUTTON_RIGHT:
				#remove_point_at(mouse_pos)


func set_state(st: State) -> void:
	if current_state == st:
		current_state = State.IDLE
	else:
		current_state = st
	
	clear()
	
	state_changed.emit()


func get_state() -> State:
	return current_state


func set_capital_id(id: int) -> void:
	capital_id = id


func set_adm_level(lv: int) -> void:
	adm_level = lv
	var adm_dp_mode = display_mode_manager.get_mode(&"administrative")
	adm_dp_mode.set_administrative_level(adm_level)
	display_mode_manager.set_mode(&"administrative")


func get_adm_level() -> int:
	return adm_level


func clear() -> void:
	capital_id = -1
