class_name DebugDisplayMode
extends MapDisplayMode

## "Debug" — pełny zestaw nakładek diagnostycznych: site'y, sąsiedztwa,
## triangulacja, centra, linki przybrzeżne, wszystko rysowane razem.


func get_id() -> StringName:
	return &"debug"


func get_display_name() -> String:
	return "Debug"


func get_order() -> int:
	return 40


func apply_display(map: Map) -> void:
	map.chunk_draw_mode = MapChunk.DrawMode.ALL
	map.draw_cells = true
	map.draw_points = true
	map.draw_neighbors = true
	map.draw_triangulation = true
	map.draw_site_centers = true
	map.draw_region_fill = true
	map.draw_coastal_links = true
	map.draw_land_mask_outline = true
	map.draw_water_cell_borders = true
	map.highlight_water_cells = true
	map.draw_region_boundaries = false
	map.visible_admin_level = 0
