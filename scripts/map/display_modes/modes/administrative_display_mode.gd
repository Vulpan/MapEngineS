class_name AdministrativeDisplayMode
extends MapDisplayMode

## "Administracyjny" — podział administracyjny najniższego poziomu (poziom 1):
## granice regionów (RegionDisplayLayer) + wypełnienie kolorami regionów.
## Wybrany region jest podświetlany na biało przez warstwę granic.
## Wyższe poziomy (level >= 2) NIE są rysowane — do dodania w osobnych
## trybach/mode'ach, gdy hierarchia będzie gotowa.


func get_id() -> StringName:
	return &"administrative"


func get_display_name() -> String:
	return "Administracyjny"


func get_order() -> int:
	return 15


func apply_display(map: Map) -> void:
	map.chunk_draw_mode = MapChunk.DrawMode.LAND_OVER_WATER
	# Bez konturów komórek — widoczne są WYŁĄCZNIE regiony poziomu 1:
	# wypełnienie kolorem regionu + granice (RegionDisplayLayer).
	# Komórki bez regionu (lub z regionu innego poziomu) są ukrywane
	# przez filtr visible_admin_level w chunkach. Woda pozostaje jako tło.
	map.draw_cells = false
	map.draw_points = false
	map.draw_neighbors = false
	map.draw_triangulation = false
	map.draw_site_centers = false
	map.draw_region_fill = true
	map.draw_coastal_links = false
	map.draw_land_mask_outline = false
	map.draw_water_cell_borders = false
	map.highlight_water_cells = false
	map.draw_region_boundaries = true
	map.visible_admin_level = 1
