extends Camera2D

@export var pan_speed: float = 1500.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 3.0

var is_panning: bool = false

func _process(delta):
	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_right"): direction.x += 1
	if Input.is_action_pressed("ui_left"): direction.x -= 1
	if Input.is_action_pressed("ui_down"): direction.y += 1
	if Input.is_action_pressed("ui_up"): direction.y -= 1
	
	position += direction.normalized() * pan_speed * delta / zoom.x

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var new_zoom = clamp(zoom.x + zoom_speed, min_zoom, max_zoom)
			zoom = Vector2(new_zoom, new_zoom)
			
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Oddalamy
			var new_zoom = clamp(zoom.x - zoom_speed, min_zoom, max_zoom)
			zoom = Vector2(new_zoom, new_zoom)
		
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.is_pressed():
				is_panning = true
			else:
				is_panning = false
	
	if event is InputEventMouseMotion and is_panning:
		position -= event.relative / zoom.x
