extends RefCounted
## Public fixed-tick boundary. The legacy backend is private to this temporary adapter.
## Commands own their data; caller-provided IDs are validated by the backend.
const Session = preload("res://battle/application/session.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
var _session: Session
var _commands: Array[Dictionary] = []

func _init(session: Session) -> void:
	_session = session

func submit(commands: Array[Dictionary]) -> bool:
	if _session == null: return false
	for command in commands:
		if command.get("kind", "") not in ["order", "hero_input", "weapon", "retreat"]: return false
		if command.kind == "order":
			if not command.get("point") is Vector2 or not command.point.is_finite() or not command.get("order") is String or not command.get("selection") is int: return false
		elif command.kind == "hero_input":
			if not command.get("move") is Vector2 or not command.move.is_finite() or not is_finite(float(command.get("face", NAN))): return false
		elif command.kind == "weapon" and not command.get("slot") is String: return false
	_commands.append_array(commands.duplicate(true))
	return true

func step() -> void:
	if _session == null: return
	for command in _commands:
		match command.kind:
			"order": _session.issue_order(command.order, command.point, command.selection)
			"weapon": _session.request_weapon_slot(command.slot)
			"retreat": _session.request_retreat()
			"hero_input":
				var input := HeroInput.new()
				input.move = command.move
				input.face = command.face
				input.attack = bool(command.get("attack", false))
				input.block = bool(command.get("block", false))
				input.sprint = bool(command.get("sprint", false))
				input.swap = bool(command.get("swap", false))
				_session.set_hero_input(input)
	_commands.clear()
	_session.step()

func snapshot() -> Dictionary:
	return _session.snapshot() if _session != null else {}

func render_snapshot() -> Dictionary:
	return _session.snapshot(true) if _session != null else {}

func take_events() -> Array[Dictionary]:
	return _session.take_events() if _session != null else []

func result() -> Dictionary:
	return _session.result() if _session != null else {}

func dispose() -> void:
	_commands.clear()
	_session = null
