extends RefCounted
const Config = preload("res://core/campaign/config.gd")
const Relations = preload("res://core/campaign/rules/relations.gd")

static func apply_victory(party: Dictionary, policy: Dictionary, reward_bonus: float) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	if not party.has("quests"):
		return completed
	var remaining: Array = []
	for quest in party.quests:
		if not _progress(quest, policy):
			remaining.append(quest)
			continue
		var gold := roundi(float(quest.reward) * (1.0 + reward_bonus))
		party.gold += gold
		Relations.reward(party, quest.get("fac", ""), Config.QUEST_RELATION_REWARD)
		completed.append({"id": quest.get("id"), "gold": gold})
	party.quests = remaining
	return completed

static func _progress(quest: Dictionary, policy: Dictionary) -> bool:
	if quest.get("type") == Config.CAMP_QUEST:
		var target: Variant = policy.get("camp_target")
		return target != null and quest.get("sid") == target
	if quest.get("type") == Config.PURGE_QUEST and policy.progress_purge:
		quest.got = int(quest.get("got", 0)) + 1
		return quest.got >= quest.n
	return false
