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

@export var coastal_epsilon := 1.5

var bounds: Rect2
var rng := RandomNumberGenerator.new()
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

var selected_cell_id: int = -1
var selected_region_id: int = -1

var chunk_render_layer: ChunkRenderLayer
var highlight_layer: HighlightLayer
var border_layer: BorderLayer
var mask_layer: MaskLayer
var debug_layer: DebugLayer

func _ready() -> void:
	if is_active:
		initialize()


func initialize() -> void:
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


# =========================================================
# INITIAL GENERATION
# =========================================================

func _generate_initial_cells(count: int) -> void:
	map_data.clear()
	map_data.bounds = bounds

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
		cell.domain = domain
		cell.component_id = comp_id

		created += 1

	_rebuild_lookup_caches()
	print("Generated initial cells: ", map_data.cells.size(), " / ", count, " | tries=", tries)


func _site_exists_near(pos: Vector2, min_dist: float) -> bool:
	var min_dist_sqr := min_dist * min_dist
	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		if cell.site.distance_squared_to(pos) <= min_dist_sqr:
			return true
	return false


# =========================================================
# LOOKUP CACHE
# =========================================================

func _rebuild_lookup_caches() -> void:
	site_to_cell_id.clear()
	cell_id_to_site.clear()
	points.clear()

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		site_to_cell_id[cell.site] = cell.id
		cell_id_to_site[cell.id] = cell.site
		points.append(cell.site)


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
			manager.build(pts, bounds)

		component_managers[key] = manager

	_rebuild_component_cached_cells()
	_sync_geometry_from_component_managers()
	_rebuild_coastal_adjacency()

	var elapsed := Time.get_ticks_msec() - start
	print("Component geometry rebuild: ", elapsed, " ms | groups=", component_managers.size())
	chunk_render_layer.rebuild_all()
	update_layers()


func _rebuild_component_cached_cells() -> void:
	cached_cells.clear()

	for key in component_managers.keys():
		var manager: DynamicDelaunayVoronoi = component_managers[key]
		var cells = manager.get_cells()
		for site in cells.keys():
			cached_cells[site] = cells[site]


func _sync_geometry_from_component_managers() -> void:
	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		cell.polygon = PackedVector2Array()
		cell.neighbor_ids.clear()
		cell.coastal_neighbor_ids.clear()
		cell.is_land = cell.domain == CellData.DOMAIN_LAND
		cell.is_water = cell.domain == CellData.DOMAIN_WATER
		cell.is_coastal = false

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		var site := cell.site

		if not cached_cells.has(site):
			continue

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
	var land_cells: Array = []
	var water_cells: Array = []

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		cell.coastal_neighbor_ids.clear()

		if cell.polygon.size() < 2:
			continue

		if cell.domain == CellData.DOMAIN_LAND:
			land_cells.append(cell)
		else:
			water_cells.append(cell)

	for land_cell in land_cells:
		for water_cell in water_cells:
			if _polygons_touch(land_cell.polygon, water_cell.polygon, coastal_epsilon):
				land_cell.coastal_neighbor_ids.append(water_cell.id)
				water_cell.coastal_neighbor_ids.append(land_cell.id)
				land_cell.is_coastal = true
				water_cell.is_coastal = true


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
	var dir_path = path + file_name
	var dir = DirAccess.open(path).make_dir(file_name)
	dir = DirAccess.open(dir_path)
	path = dir.get_current_dir() + "/"
	
	var ok := MapSerializer.save_to_json(path + Global.map_file_name, map_data)
	
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
		"map_render_scale": map_render_scale
	}
	settings_file.store_string(JSON.stringify(settings_dict, "\t"))
	settings_file.close()
	
	print("Save map: ", ok, " | ", path)


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
	
	effective_width = int(map_width * map_render_scale)
	effective_height = int(map_height * map_render_scale)
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
	
	var loaded := MapSerializer.load_from_json(dir.get_current_dir() + "/" + Global.map_file_name)
	if loaded == null:
		return
	
	map_data = loaded
	#bounds = map_data.bounds
	
	if not is_active:
		is_active = true
	
	setup_layers()
	rebuild_geometry_from_map_data()
	
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
	if ok:
		var cell := map_data.create_cell(pos)
		cell.domain = domain
		cell.component_id = component_id
		
		_rebuild_lookup_caches()
		_rebuild_component_cached_cells()
		_sync_geometry_from_component_managers()
		_rebuild_coastal_adjacency()
		
		var affected := _get_affected_cell_ids_from_cached(pos)
		if cell.id not in affected:
			affected.append(cell.id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
	
	var elapsed := Time.get_ticks_msec() - start
	print("Add point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
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
	
	var target_manager: DynamicDelaunayVoronoi = component_managers[key]
	
	var start := Time.get_ticks_msec()
	var ok := target_manager.remove_point(cell.site)
	if ok:
		map_data.remove_cell(nearest_cell_id)
		if selected_cell_id == nearest_cell_id:
			selected_cell_id = -1
		
		_rebuild_lookup_caches()
		_rebuild_component_cached_cells()
		_sync_geometry_from_component_managers()
		_rebuild_coastal_adjacency()
		
		chunk_render_layer.remove_cell(nearest_cell_id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
	
	var elapsed := Time.get_ticks_msec() - start
	print("Remove point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
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

	if old_key == new_key:
		var target_manager: DynamicDelaunayVoronoi = component_managers[old_key]
		ok = target_manager.move_point(old_site, pos)
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
			ok = new_manager.add_point(pos)

	if ok:
		cell.site = pos
		cell.domain = new_domain
		cell.component_id = new_component_id
		
		_rebuild_lookup_caches()
		_rebuild_component_cached_cells()
		_sync_geometry_from_component_managers()
		_rebuild_coastal_adjacency()
		
		var affected := _get_affected_cell_ids_from_cached(pos)
		if nearest_cell_id not in affected:
			affected.append(nearest_cell_id)
		chunk_render_layer.refresh_chunks_for_cells(affected)
		
		selected_cell_id = nearest_cell_id
	
	var elapsed := Time.get_ticks_msec() - start
	print("Move point: ", ok, " | ", elapsed, " ms | cells=", map_data.cells.size())
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
	_rebuild_component_cached_cells()
	_sync_geometry_from_component_managers()
	_rebuild_coastal_adjacency()
	
	var affected: Array = [cell_id]
	if map_data.cells.has(cell_id):
		affected.append_array(map_data.cells[cell_id].neighbor_ids)
		affected.append_array(map_data.cells[cell_id].coastal_neighbor_ids)
	chunk_render_layer.refresh_chunks_for_cells(affected)
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
	var best_id := -1
	var best_d := INF
	var max_d_sqr := max_dist * max_dist

	for cell_id in map_data.cells.keys():
		var cell: CellData = map_data.cells[cell_id]
		var d := cell.site.distance_squared_to(pos)
		if d < best_d and d <= max_d_sqr:
			best_d = d
			best_id = cell_id

	return best_id


func find_cell_id_at_position(pos: Vector2) -> int:
	if chunk_render_layer:
		return chunk_render_layer.pick_cell_at(pos)
	return -1


# =========================================================
# REGIONS
# =========================================================

func create_region_for_selected_cell() -> void:
	if selected_cell_id == -1:
		return

	var region := map_data.create_region("Region %d" % map_data.next_region_id)
	map_data.assign_cell_to_region(selected_cell_id, region.id)
	selected_region_id = region.id
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
			KEY_E:
				create_region_for_selected_cell()
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
	
	for key in chunk_render_layer.chunks.keys():
		var chunk: MapChunk = chunk_render_layer.chunks[key]
		chunk.draw_mode = chunk_draw_mode
		chunk.refresh()
