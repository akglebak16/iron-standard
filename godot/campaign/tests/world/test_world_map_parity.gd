extends SceneTree
## Settlements, roads and pathfinding must match the browser (fixture from campaign/tools/export_world.cjs).
const WorldMap = preload("res://campaign/world/world_map.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const FIXTURE := "res://campaign/tests/fixtures/world_parity.json"
const POINT_TOLERANCE := 0.01

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for entry in fixture.seeds:
		var started := Time.get_ticks_msec()
		var map = WorldMap.create(int(entry.seed), data)
		var elapsed := Time.get_ticks_msec() - started
		var bad_settles := 0
		assert(map.settles.size() == entry.settles.size(), "settlement count")
		for i in map.settles.size():
			var s: Dictionary = map.settles[i]
			var e: Array = entry.settles[i]
			if s.id != int(e[0]) or s.kind != e[1] or s.fac != e[2] or s.name != e[3] or absf(s.x - float(e[4])) > 0.001 or absf(s.y - float(e[5])) > 0.001:
				bad_settles += 1
		var road_cells := Marshalls.base64_to_raw(entry.road)
		var bad_road := 0
		for k in road_cells.size():
			if road_cells[k] != map.paths.road[k]:
				bad_road += 1
		var bad_points := 0
		var segments_ok: bool = map.roads.size() == entry.roads.size()
		if segments_ok:
			for i in map.roads.size():
				var seg: Array = map.roads[i]
				var ref: Array = entry.roads[i]
				if seg.size() != ref.size():
					bad_points += maxi(seg.size(), ref.size())
					continue
				for q in seg.size():
					if absf(seg[q].x - float(ref[q][0])) > POINT_TOLERANCE or absf(seg[q].y - float(ref[q][1])) > POINT_TOLERANCE:
						bad_points += 1
		print("seed %d: %d ms, settlements off %d/%d, roads %d (js %d), road points off %d, road cells off %d/%d" % [int(entry.seed), elapsed, bad_settles, map.settles.size(), map.roads.size(), entry.roads.size(), bad_points, bad_road, road_cells.size()])
		assert(bad_settles == 0, "settlements differ from browser")
		assert(segments_ok, "road count differs from browser")
		assert(bad_points == 0, "road points differ from browser")
		assert(bad_road == 0, "road cells differ from browser")
	print("World map parity tests passed")
	quit(0)
