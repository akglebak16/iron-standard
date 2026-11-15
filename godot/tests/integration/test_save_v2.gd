extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const World = preload("res://campaign/world/world_state.gd")
const Save = preload("res://campaign/world/world_save.gd")
const Checkpoint = preload("res://campaign/world/world_checkpoint.gd")
const Store = preload("res://apps/godot/composition/save_store.gd")
const Europe = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	var europe := Europe.new()
	assert(ContentLoader.populate(europe))
	var first := World.create(4242, europe, "emp", ContentLoader.registry())
	first.player.away = true
	first.player.path = [Vector2(first.player.x + 10.12345, first.player.y + 4.56789)]
	first.advance(0.137)
	assert(first.clock._acc > 0.0)
	var encoded := Save.to_dict(first)
	assert(encoded.version == 2)
	var second := Save.from_dict(JSON.parse_string(JSON.stringify(encoded)), europe, ContentLoader.registry())
	assert(second != null)
	assert(Checkpoint.capture(first) == Checkpoint.capture(second), "checkpoint must retain types and full float/RNG precision")
	for i in 300:
		first.advance(0.137)
		second.advance(0.137)
	assert(Checkpoint.capture(first) == Checkpoint.capture(second), "loading must reproduce continuation, including hour work")
	var captured := Checkpoint.capture(first)
	captured.player.gold = -123
	assert(first.player.gold != -123)
	var corrupt := encoded.duplicate(true)
	corrupt.payload += "broken"
	assert(Save.from_dict(corrupt, europe, ContentLoader.registry()) == null)
	assert(Save.from_dict({"version": 1}, europe, ContentLoader.registry()) == null)
	assert(Save.from_dict({"version": 999}, europe, ContentLoader.registry()) == null)
	var legacy := Save.to_v1_dict(first)
	var migrated := Save.from_dict(JSON.parse_string(JSON.stringify(legacy)), europe, ContentLoader.registry())
	assert(migrated != null and migrated.player.troops == first.player.troops)
	assert(migrated.player.gold == first.player.gold and migrated.player.hero == first.player.hero)
	assert(Save.to_dict(migrated).version == 2)
	var malformed := legacy.duplicate(true)
	malformed.parties = [{"id": 123}]
	assert(Save.from_dict(malformed, europe, ContentLoader.registry()) == null)
	malformed = legacy.duplicate(true)
	malformed.player.troops = ["invalid"]
	assert(Save.from_dict(malformed, europe, ContentLoader.registry()) == null)
	# A torn new generation cannot destroy the previous committed save.
	var path := "user://v2-recovery.json"
	first.player.gold = 111
	assert(Store.save(first, path))
	first.player.gold = 222
	assert(Store.save(first, path))
	var generations := Store._generations(path)
	var file := FileAccess.open(generations[0].path, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	var recovered := Store.load_state(europe, path)
	assert(recovered != null and recovered.player.gold == 111)
	first.player.gold = 333
	assert(Store.save(first, path))
	var newest := Store.load_state(europe, path)
	assert(newest != null and newest.player.gold == 333)
	assert(Store.save(first, path))
	assert(Store._generations(path).size() <= Store.KEEP_GENERATIONS)
	for state in [first, second, migrated, recovered, newest]: state.dispose()
	print("Save v2 tests passed")
	quit(0)
