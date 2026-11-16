extends Node
const BattleWorker = preload("res://adapters/godot/battle_worker.gd")
const NativeMovement = preload("res://adapters/godot/native/movement.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## World map demo: generates Europe for a seed, puts the party in its home town. Click to walk, wheel to zoom,
## drag or WASD to look around (C — back to the party), Space — pause, 1/2/3 — speed.
## Options after `--`: --seed=N, --focus=x,y,zoom (for screenshots).
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const MapView = preload("res://apps/godot/presentation/campaign/world_map_view.gd")
const WorldCamera = preload("res://apps/godot/presentation/campaign/world_camera.gd")
const PartyLayer = preload("res://apps/godot/presentation/campaign/party_layer.gd")
const EncounterDialog = preload("res://apps/godot/presentation/campaign/encounter_dialog.gd")
const GameOptions = preload("res://apps/godot/composition/game_options.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const WorldMusic = preload("res://apps/godot/presentation/campaign/world_music.gd")
const UiSounds = preload("res://apps/godot/presentation/campaign/ui_sounds.gd")
const ResultWindow = preload("res://apps/godot/composition/battle_result_window.gd")
const Autosave = preload("res://apps/godot/composition/autosave.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const HeroStats = preload("res://core/battle/data/hero_stats.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const SiegeWindow = preload("res://apps/godot/presentation/campaign/siege_window.gd")
const PauseMenu = preload("res://apps/godot/composition/pause_menu.gd")
const WorldTips = preload("res://apps/godot/presentation/campaign/world_tips.gd")
const WorldMarksLayer = preload("res://apps/godot/presentation/campaign/world_marks_layer.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")
const AftermathText = preload("res://apps/godot/composition/aftermath_text.gd")
const BattleView = preload("res://apps/godot/presentation/battle/scene.tscn")
const BattleFactory = preload("res://core/battle/application/factory.gd")
const BattleSetup = preload("res://core/battle/data/battle_setup.gd")
const PresentationPreferences = preload("res://apps/godot/composition/presentation_preferences.gd")
const AutoBattle = preload("res://core/campaign/world/auto_battle.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const WorldPartiesLayer = preload("res://apps/godot/presentation/campaign/world_parties_layer.gd")
const WorldHud = preload("res://apps/godot/presentation/campaign/world_hud.gd")

signal title_requested

var state: RefCounted
var map_view: Node2D
var _meeting: Dictionary = {}
var _dialog: CanvasLayer
var _town: CanvasLayer
var _autosave := Autosave.new()
var _music: Node
var _result: CanvasLayer
var _auto_report := false
var _siege: CanvasLayer
var _menu: CanvasLayer
var _marks: Node2D
var _siege_hold := false
var _loot_pending: Dictionary = {}
var _battle_ticket: RefCounted
var _party_window: CanvasLayer
var _bridge: RefCounted
var _battle: Node2D
var _preferences := PresentationPreferences.new()
var _factions := FactionCatalog.new()
var _waiting_return := false
var camera: Camera2D
var hud: CanvasLayer
var _ready_to_play := false
var cache_static_artwork := true

func _ready() -> void:
	var loading := Label.new()
	loading.text = "Строю карту…"
	loading.position = Vector2(24, 24)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.add_child(loading)
	add_child(layer)
	await get_tree().process_frame
	var seed_value := GameOptions.seed_value if GameOptions.seed_value != 0 else randi_range(1, 999999999)
	var focus := PackedFloat64Array()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--focus="):
			for part in arg.substr(8).split(","):
				focus.append(float(part))
	var data := EuropeData.new()
	if not (ContentLoader.populate(data)):
		push_error("Required content failed to load: apps/godot/composition/world_demo.gd")
		return
	if GameOptions.continue_game:
		state = SaveStore.load_state(data)
		if state == null:
			loading.text = "Не удалось загрузить сохранение. Файлы сохранений оставлены без изменений."
			var back := Button.new()
			back.text = "Вернуться в меню"
			back.position = Vector2(24, 64)
			back.pressed.connect(func(): title_requested.emit())
			layer.add_child(back)
			return
	if state == null:
		state = WorldState.create(seed_value, data, GameOptions.culture, ContentLoader.registry())
		state.player.hero.name = GameOptions.hero_name
		state.player.hero.banner = GameOptions.banner
	var saved_banner = state.player.hero.get("banner", 0)
	GameOptions.banner = clampi(int(saved_banner) if saved_banner is int or saved_banner is float else 0, 0, preload("res://apps/godot/visuals/original_art.gd").BANNERS.size() - 1)
	preload("res://apps/godot/visuals/original_art.gd").select_player_banner(GameOptions.banner)
	map_view = MapView.new()
	map_view.cache_static_artwork = cache_static_artwork
	add_child(map_view)
	map_view.build_from(state.map)
	var factions := FactionCatalog.new()
	ContentLoader.populate(factions)
	var others := WorldPartiesLayer.new()
	map_view.add_child(others)
	others.build(state.roster, state.player)
	_marks = WorldMarksLayer.new()
	map_view.add_child(_marks)
	_marks.build(state)
	var party_layer := PartyLayer.new()
	map_view.add_child(party_layer)
	party_layer.build(state.player, preload("res://apps/godot/visuals/original_art.gd").palette("player"), state.gear)
	camera = WorldCamera.new()
	add_child(camera)
	camera.make_current()
	camera.fit_all()
	camera.map_clicked.connect(_on_map_click)
	camera.map_hovered.connect(_on_hover)
	_music = WorldMusic.new()
	_music.name = "WorldMusic"
	add_child(_music)
	_sync_music()
	hud = WorldHud.new()
	add_child(hud)
	hud.speed_changed.connect(func(s: int): state.clock.speed = s; state.clock.paused = false)
	hud.pause_toggled.connect(func(): state.clock.paused = not state.clock.paused)
	_town = TownWindow.new()
	add_child(_town)
	_town.wait_requested.connect(func(s: Dictionary): state.clock.paused = false; hud.show_notice("Ждём: %s. Клик по карте — в путь" % s.name))
	_town.closed.connect(func(): state.clock.paused = false)
	_party_window = PartyWindow.new()
	_party_window.stat_preview = HeroStats.preview
	add_child(_party_window)
	_party_window.closed.connect(func(): state.clock.paused = false)
	_party_window.quest_target.connect(func(x: float, y: float):
		_marks.show_quest_target(x, y)
		camera.detached = true
		camera.position = Vector2(x, y))
	hud.panel_requested.connect(_open_panel)
	_menu = PauseMenu.new()
	add_child(_menu)
	_menu.settings_changed.connect(func(effects: bool, music: bool, blood: bool):
		_sync_music()
		if is_instance_valid(_battle): _battle.apply_preferences(effects, music, blood))
	_menu.closed.connect(func(): state.clock.paused = false)
	_menu.closed.connect(func():
		if is_instance_valid(_battle):
			var current := _preferences.read()
			_battle.apply_preferences(current.effects, current.music, _preferences.read_blood())
			_battle.set_menu_open(false))
	_menu.save_requested.connect(func(): _menu.sub_label.text = "Игра сохранена" if SaveStore.save(state) else "Не удалось сохранить")
	_menu.title_requested.connect(func(): _autosave.save(state, _battle != null); title_requested.emit())
	_result = ResultWindow.new()
	_result.name = "BattleResult"
	add_child(_result)
	_result.action_chosen.connect(func(_action: String):
		if _waiting_return: _return_to_map()
		elif _auto_report: _after_auto_report())
	_siege = SiegeWindow.new()
	add_child(_siege)
	_siege.assault.connect(_on_assault)
	_siege.closed.connect(func(): if not _siege_hold: state.clock.paused = false)
	state.siege_requested.connect(func(s: Dictionary): state.clock.paused = true; _siege.open_for(state, s))
	state.settlement_entered.connect(func(s: Dictionary): state.clock.paused = true; _town.open_for(state, s); UiSounds.play(self, "click"); _autosave.save(state, _battle != null))
	state.settlement_changed.connect(func(_s): map_view.refresh_settlements())
	state.log_added.connect(func(text: String):
		hud.show_notice(text)
		if text.begins_with("Задание выполнено"): UiSounds.play(self, "coin"))
	_bridge = Bridge.new(ContentLoader.registry(), state.roster.rng)
	_dialog = EncounterDialog.new()
	add_child(_dialog)
	_dialog.chosen.connect(_on_encounter_choice)
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/composition/world_demo.gd")
		return
	state.party_met.connect(_on_party_met)
	if focus.size() == 3:
		camera.detached = true
		camera.position = Vector2(focus[0], focus[1])
		camera.zoom = Vector2(focus[2], focus[2])
	else:
		camera.detached = false
		camera.zoom = Vector2(0.9, 0.9)
	loading.text = ""
	_ready_to_play = true

func _exit_tree() -> void:
	_ready_to_play = false
	if _bridge != null: _bridge.dispose()
	if state != null:
		state.dispose()
		state = null

func _on_map_click(at: Vector2) -> void:
	if _meeting.size() > 0 or _result.visible or _town.visible or _party_window.visible or _siege.visible:
		return
	var p = state.player
	p.tid = -1
	var prey: Dictionary = state.party_near(at.x, at.y, 34.0)
	if not prey.is_empty():
		state.chase(prey)
		return
	var target: Dictionary = state.settlement_near(at.x, at.y, 46.0)
	if not target.is_empty() and target.kind == "camp":
		var why: String = state.chase(target)
		if why != "":
			hud.show_notice(why)
		return
	if not target.is_empty() and target.kind != "camp":
		p.enter_id = target.id
		if Vector2(target.x - p.x, target.y - p.y).length() < 50.0:
			state.enter(target)
			return
		p.path_to(state.map.paths, target.x, target.y)
	else:
		p.enter_id = -1
		p.path_to(state.map.paths, at.x, at.y)

func _on_party_met(party: Dictionary, _forced: bool) -> void:
	_meeting = party
	state.clock.paused = true
	if party.kind == "cvass":
		_vassal_talk(party)
		return
	var hostile: bool = Rules.hostile_to_player(party, state.player.rel) or party.kind == "camp"
	var rows: Array = []
	var sorted: Array = party.troops.duplicate()
	sorted.sort_custom(func(a, b): return state.roster.info[a.type].tier > state.roster.info[b.type].tier)
	for t in sorted:
		rows.append({"name": _bridge.troops.get_troop(t.type).name, "n": int(t.n)})
	var title: String = party.name
	if party.kind == "camp":
		title = "Чёрный курган" if party.fac == "undead" else "Логово разбойников"
	elif party.kind == "caravan":
		title = "Караван"
	elif party.kind == "bandit":
		title = "Крупная банда" if party.get("big", false) else "Разбойники"
	var sub: String = "%s · %d бойцов" % [_factions.get_faction(party.fac).get("name", party.fac), Rules.troop_count(party.troops)]
	if hostile:
		var help: Array = state.skirmish.helpers(state.player, party)
		if not help.is_empty():
			var extra := 0
			for h in help:
				extra += Rules.troop_count(h.troops)
			sub += " · на помощь идут ещё %d" % extra
	var actions: Array = []
	if hostile:
		actions = [{"id": "flee", "text": "Бежать"}, {"id": "auto", "text": "Рассчитать бой"}, {"id": "fight", "text": "В бой!", "primary": true}]
	else:
		actions = [{"id": "greet", "text": "Разойтись с миром", "primary": true}, {"id": "attack", "text": "Напасть"}]
	if party.kind == "lord" and not state.clans.clan_of(party).is_empty():
		var house: Dictionary = state.clans.clan_of(party)
		sub += " · %s" % house.name
		actions.push_front({"id": "parley", "text": "Переговоры с родом"})
	_dialog.open(title, sub, AutoBattle.relative_power(state.player.troops, party.troops, state.roster.info), rows, actions)

func _on_encounter_choice(action: String) -> void:
	var p := _meeting
	if action.begins_with("cv_"):
		var v: Dictionary = state.vassals.of_id(String(p.get("cid", "")))
		if action == "cv_give":
			state.vassals.give(v.cid, 200)
		elif action != "cv_ok":
			state.vassals.set_mode(v.cid, action.substr(3))
		if action == "cv_ok":
			_end_meeting(3.0)
		else:
			_vassal_talk(p)
		return
	match action:
		"parley":
			_open_parley(p)
		"parley_back":
			_on_party_met(p, false)
		"lure":
			var r: Dictionary = state.clans.lure_try(p)
			hud.show_notice(r.txt)
			if r.ok or not Rules.hostile_to_player(p, state.player.rel):
				_end_meeting(3.0)
			else:
				_on_party_met(p, false)
		"greet":
			_end_meeting(3.0)
		"attack":
			state.player.rel[p.fac] = maxi(-100, int(state.player.rel.get(p.fac, 0)) - (12 if p.kind == "caravan" else 30))
			_start_battle(p)
		"flee":
			var chance := AutoBattle.flee_chance(state.player.speed_of(state.map.paths), state.roster.speed_of(p), p.kind == "camp")
			if _bridge.rng.randf() < chance:
				p.state = "idle"
				p.path = []
				_end_meeting(6.0)
				hud.show_notice("Ты оторвался от погони")
			else:
				hud.show_notice("Не вышло уйти!")
				_start_battle(p)
		"auto":
			_finish_auto(p)
		"fight":
			_start_battle(p)

func _vassal_talk(p: Dictionary) -> void:
	var vs = state.vassals
	var v: Dictionary = vs.of_id(String(p.get("cid", "")))
	if v.is_empty():
		_end_meeting(3.0)
		return
	var s: Dictionary = state.map.settlement_by_id(v.sid)
	var rows: Array = []
	for t in p.troops:
		rows.append({"name": _bridge.troops.get_troop(t.type).name, "n": int(t.n)})
	var actions: Array = []
	for m in vs.MODES:
		actions.append({"id": "cv_" + m, "text": vs.MODES[m][0], "primary": v.get("mode", "guard") == m})
	if state.player.gold >= 200:
		actions.append({"id": "cv_give", "text": "Дать 200 золота"})
	actions.append({"id": "cv_ok", "text": "Хорошо"})
	_dialog.open(v.c.name, "Твой вассал · надел %s · %d из %d бойцов · казна %d · подать тебе %d в день" % [s.get("name", "—"), Rules.troop_count(p.troops), vs.cap(v), roundi(float(v.gold)), int(v.get("trib", 0))],
		["Приказ: " + vs.MODES[v.get("mode", "guard")][0], Color("#e0c060")], rows, actions)

func _open_parley(p: Dictionary) -> void:
	var clans = state.clans
	var c: Dictionary = clans.clan_of(p)
	var t: Dictionary = clans.TRAITS[c.trait]
	var why: String = clans.lure_why(p)
	var loy := int(c.loy)
	var rows: Array = [{"name": "%s род: %s" % [t.n, t.d], "n": clans.members(c).size()},
		{"name": "Верность: %s" % ("крепкая" if loy > 75 else ("обычная" if loy > 50 else ("шаткая" if loy > 30 else "на исходе"))), "n": clans.force(c)}]
	var actions: Array = [{"id": "parley_back", "text": "Назад"}]
	var sub: String = why
	if why == "":
		var ch: float = clans.lure_chance(c)
		sub = "Весь род перейдёт к твоему сюзерену. Задаток %d, при отказе пропадёт половина. Шансы: %s" % [clans.lure_cost(c), "хорошие" if ch > 0.55 else ("средние" if ch > 0.3 else "низкие")]
		actions.append({"id": "lure", "text": "Предложить %d" % clans.lure_cost(c), "primary": true})
	_dialog.open(c.name, sub, ["", Color.WHITE], rows, actions)

func _end_meeting(cooldown: float) -> void:
	_siege_hold = false
	_meeting.cd = cooldown
	_meeting = {}
	state.player.busy = ""
	state.clock.paused = false

func _show_resolved(resolved: Dictionary) -> void:
	if int(resolved.summary.get("levels_gained", 0)) > 0:
		UiSounds.play(self, "level")
	var town_id := int(resolved.get("loot_settlement_id", -1))
	_loot_pending = state.map.settlement_by_id(town_id) if town_id >= 0 else {}

func _offer_loot(s: Dictionary, show: bool) -> void:
	if show:
		_siege.open_loot(state, s)
		state.clock.paused = true

func _on_assault(s: Dictionary, calculate: bool) -> void:
	_siege_hold = true
	var opp: Dictionary = _bridge.siege_opponent(state, s)
	state.player.busy = "enc"
	if calculate:
		_finish_auto(opp)
	else:
		_start_battle(opp)

func _finish_auto(p: Dictionary) -> void:
	_battle_ticket = _bridge.begin(state, p)
	var resolved: Dictionary = _bridge.calculate(_battle_ticket)
	if resolved.is_empty():
		_bridge.cancel(_battle_ticket)
		_end_meeting(3.0)
		return
	_show_resolved(resolved)
	_battle_ticket = null
	_meeting = {}
	_siege_hold = false
	_autosave.save(state, false)
	state.clock.paused = true
	_auto_report = true
	_result.show_report(bool(resolved.summary.win), "Расчётный бой", ResultWindow.campaign_rows({}, resolved, _bridge.troops, _bridge.gear, _bridge.goods),
		ResultWindow.campaign_notes(resolved), [["Продолжить", "continue"]])

func _after_auto_report() -> void:
	_auto_report = false
	if _loot_pending.is_empty():
		state.clock.paused = false
	else:
		var town := _loot_pending
		_loot_pending = {}
		_offer_loot(town, true)

func _start_battle(p: Dictionary) -> void:
	_battle_ticket = _bridge.begin(state, p)
	var setup: BattleSetup = _bridge.battle_setup(_battle_ticket)
	if setup == null: return
	var session = BattleFactory.create(setup, _bridge.troops, _bridge.gear, _bridge.perks, _bridge.companions, Contacts.create(), NativeMovement.create(), NativeColumns.create())
	if session == null:
		_bridge.cancel(_battle_ticket)
		push_error("Cannot start the battle")
		_end_meeting(3.0)
		return
	var view = BattleView.instantiate()
	view.name = "Battle"
	var audio := _preferences.read()
	view.hero_level = int(state.player.hero.get("lvl", 1))
	view.configure(session, audio.effects, audio.music, _preferences.read_blood(), setup.seed, setup.biome, BattleWorker.new(session))
	view.audio_preferences_changed.connect(func(e: bool, m: bool): _preferences.save(e, m))
	view.blood_preference_changed.connect(func(on: bool): _preferences.save_blood(on))
	view.menu_requested.connect(func():
		view.set_menu_open(true)
		_menu.battle_mode = true
		_menu.open_menu(_preferences))
	var ticket := _battle_ticket
	view.battle_finished.connect(func():
		var resolved: Dictionary = _bridge.complete(ticket, session.result())
		if resolved.is_empty():
			return
		_show_resolved(resolved)
		_battle_ticket = null
		view.show_result_summary(AftermathText.build(resolved, _bridge.gear, _bridge.goods))
		_waiting_return = true
		view.set_menu_open(true)
		var result: Dictionary = session.result()
		_result.show_report(bool(resolved.summary.win), ResultWindow.duration(float(result.get("time", 0.0))),
			ResultWindow.campaign_rows(result, resolved, _bridge.troops, _bridge.gear, _bridge.goods),
			ResultWindow.campaign_notes(resolved), [["Продолжить", "continue"]]), CONNECT_ONE_SHOT)
	_battle = view
	_set_world_visible(false)
	add_child(view)

func _return_to_map() -> void:
	_waiting_return = false
	if _result.visible:
		_result.visible = false
	_battle.queue_free()
	_battle = null
	_meeting = {}
	_set_world_visible(true)
	_autosave.save(state, false)
	camera.make_current()
	_siege_hold = false
	if _loot_pending.is_empty():
		state.clock.paused = false
	else:
		var town := _loot_pending
		_loot_pending = {}
		_offer_loot(town, true)

func _sync_music() -> void:
	var audio := _preferences.read()
	UiSounds.enabled = audio.effects
	_music.enabled = audio.effects and audio.music and _battle == null

func _set_world_visible(on: bool) -> void:
	if _music != null:
		_music.enabled = on
		if on: _sync_music()
	map_view.visible = on
	hud.visible = on
	camera.enabled = on
	camera.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _open_panel(tab: String) -> void:
	if tab == "menu":
		state.clock.paused = true
		_menu.battle_mode = false
		_menu.open_menu(_preferences)
		return
	state.clock.paused = true
	_party_window.open_for(state, tab)

func _on_hover(world_pos: Vector2, screen_pos: Vector2) -> void:
	if _meeting.size() > 0 or _result.visible or _town.visible or _party_window.visible or _siege.visible or _menu.visible:
		hud.show_tip({}, screen_pos)
		return
	var p: Dictionary = state.party_near(world_pos.x, world_pos.y, 30.0)
	if not p.is_empty():
		hud.show_tip({}, screen_pos, WorldTips.party_tip(state, p, _factions))
		return
	var s: Dictionary = state.settlement_near(world_pos.x, world_pos.y, 46.0)
	hud.show_tip(s, screen_pos, WorldTips.settlement_tip(state, s, _factions) if not s.is_empty() else "")

func _unhandled_input(event: InputEvent) -> void:
	if _battle != null and not _waiting_return:
		return
	if not _ready_to_play or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if _waiting_return:
				_return_to_map()
			else:
				hud.show_notice("")
		KEY_P, KEY_H, KEY_J:
			state.clock.paused = true
			_party_window.open_for(state, {KEY_P: "troops", KEY_H: "hero", KEY_J: "journal"}[(event as InputEventKey).keycode])
		KEY_F5:
			hud.show_notice("Игра сохранена" if SaveStore.save(state) else "Не удалось сохранить")
		KEY_ESCAPE:
			if _menu.visible:
				_menu.close_window()
			elif _party_window.visible or _town.visible or _siege.visible:
				_party_window.close_window()
				_town.close_window()
				_siege.close_window()
			elif _meeting.is_empty():
				_open_panel("menu")
		KEY_SPACE:
			state.clock.paused = not state.clock.paused
		KEY_1, KEY_2, KEY_3:
			state.clock.speed = [1, 2, 4][(event as InputEventKey).keycode - KEY_1]
			state.clock.paused = false

func _process(delta: float) -> void:
	if not _ready_to_play or _battle != null:
		return
	state.advance(delta)
	if _autosave.crossed_midnight(state):
		_autosave.save(state, false)
	if not camera.detached:
		camera.position = Vector2(state.player.x, state.player.y)
	hud.refresh(state, state.settlement_near(state.player.x, state.player.y, 46.0))
