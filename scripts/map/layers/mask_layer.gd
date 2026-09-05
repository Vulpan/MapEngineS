extends BaseMapLayer
class_name MaskLayer


func _draw() -> void:
	if main_ref == null:
		return
	
	if not main_ref.draw_land_mask_outline:
		return
	
	if not main_ref.use_land_mask:
		return
	
	if main_ref.land_mask_processor == null:
		return
	
	for poly in main_ref.land_mask_processor.land_polygons:
		if poly.size() < 2:
			continue
		
		for i in range(poly.size()):
			var a = poly[i]
			var b = poly[(i + 1) % poly.size()]
			draw_line(a, b, Color.BLACK, 2.0)
