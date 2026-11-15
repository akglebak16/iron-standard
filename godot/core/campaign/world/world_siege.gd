extends RefCounted
## The player's side of a siege and the player's own holdings (src/05c_logic.js siegeParty, src/05i_siege.js sgTalk/sgSack,
## captureSettle, settleIncome, garrisonDay in src/05_world.js). Pure data: the world state owns the one instance.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const WorldWars = preload("res://core/campaign/world/world_wars.gd")
const SettlementRecruits = preload("res://core/campaign/rules/settlement_recruits.gd")

const MK := 2.0
const GAR_WAGE := 0.5
const INC_TOWN := 200
const INC_CASTLE := 100
const INC_VILLAGE := 15
const INC_RADIUS := 450.0
const RUIN_HOURS := 24 * 12
const PLAYER_ID := 0

var wars: WorldWars
var roster: Roster
var rng: RandomNumberGenerator

func _init(world_wars: WorldWars, party_roster: Roster, random: RandomNumberGenerator) -> void:
	wars = world_wars
	roster = party_roster
	rng = random

func now_h() -> int:
	return wars.now_h()

## Fortified places the player can storm: a hostile faction (or the dead) holds them.
static func hostile(s: Dictionary, rel: Dictionary) -> bool:
	if s.is_empty() or s.kind == "camp" or s.fac == "player":
		return false
	return s.fac == "undead" or (s.fac in Rules.REAL_FACTIONS and float(rel.get(s.fac, 0)) < -20.0)

## The defenders of a siege: the garrison plus the lords sitting inside (siegeParty).
func siege_party(s: Dictionary) -> Dictionary:
	var troops: Array = []
	for t in wars.garrison_of(s):
		troops.append({"type": t.type, "n": int(t.n)})
	var leader: Variant = null
	for p in roster.parties:
		if p.kind == "lord" and p.hide and p.home == s.id and p.fac == s.fac:
			if leader == null:
				leader = p.name
			for t in p.troops:
				Rules.add_troops(troops, t.type, int(t.n))
	troops.sort_custom(func(a, b): return int(roster.info[a.type].tier) > int(roster.info[b.type].tier))
	return {"id": -int(s.id), "kind": "siege", "fac": s.fac, "name": s.name, "troops": troops, "gold": 350 if s.kind == "town" else 180, "sid": s.id, "lord": leader}

## Closed gates and walls help the defenders (sgDefK); battered walls help less.
static func def_k(s: Dictionary) -> float:
	return (1.7 if s.kind == "castle" else 1.55) - 0.4 * float(s.get("dmg", 0.0))

static func note(s: Dictionary) -> String:
	if float(s.get("dmg", 0.0)) > 0.15:
		return "Стены повреждены: ворота слабее, в стене может быть пролом, а запасов камней и масла меньше."
	return "Ворота закрыты, их надо ломать, пока защитники бьют из-за зубцов."

## Defenders as the auto-battle sees them (their count is multiplied by the wall bonus).
func defenders_for_calc(s: Dictionary) -> Array:
	var k := def_k(s)
	var out: Array = []
	for t in siege_party(s).troops:
		out.append({"type": t.type, "n": roundi(int(t.n) * k)})
	return out

# ---------- talks ----------

static func food_max(s: Dictionary) -> int:
	return 14 if s.kind == "castle" else 10

static func food_of(s: Dictionary) -> float:
	if not s.has("food") or s.food == null:
		s.food = float(food_max(s))
	return float(s.food)

func bribe(s: Dictionary) -> int:
	return roundi((Rules.strength(wars.garrison_of(s), roster.info) * 3.0 + 200.0) * (1.0 if s.kind == "castle" else 1.15))

func talk_chance(p, s: Dictionary, gold: bool) -> float:
	var g := wars.garrison_of(s)
	var mine: float = Rules.strength(p.troops, roster.info)
	var ratio: float = mine / ((Rules.strength(g, roster.info) + 4.0) * 1.5)
	var f := food_of(s)
	var hungry := 0.45 if f <= 0.0 else (0.2 if f < 3.0 else 0.0)
	var cha := float(p.hero.get("cha", 1))
	return clampf(0.35 * ratio - 0.1 + (cha - 3.0) * 0.035 + hungry + float(s.get("dmg", 0.0)) * 0.25 + float(p.rel.get(s.fac, 0)) / 400.0 + (0.3 if gold else 0.0), 0.03, 0.9)

## null: not possible now, true: the town gave up, false: refused (a day's pause).
func talk(p, s: Dictionary, gold: bool) -> Variant:
	if int(s.get("talkT", 0)) > now_h():
		return null
	var price := bribe(s) if gold else 0
	if gold and p.gold < price:
		return null
	var ok := rng.randf() < talk_chance(p, s, gold)
	if gold:
		p.gold -= price
	if ok:
		surrender(p, s)
		return true
	s.talkT = now_h() + 24
	if s.fac in Rules.REAL_FACTIONS:
		p.rel[s.fac] = maxf(-100.0, float(p.rel.get(s.fac, 0)) - 2.0)
	return false

func surrender(p, s: Dictionary) -> void:
	s.erase("blk")
	var was: String = s.fac
	capture(p, s)
	if was in Rules.REAL_FACTIONS:
		p.rel[was] = minf(100.0, float(p.rel.get(was, 0)) + 10.0)
	s.dmg = minf(float(s.get("dmg", 0.0)), 0.1)
	s.fire = 0

## The settlement becomes the player's (captureSettle). Lords inside flee.
func capture(p, s: Dictionary) -> void:
	var was: String = s.fac
	s.cult = String(s.get("cult", was)) if String(s.get("cult", was)) in Rules.REAL_FACTIONS else "emp"
	s.fac = "player"
	s.owner = PLAYER_ID
	s.board = []
	s.gar = roster.gen_troops(s.cult, 4, 0.3)
	SettlementRecruits.refresh(s, roster.catalog, rng)
	for i in range(roster.parties.size() - 1, -1, -1):
		var q: Dictionary = roster.parties[i]
		if q.kind == "lord" and q.hide and q.home == s.id:
			roster.parties.remove_at(i)
	if was in Rules.REAL_FACTIONS:
		p.rel[was] = maxf(-100.0, float(p.rel.get(was, 0)) - 15.0)
	if was == "undead":
		s.ruin = RUIN_HOURS
		var of: String = s.get("ruinOf", "")
		if of in Rules.REAL_FACTIONS:
			p.rel[of] = minf(100.0, float(p.rel.get(of, 0)) + 8.0)

## After a stormed town the player chooses: plunder it or spare it.
func sack(p, s: Dictionary) -> String:
	var cf: String = String(s.get("cult", "emp"))
	var loot := roundi((300.0 if s.kind == "town" else 220.0) * rng.randf_range(0.8, 1.3) * MK)
	p.gold += loot
	s.dmg = maxf(float(s.get("dmg", 0.0)), 0.6)
	s.fire = rng.randi_range(36, 72)
	s.recruits = []
	if cf in Rules.REAL_FACTIONS:
		p.rel[cf] = maxf(-100.0, float(p.rel.get(cf, 0)) - 10.0)
	return "Ты разграбил %s: +%d золота. Город горит, а жители тебя ненавидят: доход упал, пока стены не починят." % [s.name, loot]

func spare(p, s: Dictionary) -> String:
	var cf: String = String(s.get("cult", "emp"))
	var gift := roundi(40.0 * MK)
	p.gold += gift
	s.dmg = minf(float(s.get("dmg", 0.0)), 0.1)
	if cf in Rules.REAL_FACTIONS:
		p.rel[cf] = minf(100.0, float(p.rel.get(cf, 0)) + 6.0)
	return "Ты пощадил жителей %s. Они подносят дары: +%d золота." % [s.name, gift]

# ---------- the player's blockade: hunger, then surrender (sgBlockStart, sgBlockHour, sgSurrender) ----------

signal surrendered(settlement: Dictionary, text: String)

func block_start(p, s: Dictionary) -> String:
	s.blk = {"t0": now_h(), "g0": maxi(1, Rules.troop_count(wars.garrison_of(s))), "away": 0}
	return "Ты взял %s в блокаду. Держи отряд рядом, пока в городе не кончится еда." % s.name

## Hourly. Returns log lines for the player.
func block_hour(p, hour: int) -> Array:
	var out: Array = []
	for s in roster.map.settles:
		if not s.has("blk") or s.blk == null:
			if s.get("food") != null and float(s.food) < food_max(s) and s.get("siege") == null and hour == 0:
				s.food = minf(food_max(s), float(s.food) + 1.0)
			continue
		if s.fac == "player" or not (s.fac in Rules.REAL_FACTIONS and float(p.rel.get(s.fac, 0)) < -20.0):
			s.erase("blk")
			continue
		if Vector2(p.x - s.x, p.y - s.y).length() > 170.0 or p.busy == "battle":
			s.blk.away = int(s.blk.away) + 1
			if s.blk.away > 12:
				s.erase("blk")
				out.append("Блокада %s снята: ты ушёл от стен." % s.name)
			continue
		s.blk.away = 0
		var g := wars.garrison_of(s)
		s.food = maxf(0.0, food_of(s) - (1.0 + Rules.troop_count(g) / 80.0) / 24.0)
		if float(s.food) > 0.0:
			continue
		if not s.blk.get("starve", false):
			s.blk.starve = true
			out.append("В %s кончилась еда: гарнизон голодает. Самое время потребовать сдачи." % s.name)
		for t in g.duplicate():
			Rules.remove_troops(g, t.type, floori(t.n * 0.02 + rng.randf())) # random rounding, like sgCut
		if Rules.troop_count(g) < int(s.blk.g0) * 0.35:
			surrender(p, s)
			surrendered.emit(s, "%s сдался без боя (голод). Город твой, жители целы." % s.name)
	return out

# ---------- hostile lords storm the player's holdings (assaultsTick, every 3 hours) ----------

var vassals: RefCounted = null  # WorldVassals: retinues help defend their fiefs
signal lost(settlement: Dictionary, text: String)
signal held(settlement: Dictionary, text: String)

func assaults_tick(p) -> void:
	for s in roster.map.settles:
		if s.fac != "player":
			continue
		var lord: Dictionary = {}
		for q in roster.parties:
			if q.kind == "lord" and not q.hide and not q.get("lock", false) and q.fac in Rules.REAL_FACTIONS and float(p.rel.get(q.fac, 0)) < -20.0 and Vector2(q.x - s.x, q.y - s.y).length() < 70.0:
				lord = q
				break
		if lord.is_empty():
			continue
		var g := wars.garrison_of(s)
		var vd: Dictionary = vassals.defence_of(s) if vassals != null else {}
		var att: float = roster.strength_of(lord) * rng.randf_range(0.8, 1.2)
		var def: float = (Rules.strength(g, roster.info) + 4.0 + (roster.strength_of(vd) if not vd.is_empty() else 0.0)) * 1.6 * rng.randf_range(0.8, 1.2)
		var r := minf(att, def) / maxf(att, def)
		if not vd.is_empty():
			vassals.defence_hit(vd, r, att <= def)
		if att > def:
			for t in lord.troops.duplicate():
				Rules.remove_troops(lord.troops, t.type, roundi(int(t.n) * r * 0.5))
			s.fac = lord.fac
			s.owner = null
			s.gar = roster.gen_troops(lord.fac, 20, 0.5)
			lord.hide = true
			lord.home = s.id
			lord.wait = float(roster.rint(10, 30))
			SettlementRecruits.refresh(s, roster.catalog, rng)
			lost.emit(s, "%s взял штурмом %s. Владение потеряно." % [lord.name, s.name])
		else:
			for t in g.duplicate():
				Rules.remove_troops(g, t.type, roundi(int(t.n) * r * 0.45))
			roster.remove(lord)
			held.emit(s, "Гарнизон %s отбил штурм: %s разбит." % [s.name, lord.name])

# ---------- holdings ----------

func villages_near(s: Dictionary) -> int:
	var n := 0
	for v in roster.map.settles:
		if v.kind == "village" and String(v.get("cult", v.fac)) == String(s.get("cult", s.fac)) and Vector2(v.x - s.x, v.y - s.y).length() < INC_RADIUS:
			n += 1
	return n

func income(s: Dictionary) -> int:
	if s.kind != "town" and s.kind != "castle":
		return 0
	var base := (INC_TOWN if s.kind == "town" else INC_CASTLE) + villages_near(s) * INC_VILLAGE
	return roundi(base * (1.0 + (MK - 1.0) * 0.5) * (0.4 if float(s.get("ruin", 0)) > 0 else 1.0) * (1.0 - 0.5 * float(s.get("dmg", 0.0))))

func upkeep(s: Dictionary) -> int:
	var w := 0.0
	for t in wars.garrison_of(s):
		w += float(roster.catalog.get_troop(t.type).wage) * int(t.n)
	return roundi(w / 3.0 * GAR_WAGE)

func holdings() -> Array:
	var out: Array = []
	for s in roster.map.settles:
		if s.fac == "player" and s.get("owner", -1) == PLAYER_ID and not s.has("vass"):
			out.append(s)
	return out

## Once a day: the player's holdings pay taxes and eat their garrison wages. Returns the log line (or "").
func holdings_day(p, wage_discount: float) -> String:
	var own := holdings()
	for s in own:
		if s.kind in ["town", "castle"] and Rules.troop_count(wars.garrison_of(s)) < 6:
			for a in roster.gen_troops(String(s.get("cult", "emp")), 1, 0.3):
				Rules.add_troops(wars.garrison_of(s), a.type, a.n)
	if own.is_empty():
		return ""
	var inc := 0
	var up := 0
	for s in own:
		inc += income(s)
		up += upkeep(s)
	up = roundi(up * (1.0 - wage_discount))
	p.gold += inc - up
	if p.gold < 0:
		p.gold = 0
		for s in own:
			var g := wars.garrison_of(s)
			if Rules.troop_count(g) > 6:
				var t: Dictionary = g[rng.randi_range(0, g.size() - 1)]
				Rules.remove_troops(g, t.type, maxi(1, roundi(int(t.n) * 0.1)))
		return "Казна пуста: гарнизоны без жалованья разбегаются."
	return "Владения: доход +%d, гарнизоны −%d золота." % [inc, up]

## Moves men between the party and a holding's garrison (garMove). Returns how many moved.
func gar_move(p, s: Dictionary, type: String, n: int, to_gar: bool, size_cap: int) -> int:
	if s.fac != "player" or s.get("owner", -1) != PLAYER_ID:
		return 0
	var from: Array = p.troops if to_gar else wars.garrison_of(s)
	var to: Array = wars.garrison_of(s) if to_gar else p.troops
	var have := 0
	for t in from:
		if t.type == type:
			have = int(t.n)
	if have == 0:
		return 0
	n = mini(n, have)
	if not to_gar:
		n = mini(n, size_cap - Rules.troop_count(p.troops))
	else:
		n = mini(n, Rules.troop_count(p.troops) - 1)
	if n < 1:
		return 0
	Rules.remove_troops(from, type, n)
	Rules.add_troops(to, type, n)
	return n
