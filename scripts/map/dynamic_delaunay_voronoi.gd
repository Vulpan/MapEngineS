extends Resource
class_name DynamicDelaunayVoronoi

var delaunay: Delaunay
var rect: Rect2

var points: Array[Vector2] = []
var points_set: Dictionary = {}        # Vector2 -> true (O(1) has_point)
var triangulation: Array = []          # Array[Delaunay.Triangle]
var last_affected_sites: Array = []    # punkty, których komórki zmieniły się w ostatniej operacji
var _touched: Dictionary = {}          # bufor roboczy dla last_affected_sites
var sites: Dictionary = {}             # Vector2 -> PackedVector2Array
var neighbors: Dictionary = {}         # Vector2 -> Array[Vector2]
var point_to_triangles: Dictionary = {} # Vector2 -> Array[Triangle]
var base_polygon: PackedVector2Array = PackedVector2Array()
var _base_center := Vector2.ZERO
var _base_radius := 0.0

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
	return points_set.has(p)


func add_point(p: Vector2) -> bool:
	if has_point(p):
		return false
	
	if not rect.has_point(p):
		return false
	
	_touched.clear()
	
	if points.size() < 3:
		points.append(p)
		points_set[p] = true
		_full_rebuild()
		return true
	
	var bad_triangles := _find_bad_triangles_for_point(p)
	
	# Jeśli nic nie znaleziono, fallback
	if bad_triangles.is_empty():
		points.append(p)
		points_set[p] = true
		_full_rebuild()
		return true
	
	var cavity_edges := _make_cavity_boundary(bad_triangles)
	if cavity_edges.is_empty():
		points.append(p)
		points_set[p] = true
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
	points_set[p] = true
	
	# zamknij cavity nowymi trójkątami
	var new_tris: Array = []
	for edge in cavity_edges:
		var nt = Delaunay.Triangle.new(p, edge.a, edge.b)
		triangulation.append(nt)
		_add_triangle_to_indices(nt)
		affected_points_dict[edge.a] = true
		affected_points_dict[edge.b] = true
		new_tris.append(nt)

	# WALIDACJA: suma pól nowych trójkątów == pole zamkniętej pętli cavity.
	# Łapie nachodzenie trójkątów (kodegeneracje okręgów opisanych, punkt
	# na/poza otoczką, niespójna pętla brzegowa) → fallback do pełnego rebuildu.
	var loop_pts := _ordered_loop_points(cavity_edges)
	var valid_patch := false
	if loop_pts.size() >= 3:
		var cav_area := absf(_poly_area(loop_pts))
		var new_area := 0.0
		for t in new_tris:
			new_area += absf((t.b - t.a).cross(t.c - t.a)) * 0.5
		valid_patch = absf(new_area - cav_area) <= maxf(0.5, cav_area * 0.001)

	if not valid_patch:
		_full_rebuild()
		return true
	
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
	
	last_affected_sites = _touched.keys()
	return true


func remove_point(p: Vector2) -> bool:
	if not has_point(p):
		return false

	# Małe zbiory: pełny rebuild jest i tak darmowy, a omija ścieżki brzegowe.
	if points.size() <= 4:
		points.erase(p)
		points_set.erase(p)
		_full_rebuild()
		return true

	# UWAGA: kopia (duplicate) — point_to_triangles.get() zwraca żywą tablicę,
	# a _remove_triangle_from_indices() modyfikuje ją w miejscu (corner == p).
	# Iterowanie po oryginale podczas erase pomijałoby co drugi element.
	var star: Array = point_to_triangles.get(p, []).duplicate()
	if star.is_empty():
		points.erase(p)
		points_set.erase(p)
		_full_rebuild()
		return true

	# Brzeg "dziury" po usuwanym punkcie (uporządkowana pętla wokół p).
	var hole := _build_hole_polygon(star, p)
	if hole.size() < 3:
		points.erase(p)
		points_set.erase(p)
		_full_rebuild()
		return true

	# Usuń trójkąty gwiazdy jednym przejazdem.
	var dead := {}
	for t in star:
		dead[t] = true
	var kept: Array = []
	for t in triangulation:
		if not dead.has(t):
			kept.append(t)
	triangulation = kept

	for t in star:
		_remove_triangle_from_indices(t)
	point_to_triangles.erase(p)
	neighbors.erase(p)
	points.erase(p)
	points_set.erase(p)

	# Lokalna retriangulacja dziury: triangulacja Delaunay'a wierzchołków brzegu
	# ograniczona do wnętrza dziury (krawędzie dziury należą do DT(H)).
	var hole_pts := PackedVector2Array(hole)
	var tri_idx := Geometry2D.triangulate_delaunay(hole_pts)
	if tri_idx.size() < 3:
		_full_rebuild()
		return true

	var added := 0
	for i in range(0, tri_idx.size(), 3):
		var a: Vector2 = hole_pts[tri_idx[i]]
		var b: Vector2 = hole_pts[tri_idx[i + 1]]
		var c: Vector2 = hole_pts[tri_idx[i + 2]]
		var centroid := (a + b + c) / 3.0
		if Geometry2D.is_point_in_polygon(centroid, hole_pts):
			var nt = Delaunay.Triangle.new(a, b, c)
			triangulation.append(nt)
			_add_triangle_to_indices(nt)
			added += 1

	if added == 0:
		_full_rebuild()
		return true

	# WALIDACJA: suma pól łatki == pole dziury (brak nachodzenia/prześwitów).
	var hole_area := absf(_poly_area(hole))
	var patch_area := 0.0
	for i in range(triangulation.size() - added, triangulation.size()):
		var t = triangulation[i]
		patch_area += absf((t.b - t.a).cross(t.c - t.a)) * 0.5
	if absf(patch_area - hole_area) > maxf(0.5, hole_area * 0.001):
		_full_rebuild()
		return true

	_touched.clear()
	_rebuild_neighbors_for_points(hole)
	_rebuild_sites_for_points(hole)
	last_affected_sites = _touched.keys()

	# Walidacja — jakiekolwiek wątpliwości: fallback do pełnego rebuildu.
	for v in hole:
		if not sites.has(v) or sites[v].size() < 3:
			_full_rebuild()
			return true

	return true


## Zwraca uporządkowaną pętlę wierzchołków brzegu gwiazdy punktu (Array[Vector2])
## albo pustą tablicę, gdy brzegu nie udało się zbudować.
## Punkty leżące na otoczce wypukłej mają "otwartą" gwiazdę — pętla wiedzie wtedy
## PRZEZ usuwany punkt; wycięcie go z pętli zamyka dziurę cięciwą, która staje się
## nową krawędzią otoczki (pozostała geometria domyka test centroidów).
func _build_hole_polygon(star: Array, removed_point: Vector2) -> Array:
	# Krawędzie należące do dokładnie jednego trójkąta gwiazdy = brzeg dziury.
	var boundary: Array = []
	for t in star:
		var tri_edges := [
			Delaunay.Edge.new(t.a, t.b),
			Delaunay.Edge.new(t.b, t.c),
			Delaunay.Edge.new(t.c, t.a),
		]
		for e in tri_edges:
			var dup_idx := -1
			for j in range(boundary.size()):
				if boundary[j].equals(e):
					dup_idx = j
					break
			if dup_idx >= 0:
				boundary.remove_at(dup_idx)
			else:
				boundary.append(e)

	if boundary.size() < 3:
		return []

	var ordered := _order_edges_loop(boundary)
	if ordered.size() != boundary.size():
		return []

	# _order_edges_loop przy niepowodzeniu zwraca oryginał — zweryfikuj domknięcie.
	for i in range(ordered.size()):
		var e = ordered[i]
		var nxt = ordered[(i + 1) % ordered.size()]
		if e.b != nxt.a:
			return []

	var poly: Array = []
	for e in ordered:
		poly.append(e.a)

	# Punkt na otoczce: pętla przechodzi przez niego — wytnij go z dziury.
	while poly.has(removed_point):
		poly.erase(removed_point)

	if poly.size() < 3:
		return []

	return poly


func move_point(old_p: Vector2, new_p: Vector2) -> bool:
	if not has_point(old_p):
		return false
	if has_point(new_p):
		return false
	if not rect.has_point(new_p):
		return false

	# Lokalnie: usuń + wstaw zamiast pełnego rebuildu triangulacji.
	if not remove_point(old_p):
		return false

	var removed_affected := last_affected_sites

	if not add_point(new_p):
		# rollback (best effort) — stan pozostaje spójny
		add_point(old_p)
		return false

	var merged := {}
	for s in removed_affected:
		merged[s] = true
	for s in last_affected_sites:
		merged[s] = true
	last_affected_sites = merged.keys()
	return true

func set_base_polygon(poly: PackedVector2Array) -> void:
	base_polygon = poly
	_base_center = Vector2.ZERO
	_base_radius = 0.0
	if poly.size() >= 3:
		var bb := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			bb = bb.expand(v)
		_base_center = bb.get_center()
		for v in poly:
			_base_radius = maxf(_base_radius, _base_center.distance_to(v))

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

	points_set.clear()
	for p in points:
		points_set[p] = true

	if points.size() < 3:
		last_affected_sites = points.duplicate()
		return

	# Natywna triangulacja (C++): O(n log n) i poprawna topologia.
	# Addonowy Bowyer-Watson triangulate() w GDScript jest O(n^2) i gubi
	# trójkąty przy otoczce wypukłej (sąsiedztwa stawały się asymetryczne).
	var packed := PackedVector2Array(points)
	var tri_idx := Geometry2D.triangulate_delaunay(packed)
	for i in range(0, tri_idx.size(), 3):
		var t = Delaunay.Triangle.new(
			packed[tri_idx[i]],
			packed[tri_idx[i + 1]],
			packed[tri_idx[i + 2]]
		)
		triangulation.append(t)

	_rebuild_all_indices()
	_rebuild_all_neighbors()
	_rebuild_all_sites()

	last_affected_sites = points.duplicate()


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
		_touched[p] = true
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
		_touched[p] = true
		var poly := _build_site_polygon(p)
		if poly.size() >= 3:
			sites[p] = poly
		else:
			sites.erase(p)


func _build_site_polygon(p: Vector2) -> PackedVector2Array:
	if not neighbors.has(p):
		return PackedVector2Array()

	var neigh: Array = neighbors[p]

	# Budujemy „surową" komórkę Voronoi — BEZ przycinania do wyspy. Dokładne
	# przecięcie komórki z polygonem wyspy wykonuje później Map._sync_single_cell
	# natywnym Geometry2D.intersect_polygons, więc wynik końcowy jest identyczny
	# jak (base ∩ komórka), a znika koszt startowania od obrysu wyspy
	# (tysiące wierzchołków × półpłaszczyzny każdego sąsiada).

	if base_polygon.size() < 3:
		# Tryb bez maski: komórki domykają się o rect mapy — dokładnie jak dawniej.
		var poly_rect: Array[Vector2] = [
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.end,
			rect.position + Vector2(0, rect.size.y)
		]
		for n in neigh:
			poly_rect = _clip_polygon_with_bisector(poly_rect, p, n)
			if poly_rect.size() < 3:
				return PackedVector2Array()
		var poly_p := _cleanup_polygon(PackedVector2Array(poly_rect))
		if poly_p.size() < 3:
			return poly_p
		return _enforce_second_ring_bisectors(p, poly_p, neigh)

	var max_d_sqr := 0.0
	for n in neigh:
		max_d_sqr = maxf(max_d_sqr, p.distance_squared_to(n))
	var margin := sqrt(max_d_sqr) * 4.0 + 16.0

	var last := PackedVector2Array()
	for attempt in range(8):
		var poly := _rect_poly_around(p, margin)
		for n in neigh:
			poly = _clip_polygon_with_bisector(poly, p, n)
			if poly.size() < 3:
				return PackedVector2Array()
		var cleaned := _cleanup_polygon(PackedVector2Array(poly))
		if cleaned.size() < 3:
			return cleaned
		cleaned = _enforce_second_ring_bisectors(p, cleaned, neigh)
		if cleaned.size() < 3:
			return cleaned
		last = cleaned
		if not _poly_touches_margin_box(cleaned, p, margin):
			return _clip_to_base_polygon(p, cleaned)
		# Komórki hull są nieograniczone — ale gdy box pokrywa już CAŁY zasięg
		# obrysu wyspy, obcięcie boxem jest nieszkodliwe: wszystko poza wyspą
		# i tak zaraz odpadnie przy przecięciu z base polygon.
		if margin >= (p - _base_center).length() + _base_radius:
			return _clip_to_base_polygon(p, cleaned)
		margin *= 4.0

	# Ostateczność (praktycznie niewykonalna): cover-margin i pełny rebuild boxa.
	var cover := (p - _base_center).length() + _base_radius + 2.0
	var poly_fb := _rect_poly_around(p, cover)
	for n in neigh:
		poly_fb = _clip_polygon_with_bisector(poly_fb, p, n)
		if poly_fb.size() < 3:
			return _clip_to_base_polygon(p, last)
	var fb := _cleanup_polygon(PackedVector2Array(poly_fb))
	if fb.size() < 3:
		return _clip_to_base_polygon(p, last)
	return _clip_to_base_polygon(p, _enforce_second_ring_bisectors(p, fb, neigh))


## Ścisłe przecięcie komórki z obrysem wyspy natywnym clipper2 — semantyka
## identyczna jak w STARYM kodzie (base ∩ komórka), tylko w C++. Multi-części
## komórki rozpiętej nad cieśniną scalamy łańcuchowo (zero-polowe mostki), jak
## robił to stary Sutherland-Hodgman.
func _clip_to_base_polygon(p: Vector2, cell: PackedVector2Array) -> PackedVector2Array:
	if base_polygon.size() < 3 or cell.size() < 3:
		return cell
	var parts: Array = Geometry2D.intersect_polygons(cell, base_polygon)
	if parts.is_empty():
		return PackedVector2Array()
	if parts.size() == 1:
		return _cleanup_polygon(parts[0])
	var owner_i := -1
	for i in range(parts.size()):
		if Geometry2D.is_point_in_polygon(p, parts[i]):
			owner_i = i
			break
	var pieces: Array = []
	if owner_i >= 0:
		pieces.append(parts[owner_i])
	for i in range(parts.size()):
		if i != owner_i:
			pieces.append(parts[i])
	if pieces.is_empty():
		return PackedVector2Array()
	var merged: Array[Vector2] = []
	merged.append_array(pieces[0])
	for i in range(1, pieces.size()):
		merged.append(pieces[i - 1][0])   # powrotny mostek (krawędź zero-polowa)
		merged.append_array(pieces[i])
	return _cleanup_polygon(PackedVector2Array(merged))


## Natywne triangulate_delaunay pomija trójkąty zdegenerowane (slivers) — wtedy
## krawędź między dwoma site'ami znika z 1-pierścienia sąsiadów i ich komórki
## Voronoi nie są przecięte wspólną symetralną, więc NACHODZĄ na siebie.
## Walidacja drugim pierścieniem: jeśli symetralna z jakimkolwiek sąsiadem
## drugiego pierścienia realnie tnie komórkę — docinamy ją. Cięcie półpłaszczyzną
## nie-sąsiada jest matematycznie nieszkodliwe (komórka = przecięcie WSZYSTKICH
## półpłaszczyzn), więc ten pass tylko naprawia zgubione krawędzie.
func _enforce_second_ring_bisectors(p: Vector2, poly: PackedVector2Array, neigh: Array) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var seen := {p: true}
	for n in neigh:
		seen[n] = true
	var out: Array[Vector2] = []
	out.append_array(poly)
	for n in neigh:
		for m in neighbors.get(n, []):
			if m in seen:
				continue
			seen[m] = true
			if _poly_outside_bisector_halfplane(out, p, m):
				out = _clip_polygon_with_bisector(out, p, m)
				if out.size() < 3:
					return PackedVector2Array()
	return _cleanup_polygon(PackedVector2Array(out))


## true = jakiś wierzchołek leży PO ZŁEJ stronie symetralnej p–m (m bliżej niż p)
func _poly_outside_bisector_halfplane(poly: Array[Vector2], p: Vector2, m: Vector2) -> bool:
	var eps := maxf(0.01, p.distance_squared_to(m) * 0.001)
	for v in poly:
		if v.distance_squared_to(p) - v.distance_squared_to(m) > eps:
			return true
	return false


func _rect_poly_around(p: Vector2, margin: float) -> Array[Vector2]:
	return [
		p + Vector2(-margin, -margin),
		p + Vector2(margin, -margin),
		p + Vector2(margin, margin),
		p + Vector2(-margin, margin),
	]


func _poly_touches_margin_box(poly: PackedVector2Array, p: Vector2, margin: float) -> bool:
	var lim := margin - 0.01
	for v in poly:
		if absf(v.x - p.x) >= lim or absf(v.y - p.y) >= lim:
			return true
	return false

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

## Jeśli krawędzie układają się w domkniętą pętlę, zwraca jej wierzchołki
## (Array[Vector2]); w przeciwnym razie pustą tablicę.
func _ordered_loop_points(edges: Array) -> Array:
	if edges.size() < 3:
		return []
	var ordered := _order_edges_loop(edges)
	if ordered.size() != edges.size():
		return []
	for i in range(ordered.size()):
		var e = ordered[i]
		var nxt = ordered[(i + 1) % ordered.size()]
		if e.b != nxt.a:
			return []
	var out: Array = []
	for e in ordered:
		out.append(e.a)
	return out


func _poly_area(poly: Array) -> float:
	var area := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

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
	# Dokładne duplikaty odfiltrowane słownikiem — O(n) zamiast O(n^2).
	# Prawie-duplikaty (< epsilon) nie występują: generator wymusza odstępy >= 1 px.
	var seen := {}
	var out: Array[Vector2] = []
	for p in arr:
		if seen.has(p):
			continue
		seen[p] = true
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
