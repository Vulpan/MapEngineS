extends RefCounted
class_name BorderMaskProcessor

var border_points: Array[Vector2] = []
var border_pairs: Array[Array] = [] # Array of [Vector2, Vector2]
var image: Image

#func load_border_mask(path: String, map_size: Vector2i, threshold: float = 0.5, spacing: float = 20.0) -> bool:
	#if not path.is_empty():
		#image = Image.load_from_file(path)
		#if image == null or image.is_empty():
			#push_error("Failed to load border mask: " + path)
			#return false
	#
	#if not image:
		#return false
	#
	#if image.get_width() != map_size.x or image.get_height() != map_size.y:
		#image.resize(map_size.x, map_size.y, Image.INTERPOLATE_NEAREST)
	#
	#border_points.clear()
	#border_pairs.clear()
	#_extract_edge_pairs(threshold, spacing, 3.0)
	#
	#return true

func load_border_mask(path: String, map_size: Vector2i, threshold: float = 0.5, spacing: float = 20.0) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("Failed to load border mask: " + path)
		return false
	
	return load_border_mask_from_image(img, map_size, threshold, spacing)


func load_border_mask_from_image(src_image: Image, map_size: Vector2i, threshold: float = 0.5, spacing: float = 20.0) -> bool:
	image = src_image.duplicate()
	if image == null or image.is_empty():
		push_error("Border mask image is empty.")
		return false
	
	if image.get_width() != map_size.x or image.get_height() != map_size.y:
		image.resize(map_size.x, map_size.y, Image.INTERPOLATE_NEAREST)
	
	border_points.clear()
	border_pairs.clear()
	_extract_edge_pairs(threshold, spacing, 3.0)
	
	return true


func _extract_edge_points(threshold: float, spacing: float) -> void:
	var w := image.get_width()
	var h := image.get_height()
	
	# krok 1: znajdź piksele krawędziowe
	var edge_pixels: Array[Vector2] = []
	
	for y in range(h):
		for x in range(w):
			if not _is_dark(x, y, threshold):
				continue
			
			# piksel jest ciemny — czy ma jasnego sąsiada?
			if _has_light_neighbor(x, y, w, h, threshold):
				edge_pixels.append(Vector2(x, y))
	
	# krok 2: grid-based sampling
	var grid_size := spacing
	var grid: Dictionary = {} # "gx:gy" -> Vector2
	
	for ep in edge_pixels:
		var gx := int(ep.x / grid_size)
		var gy := int(ep.y / grid_size)
		var key := "%d:%d" % [gx, gy]
		
		if not grid.has(key):
			grid[key] = ep
		else:
			# zachowaj punkt bliższy środkowi komórki grida
			var center := Vector2(
				(gx + 0.5) * grid_size,
				(gy + 0.5) * grid_size
			)
			if ep.distance_squared_to(center) < grid[key].distance_squared_to(center):
				grid[key] = ep
	
	border_points = []
	for key in grid.keys():
		border_points.append(grid[key])

func _extract_edge_pairs(threshold: float, spacing: float, offset: float = 3.0) -> void:
	var w := image.get_width()
	var h := image.get_height()
	
	var edge_data: Array[Array] = [] # [position, normal]
	
	for y in range(h):
		for x in range(w):
			if not _is_dark(x, y, threshold):
				continue
			
			var normal := _get_border_normal(x, y, w, h, threshold)
			if normal == Vector2.ZERO:
				continue
			
			edge_data.append([Vector2(x, y), normal])
	
	# grid sampling
	var grid_size := spacing
	var grid: Dictionary = {}
	
	for ed in edge_data:
		var pos: Vector2 = ed[0]
		var gx := int(pos.x / grid_size)
		var gy := int(pos.y / grid_size)
		var key := "%d:%d" % [gx, gy]
		
		if not grid.has(key):
			grid[key] = ed
		else:
			var center := Vector2(
				(gx + 0.5) * grid_size,
				(gy + 0.5) * grid_size
			)
			if pos.distance_squared_to(center) < (grid[key][0] as Vector2).distance_squared_to(center):
				grid[key] = ed
	
	border_points.clear()
	border_pairs.clear()
	
	for key in grid.keys():
		var ed: Array = grid[key]
		var pos: Vector2 = ed[0]
		var normal: Vector2 = ed[1]
		
		var a := pos + normal * offset
		var b := pos - normal * offset
		
		border_points.append(a)
		border_points.append(b)
		border_pairs.append([a, b])

func _is_dark(x: int, y: int, threshold: float) -> bool:
	var c := image.get_pixel(x, y)
	var brightness := (c.r + c.g + c.b) / 3.0
	return brightness < threshold


func _has_light_neighbor(x: int, y: int, w: int, h: int, threshold: float) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			
			var nx := x + dx
			var ny := y + dy
			
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				# krawędź obrazka = jasny sąsiad
				return true
			
			if not _is_dark(nx, ny, threshold):
				return true
	
	return false


func is_border_pixel(pos: Vector2, threshold: float = 0.5) -> bool:
	if image == null or image.is_empty():
		return false
	
	var x := clampi(int(round(pos.x)), 0, image.get_width() - 1)
	var y := clampi(int(round(pos.y)), 0, image.get_height() - 1)
	
	return _is_dark(x, y, threshold)

func _get_border_normal(x: int, y: int, w: int, h: int, threshold: float) -> Vector2:
	var normal := Vector2.ZERO
	
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			
			var nx := x + dx
			var ny := y + dy
			
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				normal += Vector2(dx, dy).normalized()
				continue
			
			if not _is_dark(nx, ny, threshold):
				normal += Vector2(dx, dy).normalized()
	
	if normal.length() < 0.001:
		return Vector2.ZERO
	
	return normal.normalized()
