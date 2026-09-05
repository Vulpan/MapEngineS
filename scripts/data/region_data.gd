extends Resource
class_name RegionData

var id: int = -1
var name: String = ""
var cell_ids: Array[int] = []
var meta: Dictionary = {}


func _init(_id: int = -1, _name: String = "") -> void:
	id = _id
	name = _name


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"cell_ids": cell_ids.duplicate(),
		"meta": meta.duplicate(true)
	}


static func from_dict(data: Dictionary) -> RegionData:
	var r := RegionData.new(
		data.get("id", -1),
		data.get("name", "")
	)
	
	r.cell_ids.clear()
	for value in data.get("cell_ids", []):
		r.cell_ids.append(int(value))
	
	r.meta = data.get("meta", {}).duplicate(true)
	return r
