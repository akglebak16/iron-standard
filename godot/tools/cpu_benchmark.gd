extends SceneTree

func _initialize() -> void:
	preload("res://tests/performance/battle_benchmark.gd").new().run(self)
