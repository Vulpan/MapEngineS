extends BaseMapLayer
class_name HighlightLayer

var highlighted_cell_ids: Array[int] = []
var highlight_color := Color(1.0, 1.0, 1.0, 0.3)

@onready var player: Player = get_tree().get_first_node_in_group("Player")


func set_main(main_node) -> void:
	main_ref = main_node


func set_highlighted(ids: Array[int]) -> void:
	highlighted_cell_ids = ids
	queue_redraw()


func clear_highlight() -> void:
	highlighted_cell_ids.clear()
	queue_redraw()


func _ready() -> void:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = preload("res://shaders/highlight_pulse.gdshader")
	material = shader_mat


func _draw() -> void:
	if main_ref == null:
		return
	
	if player.current_state == Player.State.REGION_EDITING:
		for cell_id in player.selected_cell_ids:
			if not main_ref.map_data.cells.has(cell_id):
				continue
			
			var cell: CellData = main_ref.map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			
			draw_colored_polygon(cell.polygon, highlight_color)
	
	else:
		for cell_id in highlighted_cell_ids:
			if not main_ref.map_data.cells.has(cell_id):
				continue
			
			var cell: CellData = main_ref.map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			
			draw_colored_polygon(cell.polygon, highlight_color)
