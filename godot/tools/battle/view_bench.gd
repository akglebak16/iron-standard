extends SceneTree
## Compatibility entry point; --view-benchmark uses the same controller in release.
const Benchmark = preload("res://tests/performance/view_benchmark.gd")

func _initialize() -> void:
	root.add_child.call_deferred(Benchmark.new())
