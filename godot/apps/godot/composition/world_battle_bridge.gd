extends RefCounted
## Glue between the world map and the battle: builds a battle for a meeting and applies the outcome to the world.
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const GoodsCatalog = preload("res://campaign/data/goods_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const Aftermath = preload("res://apps/godot/composition/encounter_aftermath.gd")
const AutoBattle = preload("res://campaign/world/auto_battle.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const Config = preload("res://campaign/config.gd")
const Siege = preload("res://campaign/world/world_siege.gd")
const WorldCompanions = preload("res://campaign/world/world_companions.gd")
const SiegeAftermath = preload("res://campaign/rules/siege_aftermath.gd")

var troops := Catalog.new()
var gear := GearCatalog.new()
var goods := GoodsCatalog.new()
var companions := CompanionCatalog.new()
var perks := PerkCatalog.new()
var rng := RandomNumberGenerator.new()

func _init() -> void:
	if not (troops.load_data() and gear.load_data() and goods.load_data() and companions.load_data() and perks.load_data()):
		push_error("Required content failed to load: apps/godot/composition/world_battle_bridge.gd")
		return
	rng.randomize()

## The browser's hero fights as the strongest troop of his culture (heroBattle picks the tier 3 line).
func hero_troop(culture: String) -> String:
	for t in troops.for_faction(culture):
		if int(t.tier) == 3:
			return t.id
	return troops.for_faction(culture)[0].id

## Allied retinues joining a fight: [{"party": map party, "troops": snapshot}] (cvBattleStart).
static func snapshot(allies: Array) -> Array:
	var out: Array = []
	for h in allies:
		out.append({"party": h, "troops": h.troops.duplicate(true)})
	return out

static func merged(own: Array, allies: Array) -> Array:
	var out: Array = own.duplicate(true)
	for a in allies:
		for t in a.troops:
			Rules.add_troops(out, t.type, int(t.n))
	return out

func make_setup(state: RefCounted, opponent: Dictionary, allies: Array = []) -> Setup:
	var s := Setup.new()
	s.seed = rng.randi_range(1, 1000000000)
	s.biome = state.map.terrain.biome_name(state.player.x, state.player.y)
	s.player_faction = state.player.culture
	s.enemy_faction = opponent.fac
	s.player_army.assign(merged(state.player.troops, allies))
	s.enemy_army.assign(opponent.troops.duplicate(true))
	s.hero_troop = hero_troop(state.player.culture)
	s.hero_profile = state.player.hero.duplicate(true)
	s.enemy_leader_name = opponent.name if Rules.is_noble(opponent) else ""
	s.hero_position = Vector2(780, 850)
	s.companion_profiles.assign(state.player.comps.duplicate(true))
	if opponent.get("kind") == "siege":
		s.siege = true
		s.wall_damage = clampf(float(opponent.get("wall_damage", 0.0)), 0.0, 1.0)
		s.wall_defense = opponent.get("wall_defense", {}).duplicate()
	return s

func party_dict(state: RefCounted, allies: Array = []) -> Dictionary:
	var p: RefCounted = state.player
	return {"id": 0, "troops": merged(p.troops, allies), "hero": p.hero.duplicate(true), "gold": p.gold, "comps": p.comps.duplicate(true),
		"inv": p.inv.duplicate(true), "rel": p.rel.duplicate(true), "quests": p.quests.duplicate(true), "stats": p.stats.duplicate(true),
		"culture": p.culture, "position": Vector2(p.x, p.y)}

func opponent_dict(party: Dictionary, camp_settlement: Dictionary) -> Dictionary:
	var o := party.duplicate(true)
	if party.kind == "camp":
		o["camp"] = party.home
	return o

func auto_result(state: RefCounted, opponent: Dictionary, allies: Array = []) -> Dictionary:
	var mult := 1.0
	if opponent.get("kind") == "siege":
		mult = Siege.def_k(state.map.settlement_by_id(opponent.sid))
	var res := AutoBattle.resolve(merged(state.player.troops, allies), state.player.hero, opponent.troops, state.roster.info, rng, float(state.player_effects().get("surv", 0.0)), mult, WorldCompanions.strength(state.player))
	res["comps"] = state.companions.auto_outcomes(state.player, res.win)
	return res

## The siege opponent for a town: defenders, wall damage and the stones/oil on the walls.
func siege_opponent(state: RefCounted, s: Dictionary) -> Dictionary:
	var o: Dictionary = state.siege.siege_party(s)
	o["wall_damage"] = clampf(float(s.get("dmg", 0.0)), 0.0, 1.0)
	o["wall_defense"] = SiegeAftermath.supplies(s)
	return o

## World dict a siege result is resolved against: the town and the lords inside it.
func siege_world(state: RefCounted, s: Dictionary) -> Dictionary:
	var inside: Array = []
	for p in state.roster.parties:
		if p.kind == "lord" and p.hide and p.home == s.id and p.fac == s.fac:
			inside.append(p.duplicate(true))
	return {"parties": inside, "settlements": [s.duplicate(true)], "factions": Rules.REAL_FACTIONS}

## Writes the updated town back (captured, garrison losses) and removes lords that fled a taken town.
func apply_siege(state: RefCounted, s: Dictionary, aftermath: Dictionary) -> void:
	for u in aftermath.world.get("settlements", []):
		if u.id == s.id:
			for k in u:
				s[k] = u[k]
	var left := {}
	for p in aftermath.world.get("parties", []):
		left[p.id] = true
	for i in range(state.roster.parties.size() - 1, -1, -1):
		var q: Dictionary = state.roster.parties[i]
		if q.kind == "lord" and q.hide and q.home == s.id and not left.has(q.id):
			state.roster.parties.remove_at(i)

func is_hero_mounted(state: RefCounted) -> bool:
	return bool(HeroGear.resolve(state.player.hero, gear).get("mounted", false))

## Applies a finished battle (played or calculated) to the world. `aftermath` is what EncounterAftermath returned.
func apply(state: RefCounted, opponent: Dictionary, aftermath: Dictionary, allies: Array = []) -> void:
	var p: RefCounted = state.player
	var party: Dictionary = aftermath.party
	p.troops = _split(state, p.troops, party.troops, allies)
	p.hero = party.hero
	p.gold = party.gold
	p.inv = party.get("inv", p.inv)
	p.comps = party.get("comps", p.comps)
	p.rel = party.get("rel", p.rel)
	p.quests = party.get("quests", p.quests)
	p.stats = party.get("stats", p.stats)
	if party.position != Vector2(p.x, p.y):
		p.x = party.position.x
		p.y = party.position.y
	p.stop()
	p.busy = ""
	if opponent.get("kind") == "siege":
		return
	var updated := _find(aftermath.world.get("parties", []), opponent.id)
	if updated.is_empty():
		_remove_opponent(state, opponent)
	else:
		for k in ["troops", "cd", "state", "path", "lock"]:
			opponent[k] = updated[k] if updated.has(k) else opponent.get(k)
		opponent.pi = 0
		if opponent.get("fac") == "undead" and state.undead != null:
			state.undead.raise(opponent, int(aftermath.summary.get("lost", 0)) * state.undead.RAISE)

func _remove_opponent(state: RefCounted, opponent: Dictionary) -> void:
	state.roster.remove(opponent)
	if opponent.kind == "camp":
		var s: Dictionary = state.map.settlement_by_id(opponent.home)
		if not s.is_empty():
			if s.get("barrow", false) and state.undead != null:
				state.undead.barrow_destroyed(state.player, s)
			s.camp = null
			s.cleared = true
			s.respawn = Config.CAMP_RESPAWN_HOURS

func _find(list: Array, id) -> Dictionary:
	for p in list:
		if p.get("id") == id:
			return p
	return {}

## Survivors of a shared fight are split back by each side's share of every troop type (cvBattleEnd).
func _split(state: RefCounted, own_before: Array, after: Array, allies: Array) -> Array:
	if allies.is_empty():
		return after
	var mine: Array = []
	for t in after:
		var total := 0
		var own := 0
		for s in own_before:
			if s.type == t.type:
				own += int(s.n)
		total += own
		var shares: Array = []
		for a in allies:
			var n := 0
			for s in a.troops:
				if s.type == t.type:
					n += int(s.n)
			shares.append(n)
			total += n
		var left := int(t.n)
		for i in allies.size():
			var h: Dictionary = allies[i].party
			var keep := floori(float(t.n) * shares[i] / maxf(1.0, total))
			var had := 0
			for s in h.troops:
				if s.type == t.type:
					had = int(s.n)
			if had > keep:
				Rules.remove_troops(h.troops, t.type, had - keep)
			left -= keep
		if left > 0:
			mine.append({"type": t.type, "n": left})
	for a in allies:
		var h: Dictionary = a.party
		for s in a.troops:
			var still := false
			for t in after:
				if t.type == s.type:
					still = true
			if not still:
				Rules.remove_troops(h.troops, s.type, int(s.n))
		if Rules.troop_count(h.troops) < 1:
			state.roster.remove(h)
		else:
			h.cd = maxf(float(h.cd), 2.0)
			h.state = "idle"
			h.path = []
			h.pi = 0
	return mine
