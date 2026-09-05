extends MenuBar

@onready var ui: CanvasLayer = $"../.."
@onready var map: Map = $"../../../Map"
@onready var file_pm: PopupMenu = $file
@onready var edit_pm: PopupMenu = $edit

func _ready() -> void:
	_setup_file_popup_menu()


func _setup_file_popup_menu() -> void:
	file_pm.add_item(tr("new"), 0)
	file_pm.add_item(tr("load"), 1)
	file_pm.add_item(tr("save"), 2)
	file_pm.id_pressed.connect(_on_file_menu_selected)


func _on_file_menu_selected(id: int) -> void:
	match id:
		0: # New
			var cnmd: CreateNewMapDialog = load("uid://bf7qte8cbii56").instantiate()
			ui.add_child(cnmd)
			cnmd.popup_centered_clamped()
		1: # Load
			var file_dialog = FileDialog.new()
			file_dialog.set_file_mode(FileDialog.FILE_MODE_OPEN_DIR)
			ui.add_child(file_dialog)
			file_dialog.get_cancel_button().pressed.connect(_remove_dialog.bind(file_dialog))
			file_dialog.dir_selected.connect(_file_selected.bind(file_dialog))
			file_dialog.current_path = Global.save_path
			file_dialog.popup_centered_clamped()
		2: # Save
			map.save_map()


func _remove_dialog(dialog: Window) -> void:
	dialog.queue_free()


func _on_cancel_button_pressed(dialog: Window) -> void:
	hide()
	_remove_dialog(dialog)


func _file_selected(path: String, dialog: Window) -> void:
	map.load_map(path)
	_remove_dialog(dialog)
