extends Node2D
class_name ChunkRenderLayer

var main_ref
var chunk_size: float = 512.0

var chunks: Dictionary = {}        # "cx:cy" -> MapChunk
var cell_to_chunk: Dictionary = {} # cell_id -> "cx:cy"

var chunks_x: int = 0
var chunks_y: int = 0


func set_main(main_node) -> void:
	main_ref = main_node


func setup_chunks(map_bounds: Rect2, p_chunk_size: float = 512.0) -> void:
	chunk_size = p_chunk_size
	_clear_all()
	
	chunks_x = int(ceil(map_bounds.size.x / chunk_size))
	chunks_y = int(ceil(map_bounds.size.y / chunk_size))
	
	for cy in range(chunks_y):
		for cx in range(chunks_x):
			var rect := Rect2(
				map_bounds.position.x + cx * chunk_size,
				map_bounds.position.y + cy * chunk_size,
				chunk_size,
				chunk_size
			)
			var key := _chunk_key(cx, cy)
			
			var chunk := MapChunk.new()
			chunk.setup(cx, cy, rect, main_ref)
			add_child(chunk)
			chunks[key] = chunk


func rebuild_all() -> void:
	cell_to_chunk.clear()
	
	for key in chunks.keys():
		chunks[key].set_cells([])
	
	if main_ref == null:
		return
	
	var assignments: Dictionary = {}
	
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		var key := _chunk_key_for_position(cell.site)
		
		if not assignments.has(key):
			assignments[key] = []
		assignments[key].append(cell.id)
		cell_to_chunk[cell.id] = key
	
	for key in assignments.keys():
		if chunks.has(key):
			chunks[key].set_cells(assignments[key])
			chunks[key].refresh()


## Aktualizuje przypisania komórek do chunków inkrementalnie,
## bez skanowania całego indeksu cell_to_chunk (kiedyś O(n) na chunka).
func refresh_chunks_for_cells(cell_ids: Array) -> void:
	var dirty_chunks: Dictionary = {}

	for cell_id in cell_ids:
		if main_ref.map_data.cells.has(cell_id):
			var cell: CellData = main_ref.map_data.cells[cell_id]
			var new_key := _chunk_key_for_position(cell.site)
			var old_key: String = cell_to_chunk.get(cell_id, "")

			if old_key != new_key:
				if old_key != "" and chunks.has(old_key):
					chunks[old_key].remove_cell_id(cell_id)
					dirty_chunks[old_key] = true
				if chunks.has(new_key):
					chunks[new_key].add_cell_id(cell_id)
				cell_to_chunk[cell_id] = new_key

			dirty_chunks[new_key] = true
		else:
			var old_key: String = cell_to_chunk.get(cell_id, "")
			if old_key != "" and chunks.has(old_key):
				chunks[old_key].remove_cell_id(cell_id)
				dirty_chunks[old_key] = true
			cell_to_chunk.erase(cell_id)

	for key in dirty_chunks.keys():
		if chunks.has(key):
			chunks[key].refresh()


func remove_cell(cell_id: int) -> void:
	var key: String = cell_to_chunk.get(cell_id, "")
	cell_to_chunk.erase(cell_id)

	if key != "" and chunks.has(key):
		chunks[key].remove_cell_id(cell_id)
		chunks[key].refresh()


func pick_cell_at(pos: Vector2) -> int:
	if main_ref == null:
		return -1
	
	var key := _chunk_key_for_position(pos)
	if not chunks.has(key):
		return -1
	
	var chunk: MapChunk = chunks[key]
	
	# ląd pierwszy
	for cell_id in chunk.cell_ids:
		if not main_ref.map_data.cells.has(cell_id):
			continue
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.domain != CellData.DOMAIN_LAND:
			continue
		if cell.polygon.size() >= 3 and Geometry2D.is_point_in_polygon(pos, cell.polygon):
			return cell_id
	
	# potem woda — nadal klikalna
	for cell_id in chunk.cell_ids:
		if not main_ref.map_data.cells.has(cell_id):
			continue
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.domain != CellData.DOMAIN_WATER:
			continue
		if cell.polygon.size() >= 3 and Geometry2D.is_point_in_polygon(pos, cell.polygon):
			return cell_id
	
	return -1


func refresh_all() -> void:
	for key in chunks.keys():
		chunks[key].refresh()


func _chunk_key(cx: int, cy: int) -> String:
	return "%d:%d" % [cx, cy]


func _chunk_key_for_position(pos: Vector2) -> String:
	var cx := int(pos.x / chunk_size)
	var cy := int(pos.y / chunk_size)
	cx = clampi(cx, 0, chunks_x - 1)
	cy = clampi(cy, 0, chunks_y - 1)
	return _chunk_key(cx, cy)


func _clear_all() -> void:
	for key in chunks.keys():
		chunks[key].queue_free()
	chunks.clear()
	cell_to_chunk.clear()
