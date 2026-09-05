extends Resource
class_name DynamicDelaunayVoronoi

var delaunay: Delaunay
var rect: Rect2

var points: Array[Vector2] = []
var triangulation: Array = []          # Array[Delaunay.Triangle]
var sites: Dictionary = {}             # Vector2 -> PackedVector2Array
var neighbors: Dictionary = {}         # Vector2 -> Array[Vector2]
var point_to_triangles: Dictionary = {} # Vector2 -> Array[Triangle]
var base_polygon: PackedVector2Array = PackedVector2Array()

var epsilon := 0.0001
var max_safe_local_remove_neighbors := 24


func _init(bounds := Rect2()) -> void:
	delaunay = Delaunay.new(bounds)
	rect = bounds


# =========================
# PUBLIC API
# =========================

func build(input_points: Array[Vector2], bounds: Rect2) -> void:
	rect = bounds
	points = _unique_points(input_points)
	_full_rebuild()


func get_cells() -> Dictionary:
	var out := {}
	for p in sites.keys():
		out[p] = [sites[p], neighbors.get(p, [])]
	return out


func has_point(p: Vector2) -> bool:
	return p in points


func add_point(p: Vector2) -> bool:
	if has_point(p):
		return false
	
	if not rect.has_point(p):
		return false
	
	if points.size() < 3:
		points.append(p)
		_full_rebuild()
		return true
	
	var bad_triangles := _find_bad_triangles_for_point(p)
	
	# Jeśli nic nie znaleziono, fallback
	if bad_triangles.is_empty():
		points.append(p)
		_full_rebuild()
		return true
	
	var cavity_edges := _make_cavity_boundary(bad_triangles)
	if cavity_edges.is_empty():
		points.append(p)
		_full_rebuild()
		return true
	
	var affected_points_dict := {}
	affected_points_dict[p] = true
	
	# usuń bad triangles
	for t in bad_triangles:
		_remove_triangle_from_indices(t)
		triangulation.erase(t)
		affected_points_dict[t.a] = true
		affected_points_dict[t.b] = true
		affected_points_dict[t.c] = true
	
	# dodaj nowy punkt
	points.append(p)
	
	# zamknij cavity nowymi trójkątami
	for edge in cavity_edges:
		var nt = Delaunay.Triangle.new(p, edge.a, edge.b)
		triangulation.append(nt)
		_add_triangle_to_indices(nt)
		affected_points_dict[edge.a] = true
		affected_points_dict[edge.b] = true
	
	# lokalne odświeżenie sąsiedztwa + komórek
	var affected_points := affected_points_dict.keys()
	_rebuild_neighbors_for_points(affected_points)
	_rebuild_sites_for_points(affected_points)
	
	var invalid := false
	for ap in affected_points:
		if not sites.has(ap) or sites[ap].size() < 3:
			invalid = true
			break

	if invalid:
		_full_rebuild()
	
	return true


func remove_point(p: Vector2) -> bool:
	if not has_point(p):
		return false
	
	points.erase(p)
	_full_rebuild()
	return true


func move_point(old_p: Vector2, new_p: Vector2) -> bool:
	if not has_point(old_p):
		return false
	if has_point(new_p):
		return false
	if not rect.has_point(new_p):
		return false
	
	# MVP: bezpieczny fallback
	points.erase(old_p)
	points.append(new_p)
	_full_rebuild()
	return true

func set_base_polygon(poly: PackedVector2Array) -> void:
	base_polygon = poly

func _cleanup_polygon(poly: PackedVector2Array, eps: float = 0.001) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	
	var arr: Array[Vector2] = []
	
	# usuń kolejne duplikaty
	for p in poly:
		if arr.is_empty() or arr[arr.size() - 1].distance_to(p) > eps:
			arr.append(p)
	
	# usuń domknięcie będące duplikatem początku
	if arr.size() > 1 and arr[0].distance_to(arr[arr.size() - 1]) <= eps:
		arr.remove_at(arr.size() - 1)
	
	# usuń punkty współliniowe / prawie współliniowe
	var changed2 := true
	while changed2 and arr.size() >= 3:
		changed2 = false
		for i in range(arr.size()):
			var a := arr[(i - 1 + arr.size()) % arr.size()]
			var b := arr[i]
			var c := arr[(i + 1) % arr.size()]
			
			var ab := b - a
			var bc := c - b
			var cross := ab.x * bc.y - ab.y * bc.x
			
			if abs(cross) <= eps:
				arr.remove_at(i)
				changed2 = true
				break
	
	if arr.size() < 3:
		return PackedVector2Array()
	
	return PackedVector2Array(arr)



# =========================
# FULL REBUILD
# =========================

func _full_rebuild() -> void:
	sites.clear()
	neighbors.clear()
	point_to_triangles.clear()
	triangulation.clear()
	
	if points.size() == 0:
		return
	
	delaunay = Delaunay.new(rect)
	for p in points:
		delaunay.add_point(p)
	
	triangulation = delaunay.triangulate()
	delaunay.remove_border_triangles(triangulation)
	
	_rebuild_all_indices()
	_rebuild_all_neighbors()
	_rebuild_all_sites()


# =========================
# TRIANGLE / INDEX CACHE
# =========================

func _rebuild_all_indices() -> void:
	point_to_triangles.clear()
	for p in points:
		point_to_triangles[p] = []
	
	for t in triangulation:
		_add_triangle_to_indices(t)


func _add_triangle_to_indices(t) -> void:
	_ensure_point_index(t.a)
	_ensure_point_index(t.b)
	_ensure_point_index(t.c)
	
	point_to_triangles[t.a].append(t)
	point_to_triangles[t.b].append(t)
	point_to_triangles[t.c].append(t)


func _remove_triangle_from_indices(t) -> void:
	if point_to_triangles.has(t.a):
		point_to_triangles[t.a].erase(t)
	if point_to_triangles.has(t.b):
		point_to_triangles[t.b].erase(t)
	if point_to_triangles.has(t.c):
		point_to_triangles[t.c].erase(t)


func _ensure_point_index(p: Vector2) -> void:
	if not point_to_triangles.has(p):
		point_to_triangles[p] = []


# =========================
# NEIGHBORS
# =========================

func _rebuild_all_neighbors() -> void:
	neighbors.clear()
	for p in points:
		neighbors[p] = []
	
	for t in triangulation:
		_add_neighbor_pair(t.a, t.b)
		_add_neighbor_pair(t.b, t.c)
		_add_neighbor_pair(t.c, t.a)


func _rebuild_neighbors_for_points(pts: Array) -> void:
	var expanded := {}
	for p in pts:
		expanded[p] = true
	
	# dodaj sąsiadów z aktualnych trójkątów
	for p in pts:
		if not point_to_triangles.has(p):
			continue
		for t in point_to_triangles[p]:
			expanded[t.a] = true
			expanded[t.b] = true
			expanded[t.c] = true
	
	var region := expanded.keys()
	
	for p in region:
		neighbors[p] = []
	
	for p in region:
		if not point_to_triangles.has(p):
			continue
		for t in point_to_triangles[p]:
			if p == t.a:
				_add_neighbor_pair(p, t.b)
				_add_neighbor_pair(p, t.c)
			elif p == t.b:
				_add_neighbor_pair(p, t.a)
				_add_neighbor_pair(p, t.c)
			elif p == t.c:
				_add_neighbor_pair(p, t.a)
				_add_neighbor_pair(p, t.b)


func _add_neighbor_pair(a: Vector2, b: Vector2) -> void:
	if a == b:
		return
	if not neighbors.has(a):
		neighbors[a] = []
	if not neighbors.has(b):
		neighbors[b] = []
	if b not in neighbors[a]:
		neighbors[a].append(b)
	if a not in neighbors[b]:
		neighbors[b].append(a)


# =========================
# VORONOI SITES
# =========================

func _is_polygon_drawable(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	
	var cleaned := _cleanup_polygon(poly)
	if cleaned.size() < 3:
		return false
	
	# area musi być sensowna
	var area := 0.0
	for i in range(cleaned.size()):
		var a := cleaned[i]
		var b := cleaned[(i + 1) % cleaned.size()]
		area += a.x * b.y - b.x * a.y
	
	return abs(area * 0.5) > 0.001

func _rebuild_all_sites() -> void:
	sites.clear()
	for p in points:
		var poly := _build_site_polygon(p)
		if poly.size() >= 3:
			sites[p] = poly


func _rebuild_sites_for_points(pts: Array) -> void:
	var expanded := {}
	for p in pts:
		expanded[p] = true
		if neighbors.has(p):
			for n in neighbors[p]:
				expanded[n] = true
	
	for p in expanded.keys():
		var poly := _build_site_polygon(p)
		if poly.size() >= 3:
			sites[p] = poly
		else:
			sites.erase(p)


func _build_site_polygon(p: Vector2) -> PackedVector2Array:
	if not neighbors.has(p):
		return PackedVector2Array()
	
	var poly: Array[Vector2] = []
	
	if base_polygon.size() >= 3:
		for v in base_polygon:
			poly.append(v)
	else:
		poly = [
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.end,
			rect.position + Vector2(0, rect.size.y)
		]
	
	for n in neighbors[p]:
		poly = _clip_polygon_with_bisector(poly, p, n)
		if poly.size() < 3:
			return PackedVector2Array()
	
	return _cleanup_polygon(PackedVector2Array(poly))

func _clip_polygon_with_bisector(poly: Array[Vector2], site: Vector2, other: Vector2) -> Array[Vector2]:
	if poly.is_empty():
		return []
	
	var output: Array[Vector2] = []
	var prev: Vector2 = poly[poly.size() - 1]
	var prev_inside := _is_point_closer_to_site(prev, site, other)
	
	for curr in poly:
		var curr_inside := _is_point_closer_to_site(curr, site, other)
		
		if curr_inside:
			if not prev_inside:
				output.append(_segment_bisector_intersection(prev, curr, site, other))
			output.append(curr)
		elif prev_inside:
			output.append(_segment_bisector_intersection(prev, curr, site, other))
		
		prev = curr
		prev_inside = curr_inside
	
	return _dedupe_polygon(output)

func _is_point_closer_to_site(x: Vector2, site: Vector2, other: Vector2) -> bool:
	return x.distance_squared_to(site) <= x.distance_squared_to(other) + epsilon

func _segment_bisector_intersection(a: Vector2, b: Vector2, site: Vector2, other: Vector2) -> Vector2:
	var d := b - a
	var n := other - site
	var c := (other.length_squared() - site.length_squared()) * 0.5
	
	var denom := d.dot(n)
	if abs(denom) < epsilon:
		return a
	
	var t := (c - a.dot(n)) / denom
	t = clamp(t, 0.0, 1.0)
	return a + d * t

func _dedupe_polygon(poly: Array[Vector2]) -> Array[Vector2]:
	if poly.size() <= 1:
		return poly
	
	var out: Array[Vector2] = []
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > epsilon:
			out.append(p)
	
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= epsilon:
		out.remove_at(out.size() - 1)
	
	return out

# =========================
# LOCAL INSERT SUPPORT
# =========================

func _find_bad_triangles_for_point(p: Vector2) -> Array:
	var bad: Array = []
	
	# MVP: pełny scan triangulacji
	# Dla bardzo dużej liczby punktów można potem zastąpić spatial indexem.
	for t in triangulation:
		if t.is_point_inside_circumcircle(p):
			bad.append(t)
	
	return bad


func _make_cavity_boundary(bad_triangles: Array) -> Array:
	var edges: Array = []
	var duplicates: Array = []
	
	for t in bad_triangles:
		edges.append(Delaunay.Edge.new(t.a, t.b))
		edges.append(Delaunay.Edge.new(t.b, t.c))
		edges.append(Delaunay.Edge.new(t.c, t.a))
	
	for i in range(edges.size()):
		for j in range(i + 1, edges.size()):
			if edges[i] != null and edges[j] != null and edges[i].equals(edges[j]):
				duplicates.append(edges[i])
				duplicates.append(edges[j])
	
	for d in duplicates:
		edges.erase(d)
	
	# opcjonalnie uporządkuj krawędzie wokół cavity
	return _order_edges_loop(edges)


func _order_edges_loop(edges: Array) -> Array:
	if edges.is_empty():
		return []
	
	var remaining := edges.duplicate()
	var ordered := [remaining.pop_front()]
	
	while not remaining.is_empty():
		var last = ordered[-1]
		var found := false
		
		for i in range(remaining.size()):
			var e = remaining[i]
			
			if e.a == last.b:
				ordered.append(e)
				remaining.remove_at(i)
				found = true
				break
			elif e.b == last.b:
				var ne = Delaunay.Edge.new(e.b, e.a)
				ordered.append(ne)
				remaining.remove_at(i)
				found = true
				break
		
		if not found:
			# jeśli nie udało się złożyć pętli, zwróć oryginał i fallback wyżej ogarnie problem
			return edges
	
	return ordered


# =========================
# GEOMETRY HELPERS
# =========================

func _clip_polygon_to_rect(poly: PackedVector2Array, clip_rect: Rect2) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	
	var bound = PackedVector2Array([
		clip_rect.position,
		clip_rect.position + Vector2(clip_rect.size.x, 0),
		clip_rect.end,
		clip_rect.position + Vector2(0, clip_rect.size.y),
	])
	
	var result = Geometry2D.intersect_polygons(poly, bound)
	if result.is_empty():
		return PackedVector2Array()
	
	# bierz największy obszar
	var best: PackedVector2Array = result[0]
	var best_area = abs(_polygon_area(best))

	for i in range(1, result.size()):
		var candidate: PackedVector2Array = result[i]
		var area = abs(_polygon_area(candidate))
		if area > best_area:
			best = candidate
			best_area = area
	
	return best


func _unique_points(arr: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in arr:
		var exists := false
		for q in out:
			if p.distance_to(q) <= epsilon:
				exists = true
				break
		if not exists:
			out.append(p)
	return out


func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	
	var area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	
	return area * 0.5
