class_name TerrainDisplayMode
extends MapDisplayMode

## "Fizyczny" — naturalne kolory komórek (bez wypełniania regionów),
## z granicami komórek, bez site'ów.


func get_id() -> StringName:
	return &"terrain"


func get_display_name() -> String:
	return "Fizyczny"


func get_order() -> int:
	return 20


func apply_display(map: Map) -> void:
	map.chunk_draw_mode = MapChunk.DrawMode.LAND_OVER_WATER
	map.draw_cells = true
	map.draw_points = false
	map.draw_neighbors = false
	map.draw_triangulation = false
	map.draw_site_centers = false
	map.draw_region_fill = false
	map.draw_coastal_links = false
	map.draw_land_mask_outline = true
	map.draw_water_cell_borders = false
	map.highlight_water_cells = false
	map.draw_region_boundaries = false
	map.visible_admin_level = 0
