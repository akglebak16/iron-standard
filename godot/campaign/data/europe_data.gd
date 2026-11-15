extends RefCounted
## Europe map data (coast shapes, ridges, regions, rivers) exported from src/05_world.js
## by campaign/tools/export_world.cjs into data/europe.json.
const PATH := "res://campaign/data/europe.json"

var eu: Dictionary = {}
var shapes: Array = []
var ridges: Array = []
var regions: Dictionary = {}
var rivers: Array = []
var factions: Array = []
var town_names: Dictionary = {}
var camp_names: Array = []

func load_data() -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	eu = parsed.eu
	shapes = parsed.shapes
	ridges = parsed.ridges
	regions = parsed.regions
	rivers = parsed.rivers
	factions = parsed.factions
	town_names = parsed.town_names
	camp_names = parsed.camp_names
	return true
