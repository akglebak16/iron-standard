extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## The Godot terrain must match the browser generator (fixture from tools/campaign/export_world.cjs).
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const FIXTURE := "res://tests/unit/campaign/fixtures/world_parity.json"
const MAX_CELL_MISMATCH := 0.002

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert(typeof(fixture) == TYPE_DICTIONARY)
	for entry in fixture.seeds:
		var started := Time.get_ticks_msec()
		var world := Generator.new()
		world.generate(int(entry.seed), data)
		var elapsed := Time.get_ticks_msec() - started
		var cells := Marshalls.base64_to_raw(entry.cells)
		var bio := Marshalls.base64_to_raw(entry.bio)
		assert(cells.size() == world.cells.size() and bio.size() == world.bio.size())
		var bad_cells := 0
		var bad_bio := 0
		for k in cells.size():
			if cells[k] != world.cells[k]:
				bad_cells += 1
			if bio[k] != world.bio[k]:
				bad_bio += 1
		print("seed %d: %d ms, cells differ %d/%d, biomes differ %d, rivers %d (js %d), bridges %d (js %d)" % [int(entry.seed), elapsed, bad_cells, cells.size(), bad_bio, world.rivers.size(), entry.rivers.size(), world.bridges.size(), int(entry.bridges)])
		assert(float(bad_cells) / cells.size() <= MAX_CELL_MISMATCH, "terrain differs from browser")
		assert(float(bad_bio) / cells.size() <= MAX_CELL_MISMATCH, "biomes differ from browser")
		assert(world.rivers.size() == entry.rivers.size(), "river count")
		for s in entry.samples:
			assert(absf(world.elevation(float(s[0]), float(s[1])) - float(s[2])) < 0.0005, "elevation sample")
			assert(world.biome_name(float(s[0]), float(s[1])) == str(s[4]))
	print("Terrain parity tests passed")
	quit(0)
