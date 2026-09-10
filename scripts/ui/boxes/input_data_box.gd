@tool
extends HBoxContainer
class_name InputDataBox

@export var box_name: StringName = ""
@export var title: String = "" : set = set_title, get = get_title
@export var placeholder: String = "" : set = set_placeholder, get = get_placeholder
@export var content: String = "" : set = set_content, get = get_content

func _ready() -> void:
	if $ContentLineEdit:
		content = $ContentLineEdit.get_text()

func set_title(trs: String) -> void:
	title = trs
	$TitleLabel.set_text(tr(title))

func get_title() -> String:
	return title

func set_placeholder(tp: String) -> void:
	placeholder = tp
	$ContentLineEdit.set_placeholder(placeholder)

func get_placeholder() -> String:
	return placeholder

func set_content(s: String) -> void:
	content = s

func get_content() -> String:
	return content

func is_same_box_name(s: StringName) -> bool:
	if box_name == s:
		return true
	return false

func _on_content_line_edit_text_changed(new_text: String) -> void:
	set_content(new_text)
