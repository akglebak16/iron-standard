extends RefCounted
## AI profiles of a battle side (ADR-022). A profile id from BattleSetup selects the brain that makes the
## side's group decisions. A brain is a script with two static functions, the contract of tactics.gd:
##   enemy_step(battle: State, command: int, elapsed: float, dt: float) -> void  # field decisions of `command`
##   siege_step(battle: State, elapsed: float, dt: float) -> void            # siege defenders (side 1)
## A new brain is added here under a new id; the reference brain stays frozen for the arena. The commander of stage 1g
## (commander.gd, DESIGN.md 4.2) leads a side only where a setup asks for it: the arena and tests until part 7 (#272).
const Config = preload("res://core/battle/config.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Commander = preload("res://core/battle/simulation/ai/commander.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")

const BRAINS := {Config.AI_PROFILE_REFERENCE: Tactics, Config.AI_PROFILE_COMMANDER: Commander}

static func is_known(profile: String) -> bool:
	return profile == Config.AI_PROFILE_PLAYER or BRAINS.has(profile)

## Null for the player's profile: that side gets its orders as commands.
static func brain(profile: String) -> Script:
	return BRAINS.get(profile)

## Siege defenders cannot follow player orders: the siege brain also batters the gates and opens them.
static func valid(setup: Setup) -> bool:
	if not is_known(setup.player_ai_profile) or not is_known(setup.enemy_ai_profile):
		return false
	return not (setup.siege and setup.enemy_ai_profile == Config.AI_PROFILE_PLAYER)
