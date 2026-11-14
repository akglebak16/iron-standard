extends RefCounted
## Wall defenders' supplies during an assault (src/03c_siegedef.js B.sd). Values only; rules/siege_defense.gd changes them.
const Config = preload("res://battle/config.gd")

var stones: int = 0
var stone_cooldown: float = Config.SIEGE_STONE_FIRST_DELAY
var stones_in_flight: Array[Dictionary] = [] # origin, impact, time, duration
var fires: Array[Dictionary] = [] # center, half_size, time, duration, damage_timer, pour_from
var cauldrons: Array[Dictionary] = [] # gap, charges, cooldown
var announced: int = 0 # 0 none, 1 stones, 2 oil; the browser announces at most these two lines.

func _init(gaps: Array[Vector2], supplies: Dictionary, wall_damage: float) -> void:
	var damage := clampf(wall_damage, 0.0, 1.0)
	var kept := 1.0 - damage * Config.SIEGE_DAMAGE_SUPPLY_LOSS
	var oil := int(supplies.get("oil", Config.SIEGE_DEFAULT_OIL))
	stones = roundi(int(supplies.get("stones", Config.SIEGE_DEFAULT_STONES)) * kept)
	for i in gaps.size():
		var minimum := 1 if i == 0 or oil >= Config.SIEGE_SIDE_CAULDRON_MIN_OIL else 0
		var charges := maxi(minimum, roundi(oil * kept * (1.0 if i == 0 else Config.SIEGE_SIDE_OIL_SHARE)))
		cauldrons.append({"gap": gaps[i], "charges": charges, "cooldown": Config.SIEGE_OIL_FIRST_DELAY + i * Config.SIEGE_OIL_DELAY_STEP})
