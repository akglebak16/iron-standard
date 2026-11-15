extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const HeroStats = preload("res://core/battle/data/hero_stats.gd")
const GearComparison = preload("res://apps/godot/presentation/campaign/gear_comparison.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var gear = s.gear
	var hero: Dictionary = s.player.hero
	HeroEquip.ensure(hero)
	var two := ""
	var shield := ""
	for id in gear.definitions():
		var it: Dictionary = gear.get_item(id)
		if it.slot == "melee" and int(it.get("hands", 1)) == 2 and two == "":
			two = id
		if it.slot == "shield" and shield == "":
			shield = id
	# comparison does not touch the real hero
	var before: Dictionary = hero.eq.duplicate(true)
	var cmp := GearComparison.compare(hero, gear.get_item(two), gear, s.perks, HeroStats.preview)
	assert(hero.eq == before, "comparison works on a copy")
	assert(cmp.rows.size() == 5 and "Кулаки" not in cmp.title and "вместо:" in cmp.title)
	var damage: Dictionary = cmp.rows[0]
	assert(damage.name == "Урон" and float(damage.next) > float(damage.old) and damage.trend == 1)
	var cooldown: Dictionary = cmp.rows[3]
	assert(cooldown.trend == (1 if float(cooldown.delta) < 0.0 else -1 if float(cooldown.delta) > 0.0 else 0))
	# the same item gives no change
	var same := GearComparison.compare(hero, gear.get_item(hero.eq.melee), gear, s.perks, HeroStats.preview)
	for r in same.rows:
		assert(r.trend == 0 and is_zero_approx(float(r.delta)))
	# a shield with a two-hander is refused, a two-hander drops the shield
	hero.eq.melee = two
	var refused := GearComparison.compare(hero, gear.get_item(shield), gear, s.perks, HeroStats.preview)
	assert(refused.rows.is_empty() and refused.note != "")
	hero.eq.melee = "sword_old"
	hero.eq.shield = shield
	var dropped := GearComparison.compare(hero, gear.get_item(two), gear, s.perks, HeroStats.preview)
	assert("Щит уйдёт в рюкзак." in dropped.note and hero.eq.shield == shield)
	# chronicle kinds survive a save and old entries still load
	s.log_world("плохо", WorldState.JOURNAL_BAD)
	s.log_world("нейтрально")
	assert(s.journal[0].kind == 0 and s.journal[1].kind == 1)
	s.journal.append({"day": 1, "text": "старая запись"})
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back != null and int(back.journal[1].kind) == 1)
	# the windows draw both
	var pw := PartyWindow.new()
	pw.stat_preview = HeroStats.preview
	root.add_child(pw)
	await process_frame
	s.journal.clear()
	pw.open_for(s, "journal")
	assert(pw.body.get_child_count() == 1, "empty chronicle shows one note")
	s.log_world("a", WorldState.JOURNAL_GOOD)
	s.log_world("b")
	pw.render()
	var day_box := pw.body.find_child("ChronicleDay_%d" % s.clock.day, true, false)
	assert(day_box != null and day_box.get_child_count() == 2, "both entries of the day are listed")
	s.player.inv[two] = 1
	pw.open_for(s, "gear")
	pw._selected_gear = two
	pw.render()
	assert(pw.body.find_child("GearComparison", true, false) != null, "selected item shows the comparison")
	print("Gear comparison and chronicle tests passed")
	quit(0)
