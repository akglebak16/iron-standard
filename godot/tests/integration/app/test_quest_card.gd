extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const QuestCard = preload("res://apps/godot/presentation/campaign/quest_card.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var factions := FactionCatalog.new()
	assert(ContentLoader.populate(factions))
	assert(QuestCard.days(1) == "1 день" and QuestCard.days(3) == "3 дня" and QuestCard.days(11) == "11 дней" and QuestCard.days(22) == "22 дня")
	var towns: Array = s.map.settles.filter(func(t): return t.kind == "town" and t.fac == "emp")
	var from: Dictionary = towns[0]
	var to: Dictionary = towns[1]
	var day: int = s.clock.day
	# jqCard: a supply errand two days from the deadline, half the goods bought
	var supply := {"id": 901, "type": "supply", "sid": to.id, "from": from.id, "fac": "emp", "day": day, "dl": day + 2, "reward": 100, "item": "grain", "n": 4}
	s.player.inv["grain"] = 2
	s.player.quests = [supply]
	var card := QuestCard.describe(supply, s, factions, 0.1)
	assert(card.type == "Поставка" and card.icon == "bag")
	assert(card.tags == [["срочно", -1]], "Two days left is urgent")
	assert(card.progress[0] == 2 and card.progress[1] == 4 and card.warning == "Нужно докупить: 2")
	assert(card.reward == 110, "The quest perk raises the reward")
	assert(card.deadline == "осталось 2 дня" and card.until == "до дня %d" % (day + 2))
	assert(card.detail.begins_with("Товар покупаешь сам, расстояние от тебя: "))
	assert(card.from == from.name and not card.target.is_empty())
	s.player.inv["grain"] = 4
	assert(["готово к сдаче", 1] in QuestCard.describe(supply, s, factions, 0.0).tags)
	# overdue: the card is blocked and has no map button
	supply.dl = day - 1
	var late := QuestCard.describe(supply, s, factions, 0.0)
	assert(late.tags == [["просрочено", -1]] and late.blocked and late.target.is_empty() and late.warning.begins_with("Задание снимут"))
	# a hostile client town closes its gates
	supply.dl = day + 5
	s.player.rel["emp"] = -50.0
	var closed := QuestCard.describe(supply, s, factions, 0.0)
	assert(closed.blocked and "закрыты" in closed.warning)
	s.player.rel["emp"] = 0.0
	# the journal draws the cards
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	pw.open_for(s, "quests")
	assert(pw.body.find_child("QuestCard", true, false) != null and pw.body.find_child("QuestTime", true, false) != null)
	assert(pw.body.find_child("QuestSummary", true, false) != null)
	var targets: Array = []
	pw.quest_target.connect(func(x, y): targets.append(Vector2(x, y)))
	var map_buttons := pw.body.find_children("*", "Button", true, false).filter(func(b): return b.text == "Показать на карте")
	assert(map_buttons.size() == 1)
	map_buttons[0].pressed.emit()
	var expected := QuestCard.target(supply, s.map)
	assert(targets == [Vector2(expected.x, expected.y)], "map action emits the actual quest destination")
	assert(not pw.visible and s.player.quests.size() == 1, "map action closes UI without completing or losing the quest")
	s.dispose()
	print("Quest card tests passed")
	quit(0)
