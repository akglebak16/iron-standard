extends RefCounted

var id: int
var side: int
var position: Vector2
var hp: float
var max_hp: float
var armor: float
var morale: float
var base_morale: float
var tier: int
var weight: float = 1.0
var dead: bool = false
var gone: bool = false
var kills: int = 0
var leader: bool = false
var hero: bool = false
var group_kind: int = 0
var slot_offset: Vector2 = Vector2.ZERO

func _init(unit_id: int, unit_side: int, at: Vector2, health: float, protection: float, unit_tier: int) -> void:
	id = unit_id
	side = unit_side
	position = at
	hp = health
	max_hp = health
	armor = protection
	tier = unit_tier
	base_morale = 72.0 + tier * 14.0
	morale = base_morale
