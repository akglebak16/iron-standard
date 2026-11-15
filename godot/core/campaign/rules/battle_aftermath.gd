extends RefCounted
## Party-local portion of applyBattleResult. The caller owns world changes.
const Config = preload("res://core/campaign/config.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Progression = preload("res://core/characters/rules/progression.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const PerkEffects = preload("res://core/characters/rules/perk_effects.gd")
const CompanionProfile = preload("res://core/characters/rules/companion_profile.gd")

## Returns a detached party and a summary. Effects already combine hero perks and companion skills.
## The encounter supplies the original enemy army and a loot policy selected by the caller.
static func resolve(party: Dictionary, result: Dictionary, encounter: Dictionary, effects: Dictionary, troops: Catalog, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog) -> Dictionary:
	if troops == null or rng == null or companions == null or perks == null or not result.get("win") is bool or not result.get("dead") is Dictionary or not result.get("wounded") is Dictionary:
		return {}
	if not party.get("hero") is Dictionary or not party.get("troops") is Array or not encounter.get("troops") is Array:
		return {}
	var enemy_value := 0
	if result.win:
		for stack in encounter.troops:
			var troop := troops.get_troop(stack.type)
			if troop.is_empty():
				return {}
			enemy_value += int(stack.n) * (int(troop.tier) * Config.TROOP_GOLD_PER_TIER + Config.TROOP_BASE_GOLD)
	var updated := party.duplicate(true)
	var remaining: Array = []
	for stack in updated.troops:
		stack.n = int(stack.n) - int(result.dead.get(stack.type, 0))
		if stack.n > 0:
			remaining.append(stack)
	updated.troops = remaining
	var hero: Dictionary = updated.hero
	hero.hp = clampf(float(result.heroHp), Config.HERO_MIN_RECOVERY_HEALTH, 1.0)
	var stats: Dictionary = updated.get("stats", {})
	var inventory: Dictionary = updated.get("inv", {})
	var summary := {"win": result.win, "lost": _total(result.dead), "wounded": _total(result.wounded), "loot": 0, "lost_gold": 0, "xp": 0}
	var xp_multiplier := Progression.xp_multiplier(hero, float(effects.get("xp", 0.0)))
	if result.win:
		var provisions: Vector2i = encounter.get("provisions", Config.BATTLE_PROVISIONS)
		var base_gold := enemy_value * rng.randf_range(Config.BATTLE_GOLD_MIN, Config.BATTLE_GOLD_MAX) * float(encounter.get("gold_multiplier", 1.0))
		base_gold += int(encounter.get("gold", 0)) + int(encounter.get("bonus_gold", 0))
		summary.loot = roundi(base_gold * (1.0 + float(effects.get("loot", 0.0))))
		updated.gold += summary.loot
		var portions := rng.randi_range(provisions.x, provisions.y)
		if portions > 0:
			inventory[Config.GRAIN_ID] = int(inventory.get(Config.GRAIN_ID, 0)) + ceili(float(portions) / Config.PORTIONS_PER_GRAIN)
		stats.wins = int(stats.get("wins", 0)) + 1
		stats.kills = int(stats.get("kills", 0)) + int(result.enemyDead)
		summary.xp = roundi((float(result.xp) + Config.VICTORY_BASE_XP + int(result.heroKills) * Config.HERO_KILL_XP) * xp_multiplier)
	else:
		summary.lost_gold = roundi(int(updated.gold) * Config.DEFEAT_GOLD_SHARE)
		updated.gold -= summary.lost_gold
		summary.xp = roundi(float(result.xp) * Config.DEFEAT_XP_SHARE * xp_multiplier)
	updated.stats = stats
	updated.inv = inventory
	summary.levels_gained = Progression.gain_hero_xp(hero, summary.xp)
	summary.comps = _apply_companions(updated.get("comps", []), result, companions, perks)
	return {"party": updated, "summary": summary}

static func _apply_companions(roster: Array, result: Dictionary, catalog: CompanionCatalog, perks: PerkCatalog) -> Dictionary:
	var outcomes: Dictionary = result.get("comps", {})
	var updates := {}
	for companion in roster:
		if not outcomes.has(companion.id):
			continue
		var definition := catalog.get_companion(companion.id)
		var resolved := CompanionProfile.resolve(companion, catalog)
		if resolved.is_empty():
			continue
		companion.merge(resolved.profile)
		var outcome: Dictionary = outcomes[companion.id]
		companion.hp = Config.COMPANION_MIN_RECOVERY_HEALTH if outcome.down else clampf(float(outcome.hp), Config.COMPANION_MIN_RECOVERY_HEALTH, 1.0)
		var own := PerkEffects.own(companion, perks)
		var share := 1.0 if result.win else Config.DEFEAT_XP_SHARE
		var base_xp := share * float(result.xp) * Config.COMPANION_BATTLE_XP_SHARE + int(outcome.kills) * Config.COMPANION_KILL_XP + Config.COMPANION_BASE_XP
		var xp := roundi(base_xp * Progression.xp_multiplier(companion, float(own.get("xp", 0))))
		var levels := Progression.gain_companion_xp(companion, xp, definition.grow)
		updates[companion.id] = {"down": outcome.down, "kills": outcome.kills, "xp": xp, "levels_gained": levels}
	return updates

static func _total(counts: Dictionary) -> int:
	var total := 0
	for count in counts.values():
		total += int(count)
	return total
