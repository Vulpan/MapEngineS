extends Node2D
class_name Player

enum State {IDLE, REGION_EDITING, STATE_EDITING, POLYGONS_EDITING}

signal state_changed

var current_state: State = State.IDLE : set = set_state

var selected_cell_ids: Array[int] = []

@onready var map: Map = get_tree().get_first_node_in_group("Map")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos := get_local_mouse_position()

		if event.button_index == MOUSE_BUTTON_LEFT:
			if current_state == State.REGION_EDITING:
				if Input.is_key_pressed(KEY_SHIFT):
					var id = map.find_cell_id_at_position(mouse_pos)
					selected_cell_ids.append(id)
				else:
					selected_cell_ids.clear()
					var id = map.find_cell_id_at_position(mouse_pos)
					selected_cell_ids.append(id)
		
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
	
	state_changed.emit()
