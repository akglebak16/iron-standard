extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const UnitView = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Snapshot = preload("res://battle/application/render_snapshot.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	var session := Factory.create(setup, catalog)
	var before_rng: int = session._rng.state
	var original := session.snapshot()
	var compact := session.snapshot(true)
	var render: Snapshot = compact.render
	assert(not compact.has("units") and render.size() == original.units.size())
	for key in original:
		if key != "units": assert(original[key] == compact[key], key)
	for i in render.size():
		var unit := render.unit_at(i)
		for key in original.units[i]: assert(unit[key] == original.units[i][key], key)
		assert(unit.look.is_read_only())
	assert(session._rng.state == before_rng and session.snapshot() == original)
	var saved_positions := render.positions()
	var modified := render.positions()
	modified[0] = Vector2.INF
	var figure := render.unit_at(0)
	figure.position = Vector2.INF
	assert(render.positions() == saved_positions)
	assert(session.snapshot() == original)
	# Future ticks cannot overwrite an older snapshot held by a consumer.
	session.step()
	assert(render.positions() == saved_positions)
	var moved: Snapshot = session.snapshot(true).render
	for i in moved.size():
		assert(moved.unit_at(i, 0.0).position == moved.previous_positions()[i])
		assert(moved.unit_at(i, 1.0).position == moved.positions()[i])
	# Ordinary casualties leave the hot render stream. Death data survives independently.
	var victim = session._state.units[1]
	assert(not victim.hero and not victim.companion)
	session._state.kill(victim, session._hero)
	session.step()
	var events := session.take_events()
	var figures := UnitView.new()
	figures.advance(1.0 / 60.0, events)
	assert(figures._corpses.has(victim.id))
	assert(figures._corpses[victim.id].position == victim.position)
	assert(figures._corpses[victim.id].look == victim.appearance)
	assert(session.snapshot(true).render.size() == render.size() - 1)
	assert(session.snapshot().units.size() == original.units.size()) # Results still own casualties.
	figures._corpses[victim.id].look.clear()
	assert(not victim.appearance.is_empty())
	print("Render snapshot tests passed")
	quit(0)
