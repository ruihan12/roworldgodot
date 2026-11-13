# Port of RoWorld src/shared/Data/BotNames.luau: names for bot players, built like ordinary player
# handles ("IronFalcon", "nova_ryder", "Blaze27", "QuietStorm_9") so bots pass for real players.
class_name BotNames
extends RefCounted

const FIRST := [
	"Iron", "Nova", "Shadow", "Silent", "Frost", "Blaze", "Storm", "Lunar", "Solar", "Crimson", "Echo", "Rogue",
	"Swift", "Atlas", "Ember", "Onyx", "Cobalt", "Viper", "Rapid", "Quiet", "Night", "Golden", "Wild", "Bright",
	"Dark", "Lucky", "Mighty", "Neon", "Pixel", "Turbo", "Arctic", "Stealth", "Hyper", "Royal", "Sly", "Brave",
	"Cosmic", "Mystic", "Rusty", "Titan", "Zen", "Aqua", "Lazy", "Epic", "Chill", "Sonic", "Venom", "Ghost",
	"Alpha", "Omega", "Red", "Blue", "Grey", "Jade", "Scarlet", "Amber", "Polar", "Desert", "Jungle", "Coastal"
]
const SECOND := [
	"Falcon", "Ryder", "Wolf", "Storm", "Tide", "Fox", "Hawk", "Knight", "Raven", "Tiger", "Comet", "Pilot",
	"Ranger", "Viking", "Ninja", "Dragon", "Panther", "Orbit", "Arrow", "Bolt", "Blade", "Spark", "Rider",
	"Hunter", "Legend", "Sniper", "Warden", "Captain", "Baron", "Rebel", "Nomad", "Phantom", "Racer", "Sparrow",
	"Bear", "Lynx", "Cobra", "Shark", "Owl", "Stag", "Mage", "Scout", "Pirate", "Samurai", "Duke", "General",
	"Major", "Titan", "Golem", "Kraken", "Moose", "Otter", "Badger", "Falcon", "Jester", "Maverick", "Voyager",
	"Spectre", "Drifter", "Ace"
]
const SINGLE := [
	"Kaizen", "Morrow", "Zephyr", "Quill", "Brixton", "Marlow", "Juniper", "Oakley", "Rowan", "Sable", "Tobias",
	"Wren", "Kestrel", "Lachlan", "Nico", "Ezra", "Milo", "Jasper", "Felix", "Leo", "Arlo", "Silas", "Theo",
	"Ivy", "Luna", "Nova", "Aria", "Zara", "Kira", "Maya"
]

# A name from `rand` (a Callable returning a float in [0, 1)).
static func one(rand: Callable) -> String:
	var pick := func(list: Array) -> String: return list[int(floor(float(rand.call()) * list.size()))]
	var style: float = rand.call()
	if style < 0.35: return pick.call(FIRST) + pick.call(SECOND)
	if style < 0.55: return str(pick.call(FIRST)).to_lower() + "_" + str(pick.call(SECOND)).to_lower()
	if style < 0.75: return pick.call(FIRST) + pick.call(SECOND) + str(int(floor(float(rand.call()) * 99)) + 1)
	if style < 0.9: return pick.call(SINGLE) + str(int(floor(float(rand.call()) * 900)) + 100)
	return pick.call(FIRST) + "_" + pick.call(SINGLE)

# `n` distinct names not in `taken` (names already used in the match; updated).
static func many(n: int, rand: Callable, taken := {}) -> Array:
	var out := []
	var guard := 0
	while out.size() < n and guard < n * 50:
		guard += 1
		var name := one(rand)
		if not taken.has(name):
			taken[name] = true
			out.append(name)
	while out.size() < n:
		var name := "Player%d" % (out.size() + 1000)
		taken[name] = true
		out.append(name)
	return out
