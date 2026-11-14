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
const PerkEffects = preload("res://characters/rules/perk_effects.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const REWARD_SEED_OFFSET := 1
const DEMO_REWARD_TEXT := "\nПогибло: %d · Ранено: %d · Золото: %+d · Опыт: +%d · Трофеи: %s"
const NO_DROPS := "—"
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
	var effects := PerkEffects.own(profile, perk_catalog)
	var roster: Array[Dictionary] = []
	for saved in battle_setup.companion_profiles:
		var resolved := CompanionProfile.resolve(saved, companion_catalog)
		roster.append(resolved.profile)
		for effect in resolved.party_effects:
			effects[effect] = float(effects.get(effect, 0)) + resolved.party_effects[effect]
	_demo_party = {"troops": battle_setup.player_army.duplicate(true), "hero": profile, "gold": 0, "comps": roster}
	var opponent := {"troops": battle_setup.enemy_army.duplicate(true), "fac": battle_setup.enemy_faction}
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_setup.seed + REWARD_SEED_OFFSET
	var mounted := bool(HeroGear.resolve(profile, gear_catalog).get("mounted", false))
	var bridge := EncounterAftermath.new(session)
	view.battle_finished.connect(_show_aftermath.bind(view, bridge, opponent, effects, mounted, catalog, gear_catalog, goods, rng), CONNECT_ONE_SHOT)
	add_child(view)

func _show_aftermath(view: Node2D, bridge: EncounterAftermath, opponent: Dictionary, effects: Dictionary, mounted: bool, troops: Catalog, gear: GearCatalog, goods: GoodsCatalog, rng: RandomNumberGenerator) -> void:
	var resolved := bridge.resolve(_demo_party, opponent, effects, mounted, troops, gear, goods, rng)
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
	view.show_result_summary(DEMO_REWARD_TEXT % [summary.lost, summary.wounded, summary.loot - summary.lost_gold, summary.xp, NO_DROPS if names.is_empty() else ", ".join(names)])
