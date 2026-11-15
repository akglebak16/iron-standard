extends RefCounted
## Human-readable battle outcome shared by the demo and the world map.
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const GoodsCatalog = preload("res://core/campaign/data/goods_catalog.gd")
const DEMO_REWARD_TEXT := "\nПогибло: %d · Ранено: %d · Золото: %+d · Опыт: +%d · Трофеи: %s"
const NO_DROPS := "—"
const COMPANION_XP_TEXT := "%s +%d опыта"
const COMPANION_LEVEL_TEXT := " (ур. %d)"
const RECOVERY_TEXT := "\nГерой очнулся у города %s."
const QUEST_REWARDS_TEXT := "\nЗаданий выполнено: %d · Награда: %d золота"
const BARROW_CLEARED_TEXT := "\nЧёрный курган разрушен."

static func drop_names(drops: Array, gear: GearCatalog, goods: GoodsCatalog) -> PackedStringArray:
	var names: PackedStringArray = []
	if drops.is_empty():
		return names
	var trade_goods := goods.definitions()
	for drop in drops:
		var item := gear.get_item(drop.id)
		var display_name: String = item.name if not item.is_empty() else trade_goods[drop.id].n
		names.append("%s ×%d" % [display_name, drop.n])
	return names

static func build(resolved: Dictionary, gear: GearCatalog, goods: GoodsCatalog) -> String:
	var summary: Dictionary = resolved.summary
	var names := drop_names(summary.drops, gear, goods)
	var gold_change: int = summary.loot - summary.lost_gold + summary.get("recovery_gold", 0)
	var text := DEMO_REWARD_TEXT % [summary.lost, summary.wounded, gold_change, summary.xp, NO_DROPS if names.is_empty() else ", ".join(names)]
	if summary.has("recovery_town"):
		text += RECOVERY_TEXT % summary.recovery_town
	if summary.get("barrow_destroyed", false):
		text += BARROW_CLEARED_TEXT
	var completed: Array = summary.get("completed_quests", [])
	if not completed.is_empty():
		var reward := 0
		for quest in completed:
			reward += int(quest.gold)
		text += QUEST_REWARDS_TEXT % [completed.size(), reward]
	var companions_text := PackedStringArray()
	for profile in resolved.party.comps:
		if not summary.comps.has(profile.id):
			continue
		var gain: Dictionary = summary.comps[profile.id]
		var line := COMPANION_XP_TEXT % [profile.name, gain.xp]
		if gain.levels_gained > 0:
			line += COMPANION_LEVEL_TEXT % profile.lvl
		companions_text.append(line)
	if not companions_text.is_empty():
		text += "\n" + " · ".join(companions_text)
	return text
