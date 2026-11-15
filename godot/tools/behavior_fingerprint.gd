extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Behaviour fingerprint: runs the demo battles on a fixed seed and prints hashes of the whole snapshot and result.
## Run it before and after a refactoring that must not change behaviour; the printed lines must be identical:
##   godot --headless --path godot --script res://tools/behavior_fingerprint.gd
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const Config = preload("res://core/battle/config.gd")
const SNAPSHOT_TICKS := 1200
const SAMPLE_EVERY := 120
const TICK_SECONDS := 1.0 / 60.0
func _initialize() -> void:
	var c := Catalog.new(); ContentLoader.populate(c)
	var g := GearCatalog.new(); ContentLoader.populate(g)
	var p := PerkCatalog.new(); ContentLoader.populate(p)
	var k := CompanionCatalog.new(); ContentLoader.populate(k)
	for path in ["res://content/scenarios/demo_battle.tres", "res://content/scenarios/demo_siege.tres"]:
		var s = Factory.create(load(path).to_setup(), c, g, p, k)
		s.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
		var trace := 0
		for i in SNAPSHOT_TICKS:
			s.advance(TICK_SECONDS)
			if i % SAMPLE_EVERY == 0:
				trace = hash([trace, hash(var_to_str(s.snapshot()))])
		var snap = s.snapshot()
		var res = s.result()
		print("FP ", path.get_file(), " ", str(snap.units.size()), " ", str(snap.tick), " ", hash(var_to_str(snap)), " ", trace, " ", hash(var_to_str(res)))
	quit(0)
