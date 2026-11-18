extends Node2D

const CAMERA_SPEED := 560.0
const MAP_SIZE := Vector2(2560, 1600)

@onready var camera: Camera2D = $Camera2D
@onready var renderer: IronWorldMapRenderer = $WorldMap
@onready var bridge_button: CheckButton = %Bridge
@onready var status_label: Label = %Status

var _status_elapsed := 0.0


func _ready() -> void:
	bridge_button.toggled.connect(renderer.set_bridge)
	%Reload.pressed.connect(renderer.reload_trial)


func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position = (camera.position + direction * CAMERA_SPEED * delta / camera.zoom.x).clamp(
		Vector2.ZERO, MAP_SIZE)
	var span := get_viewport_rect().size / camera.zoom
	renderer.update_trial(Rect2(camera.position - span / 2, span), delta)
	_status_elapsed += delta
	if _status_elapsed >= 0.25:
		_status_elapsed = 0
		var status := renderer.trial_status()
		status_label.text = tr("Участков в памяти: %d   Загружено: %d   Выгружено: %d") % [
			status.resident, status.uploaded, status.evicted]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = Vector2.ONE * minf(2.0, camera.zoom.x * 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * maxf(0.45, camera.zoom.x / 1.15)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.position -= event.relative / camera.zoom
