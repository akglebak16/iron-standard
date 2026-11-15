extends "res://core/content/api/definition_catalog.gd"
## Europe map data (coast shapes, ridges, regions, rivers) exported from src/05_world.js
## by tools/campaign/export_world.cjs into data/europe.json.
const CONTENT_KEY := "europe"

var eu: Dictionary = {}
var shapes: Array = []
var ridges: Array = []
var regions: Dictionary = {}
var rivers: Array = []
var factions: Array = []
var town_names: Dictionary = {}
var camp_names: Array = []

func replace_data(parsed: Variant) -> bool:
	if _sealed: return false
	if not parsed is Dictionary: return false
	for key in ["eu", "regions", "town_names"]:
		if not parsed.get(key) is Dictionary: return false
	for key in ["shapes", "ridges", "rivers", "factions", "camp_names"]:
		if not parsed.get(key) is Array: return false
	parsed = parsed.duplicate(true)
	eu = parsed.eu
	shapes = parsed.shapes
	ridges = parsed.ridges
	regions = parsed.regions
	rivers = parsed.rivers
	factions = parsed.factions
	town_names = parsed.town_names
	camp_names = parsed.camp_names
	_valid = true
	return true
