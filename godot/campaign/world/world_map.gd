extends RefCounted
## One generated world: terrain, settlements, roads and pathfinding for a seed (the static part of `G`/`WT` in the browser).
const Generator = preload("res://campaign/world/terrain_generator.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const SettlementGenerator = preload("res://campaign/world/settlement_generator.gd")
const RoadGenerator = preload("res://campaign/world/road_generator.gd")
const Pathfinder = preload("res://campaign/world/pathfinder.gd")

var seed_value := 0
var terrain: Generator
var settles: Array = []
var roads: Array = []
var paths: Pathfinder
var next_id := 1

static func create(seed_in: int, data: EuropeData) -> RefCounted:
	var map := new()
	map.seed_value = seed_in
	map.terrain = Generator.new()
	map.terrain.generate(seed_in, data)
	var gen := SettlementGenerator.new()
	map.settles = gen.generate(map.terrain, data, seed_in)
	map.next_id = gen.next_id()
	map.paths = Pathfinder.new(map.terrain)
	map.roads = RoadGenerator.new().generate(map.terrain, map.paths, map.settles)
	return map

func settlement_by_id(id: int) -> Dictionary:
	for s in settles:
		if s.id == id:
			return s
	return {}
