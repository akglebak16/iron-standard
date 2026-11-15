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
const AftermathText = preload("res://app/aftermath_text.gd")
const GoodsCatalog = preload("res://campaign/data/goods_catalog.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const PresentationPreferences = preload("res://app/presentation_preferences.gd")
const REWARD_SEED_OFFSET := 1
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
	var menu := preload("res://app/pause_menu.gd").new()
	menu.name = "BattlePause"
	menu.battle_mode = true
	add_child(menu)
	menu.settings_changed.connect(view.apply_preferences)
	view.menu_requested.connect(func():
		if not view.attract_mode:
			view.set_menu_open(true)
			menu.open_menu(presentation_preferences))
	menu.closed.connect(func():
		var current := presentation_preferences.read()
		view.apply_preferences(current.effects, current.music, presentation_preferences.read_blood())
		view.set_menu_open(false))
	menu.title_requested.connect(func(): get_tree().change_scene_to_file("res://app/main_menu.tscn"))

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
	view.show_result_summary(AftermathText.build(resolved, gear, goods))
