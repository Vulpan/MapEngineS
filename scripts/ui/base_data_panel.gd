extends PanelContainer
class_name BaseDataPanel

@onready var map_node: Map = get_tree().get_first_node_in_group("Map")

@onready var map_name_data_box: DataBox = $Scroll/VBox/MapNameDataBox
@onready var map_size_data_box: DataBox = $Scroll/VBox/MapSizeDataBox
@onready var map_scale_data_box: DataBox = $Scroll/VBox/MapScaleDataBox

func set_data() -> void:
	if map_node.is_active:
		map_name_data_box.set_content(map_node.save_name.split(".")[0])
		
		var h = map_node.map_height
		var w = map_node.map_width
		map_size_data_box.set_content("%s x %s" % [h, w])
		
		map_scale_data_box.set_content(str(map_node.map_render_scale))


func _on_map_initialized() -> void:
	set_data()
