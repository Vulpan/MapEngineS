class_name DisplayModeManager
extends Node

## Menedżer trybów wyświetlania mapy.
##
## Jest w pełni niezależny od map.gd — map.gd nic o nim nie wie i dodanie
## nowego trybu NIE wymaga żadnych zmian w map.gd ani w tym pliku:
## wystarczy nowy skrypt w res://scripts/map/display_modes/modes/
## dziedziczący po MapDisplayMode (zobacz nagłówek map_display_mode.gd).
##
## SPOSÓB UŻYCIA:
##  a) W scenie: dodaj ten node jako dziecko węzła z map.gd — mapa zostanie
##     wykryta automatycznie (szukamy wśród przodków).
##  b) Z kodu:
##       var m := DisplayModeManager.new()
##       add_child(m)              # albo map.add_child(m)
##       m.setup(map_node)         # tylko gdy nie jest dzieckiem mapy
##       m.set_mode(&"political")
##
## API:
##   set_mode(id)      -> bool   aktywuje tryb (ustawia flagi + odświeża warstwy)
##   cycle_next()      -> id     następny tryb wg get_order()
##   get_mode_ids()    -> lista  id w kolejności menu
##   get_mode(id)      -> instancja trybu (np. po display_name)
##   register_mode(m)           ręczne dodanie trybu spoza katalogu modes/
##
## Domyślnie tryby przełączane są też klawiszem M (cycle_key); ustaw
## KEY_NONE, żeby wyłączyć.

signal mode_changed(id: StringName, display_name: String)

@export var auto_discover := true
@export var modes_directory := "res://scripts/map/display_modes/modes/"
## Czy na starcie od razu zastosować initial_mode (false = nic nie zmieniaj,
## dopóki ktoś nie wywoła set_mode/cycle_next).
@export var apply_on_ready := false
@export var initial_mode: StringName = &"default"
@export var cycle_key: Key = Key.KEY_M

var map: Map
## StringName -> MapDisplayMode
var modes: Dictionary = {}
var current_id: StringName = &""


func _ready() -> void:
	if map == null:
		var node := get_parent()
		while node != null:
			if node is Map:
				map = node
				break
			node = node.get_parent()
	if auto_discover:
		discover_modes()
	if apply_on_ready and modes.has(initial_mode):
		set_mode(initial_mode)


func setup(p_map: Map) -> void:
	map = p_map


## Skanuje katalog trybów i rejestruje wszystko, co dziedziczy
## po MapDisplayMode. Wywoływane automatycznie w _ready().
func discover_modes(directory: String = "") -> void:
	if directory.is_empty():
		directory = modes_directory
	modes.clear()

	var dir := DirAccess.open(directory)
	if dir == null:
		push_warning("DisplayModeManager: brak katalogu trybów: " + directory)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var script: GDScript = load(directory + file_name)
			if script != null and script.can_instantiate():
				var candidate = script.new()
				if candidate is MapDisplayMode and candidate.get_id() != &"base":
					register_mode(candidate)
		file_name = dir.get_next()
	dir.list_dir_end()


func register_mode(mode: MapDisplayMode) -> void:
	if mode == null or modes.has(mode.get_id()):
		return
	modes[mode.get_id()] = mode


## Aktywuje tryb: ustawia pełny stan flag i odświeża warstwy mapy.
func set_mode(id: StringName) -> bool:
	if not modes.has(id):
		push_warning("DisplayModeManager: nieznany tryb: " + String(id))
		return false
	if map == null:
		push_warning("DisplayModeManager: mapa nieustawiona (setup()/rodzic)")
		return false

	var mode: MapDisplayMode = modes[id]
	mode.apply_display(map)
	current_id = id
	_refresh_map()
	mode_changed.emit(id, mode.get_display_name())
	print("[DisplayMode] ", mode.get_display_name())
	return true


## Przełącza na następny tryb wg get_order() (po ostatnim wraca na pierwszy).
func cycle_next() -> StringName:
	var ordered := get_mode_ids()
	if ordered.is_empty():
		return &""
	var idx := 0
	if current_id != &"":
		idx = ordered.find(current_id)
		if idx == -1:
			idx = 0
	idx = (idx + 1) % ordered.size()
	set_mode(ordered[idx])
	return current_id


## Identyfikatory trybów w kolejności menu (order rosnąco, potem alfabetycznie).
func get_mode_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	var list: Array = modes.values()
	list.sort_custom(func(a: MapDisplayMode, b: MapDisplayMode):
		if a.get_order() != b.get_order():
			return a.get_order() < b.get_order()
		return String(a.get_id()) < String(b.get_id()))
	for mode in list:
		result.append(mode.get_id())
	return result


func get_mode(id: StringName) -> MapDisplayMode:
	return modes.get(id, null)


func get_current_id() -> StringName:
	return current_id


func get_current_display_name() -> String:
	var mode := get_mode(current_id)
	return mode.get_display_name() if mode != null else ""


func _refresh_map() -> void:
	if map == null:
		return
	map.update_layers()
	# chunk_draw_mode może się zmienić — przeładuj chunki i warstwę wody
	if map.has_method("_apply_chunk_draw_mode"):
		map._apply_chunk_draw_mode()


func _unhandled_input(event: InputEvent) -> void:
	if cycle_key == Key.KEY_NONE:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == cycle_key:
		cycle_next()
