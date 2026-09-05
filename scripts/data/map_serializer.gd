extends RefCounted
class_name MapSerializer

static func save_to_json(path: String, map_data: MapData) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open file for writing: " + path)
		return false
	
	file.store_string(JSON.stringify(map_data.to_dict(), "\t"))
	return true

static func load_from_json(path: String) -> MapData:
	if not FileAccess.file_exists(path):
		push_error("File does not exist: " + path)
		return null
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open file for reading: " + path)
		return null
	
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse error in file: " + path)
		return null
	
	var map_data := MapData.new()
	map_data.from_dict(json.data)
	return map_data
