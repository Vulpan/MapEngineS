@tool
extends HBoxContainer
class_name InputNumberDataBox

@export var box_name: StringName = ""
@export var title: String = "" : set = set_title, get = get_title
@export var content: int = 1: set = set_content, get = get_content
@export var blocked: bool = false: set = set_blockade

func set_title(trs: String) -> void:
	title = trs
	$TitleLabel.set_text(tr(title))

func get_title() -> String:
	return title

func set_content(s: int) -> void:
	content = s
	if $SpinBox.value != content:
		$SpinBox.set_value(content)

func get_content() -> int:
	return content

func is_same_box_name(s: StringName) -> bool:
	if box_name == s:
		return true
	return false

func set_blockade(value: bool) -> void:
	blocked = value
	if blocked:
		$SpinBox.set_editable(false)
	else:
		$SpinBox.set_editable(true)

func _on_spin_box_value_changed(value: float) -> void:
	set_content(int(value))
