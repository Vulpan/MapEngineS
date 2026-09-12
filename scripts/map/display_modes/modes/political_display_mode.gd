class_name PoliticalDisplayMode
extends MapDisplayMode

## "Polityczny" — kolory regionów na pierwszym planie, czysty podgląd
## bez site'ów i nakładek debugowych.


func get_id() -> StringName:
	return &"political"


func get_display_name() -> String:
	return "Polityczny"


func get_order() -> int:
	return 10


func apply_display(map: Map) -> void:
	map.chunk_draw_mode = MapChunk.DrawMode.LAND_OVER_WATER
	map.draw_cells = true
	map.draw_points = false
	map.draw_neighbors = false
	map.draw_triangulation = false
	map.draw_site_centers = false
	map.draw_region_fill = true
	map.draw_coastal_links = false
	map.draw_land_mask_outline = true
	map.draw_water_cell_borders = false
	map.highlight_water_cells = false
	map.draw_region_boundaries = false
	map.visible_admin_level = 0
