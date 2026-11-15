extends RefCounted
const Demo = preload("res://apps/godot/presentation/battle/demo_config.gd")

static func draw(canvas: CanvasItem, shot: Dictionary) -> void:
	var origin: Vector2 = shot.origin
	var delta: Vector2 = shot.impact - origin
	var progress: float = shot.progress
	var base := origin + delta * progress
	var distance := delta.length()
	var phase := progress * PI
	var arc := Demo.BOLT_ARC_SCALE if shot.crossbow else Demo.ARROW_ARC_SCALE
	var raised := base - Vector2(0.0, sin(phase) * distance * arc)
	var tangent := Vector2(delta.x, delta.y - cos(phase) * distance * Demo.ARROW_ARC_SCALE * Demo.PROJECTILE_TILT_SCALE)
	var direction := Vector2.from_angle(tangent.angle())
	var shadow := base + Demo.PROJECTILE_SHADOW_OFFSET
	canvas.draw_line(shadow, shadow - Vector2(direction.x * Demo.PROJECTILE_SHADOW_LENGTH, 0), Demo.PROJECTILE_SHADOW_COLOR, Demo.PROJECTILE_SHADOW_WIDTH, true)
	var length := Demo.JAVELIN_LENGTH if shot.throwing else Demo.ARROW_LENGTH
	var width := Demo.JAVELIN_WIDTH if shot.throwing else Demo.ARROW_WIDTH
	canvas.draw_line(raised, raised - direction * length, Demo.PROJECTILE_COLOR, width, true)
	canvas.draw_line(raised - direction * Demo.FLETCHING_START, raised - direction * Demo.FLETCHING_END, Demo.PROJECTILE_FLETCHING_COLOR, Demo.FLETCHING_WIDTH, true)
