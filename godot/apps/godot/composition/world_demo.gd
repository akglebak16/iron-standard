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
const HeroOrigin = preload("res://core/campaign/world/hero_origin.gd")
const SaveSlots = preload("res://adapters/persistence/save_slots.gd")
const SaveSlotsWindow = preload("res://apps/godot/composition/save_slots_window.gd")
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
const WorldSkirmish = preload("res://core/campaign/world/world_skirmish.gd")
const WorldPartiesLayer = preload("res://apps/godot/presentation/campaign/world_parties_layer.gd")
const WorldMotion = preload("res://apps/godot/presentation/campaign/world_motion.gd")
const CompanionRemarks = preload("res://apps/godot/presentation/campaign/companion_remarks.gd")
const WorldHud = preload("res://apps/godot/presentation/campaign/world_hud.gd")
const LoadingView = preload("res://apps/godot/presentation/campaign/campaign_loading_view.gd")

signal title_requested
## Start the campaign scene again (loading another save from the pause menu).
signal campaign_requested

## The world. While the simulation thread runs a step (world_sim_thread.gd) the world is its own: reading `state` waits
## for that step, so every handler and window sees a whole world. _process never waits: it asks _sim.poll() first.
var state: RefCounted:
	get:
		if _sim != null and _sim.given:
			var from := Time.get_ticks_usec()
			_sim.take()
			# The main thread stood still for the rest of the step: fine for a click, a freeze if it happens every frame.
			var waited := Time.get_ticks_usec() - from
			if waited > 2000 and _hitch_log < 400:
				_hitch_log += 1
				var stack := get_stack()
				print("WORLDWAIT %.1f ms in %s" % [waited / 1000.0, " <- ".join(stack.slice(1, 4).map(func(f): return "%s:%d" % [f.function, f.line]))])
		return _state
	set(value):
		_state = value
var _state: RefCounted
const WorldSimThread = preload("res://apps/godot/composition/world_sim_thread.gd")
## One world step at a time runs on a worker thread and the map is drawn from frozen copies meanwhile (ADR-024).
## Off in headless runs (tests drive the world step by step) unless a benchmark turns it on.
var sim_thread := DisplayServer.get_name() != "headless"
var _sim: WorldSimThread
var _frozen := false
var _frozen_at := Vector2.ZERO
var _frozen_speed := 1
var _pending_dt := 0.0
var _events: Array = []  # [handler, args] of world signals raised inside a step on the worker; run when the world is back
var _no_arg := RefCounted.new()
var _hitch_log := 0
var _hover_pending: Array = []  # [world_pos, screen_pos] of a mouse move that came while a step was running
var map_view: Node2D
var _meeting: Dictionary = {}
var _meeting_fight: Dictionary = {} # the map fight the player rode up to (WorldSkirmish)
var _join: Dictionary = {}          # the side of that fight the player took: {foe, foes, friends}
var _dialog: CanvasLayer
var _town: CanvasLayer
var _autosave := Autosave.new()
var _music: Node
var _result: CanvasLayer
var _auto_report := false
var _siege: CanvasLayer
var _menu: CanvasLayer
var _slots: CanvasLayer
var _marks: Node2D
var _others: Node2D
var _party_layer: Node2D
var _siege_hold := false
var _loot_pending: Dictionary = {}
var _battle_ticket: RefCounted
var _party_window: CanvasLayer
var _bridge: RefCounted
var _battle: Node2D
var _preferences := PresentationPreferences.new()
var _factions := FactionCatalog.new()
var _waiting_return := false
var _motion := WorldMotion.new()
var _remark_rng := RandomNumberGenerator.new()
var _camp_hour := 0
var camera: Camera2D
var hud: CanvasLayer
var _ready_to_play := false
var cache_static_artwork := true
var profile_startup := false
var startup_marks_us := {}
var _world_job: Thread
var profile_map_frames := false
var map_step_us := 0
var map_hud_us := 0
var map_steps := 0
var map_main_us := 0  # time of this node's _process on the main thread

func _startup_mark(stage: String) -> void:
	if profile_startup:
		startup_marks_us[stage] = Time.get_ticks_usec()

func _ready() -> void:
	_startup_mark("scene_entered")
	_remark_rng.randomize()
	var loading := LoadingView.new()
	loading.back_requested.connect(func(): title_requested.emit())
	add_child(loading)
	loading.show_stage("Готовим кампанию…")
	await get_tree().process_frame
	_startup_mark("loading_frame")
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
		loading.show_error("Не удалось открыть данные кампании.")
		return
	if GameOptions.continue_game:
		loading.show_stage("Загружаем сохранение…")
		await get_tree().process_frame
		var loaded := SaveSlots.load_slot(data, GameOptions.load_slot)
		state = loaded.state
		if state == null:
			loading.show_error(loaded.error)
			return
	if state == null:
		var registry := ContentLoader.registry()
		_startup_mark("content_ready")
		loading.show_stage("Создаём мир и отряды…")
		var generate := WorldState.create.bind(seed_value, data, GameOptions.culture, registry)
		# The worker owns the new simulation until joined. All nodes and GPU work stay here.
		if DisplayServer.get_name() != "headless":
			_world_job = Thread.new()
			if _world_job.start(generate) != OK:
				_world_job = null
		if _world_job == null:
			state = generate.call()
		else:
			while _world_job.is_alive():
				await get_tree().process_frame
				if not is_inside_tree(): return
			state = _world_job.wait_to_finish()
			_world_job = null
		if state == null:
			loading.show_error("Не удалось создать кампанию.")
			return
		state.player.hero.name = GameOptions.hero_name
		state.player.hero.banner = GameOptions.banner
		if not GameOptions.hero_face.is_empty():
			state.player.hero.face = GameOptions.hero_face.duplicate()
		if not HeroOrigin.apply(state.player.hero, GameOptions.origin):
			push_warning("The start background was not applied: %s" % GameOptions.origin)
	var saved_banner = state.player.hero.get("banner", 0)
	_startup_mark("world_ready")
	loading.show_stage("Рисуем карту…")
	GameOptions.banner = clampi(int(saved_banner) if saved_banner is int or saved_banner is float else 0, 0, preload("res://apps/godot/visuals/original_art.gd").BANNERS.size() - 1)
	preload("res://apps/godot/visuals/original_art.gd").select_player_banner(GameOptions.banner)
	map_view = MapView.new()
	map_view.cache_static_artwork = cache_static_artwork
	if profile_startup:
		map_view.ready_to_show.connect(_startup_mark.bind("map_painted"), CONNECT_ONE_SHOT)
	add_child(map_view)
	map_view.build_from(state.map)
	_startup_mark("map_resources_ready")
	var factions := FactionCatalog.new()
	ContentLoader.populate(factions)
	var others := WorldPartiesLayer.new()
	_others = others
	map_view.add_child(others)
	others.build(state.roster, state.player)
	others.motion = _motion
	_marks = WorldMarksLayer.new()
	map_view.add_child(_marks)
	_marks.build(state)
	var party_layer := PartyLayer.new()
	_party_layer = party_layer
	map_view.add_child(party_layer)
	party_layer.build(state.player, preload("res://apps/godot/visuals/original_art.gd").palette("player"), state.gear)
	party_layer.motion = _motion
	camera = WorldCamera.new()
	add_child(camera)
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
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
	_town.wait_requested.connect(func(s: Dictionary): state.clock.paused = false; state.waiting = true; hud.show_notice("Ждём: %s. Любой клик по карте или Z — в путь" % s.name))
	_town.closed.connect(func(): state.clock.paused = false)
	_town.map_target.connect(func(x: float, y: float):
		_marks.show_quest_target(x, y)
		camera.detached = true
		camera.position = Vector2(x, y))
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
	_slots = SaveSlotsWindow.new()
	_slots.name = "SaveSlots"
	add_child(_slots)
	_slots.closed.connect(func(): state.clock.paused = false)
	_slots.load_chosen.connect(_load_slot)
	_menu.save_requested.connect(func(): _open_slots(true))
	_menu.load_requested.connect(func(): _open_slots(false))
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
	state.siege_requested.connect(_ev(func(s: Dictionary): state.clock.paused = true; _siege.open_for(state, s)))
	state.settlement_entered.connect(_ev(func(s: Dictionary): state.clock.paused = true; _town_remark(s); _town.open_for(state, s); UiSounds.play(self, "click"); _autosave.save(state, _battle != null)))
	state.settlement_changed.connect(_ev(func(_s): map_view.refresh_settlements()))
	state.log_added.connect(_ev(func(text: String):
		hud.show_notice(text)
		if text.begins_with("Задание выполнено"): UiSounds.play(self, "coin")))
	_bridge = Bridge.new(ContentLoader.registry(), state.roster.rng)
	_dialog = EncounterDialog.new()
	add_child(_dialog)
	_dialog.chosen.connect(_on_encounter_choice)
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/composition/world_demo.gd")
		return
	state.party_met.connect(_ev(_on_party_met))
	if focus.size() == 3:
		camera.detached = true
		camera.position = Vector2(focus[0], focus[1])
		camera.zoom = Vector2(focus[2], focus[2])
	else:
		camera.detached = false
		camera.zoom = Vector2(0.9, 0.9)
	if DisplayServer.get_name() != "headless":
		await map_view.ready_to_show
	loading.queue_free()
	camera.set_process(true)
	camera.set_process_unhandled_input(true)
	if sim_thread:
		_sim = WorldSimThread.new()
		if not _sim.start(_state):
			_sim = null
	_ready_to_play = true
	_startup_mark("input_ready")

## A handler of a world signal. Raised inside a step on the simulation thread it is put off until the world is back
## on the main thread (_thaw); raised on the main thread it runs at once, as before.
func _ev(handler: Callable) -> Callable:
	return func(a: Variant = _no_arg, b: Variant = _no_arg) -> void:
		var args: Array = []
		for v in [a, b]:
			if not is_same(v, _no_arg):
				args.append(v)
		if OS.get_thread_caller_id() != OS.get_main_thread_id():
			_events.append([handler, args])
		else:
			handler.callv(args)

func _freeze() -> void:
	_frozen = true
	_frozen_at = Vector2(_state.player.x, _state.player.y)
	_frozen_speed = _state.clock.speed
	_others.freeze()
	_party_layer.freeze()
	_marks.frozen = true

func _thaw() -> void:
	_frozen = false
	_others.thaw()
	_party_layer.thaw()
	_marks.frozen = false
	var events := _events
	_events = []
	for e in events:
		(e[0] as Callable).callv(e[1])

func _exit_tree() -> void:
	_ready_to_play = false
	if _sim != null:
		_sim.stop()
		_sim = null
	if _world_job != null:
		var abandoned = _world_job.wait_to_finish()
		_world_job = null
		if abandoned != null: abandoned.dispose()
	if _bridge != null: _bridge.dispose()
	if state != null:
		state.dispose()
		state = null

func _on_map_click(at: Vector2) -> void:
	if _meeting.size() > 0 or _result.visible or _town.visible or _party_window.visible or _siege.visible:
		return
	var p = state.player
	p.tid = -1
	state.waiting = false
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
		if not p.path_to(state.map.paths, at.x, at.y):
			hud.show_notice("Туда не пройти")

func _on_party_met(party: Dictionary, _forced: bool) -> void:
	_meeting = party
	state.clock.paused = true
	if party.kind == "cvass":
		_vassal_talk(party)
		return
	var fight: Dictionary = state.skirmish.fight_of(party)
	if not fight.is_empty() and _join.is_empty():
		_fight_talk(fight)
		return
	var hostile: bool = Rules.hostile_to_player(party, state.player.rel) or party.kind == "camp" or not _join.is_empty()
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
	var power: Array = AutoBattle.relative_power(state.player.troops, party.troops, state.roster.info)
	if hostile:
		var help: Array = _join.get("foes", []) + state.skirmish.helpers(state.player, party)
		var friends: Array = _join.get("friends", []) + state.vassals.helpers(party) + state.skirmish.allies(state.player, party)
		var extra := _men(help, [party])
		if extra > 0:
			sub += " · на помощь идут ещё %d" % extra
		var ours := _men(friends, [party] + help)
		if ours > 0:
			sub += " · с тобой ещё %d" % ours
		var mine: Array = state.player.troops.duplicate(true)
		for h in friends:
			for t in h.troops:
				Rules.add_troops(mine, t.type, int(t.n))
		var theirs: Array = party.troops.duplicate(true)
		for h in help:
			for t in h.troops:
				Rules.add_troops(theirs, t.type, int(t.n))
		power = AutoBattle.relative_power(mine, theirs, state.roster.info)
	var actions: Array = []
	if hostile:
		actions = [{"id": "flee", "text": "Бежать"}, {"id": "auto", "text": "Рассчитать бой"}, {"id": "fight", "text": "В бой!", "primary": true}]
	else:
		actions = [{"id": "greet", "text": "Разойтись с миром", "primary": true}, {"id": "attack", "text": "Напасть"}]
	if party.kind == "lord" and not state.clans.clan_of(party).is_empty():
		var house: Dictionary = state.clans.clan_of(party)
		sub += " · %s" % house.name
		actions.push_front({"id": "parley", "text": "Переговоры с родом"})
	_dialog.open(title, sub, power, rows, actions)

## Soldiers in distinct parties of `list` that are not in `skip`.
static func _men(list: Array, skip: Array) -> int:
	var seen: Array = skip.duplicate()
	var n := 0
	for h in list:
		if seen.any(func(x): return is_same(x, h)):
			continue
		seen.append(h)
		n += Rules.troop_count(h.troops)
	return n

## A fight between map parties: who is against whom, and which side the player may take.
func _fight_talk(fight: Dictionary) -> void:
	_meeting_fight = fight
	var both: Array = state.skirmish.sides(fight)
	var cards: Array = []
	var actions: Array = [{"id": "fight_leave", "text": "Не вмешиваться"}]
	for i in 2:
		var side: Array = both[i]
		var names: Array = []
		var parties: Array = []
		var troops: Array = state.player.troops.duplicate(true)
		for q in side:
			var fname: String = _factions.get_faction(q.fac).get("name", q.fac)
			if not fname in names:
				names.append(fname)
			parties.append({"name": q.name, "n": Rules.troop_count(q.troops)})
			for t in q.troops:
				Rules.add_troops(troops, t.type, int(t.n))
		var label := ", ".join(names)
		var card := {"fac": side[0].fac if not side.is_empty() else "", "label": label, "men": _men(side, []), "parties": parties}
		if side.is_empty() or side.any(func(q): return Rules.hostile_to_player(q, state.player.rel)):
			card.note = "Враждебны тебе: помогать им ты не станешь."
		else:
			var others: Array = []
			for q in both[1 - i]:
				others.append_array(q.troops)
			card.power = AutoBattle.relative_power(troops, others, state.roster.info)
			var against: Array = WorldSkirmish.peaceful(both[1 - i], state.player.rel)
			if not against.is_empty():
				card.note = "Испортятся отношения: %s." % ", ".join(against.map(func(q): return _factions.get_faction(q.fac).get("name", q.fac)))
			actions.append({"id": "fight_help_%d" % i, "text": "Помочь: %s" % label, "primary": against.is_empty()})
		cards.append(card)
	_dialog.open_fight("Идёт сражение", "Отряды сцепились у тебя на пути. Можно встать на одну из сторон или проехать мимо.", cards, actions)

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
	if action == "fight_leave":
		_end_meeting(3.0)
		return
	if action.begins_with("fight_help_"):
		var j: Dictionary = state.skirmish.join(_meeting_fight, int(action.trim_prefix("fight_help_")))
		_meeting_fight = {}
		if j.is_empty():
			_end_meeting(3.0)
			return
		for q in WorldSkirmish.peaceful([j.foe] + j.foes, state.player.rel):
			state.attack(q)
		_join = j
		_on_party_met(j.foe, false)
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
			state.attack(p)
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
	state.waiting = false
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
	_join = {}
	_meeting_fight = {}
	_meeting.cd = cooldown
	_meeting = {}
	state.player.busy = ""
	state.clock.paused = false

## Result notes plus a word from a companion who fought (win/lose lines).
func _notes_with_remark(resolved: Dictionary) -> Array:
	var notes: Array = ResultWindow.campaign_notes(resolved)
	var fought: Array = resolved.summary.get("comps", {}).keys()
	var kind := CompanionRemarks.WIN if resolved.summary.win else CompanionRemarks.LOSE
	var pair := CompanionRemarks.pair_exchange(state.player.comps, fought, state.companion_catalog, kind, _remark_rng)
	if not pair.is_empty() and _remark_rng.randf() < 0.5:
		notes.append_array(pair)
		return notes
	var line := CompanionRemarks.pick(fought, state.companion_catalog, kind, _remark_rng)
	if line != "":
		notes.append(line)
	return notes

## While the party waits, a pair of companions talks now and then (written to the chronicle).
func _camp_talk() -> void:
	if not state.waiting or state.hours_passed - _camp_hour < CompanionRemarks.CAMP_EVERY_HOURS:
		return
	_camp_hour = state.hours_passed
	if _remark_rng.randf() >= CompanionRemarks.CAMP_CHANCE:
		return
	var hired: Array = state.player.comps.map(func(c): return c.id)
	for line in CompanionRemarks.pair_exchange(state.player.comps, hired, state.companion_catalog, CompanionRemarks.CAMP, _remark_rng):
		state.log_world(line, state.JOURNAL_INFO)

## Now and then a hired companion comments on the town (town lines), written to the chronicle.
func _town_remark(s: Dictionary) -> void:
	if s.get("kind") != "town" or _remark_rng.randf() >= CompanionRemarks.TOWN_CHANCE:
		return
	var hired: Array = state.player.comps.map(func(c): return c.id)
	var line := CompanionRemarks.pick(hired, state.companion_catalog, CompanionRemarks.TOWN, _remark_rng)
	if line != "":
		state.log_world(line, state.JOURNAL_INFO)

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
	_battle_ticket = _bridge.begin(state, p, _join.get("friends", []), _join.get("foes", []))
	_join = {}
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
		_notes_with_remark(resolved), [["Продолжить", "continue"]])

func _after_auto_report() -> void:
	_auto_report = false
	if int(state.player.hero.get("pts", 0)) > 0 or int(state.player.hero.get("pp", 0)) > 0:
		hud.show_notice("Есть свободные очки: атрибуты и перки в окне героя (H)")
	if _loot_pending.is_empty():
		state.clock.paused = false
	else:
		var town := _loot_pending
		_loot_pending = {}
		_offer_loot(town, true)

func _start_battle(p: Dictionary) -> void:
	_battle_ticket = _bridge.begin(state, p, _join.get("friends", []), _join.get("foes", []))
	_join = {}
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
			_notes_with_remark(resolved), [["Продолжить", "continue"]]), CONNECT_ONE_SHOT)
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
	if int(state.player.hero.get("pts", 0)) > 0 or int(state.player.hero.get("pp", 0)) > 0:
		hud.show_notice("Есть свободные очки: атрибуты и перки в окне героя (H)")
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

## The save/load screen replaces the pause menu; the map stays paused while it is open.
func _open_slots(saving: bool) -> void:
	if _battle != null:
		return
	_menu.close_window()
	state.clock.paused = true
	if saving: _slots.open_save(state)
	else: _slots.open_load(true)

func _load_slot(id: String) -> void:
	GameOptions.continue_game = true
	GameOptions.load_slot = id
	campaign_requested.emit()

func _open_panel(tab: String) -> void:
	if tab == "menu":
		state.clock.paused = true
		_menu.battle_mode = false
		_menu.open_menu(_preferences)
		return
	state.clock.paused = true
	_party_window.open_for(state, tab)

func _on_hover(world_pos: Vector2, screen_pos: Vector2) -> void:
	# The mouse moves many times a frame: while a world step runs the tip waits for the world instead of the frame
	# waiting for the step (_process answers it when the world is back).
	if _sim != null and not _sim.poll():
		_hover_pending = [world_pos, screen_pos]
		return
	_hover_pending = []
	if _meeting.size() > 0 or _result.visible or _town.visible or _party_window.visible or _siege.visible or _menu.visible or _slots.visible:
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
		KEY_P, KEY_H, KEY_J, KEY_K:
			state.clock.paused = true
			_party_window.open_for(state, {KEY_P: "troops", KEY_H: "hero", KEY_J: "journal", KEY_K: "factions"}[(event as InputEventKey).keycode])
		KEY_F5:
			hud.show_notice("Быстрое сохранение" if SaveSlots.save(state, SaveSlots.QUICK) else "Не удалось сохранить")
		KEY_ESCAPE:
			if _menu.visible:
				_menu.close_window()
			elif _party_window.visible or _town.visible or _siege.visible:
				_party_window.close_window()
				_town.close_window()
				_siege.close_window()
			elif _meeting.is_empty():
				_open_panel("menu")
		KEY_Z:
			if _waiting_return or _meeting.size() > 0 or _result.visible:
				return
			hud.show_notice(state.toggle_wait())
		KEY_SPACE:
			state.clock.paused = not state.clock.paused
		KEY_1, KEY_2, KEY_3:
			state.clock.speed = [1, 2, 4][(event as InputEventKey).keycode - KEY_1]
			state.clock.paused = false

func _process(delta: float) -> void:
	if not _ready_to_play or _battle != null:
		return
	if _sim != null and not _sim.poll():
		# A world step is running on the simulation thread: draw the frozen copies and touch nothing of the world.
		_pending_dt += delta
		_motion.tick(delta, true, 0.0, _frozen_speed)
		if not camera.detached:
			camera.position = _motion.at(-1, _frozen_at)
		_log_hitch(delta, 0, 0)
		map_main_us = 0
		return
	var frame_from := Time.get_ticks_usec()
	if _frozen:
		_thaw()  # runs what the step raised: a meeting or a town may open here
		if _battle != null:
			return
	if not _hover_pending.is_empty():
		_on_hover(_hover_pending[0], _hover_pending[1])
	var started := Time.get_ticks_usec()
	var sim_us := 0
	if _sim != null:
		state.tick_time(delta + _pending_dt)
		_pending_dt = 0.0
		if profile_map_frames:
			map_steps = 1 if _sim.last_step_us > 0 else 0
			map_step_us = _sim.last_step_us
			_sim.last_step_us = 0
	else:
		var steps: int = state.advance(delta)
		sim_us = Time.get_ticks_usec() - started
		if profile_map_frames:
			map_steps = steps
			map_step_us = sim_us
	_camp_talk()
	_motion.tick(delta, not state.clock.paused and (state.waiting or state.is_moving()), state.clock.step_fraction(), state.clock.speed)
	var save_due: bool = _autosave.crossed_midnight(state)
	if save_due and _sim == null:
		_autosave.save(state, false)
	if not camera.detached:
		camera.position = _motion.at(-1, Vector2(state.player.x, state.player.y))
	started = Time.get_ticks_usec()
	hud.refresh(state, state.settlement_near(state.player.x, state.player.y, 46.0))
	var hud_us := Time.get_ticks_usec() - started
	if profile_map_frames: map_hud_us = hud_us
	_log_hitch(delta, sim_us, hud_us)
	# The next due step goes to the simulation thread; this frame and the next ones are drawn from frozen copies.
	if _sim != null and _battle == null and save_due:
		_freeze()
		_sim.give(_autosave.save.bind(_state, false))  # the midnight autosave writes the whole world: off the main thread too
	elif _sim != null and _battle == null and not state.clock.paused and (state.waiting or state.is_moving()) and state.clock.backlog() >= 1.0:
		_freeze()
		_sim.give()
	map_main_us = Time.get_ticks_usec() - frame_from

## A long frame is written to the log (--log-file): how hitches are found on a real machine.
func _log_hitch(delta: float, sim_us: int, hud_us: int) -> void:
	if delta > 0.0125 and _hitch_log < 400:
		_hitch_log += 1
		print("HITCH %.1f ms (previous frame); world on this thread %d us, hud %d us, thread %s, step running %s" % [delta * 1000.0, sim_us, hud_us, _sim != null, _frozen])
