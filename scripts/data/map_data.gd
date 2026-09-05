extends Resource
class_name MapData

var version: int = 1
var bounds: Rect2 = Rect2()

var next_cell_id: int = 1
var next_region_id: int = 1

var cells: Dictionary = {}   # int -> CellData
var regions: Dictionary = {} # int -> RegionData


func clear() -> void:
	cells.clear()
	regions.clear()
	next_cell_id = 1
	next_region_id = 1


func create_cell(site: Vector2) -> CellData:
	var cell := CellData.new(next_cell_id, site)
	cells[cell.id] = cell
	next_cell_id += 1
	return cell


func remove_cell(cell_id: int) -> void:
	if not cells.has(cell_id):
		return
	
	for other_id in cells.keys():
		var cell: CellData = cells[other_id]
		cell.neighbor_ids.erase(cell_id)
	
	for region_id in regions.keys():
		var region: RegionData = regions[region_id]
		region.cell_ids.erase(cell_id)
	
	cells.erase(cell_id)


func get_cell(cell_id: int) -> CellData:
	return cells.get(cell_id, null)


func get_cell_ids() -> Array:
	return cells.keys()


func create_region(name: String = "") -> RegionData:
	var region := RegionData.new(next_region_id, name)
	regions[region.id] = region
	next_region_id += 1
	return region


func remove_region(region_id: int) -> void:
	if not regions.has(region_id):
		return
	
	for cell_id in regions[region_id].cell_ids:
		if cells.has(cell_id):
			var cell: CellData = cells[cell_id]
			if cell.region_id == region_id:
				cell.region_id = -1
	
	regions.erase(region_id)


func get_region(region_id: int) -> RegionData:
	return regions.get(region_id, null)


func assign_cell_to_region(cell_id: int, region_id: int) -> void:
	if not cells.has(cell_id):
		return
	if not regions.has(region_id):
		return
	
	var cell: CellData = cells[cell_id]
	
	if cell.region_id != -1 and regions.has(cell.region_id):
		regions[cell.region_id].cell_ids.erase(cell_id)
	
	cell.region_id = region_id
	
	if cell_id not in regions[region_id].cell_ids:
		regions[region_id].cell_ids.append(cell_id)


func unassign_cell_from_region(cell_id: int) -> void:
	if not cells.has(cell_id):
		return
	
	var cell: CellData = cells[cell_id]
	if cell.region_id != -1 and regions.has(cell.region_id):
		regions[cell.region_id].cell_ids.erase(cell_id)
	cell.region_id = -1


func to_dict() -> Dictionary:
	var cell_arr: Array = []
	for id in cells.keys():
		var c: CellData = cells[id]
		cell_arr.append(c.to_dict())
	
	var region_arr: Array = []
	for id in regions.keys():
		var r: RegionData = regions[id]
		region_arr.append(r.to_dict())
	
	return {
		"version": version,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"next_cell_id": next_cell_id,
		"next_region_id": next_region_id,
		"cells": cell_arr,
		"regions": region_arr
	}


func from_dict(data: Dictionary) -> void:
	clear()
	version = int(data.get("version", 1))
	
	var b = data.get("bounds", [0, 0, 0, 0])
	if b.size() >= 4:
		bounds = Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	
	next_cell_id = int(data.get("next_cell_id", 1))
	next_region_id = int(data.get("next_region_id", 1))
	
	for cell_data in data.get("cells", []):
		var cell := CellData.from_dict(cell_data)
		cells[cell.id] = cell
	
	for region_data in data.get("regions", []):
		var region := RegionData.from_dict(region_data)
		regions[region.id] = region
