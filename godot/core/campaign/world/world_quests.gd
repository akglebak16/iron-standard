extends RefCounted
## Town quest boards and the player's quests on the map (genQuests, questText, questsOnEnter, questsScoutTick, acceptQuest,
## questDone and the deadline check in src/05_world.js). Camp and purge progress after a battle lives in core/campaign/rules/battle_quests.gd.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Market = preload("res://core/campaign/economy/market.gd")

const MAX_QUESTS := 4
const BOARD_SIZE := 3
const BOARD_DAYS := 12
const SCOUT_RADIUS := 120.0

signal message(text: String)

var map: RefCounted
var goods: Dictionary
var rng: RandomNumberGenerator
var wars: RefCounted   # garrison_of for muster quests
var catalog: RefCounted  # troop catalog (tiers)
var next_id := 1

func _init(world_map: RefCounted, goods_table: Dictionary, troop_catalog: RefCounted, world_wars: RefCounted, random: RandomNumberGenerator) -> void:
	map = world_map
	goods = goods_table
	catalog = troop_catalog
	wars = world_wars
	rng = random

func _pick(list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]

func _dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

func _nearest(list: Array, s: Dictionary, k: int) -> Array:
	var l := list.filter(func(x): return x.id != s.id)
	l.sort_custom(func(a, b): return _dist(a, s) < _dist(b, s))
	return l.slice(0, k)

## Daily: refills the boards of the towns of real factions (three offers each, older than 12 days drop off).
func gen_boards(day: int) -> void:
	var camps: Array = map.settles.filter(func(c): return c.kind == "camp")
	for s in map.settles:
		if s.kind != "town":
			continue
		if not s.fac in Rules.REAL_FACTIONS:
			s.board = []
			continue
		var board: Array = s.get("board", []) if s.get("board") is Array else []
		board = board.filter(func(q): return day - int(q.day) < BOARD_DAYS)
		var near_camps := _nearest(camps, s, 3)
		var guard := 0
		while board.size() < BOARD_SIZE and guard < 20:
			guard += 1
			var q := _make(s, day, near_camps)
			if not q.is_empty():
				board.append(q)
		s.board = board

func _make(s: Dictionary, day: int, camps: Array) -> Dictionary:
	var base := {"id": next_id, "from": s.id, "fac": s.fac, "day": day}
	var kinds := ["deliver", "deliver", "supply", "supply", "purge", "muster"]
	if not camps.is_empty():
		kinds += ["camp", "camp", "scout"]
	var kind: String = _pick(kinds)
	var q := {}
	match kind:
		"camp":
			q = {"type": "camp", "sid": _pick(camps).id, "reward": rng.randi_range(300, 520), "dl": day + 20}
		"scout":
			q = {"type": "scout", "sid": _pick(camps).id, "seen": false, "reward": rng.randi_range(160, 260), "dl": day + 14}
		"purge":
			var n := rng.randi_range(2, 3)
			q = {"type": "purge", "sid": s.id, "n": n, "got": 0, "reward": 150 + n * 90, "dl": day + 16}
		"supply":
			var ds := _nearest(map.settles.filter(func(x): return x.kind == "town" or x.kind == "castle"), s, 6)
			if ds.is_empty():
				return {}
			var d: Dictionary = _pick(ds)
			var ids: Array = goods.keys().filter(func(k): return not goods[k].get("lux", false))
			var item: String = _pick(ids)
			var n := rng.randi_range(6, 14)
			var dist := _dist(d, s)
			q = {"type": "supply", "sid": d.id, "item": item, "n": n, "reward": roundi(n * float(goods[item].p) * 1.3 + dist * 0.15 + 40.0), "dl": day + ceili(dist / 150.0) + 8}
		"muster":
			var ds := _nearest(map.settles.filter(func(x): return (x.kind == "town" or x.kind == "castle") and x.fac == s.fac), s, 4)
			if ds.is_empty():
				return {}
			var d: Dictionary = _pick(ds)
			var n := rng.randi_range(6, 12)
			var dist := _dist(d, s)
			q = {"type": "muster", "sid": d.id, "n": n, "reward": roundi(n * 48.0 + dist * 0.1), "dl": day + ceili(dist / 150.0) + 8}
		_:
			var ds := _nearest(map.settles.filter(func(x): return x.kind != "camp"), s, 8)
			if ds.is_empty():
				return {}
			var d: Dictionary = _pick(ds)
			var dist := _dist(d, s)
			q = {"type": "deliver", "sid": d.id, "reward": roundi(90.0 + dist * 0.22), "dl": day + ceili(dist / 150.0) + 4}
	next_id += 1
	base.merge(q)
	return base

func text(q: Dictionary) -> String:
	var s: Dictionary = map.settlement_by_id(q.sid)
	var f: Dictionary = map.settlement_by_id(q.from)
	var sn: String = s.get("name", "?")
	match q.type:
		"camp":
			return "Разгромить разбойников: «%s»" % sn
		"scout":
			return "Разведать лагерь «%s» и вернуться в %s" % [sn, f.get("name", "?")]
		"purge":
			return "Разбить разбойничьи отряды в пути: %d (%d/%d)" % [q.n, int(q.get("got", 0)), q.n]
		"supply":
			return "Привезти в %s: %s ×%d" % [sn, String(goods[q.item].n).to_lower(), q.n]
		"muster":
			return "Прислать в гарнизон %s бойцов 2 уровня и выше: %d" % [sn, q.n]
	return "Доставить груз в %s" % sn

func detail(q: Dictionary, from: Dictionary) -> String:
	var s: Dictionary = map.settlement_by_id(q.sid)
	var lg := "%s лиг" % str(roundf(_dist(s, from) / 10.0) / 10.0)
	match q.type:
		"camp", "scout":
			return "Расстояние: " + lg
		"purge":
			return "Любые разбойничьи отряды на дорогах"
		"supply":
			return "Товар покупаешь сам, расстояние: " + lg
		"muster":
			return "Бойцы переходят в гарнизон, расстояние: " + lg
	return "Груз уже погружен"

## "" on success, otherwise the reason.
func accept(p, s: Dictionary, qid: int) -> String:
	if p.quests.size() >= MAX_QUESTS:
		return "Не больше четырёх заданий одновременно."
	var board: Array = s.get("board", [])
	for i in board.size():
		if int(board[i].id) == qid:
			p.quests.append(board[i])
			board.remove_at(i)
			return ""
	return "Задание уже взято."

func done(p, q: Dictionary, reward_bonus: float) -> void:
	p.quests.erase(q)
	var rw := roundi(float(q.reward) * (1.0 + reward_bonus))
	p.gold += rw
	p.rel[q.fac] = minf(100.0, float(p.rel.get(q.fac, 0)) + 6.0)
	message.emit("Задание выполнено: %s. Награда: %d золота." % [text(q), rw])

## Entering a settlement hands in deliveries, supplies, musters and finished scouting.
func on_enter(p, s: Dictionary, reward_bonus: float) -> void:
	for q in p.quests.duplicate():
		if q.type == "deliver" and q.sid == s.id:
			done(p, q, reward_bonus)
		elif q.type == "scout" and q.get("seen", false) and q.from == s.id:
			done(p, q, reward_bonus)
		elif q.type == "supply" and q.sid == s.id:
			var have := int(p.inv.get(q.item, 0))
			if have >= int(q.n):
				p.inv[q.item] = have - int(q.n)
				if p.inv[q.item] <= 0:
					p.inv.erase(q.item)
				done(p, q, reward_bonus)
			else:
				message.emit("Для задания нужно ещё: %s ×%d" % [String(goods[q.item].n).to_lower(), int(q.n) - have])
		elif q.type == "muster" and q.sid == s.id:
			var pool: Array = p.troops.filter(func(t): return int(catalog.get_troop(t.type).tier) >= 2)
			pool.sort_custom(func(a, b): return int(catalog.get_troop(a.type).tier) < int(catalog.get_troop(b.type).tier))
			var have := 0
			for t in pool:
				have += int(t.n)
			if have >= int(q.n) and Rules.troop_count(p.troops) - int(q.n) >= 1:
				var need := int(q.n)
				for t in pool.duplicate():
					var k := mini(int(t.n), need)
					if k > 0:
						Rules.remove_troops(p.troops, t.type, k)
						Rules.add_troops(wars.garrison_of(s), t.type, k)
						need -= k
				done(p, q, reward_bonus)
			else:
				message.emit("Для задания нужно бойцов 2 уровня и выше: %d (у тебя %d)" % [q.n, have])

## Hourly: the scouted camp is marked when the party passes near it.
func scout_tick(p) -> void:
	for q in p.quests:
		if q.type == "scout" and not q.get("seen", false):
			var c: Dictionary = map.settlement_by_id(q.sid)
			if not c.is_empty() and Vector2(c.x - p.x, c.y - p.y).length() < SCOUT_RADIUS:
				q.seen = true
				message.emit("Лагерь «%s» разведан. Возвращайся в %s." % [c.name, map.settlement_by_id(q.from).get("name", "?")])

## Daily: late quests fail and cost relations.
func deadline_day(p, day: int) -> void:
	for q in p.quests.duplicate():
		if day > int(q.dl):
			p.quests.erase(q)
			p.rel[q.fac] = maxf(-100.0, float(p.rel.get(q.fac, 0)) - 4.0)
			message.emit("Срок задания истёк: " + text(q))
