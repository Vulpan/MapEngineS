extends RefCounted
class_name SpatialHash2D

## Lekki indeks przestrzenny typu "hash grid" dla punktów 2D.
## Zapytania promieniowe zależą od lokalnej gęstości punktów, a nie od ich liczby.
## Klucze (id) mogą być dowolnego typu — pozycja jest zapamiętywana wewnętrznie.

var bucket_size: float = 32.0

var positions: Dictionary = {}  # id -> Vector2
var buckets: Dictionary = {}    # Vector2i -> Array (id)


func _init(p_bucket_size: float = 32.0) -> void:
	bucket_size = maxf(p_bucket_size, 0.001)


func size() -> int:
	return positions.size()


func clear() -> void:
	positions.clear()
	buckets.clear()


func has(id) -> bool:
	return positions.has(id)


func get_position(id) -> Vector2:
	return positions.get(id, Vector2.ZERO)


func insert(id, pos: Vector2) -> void:
	if positions.has(id):
		remove(id)
	positions[id] = pos
	var k := _bucket_key(pos)
	if not buckets.has(k):
		buckets[k] = []
	buckets[k].append(id)


func remove(id) -> void:
	if not positions.has(id):
		return
	var k := _bucket_key(positions[id])
	positions.erase(id)
	if buckets.has(k):
		buckets[k].erase(id)
		if (buckets[k] as Array).is_empty():
			buckets.erase(k)


func move(id, new_pos: Vector2) -> void:
	if not positions.has(id):
		insert(id, new_pos)
		return
	var old_k := _bucket_key(positions[id])
	var new_k := _bucket_key(new_pos)
	positions[id] = new_pos
	if old_k != new_k:
		if buckets.has(old_k):
			buckets[old_k].erase(id)
			if (buckets[old_k] as Array).is_empty():
				buckets.erase(old_k)
		if not buckets.has(new_k):
			buckets[new_k] = []
		buckets[new_k].append(id)


func has_point_within(pos: Vector2, radius: float) -> bool:
	var r_sqr := radius * radius
	var x0 := floori((pos.x - radius) / bucket_size)
	var y0 := floori((pos.y - radius) / bucket_size)
	var x1 := floori((pos.x + radius) / bucket_size)
	var y1 := floori((pos.y + radius) / bucket_size)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var k := Vector2i(gx, gy)
			if not buckets.has(k):
				continue
			for id in buckets[k]:
				if (positions[id] as Vector2).distance_squared_to(pos) <= r_sqr:
					return true
	return false


## Zwraca id najbliższego punktu w promieniu albo null (brak kandydatów).
func find_nearest_within(pos: Vector2, radius: float) -> Variant:
	var r_sqr := radius * radius
	var best = null
	var best_d := INF
	var x0 := floori((pos.x - radius) / bucket_size)
	var y0 := floori((pos.y - radius) / bucket_size)
	var x1 := floori((pos.x + radius) / bucket_size)
	var y1 := floori((pos.y + radius) / bucket_size)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var k := Vector2i(gx, gy)
			if not buckets.has(k):
				continue
			for id in buckets[k]:
				var d := (positions[id] as Vector2).distance_squared_to(pos)
				if d < best_d and d <= r_sqr:
					best_d = d
					best = id
	return best


func query_radius(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var r_sqr := radius * radius
	var x0 := floori((pos.x - radius) / bucket_size)
	var y0 := floori((pos.y - radius) / bucket_size)
	var x1 := floori((pos.x + radius) / bucket_size)
	var y1 := floori((pos.y + radius) / bucket_size)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var k := Vector2i(gx, gy)
			if not buckets.has(k):
				continue
			for id in buckets[k]:
				if (positions[id] as Vector2).distance_squared_to(pos) <= r_sqr:
					out.append(id)
	return out


func _bucket_key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / bucket_size), floori(pos.y / bucket_size))
