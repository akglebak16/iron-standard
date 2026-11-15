extends RefCounted
## Noble houses, rulers and the player's oath (clans, rulers, oath and lure parts of src/05g_war.js).
## Each faction has 4 houses of 2 lords; a house may defect to a stronger enemy, the player (as a vassal) may lure one.
## The ruler heads one house; while the throne is empty the faction starts no campaigns or wars.
const Rules = preload("res://campaign/world/party_rules.gd")
const Roster = preload("res://campaign/world/party_roster.gd")
const WorldWars = preload("res://campaign/world/world_wars.gd")

const MK := 2.0
const CLANS_PER_F := 4
const CLAN_SIZE := 2
const CLAN_DEF_CD := 60
const CLAN_FAC_CD := 30
const CLAN_MIN := 2
const CLAN_MAX := 6
const LURE_CD := 20
const OATH_REL := 20
const OATH_LVL := 2
const TRAITS := {
	"loyal": {"n": "Верный", "d": "держится присяги, почти не склонен к измене", "base": 88, "thr": 10, "ch": 0.12, "cost": 2.0, "luck": 0.25},
	"greedy": {"n": "Корыстный", "d": "продаётся тому, кто больше платит", "base": 62, "thr": 30, "ch": 0.5, "cost": 0.7, "luck": 1.0},
	"ambit": {"n": "Честолюбивый", "d": "тянется к сильному и побеждающему", "base": 60, "thr": 42, "ch": 0.7, "cost": 1.2, "luck": 1.0},
	"proud": {"n": "Обидчивый", "d": "помнит обиды и потери земель", "base": 62, "thr": 34, "ch": 0.5, "cost": 1.1, "luck": 1.0},
	"fickle": {"n": "Переменчивый", "d": "легко меняет сторону", "base": 50, "thr": 44, "ch": 1.0, "cost": 0.8, "luck": 1.4},
}
const TRAIT_POOL := ["loyal", "loyal", "greedy", "greedy", "ambit", "ambit", "proud", "proud", "fickle"]
const RTITLE := {"nord": "Конунг", "emp": "Император", "khan": "Хан", "kin": "Король", "emi": "Эмир", "dom": "Великий князь", "pact": "Король"}
const RTRAIT := {"war": ["воинственный", 1.6, 0.6], "peace": ["миролюбивый", 0.5, 1.6], "norm": ["рассудительный", 1.0, 1.0]}

signal announced(text: String)
signal message(text: String)  # only for the player

var roster: Roster
var wars: WorldWars
var player: RefCounted
var clans: Array = []      # {id, fac, name, trait, loy, home, cd, vac, rule, born}
var switched: Dictionary = {}  # faction -> day of its last voluntary defection
var rulers: Dictionary = {}    # faction -> {trait, dead, until, name}
var next_id := 1
var siege: RefCounted = null  # WorldSiege: the liege may grant a fief

func _init(party_roster: Roster, world_wars: WorldWars, player_party: RefCounted) -> void:
	roster = party_roster
	wars = world_wars
	player = player_party

func _day() -> int:
	return wars.day

static func label(n: String) -> String:
	var g := n
	if n.ends_with("ий"):
		g = n.substr(0, n.length() - 2) + "ия"
	elif n.ends_with("й") or n.ends_with("ь"):
		g = n.substr(0, n.length() - 1) + "я"
	elif not n.right(1) in ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]:
		g = n + "а"
	return "Дом " + g

func of_faction(f: String) -> Array:
	return clans.filter(func(c): return c.fac == f)

func by_id(id) -> Dictionary:
	for c in clans:
		if c.id == id:
			return c
	return {}

func clan_of(p: Dictionary) -> Dictionary:
	return by_id(int(p.clan)) if p.get("clan") != null else {}

func members(c: Dictionary) -> Array:
	return roster.parties.filter(func(p): return p.kind == "lord" and p.get("clan") == c.id)

func is_free(c: Dictionary) -> bool:
	return members(c).all(func(p): return not p.get("lock", false) and not p.get("fight", false) and not p.get("army", false))

func force(c: Dictionary) -> int:
	var n := 0
	for p in members(c):
		n += Rules.troop_count(p.troops)
	return n

func init() -> void:
	if not clans.is_empty():
		return
	for f in wars.factions_alive():
		var hs: Array = roster.map.settles.filter(func(s): return s.fac == f and s.kind != "village" and s.kind != "camp")
		var used := {}
		var unclaimed: Array = roster.parties.filter(func(p): return p.kind == "lord" and p.fac == f and p.get("clan") == null)
		var names: Array = roster.factions.get_faction(f).names
		for i in CLANS_PER_F:
			var nm: String = roster.pick(names)
			var k := 0
			while used.has(nm) and k < 30:
				nm = roster.pick(names)
				k += 1
			used[nm] = true
			var tr: String = roster.pick(TRAIT_POOL)
			var h: Variant = hs[i % hs.size()] if not hs.is_empty() else null
			var c := {"id": next_id, "fac": f, "name": label(nm), "trait": tr, "loy": int(TRAITS[tr].base) + roster.rint(-8, 8), "home": h.id if h != null else null, "cd": 0, "vac": 0, "rule": false, "born": false}
			next_id += 1
			clans.append(c)
			for j in CLAN_SIZE:
				if unclaimed.is_empty():
					break
				unclaimed.pop_front().clan = c.id

## A faction lost a settlement: its houses grumble, the winner's houses are pleased.
func on_capture(s: Dictionary, old: String, by: String) -> void:
	for c in of_faction(old):
		c.loy = maxi(0, int(c.loy) - (18 if c.home == s.id else (9 if c.trait == "proud" else 5)))
		if c.home == s.id:
			var h: Array = roster.map.settles.filter(func(q): return q.fac == old and q.kind != "village" and q.kind != "camp" and q.id != s.id)
			c.home = h[0].id if not h.is_empty() else null
	for c in of_faction(by):
		c.loy = mini(100, int(c.loy) + 4)
	# the player's liege rewards a vassal who answered the call
	var call: Variant = player.get("summons")
	if player.liege == by and call is Dictionary and not call.joined and Vector2(player.x - s.x, player.y - s.y).length() < 220.0:
		call.joined = true
		vassal_reward(s)

func on_campaign(f: String, target: Dictionary) -> void:
	if player.liege == f:
		player.summons = {"tid": target.id, "until": wars.now_h() + 96, "joined": false}
		message.emit("Твой сюзерен зовёт тебя в поход: %s. Будь рядом, когда начнётся осада." % target.name)

func settle_near(f: String, x: float, y: float) -> Dictionary:
	var best := {}
	var bd := 1e9
	for s in roster.map.settles:
		if s.fac == f and s.kind != "village" and s.kind != "camp":
			var d := Vector2(s.x - x, s.y - y).length()
			if d < bd:
				bd = d
				best = s
	return best

func defect(c: Dictionary, to: String, forced: bool) -> void:
	var from: String = c.fac
	var mem := members(c)
	var h := settle_near(to, mem[0].x if not mem.is_empty() else 0.0, mem[0].y if not mem.is_empty() else 0.0)
	c.fac = to
	c.rule = false
	c.cd = _day() + CLAN_DEF_CD
	c.loy = maxi(55, int(c.loy))
	if not h.is_empty():
		c.home = h.id
	if not forced:
		switched[from] = _day()
	for p in mem:
		p.fac = to
		p.ruler = false
		p.name = roster.lord_name(to)
		p.army = false
		p.arrived = false
		p.state = "idle"
		p.path = []
		p.pi = 0
		p.tid = null
		p.sid = null
		if not h.is_empty():
			p.home = h.id
			p.hide = false
			p.x = h.x + roster.rint(-10, 10)
			p.y = h.y + 20
	announced.emit("%s (%s род) переходит от %s к %s." % [c.name, String(TRAITS[c.trait].n).to_lower(), _gen(from), _gen(to)])

func _gen(f: String) -> String:
	return roster.factions.get_faction(f).get("gen", f)

func _fname(f: String) -> String:
	return roster.factions.get_faction(f).get("name", f)

## Once a day: rulers, loyalty drift, defections and the player's service.
func day_tick() -> void:
	if clans.is_empty():
		init()
	ruler_day()
	var alive_list: Array = wars.factions_alive()
	for c in clans:
		var t: Dictionary = TRAITS[c.trait]
		c.loy = int(c.loy) + (1 if int(c.loy) < int(t.base) else (-1 if int(c.loy) > int(t.base) else 0))
		if not c.fac in alive_list or c.rule or _day() < int(c.cd) or int(c.loy) > int(t.thr) or roster.rng.randf() > float(t.ch) * 0.08:
			continue
		if of_faction(c.fac).size() <= CLAN_MIN or _day() - int(switched.get(c.fac, -99)) < CLAN_FAC_CD or not is_free(c):
			continue
		var best := ""
		var bp := 0.0
		for e in alive_list:
			if e != c.fac and wars.at_war(c.fac, e) and of_faction(e).size() < CLAN_MAX:
				var pw: float = wars.power(e)
				if pw > bp:
					bp = pw
					best = e
		if best == "" or (c.trait == "ambit" and bp < wars.power(c.fac) * 1.15):
			continue
		defect(c, best, false)
	vassal_day()

## Hour 12: a house that lost a lord gets a new kinsman a few days later.
func refill() -> void:
	for c in clans:
		if not wars.alive(c.fac):
			continue
		if members(c).size() >= CLAN_SIZE:
			c.vac = 0
			continue
		if int(c.vac) == 0:
			c.vac = _day() + (3 if c.born else 0)
		if _day() < int(c.vac):
			continue
		var h: Dictionary = roster.map.settlement_by_id(c.home) if c.home != null else {}
		if h.is_empty() or h.fac != c.fac:
			h = settle_near(c.fac, 0.0, 0.0)
			c.home = h.id if not h.is_empty() else null
		if h.is_empty():
			continue
		roster.make_party("lord", c.fac, roster.lord_name(c.fac), h.x + 10, h.y + 20, roster.gen_troops(c.fac, roster.rint(roster.LORD_NEW_MIN, roster.LORD_NEW_MAX), 0.6), {"home": h.id, "clan": c.id})
		c.born = true
		c.vac = 0

# ---------- rulers ----------

func ruler_of(f: String) -> Dictionary:
	for p in roster.parties:
		if p.get("ruler", false) and p.fac == f and p.kind == "lord":
			return p
	return {}

func kingless(f: String) -> bool:
	return rulers.has(f) and int(rulers[f].get("dead", 0)) > 0

func ruler_trait(f: String) -> Array:
	return RTRAIT.get(rulers.get(f, {}).get("trait", "norm"), RTRAIT.norm)

func ruler_war(a: String, b: String) -> float:
	return (float(ruler_trait(a)[1]) + float(ruler_trait(b)[1])) / 2.0

func ruler_peace(a: String, b: String) -> float:
	return (float(ruler_trait(a)[2]) + float(ruler_trait(b)[2])) / 2.0

func ruler_pick(f: String) -> bool:
	var lords: Array = roster.parties.filter(func(p): return p.kind == "lord" and p.fac == f and p.get("clan") != null)
	if lords.is_empty():
		return false
	var cand: Array = []
	for c in of_faction(f):
		if c.rule:
			cand = members(c)
	if cand.is_empty():
		cand = lords
	cand.sort_custom(func(a, b): return Rules.troop_count(a.troops) > Rules.troop_count(b.troops))
	var best: Dictionary = cand[0]
	for x in of_faction(f):
		x.rule = false
	var c := clan_of(best)
	if not c.is_empty():
		c.rule = true
	best.ruler = true
	var parts: PackedStringArray = String(best.name).split(" ")
	best.name = RTITLE.get(f, "Король") + " " + " ".join(parts.slice(1))
	for a in roster.gen_troops(f, 50, 0.7):
		Rules.add_troops(best.troops, a.type, a.n)
	var tr: String = roster.pick(["war", "peace", "norm", "norm"])
	rulers[f] = {"trait": tr, "dead": 0, "until": 0, "name": best.name}
	announced.emit("%s (%s) правит: %s." % [best.name, RTRAIT[tr][0], _fname(f)])
	return true

func ruler_day() -> void:
	for f in wars.factions_alive():
		if not ruler_of(f).is_empty():
			if rulers.has(f):
				rulers[f].dead = 0
			continue
		if not rulers.has(f):
			ruler_pick(f)
			continue
		var r: Dictionary = rulers[f]
		if int(r.dead) == 0:
			r.dead = _day()
			r.until = _day() + 5
			for c in of_faction(f):
				c.loy = maxi(0, int(c.loy) - 10)
			announced.emit("%s пал. %s без правителя, роды колеблются." % [r.name, _fname(f)])
		elif _day() >= int(r.until):
			ruler_pick(f)

## The ruler's guards often carry him off a lost field: he goes home and gathers a new retinue (rulerHome).
func ruler_home(p: Dictionary) -> void:
	var h: Dictionary = roster.map.settlement_by_id(p.home) if p.get("home") != null else {}
	if h.is_empty() or h.fac != p.fac:
		h = settle_near(p.fac, p.x, p.y)
	if not h.is_empty():
		p.home = h.id
		p.x = h.x
		p.y = h.y + 20
		p.hide = true
		p.wait = float(roster.rint(8, 16))
	p.fight = false
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.cd = 6.0
	var need := roundi(90 * MK) - Rules.troop_count(p.troops)
	if need > 0:
		for a in roster.gen_troops(p.fac, ceili(need / MK), 0.6):
			Rules.add_troops(p.troops, a.type, a.n)

## A beaten ruler survives three times out of four (only after a field loss).
func ruler_spared(p: Dictionary) -> bool:
	if not p.get("ruler", false) or roster.rng.randf() > 0.78:
		return false
	ruler_home(p)
	return true

# ---------- the player's oath ----------

func oath_why(f: String) -> String:
	if player.liege != "":
		return "Ты уже служишь: %s." % _fname(player.liege)
	if not f in Rules.REAL_FACTIONS or not wars.alive(f):
		return "Нельзя."
	if int(player.hero.get("lvl", 1)) < OATH_LVL:
		return "Нужен %d уровень героя." % OATH_LVL
	if float(player.rel.get(f, 0)) < OATH_REL:
		return "Нужны отношения от %d (сейчас %d). Выполняй задания и бей врагов фракции." % [OATH_REL, roundi(float(player.rel.get(f, 0)))]
	if wars.wars.is_empty():
		return "Сейчас мир: сюзерену нужны воины для войны. Подожди, пока начнётся."
	return ""

func swear(f: String) -> String:
	var why := oath_why(f)
	if why != "":
		return why
	player.liege = f
	player.oath_day = _day()
	player.strikes = 0
	player.summons = null
	player.rel[f] = minf(100.0, float(player.rel.get(f, 0)) + 10.0)
	vassal_enemies()
	message.emit("Ты принёс присягу: %s. Враги сюзерена — твои враги, взамен он платит жалованье и награждает за походы." % _fname(f))
	return ""

func leave(why := "") -> void:
	var f: String = player.liege
	if f == "":
		return
	player.liege = ""
	player.summons = null
	if why == "betray":
		player.rel[f] = minf(float(player.rel.get(f, 0)), -45.0)
	elif why == "expelled":
		player.rel[f] = maxf(-100.0, float(player.rel.get(f, 0)) - 15.0)
	else:
		player.rel[f] = maxf(-100.0, float(player.rel.get(f, 0)) - 20.0)
	message.emit("Сюзерен изгнал тебя со службы за неповиновение." if why == "expelled" else ("Ты предал сюзерена!" if why == "betray" else "Ты оставил службу: %s." % _fname(f)))

func vassal_enemies() -> void:
	if player.liege == "":
		return
	for f in Rules.REAL_FACTIONS:
		if f != player.liege and wars.at_war(player.liege, f) and float(player.rel.get(f, 0)) > -25.0:
			player.rel[f] = -25.0

func pay() -> int:
	return 16 + int(player.hero.get("lvl", 1)) * 6

func vassal_day() -> void:
	if player.liege == "":
		return
	var f: String = player.liege
	if not wars.alive(f):
		player.liege = ""
		return
	player.gold += pay()
	vassal_enemies()
	var call: Variant = player.summons
	if call is Dictionary and wars.now_h() > int(call.until):
		if not call.joined:
			player.strikes += 1
			player.rel[f] = maxf(-100.0, float(player.rel.get(f, 0)) - 5.0)
			message.emit("Ты не явился на зов сюзерена (%d/3)." % player.strikes)
			if player.strikes >= 3:
				leave("expelled")
		player.summons = null

func vassal_reward(s: Dictionary) -> void:
	var g := 120 + (160 if s.kind == "castle" else (120 if s.kind == "town" else 0))
	player.gold += g
	player.rel[player.liege] = minf(100.0, float(player.rel.get(player.liege, 0)) + 6.0)
	message.emit("Ты участвовал во взятии %s: награда %d золота." % [s.name, g])
	if siege != null and (s.kind == "village" or roster.rng.randf() < 0.4):
		siege.capture(player, s)
		message.emit("Сюзерен жалует тебе %s в лен." % s.name)

# ---------- luring a house (only a vassal can) ----------

func lure_cost(c: Dictionary) -> int:
	return roundi((400.0 + force(c) * 5.0) * float(TRAITS[c.trait].cost) / 10.0) * 10

func lure_chance(c: Dictionary) -> float:
	var t: Dictionary = TRAITS[c.trait]
	var l: String = player.liege
	var ch := (100.0 - float(c.loy)) / 130.0 + float(player.rel.get(l, 0)) / 500.0 + int(player.hero.get("lvl", 1)) * 0.008
	if c.trait == "ambit" and wars.power(l) > wars.power(c.fac) * 1.2:
		ch += 0.15
	if c.trait == "proud" and int(c.loy) < 45:
		ch += 0.1
	if c.trait == "greedy":
		ch += 0.08
	return clampf(ch * float(t.luck), 0.03, 0.8)

func lure_why(p: Dictionary) -> String:
	var c := clan_of(p)
	if c.is_empty():
		return "Это не знатный род."
	if c.rule:
		return "Это правящий род: он не предаст трон."
	if player.liege == "":
		return "Звать род к себе может только вассал: присягни фракции."
	if c.fac == player.liege:
		return "Они и так служат твоему сюзерену."
	if not wars.alive(player.liege):
		return "Сюзерен пал."
	if _day() < int(player.lure_day) + LURE_CD:
		return "Ты недавно уже вёл переговоры. Подожди %d дн." % (int(player.lure_day) + LURE_CD - _day())
	if _day() < int(c.cd):
		return "Род недавно сменил сторону и пока не станет метаться."
	if of_faction(c.fac).size() <= CLAN_MIN:
		return "Этот дом остался без союзников и не покинет своё государство."
	if of_faction(player.liege).size() >= CLAN_MAX:
		return "У твоего сюзерена уже слишком много родов."
	return ""

func lure_try(p: Dictionary) -> Dictionary:
	var c := clan_of(p)
	var why := lure_why(p)
	if why != "":
		return {"ok": false, "txt": why}
	var cost := lure_cost(c)
	if player.gold < cost:
		return {"ok": false, "txt": "Нужно %d золота." % cost}
	player.lure_day = _day()
	var l: String = player.liege
	var from: String = c.fac
	if roster.rng.randf() < lure_chance(c):
		player.gold -= cost
		defect(c, l, false)
		var back := roundi(cost * 0.4)
		player.gold += back
		player.rel[l] = minf(100.0, float(player.rel.get(l, 0)) + 6.0)
		player.rel[from] = maxf(-100.0, float(player.rel.get(from, 0)) - 10.0)
		message.emit("%s перешёл на сторону %s. Сюзерен возместил %d золота." % [c.name, _gen(l), back])
		return {"ok": true, "txt": "%s переходит к %s!" % [c.name, _gen(l)]}
	player.gold -= roundi(cost * 0.5)
	player.rel[from] = maxf(-100.0, float(player.rel.get(from, 0)) - 8.0)
	message.emit("Переговоры с %s провалились: золото потеряно." % c.name)
	return {"ok": false, "txt": "%s отказал и забрал половину задатка." % c.name}

func to_dict() -> Dictionary:
	return {"clans": clans.duplicate(true), "switched": switched.duplicate(), "rulers": rulers.duplicate(true), "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	clans = []
	for c in d.get("clans", []):
		var x: Dictionary = c.duplicate(true)
		for k in ["id", "loy", "cd", "vac"]:
			x[k] = int(x.get(k, 0))
		if x.get("home") != null:
			x.home = int(x.home)
		clans.append(x)
	switched = {}
	for k in d.get("switched", {}):
		switched[k] = int(d.switched[k])
	rulers = {}
	for k in d.get("rulers", {}):
		var r: Dictionary = d.rulers[k].duplicate()
		r.dead = int(r.get("dead", 0))
		r.until = int(r.get("until", 0))
		rulers[k] = r
	next_id = int(d.get("next_id", next_id))
