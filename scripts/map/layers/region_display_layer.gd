extends BaseMapLayer
class_name RegionDisplayLayer

## Granice regionów najniższego poziomu administracyjnego (poziom 1).
##
## Algorytm: dla każdego regionu zliczamy odcinki krawędzi jego komórek po
## kluczu z zaokrąglonych (snap 3 miejsca po przecinku) i znormalizowanych
## kierunkowo wierzchołków. Krawędź wspólna dwóch komórek regionu liczy się
## 2 razy (kasowanie wnętrza) — na obrysie zostają wyłącznie odcinki
## liczone dokładnie raz. Żadnych merge_polygons (zawodne na łańcuchach
## samopodobnych wielokątów).
##
## Widoczność: main_ref.draw_region_boundaries (synchronizowane w
## Map.update_layers()). Wybrany region (main_ref.selected_region_id)
## dostaje białą obwódkę i lekkie wypełnienie.

## Zaokrąglanie wierzchołków do 3 miejsc po przecinku (musi się zgadzać
## z tolerancją budowy geometrii — jeśli granice wyglądają na przerywane
## albo podwójne, zwiększ precyzję).
const EDGE_PREC := 1000.0

@export var boundary_width := 2.0
@export var selected_width := 3.5
@export var selected_fill_color := Color(1.0, 1.0, 1.0, 0.18)


func _draw() -> void:
	if main_ref == null or not main_ref.draw_region_boundaries:
		return
	var map_data: MapData = main_ref.map_data
	if map_data == null:
		return

	var selected_region: int = main_ref.selected_region_id
	var regions = get_admin_region_ids(map_data) 
	var reg_cell_ids: Array[int] = []
	for rid in regions:
		var region: RegionData = map_data.regions[rid]
		reg_cell_ids.append_array(region.cell_ids)
	
	for cell_id in main_ref.map_data.cells.keys():
		if reg_cell_ids.has(cell_id):
			continue
		
		var cell: CellData = main_ref.map_data.cells[cell_id]
		var poly := cell.polygon
		
		if cell.domain != CellData.DOMAIN_LAND:
			continue
		if not main_ref.is_polygon_drawable(poly):
			continue
		
		draw_colored_polygon(cell.polygon, Color(0.3, 0.3, 0.3, 0.3))
	
	for rid in regions:
		var region: RegionData = map_data.regions[rid]
		var edges := compute_boundary_edges(rid, map_data)
		if edges.is_empty():
			continue

		var col: Color = region.color if region.color != Color.BLACK \
			else main_ref.color_from_id(rid * 1000, 1.0)
		for e in edges:
			draw_line(e[0], e[1], col, boundary_width, false)

		# wybrany region: wypełnienie per komórka (komórki teselują region
		# dokładnie — nie trzeba scalać wielokątów) + biała obwódka na wierzchu
		if rid == selected_region:
			for cid in region.cell_ids:
				var cell: CellData = map_data.cells.get(cid)
				if cell == null or cell.polygon.size() < 3:
					continue
				draw_colored_polygon(cell.polygon, selected_fill_color)
			for e in edges:
				draw_line(e[0], e[1], Color.WHITE, selected_width, false)


## Regiony poziomu administracyjnego aktualnie wyświetlanego
## (main_ref.visible_admin_level; domyślnie 1) — do rysowania i testów.
func get_admin_region_ids(map_data: MapData) -> Array:
	var result: Array = []
	if map_data == null:
		return result
	var lvl: int = 1
	if main_ref != null and main_ref.visible_admin_level > 0:
		lvl = main_ref.visible_admin_level
	for rid in map_data.regions.keys():
		var region: RegionData = map_data.regions[rid]
		if region.is_admin_level(lvl):
			result.append(rid)
	result.sort()
	return result


## Obrys regionu jako lista odcinków [Vector2, Vector2]. Krawędzie wewnętrzne
## (wspólne dla dwóch komórek regionu) są kasowane przez zliczanie.
func compute_boundary_edges(region_id: int, map_data: MapData) -> Array:
	if map_data == null or not map_data.regions.has(region_id):
		return []
	var region: RegionData = map_data.regions[region_id]

	var counts := {}      # Vector4i -> liczba wystąpień
	var segments := {}    # Vector4i -> [Vector2, Vector2] (pierwsze oryginalne)
	for cid in region.cell_ids:
		var cell: CellData = map_data.cells.get(cid)
		if cell == null or cell.polygon.size() < 3:
			continue
		var n := cell.polygon.size()
		for i in range(n):
			var a: Vector2 = cell.polygon[i]
			var b: Vector2 = cell.polygon[(i + 1) % n]
			var key := _edge_key(a, b)
			if counts.has(key):
				counts[key] = counts[key] + 1
			else:
				counts[key] = 1
				segments[key] = [a, b]

	var result: Array = []
	for key in counts.keys():
		if counts[key] == 1:
			result.append(segments[key])
	return result


## Klucz krawędzi: wierzchołki zaokrąglone (snap) i znormalizowane kierunkowo,
## żeby wspólna krawędź dwóch komórek o przeciwnym windingu dała ten sam klucz.
func _edge_key(a: Vector2, b: Vector2) -> Vector4i:
	var pa := Vector2i(int(round(a.x * EDGE_PREC)), int(round(a.y * EDGE_PREC)))
	var pb := Vector2i(int(round(b.x * EDGE_PREC)), int(round(b.y * EDGE_PREC)))
	if pa.x > pb.x or (pa.x == pb.x and pa.y > pb.y):
		var tmp := pa
		pa = pb
		pb = tmp
	return Vector4i(pa.x, pa.y, pb.x, pb.y)
