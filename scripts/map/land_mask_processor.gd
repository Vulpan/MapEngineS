extends RefCounted
class_name LandMaskProcessor

var image: Image

var land_bitmap: BitMap
var water_bitmap: BitMap

var land_polygons: Array[PackedVector2Array] = []
var land_polygon_areas: Array[float] = []
var land_polygon_bounds: Array[Rect2] = []

var water_polygons: Array[PackedVector2Array] = []
var water_polygon_areas: Array[float] = []
var water_polygon_bounds: Array[Rect2] = []

var threshold: float = 0.5
var black_is_land: bool = true
var map_rect: Rect2 = Rect2()


#func load_mask(texture_path: String, map_size: Vector2i, p_threshold: float = 0.5, p_black_is_land: bool = true) -> bool:
	#threshold = p_threshold
	#black_is_land = p_black_is_land
	#map_rect = Rect2(0, 0, map_size.x, map_size.y)
	#
	#if not texture_path.is_empty():
		#image = Image.load_from_file(texture_path)
		#if image == null or image.is_empty():
			#push_error("Failed to load mask image: " + texture_path)
			#return false
	#
	#if not image:
		#return false
	#
	#if image.get_width() != map_size.x or image.get_height() != map_size.y:
		#image.resize(map_size.x, map_size.y, Image.INTERPOLATE_NEAREST)
	#
	#land_bitmap = BitMap.new()
	#water_bitmap = BitMap.new()
	#land_bitmap.create(Vector2i(image.get_width(), image.get_height()))
	#water_bitmap.create(Vector2i(image.get_width(), image.get_height()))
	#
	#for y in range(image.get_height()):
		#for x in range(image.get_width()):
			#var c := image.get_pixel(x, y)
			#var brightness := (c.r + c.g + c.b) / 3.0
			#var is_land := brightness < threshold if black_is_land else brightness > threshold
			#var is_water := not is_land
			#
			#land_bitmap.set_bit(x, y, is_land)
			#water_bitmap.set_bit(x, y, is_water)
	#
	#land_polygons = land_bitmap.opaque_to_polygons(
		#Rect2i(Vector2i.ZERO, Vector2i(image.get_width(), image.get_height())),
		#1.5
	#)
	##water_polygons = water_bitmap.opaque_to_polygons(
		##Rect2i(Vector2i.ZERO, Vector2i(image.get_width(), image.get_height())),
		##1.5
	##)
	#
	##_rebuild_land_polygon_cache()
	##_rebuild_water_polygon_cache()
	#_rebuild_land_polygon_cache()
	#_build_water_polygons()
	#
	#return true


func load_mask(texture_path: String, map_size: Vector2i, p_threshold: float = 0.5, p_black_is_land: bool = true) -> bool:
	var img := Image.load_from_file(texture_path)
	if img == null or img.is_empty():
		push_error("Failed to load mask image: " + texture_path)
		return false
	
	return load_mask_from_image(img, map_size, p_threshold, p_black_is_land)


func load_mask_from_image(src_image: Image, map_size: Vector2i, p_threshold: float = 0.5, p_black_is_land: bool = true) -> bool:
	threshold = p_threshold
	black_is_land = p_black_is_land
	map_rect = Rect2(0, 0, map_size.x, map_size.y)
	
	image = src_image.duplicate()
	if image == null or image.is_empty():
		push_error("Land mask image is empty.")
		return false
	
	if image.get_width() != map_size.x or image.get_height() != map_size.y:
		image.resize(map_size.x, map_size.y, Image.INTERPOLATE_NEAREST)
	
	land_bitmap = BitMap.new()
	water_bitmap = BitMap.new()
	land_bitmap.create(Vector2i(image.get_width(), image.get_height()))
	water_bitmap.create(Vector2i(image.get_width(), image.get_height()))
	
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			var brightness := (c.r + c.g + c.b) / 3.0
			var is_land := brightness < threshold if black_is_land else brightness > threshold
			var is_water := not is_land
			
			land_bitmap.set_bit(x, y, is_land)
			water_bitmap.set_bit(x, y, is_water)
	
	land_polygons = land_bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, Vector2i(image.get_width(), image.get_height())),
		1.5
	)
	
	_rebuild_land_polygon_cache()
	# jeśli masz jeszcze wodę logiczną z bitmapy albo inne cache, zbuduj je tutaj
	
	return true


func _rebuild_land_polygon_cache() -> void:
	land_polygon_areas.clear()
	land_polygon_bounds.clear()
	
	var filtered: Array[PackedVector2Array] = []
	
	for poly in land_polygons:
		if poly.size() < 3:
			continue
		
		var area: float = abs(_polygon_area(poly))
		if area <= 0.001:
			continue
		
		filtered.append(poly)
		land_polygon_areas.append(area)
		land_polygon_bounds.append(_polygon_bounds(poly))
	
	land_polygons = filtered


func _rebuild_water_polygon_cache() -> void:
	water_polygon_areas.clear()
	water_polygon_bounds.clear()
	
	var filtered: Array[PackedVector2Array] = []
	
	for poly in water_polygons:
		if poly.size() < 3:
			continue
		
		var area: float = abs(_polygon_area(poly))
		if area <= 0.001:
			continue
		
		filtered.append(poly)
		water_polygon_areas.append(area)
		water_polygon_bounds.append(_polygon_bounds(poly))
	
	water_polygons = filtered

func _build_water_polygons() -> void:
	water_polygons.clear()
	water_polygon_areas.clear()
	water_polygon_bounds.clear()
	
	var map_poly := PackedVector2Array([
		map_rect.position,
		map_rect.position + Vector2(map_rect.size.x, 0),
		map_rect.end,
		map_rect.position + Vector2(0, map_rect.size.y)
	])
	
	var current_parts: Array[PackedVector2Array] = [map_poly]
	
	for land_poly in land_polygons:
		var next_parts: Array[PackedVector2Array] = []
		
		for part in current_parts:
			var result_parts = Geometry2D.clip_polygons(part, land_poly)
			
			if result_parts.is_empty():
				continue
			
			for rp in result_parts:
				var cleaned := _cleanup_polygon(rp)
				if cleaned.size() >= 3 and abs(_polygon_area(cleaned)) > 0.001:
					next_parts.append(cleaned)
		
		current_parts = next_parts
	
	for poly in current_parts:
		var cleaned := _cleanup_polygon(poly)
		if cleaned.size() < 3:
			continue
		
		var area: float = abs(_polygon_area(cleaned))
		if area <= 0.001:
			continue
		
		water_polygons.append(cleaned)
		water_polygon_areas.append(area)
		water_polygon_bounds.append(_polygon_bounds(cleaned))

func sample_is_land(pos: Vector2) -> bool:
	if image == null or image.is_empty():
		return true
	
	var x := clampi(int(round(pos.x)), 0, image.get_width() - 1)
	var y := clampi(int(round(pos.y)), 0, image.get_height() - 1)
	
	var c := image.get_pixel(x, y)
	var brightness := (c.r + c.g + c.b) / 3.0
	return brightness < threshold if black_is_land else brightness > threshold


func sample_domain(pos: Vector2) -> int:
	return CellData.DOMAIN_LAND if sample_is_land(pos) else CellData.DOMAIN_WATER


func find_component_for_point(pos: Vector2, domain: int) -> int:
	var polygons = land_polygons if domain == CellData.DOMAIN_LAND else water_polygons
	
	for i in range(polygons.size()):
		if Geometry2D.is_point_in_polygon(pos, polygons[i]):
			return i
	
	# fallback: nearest polygon center/bounds center
	var bounds_arr = land_polygon_bounds if domain == CellData.DOMAIN_LAND else water_polygon_bounds
	var best_idx := -1
	var best_d := INF
	
	for i in range(bounds_arr.size()):
		var c := bounds_arr[i].get_center()
		var d := c.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_idx = i
	
	return best_idx


func clip_polygon_to_component(poly: PackedVector2Array, site: Vector2, domain: int, component_id: int) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	
	var domain_polygons = land_polygons if domain == CellData.DOMAIN_LAND else water_polygons
	if component_id < 0 or component_id >= domain_polygons.size():
		return PackedVector2Array()
	
	var target_poly: PackedVector2Array = domain_polygons[component_id]
	var results = Geometry2D.intersect_polygons(poly, target_poly)
	
	if results.is_empty():
		return PackedVector2Array()
	
	# 1. preferuj fragment zawierający site
	for piece in results:
		if piece.size() >= 3 and Geometry2D.is_point_in_polygon(site, piece):
			return _cleanup_polygon(piece)
	
	# 2. fallback: najbliższy środek bounds do site
	var best := PackedVector2Array()
	var best_d := INF
	
	for piece in results:
		if piece.size() < 3:
			continue
		
		var center := _polygon_bounds(piece).get_center()
		var d := center.distance_squared_to(site)
		if d < best_d:
			best_d = d
			best = piece
	
	return _cleanup_polygon(best)


func classify_cell(_site: Vector2, original_poly: PackedVector2Array, clipped_poly: PackedVector2Array, domain: int) -> Dictionary:
	var original_area: float = abs(_polygon_area(original_poly))
	var clipped_area: float = abs(_polygon_area(clipped_poly))
	
	var exists: float = clipped_poly.size() >= 3 and clipped_area > 0.0
	var is_coastal := false
	
	if exists and original_area > 0.0:
		var ratio: float = clipped_area / original_area
		is_coastal = ratio < 0.999
	
	return {
		"is_land": domain == CellData.DOMAIN_LAND and exists,
		"is_water": domain == CellData.DOMAIN_WATER and exists,
		"is_coastal": is_coastal
	}


func get_land_polygon_count() -> int:
	return land_polygons.size()


func get_land_polygon_area(index: int) -> float:
	if index < 0 or index >= land_polygon_areas.size():
		return 0.0
	return land_polygon_areas[index]


func get_random_point_in_land_polygon(index: int, rng: RandomNumberGenerator, max_attempts: int = 32) -> Vector2:
	if index < 0 or index >= land_polygons.size():
		return Vector2.ZERO
	
	var poly: PackedVector2Array = land_polygons[index]
	var bounds: Rect2 = land_polygon_bounds[index]
	
	for i in range(max_attempts):
		var p := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	
	return bounds.get_center()


func get_random_land_point(rng: RandomNumberGenerator, max_attempts_per_polygon: int = 32) -> Vector2:
	if land_polygons.is_empty():
		return Vector2.ZERO
	
	var poly_index := _pick_weighted_polygon_index(rng)
	return get_random_point_in_land_polygon(poly_index, rng, max_attempts_per_polygon)


func get_random_land_point_balanced(rng: RandomNumberGenerator, small_island_boost: float = 0.35, max_attempts_per_polygon: int = 32) -> Vector2:
	if land_polygons.is_empty():
		return Vector2.ZERO
	
	var poly_index := _pick_weighted_polygon_index_balanced(rng, small_island_boost)
	return get_random_point_in_land_polygon(poly_index, rng, max_attempts_per_polygon)


func get_component_polygon(domain: int, component_id: int) -> PackedVector2Array:
	if domain == CellData.DOMAIN_LAND:
		if component_id >= 0 and component_id < land_polygons.size():
			return land_polygons[component_id]
	else:
		if component_id >= 0 and component_id < water_polygons.size():
			return water_polygons[component_id]
	return PackedVector2Array()


func _pick_weighted_polygon_index(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for a in land_polygon_areas:
		total += a
	
	if total <= 0.0:
		return 0
	
	var r := rng.randf() * total
	var accum := 0.0
	
	for i in range(land_polygon_areas.size()):
		accum += land_polygon_areas[i]
		if r <= accum:
			return i
	
	return land_polygon_areas.size() - 1


func _pick_weighted_polygon_index_balanced(rng: RandomNumberGenerator, small_island_boost: float = 0.35) -> int:
	var weights: Array[float] = []
	var total := 0.0
	
	for area in land_polygon_areas:
		var w: float = lerp(area, sqrt(area), small_island_boost)
		weights.append(w)
		total += w
	
	if total <= 0.0:
		return 0
	
	var r := rng.randf() * total
	var accum := 0.0
	
	for i in range(weights.size()):
		accum += weights[i]
		if r <= accum:
			return i
	
	return weights.size() - 1


func _polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect


func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	
	var area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	
	return area * 0.5

func _cleanup_polygon(poly: PackedVector2Array, eps: float = 0.001) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	
	var arr: Array[Vector2] = []
	for p in poly:
		if arr.is_empty() or arr[arr.size() - 1].distance_to(p) > eps:
			arr.append(p)
	
	if arr.size() > 1 and arr[0].distance_to(arr[arr.size() - 1]) <= eps:
		arr.remove_at(arr.size() - 1)
	
	if arr.size() < 3:
		return PackedVector2Array()
	
	return PackedVector2Array(arr)
