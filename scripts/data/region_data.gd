extends Resource
class_name RegionData


var id: int = -1
var name: String = ""
var level: int = -1
var parent: int
var color: Color = Color.BLACK
var capital_cell_id: int = -1
var cell_ids: Array[int] = []
var meta: Dictionary = {}


func _init(_id: int = -1, _name: String = "", _level: int = -1, _parent: int = -1, _red: float = 0.0, _green: float = 0.0, _blue: float = 0.0, _cap_cell_id: int = -1) -> void:
	id = _id
	name = _name
	level = _level
	parent = _parent
	color = Color(_red, _green, _blue)
	capital_cell_id = _cap_cell_id


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


## Czy region należy do poziomu 1 — najniższego poziomu podziału
## administracyjnego (poziom liścia, właściciel komórek).
## Poziom 1 = region z jawnie ustawionym level == 1. Region bez przypisanego
## poziomu (level <= 0) traktujemy jako poziom 1 tylko wtedy, gdy posiada
## komórki — tak powstają regiony tworzone bezpośrednio w edytorze
## (create_region domyślnie daje level = -1).
func is_admin_level1() -> bool:
	return is_admin_level(1)


## Czy region należy do podanego poziomu administracyjnego.
## lvl <= 1: patrz is_admin_level1(). lvl >= 2: wyłącznie level == lvl
## (poziomy wyższe mają zawsze jawnie ustawiony level).
func is_admin_level(lvl: int) -> bool:
	if lvl <= 1:
		return level == 1 or (level <= 0 and not cell_ids.is_empty())
	return level == lvl
