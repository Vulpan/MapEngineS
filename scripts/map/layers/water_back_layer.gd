extends Node2D
class_name WaterBackLayer

## Rysuje poligon wypełniony wszystkich komórek WODNYCH pod całą resztą warstw.
## Problem, który to rozwiązuje: chunki są siblingami CanvasItem — Godot rysuje je
## w kolejności drzewa, więc "woda najpierw, ląd na wierzchu" obowiązywało tylko
## W OBRĘBIE jednego chunka; woda z późniejszego chunka zasłaniała ląd wcześniejszego.
## Komórki wodne są małoliczne, więc jeden _draw() bez chunkowania wystarcza.

var main_ref

const WATER_COLOR := Color(0.16, 0.35, 0.72, 0.30)


func set_main(main_node) -> void:
	main_ref = main_node


func _draw() -> void:
	if main_ref == null or main_ref.map_data == null:
		return
	for cell_id in main_ref.map_data.cells.keys():
		var cell: CellData = main_ref.map_data.cells[cell_id]
		if cell.domain != CellData.DOMAIN_WATER:
			continue
		if cell.polygon.size() < 3:
			continue
		draw_colored_polygon(cell.polygon, WATER_COLOR)
