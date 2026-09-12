class_name Map
extends Node2D

signal initialized

@export var is_active: bool = true
@export var map_width: int = 4096
@export var map_height: int = 4096
@export var map_render_scale := 1.0
@export var initial_points_count: int = 1000
@export var max_water_cells: int = 10
@export var max_border_points := 200
@export var chunk_size := 512.0
@export var highlight_water_cells := false

#LAND_ONLY - tylko ląd, woda = tło z _draw()
#WATER_ONLY - tylko woda, debug
#ALl - wszystko razem, bez gwarancji kolejności
#LAND_OVER_WATER - woda pod lądem w tym samym chunku
@export_enum("LAND_ONLY", "WATER_ONLY", "ALL", "LAND_OVER_WATER") var chunk_draw_mode: int = 3
@export var draw_cells := true
@export var draw_points := true
@export var draw_neighbors := false
@export var draw_triangulation := false
@export var draw_site_centers := false
@export var draw_region_fill := false
@export var draw_coastal_links := false

@export var draw_land_mask_outline := true
@export var draw_water_cell_borders := false
## Granice regionów poziomu 1 (warstwa RegionDisplayLayer; tryb Administracyjny).
@export var draw_region_boundaries := false
## Filtr poziomu administracyjnego dla chunków: 0 = wyłączony (rysuj wszystko),
## N > 0 = rysowane są WYŁĄCZNIE komórki należące do regionów poziomu N
## (komórki lądowe bez regionu lub z regionu innego poziomu są ukrywane;
## woda pozostaje widoczna jako tło mapy).
@export var visible_admin_level := 0
## Automatyczne łatanie "szczelin" lądu — fragmentów maski lądu, do których
## nie dociera żadna komórka lądowa (cienkie cyple/przesmyki bez site'u lądu).
## Bez tego takie miejsca renderują się jak woda, nie da się ich kliknąć
## ani przypisać do regionu (wcięcia w trybie administracyjnym).
@export var patch_land_slivers := true
## Minimalne pole (px²) szczeliny lądu, która jest łataną (mniejsze są
## niewidoczne i pomijane).
@export var land_sliver_min_area := 150.0

@export var point_radius := 3.0
@export var remove_radius := 20.0
@export var save_path := Global.save_path
@export var save_name := "map.json"

@export var use_land_mask := false
@export_file("*.png") var land_mask_path := ""
@export var land_threshold := 0.5
@export var black_is_land := true
@export var site_min_distance: float = 3.0

@export var use_border_mask := false
@export_file("*.png") var border_mask_path := "res://assets/map/map-border-only-4096.png"
@export var border_spacing := 20.0
@export var border_threshold := 0.5

@export var generate_on_land_only := true
@export var balanced_island_distribution := true
@export var allow_manual_points_on_water := true

@export var minimum_points_per_island := 1
@export var minimum_island_area := 128.0

# Wypisuje rozbicie czasu operacji edycyjnych (add/remove/move) na sekcje.
@export var profile_ops := false

@export var coastal_epsilon := 1.5

var bounds: Rect2
var rng := RandomNumberGenerator.new()
@export var randomization_seed: int = 0  # 0 = losowe; >0 = powtarzalna mapa (debug/testy)
var effective_width: int
var effective_height: int

var points: Array[Vector2] = []
var cached_cells: Dictionary = {} # site -> [polygon, neighbor_sites]

var map_data: MapData
var land_mask_processor: LandMaskProcessor
var border_mask_processor: BorderMaskProcessor

var site_to_cell_id: Dictionary = {} # Vector2 -> int
var cell_id_to_site: Dictionary = {} # int -> Vector2

var component_managers: Dictionary = {} # "domain:component" -> DynamicDelaunayVoronoi

var site_index := SpatialHash2D.new(32.0) # indeks przestrzenny site'ów (O(1) zamiast skanów O(n))

# Siatki przestrzenne dla sąsiedztwa przybrzeżnego (dualne: woda + ląd).
var water_grid: Dictionary = {}        # Vector2i -> Array[int] (id komórek wodnych)
var land_grid: Dictionary = {}         # Vector2i -> Array[int] (id komórek lądowych)
var water_grid_cells: Dictionary = {}  # cell_id -> Array[Vector2i] (zajmowane kubełki)
var land_grid_cells: Dictionary = {}
var coastal_grid_size := 128.0

var selected_cell_id: int = -1
var selected_region_id: int = -1

var chunk_render_layer: ChunkRenderLayer
var water_back_layer: WaterBackLayer
var highlight_layer: HighlightLayer
var border_layer: BorderLayer
var region_display_layer: RegionDisplayLayer
var mask_layer: MaskLayer
var debug_layer: DebugLayer

func _ready() -> void:
	if is_active:
		initialize()


func initialize() -> void:
	if randomization_seed != 0:
		rng.seed = randomization_seed
	else:
		rng.randomize()
	effective_width = int(map_width * map_render_scale)
	effective_height = int(map_height * map_render_scale)
	bounds = Rect2(0, 0, effective_width, effective_height)

	map_data = MapData.new()
	map_data.bounds = bounds

	land_mask_processor = LandMaskProcessor.new()
	if use_land_mask and land_mask_path != "":
		var ok := land_mask_processor.load_mask(
			land_mask_path,
			Vector2i(effective_width, effective_height),
			land_threshold,
			black_is_land
		)
		print("Mask loaded: ", ok, " | land comps=", land_mask_processor.land_polygons.size())
	
	border_mask_processor = BorderMaskProcessor.new()
	if use_border_mask and border_mask_path != "":
		var ok := border_mask_processor.load_border_mask(
			border_mask_path,
			Vector2i(effective_width, effective_height),
			border_threshold,
			border_spacing
		)
		print("Border mask loaded: ", ok, " | points=", border_mask_processor.border_points.size())
	
	setup_layers()

	_generate_initial_cells(initial_points_count)
	rebuild_geometry_from_map_data()
	if patch_land_slivers:
		_patch_land_slivers()
	update_layers()
	queue_redraw()
	
	save_map()
	initialized.emit()


func create_new_map(dict: Dictionary) -> void:
	var map_name = dict["map_name"]
	var picture_path = dict["picture_path"]
	var border_path = dict["border_path"]
	
	if picture_path.is_empty():
		use_land_mask = false
		land_mask_path = ""
	
	if border_path.is_empty():
		use_border_mask = false
		border_mask_path = ""
	
	land_mask_path = picture_path
	border_mask_path = border_path
	print(dict)
	map_height = int(dict["height"])
	map_width = int(dict["width"])
	map_render_scale = float(dict["map_scale"])
	
	save_name = map_name
	
	is_active = true
	initialize()


func _draw() -> void:
	draw_rect(bounds, Color(0.08, 0.08, 0.08, 1.0), true)


# =========================================================
# LAYERS
# =========================================================
#TODO komentarze
func setup_layers() -> void:
	var old := get_node_or_null("RenderLayers")
	if old:
		old.queue_free()
	
	var container := Node2D.new()
	container.name = "RenderLayers"
	add_child(container)
	
	# 0. woda — rysowana GLOBALNIE pod chunkami (kolejność drzewa!), bo poligony
	# wodne przekraczają granice chunków i sibling CanvasItem'y nie zachowują
	# per-chunk porządku "woda pod lądem"
	water_back_layer = WaterBackLayer.new()
	water_back_layer.name = "WaterBackLayer"
	container.add_child(water_back_layer)
	water_back_layer.set_main(self)
	
	# 1. chunk render (fill wody + lądu)
	chunk_render_layer = ChunkRenderLayer.new()
	chunk_render_layer.name = "ChunkRenderLayer"
	container.add_child(chunk_render_layer)
	chunk_render_layer.set_main(self)
	chunk_render_layer.setup_chunks(bounds, chunk_size)
	_apply_chunk_draw_mode()
	
	# 2. Podświetlanie
	highlight_layer = HighlightLayer.new()
	highlight_layer.name = "HighlightLayer"
	container.add_child(highlight_layer)
	highlight_layer.set_main(self)
	#var shader_mat := ShaderMaterial.new()
	#shader_mat.shader = preload("res://shaders/highlight_pulse.gdshader")
	#highlight_layer.material = shader_mat
	
	# 3. kontury komórek
	border_layer = BorderLayer.new()
	border_layer.name = "BorderLayer"
	container.add_child(border_layer)
	border_layer.set_main(self)

	# 3.5 granice regionów poziomu 1 — nad konturami komórek, pod maską i debugiem
	region_display_layer = RegionDisplayLayer.new()
	region_display_layer.name = "RegionDisplayLayer"
	container.add_child(region_display_layer)
	region_display_layer.set_main(self)
	region_display_layer.visible = draw_region_boundaries
	
	# 4. kontur maski PNG
	mask_layer = MaskLayer.new()
	mask_layer.name = "MaskLayer"
	container.add_child(mask_layer)
	mask_layer.set_main(self)
	
	# 5. debug
	debug_layer = DebugLayer.new()
	debug_layer.name = "DebugLayer"
	container.add_child(debug_layer)
	debug_layer.set_main(self)


func update_layers() -> void:
	if border_layer:
		border_layer.queue_redraw()
	if mask_layer:
		mask_layer.queue_redraw()
	if debug_layer:
		debug_layer.queue_redraw()
	if region_display_layer:
		region_display_layer.visible = draw_region_boundaries
		region_display_layer.queue_redraw()


# =========================================================
# INITIAL GENERATION
# =========================================================

func _generate_initial_cells(count: int) -> void:
	map_data.clear()
	map_data.bounds = bounds
	site_index.clear()

	var created := 0
	var water_count := 0
	
	# ==========================================
	# FAZA 0: punkty z maski granic
	# ==========================================
	if use_border_mask and border_mask_processor != null:
		var border_created := 0
		var min_border_dist := border_spacing * 0.8
		var min_border_dist_sqr := min_border_dist * min_border_dist
		
		var pair_indices: Array[int] = []
		for i in range(border_mask_processor.border_pairs.size()):
			pair_indices.append(i)
		pair_indices.shuffle()
		
		var accepted: Array[Vector2] = []
		
		for idx in pair_indices:
			if border_created >= max_border_points:
				break
			
			var pair: Array = border_mask_processor.border_pairs[idx]
			var a: Vector2 = pair[0]
			var b: Vector2 = pair[1]
			var center := (a + b) * 0.5
			
			if not bounds.has_point(a) or not bounds.has_point(b):
				continue
			
			var too_close := false
			for existing in accepted:
				if center.distance_squared_to(existing) < min_border_dist_sqr:
					too_close = true
					break
			
			if too_close:
				continue
			
			if _site_exists_near(a, 1.0) or _site_exists_near(b, 1.0):
				continue
			
			var cell_a := map_data.create_cell(a)
			var cell_b := map_data.create_cell(b)
			site_index.insert(cell_a.id, a)
			site_index.insert(cell_b.id, b)
			
			if use_land_mask and land_mask_processor != null:
				cell_a.domain = land_mask_processor.sample_domain(a)
				cell_a.component_id = land_mask_processor.find_component_for_point(a, cell_a.domain)
				cell_b.domain = land_mask_processor.sample_domain(b)
				cell_b.component_id = land_mask_processor.find_component_for_point(b, cell_b.domain)
			else:
				cell_a.domain = CellData.DOMAIN_LAND
				cell_a.component_id = 0
				cell_b.domain = CellData.DOMAIN_LAND
				cell_b.component_id = 0
			
			cell_a.meta["border_origin"] = true
			cell_b.meta["border_origin"] = true
			
			accepted.append(center)
			border_created += 1
		
		print("Border pairs created: ", border_created, " / candidates: ", border_mask_processor.border_pairs.size())
	
	if use_land_mask and generate_on_land_only and land_mask_processor != null:
		var island_count := land_mask_processor.get_land_polygon_count()

		for island_index in range(island_count):
			if created >= count:
				break

			var area := land_mask_processor.get_land_polygon_area(island_index)
			if area < minimum_island_area:
				continue

			for i in range(minimum_points_per_island):
				if created >= count:
					break

				var site := land_mask_processor.get_random_point_in_land_polygon(island_index, rng)

				if _site_exists_near(site, site_min_distance):
					var found := false
					for retry in range(16):
						site = land_mask_processor.get_random_point_in_land_polygon(island_index, rng)
						if not _site_exists_near(site, site_min_distance):
							found = true
							break
					if not found:
						continue

				var cell := map_data.create_cell(site)
				site_index.insert(cell.id, site)
				cell.domain = CellData.DOMAIN_LAND
				cell.component_id = island_index
				created += 1

	var tries := 0
	var max_tries := count * 100

	while created < count and tries < max_tries:
		tries += 1

		var site := Vector2.ZERO

		if use_land_mask and generate_on_land_only and land_mask_processor != null and land_mask_processor.get_land_polygon_count() > 0:
			if balanced_island_distribution:
				site = land_mask_processor.get_random_land_point_balanced(rng)
			else:
				site = land_mask_processor.get_random_land_point(rng)
		else:
			site = Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			)

		if _site_exists_near(site, site_min_distance):
			continue
		
		var domain := CellData.DOMAIN_LAND
		var comp_id := 0
		
		if use_land_mask and land_mask_processor != null:
			domain = land_mask_processor.sample_domain(site)
			comp_id = land_mask_processor.find_component_for_point(site, domain)
		
		if domain == CellData.DOMAIN_WATER:
			if water_count >= max_water_cells:
				continue
			water_count += 1
		
		var cell := map_data.create_cell(site)
		site_index.insert(cell.id, site)
		cell.domain = domain
		cell.component_id = comp_id

		created += 1

	_rebuild_lookup_caches()
	print("Generated initial cells: ", map_data.cells.size(), " / ", count, " | tries=", tries)


func _site_exists_near(pos: Vector2, min_dist: float) -> bool:
	return site_index.has_point_within(pos, min_dist)


# =========================================================
# LOOKUP CACHE
# =========================================================

func _rebuild_lookup_caches() -> void:
	site_to_cell_id.clear()
	cell_id_to_site.clear()
	points.clear()
	site_index.clear()

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		site_to_cell_id[cell.site] = cell.id
		cell_id_to_site[cell.id] = cell.site
		points.append(cell.site)
		site_index.insert(cell.id, cell.site)


func _manager_key(domain: int, component_id: int) -> String:
	return "%d:%d" % [domain, component_id]


func _group_points_by_component() -> Dictionary:
	var groups := {}

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		var key := _manager_key(cell.domain, cell.component_id)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(cell.site)

	return groups


# =========================================================
# GEOMETRY REBUILD
# =========================================================

func rebuild_geometry_from_map_data() -> void:
	_rebuild_lookup_caches()
	component_managers.clear()
	cached_cells.clear()

	var grouped_points := _group_points_by_component()
	var start := Time.get_ticks_msec()
	var t_build := 0

	for key in grouped_points.keys():
		var pts: Array[Vector2] = []
		for p in grouped_points[key]:
			pts.append(p)

		var manager := DynamicDelaunayVoronoi.new(bounds)

		var split = key.split(":")
		var domain := int(split[0])
		var component_id := int(split[1])

		if use_land_mask and land_mask_processor != null and domain == CellData.DOMAIN_LAND:
			var component_poly := land_mask_processor.get_component_polygon(domain, component_id)
			if component_poly.size() >= 3:
				manager.set_base_polygon(component_poly)

		if pts.size() > 0:
			var tb := Time.get_ticks_msec()
			manager.build(pts, bounds)
			t_build += Time.get_ticks_msec() - tb

		component_managers[key] = manager

	var t1 := Time.get_ticks_msec()
	_rebuild_component_cached_cells()
	_sync_geometry_from_component_managers()
	var t_sync := Time.get_ticks_msec() - t1

	t1 = Time.get_ticks_msec()
	_rebuild_coastal_adjacency()
	var t_coastal := Time.get_ticks_msec() - t1

	var elapsed := Time.get_ticks_msec() - start
	print("Component geometry rebuild: ", elapsed, " ms | groups=", component_managers.size(),
		" | build=", t_build, "ms sync=", t_sync, "ms coastal=", t_coastal, "ms")
	chunk_render_layer.rebuild_all()
	_queue_water_redraw()
	update_layers()


## Grupuje niepokryte punkty (entries: [Vector2, komponent]) w klastry o danym
## promieniu; zwraca listę {comp, pts, centroid}.
func _cluster_entries(entries: Array, radius: float) -> Array:
	var clusters: Array = []
	for e in entries:
		var p: Vector2 = e[0]
		var comp: int = e[1]
		var found := false
		for cl in clusters:
			if cl.comp == comp and p.distance_to(cl.centroid) < radius:
				cl.pts.append(p)
				var c := Vector2.ZERO
				for qv: Vector2 in cl.pts:
					c += qv
				cl.centroid = c / cl.pts.size()
				found = true
				break
		if not found:
			clusters.append({comp = comp, pts = [p], centroid = p})
	return clusters


## Jak _cluster_entries, ale dla gołych punktów (bez komponentu).
func _cluster_points(points: Array, radius: float) -> Array:
	var clusters: Array = []
	for p in points:
		var pv: Vector2 = p
		var found := false
		for cl in clusters:
			if pv.distance_to(cl.centroid) < radius:
				cl.pts.append(pv)
				var c := Vector2.ZERO
				for qv: Vector2 in cl.pts:
					c += qv
				cl.centroid = c / cl.pts.size()
				found = true
				break
		if not found:
			clusters.append({pts = [pv], centroid = pv})
	return clusters


func _point_in_any_land_polygon(p: Vector2) -> bool:
	for lp in land_mask_processor.land_polygons:
		if lp.size() >= 3 and Geometry2D.is_point_in_polygon(p, lp):
			return true
	return false


## Łata "szczeliny" lądu: fragmenty maski lądu niepokryte przez ŻADNĄ komórkę
## lądową (cienkie cyple/przesmyki, w które nie trafił żaden site lądu — site
## wodny "wygrywa" Voronoi). Takie miejsca renderują się jak woda, nie da się
## ich kliknąć ani przypisać do regionu — w trybie administracyjnym robią
## charakterystyczne wcięcia w granicach regionów.
## Detekcja: sampling maski lądu (co land_sliver_stride px) i sprawdzenie,
## czy punkt pokrywa poligon którejś komórki LĄDOWEJ; dla niepokrytych
## punktów dodajemy site'y lądu i przebudowujemy geometrię.
## Zwraca liczbę dodanych komórek.
func _patch_land_slivers(max_passes: int = 3) -> int:
	if not use_land_mask or land_mask_processor == null:
		return 0
	var total := 0
	var failed: Array[Vector2] = []
	const STRIDE := 16.0
	const MAX_TOTAL := 200
	const G := 64.0
	# Promień klastra ~ typowy rozmiar lokalnej komórki: każda szczelina dostaje
	# JEDEN site wielkości sąsiednich komórek (a nie siatkę identycznych
	# kwadracików, jak przy stałym małym odstępie).
	var area_per_site: float = bounds.get_area() / max(float(map_data.cells.size()), 1.0)
	var cluster_radius: float = max(sqrt(area_per_site) * 0.9, 24.0)

	for _pass in range(max_passes):
		if total >= MAX_TOTAL:
			push_warning("Land sliver patch: osiągnięto limit %d nowych komórek" % MAX_TOTAL)
			break

		# Indeks bbox poligonów komórek lądu (pokrycie sprawdzamy tylko wobec nich).
		var grid := {}
		for cell_id in map_data.cells.keys():
			var cell: CellData = map_data.cells[cell_id]
			if cell.domain != CellData.DOMAIN_LAND or cell.polygon.size() < 3:
				continue
			var r := Rect2(cell.polygon[0], Vector2())
			for v in cell.polygon:
				r = r.expand(v)
			for gy in range(int(r.position.y / G), int(r.end.y / G) + 1):
				for gx in range(int(r.position.x / G), int(r.end.x / G) + 1):
					var k := Vector2i(gx, gy)
					if not grid.has(k):
						grid[k] = []
					grid[k].append(cell_id)

		# Sampling: punkty lądu, których nie pokrywa żadna komórka lądu.
		# Weryfikacja wobec POLIGONÓW maski (nie tylko bitmapy sample_domain —
		# na subpikselowych granicach bitmapa i poligon mogą się rozjechać,
		# a site poza poligonem komponentu dostaje po clipie pusty poligon).
		var raw: Array = []   # [punkt, komponent]
		var y := STRIDE * 0.5
		while y < bounds.size.y:
			var x := STRIDE * 0.5
			while x < bounds.size.x:
				var p := Vector2(x, y)
				if land_mask_processor.sample_domain(p) == CellData.DOMAIN_LAND:
					var covered := false
					for id in grid.get(Vector2i(int(x / G), int(y / G)), []):
						if Geometry2D.is_point_in_polygon(p, map_data.cells[id].polygon):
							covered = true
							break
					if not covered:
						for i in range(land_mask_processor.land_polygons.size()):
							var lp: PackedVector2Array = land_mask_processor.land_polygons[i]
							if lp.size() >= 3 and Geometry2D.is_point_in_polygon(p, lp):
								raw.append([p, i])
								break
				x += STRIDE
			y += STRIDE

		if raw.is_empty():
			break

		# Klastrujemy niepokryte punkty: JEDEN site na szczelinę (centroid
		# klastra; jeśli wypada poza poligon lądu — pierwszy punkt klastra
		# wewnątrz niego). Site wielkości lokalnych komórek wygląda naturalnie.
		var added: Array[Vector2] = []
		var added_comp: Array[int] = []
		for cl in _cluster_entries(raw, cluster_radius):
			if total >= MAX_TOTAL:
				break
			var lp: PackedVector2Array = land_mask_processor.land_polygons[cl.comp]
			var site := Vector2.ZERO
			var have_site := false
			if Geometry2D.is_point_in_polygon(cl.centroid, lp):
				site = cl.centroid
				have_site = true
			else:
				for qv: Vector2 in cl.pts:
					if Geometry2D.is_point_in_polygon(qv, lp):
						site = qv
						have_site = true
						break
			if not have_site:
				continue
			if site_index.has_point_within(site, 1.0):
				continue
			var too_close := false
			for q in failed:
				if site.distance_squared_to(q) < cluster_radius * cluster_radius:
					too_close = true
					break
			if too_close:
				continue
			added.append(site)
			added_comp.append(cl.comp)

		if added.is_empty():
			break

		for idx in range(added.size()):
			var new_cell := map_data.create_cell(added[idx])
			new_cell.domain = CellData.DOMAIN_LAND
			new_cell.component_id = added_comp[idx]
			new_cell.is_land = true
			new_cell.is_water = false
			new_cell.meta["sliver_patch"] = true
			total += 1

		# Pełna przebudowa nadpisuje poligony i przebudowuje cache.
		rebuild_geometry_from_map_data()

		# Sprzątanie: łatki, których poligon i tak został wycięty (pusty),
		# usuwamy — zostawiłyby martwe, nieklikalne komórki. Ich site'y
		# trafiają na blokadę, żeby następny pass nie dodał ich ponownie.
		var purge := 0
		for cell_id in map_data.cells.keys().duplicate():
			var c: CellData = map_data.cells[cell_id]
			if c.meta.get("sliver_patch", false) and c.polygon.size() < 3:
				failed.append(c.site)
				map_data.remove_cell(cell_id)
				purge += 1
		if purge > 0:
			total -= purge
			rebuild_geometry_from_map_data()

	# ── FAZA 2: dziury w teselacji po stronie Wody ──
	# Komórki lądowe są przycinane do poligonu lądu; obszar maski-wody, do którego
	# nie sięga żaden site wody, nie należy więc do ŻADNEJ komórki (nieklikalne
	# "nic", dziura w renderze wody i wcięcia granic przy wybrzeżu — typowe
	# w zapisach po edycjach). Dodajemy site'y wody w takich miejscach.
	# Dwa przebiegi: siatka 16px (duże dziury), potem 8px (mikro-dziury przy
	# wybrzeżu, którymi zajmujemy się dopiero po zbudowaniu grobli z passu 1).
	var wstrides: Array[float] = [16.0, 8.0]
	var wstride_idx := 0
	while wstride_idx < wstrides.size():
		var wstride: float = wstrides[wstride_idx]
		wstride_idx += 1
		if total >= MAX_TOTAL:
			break

		var grid_all := {}
		for cell_id in map_data.cells.keys():
			var cell: CellData = map_data.cells[cell_id]
			if cell.polygon.size() < 3:
				continue
			var rb := Rect2(cell.polygon[0], Vector2())
			for v in cell.polygon:
				rb = rb.expand(v)
			for gy in range(int(rb.position.y / G), int(rb.end.y / G) + 1):
				for gx in range(int(rb.position.x / G), int(rb.end.x / G) + 1):
					var kk := Vector2i(gx, gy)
					if not grid_all.has(kk):
						grid_all[kk] = []
					grid_all[kk].append(cell_id)

		var wraw: Array = []
		var wy := wstride * 0.5
		while wy < bounds.size.y:
			var wx := wstride * 0.5
			while wx < bounds.size.x:
				var p := Vector2(wx, wy)
				var dom := land_mask_processor.sample_domain(p)
				# "Ziemia niczyja": punkt niepokryty przez ŻADNĄ komórkę. Site lądu
				# ma sens tylko wewnątrz poligonu lądu (inaczej clip go wyzeruje);
				# poza nim (rozjazd bitmapy i poligonów na wybrzeżu) dziurę łacze
				# site'em WODY — woda nie jest przycinana, a ląd rysuje się i tak
				# na wierzchu, więc takie wypełnienie jest zawsze bezpieczne.
				if dom == CellData.DOMAIN_WATER or not _point_in_any_land_polygon(p):
					var covered := false
					for id in grid_all.get(Vector2i(int(wx / G), int(wy / G)), []):
						if Geometry2D.is_point_in_polygon(p, map_data.cells[id].polygon):
							covered = true
							break
					if not covered:
						wraw.append(p)
				wx += wstride
			wy += wstride

		if wraw.is_empty():
			continue   # spróbuj drobniejszej siatki (ostatni pass zakończy pętlę)

		# Jeden site (centroid klastra) na dziurę — komórka wypełnia całą
		# dziurę organicznie, rozmiarem zgodna z sąsiedztwem.
		var wadded: Array[Vector2] = []
		for cl in _cluster_points(wraw, cluster_radius):
			if total >= MAX_TOTAL:
				break
			var site: Vector2 = cl.centroid
			if site_index.has_point_within(site, 1.0):
				continue
			var too_close := false
			for q in failed:
				if site.distance_squared_to(q) < cluster_radius * cluster_radius:
					too_close = true
					break
			if too_close:
				continue
			wadded.append(site)

		if wadded.is_empty():
			continue

		for site in wadded:
			var new_cell := map_data.create_cell(site)
			new_cell.domain = CellData.DOMAIN_WATER
			new_cell.component_id = land_mask_processor.find_component_for_point(site, CellData.DOMAIN_WATER)
			new_cell.is_land = false
			new_cell.is_water = true
			new_cell.meta["sliver_patch"] = true
			total += 1

		rebuild_geometry_from_map_data()

		var wpurge := 0
		for cell_id in map_data.cells.keys().duplicate():
			var c: CellData = map_data.cells[cell_id]
			if c.meta.get("sliver_patch", false) and c.polygon.size() < 3:
				failed.append(c.site)
				map_data.remove_cell(cell_id)
				wpurge += 1
		if wpurge > 0:
			total -= wpurge
			rebuild_geometry_from_map_data()

	if total > 0:
		print("Land sliver patch: dodano komórek (ląd+woda): ", total)
	return total


func _rebuild_component_cached_cells() -> void:
	cached_cells.clear()

	for key in component_managers.keys():
		var manager: DynamicDelaunayVoronoi = component_managers[key]
		var cells = manager.get_cells()
		for site in cells.keys():
			cached_cells[site] = cells[site]


func _sync_geometry_from_component_managers() -> void:
	for cell_id in map_data.cells.keys():
		_sync_single_cell(map_data.cells[cell_id])


## Synchronizuje wyłącznie komórki dotknięte ostatnią operacją w danym managerze
## (zamiast pełnego przejazdu po wszystkich komórkach z przycinaniem polygonów).
func _sync_cells_for_sites(manager: DynamicDelaunayVoronoi, sites_to_sync: Array) -> void:
	for s in sites_to_sync:
		if manager.sites.has(s):
			cached_cells[s] = [manager.sites[s], manager.neighbors.get(s, [])]
		else:
			cached_cells.erase(s)

	for s in sites_to_sync:
		if not site_to_cell_id.has(s):
			continue
		var cell: CellData = map_data.cells[site_to_cell_id[s]]
		_sync_single_cell(cell)


func _sync_single_cell(cell: CellData) -> void:
	cell.polygon = PackedVector2Array()
	cell.neighbor_ids.clear()
	# UWAGA: NIE czyścimy tu coastal_neighbor_ids — inkrementalna aktualizacja
	# wybrzeża (_update_coastal_for_cells) sama rozłącza dotknięte komórki
	# obustronnie; czyszczenie w tym miejscu zostawiałoby partnerom wiszące
	# referencje (asymetria linków).
	cell.is_land = cell.domain == CellData.DOMAIN_LAND
	cell.is_water = cell.domain == CellData.DOMAIN_WATER
	cell.is_coastal_clipped = false
	cell.is_coastal = false

	var site := cell.site

	if not cached_cells.has(site):
		return

	var original_poly: PackedVector2Array = cached_cells[site][0]
	var neigh_sites: Array = cached_cells[site][1]

	var final_poly := original_poly

	if use_land_mask and land_mask_processor != null and cell.domain == CellData.DOMAIN_LAND:
		final_poly = land_mask_processor.clip_polygon_to_component(
			original_poly,
			cell.site,
			cell.domain,
			cell.component_id
		)

		var info := land_mask_processor.classify_cell(
			site,
			original_poly,
			final_poly,
			cell.domain
		)
		cell.is_land = info["is_land"]
		cell.is_water = info["is_water"]
		cell.is_coastal_clipped = info["is_coastal"]
		cell.is_coastal = info["is_coastal"]

	cell.polygon = final_poly

	var neigh_ids: Array[int] = []
	for neigh_site in neigh_sites:
		if site_to_cell_id.has(neigh_site):
			var neigh_id: int = site_to_cell_id[neigh_site]
			if map_data.cells.has(neigh_id):
				var neigh_cell: CellData = map_data.cells[neigh_id]
				if neigh_cell.domain == cell.domain and neigh_cell.component_id == cell.component_id:
					neigh_ids.append(neigh_id)

	cell.neighbor_ids = neigh_ids


func _rebuild_coastal_adjacency() -> void:
	water_grid.clear()
	land_grid.clear()
	water_grid_cells.clear()
	land_grid_cells.clear()

	# Reset połączeń. Flaga wynikowa = clip do maski (is_coastal_clipped) LUB dotyk z wodą.
	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		cell.coastal_neighbor_ids.clear()
		cell.is_coastal = cell.is_coastal_clipped

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		if cell.polygon.size() < 2:
			continue
		if cell.domain == CellData.DOMAIN_WATER:
			_coastal_grid_insert(water_grid, water_grid_cells, cell)
		else:
			_coastal_grid_insert(land_grid, land_grid_cells, cell)

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		if cell.domain != CellData.DOMAIN_LAND or cell.polygon.size() < 2:
			continue
		for water_id in _coastal_grid_query(water_grid, _polygon_bounds(cell.polygon)):
			_try_coastal_link(cell, map_data.cells[water_id])


## Inkrementalna aktualizacja połączeń przybrzeżnych dla dotkniętych komórek —
## zamiast pełnego rebuildu O(n) przy każdej operacji edycyjnej.
## removed_coastal: cell_id -> Array[int] (dawni partnerzy) dla komórek już usuniętych.
func _update_coastal_for_cells(cell_ids: Array, removed_coastal: Dictionary = {}) -> void:
	# dedupe identyfikatorów (ten sam site może przyjść z dwóch managerów)
	var unique := {}
	for id in cell_ids:
		unique[id] = true
	cell_ids = unique.keys()

	# 1. Sprzątnij powiązania wsteczne usuniętych komórek.
	for rid in removed_coastal.keys():
		_coastal_grid_remove(water_grid, water_grid_cells, rid)
		_coastal_grid_remove(land_grid, land_grid_cells, rid)
		for pid in removed_coastal[rid]:
			var partner: CellData = map_data.cells.get(pid, null)
			if partner != null:
				partner.coastal_neighbor_ids.erase(rid)
				partner.is_coastal = partner.is_coastal_clipped or not partner.coastal_neighbor_ids.is_empty()

	# 2. Odepnij dotknięte komórki (obustronnie) i wysuń je z obu siatek.
	for id in cell_ids:
		var cell: CellData = map_data.cells.get(id, null)
		if cell == null:
			continue
		for pid in cell.coastal_neighbor_ids:
			var partner: CellData = map_data.cells.get(pid, null)
			if partner != null:
				partner.coastal_neighbor_ids.erase(id)
				partner.is_coastal = partner.is_coastal_clipped or not partner.coastal_neighbor_ids.is_empty()
		cell.coastal_neighbor_ids.clear()
		cell.is_coastal = cell.is_coastal_clipped
		_coastal_grid_remove(water_grid, water_grid_cells, id)
		_coastal_grid_remove(land_grid, land_grid_cells, id)

	# 3. Włóż dotknięte komórki z powrotem do odpowiednich siatek.
	for id in cell_ids:
		var cell: CellData = map_data.cells.get(id, null)
		if cell == null or cell.polygon.size() < 2:
			continue
		if cell.domain == CellData.DOMAIN_WATER:
			_coastal_grid_insert(water_grid, water_grid_cells, cell)
		else:
			_coastal_grid_insert(land_grid, land_grid_cells, cell)

	# 4. Linkuj na nowo (dedupe w _try_coastal_link).
	for id in cell_ids:
		var cell: CellData = map_data.cells.get(id, null)
		if cell == null or cell.polygon.size() < 2:
			continue
		var rect := _polygon_bounds(cell.polygon)
		if cell.domain == CellData.DOMAIN_LAND:
			for water_id in _coastal_grid_query(water_grid, rect):
				_try_coastal_link(cell, map_data.cells[water_id])
		else:
			for land_id in _coastal_grid_query(land_grid, rect):
				_try_coastal_link(map_data.cells[land_id], cell)


func _try_coastal_link(land_cell: CellData, water_cell: CellData) -> void:
	if _polygons_touch(land_cell.polygon, water_cell.polygon, coastal_epsilon):
		if water_cell.id not in land_cell.coastal_neighbor_ids:
			land_cell.coastal_neighbor_ids.append(water_cell.id)
		if land_cell.id not in water_cell.coastal_neighbor_ids:
			water_cell.coastal_neighbor_ids.append(land_cell.id)
		land_cell.is_coastal = true
		water_cell.is_coastal = true


func _cell_ids_for_sites(sites_list: Array) -> Array:
	var out: Array = []
	for s in sites_list:
		if site_to_cell_id.has(s):
			out.append(site_to_cell_id[s])
	return out


func _coastal_grid_insert(grid: Dictionary, cells_map: Dictionary, cell: CellData) -> void:
	# idempotentność: bez tego duplikat w kubełku przetrwałby remove (erase zdejmuje
	# tylko pierwsze wystąpienie) i generował stale linki
	if cells_map.has(cell.id):
		_coastal_grid_remove(grid, cells_map, cell.id)

	var rect := _polygon_bounds(cell.polygon).grow(coastal_epsilon)
	var bs := coastal_grid_size
	var keys: Array = []
	var x0 := floori(rect.position.x / bs)
	var y0 := floori(rect.position.y / bs)
	var x1 := floori(rect.end.x / bs)
	var y1 := floori(rect.end.y / bs)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var key := Vector2i(gx, gy)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(cell.id)
			keys.append(key)
	cells_map[cell.id] = keys


func _coastal_grid_remove(grid: Dictionary, cells_map: Dictionary, cell_id: int) -> void:
	var keys: Array = cells_map.get(cell_id, [])
	for k in keys:
		if grid.has(k):
			grid[k].erase(cell_id)
			if (grid[k] as Array).is_empty():
				grid.erase(k)
	cells_map.erase(cell_id)


func _coastal_grid_query(grid: Dictionary, rect: Rect2) -> Array:
	var grown := rect.grow(coastal_epsilon)
	var bs := coastal_grid_size
	var x0 := floori(grown.position.x / bs)
	var y0 := floori(grown.position.y / bs)
	var x1 := floori(grown.end.x / bs)
	var y1 := floori(grown.end.y / bs)
	var out: Array = []
	var seen := {}
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var key := Vector2i(gx, gy)
			if not grid.has(key):
				continue
			for id in grid[key]:
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


func _polygons_touch(poly_a: PackedVector2Array, poly_b: PackedVector2Array, eps: float) -> bool:
	if poly_a.size() < 2 or poly_b.size() < 2:
		return false

	var rect_a := _polygon_bounds(poly_a).grow(eps)
	var rect_b := _polygon_bounds(poly_b).grow(eps)
	if not rect_a.intersects(rect_b):
		return false

	for i in range(poly_a.size()):
		var a1 := poly_a[i]
		var a2 := poly_a[(i + 1) % poly_a.size()]

		for j in range(poly_b.size()):
			var b1 := poly_b[j]
			var b2 := poly_b[(j + 1) % poly_b.size()]

			if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
				return true

			if _point_segment_distance_squared(a1, b1, b2) <= eps * eps:
				return true
			if _point_segment_distance_squared(a2, b1, b2) <= eps * eps:
				return true
			if _point_segment_distance_squared(b1, a1, a2) <= eps * eps:
				return true
			if _point_segment_distance_squared(b2, a1, a2) <= eps * eps:
				return true

	return false


func _polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect


func _point_segment_distance_squared(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sqr := ab.length_squared()
	if ab_len_sqr <= 0.000001:
		return p.distance_squared_to(a)

	var t = clamp((p - a).dot(ab) / ab_len_sqr, 0.0, 1.0)
	var q = a + ab * t
	return p.distance_squared_to(q)


# =========================================================
# SAVE / LOAD
# =========================================================

func save_map(path: String = save_path, file_name: String = save_name) -> void:
	var dir_path: String = path + file_name
	# Katalog mapy (i ewentualne rodzice) muszą istnieć przed zapisem —
	# DirAccess.open() na nieistniejącej ścieżce zwraca null (crash przy
	# pierwszym zapisie na świeżym klonie repo).
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("save_map: nie można utworzyć katalogu mapy: " + dir_path)
		return
	path = dir.get_current_dir() + "/"
	
	var t_save := Time.get_ticks_msec()
	var ok := MapSerializer.save_to_binary(path + Global.map_bin_file, map_data)
	var save_ms := Time.get_ticks_msec() - t_save
	
	if use_land_mask:
		var image_file = FileAccess.open(path + Global.land_mask_file, FileAccess.WRITE)
		image_file.store_buffer(land_mask_processor.image.save_png_to_buffer())
		image_file.close()
	
	if use_border_mask:
		var image_file = FileAccess.open(path + Global.border_mask_file, FileAccess.WRITE)
		image_file.store_buffer(border_mask_processor.image.save_png_to_buffer())
		image_file.close()
		
	var settings_file = FileAccess.open(path + Global.settings_file, FileAccess.WRITE)
	var settings_dict = {
		"height": map_height,
		"width": map_width,
		"save_name": save_name,
		"use_land_mask": use_land_mask,
		"use_border_mask": use_border_mask,
		"map_render_scale": map_render_scale,
		"effective_width": effective_width,
		"effective_height": effective_height
	}
	settings_file.store_string(JSON.stringify(settings_dict, "\t"))
	settings_file.close()
	
	var bin_size := 0
	if ok:
		bin_size = FileAccess.get_file_as_bytes(path + Global.map_bin_file).size()
	print("Save map: ", ok, " | ", path, " | bin=", bin_size, "B in ", save_ms, "ms")


func load_map(path: String = save_path, _file_name: String = save_name) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open dir: " + path)
		return
	
	var settings_path := dir.get_current_dir() + "/" + Global.settings_file
	var settings_file := FileAccess.open(settings_path, FileAccess.READ)
	if settings_file == null:
		push_error("Cannot open settings file: " + settings_path)
		return
	
	var json_file = JSON.parse_string(settings_file.get_as_text())
	settings_file.close()
	
	if typeof(json_file) != TYPE_DICTIONARY:
		push_error("Invalid settings JSON")
		return
	
	map_height = int(json_file["height"])
	map_width = int(json_file["width"])
	use_land_mask = json_file["use_land_mask"]
	use_border_mask = json_file["use_border_mask"]
	map_render_scale = float(json_file.get("map_render_scale", 1.0))
	save_name = json_file["save_name"]
	
	land_mask_processor = null
	border_mask_processor = null
	
	var implied_eff_w := int(map_width * map_render_scale)
	var implied_eff_h := int(map_height * map_render_scale)
	# Poligony w zapisie żyją w przestrzeni EFECTIVE z momentu zapisu — przy rozjazdzie
	# z obecnymi ustawieniami zaufanie ma zapis (inaczej maski/geometria by się rozjeżdżały).
	effective_width = int(json_file.get("effective_width", implied_eff_w))
	effective_height = int(json_file.get("effective_height", implied_eff_h))
	if effective_width != implied_eff_w or effective_height != implied_eff_h:
		push_warning("Map.load_map: zapis ma effective %dx%d, a obecne ustawienia dają %dx%d "
			% [effective_width, effective_height, implied_eff_w, implied_eff_h]
			+ "— używam wymiarów ZAPISU (polygonie nie zostaną rozjeżdżone).")
	bounds = Rect2(0, 0, effective_width, effective_height)
	
	if use_land_mask:
		var image_path := dir.get_current_dir() + "/" + Global.land_mask_file
		var image_file := FileAccess.open(image_path, FileAccess.READ)
		if image_file != null:
			var image := Image.new()
			var err := image.load_png_from_buffer(image_file.get_buffer(image_file.get_length()))
			image_file.close()
			
			if err == OK:
				land_mask_processor = LandMaskProcessor.new()
				var ok := land_mask_processor.load_mask_from_image(
					image,
					Vector2i(effective_width, effective_height),
					land_threshold,
					black_is_land
				)
				print("Land mask loaded: ", ok, " | land comps=", land_mask_processor.land_polygons.size())
	
	if use_border_mask:
		var image_path := dir.get_current_dir() + "/" + Global.border_mask_file
		var image_file := FileAccess.open(image_path, FileAccess.READ)
		if image_file != null:
			var image := Image.new()
			var err := image.load_png_from_buffer(image_file.get_buffer(image_file.get_length()))
			image_file.close()
			
			if err == OK:
				border_mask_processor = BorderMaskProcessor.new()
				var ok := border_mask_processor.load_border_mask_from_image(
					image,
					Vector2i(effective_width, effective_height),
					border_threshold,
					border_spacing
				)
				print("Border mask loaded: ", ok, " | points=", border_mask_processor.border_points.size())
	
	var bin_path := dir.get_current_dir() + "/" + Global.map_bin_file
	var loaded := MapSerializer.load_from_binary(bin_path)
	if loaded == null:
		push_error("Brak lub uszkodzony plik binarny mapy: " + bin_path)
		return
	
	map_data = loaded
	#bounds = map_data.bounds
	
	if not is_active:
		is_active = true
	
	setup_layers()
	rebuild_geometry_from_map_data()
	if patch_land_slivers:
		_patch_land_slivers()
	
	selected_cell_id = -1
	selected_region_id = -1
	
	print("Map loaded: ", dir.get_current_dir())
	update_layers()
	initialized.emit()


# =========================================================
# CELL OPERATIONS
# =========================================================

func add_point_at(pos: Vector2) -> void:
	if not bounds.has_point(pos):
		return

	if site_to_cell_id.has(pos):
		return

	var domain := CellData.DOMAIN_LAND
	var component_id := 0

	if use_land_mask and land_mask_processor != null:
		domain = land_mask_processor.sample_domain(pos)
		component_id = land_mask_processor.find_component_for_point(pos, domain)

		if domain == CellData.DOMAIN_WATER and not allow_manual_points_on_water:
			return

	var key := _manager_key(domain, component_id)
	if not component_managers.has(key):
		var new_manager := DynamicDelaunayVoronoi.new(bounds)
		if use_land_mask and land_mask_processor != null and domain == CellData.DOMAIN_LAND:
			var component_poly := land_mask_processor.get_component_polygon(domain, component_id)
			if component_poly.size() >= 3:
				new_manager.set_base_polygon(component_poly)
		component_managers[key] = new_manager

	var target_manager: DynamicDelaunayVoronoi = component_managers[key]

	var start := Time.get_ticks_msec()
	var ok := target_manager.add_point(pos)
	var t_manager := Time.get_ticks_msec() - start
	var t_sync := 0
	var t_coastal := 0
	var t_chunks := 0
	if ok:
		var cell := map_data.create_cell(pos)
		cell.domain = domain
		cell.component_id = component_id

		var t := Time.get_ticks_msec()
		_rebuild_lookup_caches()
		_sync_cells_for_sites(target_manager, target_manager.last_affected_sites)
		t_sync = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		var affected_ids := _cell_ids_for_sites(target_manager.last_affected_sites)
		affected_ids.append(cell.id)
		_update_coastal_for_cells(affected_ids)
		t_coastal = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		var affected := _get_affected_cell_ids_from_cached(pos)
		if cell.id not in affected:
			affected.append(cell.id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
		_queue_water_redraw()
		t_chunks = Time.get_ticks_msec() - t

	var elapsed := Time.get_ticks_msec() - start
	print("Add point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
	if profile_ops:
		print("  [split] manager=%dms sync=%dms coastal=%dms chunks=%dms" % [t_manager, t_sync, t_coastal, t_chunks])
	update_layers()


func remove_point_at(pos: Vector2) -> void:
	var nearest_cell_id := find_nearest_cell_id(pos, remove_radius)
	if nearest_cell_id == -1:
		return
	
	if not map_data.cells.has(nearest_cell_id):
		return
	
	var cell: CellData = map_data.cells[nearest_cell_id]
	var key := _manager_key(cell.domain, cell.component_id)
	if not component_managers.has(key):
		return
	
	var affected: Array = cell.neighbor_ids.duplicate()
	affected.append_array(cell.coastal_neighbor_ids)
	var victim_coastal: Array = cell.coastal_neighbor_ids.duplicate()

	var target_manager: DynamicDelaunayVoronoi = component_managers[key]

	var start := Time.get_ticks_msec()
	var ok := target_manager.remove_point(cell.site)
	var t_manager := Time.get_ticks_msec() - start
	var t_sync := 0
	var t_coastal := 0
	var t_chunks := 0
	if ok:
		map_data.remove_cell(nearest_cell_id)
		if selected_cell_id == nearest_cell_id:
			selected_cell_id = -1

		var t := Time.get_ticks_msec()
		_rebuild_lookup_caches()
		_sync_cells_for_sites(target_manager, target_manager.last_affected_sites)
		t_sync = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		var rm_touched_ids := _cell_ids_for_sites(target_manager.last_affected_sites)
		_update_coastal_for_cells(rm_touched_ids, {nearest_cell_id: victim_coastal})
		t_coastal = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		chunk_render_layer.remove_cell(nearest_cell_id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
		_queue_water_redraw()
		t_chunks = Time.get_ticks_msec() - t

	var elapsed := Time.get_ticks_msec() - start
	print("Remove point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
	if profile_ops:
		print("  [split] manager=%dms sync=%dms coastal=%dms chunks=%dms" % [t_manager, t_sync, t_coastal, t_chunks])
	update_layers()


func move_nearest_point_to(pos: Vector2) -> void:
	var nearest_cell_id := find_nearest_cell_id(pos, remove_radius)
	if nearest_cell_id == -1:
		return

	if not map_data.cells.has(nearest_cell_id):
		return

	if not bounds.has_point(pos):
		return

	if site_to_cell_id.has(pos):
		return

	var cell: CellData = map_data.cells[nearest_cell_id]
	var old_site := cell.site
	var old_key := _manager_key(cell.domain, cell.component_id)

	var new_domain := cell.domain
	var new_component_id := cell.component_id

	if use_land_mask and land_mask_processor != null:
		new_domain = land_mask_processor.sample_domain(pos)
		new_component_id = land_mask_processor.find_component_for_point(pos, new_domain)

	var new_key := _manager_key(new_domain, new_component_id)

	var start := Time.get_ticks_msec()
	var ok := false
	var managers_to_sync: Array = []
	var t_manager := 0
	var t_sync := 0
	var t_coastal := 0
	var t_chunks := 0

	if old_key == new_key:
		var target_manager: DynamicDelaunayVoronoi = component_managers[old_key]
		ok = target_manager.move_point(old_site, pos)
		if ok:
			managers_to_sync.append(target_manager)
	else:
		var old_manager: DynamicDelaunayVoronoi = component_managers[old_key]

		if not component_managers.has(new_key):
			var created_manager := DynamicDelaunayVoronoi.new(bounds)
			if use_land_mask and land_mask_processor != null and new_domain == CellData.DOMAIN_LAND:
				var component_poly := land_mask_processor.get_component_polygon(new_domain, new_component_id)
				if component_poly.size() >= 3:
					created_manager.set_base_polygon(component_poly)
			component_managers[new_key] = created_manager

		var new_manager: DynamicDelaunayVoronoi = component_managers[new_key]

		var removed := old_manager.remove_point(old_site)
		if removed:
			managers_to_sync.append(old_manager)
			ok = new_manager.add_point(pos)
			if ok:
				managers_to_sync.append(new_manager)

	t_manager = Time.get_ticks_msec() - start

	if ok:
		cell.site = pos
		cell.domain = new_domain
		cell.component_id = new_component_id

		var t := Time.get_ticks_msec()
		_rebuild_lookup_caches()
		for m in managers_to_sync:
			_sync_cells_for_sites(m, m.last_affected_sites)
		t_sync = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		var mv_touched_ids := []
		for m in managers_to_sync:
			mv_touched_ids.append_array(_cell_ids_for_sites(m.last_affected_sites))
		mv_touched_ids.append(nearest_cell_id)
		_update_coastal_for_cells(mv_touched_ids)
		t_coastal = Time.get_ticks_msec() - t

		t = Time.get_ticks_msec()
		var affected := _get_affected_cell_ids_from_cached(pos)
		if nearest_cell_id not in affected:
			affected.append(nearest_cell_id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
		_queue_water_redraw()
		t_chunks = Time.get_ticks_msec() - t

		selected_cell_id = nearest_cell_id

	var elapsed := Time.get_ticks_msec() - start
	print("Move point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
	if profile_ops:
		print("  [split] manager=%dms sync=%dms coastal=%dms chunks=%dms" % [t_manager, t_sync, t_coastal, t_chunks])
	update_layers()


func set_cell_domain(cell_id: int, new_domain: int) -> bool:
	if not map_data.cells.has(cell_id):
		return false

	if new_domain != CellData.DOMAIN_LAND and new_domain != CellData.DOMAIN_WATER:
		return false

	var cell: CellData = map_data.cells[cell_id]
	var new_component_id := cell.component_id

	if use_land_mask and land_mask_processor != null:
		new_component_id = land_mask_processor.find_component_for_point(cell.site, new_domain)

	var old_key := _manager_key(cell.domain, cell.component_id)
	var new_key := _manager_key(new_domain, new_component_id)

	if old_key == new_key:
		cell.domain = new_domain
		cell.component_id = new_component_id
		rebuild_geometry_from_map_data()
		return true

	if not component_managers.has(old_key):
		return false

	var old_manager: DynamicDelaunayVoronoi = component_managers[old_key]

	if not component_managers.has(new_key):
		var created_manager := DynamicDelaunayVoronoi.new(bounds)
		if use_land_mask and land_mask_processor != null and new_domain == CellData.DOMAIN_LAND:
			var component_poly := land_mask_processor.get_component_polygon(new_domain, new_component_id)
			if component_poly.size() >= 3:
				created_manager.set_base_polygon(component_poly)
		component_managers[new_key] = created_manager

	var new_manager: DynamicDelaunayVoronoi = component_managers[new_key]

	var removed := old_manager.remove_point(cell.site)
	if not removed:
		return false

	var added := new_manager.add_point(cell.site)
	if not added:
		old_manager.add_point(cell.site)
		return false

	cell.domain = new_domain
	cell.component_id = new_component_id

	_rebuild_lookup_caches()
	_sync_cells_for_sites(old_manager, old_manager.last_affected_sites)
	_sync_cells_for_sites(new_manager, new_manager.last_affected_sites)
	var domain_touched_ids := _cell_ids_for_sites(old_manager.last_affected_sites)
	domain_touched_ids.append_array(_cell_ids_for_sites(new_manager.last_affected_sites))
	domain_touched_ids.append(cell_id)
	_update_coastal_for_cells(domain_touched_ids)

	var affected: Array = [cell_id]
	if map_data.cells.has(cell_id):
		affected.append_array(map_data.cells[cell_id].neighbor_ids)
		affected.append_array(map_data.cells[cell_id].coastal_neighbor_ids)
	chunk_render_layer.refresh_chunks_for_cells(affected)
	_queue_water_redraw()
	update_layers()
	
	return true


func make_cell_land(cell_id: int) -> bool:
	return set_cell_domain(cell_id, CellData.DOMAIN_LAND)


func make_cell_water(cell_id: int) -> bool:
	return set_cell_domain(cell_id, CellData.DOMAIN_WATER)


func clear_all_points() -> void:
	map_data.clear()
	cached_cells.clear()
	points.clear()
	site_to_cell_id.clear()
	cell_id_to_site.clear()
	component_managers.clear()
	selected_cell_id = -1
	selected_region_id = -1
	
	chunk_render_layer.rebuild_all()
	_queue_water_redraw()
	update_layers()

func _get_affected_cell_ids_from_cached(site: Vector2) -> Array:
	var affected: Array = []
	
	if not site_to_cell_id.has(site):
		return affected
	
	var cell_id: int = site_to_cell_id[site]
	affected.append(cell_id)
	
	if map_data.cells.has(cell_id):
		var cell: CellData = map_data.cells[cell_id]
		affected.append_array(cell.neighbor_ids)
		affected.append_array(cell.coastal_neighbor_ids)
	
	return affected

# =========================================================
# FIND / SELECT
# =========================================================

func find_nearest_cell_id(pos: Vector2, max_dist: float = INF) -> int:
	if max_dist == INF:
		# rzadka ścieżka bez ograniczenia zasięgu — pełny skan
		var best_id := -1
		var best_d := INF
		for cell_id in map_data.cells.keys():
			var cell: CellData = map_data.cells[cell_id]
			var d := cell.site.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best_id = cell_id
		return best_id

	var found = site_index.find_nearest_within(pos, max_dist)
	return -1 if found == null else int(found)


func find_cell_id_at_position(pos: Vector2) -> int:
	if chunk_render_layer:
		return chunk_render_layer.pick_cell_at(pos)
	return -1


# =========================================================
# REGIONS
# =========================================================

func create_region_for_selected_cell(cells: Array[int], r_name: String, level: int, parent: int, red: float, green: float, blue: float) -> void:
	if cells.is_empty():
		return

	var region := map_data.create_region(r_name, level, parent, red, green, blue)
	for cell in cells:
		map_data.assign_cell_to_region(cell, region.id)
	update_layers()


func assign_selected_cell_to_selected_region() -> void:
	if selected_cell_id == -1 or selected_region_id == -1:
		return

	map_data.assign_cell_to_region(selected_cell_id, selected_region_id)
	update_layers()


func select_next_region() -> void:
	var ids := map_data.regions.keys()
	if ids.is_empty():
		selected_region_id = -1
		return

	ids.sort()
	if selected_region_id == -1:
		selected_region_id = ids[0]
	else:
		var idx := ids.find(selected_region_id)
		if idx == -1 or idx >= ids.size() - 1:
			selected_region_id = ids[0]
		else:
			selected_region_id = ids[idx + 1]

	update_layers()

# =========================================================
# INPUT
# =========================================================

func _input(event: InputEvent) -> void:
	if is_active:
		if event is InputEventMouseMotion:
			var pos := get_local_mouse_position()
			var cell_id := find_cell_id_at_position(pos)
			
			if cell_id != -1:
				if not highlight_water_cells and map_data.cells.has(cell_id):
					var cell: CellData = map_data.cells[cell_id]
					if cell.domain == CellData.DOMAIN_WATER:
						highlight_layer.clear_highlight()
						return
				
				highlight_layer.set_highlighted([cell_id])
			else:
				highlight_layer.clear_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				rebuild_geometry_from_map_data()
			KEY_C:
				clear_all_points()
			KEY_G:
				_generate_initial_cells(initial_points_count)
				rebuild_geometry_from_map_data()
			KEY_S:
				save_map()
			KEY_L:
				load_map()
			KEY_N:
				draw_neighbors = !draw_neighbors
				update_layers()
			KEY_T:
				draw_triangulation = !draw_triangulation
				update_layers()
			KEY_P:
				draw_points = !draw_points
				update_layers()
			KEY_V:
				draw_cells = !draw_cells
				update_layers()
			KEY_B:
				draw_region_fill = !draw_region_fill
				update_layers()
			KEY_K:
				draw_coastal_links = !draw_coastal_links
				update_layers()
			KEY_O:
				draw_land_mask_outline = !draw_land_mask_outline
				update_layers()
			#KEY_E:
				#create_region_for_selected_cell()
			KEY_Q:
				select_next_region()
			KEY_A:
				assign_selected_cell_to_selected_region()
			KEY_D:
				chunk_draw_mode = (chunk_draw_mode + 1) % 4
				_apply_chunk_draw_mode()
				print("Draw mode: ", chunk_draw_mode)
			KEY_W:
				highlight_water_cells = !highlight_water_cells
				print("Highlight water: ", highlight_water_cells)


# =========================================================
# HELPERS USED BY LAYERS
# =========================================================

func is_polygon_drawable(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false

	var area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y

	return abs(area * 0.5) > 0.001


func color_from_id(id: int, alpha: float = 1.0) -> Color:
	var h := fmod(abs(float(id) * 0.381966011), 1.0)
	return Color.from_hsv(h, 0.55, 0.85, alpha)

# =========================================================
# DEBUG MASK VIS
# =========================================================

func debug_spawn_mask_polygons(show_land: bool = true, _show_water: bool = true) -> void:
	var old := get_node_or_null("MaskDebug")
	if old:
		old.queue_free()

	var container := Node2D.new()
	container.name = "MaskDebug"
	add_child(container)

	if land_mask_processor == null:
		return

	if show_land:
		for i in range(land_mask_processor.land_polygons.size()):
			var poly: PackedVector2Array = land_mask_processor.land_polygons[i]
			if poly.size() < 3:
				continue

			var p2d := Polygon2D.new()
			p2d.name = "LandPoly_%d" % i
			p2d.polygon = poly
			p2d.color = Color(0.1, 1.0, 0.1, 0.25)
			container.add_child(p2d)

			var line := Line2D.new()
			line.name = "LandOutline_%d" % i
			line.width = 2.0
			line.default_color = Color(0.0, 0.8, 0.0, 1.0)
			for p in poly:
				line.add_point(p)
			line.add_point(poly[0])
			container.add_child(line)


func debug_clear_mask_polygons() -> void:
	var old := get_node_or_null("MaskDebug")
	if old:
		old.queue_free()

func highlight_region(region_id: int) -> void:
	if not map_data.regions.has(region_id):
		return
	
	var region: RegionData = map_data.regions[region_id]
	highlight_layer.set_highlighted(region.cell_ids)

func _apply_chunk_draw_mode() -> void:
	if chunk_render_layer == null:
		return
	
	# W trybie LAND_OVER_WATER wodę rysuje warstwa globalna pod chunkami
	# (WaterBackLayer), a chunki malują wyłącznie ląd — dzięki temu kolejność
	# woda->ląd obowiązuje też między chunkami, nie tylko wewnątrz _draw().
	var water_under: bool = chunk_draw_mode == MapChunk.DrawMode.LAND_OVER_WATER
	if water_back_layer:
		water_back_layer.visible = water_under
		water_back_layer.queue_redraw()
	
	for key in chunk_render_layer.chunks.keys():
		var chunk: MapChunk = chunk_render_layer.chunks[key]
		chunk.draw_mode = MapChunk.DrawMode.LAND_ONLY if water_under else chunk_draw_mode
		chunk.refresh()


func _queue_water_redraw() -> void:
	if water_back_layer:
		water_back_layer.queue_redraw()
