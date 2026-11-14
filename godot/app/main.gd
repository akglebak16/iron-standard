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
const PresentationPreferences = preload("res://app/presentation_preferences.gd")
const REWARD_SEED_OFFSET := 1
const DEMO_REWARD_TEXT := "\nПогибло: %d · Ранено: %d · Золото: %+d · Опыт: +%d · Трофеи: %s"
const NO_DROPS := "—"
const COMPANION_XP_TEXT := "%s +%d опыта"
const COMPANION_LEVEL_TEXT := " (ур. %d)"
const RECOVERY_TEXT := "\nГерой очнулся у города %s."
const QUEST_REWARDS_TEXT := "\nЗаданий выполнено: %d · Награда: %d золота"
const BARROW_CLEARED_TEXT := "\nЧёрный курган разрушен."
@export var demo_world: Dictionary = {}
@export var demo_party_position := Vector2.ZERO
@export var battle_setup: Setup = preload("res://battle/data/demo_battle.tres")
var _demo_party: Dictionary
var _demo_world: Dictionary
var presentation_preferences := PresentationPreferences.new()

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
	var audio := presentation_preferences.read()
	view.configure(session, audio.effects, audio.music, presentation_preferences.read_blood(), battle_setup.seed, battle_setup.biome)
	view.audio_preferences_changed.connect(_save_audio_preferences)
	view.blood_preference_changed.connect(_save_blood_preference)
	var profile := battle_setup.hero_profile.duplicate(true)
	var roster: Array[Dictionary] = []
	for saved in battle_setup.companion_profiles:
		var resolved := CompanionProfile.resolve(saved, companion_catalog)
		roster.append(resolved.profile)
	_demo_party = {"troops": battle_setup.player_army.duplicate(true), "hero": profile, "gold": 0, "comps": roster, "position": demo_party_position}
	var opponent := {"id": "demo_opponent", "troops": battle_setup.enemy_army.duplicate(true), "fac": battle_setup.enemy_faction}
	_demo_world = demo_world.duplicate(true)
	_demo_world.parties = [opponent.duplicate(true)]
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_setup.seed + REWARD_SEED_OFFSET
	var mounted := bool(HeroGear.resolve(profile, gear_catalog).get("mounted", false))
	var bridge := EncounterAftermath.new(session)
	view.battle_finished.connect(_show_aftermath.bind(view, bridge, opponent, mounted, catalog, gear_catalog, goods, rng, companion_catalog, perk_catalog), CONNECT_ONE_SHOT)
	add_child(view)

func _save_audio_preferences(effects: bool, music: bool) -> void:
	var error := presentation_preferences.save(effects, music)
	if error != OK:
		push_warning("Cannot save audio preferences: " + error_string(error))

func _save_blood_preference(enabled: bool) -> void:
	var error := presentation_preferences.save_blood(enabled)
	if error != OK:
		push_warning("Cannot save blood preference: " + error_string(error))

func _show_aftermath(view: Node2D, bridge: EncounterAftermath, opponent: Dictionary, mounted: bool, troops: Catalog, gear: GearCatalog, goods: GoodsCatalog, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog) -> void:
	var resolved := bridge.resolve(_demo_party, opponent, mounted, troops, gear, goods, rng, companions, perks, _demo_world)
	if resolved.is_empty():
		return
	_demo_party = resolved.party
	_demo_world = resolved.world
	var summary: Dictionary = resolved.summary
	var names: PackedStringArray = []
	var trade_goods := goods.definitions()
	for drop in summary.drops:
		var item := gear.get_item(drop.id)
		var display_name: String = item.name if not item.is_empty() else trade_goods[drop.id].n
		names.append("%s ×%d" % [display_name, drop.n])
	var gold_change: int = summary.loot - summary.lost_gold + summary.get("recovery_gold", 0)
	var text := DEMO_REWARD_TEXT % [summary.lost, summary.wounded, gold_change, summary.xp, NO_DROPS if names.is_empty() else ", ".join(names)]
	if summary.has("recovery_town"):
		text += RECOVERY_TEXT % summary.recovery_town
	if summary.get("barrow_destroyed", false):
		text += BARROW_CLEARED_TEXT
	var completed: Array = summary.get("completed_quests", [])
	if not completed.is_empty():
		var reward := 0
		for quest in completed:
			reward += int(quest.gold)
		text += QUEST_REWARDS_TEXT % [completed.size(), reward]
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
