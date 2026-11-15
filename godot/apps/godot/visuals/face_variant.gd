extends RefCounted
## A hero's or companion's own face from his seed (makeVariant and mulberry in src/02_art.js and src/01_core.js):
## the same random draws in the same order, so a saved hero keeps the face he had in the browser.
const SKINS := ["#e2b48c", "#d6a179", "#c98f66", "#b97d58", "#e8c3a0"]
const HAIRS := ["#2a1d14", "#4a3020", "#6b4423", "#8c5a2b", "#a8672e", "#b9b2a5", "#1a1a1a", "#7a2e16"]
const MASK := 0xFFFFFFFF

## mulberry32: a closure in JS, a state array here. Returns the next float in [0, 1).
static func next(state: Array) -> float:
	var a: int = (int(state[0]) + 0x6D2B79F5) & MASK
	state[0] = a
	var t := _imul(a ^ (a >> 15), 1 | a)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

## Math.imul on unsigned 32-bit values, without overflowing 64-bit integers.
static func _imul(x: int, y: int) -> int:
	x &= MASK
	y &= MASK
	var low := (x & 0xFFFF) * y
	var high := ((x >> 16) * y) & 0xFFFF
	return (low + (high << 16)) & MASK

## {skin, hair, beard, stache, bald, scar} for a look with `beard` chance, optional fixed `hair` and moustache flag.
static func variant(seed_value: int, beard_chance: float, hair: Variant = null, stache := false) -> Dictionary:
	var state := [seed_value & MASK]
	var beard := 0
	if next(state) < beard_chance:
		beard = 2 if next(state) < 0.45 else 1
	var skin: String = SKINS[floori(next(state) * SKINS.size())]
	var drawn: String = HAIRS[floori(next(state) * HAIRS.size())]
	var bald := next(state) < 0.15
	var scar := next(state) < 0.2
	return {"skin": skin, "hair": String(hair) if hair is String and not String(hair).is_empty() else drawn, "beard": beard,
		"stache": 1 if stache and beard == 0 else 0, "bald": bald, "scar": scar}

## The face of a look that carries a seed (heroLook: beard defaults to 1), or empty for troops.
static func of_look(look: Dictionary) -> Dictionary:
	if not look.has("seed"):
		return {}
	var beard: Variant = look.get("beard")
	return variant(int(look.seed), float(beard) if beard is int or beard is float else 1.0, look.get("hair"), bool(look.get("stache", false)))
