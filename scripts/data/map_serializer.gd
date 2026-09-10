extends RefCounted
class_name MapSerializer

# Format binarny (wersja 2): pojedynczy plik z nagłówkiem + skompresowany Variant
# (kolumnowy payload MapData).
const BIN_MAGIC := 0x4D415042  # "MAPB"
const BIN_VERSION := 2


static func save_to_binary(path: String, map_data: MapData) -> bool:
	# Zapis atomowy: plik tymczasowy -> rename (nigdy nie zostaje ucięty plik).
	# Uwaga: open_compressed zarządza własnymi blokami, więc nagłówek też piszemy
	# przez strumień skompresowany (kilka bajtów — bez znaczenia dla rozmiaru).
	var tmp_path := path + ".tmp"
	var out := FileAccess.open_compressed(
		tmp_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD
	)
	if out == null:
		push_error("Cannot open file for writing: " + tmp_path)
		return false
	out.store_32(BIN_MAGIC)
	out.store_16(BIN_VERSION)
	out.store_16(0)  # flags, zarezerwowane
	out.store_var(map_data.to_binary_payload(), true)
	out.close()

	DirAccess.rename_absolute(tmp_path, path)
	return true


static func load_from_binary(path: String) -> MapData:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open_compressed(
		path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		push_error("Cannot open binary map: " + path)
		return null

	var magic := file.get_32()
	if magic != BIN_MAGIC:
		push_error("Bad magic in binary map: " + path)
		return null
	var version := file.get_16()
	if version != BIN_VERSION:
		push_error("Unsupported map.bin version %d in %s" % [version, path])
		return null
	file.get_16()  # flags

	var payload = file.get_var(true)
	if typeof(payload) != TYPE_DICTIONARY:
		push_error("Corrupted binary payload in: " + path)
		return null

	var map_data := MapData.new()
	map_data.from_binary_payload(payload)
	return map_data
