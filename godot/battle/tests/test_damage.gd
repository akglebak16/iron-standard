extends SceneTree

const Damage = preload("res://battle/damage.gd")

func _initialize() -> void:
	var cases := [[100.0, 0.0, 0.0, 100], [100.0, 55.0, 0.0, 50], [100.0, 110.0, 0.5, 50], [0.0, 0.0, 0.0, 1], [5.0, 55.0, 0.0, 3]]
	for c in cases:
		var result: int = Damage.after_armor(c[0], c[1], c[2])
		if result != c[3]:
			push_error("damage mismatch: %s -> %s" % [c, result])
			quit(1)
			return
	print("Damage tests passed")
	quit(0)
