extends Resource
class_name RegionData


var id: int = -1
var name: String = ""
var level: int = -1
var parent: int
var cell_ids: Array[int] = []
var meta: Dictionary = {}


func _init(_id: int = -1, _name: String = "", _level: int = -1, _parent: int = -1) -> void:
	id = _id
	name = _name
	level = _level
	parent = _parent


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"level": level,
		"parent": parent,
		"cell_ids": cell_ids.duplicate(),
		"meta": meta.duplicate(true)
	}


static func from_dict(data: Dictionary) -> RegionData:
	var r := RegionData.new(
		data.get("id", -1),
		data.get("name", ""),
		data.get("level", -1),
		data.get("parent", -1)
	)
	
	r.cell_ids.clear()
	for value in data.get("cell_ids", []):
		r.cell_ids.append(int(value))
	
	r.meta = data.get("meta", {}).duplicate(true)
	return r
