-- Sinborn shared configuration: bloodlines, affinities, bosses and formulas.
-- Lives in ReplicatedStorage.Sinborn.Config so both server and client can read it.
-- Distances are in studs, speeds in studs per second, times in seconds.
-- Skill "dmg" is a multiplier of the player's skill power.

local C = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
C.rgb = rgb

C.THEME = {
	pit = rgb(11, 8, 9),
	stone = rgb(26, 19, 21),
	stone2 = rgb(36, 26, 29),
	seam = rgb(58, 42, 46),
	bone = rgb(236, 226, 214),
	ash = rgb(161, 146, 139),
	blood = rgb(196, 32, 47),
	ember = rgb(242, 169, 59),
	hp = rgb(210, 51, 69),
	mal = rgb(139, 77, 255),
	xp = rgb(242, 169, 59),
	soul = rgb(159, 230, 255),
	danger = rgb(255, 48, 64),
}

C.RARITY = {
	common = { name = "Common", color = rgb(183, 174, 166) },
	uncommon = { name = "Uncommon", color = rgb(108, 199, 122) },
	rare = { name = "Rare", color = rgb(90, 167, 255) },
	legendary = { name = "Legendary", color = rgb(242, 169, 59) },
	mythic = { name = "Mythic", color = rgb(255, 79, 176) },
}
C.RANK_LETTERS = { "D", "C", "B", "A", "S" }
C.RANK_COLORS = { rgb(183, 174, 166), rgb(108, 199, 122), rgb(90, 167, 255), rgb(242, 169, 59), rgb(255, 79, 176) }

C.SIN_ORDER = { "sloth", "gluttony", "greed", "envy", "lust", "wrath", "pride" }
C.SINS = {
	sloth = {
		name = "Sloth", rarity = "common", w = 30, color = rgb(111, 183, 255), bonus = { vit = 1.15 },
		passive = "Idle Grace: stand still for a second and your HP and Malice regenerate three times faster.",
		skills = {
			{ id = "sl1", name = "Dream Bolt", u = 1, cd = 3, cost = 12, kind = "proj", count = 1, speed = 62, r = 1.1, dmg = 2.2, life = 1.1, status = { "sleep", 2.2 }, desc = "A drowsy bolt that puts its target to sleep." },
			{ id = "sl2", name = "Lethargy Field", u = 4, cd = 9, cost = 25, kind = "vortex", rad = 18, dur = 4, pull = 0, dps = 0.8, status = { "slow", 1 }, desc = "A pool of torpor that slows and wears down everything inside." },
			{ id = "sl3", name = "Heavy Eyelids", u = 9, cd = 10, cost = 30, kind = "cone", range = 28, half = 0.65, dmg = 2.6, status = { "sleep", 3 }, desc = "A wave of exhaustion that sends everything in front of you to sleep." },
			{ id = "sl4", name = "Eternal Rest", u = 15, cd = 22, cost = 55, kind = "nova", at = "cursor", rad = 25, delay = 1.2, dmg = 9, status = { "stun", 1.6 }, desc = "After a long yawn, the ground at your aim collapses into dreamless sleep." },
		},
	},
	gluttony = {
		name = "Gluttony", rarity = "common", w = 25, color = rgb(255, 140, 46), bonus = { vit = 1.2, str = 1.05 },
		passive = "Bottomless: 10% of all damage you deal heals you.",
		skills = {
			{ id = "gl1", name = "Devour", u = 1, cd = 4, cost = 12, kind = "cone", range = 15, half = 0.8, dmg = 3, lifesteal = 0.5, desc = "A savage bite in front of you that heals for half the damage." },
			{ id = "gl2", name = "Bile Spit", u = 4, cd = 6, cost = 20, kind = "proj", count = 5, spread = 0.55, speed = 56, r = 0.9, dmg = 1.4, life = 0.7, status = { "slow", 2 }, desc = "A spray of corrosive bile that slows." },
			{ id = "gl3", name = "Gorge", u = 9, cd = 12, cost = 35, kind = "vortex", rad = 28, dur = 2.5, pull = 34, dps = 1.2, desc = "Open a hungry vortex that drags enemies in and chews them." },
			{ id = "gl4", name = "Maw of Hunger", u = 15, cd = 20, cost = 55, kind = "beam", len = 65, width = 10, delay = 0.5, dmg = 10, lifesteal = 0.3, desc = "A spectral jaw snaps shut along a line, feeding you." },
		},
	},
	greed = {
		name = "Greed", rarity = "uncommon", w = 18, color = rgb(245, 197, 66), bonus = { agi = 1.1, mal = 1.05 },
		passive = "Avarice: enemies drop 60% more souls.",
		skills = {
			{ id = "gr1", name = "Coin Fan", u = 1, cd = 2.5, cost = 10, kind = "proj", count = 3, spread = 0.35, speed = 77, r = 0.9, dmg = 1.8, pierce = 1, life = 0.8, desc = "Flick a fan of razor-edged coins." },
			{ id = "gr2", name = "Tithe Rush", u = 4, cd = 6, cost = 18, kind = "dash", dist = 36, width = 7, dmg = 3.5, soulsOnHit = 2, desc = "Dash through enemies, collecting a tithe of souls from each." },
			{ id = "gr3", name = "Golden Hoard", u = 9, cd = 16, cost = 30, kind = "shield", amount = 0.45, dur = 7, desc = "Wrap yourself in hoarded gold that absorbs damage." },
			{ id = "gr4", name = "Midas Touch", u = 15, cd = 20, cost = 50, kind = "nova", at = "cursor", rad = 20, delay = 0.6, dmg = 7, exec = 0.35, desc = "Turn enemies below 35% HP to gold. Bosses take heavy damage instead." },
		},
	},
	envy = {
		name = "Envy", rarity = "rare", w = 12, color = rgb(61, 220, 132), bonus = { agi = 1.15, mal = 1.1 },
		passive = "Covetous Eye: deal 25% more damage to enemies with a higher HP percentage than yours.",
		skills = {
			{ id = "en1", name = "Green Eye", u = 1, cd = 3, cost = 12, kind = "proj", count = 2, spread = 0.5, homing = true, speed = 52, r = 1, dmg = 2, life = 1.6, desc = "Two jealous eyes that hunt the nearest enemy." },
			{ id = "en2", name = "Jealous Chains", u = 4, cd = 7, cost = 20, kind = "proj", count = 1, speed = 86, r = 1, dmg = 2.5, pierce = 3, life = 0.8, status = { "root", 2.5 }, desc = "A chain that pierces and roots up to four enemies." },
			{ id = "en3", name = "Usurp", u = 9, cd = 9, cost = 28, kind = "blink", range = 43, rad = 16, dmg = 4, status = { "slow", 2 }, desc = "Step into the place you covet, bursting on arrival." },
			{ id = "en4", name = "Green-Eyed Monster", u = 15, cd = 22, cost = 55, kind = "rain", n = 10, area = 28, rad = 9, dmg = 3.6, interval = 0.12, desc = "Claws of envy tear up the ground around your aim." },
		},
	},
	lust = {
		name = "Lust", rarity = "rare", w = 9, color = rgb(255, 95, 162), bonus = { mal = 1.15, agi = 1.1 },
		passive = "Allure: melee hits have a 15% chance to charm, stopping the enemy from attacking.",
		skills = {
			{ id = "lu1", name = "Kiss of Thorns", u = 1, cd = 3, cost = 12, kind = "proj", count = 1, speed = 67, r = 1.1, dmg = 2.4, life = 1, status = { "charm", 2.5 }, desc = "A thorned kiss that charms its target." },
			{ id = "lu2", name = "Rose Whip", u = 4, cd = 5, cost = 18, kind = "beam", len = 41, width = 4.5, delay = 0.1, dmg = 4, knock = 20, desc = "A long lash of briars." },
			{ id = "lu3", name = "Allure", u = 9, cd = 12, cost = 32, kind = "nova", at = "self", rad = 30, dmg = 2, pull = 26, status = { "charm", 3 }, desc = "Draw every nearby enemy toward you, charmed." },
			{ id = "lu4", name = "Heartbreak", u = 15, cd = 20, cost = 55, kind = "nova", at = "self", rad = 45, delay = 0.8, dmg = 8, vsCharm = 2, desc = "Shatter every heart nearby. Charmed enemies take double damage." },
		},
	},
	wrath = {
		name = "Wrath", rarity = "legendary", w = 5, color = rgb(255, 59, 48), bonus = { str = 1.3, mal = 1.1 },
		passive = "Seething: deal up to 60% more damage the lower your HP falls.",
		skills = {
			{ id = "wr1", name = "Rage Fist", u = 1, cd = 4, cost = 14, kind = "dash", dist = 28, width = 8, dmg = 4, knock = 38, desc = "Lunge forward with a burning fist." },
			{ id = "wr2", name = "Eruption", u = 4, cd = 8, cost = 24, kind = "nova", at = "self", rad = 22, dmg = 4.5, status = { "burn", 3 }, knock = 31, desc = "Explode in rage, scorching and hurling enemies away." },
			{ id = "wr3", name = "Fury Barrage", u = 9, cd = 8, cost = 28, kind = "proj", count = 7, spread = 0.9, speed = 80, r = 0.9, dmg = 1.6, life = 0.7, status = { "burn", 2 }, desc = "Seven blazing strikes thrown at once." },
			{ id = "wr4", name = "Apocalypse", u = 15, cd = 24, cost = 60, kind = "rain", n = 16, area = 36, rad = 11, dmg = 5, interval = 0.1, status = { "burn", 3 }, desc = "Call down a storm of hellstones around your aim." },
		},
	},
	pride = {
		name = "Pride", rarity = "mythic", w = 1, color = rgb(227, 194, 255), bonus = { vit = 1.2, mal = 1.2, str = 1.2, agi = 1.2 }, takenMult = 0.9,
		passive = "Divine Right: +20% to every stat and 10% less damage taken.",
		skills = {
			{ id = "pr1", name = "Halo Lance", u = 1, cd = 2.5, cost = 12, kind = "beam", len = 74, width = 3.4, delay = 0.12, dmg = 3.5, desc = "A spear of radiant light that pierces the whole line." },
			{ id = "pr2", name = "Throne Quake", u = 4, cd = 8, cost = 24, kind = "nova", at = "self", rad = 28, dmg = 4, status = { "stun", 1.2 }, knock = 26, desc = "Stamp your authority into the ground, stunning all around you." },
			{ id = "pr3", name = "Judgement", u = 9, cd = 12, cost = 35, kind = "rain", n = 7, area = 20, rad = 10, dmg = 5, interval = 0.18, status = { "stun", 0.6 }, desc = "Pillars of light fall where you aim." },
			{ id = "pr4", name = "Morningstar's Fall", u = 15, cd = 26, cost = 70, kind = "nova", at = "cursor", rad = 37, delay = 1.4, dmg = 16, status = { "burn", 4 }, desc = "Drop a falling star where you aim." },
		},
	},
}

C.AFF_ORDER = { "hellfire", "frost", "brimstone", "storm", "umbra" }
C.AFFS = {
	hellfire = {
		name = "Hellfire", rarity = "common", w = 30, color = rgb(255, 106, 42), passive = "Fire that burns over time.",
		skills = {
			{ id = "hf1", name = "Hellfire Orb", u = 2, cd = 4, cost = 15, kind = "proj", count = 1, speed = 55, r = 1.7, dmg = 2.5, explode = 10, life = 1.2, status = { "burn", 3 }, desc = "A slow orb that bursts into flame on impact." },
			{ id = "hf2", name = "Inferno Ring", u = 7, cd = 11, cost = 30, kind = "nova", at = "self", rad = 25, dmg = 4, status = { "burn", 4 }, knock = 22, desc = "A ring of fire erupts around you." },
		},
	},
	frost = {
		name = "Cocytus Frost", rarity = "common", w = 26, color = rgb(159, 230, 255), passive = "Ice from the frozen lake. Slows and freezes.",
		skills = {
			{ id = "fr1", name = "Ice Shards", u = 2, cd = 3.5, cost = 14, kind = "proj", count = 3, spread = 0.25, speed = 72, r = 0.9, dmg = 1.8, life = 0.9, status = { "slow", 2.5 }, desc = "Three shards that chill and slow." },
			{ id = "fr2", name = "Frozen Tomb", u = 7, cd = 12, cost = 30, kind = "nova", at = "cursor", rad = 17, delay = 0.4, dmg = 3.5, status = { "stun", 2.2 }, desc = "Encase an area in ice, freezing enemies solid." },
		},
	},
	brimstone = {
		name = "Brimstone", rarity = "uncommon", w = 22, color = rgb(192, 138, 90), passive = "Sulphur and stone. Heavy knockback and roots.",
		skills = {
			{ id = "br1", name = "Boulder", u = 2, cd = 5, cost = 16, kind = "proj", count = 1, speed = 47, r = 2.6, dmg = 3.6, knock = 46, pierce = 2, life = 1.2, desc = "Hurl a smouldering boulder that bowls enemies over." },
			{ id = "br2", name = "Fissure", u = 7, cd = 11, cost = 28, kind = "beam", len = 50, width = 7.7, delay = 0.35, dmg = 4.2, status = { "root", 1.8 }, desc = "Split the ground in a line, rooting enemies." },
		},
	},
	storm = {
		name = "Storm", rarity = "rare", w = 15, color = rgb(201, 182, 255), passive = "Lightning from the second circle. Fast stuns.",
		skills = {
			{ id = "st1", name = "Chain Bolt", u = 2, cd = 3.5, cost = 14, kind = "beam", len = 55, width = 3, delay = 0, dmg = 3, status = { "stun", 0.45 }, desc = "An instant bolt that briefly stuns everything it crosses." },
			{ id = "st2", name = "Thunderhead", u = 7, cd = 12, cost = 32, kind = "rain", n = 8, area = 25, rad = 8, dmg = 3, interval = 0.15, status = { "stun", 0.5 }, desc = "Lightning strikes rain down around your aim." },
		},
	},
	umbra = {
		name = "Umbra", rarity = "legendary", w = 7, color = rgb(143, 107, 255), passive = "Living shadow. Steals life.",
		skills = {
			{ id = "um1", name = "Shade Bolt", u = 2, cd = 3.5, cost = 14, kind = "proj", count = 1, homing = true, speed = 58, r = 1.1, dmg = 2.6, lifesteal = 0.3, life = 1.5, desc = "A seeking bolt of shadow that drains life." },
			{ id = "um2", name = "Night Veil", u = 7, cd = 13, cost = 30, kind = "nova", at = "self", rad = 23, dmg = 3, heal = 0.15, status = { "slow", 2 }, desc = "Shadow bursts from you, healing 15% HP." },
		},
	},
}

-- Bosses: one Hollow Prince per sin, behind a sealed arena.
C.BOSSES = {
	{ sin = "sloth", name = "Belphag the Slumbering", req = 5, atks = { "slam", "burst", "summon" }, speed = 8.5, r = 5.5 },
	{ sin = "gluttony", name = "Gorlund, the Endless Maw", req = 9, atks = { "charge", "slam", "pull" }, speed = 11, r = 6.2 },
	{ sin = "greed", name = "Aurix the Hoarder", req = 13, atks = { "aimed", "burst", "summon" }, speed = 13, r = 4.8 },
	{ sin = "envy", name = "Viridia, Mother of Envy", req = 17, atks = { "aimed", "slam", "summon", "burst" }, speed = 15.5, r = 4.8 },
	{ sin = "lust", name = "Seraphine Thornheart", req = 21, atks = { "spiral", "charge", "aimed" }, speed = 18, r = 4.6 },
	{ sin = "wrath", name = "Kharos the Unquenched", req = 25, atks = { "charge", "slam", "burst", "spiral" }, speed = 18, r = 5.8 },
	{ sin = "pride", name = "Lucant, the Unbowed Crown", req = 30, atks = { "spiral", "slam", "aimed", "charge", "summon" }, speed = 19, r = 5.3 },
}

C.RANKS = { { 1, "Initiate" }, { 5, "Acolyte" }, { 10, "Sinner" }, { 15, "Fallen" }, { 20, "Archfiend" }, { 25, "Sin Prince" }, { 30, "Sin Lord" } }
C.STAT_ORDER = { "vit", "mal", "str", "agi" }
C.STAT_INFO = {
	vit = { name = "Vitality", short = "VIT", d = "+12 max HP per point. Trains when you take hits." },
	mal = { name = "Malice", short = "MAL", d = "Skill damage and max Malice. Trains while charging (faster at the Altar)." },
	str = { name = "Strength", short = "STR", d = "Melee damage. Trains with every melee hit, dummies included." },
	agi = { name = "Agility", short = "AGI", d = "Move speed. Trains when you dash and run." },
}
C.ETYPES = {
	imp = { name = "Imp", r = 1.5, speed = 18, hp = 1.0, dmg = 1.0, xp = 1.0, color = rgb(184, 50, 58), minL = 1, w = 5 },
	hound = { name = "Hellhound", r = 1.6, speed = 28, hp = 0.75, dmg = 0.85, xp = 1.1, color = rgb(208, 106, 42), minL = 3, w = 3 },
	wisp = { name = "Wisp", r = 1.4, speed = 14.5, hp = 0.6, dmg = 0.9, xp = 1.1, color = rgb(169, 139, 255), minL = 5, w = 2.4 },
	brute = { name = "Brute", r = 3, speed = 11, hp = 2.6, dmg = 1.7, xp = 2.2, color = rgb(107, 58, 63), minL = 8, w = 1.6 },
}
C.ETYPE_ORDER = { "imp", "hound", "wisp", "brute" }
C.MAST = { 0, 10, 30, 70, 140 }
C.LEVEL_CAP = 40
C.START_SPINS = 8
C.PITY = 50

C.WORLD = {
	R = 280, villageR = 60, arenaR = 40, cursorRange = 53,
	meleeRange = 8, meleeHalf = 1.0, playerR = 1.5,
}

-- Gate centres (x, z). Bosses sit further out as their level rises.
C.GATES = {}
for i = 1, 7 do
	local a = -math.pi / 2 + (i - 1) * (math.pi * 2 / 7) * 3 + 0.3
	local d = 110 + (i - 1) * 22
	C.GATES[i] = { x = math.cos(a) * d, z = math.sin(a) * d, i = i }
end

-- ---------- formulas ----------
function C.enemyLevelAt(x, z)
	local d = math.sqrt(x * x + z * z)
	local l = math.floor(1 + (d - C.WORLD.villageR) / 6.6)
	if l < 1 then l = 1 end
	if l > 36 then l = 36 end
	return l
end
function C.enemyHP(l) return 24 + l * 10 + l * l * 0.9 end
function C.enemyDMG(l) return 5 + l * 1.6 + l * l * 0.03 end
function C.xpNeed(l) return math.floor(40 * l ^ 1.55 + 40) end

function C.rankName(l)
	local n = C.RANKS[1][2]
	for _, r in ipairs(C.RANKS) do
		if l >= r[1] then n = r[2] end
	end
	return n
end
function C.eff(prof, s)
	return prof.stats[s] * (C.SINS[prof.sin].bonus[s] or 1)
end
function C.maxHp(prof) return math.floor(100 + prof.level * 8 + C.eff(prof, "vit") * 12 + 0.5) end
function C.maxMal(prof) return math.floor(100 + C.eff(prof, "mal") * 8 + 0.5) end
function C.meleePow(prof) return (8 + C.eff(prof, "str") * 2.2) * (1 + prof.level * 0.03) end
function C.skillPow(prof) return (6 + C.eff(prof, "mal") * 1.1) * (1 + prof.level * 0.03) end
function C.moveSpeed(prof) return math.min(30, 16 + C.eff(prof, "agi") * 0.22) end
function C.trainNeed(prof, s) return 15 + prof.stats[s] * 3 end
function C.mastery(prof, id)
	local u = prof.mastery[id] or 0
	local m = 1
	for i = 2, #C.MAST do
		if u >= C.MAST[i] then m = i end
	end
	return m
end

-- The six active skills for a profile, each tagged with its key and source.
C.KEYS = { "1", "2", "3", "4", "Z", "X" }
function C.currentSkills(prof)
	local out = {}
	local s = C.SINS[prof.sin]
	for i, sk in ipairs(s.skills) do
		local c = {}
		for k, v in pairs(sk) do c[k] = v end
		c.key = C.KEYS[i]
		c.src = prof.sin
		c.color = s.color
		out[#out + 1] = c
	end
	local a = C.AFFS[prof.aff]
	for i, sk in ipairs(a.skills) do
		local c = {}
		for k, v in pairs(sk) do c[k] = v end
		c.key = C.KEYS[4 + i]
		c.src = prof.aff
		c.color = a.color
		out[#out + 1] = c
	end
	return out
end
function C.findSkill(prof, key)
	for _, sk in ipairs(C.currentSkills(prof)) do
		if sk.key == key then return sk end
	end
	return nil
end

function C.weightedPick(order, tbl, rng)
	local total = 0
	for _, k in ipairs(order) do total = total + tbl[k].w end
	local r = (rng and rng:NextNumber() or math.random()) * total
	for _, k in ipairs(order) do
		r = r - tbl[k].w
		if r <= 0 then return k end
	end
	return order[1]
end

function C.newProfile(name)
	return {
		v = 1, name = name or "Soul",
		sin = C.weightedPick(C.SIN_ORDER, C.SINS), aff = C.weightedPick(C.AFF_ORDER, C.AFFS),
		level = 1, xp = 0, souls = 60, spins = C.START_SPINS, spinsBought = 0, pity = 0,
		stats = { vit = 5, mal = 5, str = 5, agi = 5 }, train = { vit = 0, mal = 0, str = 0, agi = 0 }, points = 0,
		mastery = {}, bosses = {}, slots = { "", "" }, board = {}, mission = nil,
		kills = 0, deaths = 0, created = false,
	}
end

function C.hasBoss(prof, i)
	for _, b in ipairs(prof.bosses) do
		if b == i then return true end
	end
	return false
end

return C
