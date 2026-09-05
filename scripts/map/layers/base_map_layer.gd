extends Node2D
class_name BaseMapLayer

var main_ref


func set_main(main_node) -> void:
	main_ref = main_node
	queue_redraw()
