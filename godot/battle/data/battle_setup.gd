extends Resource
## Authoring data only. A factory creates new mutable runtime objects for each battle.
@export var seed: int = 0
@export var player_faction: String = ""
@export var enemy_faction: String = ""
@export var player_army: Array[Dictionary] = []
@export var enemy_army: Array[Dictionary] = []
@export var hero_troop: String = ""
@export var hero_position : Vector2 = Vector2.ZERO
