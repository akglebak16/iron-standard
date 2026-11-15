extends Node
## World map demo: generates Europe for a seed, puts the party in its home town. Click to walk, wheel to zoom,
## drag or WASD to look around (C — back to the party), Space — pause, 1/2/3 — speed.
## Options after `--`: --seed=N, --focus=x,y,zoom (for screenshots).
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const MapView = preload("res://campaign/presentation/world_map_view.gd")
const WorldCamera = preload("res://campaign/presentation/world_camera.gd")
const PartyLayer = preload("res://campaign/presentation/party_layer.gd")
const EncounterDialog = preload("res://campaign/presentation/encounter_dialog.gd")
const GameOptions = preload("res://app/game_options.gd")
const SaveStore = preload("res://app/save_store.gd")
const TownWindow = preload("res://campaign/presentation/town_window.gd")
const PartyWindow = preload("res://campaign/presentation/party_window.gd")
const SiegeWindow = preload("res://campaign/presentation/siege_window.gd")
const PauseMenu = preload("res://app/pause_menu.gd")
const WorldTips = preload("res://campaign/presentation/world_tips.gd")
const WorldMarksLayer = preload("res://campaign/presentation/world_marks_layer.gd")
const Bridge = preload("res://app/world_battle_bridge.gd")
const Aftermath = preload("res://app/encounter_aftermath.gd")
const AftermathText = preload("res://app/aftermath_text.gd")
const BattleView = preload("res://battle/presentation/scene.tscn")
const BattleFactory = preload("res://battle/application/factory.gd")
const PresentationPreferences = preload("res://app/presentation_preferences.gd")
const AutoBattle = preload("res://campaign/world/auto_battle.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const WorldPartiesLayer = preload("res://campaign/presentation/world_parties_layer.gd")
const WorldHud = preload("res://campaign/presentation/world_hud.gd")

var state: RefCounted
var map_view: Node2D
var _meeting: Dictionary = {}
var _dialog: CanvasLayer
var _town: CanvasLayer
var _siege: CanvasLayer
var _menu: CanvasLayer
var _marks: Node2D
var _siege_hold := false
var _loot_pending: Dictionary = {}
var _allies: Array = []
var _party_window: CanvasLayer
var _bridge: RefCounted
var _battle: Node2D
var _preferences := PresentationPreferences.new()
var _factions := FactionCatalog.new()
var _waiting_return := false
var camera: Camera2D
var hud: CanvasLayer
var _ready_to_play := false

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
	if not (data.load_data()):
		push_error("Required content failed to load: app/world_demo.gd")
		return
	if GameOptions.continue_game:
		state = SaveStore.load_state(data)
	if state == null:
		state = WorldState.create(seed_value, data, GameOptions.culture)
		state.player.hero.name = GameOptions.hero_name
	map_view = MapView.new()
	add_child(map_view)
	map_view.build_from(state.map)
	var factions := FactionCatalog.new()
	factions.load_data()
	var others := WorldPartiesLayer.new()
	map_view.add_child(others)
	others.build(state.roster, state.player)
	_marks = WorldMarksLayer.new()
	map_view.add_child(_marks)
	_marks.build(state)
	var party_layer := PartyLayer.new()
	map_view.add_child(party_layer)
	party_layer.build(state.player, factions.get_faction("player"), state.gear)
	camera = WorldCamera.new()
	add_child(camera)
	camera.make_current()
	camera.fit_all()
	camera.map_clicked.connect(_on_map_click)
	camera.map_hovered.connect(_on_hover)
	hud = WorldHud.new()
	add_child(hud)
	hud.speed_changed.connect(func(s: int): state.clock.speed = s; state.clock.paused = false)
	hud.pause_toggled.connect(func(): state.clock.paused = not state.clock.paused)
	_town = TownWindow.new()
	add_child(_town)
	_town.wait_requested.connect(func(s: Dictionary): state.clock.paused = false; hud.show_notice("Ждём: %s. Клик по карте — в путь" % s.name))
	_town.closed.connect(func(): state.clock.paused = false)
	_party_window = PartyWindow.new()
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
		if is_instance_valid(_battle): _battle.apply_preferences(effects, music, blood))
	_menu.closed.connect(func(): state.clock.paused = false)
	_menu.closed.connect(func():
		if is_instance_valid(_battle):
			var current := _preferences.read()
			_battle.apply_preferences(current.effects, current.music, _preferences.read_blood())
			_battle.set_menu_open(false))
	_menu.save_requested.connect(func(): _menu.sub_label.text = "Игра сохранена" if SaveStore.save(state) else "Не удалось сохранить")
	_menu.title_requested.connect(func(): get_tree().change_scene_to_file("res://app/main_menu.tscn"))
	_siege = SiegeWindow.new()
	add_child(_siege)
	_siege.assault.connect(_on_assault)
	_siege.closed.connect(func(): if not _siege_hold: state.clock.paused = false)
	state.siege_requested.connect(func(s: Dictionary): state.clock.paused = true; _siege.open_for(state, s))
	state.settlement_entered.connect(func(s: Dictionary): state.clock.paused = true; _town.open_for(state, s))
	state.settlement_changed.connect(func(_s): map_view.refresh_settlements())
	state.log_added.connect(func(text: String): hud.show_notice(text))
	_bridge = Bridge.new()
	_dialog = EncounterDialog.new()
	add_child(_dialog)
	_dialog.chosen.connect(_on_encounter_choice)
	if not (_factions.load_data()):
		push_error("Required content failed to load: app/world_demo.gd")
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

func _on_map_click(at: Vector2) -> void:
	if _meeting.size() > 0 or _town.visible or _party_window.visible or _siege.visible:
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

func _world_for(p: Dictionary) -> Dictionary:
	if p.kind == "siege":
		return _bridge.siege_world(state, state.map.settlement_by_id(p.sid))
	return {"parties": [p.duplicate(true)], "settlements": [], "factions": Rules.REAL_FACTIONS}

## Applies a resolved battle; for a siege also writes the town back and queues the plunder choice.
func _apply_resolved(p: Dictionary, resolved: Dictionary) -> void:
	var was := ""
	var town: Dictionary = {}
	if p.kind == "siege":
		town = state.map.settlement_by_id(p.sid)
		was = town.fac
	_bridge.apply(state, p, resolved, _allies)
	state.skirmish.split(p)
	if not _allies.is_empty():
		state.log_world("Дружины вассалов бились рядом с тобой.")
	_allies = []
	if p.kind == "siege":
		_bridge.apply_siege(state, town, resolved)
		state.settlement_changed.emit(town)
		if resolved.summary.has("captured"):
			state.log_world("%s взят штурмом!" % town.name)
			if was in Rules.REAL_FACTIONS:
				_loot_pending = town

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

func _opponent(p: Dictionary) -> Dictionary:
	return _bridge.opponent_dict(p, {})

func _finish_auto(p: Dictionary) -> void:
	state.skirmish.merge(p, state.skirmish.helpers(state.player, p))
	_allies = Bridge.snapshot(state.vassals.helpers(p))
	var result: Dictionary = _bridge.auto_result(state, p, _allies)
	var party: Dictionary = _bridge.party_dict(state, _allies)
	var opponent := _opponent(p)
	var world := _world_for(opponent)
	var resolved := Aftermath.resolve_result(result, party, opponent, _bridge.is_hero_mounted(state), _bridge.troops, _bridge.gear, _bridge.goods, _bridge.rng, _bridge.companions, _bridge.perks, world)
	if resolved.is_empty():
		_end_meeting(3.0)
		return
	_apply_resolved(p, resolved)
	_meeting = {}
	hud.show_notice(("Победа!" if result.win else "Поражение.") + AftermathText.build(resolved, _bridge.gear, _bridge.goods))
	_siege_hold = false
	if _loot_pending.is_empty():
		state.clock.paused = false
	else:
		var town := _loot_pending
		_loot_pending = {}
		_offer_loot(town, true)

func _start_battle(p: Dictionary) -> void:
	state.skirmish.merge(p, state.skirmish.helpers(state.player, p))
	_allies = Bridge.snapshot(state.vassals.helpers(p))
	var setup: Resource = _bridge.make_setup(state, p, _allies)
	var session = BattleFactory.create(setup, _bridge.troops, _bridge.gear, _bridge.perks, _bridge.companions)
	if session == null:
		push_error("Cannot start the battle")
		_end_meeting(3.0)
		return
	var view = BattleView.instantiate()
	view.name = "Battle"
	var audio := _preferences.read()
	view.configure(session, audio.effects, audio.music, _preferences.read_blood(), setup.seed, setup.biome)
	view.audio_preferences_changed.connect(func(e: bool, m: bool): _preferences.save(e, m))
	view.blood_preference_changed.connect(func(on: bool): _preferences.save_blood(on))
	view.menu_requested.connect(func():
		view.set_menu_open(true)
		_menu.battle_mode = true
		_menu.open_menu(_preferences))
	var opponent := _opponent(p)
	var bridge := Aftermath.new(session)
	view.battle_finished.connect(func():
		var world := _world_for(opponent)
		var resolved := bridge.resolve(_bridge.party_dict(state, _allies), opponent, _bridge.is_hero_mounted(state), _bridge.troops, _bridge.gear, _bridge.goods, _bridge.rng, _bridge.companions, _bridge.perks, world)
		if resolved.is_empty():
			return
		_apply_resolved(p, resolved)
		view.show_result_summary(AftermathText.build(resolved, _bridge.gear, _bridge.goods) + "\nEnter — вернуться на карту")
		_waiting_return = true, CONNECT_ONE_SHOT)
	_battle = view
	_set_world_visible(false)
	add_child(view)

func _return_to_map() -> void:
	_waiting_return = false
	_battle.queue_free()
	_battle = null
	_meeting = {}
	_set_world_visible(true)
	camera.make_current()
	_siege_hold = false
	if _loot_pending.is_empty():
		state.clock.paused = false
	else:
		var town := _loot_pending
		_loot_pending = {}
		_offer_loot(town, true)

func _set_world_visible(on: bool) -> void:
	map_view.visible = on
	hud.visible = on
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
	if _meeting.size() > 0 or _town.visible or _party_window.visible or _siege.visible or _menu.visible:
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
	if not camera.detached:
		camera.position = Vector2(state.player.x, state.player.y)
	hud.refresh(state, state.settlement_near(state.player.x, state.player.y, 46.0))
