extends RefCounted
## Port of mulberry() and makeNoise() from src/01_core.js. Results match the browser,
## so a seed gives the same continent in both versions.
const MASK := 0xFFFFFFFF

class Mulberry extends RefCounted:
	var _a: int
	func _init(seed_value: int) -> void:
		_a = seed_value & 0xFFFFFFFF
	func next() -> float:
		_a = (_a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := _imul(_a ^ (_a >> 15), 1 | _a)
		t = ((t + _imul(t ^ (t >> 7), 61 | t)) ^ t) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
	static func _imul(a: int, b: int) -> int:
		return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF

class ValueNoise extends RefCounted:
	var _p := PackedFloat32Array()
	func _init(seed_value: int) -> void:
		var rng := Mulberry.new(seed_value)
		_p.resize(4096)
		for i in 4096:
			_p[i] = rng.next()
	func _at(x: int, y: int) -> float:
		return _p[(x & 63) + (y & 63) * 64]
	func _n1(x: float, y: float) -> float:
		var xi := floori(x)
		var yi := floori(y)
		var fx := x - xi
		var fy := y - yi
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		var a := _at(xi, yi)
		var b := _at(xi + 1, yi)
		var c := _at(xi, yi + 1)
		var d := _at(xi + 1, yi + 1)
		var top := a + (b - a) * fx
		var bottom := c + (d - c) * fx
		return top + (bottom - top) * fy
	func table() -> PackedFloat32Array:
		return _p
	func value(x: float, y: float) -> float:
		return _n1(x, y) * 0.55 + _n1(x * 2.1 + 7.0, y * 2.1 + 3.0) * 0.3 + _n1(x * 4.3 + 13.0, y * 4.3 + 9.0) * 0.15
