extends RefCounted
## Equipment rules shared by battle calculations and future inventory UI.
const DAMAGE_TYPE_CUT := "cut"
const DAMAGE_TYPE_PIERCE := "pierce"
const DAMAGE_TYPE_BLUNT := "blunt"
const ARMOR_LIGHT_MAX := 18.0
const ARMOR_MEDIUM_MAX := 38.0
const DAMAGE_TYPE_PIERCE_CAP := 0.8
const LIGHT_ARMOR_CUT_MULTIPLIER := 1.15
const DAMAGE_TYPE_ARMOR_PIERCE := {
	DAMAGE_TYPE_CUT: [0.0, 0.06, 0.0],
	DAMAGE_TYPE_PIERCE: [0.18, 0.38, 0.22],
	DAMAGE_TYPE_BLUNT: [0.10, 0.26, 0.42],
}
const SHIELD_ARROW_BONUS := {"kite": 0.18, "round": 0.12, "small": 0.07}
