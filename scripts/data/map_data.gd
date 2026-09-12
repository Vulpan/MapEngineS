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


#func create_region(name: String = "") -> RegionData:
	#var region := RegionData.new(next_region_id, name)
	#regions[region.id] = region
	#next_region_id += 1
	#return region

func create_region(
	name: String = "", 
	level: int = -1, 
	parent: int = -1, 
	red: float = 0.0, 
	green: float = 0.0, 
	blue: float = 0.0
	) -> RegionData:
	var region := RegionData.new(next_region_id, name, level, parent, red, green, blue)
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


## Kolumnowy (SoA) payload binarny — bez kluczy-stringów per komórka,
## z natywnymi typami (PackedVector2Array itd.). store_var to skompresuje
## dobrze i odczyta natychmiastowo (bez parsera tekstu).
func to_binary_payload() -> Dictionary:
	var ids := PackedInt32Array()
	var sites := PackedVector2Array()
	var doms := PackedByteArray()
	var comps := PackedInt32Array()
	var regs := PackedInt32Array()
	var flags := PackedByteArray()

	var poly_flat := PackedFloat32Array()
	var poly_off := PackedInt32Array()
	var neigh_flat := PackedInt32Array()
	var neigh_off := PackedInt32Array()
	var coastal_flat := PackedInt32Array()
	var coastal_off := PackedInt32Array()

	var meta_idx := PackedInt32Array()
	var meta_arr: Array = []

	for id in cells.keys():
		var c: CellData = cells[id]
		ids.append(id)
		sites.append(c.site)
		doms.append(c.domain)
		comps.append(c.component_id)
		regs.append(c.region_id)
		var f := 0
		if c.is_land: f |= 1
		if c.is_water: f |= 2
		if c.is_coastal: f |= 4
		flags.append(f)

		poly_off.append(poly_flat.size())
		for v in c.polygon:
			poly_flat.append(v.x)
			poly_flat.append(v.y)

		neigh_off.append(neigh_flat.size())
		for n in c.neighbor_ids:
			neigh_flat.append(n)

		coastal_off.append(coastal_flat.size())
		for n in c.coastal_neighbor_ids:
			coastal_flat.append(n)

		if not c.meta.is_empty():
			meta_idx.append(ids.size() - 1)
			meta_arr.append(c.meta.duplicate(true))

	poly_off.append(poly_flat.size())
	neigh_off.append(neigh_flat.size())
	coastal_off.append(coastal_flat.size())

	var reg_ids := PackedInt32Array()
	var reg_names := PackedStringArray()
	var reg_levels := PackedInt32Array()
	var reg_parents := PackedInt32Array()
	var reg_red := PackedFloat32Array()
	var reg_green := PackedFloat32Array()
	var reg_blue := PackedFloat32Array()
	var reg_flat := PackedInt32Array()
	var reg_off := PackedInt32Array()
	var reg_meta: Array = []
	for rid in regions.keys():
		var r: RegionData = regions[rid]
		reg_ids.append(rid)
		reg_names.append(r.name)
		reg_levels.append(r.level)
		reg_parents.append(r.parent)
		reg_red.append(r.color.r)
		reg_green.append(r.color.g)
		reg_blue.append(r.color.b)
		reg_off.append(reg_flat.size())
		for cid in r.cell_ids:
			reg_flat.append(cid)
		reg_meta.append(r.meta.duplicate(true))
	reg_off.append(reg_flat.size())

	return {
		"version": 1,
		"bounds": bounds,
		"next_cell_id": next_cell_id,
		"next_region_id": next_region_id,
		"cell_ids": ids,
		"cell_sites": sites,
		"cell_domain": doms,
		"cell_component": comps,
		"cell_region": regs,
		"cell_flags": flags,
		"poly_flat": poly_flat,
		"poly_off": poly_off,
		"neigh_flat": neigh_flat,
		"neigh_off": neigh_off,
		"coastal_flat": coastal_flat,
		"coastal_off": coastal_off,
		"meta_idx": meta_idx,
		"meta_arr": meta_arr,
		"reg_ids": reg_ids,
		"reg_names": reg_names,
		"reg_levels": reg_levels,
		"reg_parents": reg_parents,
		"reg_red": reg_red,
		"reg_green": reg_green,
		"reg_blue": reg_blue,
		"reg_flat": reg_flat,
		"reg_off": reg_off,
		"reg_meta": reg_meta,
	}


func from_binary_payload(d: Dictionary) -> void:
	clear()
	version = int(d.get("version", 2))
	bounds = d.get("bounds", Rect2())
	next_cell_id = int(d.get("next_cell_id", 1))
	next_region_id = int(d.get("next_region_id", 1))

	var ids: PackedInt32Array = d.get("cell_ids", PackedInt32Array())
	var sites: PackedVector2Array = d.get("cell_sites", PackedVector2Array())
	var doms: PackedByteArray = d.get("cell_domain", PackedByteArray())
	var comps: PackedInt32Array = d.get("cell_component", PackedInt32Array())
	var regs: PackedInt32Array = d.get("cell_region", PackedInt32Array())
	var flags: PackedByteArray = d.get("cell_flags", PackedByteArray())
	var poly_flat: PackedFloat32Array = d.get("poly_flat", PackedFloat32Array())
	var poly_off: PackedInt32Array = d.get("poly_off", PackedInt32Array())
	var neigh_flat: PackedInt32Array = d.get("neigh_flat", PackedInt32Array())
	var neigh_off: PackedInt32Array = d.get("neigh_off", PackedInt32Array())
	var coastal_flat: PackedInt32Array = d.get("coastal_flat", PackedInt32Array())
	var coastal_off: PackedInt32Array = d.get("coastal_off", PackedInt32Array())
	var meta_idx: PackedInt32Array = d.get("meta_idx", PackedInt32Array())
	var meta_arr: Array = d.get("meta_arr", [])

	var meta_map := {}
	for i in range(meta_idx.size()):
		meta_map[meta_idx[i]] = meta_arr[i]

	for i in range(ids.size()):
		var c := CellData.new(ids[i], sites[i])
		c.domain = doms[i]
		c.component_id = comps[i]
		c.region_id = regs[i]
		c.is_land = (flags[i] & 1) != 0
		c.is_water = (flags[i] & 2) != 0
		c.is_coastal = (flags[i] & 4) != 0

		var poly := PackedVector2Array()
		var start := poly_off[i]
		var stop := poly_off[i + 1]
		poly.resize(int((stop - start) / 2.0))
		for j in range(start, stop, 2):
			poly[int((j - start) / 2.0)] = Vector2(poly_flat[j], poly_flat[j + 1])
		c.polygon = poly

		var ns := neigh_off[i]
		var ne := neigh_off[i + 1]
		var narr: Array[int] = []
		narr.resize(ne - ns)
		for j in range(ne - ns):
			narr[j] = neigh_flat[ns + j]
		c.neighbor_ids = narr

		var cs := coastal_off[i]
		var ce := coastal_off[i + 1]
		var carr: Array[int] = []
		carr.resize(ce - cs)
		for j in range(ce - cs):
			carr[j] = coastal_flat[cs + j]
		c.coastal_neighbor_ids = carr

		if meta_map.has(i):
			c.meta = meta_map[i].duplicate(true)

		cells[c.id] = c

	var reg_ids: PackedInt32Array = d.get("reg_ids", PackedInt32Array())
	var reg_names: PackedStringArray = d.get("reg_names", PackedStringArray())
	var reg_levels: PackedInt32Array = d.get("reg_levels", PackedInt32Array())
	var reg_parents: PackedInt32Array = d.get("reg_parents", PackedInt32Array())
	var reg_red: PackedFloat32Array = d.get("reg_red", PackedFloat32Array())
	var reg_green: PackedFloat32Array = d.get("reg_green", PackedFloat32Array())
	var reg_blue: PackedFloat32Array = d.get("reg_blue", PackedFloat32Array())
	var reg_flat: PackedInt32Array = d.get("reg_flat", PackedInt32Array())
	var reg_off: PackedInt32Array = d.get("reg_off", PackedInt32Array())
	var reg_meta: Array = d.get("reg_meta", [])
	for i in range(reg_ids.size()):
		var r := RegionData.new(
			reg_ids[i],
			reg_names[i],
			reg_levels[i],
			reg_parents[i],
			reg_red[i],
			reg_green[i],
			reg_blue[i]
		)
		var rs := reg_off[i]
		var re := reg_off[i + 1]
		for j in range(rs, re):
			r.cell_ids.append(reg_flat[j])
		if i < reg_meta.size():
			r.meta = reg_meta[i].duplicate(true)
		regions[r.id] = r


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
