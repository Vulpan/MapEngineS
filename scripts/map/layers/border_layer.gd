extends BaseMapLayer
class_name BorderLayer


func _draw() -> void:
	if main_ref == null:
		return
	
	if not main_ref.draw_cells:
		return
	
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		var poly := cell.polygon
		
		if not main_ref.is_polygon_drawable(poly):
			continue
		
		if cell.domain == CellData.DOMAIN_WATER and not main_ref.draw_water_cell_borders:
			continue
		
		var border_color := Color.WHITE
		
		if cell.domain == CellData.DOMAIN_WATER:
			border_color = Color(0.4, 0.7, 1.0, 0.5)
		elif cell.region_id != -1:
			border_color = main_ref.color_from_id(cell.region_id * 1000, 1.0)
		
		for i in range(poly.size()):
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			draw_line(a, b, border_color, 1.0)
