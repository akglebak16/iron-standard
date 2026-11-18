extends "res://apps/godot/presentation/overworld/overworld_trial.gd"

const LIBRARY := preload("res://apps/godot/presentation/overworld/art/region_library.tres")
const SURFACE := preload("res://apps/godot/presentation/overworld/art/surface.gdshader")
const INK := preload("res://apps/godot/presentation/overworld/art/illustration.gdshader")
var surface := ShaderMaterial.new()
var ink := ShaderMaterial.new()
var hour := 12.0


func _ready() -> void:
	super()
	surface.shader = SURFACE
	surface.set_shader_parameter("meadow", LIBRARY.meadow)
	ink.shader = INK
	renderer.material = surface
	renderer.configure_art(LIBRARY.landmarks.get_rid(), LIBRARY.landforms.get_rid(),
		ink.get_rid(), LIBRARY.regions, LIBRARY.second_sheet_start)
	camera.position = Vector2(1280, 640)
	camera.zoom = Vector2.ONE * 0.86
	bridge_button.button_pressed = true
	set_hour(hour)
	%Hour.pressed.connect(_change_hour)


func _change_hour() -> void:
	if hour < 9:
		set_hour(12)
	elif hour < 18:
		set_hour(22)
	else:
		set_hour(6)

func _unhandled_input(event: InputEvent) -> void:
	if not $Loading.visible:
		super(event)


func set_hour(value: float) -> void:
	renderer.set_world_hour(value)
	_update_light(renderer.world_hour())

func _process(delta: float) -> void:
	if $Loading.visible:
		var span := get_viewport_rect().size / camera.zoom
		renderer.update_trial(Rect2(camera.position-span/2,span),0)
		var status := renderer.trial_status()
		if status.uploaded > 0 and not status.busy:
			$Loading.hide()
		return
	super(delta)
	if absf(renderer.world_hour()-hour) > 0.01:
		_update_light(renderer.world_hour())

func _update_light(value: float) -> void:
	hour = value
	var elevation := sin((hour - 6.0) * TAU / 24.0)
	var daylight := smoothstep(-0.25, 0.75, elevation)
	var twilight := 1.0 - smoothstep(0.0, 0.55, absf(elevation))
	var light := Vector3(.37,.45,.66).lerp(Vector3.ONE, daylight)
	light += Vector3(.31,.11,-.04) * twilight
	for material in [surface, ink]:
		material.set_shader_parameter("sunlight", light)
	ink.set_shader_parameter("shadow_slope", .20 + .56 * cos((hour-6)*TAU/24))
	ink.set_shader_parameter("night", 1.0-daylight)
	%Hour.text = tr("Время суток · %02d:00") % int(hour)
