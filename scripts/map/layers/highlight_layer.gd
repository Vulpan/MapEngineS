extends BaseMapLayer
class_name HighlightLayer

var highlighted_cell_ids: Array[int] = []
var highlight_color := Color(1.0, 1.0, 1.0, 0.3)
var highlight_color_red := Color(1.0, 0.0, 0.0, 0.75)

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
	
	var state = player.get_state()
	if state == Player.State.REGION_EDITING or state == Player.State.PAUSE:
		var cells = []
		cells.append_array(player.selected_cell_ids)
		cells.append_array(highlighted_cell_ids)
		for cell_id in cells:
			if not main_ref.map_data.cells.has(cell_id):
				continue
			
			var cell: CellData = main_ref.map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			
			draw_colored_polygon(cell.polygon, highlight_color)
		
		if state == Player.State.PAUSE:
			var capital_id = player.capital_id
			if main_ref.map_data.cells.has(capital_id):
				var cell: CellData = main_ref.map_data.cells[capital_id]
				if cell.polygon.size() >= 3:
					draw_colored_polygon(cell.polygon, highlight_color_red)
		
	else:
		for cell_id in highlighted_cell_ids:
			if not main_ref.map_data.cells.has(cell_id):
				continue
			
			var cell: CellData = main_ref.map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			
			draw_colored_polygon(cell.polygon, highlight_color)
