extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Config = preload("res://battle/config.gd")
const Companions = preload("res://characters/data/companion_catalog.gd")
const Unit = preload("res://battle/model/unit.gd")

func _initialize() -> void:
	var troops := Catalog.new()
	var companions := Companions.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(companions))
	var setup := Setup.new()
	setup.siege = true
	setup.hero_troop = "n1"
	setup.enemy_leader_name = "Leader"
	setup.enemy_army = [{"type": "e1", "n": 2}, {"type": "e2a", "n": 1}, {"type": "e3c", "n": 1}, {"type": "s1", "n": 1}]
	setup.companion_profiles = [{"id": "vikenty", "hp": 0.1, "lvl": 7}]
	var session := Factory.create(setup, troops, null, null, companions)
	assert(session != null)
	var state := session._state
	var wall = state.wall
	assert(wall.x == 1620.0 and wall.half_width == 22.0 and is_equal_approx(state.siege_skill, 0.7))
	assert(wall.gap_at(330.0) == Vector2.ZERO and wall.gap_at(331.0) == Vector2(330, 425))
	assert(wall.gap_at(850.0) == Vector2(770, 930) and wall.gap_at(1300.0) == Vector2(1275, 1370))
	var expected := [Rect2(1598, 0, 44, 330), Rect2(1598, 425, 44, 345), Rect2(1598, 930, 44, 345), Rect2(1598, 1370, 44, 330)]
	assert(session.snapshot().walls == expected)
	var detached: Array = session.snapshot().walls
	detached.clear()
	assert(session.snapshot().walls == expected)
	var centers := [Vector2(1700, 850), Vector2(1672, 850), Vector2(2220, 850)]
	for group in state.groups[1]:
		assert(group.center == centers[group.kind] and group.order == Config.ORDER_HOLD and group.direction == PI)
	for unit in state.units:
		if unit.side != 1:
			continue
		var group = state.groups[1][unit.group_kind]
		assert(unit.position.is_equal_approx(group.slot_position(unit, state.arena_size)) and unit.facing == PI)
		var expected_morale := 200.0 if unit.leader else (999.0 if unit.troop_id == "s1" else 72.0 + unit.tier * 14.0 + 8.0)
		assert(unit.morale == expected_morale and unit.base_morale == expected_morale)
	var hero: Unit = session._hero
	hero.position = Vector2(1610, 700)
	session.advance(0.01)
	assert(hero.position.x == 1588.0)
	hero.position = Vector2(1610, 771)
	session.advance(0.01)
	assert(hero.position.x == 1610.0 and is_equal_approx(hero.position.y, 779.375))
	setup.siege = false
	assert(Factory.create(setup, troops, null, null, companions).snapshot().walls.is_empty())
	print("Siege setup tests passed")
	quit(0)
