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
const WorldPartiesLayer = preload("res://campaign/presentation/world_parties_layer.gd")
const WorldHud = preload("res://campaign/presentation/world_hud.gd")

var state: RefCounted
var map_view: Node2D
var _meeting: Dictionary = {}
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
	var seed_value := 12345
	var focus := PackedFloat64Array()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--focus="):
			for part in arg.substr(8).split(","):
				focus.append(float(part))
	var data := EuropeData.new()
	assert(data.load_data())
	state = WorldState.create(seed_value, data)
	map_view = MapView.new()
	add_child(map_view)
	map_view.build_from(state.map)
	var factions := FactionCatalog.new()
	factions.load_data()
	var others := WorldPartiesLayer.new()
	map_view.add_child(others)
	others.build(state.roster, state.player)
	var party_layer := PartyLayer.new()
	map_view.add_child(party_layer)
	party_layer.build(state.player, factions.get_faction("player"))
	camera = WorldCamera.new()
	add_child(camera)
	camera.make_current()
	camera.fit_all()
	camera.map_clicked.connect(func(p: Vector2): state.player.path_to(state.map.paths, p.x, p.y))
	camera.map_hovered.connect(_on_hover)
	hud = WorldHud.new()
	add_child(hud)
	hud.speed_changed.connect(func(s: int): state.clock.speed = s; state.clock.paused = false)
	hud.pause_toggled.connect(func(): state.clock.paused = not state.clock.paused)
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

func _on_party_met(party: Dictionary, _forced: bool) -> void:
	_meeting = party
	state.clock.paused = true
	var n := 0
	for s in party.troops:
		n += int(s.n)
	hud.show_notice("Встреча: %s (%d бойцов). Enter — разойтись" % [party.name, n])

func _on_hover(world_pos: Vector2, screen_pos: Vector2) -> void:
	hud.show_tip(state.settlement_near(world_pos.x, world_pos.y, 46.0), screen_pos)

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_play or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if not _meeting.is_empty():  # the battle hand-off arrives with the encounter slice
				_meeting.cd = 6.0
				_meeting = {}
				state.player.busy = ""
				state.clock.paused = false
				hud.show_notice("")
		KEY_SPACE:
			state.clock.paused = not state.clock.paused
		KEY_1, KEY_2, KEY_3:
			state.clock.speed = [1, 2, 4][(event as InputEventKey).keycode - KEY_1]
			state.clock.paused = false

func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	state.advance(delta)
	if not camera.detached:
		camera.position = Vector2(state.player.x, state.player.y)
	hud.refresh(state, state.settlement_near(state.player.x, state.player.y, 46.0))
