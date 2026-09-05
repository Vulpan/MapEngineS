extends BaseMapLayer
class_name DebugLayer


func _draw() -> void:
	if main_ref == null:
		return
	
	if main_ref.draw_neighbors:
		_draw_neighbors()
	
	if main_ref.draw_coastal_links:
		_draw_coastal_links()
	
	if main_ref.draw_triangulation:
		_draw_triangulation_lines()
	
	if main_ref.draw_points:
		_draw_points()
	
	if main_ref.draw_site_centers:
		_draw_site_centers()
	
	_draw_selection()
	_draw_debug_text()


func _draw_neighbors() -> void:
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		for neigh_id in cell.neighbor_ids:
			if cell_id < neigh_id and main_ref.map_data.cells.has(neigh_id):
				var other: CellData = main_ref.map_data.cells[neigh_id]
				draw_line(cell.site, other.site, Color(1.0, 0.2, 0.2, 0.35), 1.0)


func _draw_coastal_links() -> void:
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.domain != CellData.DOMAIN_LAND:
			continue
		
		for neigh_id in cell.coastal_neighbor_ids:
			if main_ref.map_data.cells.has(neigh_id):
				var other: CellData = main_ref.map_data.cells[neigh_id]
				draw_line(cell.site, other.site, Color(0.0, 1.0, 1.0, 0.4), 1.0)


func _draw_triangulation_lines() -> void:
	for key in main_ref.component_managers.keys():
		var manager: DynamicDelaunayVoronoi = main_ref.component_managers[key]
		var is_water = key.begins_with(str(CellData.DOMAIN_WATER) + ":")
		var color := Color(0.2, 1.0, 0.2, 0.35)
		if is_water:
			color = Color(0.2, 0.5, 1.0, 0.35)
		
		for t in manager.triangulation:
			draw_line(t.a, t.b, color, 1.0)
			draw_line(t.b, t.c, color, 1.0)
			draw_line(t.c, t.a, color, 1.0)


func _draw_points() -> void:
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		var color := Color(1.0, 0.8, 0.1)
		if cell.domain == CellData.DOMAIN_WATER:
			color = Color(0.4, 0.7, 1.0)
		draw_circle(cell.site, main_ref.point_radius, color)
		draw_circle(cell.site, main_ref.point_radius + 1.0, Color.BLACK, false)


func _draw_site_centers() -> void:
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		draw_circle(cell.site, 2.0, Color(0.0, 1.0, 0.0))


func _draw_selection() -> void:
	if main_ref.selected_cell_id != -1 and main_ref.map_data.cells.has(main_ref.selected_cell_id):
		var cell: CellData = main_ref.map_data.cells[main_ref.selected_cell_id]
		if cell.polygon.size() >= 3:
			for i in range(cell.polygon.size()):
				var a := cell.polygon[i]
				var b := cell.polygon[(i + 1) % cell.polygon.size()]
				draw_line(a, b, Color.YELLOW, 3.0)
		draw_circle(cell.site, main_ref.point_radius + 3.0, Color.YELLOW, false)
	
	if main_ref.selected_region_id != -1 and main_ref.map_data.regions.has(main_ref.selected_region_id):
		var region: RegionData = main_ref.map_data.regions[main_ref.selected_region_id]
		for cell_id in region.cell_ids:
			if not main_ref.map_data.cells.has(cell_id):
				continue
			var cell: CellData = main_ref.map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			for i in range(cell.polygon.size()):
				var a := cell.polygon[i]
				var b := cell.polygon[(i + 1) % cell.polygon.size()]
				draw_line(a, b, Color(1.0, 0.5, 0.0, 1.0), 2.0)


func _draw_debug_text() -> void:
	var text := "Cells: %d | Regions: %d | Groups: %d | Selected cell: %d" % [
		main_ref.map_data.cells.size(),
		main_ref.map_data.regions.size(),
		main_ref.component_managers.size(),
		main_ref.selected_cell_id
	]
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(12, 20),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color.WHITE
	)
