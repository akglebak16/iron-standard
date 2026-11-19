extends SceneTree
## The player joins a fight between map parties on a chosen side, and parties at war with his enemy
## fight at his side (#238).
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSkirmish = preload("res://core/campaign/world/world_skirmish.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")
const Config = preload("res://core/campaign/config.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var p = s.player
	# two states at war with each other, the player at peace with both
	var pair := _warring_pair(s)
	assert(not pair.is_empty(), "the world starts with a war between two states")
	var fa: String = pair[0]
	var fb: String = pair[1]
	p.rel[fa] = 0.0
	p.rel[fb] = 50.0
	var bridge := Bridge.new(ContentLoader.registry(), RandomNumberGenerator.new())
	var troop_a: String = bridge.troops.for_faction(fa)[0].id
	var troop_b: String = bridge.troops.for_faction(fb)[0].id
	p.x = 2600.0
	p.y = 1700.0
	var a: Dictionary = s.roster.make_party("lord", fa, "Тест А", 2620, 1700, [{"type": troop_a, "n": 60}])
	var b: Dictionary = s.roster.make_party("lord", fb, "Тест Б", 2625, 1700, [{"type": troop_b, "n": 60}])
	var b2: Dictionary = s.roster.make_party("lord", fb, "Тест Б2", 2630, 1705, [{"type": troop_b, "n": 20}])
	s.skirmish.contact(a, b, s.ai.auto_fight)
	var sk: Dictionary = s.skirmish.fight_of(a)
	assert(not sk.is_empty() and s.skirmish.fight_of(b) == sk, "the two lords fight for hours")
	if s.skirmish.fight_of(b2).is_empty():
		sk.B.append(b2.id)
		b2.fight = sk.id
	var both: Array = s.skirmish.sides(sk)
	assert(a in both[0] and b in both[1] and b2 in both[1])
	# helping A against B is an attack on B's state, the player is at peace with
	assert(WorldSkirmish.peaceful(both[1], p.rel).size() == 1, "one attack per state, not per party")
	assert(WorldSkirmish.peaceful(both[0], {fa: -50.0}).is_empty())
	var j: Dictionary = s.skirmish.join(sk, 0)
	assert(j.foe == b and j.foes == [b2] and j.friends == [a], "the strongest of the other side leads it")
	assert(s.skirmish.fights.is_empty() and a.fight == null and b.fight == null and b2.fight == null, "the map fight became the player's battle")
	for q in WorldSkirmish.peaceful([j.foe] + j.foes, p.rel):
		s.attack(q)
	assert(float(p.rel[fb]) < 50.0, "B's state takes it as an attack")
	# the side the player helps is at war with the foe, so it would also join on its own
	assert(a in s.skirmish.allies(p, b))
	assert(not b2 in s.skirmish.allies(p, b), "the foe's comrades never help the player")
	p.troops = [{"type": "e3c", "n": 400}]
	var rel_before: float = float(p.rel[fa])
	var a_before: int = Rules.troop_count(a.troops)
	var ticket: RefCounted = bridge.begin(s, b, j.friends, j.foes)
	assert(ticket != null)
	assert(Rules.troop_count(b.troops) == 80 and not b2 in s.roster.parties, "the rest of the other side pours into the foe")
	assert(bridge._encounter_pending_allies.size() == 1 and bridge._encounter_pending_allies[0].party == a, "the helped side fights once, not twice")
	var setup = bridge.battle_setup(ticket)
	assert(Rules.troop_count(setup.player_army) == 400 + a_before, "the allies stand in the player's army")
	assert(Rules.troop_count(setup.enemy_army) == 80)
	var resolved: Dictionary = bridge.calculate(ticket)
	assert(not resolved.is_empty() and resolved.summary.win, "a huge army wins")
	assert(Rules.troop_count(p.troops) <= 400, "the player keeps only his own share")
	assert(not a in s.roster.parties or Rules.troop_count(a.troops) <= a_before, "allies carry their own losses")
	assert(float(p.rel[fa]) == minf(100.0, rel_before + Config.ALLY_WIN_RELATION), "a shared victory warms the ally")
	assert(s.journal.any(func(e): return "Тест А" in str(e)), "the journal names who fought alongside")
	# a party at peace with the player and at war with his enemy joins him without being asked
	p.x = 3600.0
	p.y = 900.0
	var enemy: Dictionary = s.roster.make_party("lord", fb, "Тест Враг", 3610, 900, [{"type": troop_b, "n": 30}])
	var friend: Dictionary = s.roster.make_party("lord", fa, "Тест Друг", 3650, 900, [{"type": troop_a, "n": 30}])
	var far: Dictionary = s.roster.make_party("lord", fa, "Тест Далеко", 3610 + WorldSkirmish.HELP_RADIUS + 400, 900, [{"type": troop_a, "n": 30}])
	var caravan: Dictionary = s.roster.make_party("caravan", fa, "Тест Караван", 3620, 905, [{"type": troop_a, "n": 10}])
	var near: Array = s.skirmish.allies(p, enemy)
	assert(friend in near and not far in near and not caravan in near and not enemy in near)
	p.rel[fa] = -60.0
	assert(not friend in s.skirmish.allies(p, enemy), "the player's enemies do not help him")
	p.rel[fa] = 0.0
	var bandit: Dictionary = s.roster.make_party("bandit", "bandit", "Тест Шайка", 3615, 902, [{"type": "b1", "n": 10}])
	assert(not bandit in s.skirmish.allies(p, enemy), "bandits fight for nobody")
	assert(s.skirmish.allies(p, {"kind": "siege", "fac": fb, "x": 3610.0, "y": 900.0}).is_empty())
	var t2: RefCounted = bridge.begin(s, enemy)
	assert(bridge._encounter_pending_allies.any(func(x): return x.party == friend))
	assert(bridge.cancel(t2))
	s.dispose()
	print("World join battle tests passed")
	quit(0)

func _warring_pair(s) -> Array:
	var facs: Array = Rules.REAL_FACTIONS.filter(func(f): return f != "emp")
	for x in facs:
		for y in facs:
			if x != y and s.roster.hostile({"kind": "lord", "fac": x}, {"kind": "lord", "fac": y}):
				return [x, y]
	return []
