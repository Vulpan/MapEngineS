class_name DefaultDisplayMode
extends MapDisplayMode

## "Podstawowy" — stan bazowy projektu (domyślne wartości z map.gd)
## + wypełnianie regionów (chunki kolorują komórki po przypisanym regionie).


func get_id() -> StringName:
	return &"default"


func get_display_name() -> String:
	return "Podstawowy"


func get_order() -> int:
	return 0


func apply_display(map: Map) -> void:
	map.chunk_draw_mode = MapChunk.DrawMode.LAND_OVER_WATER
	map.draw_cells = true
	map.draw_points = true
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
