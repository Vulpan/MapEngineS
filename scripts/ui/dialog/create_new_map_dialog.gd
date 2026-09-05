class_name CreateNewMapDialog
extends PopupPanel

var ui_canvas: CanvasLayer = null
var map: Map = null

var map_name: String = ""
var picture_path: String = ""
var border_path: String = ""

@onready var selected_picture_path_line: LineEdit = $VBoxContainer/PictureBox/SelectedPicturePathLine
@onready var select_picture_button: Button = $VBoxContainer/PictureBox/SelectPictureButton
@onready var border_selected_picture_path_line: LineEdit = $VBoxContainer/BorderPictureBox/BorderSelectedPicturePathLine
@onready var borderSelect_picture_button: Button = $VBoxContainer/BorderPictureBox/BorderSelectPictureButton

@onready var border_warning_label: Label = $VBoxContainer/BorderWarningLabel
@onready var picture_checkbox: CheckBox = $VBoxContainer/PictureBox/PictureCheckbox
@onready var border_picture_checkbox: CheckBox = $VBoxContainer/BorderPictureBox/BorderPictureCheckbox
@onready var height_line_edit: LineEdit = $VBoxContainer/MapSizeBox/HeightLineEdit
@onready var width_line_edit: LineEdit = $VBoxContainer/MapSizeBox/WidthLineEdit
@onready var map_render_spin_box: SpinBox = $VBoxContainer/MapRenderScale/MapRenderSpinBox

func _ready() -> void:
	ui_canvas = get_tree().get_first_node_in_group("UICanvasLayer")
	map = get_tree().get_first_node_in_group("Map")
	
	_on_picture_checkbox_toggled(picture_checkbox.button_pressed)
	_on_border_picture_checkbox_toggled(border_picture_checkbox.button_pressed)
	border_picture_checkbox.set_disabled(true)


func _on_select_picture_button_pressed(type: int) -> void:
	var file_dialog = FileDialog.new()
	file_dialog.set_file_mode(FileDialog.FILE_MODE_OPEN_FILE)
	ui_canvas.add_child(file_dialog)
	file_dialog.get_cancel_button().pressed.connect(_remove_dialog.bind(file_dialog))
	file_dialog.get_ok_button().pressed.connect(_on_confirm_pictrue_dialog_button_pressed.bind(file_dialog, type))
	file_dialog.current_path = "res://assets/map/"
	file_dialog.set_filters(PackedStringArray(["*.png,*.jpg,*.jpeg;Image Files;image/png,image/jpeg]"]))
	file_dialog.popup_centered_clamped()


func _on_confirm_button_pressed() -> void:
	var height = height_line_edit.get_text()
	var width = width_line_edit.get_text()
	var map_scale = map_render_spin_box.get_value()
	
	if map_name.is_empty():
		return
	
	if not picture_checkbox.button_pressed:
		if height.is_empty() or width.is_empty():
			return
	
	var dict: Dictionary = {
		"map_name": map_name,
		"picture_path": picture_path,
		"border_path": border_path,
		"height": height,
		"width": width, 
		"map_scale": map_scale
	}
	
	map.create_new_map(dict)
	hide()
	_remove_dialog(self)


func _on_cancel_button_pressed() -> void:
	hide()
	_remove_dialog(self)


func _confirm_file() -> void:
	pass


func _remove_dialog(dialog: Window) -> void:
	dialog.queue_free()


func _on_map_name_line_edit_text_changed(new_text: String) -> void:
	map_name = new_text


func _on_picture_checkbox_toggled(toggled_on: bool) -> void:
	if toggled_on:
		selected_picture_path_line.editable = toggled_on
		select_picture_button.set_disabled(not toggled_on)
		border_picture_checkbox.set_disabled(false)
		height_line_edit.set_editable(false)
		width_line_edit.set_editable(false)
	else:
		_on_border_picture_checkbox_toggled(toggled_on)
		selected_picture_path_line.editable = toggled_on
		select_picture_button.set_disabled(not toggled_on)
		border_picture_checkbox.set_disabled(true)
		border_picture_checkbox.button_pressed = false
		height_line_edit.set_editable(true)
		width_line_edit.set_editable(true)


func _on_border_picture_checkbox_toggled(toggled_on: bool) -> void:
	if toggled_on:
		border_selected_picture_path_line.editable = toggled_on
		borderSelect_picture_button.set_disabled(not toggled_on)
		border_warning_label.show()
	else:
		border_selected_picture_path_line.editable = toggled_on
		borderSelect_picture_button.set_disabled(not toggled_on)
		border_warning_label.hide()


func _on_confirm_pictrue_dialog_button_pressed(dialog: FileDialog, type: int) -> void:
	match type:
		0:
			picture_path = dialog.get_current_path()
			selected_picture_path_line.set_text(picture_path)
			var img = ResourceLoader.load(picture_path)
			height_line_edit.set_text(str(img.get_height()))
			width_line_edit.set_text(str(img.get_width()))
		1:
			border_path = dialog.get_current_path()
			border_selected_picture_path_line.set_text(border_path)
	
	_remove_dialog(dialog)
	await get_tree().process_frame
	await get_tree().process_frame
	hide()
	popup_centered_clamped()


func _on_same_size_check_box_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var height = height_line_edit.get_text()
		var width = width_line_edit.get_text()
		if height.is_empty():
			height = str(0.0)
		if width.is_empty():
			width = str(0.0)
		
		var new_size = str(0.0)
		if height >= width:
			new_size = height
		else:
			new_size = width
		
		height_line_edit.set_text(new_size)
		width_line_edit.set_text(new_size)
	
	else:
		if not picture_path.is_empty():
			var img = Image.new()
			img.load(picture_path)
			height_line_edit.set_text(str(img.get_height()))
			width_line_edit.set_text(str(img.get_width()))
