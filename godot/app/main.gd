extends Node2D
## Composition root: the only place that connects storage, scenario and view.
const Catalog = preload("res://battle/data/catalog.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const BattleView = preload("res://battle/presentation/scene.tscn")
@export var battle_setup: Setup = preload("res://battle/data/demo_battle.tres")

func _ready() -> void:
	var catalog := Catalog.new()
	if not catalog.load_data():
		push_error("Cannot load battle catalog")
		return
	var session = Factory.create(battle_setup, catalog)
	if session == null:
		push_error("Invalid battle setup")
		return
	var view = BattleView.instantiate()
	view.name = "Battle"
	view.configure(session)
	add_child(view)
