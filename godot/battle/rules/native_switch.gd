extends RefCounted
## Whether battle rules use the native core (godot/native). Turned off only by differential tests, which run the
## GDScript reference implementation and compare the battles bit for bit.
static var on := true
