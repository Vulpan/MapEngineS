@tool
extends MarginContainer
class_name DataBox

@export var box_name: StringName = ""
@export var title: String = "" : set = set_title, get = get_title
@export var content: String = "" : set = set_content, get = get_content

func set_title(trs: String) -> void:
	title = trs
	$HBox/TitleLabel.set_text(tr(title))

func get_title() -> String:
	return title

func set_content(s: String) -> void:
	content = s
	$HBox/DataLabel.set_text(content)

func get_content() -> String:
	return content

func is_same_box_name(s: StringName) -> bool:
	if box_name == s:
		return true
	return false
