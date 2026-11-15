extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Bridge = preload("res://apps/godot/composition/world_battle_bridge.gd")
const Aftermath = preload("res://apps/godot/composition/encounter_aftermath.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var s := WorldState.create(5, data, "emp")
	var b := Bridge.new()
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "nord":
			town = t
			break
	assert(not town.is_empty())
	var opp: Dictionary = b.siege_opponent(s, town)
	assert(opp.kind == "siege" and opp.wall_defense.stones > 0)
	var setup := b.make_setup(s, opp)
	assert(setup.siege and setup.wall_defense.stones == opp.wall_defense.stones)
	# a huge calculated assault takes the castle
	s.player.troops = [{"type": "e2a", "n": 900}]
	var result := b.auto_result(s, opp)
	assert(result.win)
	var party := b.party_dict(s)
	var resolved := Aftermath.resolve_result(result, party, opp, false, b.troops, b.gear, b.goods, b.rng, b.companions, b.perks, b.siege_world(s, town))
	assert(not resolved.is_empty() and resolved.summary.has("captured"), "captured is reported")
	b.apply(s, opp, resolved)
	b.apply_siege(s, town, resolved)
	assert(town.fac == "player" and town.owner == 0 and town.gar.size() > 0)
	# a hopeless calculated assault loses and thins the garrison
	var other: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "khan":
			other = t
			break
	var before := 0
	for st in s.wars.garrison_of(other):
		before += int(st.n)
	s.player.troops = [{"type": "e1", "n": 1}]
	var opp2: Dictionary = b.siege_opponent(s, other)
	var r2 := b.auto_result(s, opp2)
	assert(not r2.win)
	var res2 := Aftermath.resolve_result(r2, b.party_dict(s), opp2, false, b.troops, b.gear, b.goods, b.rng, b.companions, b.perks, b.siege_world(s, other))
	b.apply(s, opp2, res2)
	b.apply_siege(s, other, res2)
	var after := 0
	for st in other.gar:
		after += int(st.n)
	assert(other.fac == "khan" and after <= before)
	print("Siege bridge tests passed")
	quit(0)
