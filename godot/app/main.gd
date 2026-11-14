extends Node2D
## Composition root: the only place that connects storage, scenario and view.
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const BattleView = preload("res://battle/presentation/scene.tscn")
const EncounterAftermath = preload("res://app/encounter_aftermath.gd")
const GoodsCatalog = preload("res://campaign/data/goods_catalog.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const REWARD_SEED_OFFSET := 1
const DEMO_REWARD_TEXT := "\nПогибло: %d · Ранено: %d · Золото: %+d · Опыт: +%d · Трофеи: %s"
const NO_DROPS := "—"
const COMPANION_XP_TEXT := "%s +%d опыта"
const COMPANION_LEVEL_TEXT := " (ур. %d)"
@export var battle_setup: Setup = preload("res://battle/data/demo_battle.tres")
var _demo_party: Dictionary

func _ready() -> void:
	var catalog := Catalog.new()
	if not catalog.load_data():
		push_error("Cannot load battle catalog")
		return
	var gear_catalog := GearCatalog.new()
	if not gear_catalog.load_data():
		push_error("Cannot load gear catalog")
		return
	var perk_catalog := PerkCatalog.new()
	if not perk_catalog.load_data():
		push_error("Cannot load perk catalog")
		return
	var companion_catalog := CompanionCatalog.new()
	if not companion_catalog.load_data():
		return
	var goods := GoodsCatalog.new()
	if not goods.load_data():
		push_error("Cannot load trade goods catalog")
		return
	var session = Factory.create(battle_setup, catalog, gear_catalog, perk_catalog, companion_catalog)
	if session == null:
		push_error("Invalid battle setup")
		return
	var view = BattleView.instantiate()
	view.name = "Battle"
	view.configure(session)
	var profile := battle_setup.hero_profile.duplicate(true)
	var roster: Array[Dictionary] = []
	for saved in battle_setup.companion_profiles:
		var resolved := CompanionProfile.resolve(saved, companion_catalog)
		roster.append(resolved.profile)
	_demo_party = {"troops": battle_setup.player_army.duplicate(true), "hero": profile, "gold": 0, "comps": roster}
	var opponent := {"troops": battle_setup.enemy_army.duplicate(true), "fac": battle_setup.enemy_faction}
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_setup.seed + REWARD_SEED_OFFSET
	var mounted := bool(HeroGear.resolve(profile, gear_catalog).get("mounted", false))
	var bridge := EncounterAftermath.new(session)
	view.battle_finished.connect(_show_aftermath.bind(view, bridge, opponent, mounted, catalog, gear_catalog, goods, rng, companion_catalog, perk_catalog), CONNECT_ONE_SHOT)
	add_child(view)

func _show_aftermath(view: Node2D, bridge: EncounterAftermath, opponent: Dictionary, mounted: bool, troops: Catalog, gear: GearCatalog, goods: GoodsCatalog, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog) -> void:
	var resolved := bridge.resolve(_demo_party, opponent, mounted, troops, gear, goods, rng, companions, perks)
	if resolved.is_empty():
		return
	_demo_party = resolved.party
	var summary: Dictionary = resolved.summary
	var names: PackedStringArray = []
	var trade_goods := goods.definitions()
	for drop in summary.drops:
		var item := gear.get_item(drop.id)
		var display_name: String = item.name if not item.is_empty() else trade_goods[drop.id].n
		names.append("%s ×%d" % [display_name, drop.n])
	var text := DEMO_REWARD_TEXT % [summary.lost, summary.wounded, summary.loot - summary.lost_gold, summary.xp, NO_DROPS if names.is_empty() else ", ".join(names)]
	var companions_text := PackedStringArray()
	for profile in _demo_party.comps:
		if not summary.comps.has(profile.id):
			continue
		var gain: Dictionary = summary.comps[profile.id]
		var line := COMPANION_XP_TEXT % [profile.name, gain.xp]
		if gain.levels_gained > 0:
			line += COMPANION_LEVEL_TEXT % profile.lvl
		companions_text.append(line)
	if not companions_text.is_empty():
		text += "\n" + " · ".join(companions_text)
	view.show_result_summary(text)
