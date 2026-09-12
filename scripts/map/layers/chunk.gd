extends Node2D
class_name MapChunk

enum DrawMode {
	LAND_ONLY,      # tylko ląd, woda jako tło
	WATER_ONLY,     # tylko woda
	ALL,            # wszystko razem
	LAND_OVER_WATER # woda najpierw, ląd na wierzchu
}

var chunk_x: int = 0
var chunk_y: int = 0
var chunk_rect: Rect2
var cell_ids: Array = []
var main_ref
var draw_mode: int = DrawMode.LAND_OVER_WATER


func setup(cx: int, cy: int, rect: Rect2, main_node) -> void:
	chunk_x = cx
	chunk_y = cy
	chunk_rect = rect
	main_ref = main_node
	name = "Chunk_%d_%d" % [cx, cy]


func set_cells(ids: Array) -> void:
	cell_ids = ids


func add_cell_id(id: int) -> void:
	if id not in cell_ids:
		cell_ids.append(id)


func remove_cell_id(id: int) -> void:
	cell_ids.erase(id)


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if main_ref == null:
		return
	
	match draw_mode:
		DrawMode.LAND_ONLY:
			_draw_domain(CellData.DOMAIN_LAND)
		DrawMode.WATER_ONLY:
			_draw_domain(CellData.DOMAIN_WATER)
		DrawMode.ALL:
			_draw_all()
		DrawMode.LAND_OVER_WATER:
			_draw_domain(CellData.DOMAIN_WATER)
			_draw_domain(CellData.DOMAIN_LAND)


func _draw_domain(domain: int) -> void:
	for cell_id in cell_ids:
		if not main_ref.map_data.cells.has(cell_id):
			continue
		
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.domain != domain:
			continue
		if cell.polygon.size() < 3:
			continue
		if not _admin_visible(cell):
			continue
		
		draw_colored_polygon(cell.polygon, _get_cell_color(cell))


func _draw_all() -> void:
	for cell_id in cell_ids:
		if not main_ref.map_data.cells.has(cell_id):
			continue
		
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.polygon.size() < 3:
			continue
		if not _admin_visible(cell):
			continue
		
		draw_colored_polygon(cell.polygon, _get_cell_color(cell))


## Filtr poziomu administracyjnego (main_ref.visible_admin_level):
## 0 = bez filtra. N > 0 = widoczne są tylko komórki regionów poziomu N;
## ląd bez regionu / z innego poziomu jest ukrywany. Woda zawsze widoczna
## (jest tłem mapy, nie elementem podziału administracyjnego).
func _admin_visible(cell: CellData) -> bool:
	var lvl: int = main_ref.visible_admin_level
	if lvl <= 0 or cell.domain == CellData.DOMAIN_WATER:
		return true
	if cell.region_id == -1:
		return false
	var region = main_ref.map_data.regions.get(cell.region_id)
	return region != null and region.is_admin_level(lvl)


func _get_cell_color(cell: CellData) -> Color:
	if cell.domain == CellData.DOMAIN_WATER:
		return Color(0.16, 0.35, 0.72, 0.30)
	
	if cell.region_id != -1 and main_ref != null and main_ref.draw_region_fill:
		var region = main_ref.map_data.regions.get(cell.region_id)
		if region != null and region.color != Color.BLACK:
			return Color(region.color, 0.35)
		return main_ref.color_from_id(cell.region_id * 1000, 0.35)
	
	if main_ref != null:
		return main_ref.color_from_id(cell.id, 0.22)
	
	return Color(0.5, 0.5, 0.5, 0.22)
