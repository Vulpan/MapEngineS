extends Resource
class_name CellData

const DOMAIN_LAND := 0
const DOMAIN_WATER := 1

var id: int = -1
var site: Vector2 = Vector2.ZERO
var polygon: PackedVector2Array = PackedVector2Array()

var neighbor_ids: Array[int] = []
var coastal_neighbor_ids: Array[int] = []

var region_id: int = -1
var meta: Dictionary = {}

var domain: int = DOMAIN_LAND
var component_id: int = -1

var is_land: bool = true
var is_water: bool = false
var is_coastal: bool = false


func _init(_id: int = -1, _site: Vector2 = Vector2.ZERO) -> void:
	id = _id
	site = _site


func to_dict() -> Dictionary:
	return {
		"id": id,
		"site": [site.x, site.y],
		"polygon": _polygon_to_array(polygon),
		"neighbor_ids": neighbor_ids.duplicate(),
		"coastal_neighbor_ids": coastal_neighbor_ids.duplicate(),
		"region_id": region_id,
		"meta": meta.duplicate(true),
		"domain": domain,
		"component_id": component_id,
		"is_land": is_land,
		"is_water": is_water,
		"is_coastal": is_coastal
	}


static func from_dict(data: Dictionary) -> CellData:
	var c := CellData.new(
		data.get("id", -1),
		_array_to_vec2(data.get("site", [0.0, 0.0]))
	)
	
	c.polygon = _array_to_polygon(data.get("polygon", []))
	
	c.neighbor_ids.clear()
	for value in data.get("neighbor_ids", []):
		c.neighbor_ids.append(int(value))
	
	c.coastal_neighbor_ids.clear()
	for value in data.get("coastal_neighbor_ids", []):
		c.coastal_neighbor_ids.append(int(value))
	
	c.region_id = int(data.get("region_id", -1))
	c.meta = data.get("meta", {}).duplicate(true)
	c.domain = int(data.get("domain", DOMAIN_LAND))
	c.component_id = int(data.get("component_id", -1))
	c.is_land = bool(data.get("is_land", c.domain == DOMAIN_LAND))
	c.is_water = bool(data.get("is_water", c.domain == DOMAIN_WATER))
	c.is_coastal = bool(data.get("is_coastal", false))
	return c


static func _polygon_to_array(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly:
		out.append([p.x, p.y])
	return out


static func _array_to_polygon(arr: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for item in arr:
		poly.append(_array_to_vec2(item))
	return poly


static func _array_to_vec2(arr: Array) -> Vector2:
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO
