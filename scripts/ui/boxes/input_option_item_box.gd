@tool
extends HBoxContainer
class_name InputOptionItemBox

signal value_changed(id: int)

@export var box_name: StringName = ""
@export var title: String = "" : set = set_title, get = get_title
@export var content: Array[int] = [] : set = set_content, get = get_content
@export var selected_option: int = -1 : set = _set_selected_option, get = get_selected_option

func set_title(trs: String) -> void:
	title = trs
	$TitleLabel.set_text(tr(title))

func get_title() -> String:
	return title

func set_content(ai: Array[int]) -> void:
	content = ai
	$OptionButton.clear()
	for i in content:
		$OptionButton.add_item(str(i))
	if content.size() > 0:
		$OptionButton.select(0)
		_set_selected_option(content[0])

func get_content() -> Array[int]:
	return content

func is_same_box_name(s: StringName) -> bool:
	if box_name == s:
		return true
	return false


func _set_selected_option(value: int) -> void:
	selected_option = value
	value_changed.emit(selected_option)

func get_selected_option() -> int:
	return selected_option

func clear() -> void:
	$OptionButton.clear()

func _on_option_button_item_selected(index: int) -> void:
	_set_selected_option(get_content()[index])
	
