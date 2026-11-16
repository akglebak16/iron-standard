extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")

func _texts(s) -> Array:
	return s.journal.map(func(e): return e.text)

func _has(s, part: String) -> bool:
	for t in _texts(s):
		if String(t).contains(part):
			return true
	return false

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(7, data, "emp", ContentLoader.registry())
	# worldUpdate: a party standing still freezes the world
	var hour: int = s.clock.hour
	s.player.stop()
	assert(s.advance(5.0) == 0 and s.clock.hour == hour, "No time passes while the party stands")
	# Z: wait on the spot, then go on
	assert(s.toggle_wait() == "Отряд ждёт" and s.waiting)
	assert(s.advance(5.0) > 0, "Waiting lets time pass")
	assert(s.toggle_wait() == "Снова в путь" and not s.waiting)
	assert(s.advance(5.0) == 0)
	# walking lets time pass too
	assert(s.player.path_to(s.map.paths, s.player.x + 60, s.player.y))
	assert(s.advance(1.0) > 0)
	s.player.stop()
	# entering a settlement ends the wait (townEnter)
	s.waiting = true
	var home: Dictionary = s.map.settlement_by_id(s.home_id)
	s.player.x = home.x
	s.player.y = home.y + 20
	s.enter(home)
	assert(not s.waiting)
	# encAttack: relations drop and the chronicle says so
	var caravan: Dictionary = s.roster.make_party("caravan", "nord", "Караван", s.player.x, s.player.y, [{"type": "n1", "n": 3}])
	var before := float(s.player.rel.get("nord", 0))
	s.attack(caravan)
	assert(is_equal_approx(float(s.player.rel.nord), maxf(-100.0, before - 12.0)))
	assert(_has(s, "Ты напал на Нордмарка. Отношения испорчены."))
	# a won battle is written to the chronicle with its loot (applyBattleResult)
	var bridge = Bridge.new(ContentLoader.registry(), RandomNumberGenerator.new())
	bridge.rng.seed = 3
	s.player.troops = [{"type": "e1", "n": 60}]
	var weak: Dictionary = s.roster.make_party("bandit", "bandit", "Шайка", s.player.x + 5, s.player.y, [{"type": "b1", "n": 3}])
	var ticket: RefCounted = bridge.begin(s, weak)
	var won: Dictionary = bridge.calculate(ticket)
	assert(won.summary.win)
	assert(_has(s, "Победа над отрядом «Шайка». Добыча: %d золота." % int(won.summary.loot)))
	# a lost one too
	s.player.troops = [{"type": "e1", "n": 2}]
	var lord: Dictionary = s.roster.make_party("lord", "nord", "Лорд", s.player.x, s.player.y, [{"type": "n1", "n": 90}])
	var lost: Dictionary = bridge.calculate(bridge.begin(s, lord))
	assert(not lost.summary.win)
	assert(_has(s, "Ты потерпел поражение от «Лорд»."))
	# companion growth and the hero's level (compsAfter)
	var before_lines: int = s.journal.size()
	Bridge._journal_progress(s, {"levels_gained": 2, "comps": {"x": {"name": "Ольгерд", "skill": "Следопыт", "ranks": ["II"], "levels_gained": 1, "lvl": 4}}})
	assert(s.journal.size() == before_lines + 3)
	assert(_has(s, "Ольгерд: умение «Следопыт» окрепло (ранг II)."))
	assert(_has(s, "Ольгерд достигает уровня 4."))
	assert(_has(s, "Очки: атрибуты +4, перки +2."))
	# captureSettle tells what the new holding brings
	var town: Dictionary = s.map.settles.filter(func(t): return t.kind == "town" and t.fac == "khan")[0]
	s.siege.capture(s.player, town)
	assert(_has(s, "Город %s теперь твой! Доход" % town.name))
	s.dispose()
	print("World time and journal tests passed")
	quit(0)
