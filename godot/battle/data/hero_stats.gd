extends RefCounted
## Applies a detached hero gear projection to a runtime Unit.
const Config = preload("res://battle/config.gd")
const EquipmentConfig = preload("res://equipment/config.gd")
const Unit = preload("res://battle/model/unit.gd")

static func apply(hero: Unit, profile: Dictionary, gear: Dictionary, initial: bool = true) -> bool:
	for stat in ["str", "agi", "vit", "cha", "lead", "hp"]:
		var value: Variant = profile.get(stat, 1.0 if stat == "hp" else 0.0)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0.0:
			return false
	var strength: float = float(profile.get("str", 0.0))
	var agility: float = float(profile.get("agi", 0.0))
	var vitality: float = float(profile.get("vit", 0.0))
	var weapon: Dictionary = gear.weapon
	var ranged: bool = weapon.get("slot") == "ranged"
	var effects: Dictionary = hero.perk_effects
	var heavy_bonus: float = float(effects.get("heavy", 0.0)) if not ranged and int(weapon.get("hands", 1)) == 2 else 0.0
	if initial:
		hero.max_hp = roundf((Config.HERO_BASE_HEALTH + vitality * Config.HERO_HEALTH_PER_VITALITY) * (1.0 + float(effects.get("hp", 0.0))))
		hero.hp = maxf(hero.max_hp * Config.HERO_MIN_HEALTH_FRACTION, hero.max_hp * float(profile.get("hp", 1.0)))
		hero.mounted = bool(gear.mounted)
		hero.speed = float(gear.horse.v) if hero.mounted else Config.HERO_BASE_FOOT_SPEED + agility * Config.HERO_SPEED_PER_AGILITY
		hero.speed *= 1.0 + float(effects.get("run", 0.0))
		hero.collision_radius = Config.HORSE_COLLISION_RADIUS if hero.mounted else Config.FOOT_COLLISION_RADIUS
		hero.mass = Config.HORSE_MASS if hero.mounted else Config.FOOT_MASS
	hero.armor = float(gear.armor) + float(effects.get("arm", 0.0))
	hero.damage = (float(weapon.dmg) + strength * (float(weapon.get("bs", 0.0)) if ranged else Config.HERO_MELEE_DAMAGE_PER_STRENGTH)) * (1.0 + float(effects.get("dmg", 0.0)) + heavy_bonus)
	hero.attack_interval = (maxf(Config.HERO_RANGED_MIN_COOLDOWN, float(weapon.cd) * (1.0 - agility * Config.HERO_RANGED_AGILITY_COOLDOWN)) if ranged else maxf(Config.HERO_MELEE_MIN_COOLDOWN, Config.HERO_MELEE_BASE_COOLDOWN - agility * Config.HERO_MELEE_AGILITY_COOLDOWN) * float(weapon.spd)) * (1.0 - float(effects.get("cd", 0.0)))
	hero.attack_range = roundf(float(weapon.range) * (1.0 + float(effects.get("range", 0.0)))) if ranged else 0.0
	hero.block_chance = float(gear.block)
	hero.shield_block = float(EquipmentConfig.SHIELD_ARROW_BONUS.get(gear.shield.get("look", ""), 0.0))
	hero.weapon_kind = str(weapon.wt)
	hero.damage_type = str(weapon.dt)
	hero.pierce = float(weapon.get("pb", 0.0))
	hero.accuracy = float(weapon.get("acc", 0.0)) * (1.0 - float(effects.get("acc", 0.0))) * Config.HERO_GEAR_ACCURACY_MULTIPLIER
	hero.anti_cavalry = bool(weapon.get("anticav", false))
	hero.hero_weapon = weapon.duplicate(true)
	return true
