extends RefCounted
## Value object owned by the caller. Session copies values when input is submitted.
var move := Vector2.ZERO
var face := 0.0
var sprint := false
var block := false
var attack := false

func to_dictionary() -> Dictionary:
	return {"move": move.limit_length(), "face": face, "sprint": sprint, "block": block, "attack": attack}
