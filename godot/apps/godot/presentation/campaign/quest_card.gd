extends RefCounted
## A quest card of the journal (jqCard, jqProgress, jqProblem, jqTarget, jqDays in src/06f_jquests.js): what kind of
## errand it is, who gave it, how far, how much is done, what stands in the way, the reward and the time left.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Economy = preload("res://core/campaign/economy/party_economy.gd")

const TYPES := {"camp": ["Разгром", "skull"], "scout": ["Разведка", "zoom"], "purge": ["Охота", "sword"],
	"supply": ["Поставка", "bag"], "muster": ["Пополнение", "men"], "deliver": ["Доставка", "horse"]}
const HOSTILE_RELATION := -20.0

static func days(n: int) -> String:
	var a := absi(n) % 100
	var b := a % 10
	return "%d %s" % [n, "дней" if a > 10 and a < 20 else ("день" if b == 1 else ("дня" if b >= 2 and b <= 4 else "дней"))]

## Where to go now: a scouted camp sends you back to the client; a hunt has no single place.
static func target(q: Dictionary, map: RefCounted) -> Dictionary:
	if q.type == "purge":
		return {}
	return map.settlement_by_id(q.from if q.type == "scout" and q.get("seen", false) else q.sid)

## [have, need, caption] or [] for errands without a counter.
static func progress(q: Dictionary, player: RefCounted, goods: Dictionary, troops: RefCounted) -> Array:
	match q.type:
		"purge":
			return [int(q.get("got", 0)), int(q.n), "Разбито отрядов"]
		"scout":
			var seen := bool(q.get("seen", false))
			return [1 if seen else 0, 2, "Лагерь разведан — вернись к заказчику" if seen else "Подойди к лагерю, затем вернись"]
		"supply":
			return [mini(int(player.inv.get(q.item, 0)), int(q.n)), int(q.n), "В обозе: " + String(goods.get(q.item, {}).get("n", q.item)).to_lower()]
		"muster":
			var have := 0
			for stack in player.troops:
				if int(troops.get_troop(stack.type).get("tier", 0)) >= 2:
					have += int(stack.n)
			return [mini(have, int(q.n)), int(q.n), "Бойцов 2 уровня и выше в отряде"]
	return []

## What prevents finishing it, or "".
## The bandits sitting in a camp, or {} when the camp is empty (settlement.camp holds the party id).
static func camp_party(camp: Dictionary, roster: RefCounted) -> Dictionary:
	if camp.is_empty() or camp.get("camp") == null:
		return {}
	return roster.party_by_id(camp.camp)

static func problem(q: Dictionary, left: int, player: RefCounted, map: RefCounted, factions: RefCounted, done: Array, roster: RefCounted = null) -> String:
	if left < 0:
		return "Задание снимут, отношения с заказчиком ухудшатся"
	var t := target(q, map)
	if q.type == "camp":
		var camp: Dictionary = map.settlement_by_id(q.sid)
		if not camp.is_empty() and (roster == null or camp_party(camp, roster).is_empty()):
			return "Лагерь пуст — разбойники ещё не вернулись"
	if not t.is_empty() and t.kind != "camp":
		if t.fac == "undead":
			return "%s в руинах" % t.name
		if t.fac in Rules.REAL_FACTIONS and float(player.rel.get(t.fac, 0)) < HOSTILE_RELATION:
			return "Ворота %s закрыты: ты враг %s" % [t.name, factions.get_faction(t.fac).get("gen", t.fac)]
	if q.type in ["muster", "supply"] and not done.is_empty() and done[0] < done[1]:
		return ("Не хватает бойцов: %d" if q.type == "muster" else "Нужно докупить: %d") % (done[1] - done[0])
	return ""

static func describe(q: Dictionary, state: RefCounted, factions: RefCounted, reward_bonus: float) -> Dictionary:
	var map: RefCounted = state.map
	var player: RefCounted = state.player
	var kind: Array = TYPES.get(q.type, ["Поручение", "flag"])
	var from: Dictionary = map.settlement_by_id(q.from)
	var t := target(q, map)
	var day: int = state.clock.day
	var left: int = int(q.dl) - day
	var total := maxi(1, int(q.dl) - int(q.get("day", day)))
	var done := progress(q, player, state.market.goods, state.roster.catalog)
	var warn := problem(q, left, player, map, factions, done, state.roster)
	var hard := left < 0 or "закрыты" in warn or "руинах" in warn
	var tags: Array = []
	if left < 0:
		tags.append(["просрочено", -1])
	elif left <= 2:
		tags.append(["срочно", -1])
	if not done.is_empty() and done[0] >= done[1] and not hard:
		tags.append(["готово к сдаче", 1])
	var detail: String = String(state.quests.detail(q, {"x": player.x, "y": player.y})).replace("асстояние: ", "асстояние от тебя: ")
	if q.type == "scout" and q.get("seen", false) and not t.is_empty():
		detail += " · до %s: %s лиг" % [t.name, str(roundf(Vector2(player.x, player.y).distance_to(Vector2(t.x, t.y)) / 10.0) / 10.0)]
	var camp_size := -1
	if q.type == "camp":
		var bandits := camp_party(map.settlement_by_id(q.sid), state.roster)
		if not bandits.is_empty():
			camp_size = Economy.troop_count(bandits.troops)
	return {"type": kind[0], "icon": kind[1], "tags": tags, "title": state.quests.text(q),
		"from": from.get("name", "—"), "faction": q.fac, "faction_name": factions.get_faction(q.fac).get("name", q.fac),
		"detail": detail, "camp_size": camp_size, "progress": done, "warning": warn, "blocked": hard,
		"reward": roundi(float(q.reward) * (1.0 + reward_bonus)),
		"deadline": "срок вышел" if left < 0 else ("последний день" if left == 0 else "осталось " + days(left)), "until": "до дня %d" % int(q.dl),
		"time_left": clampf(float(left) / total, 0.0, 1.0), "target": t if not hard else {}}
