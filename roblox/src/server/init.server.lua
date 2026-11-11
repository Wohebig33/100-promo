-- Sinborn server: profiles, combat, enemies, bosses, missions, spins and the shop.
-- The server owns all game state; clients only send intents (aim point + action).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = RS:WaitForChild("Sinborn")
local C = require(Root:WaitForChild("Config"))
local Data = require(script:WaitForChild("Data"))
local World = require(script:WaitForChild("World"))

-- ---------- remotes ----------
local remotes = Root:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
end
local function remote(n)
	local r = remotes:FindFirstChild(n)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = n
		r.Parent = remotes
	end
	return r
end
local Action = remote("Action")
local StateR = remote("State")
local FXR = remote("FX")
local Notify = remote("Notify")
remotes.Parent = Root

Players.RespawnTime = 4
local W = World.build()
local rng = Random.new()
local T = C.THEME
local WR = C.WORLD
local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)
local GOLD = C.rgb(255, 211, 107)

-- ---------- state ----------
local clock = 0
local profiles = {}
local PS = {}
local dirty = {}
local enemies = {}
local pproj, eproj, fields = {}, {}, {}
local activeBoss = {}

-- ---------- utils ----------
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function d2(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
local function clamp(v, a, b)
	if v < a then return a elseif v > b then return b end
	return v
end
local function dirFromAngle(a) return Vector3.new(math.cos(a), 0, math.sin(a)) end
local function angleOf(v) return math.atan2(v.Z, v.X) end
local function validVec(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e5 and math.abs(v.Z) < 1e5
end
local function copy(t)
	local o = {}
	for k, v in pairs(t) do o[k] = v end
	return o
end
local function pick(list) return list[rng:NextInteger(1, #list)] end

local function fxAll(kind, d) FXR:FireAllClients(kind, d) end
local function fxTo(plr, kind, d)
	if plr and plr.Parent then FXR:FireClient(plr, kind, d) end
end
local function notify(plr, kind, d)
	if plr and plr.Parent then Notify:FireClient(plr, kind, d) end
end
local function toast(plr, text, color, gate)
	local st = PS[plr]
	if gate and st then
		if st.toastGate[gate] and clock - st.toastGate[gate] < 1.6 then return end
		st.toastGate[gate] = clock
	end
	notify(plr, "toast", { text = text, color = color or T.blood })
end
local function banner(plr, main, sub, color)
	notify(plr, "banner", { main = main, sub = sub, color = color or T.bone })
end
local function markDirty(plr) dirty[plr] = true end

local function charOf(plr)
	local c = plr and plr.Character
	if not c then return nil end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then return c, hrp, hum end
	return nil
end

local function aimDir(hrp, aim)
	local d = Vector3.new(0, 0, 0)
	if validVec(aim) then d = flat(aim - hrp.Position) end
	if d.Magnitude < 0.05 then d = flat(hrp.CFrame.LookVector) end
	if d.Magnitude < 0.05 then d = Vector3.new(0, 0, -1) end
	return d.Unit
end
local function cursorPoint(hrp, aim, range)
	local p = flat(hrp.Position)
	local dir = aimDir(hrp, aim)
	local dist = range
	if validVec(aim) then dist = math.min(d2(aim, p), range) end
	return p + dir * dist
end
local function inVillage(pos, pad) return pos.Magnitude < WR.villageR + (pad or 0) end
local function moveCharTo(c, hrp, pos)
	local rot = hrp.CFrame - hrp.CFrame.Position
	c:PivotTo(CFrame.new(pos.X, hrp.Position.Y, pos.Z) * rot)
end

-- ---------- player runtime ----------
local function newRuntime(old)
	return {
		mal = 0, cd = {}, meleeAt = 0, combo = 0, lastSwing = -9, dashAt = 0, dashUntil = 0,
		iframeUntil = 0, stunUntil = 0, blocking = false, charging = false, shield = 0, shieldUntil = 0,
		awaken = false, awakenUntil = 0, awakenCdUntil = 0, lastHurt = -99, idle = 0, runAcc = 0,
		lastPos = nil, skillDash = nil, gate = nil, toastGate = old and old.toastGate or {}, spinAt = 0,
	}
end

local function dmgMult(plr)
	local st, prof = PS[plr], profiles[plr]
	local m = st.awaken and 1.4 or 1
	if prof.sin == "wrath" then
		local _, _, hum = charOf(plr)
		if hum then m = m * (1 + 0.6 * (1 - hum.Health / hum.MaxHealth)) end
	end
	return m
end

local function refreshHealth(plr, full)
	local _, _, hum = charOf(plr)
	local prof = profiles[plr]
	if not hum or not prof then return end
	local m = C.maxHp(prof)
	hum.MaxHealth = m
	if full or hum.Health > m then hum.Health = m end
end

local function train(plr, s, amt)
	local prof = profiles[plr]
	if not prof then return end
	prof.train[s] = prof.train[s] + amt
	local need = C.trainNeed(prof, s)
	local gained = false
	while prof.train[s] >= need do
		prof.train[s] = prof.train[s] - need
		prof.stats[s] = prof.stats[s] + 1
		toast(plr, "+1 " .. C.STAT_INFO[s].name .. " from training", T.bone)
		need = C.trainNeed(prof, s)
		gained = true
	end
	if gained then refreshHealth(plr, false) end
	markDirty(plr)
end

local function gainXP(plr, x)
	local prof, st = profiles[plr], PS[plr]
	if not prof or prof.level >= C.LEVEL_CAP then return end
	prof.xp = prof.xp + x
	while prof.level < C.LEVEL_CAP and prof.xp >= C.xpNeed(prof.level) do
		prof.xp = prof.xp - C.xpNeed(prof.level)
		local oldRank = C.rankName(prof.level)
		prof.level = prof.level + 1
		prof.points = prof.points + 3
		refreshHealth(plr, true)
		st.mal = C.maxMal(prof)
		local _, hrp = charOf(plr)
		if hrp then
			fxAll("ring", { pos = flat(hrp.Position), r0 = 1, r1 = 20, color = T.ember, dur = 0.7 })
			fxAll("burst", { pos = hrp.Position, color = T.ember, n = 40, speed = 30 })
		end
		local unlocked = {}
		for _, sk in ipairs(C.currentSkills(prof)) do
			if sk.u == prof.level then unlocked[#unlocked + 1] = sk.name end
		end
		local sub = "+3 stat points · press K"
		if #unlocked > 0 then sub = "Unlocked " .. table.concat(unlocked, ", ") .. " · +3 stat points" end
		if prof.level == 12 then sub = "Sin Awakening unlocked · press G" end
		banner(plr, "Level " .. prof.level, sub, T.ember)
		if C.rankName(prof.level) ~= oldRank then
			prof.spins = prof.spins + 2
			task.delay(2.7, function() banner(plr, C.rankName(prof.level), "New rank · +2 spins", C.RARITY.mythic.color) end)
		end
	end
	if prof.level >= C.LEVEL_CAP then prof.xp = 0 end
	markDirty(plr)
end

-- ---------- missions ----------
local function genMissions(prof)
	local L = prof.level
	local list = {}
	local types = { "slay", "hunt", "elite", "shards" }
	for i = 1, 3 do
		local ri = clamp(math.floor(L / 8) + rng:NextInteger(-1, 1), 0, 4)
		local typ = (i == 1) and "slay" or pick(types)
		local m = { id = tostring(rng:NextInteger(100000, 999999)), rank = ri + 1, type = typ, prog = 0 }
		if typ == "slay" then
			m.n = 8 + ri * 3
			m.text = "Slay " .. m.n .. " denizens of the Pit"
		elseif typ == "hunt" then
			local ok = {}
			for _, k in ipairs(C.ETYPE_ORDER) do
				if C.ETYPES[k].minL <= math.max(L, 2) then ok[#ok + 1] = k end
			end
			m.etype = pick(ok)
			m.n = 5 + ri * 2
			m.text = "Hunt " .. m.n .. " " .. C.ETYPES[m.etype].name .. "s"
		elseif typ == "elite" then
			m.n = 1
			m.text = "Destroy a named elite"
		else
			m.n = 4 + ri
			m.text = "Gather " .. m.n .. " soul shards from the fallen"
		end
		m.xp = math.floor(C.xpNeed(L) * (0.25 + ri * 0.08))
		m.souls = math.floor((40 + L * 12) * (1 + ri * 0.4))
		m.spin = (ri >= 3 or rng:NextNumber() < 0.25) and 1 or 0
		list[#list + 1] = m
	end
	return list
end

local function progMission(plr, n)
	local prof = profiles[plr]
	if not prof or not prof.mission then return end
	local m = prof.mission
	m.prog = math.min(m.n, m.prog + n)
	if m.prog >= m.n then
		prof.mission = nil
		prof.souls = prof.souls + m.souls
		prof.spins = prof.spins + m.spin
		toast(plr, "Mission complete: +" .. m.xp .. " XP, +" .. m.souls .. " souls" .. (m.spin > 0 and ", +1 spin" or ""), C.RANK_COLORS[m.rank])
		gainXP(plr, m.xp)
		prof.board = genMissions(prof)
		task.spawn(Data.save, plr.UserId, prof)
	end
	markDirty(plr)
end

-- ---------- enemy models ----------
local function ePart(props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.Anchored = true
	return World.part(props)
end

local function newStatus() return { slow = 0, stun = 0, root = 0, charm = 0, sleep = 0, burn = 0 } end

local function buildEnemyModel(e)
	local m = Instance.new("Model")
	local et = C.ETYPES[e.type]
	m.Name = e.boss and "Boss" or (e.elite and "Elite" or et.name)
	local r = e.r
	local base = CFrame.new(e.pos.X, e.y, e.pos.Z)
	local body
	local col = e.boss and C.rgb(30, 18, 22) or et.color
	if e.boss then
		local bc = C.SINS[C.BOSSES[e.bi].sin].color
		body = ePart({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = base, Color = col, Material = Enum.Material.Slate, Parent = m })
		for i = -3, 3 do
			local a = i * 0.32
			ePart({ Name = "Crown", Size = Vector3.new(0.6, r * 0.8, 0.6), CFrame = base * CFrame.Angles(0, 0, a) * CFrame.new(0, r * 1.05, 0), Color = bc, Material = Enum.Material.Neon, Parent = m })
		end
		local ringM = Instance.new("Model")
		ringM.Name = "Halo"
		World.heptagram(ringM, Vector3.new(e.pos.X, 0.4, e.pos.Z), r * 1.6, bc, 0, 0.35, "Sigil")
		for _, b in ipairs(ringM:GetDescendants()) do
			if b:IsA("BasePart") then b.Parent = m end
		end
		ringM:Destroy()
		local l = Instance.new("PointLight")
		l.Color = bc
		l.Range = 30
		l.Brightness = 3
		l.Parent = body
	elseif e.type == "imp" then
		body = ePart({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = base, Color = col, Material = Enum.Material.SmoothPlastic, Parent = m })
		for _, sx in ipairs({ -1, 1 }) do
			ePart({ Name = "Horn", Size = Vector3.new(0.35, r * 0.9, 0.35), CFrame = base * CFrame.new(sx * r * 0.5, r * 0.85, 0) * CFrame.Angles(0, 0, -sx * 0.4), Color = C.rgb(42, 10, 12), Material = Enum.Material.SmoothPlastic, Parent = m })
		end
	elseif e.type == "hound" then
		body = ePart({ Name = "Body", Size = Vector3.new(r * 1.3, r * 1.1, r * 2.6), CFrame = base, Color = col, Material = Enum.Material.SmoothPlastic, Parent = m })
		ePart({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 1.2, r * 1.2, r * 1.2), CFrame = base * CFrame.new(0, r * 0.3, -r * 1.4), Color = col, Material = Enum.Material.SmoothPlastic, Parent = m })
	elseif e.type == "wisp" then
		body = ePart({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = base, Color = col, Material = Enum.Material.Neon, Transparency = 0.15, Parent = m })
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 8
		l.Brightness = 1.5
		l.Parent = body
	else
		body = ePart({ Name = "Body", Size = Vector3.new(r * 2, r * 1.8, r * 2), CFrame = base, Color = col, Material = Enum.Material.Slate, Parent = m })
		for i = 0, 5 do
			local a = i / 6 * TAU
			ePart({ Name = "Spike", Size = Vector3.new(0.6, 0.6, 1.4), CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, r * 0.4, -r * 1.05), Color = T.danger, Material = Enum.Material.Neon, Parent = m })
		end
	end
	if e.type ~= "wisp" or e.boss then
		local er = e.boss and r * 0.14 or math.max(0.25, r * 0.16)
		for _, sx in ipairs({ -1, 1 }) do
			ePart({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(er * 2, er * 2, er * 2), CFrame = base * CFrame.new(sx * r * 0.35, r * 0.25, -r * (e.type == "hound" and 1.9 or 0.92)), Color = e.boss and C.SINS[C.BOSSES[e.bi].sin].color or C.rgb(255, 211, 107), Material = Enum.Material.Neon, Parent = m })
		end
	end
	if e.elite then
		local ring = World.disc(m, Vector3.new(e.pos.X, 0.12, e.pos.Z), r + 1.2, 0.1, T.ember, Enum.Material.Neon, "EliteRing")
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Transparency = 0.3
	end
	m.PrimaryPart = body

	local bb = Instance.new("BillboardGui")
	bb.Name = "HP"
	bb.Size = UDim2.fromOffset(e.boss and 0 or 110, 30)
	bb.StudsOffset = Vector3.new(0, r + 1.8, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 14)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextStrokeTransparency = 0.4
	name.TextColor3 = e.elite and T.ember or T.ash
	name.Text = e.elite and (e.name .. " · " .. e.lvl) or ("Lv " .. e.lvl)
	name.Parent = bb
	local barBg = Instance.new("Frame")
	barBg.Name = "Bar"
	barBg.Position = UDim2.new(0.1, 0, 0, 16)
	barBg.Size = UDim2.new(0.8, 0, 0, 5)
	barBg.BackgroundColor3 = Color3.new(0, 0, 0)
	barBg.BackgroundTransparency = 0.3
	barBg.BorderSizePixel = 0
	barBg.Visible = e.elite == true
	barBg.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = e.elite and T.ember or T.hp
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	local stl = Instance.new("TextLabel")
	stl.Name = "Status"
	stl.BackgroundTransparency = 1
	stl.Position = UDim2.new(0, 0, 0, 22)
	stl.Size = UDim2.new(1, 0, 0, 10)
	stl.Font = Enum.Font.GothamBold
	stl.TextSize = 10
	stl.TextStrokeTransparency = 0.4
	stl.TextColor3 = C.rgb(207, 216, 255)
	stl.Text = ""
	stl.Parent = bb
	bb.Parent = body

	m.Parent = W.enemies
	e.model, e.body, e.baseColor, e.fill, e.barBg, e.stLabel = m, body, col, fill, barBg, stl
end

local function setBodyColor(e)
	if not e.body or not e.body.Parent then return end
	if e.flashUntil and clock < e.flashUntil then
		e.body.Color = WHITE
	elseif e.wind and e.wind > 0 then
		e.body.Color = T.danger
	elseif e.st.charm > clock then
		e.body.Color = C.rgb(255, 140, 196)
	elseif e.st.stun > clock then
		e.body.Color = C.rgb(207, 216, 255)
	else
		e.body.Color = e.baseColor
	end
end

local function updateEnemyGui(e)
	if e.fill then
		e.fill.Size = UDim2.fromScale(math.max(0, e.hp / e.maxHp), 1)
		e.barBg.Visible = e.hp < e.maxHp or e.elite == true
	end
end

local function statusText(e)
	local s = {}
	if e.st.sleep > clock then s[#s + 1] = "zZ" end
	if e.st.stun > clock then s[#s + 1] = "STUN" end
	if e.st.root > clock then s[#s + 1] = "ROOT" end
	if e.st.charm > clock then s[#s + 1] = "CHARM" end
	if e.st.slow > clock then s[#s + 1] = "SLOW" end
	if e.st.burn > clock then s[#s + 1] = "BURN" end
	return table.concat(s, " ")
end

local function makeEnemy(typ, lvl, pos, extra)
	local et = C.ETYPES[typ]
	local elite = extra and extra.elite
	local hp = C.enemyHP(lvl) * et.hp * (elite and 4 or 1)
	local e = {
		type = typ, lvl = lvl, pos = flat(pos), r = et.r * (elite and 1.35 or 1), hp = hp, maxHp = hp,
		dmg = C.enemyDMG(lvl) * et.dmg * (elite and 1.5 or 1), speed = et.speed * (elite and 1.1 or 1),
		st = newStatus(), burnDps = 0, burnTick = 0, kv = Vector3.new(0, 0, 0), atkCd = rng:NextNumber(0.4, 1.2),
		wind = 0, special = rng:NextNumber(1, 3), face = Vector3.new(0, 0, -1), aggro = false,
		wander = rng:NextNumber(0, TAU), hitT = -9, phase = rng:NextNumber(0, TAU),
	}
	if extra then
		for k, v in pairs(extra) do e[k] = v end
	end
	e.y = (typ == "wisp") and (e.r + 2.5) or e.r
	buildEnemyModel(e)
	enemies[#enemies + 1] = e
	return e
end

local function removeEnemy(e)
	e.dead = true
	if e.model then e.model:Destroy() end
	e.model = nil
end

-- ---------- combat core ----------
local bossDefeated
local function killEnemy(e, plr)
	if e.dead then return end
	if e.boss then
		bossDefeated(e)
		return
	end
	e.dead = true
	local col = C.ETYPES[e.type].color
	fxAll("burst", { pos = Vector3.new(e.pos.X, e.y, e.pos.Z), color = col, n = 24, speed = 26 })
	if e.model then e.model:Destroy() end
	if e.elite and e.owner and profiles[e.owner] then
		local op = profiles[e.owner]
		if op.mission and op.mission.type == "elite" then progMission(e.owner, 1) end
	end
	local prof = plr and profiles[plr]
	if not prof then return end
	local et = C.ETYPES[e.type]
	local xp = math.floor((6 + e.lvl * 5) * et.xp * (e.elite and 5 or 1) * (e.minion and 0.3 or 1))
	local souls = math.floor((2 + e.lvl * 1.5) * rng:NextNumber(0.7, 1.3) * (e.elite and 5 or 1) * (e.minion and 0.3 or 1))
	if prof.sin == "greed" then souls = math.floor(souls * 1.6) end
	prof.souls = prof.souls + souls
	prof.kills = prof.kills + 1
	fxTo(plr, "text", { pos = Vector3.new(e.pos.X, e.y + e.r + 2.5, e.pos.Z), str = "+" .. souls .. " souls", color = T.soul })
	gainXP(plr, xp)
	local m = prof.mission
	if m and not e.minion then
		if m.type == "slay" then
			progMission(plr, 1)
		elseif m.type == "hunt" and e.type == m.etype then
			progMission(plr, 1)
		elseif m.type == "shards" and rng:NextNumber() < 0.45 then
			fxTo(plr, "text", { pos = Vector3.new(e.pos.X, e.y + e.r + 4, e.pos.Z), str = "Soul shard", color = T.ember })
			progMission(plr, 1)
		end
	end
	markDirty(plr)
end

local function applyStatus(e, st, prof)
	if not st then return end
	local typ, dur = st[1], st[2]
	if typ == "burn" then
		e.st.burn = math.max(e.st.burn, clock + dur)
		if prof then e.burnDps = math.max(e.burnDps, C.skillPow(prof) * 0.45) end
	else
		local dd = dur * (e.boss and 0.3 or 1)
		e.st[typ] = math.max(e.st[typ] or 0, clock + dd)
	end
end

local function healPlayer(plr, amt, show)
	local _, hrp, hum = charOf(plr)
	if not hum then return end
	local before = hum.Health
	hum.Health = math.min(hum.MaxHealth, hum.Health + amt)
	if show and hum.Health - before >= 1 then
		fxTo(plr, "text", { pos = hrp.Position + Vector3.new(0, 3.5, 0), str = "+" .. math.floor(hum.Health - before), color = C.RARITY.uncommon.color })
	end
end

local function damageEnemy(e, base, o, plr)
	if e.dead then return end
	local prof = plr and profiles[plr]
	local d = base
	if prof and prof.sin == "envy" then
		local _, _, hum = charOf(plr)
		if hum and e.hp / e.maxHp > hum.Health / hum.MaxHealth then d = d * 1.25 end
	end
	if o.vsCharm and e.st.charm > clock then d = d * o.vsCharm end
	local crit = rng:NextNumber() < 0.1
	if crit then d = d * 1.5 end
	if o.exec then
		if not e.boss and e.hp / e.maxHp <= o.exec then
			d = e.hp + 1
			fxAll("burst", { pos = Vector3.new(e.pos.X, e.y, e.pos.Z), color = C.SINS.greed.color, n = 20, speed = 20 })
		elseif e.boss then
			d = d * 1.6
		end
	end
	d = math.max(1, math.floor(d + 0.5))
	e.hp = e.hp - d
	e.hitT = clock
	e.aggro = true
	if plr then e.lastHitBy = plr end
	e.flashUntil = clock + 0.08
	if e.st.sleep > clock and not (o.status and o.status[1] == "sleep") then e.st.sleep = 0 end
	if o.status then applyStatus(e, o.status, prof) end
	if o.charmChance and rng:NextNumber() < o.charmChance then applyStatus(e, { "charm", 2 }, prof) end
	if (o.knock or o.pull) and not e.boss then
		local from = o.from
		if not from and plr then
			local _, hrp = charOf(plr)
			if hrp then from = flat(hrp.Position) end
		end
		if from then
			local dir = flat(e.pos - from)
			if dir.Magnitude > 0.01 then
				dir = dir.Unit
				if o.knock then e.kv = e.kv + dir * o.knock * (e.type == "brute" and 0.45 or 1) end
				if o.pull then e.kv = e.kv - dir * o.pull end
			end
		end
	end
	if prof then
		local ls = (o.lifesteal or 0) + (prof.sin == "gluttony" and 0.1 or 0)
		if ls > 0 then healPlayer(plr, d * ls, false) end
		if o.soulsOnHit then
			prof.souls = prof.souls + o.soulsOnHit
			markDirty(plr)
		end
		fxTo(plr, "text", { pos = Vector3.new(e.pos.X, e.y + e.r + 1, e.pos.Z), str = tostring(d), color = crit and GOLD or (o.color or WHITE), big = crit })
	end
	fxAll("burst", { pos = Vector3.new(e.pos.X, e.y, e.pos.Z), color = o.color or WHITE, n = crit and 10 or 5, speed = 14 })
	setBodyColor(e)
	updateEnemyGui(e)
	if e.hp <= 0 then killEnemy(e, plr) end
end

local function aoe(center, r, dmg, o, plr)
	local oo = copy(o)
	oo.from = center
	for _, e in ipairs(enemies) do
		if not e.dead and d2(center, e.pos) < r + e.r then damageEnemy(e, dmg, oo, plr) end
	end
end
local function lineHits(origin, dir, len, w, cb)
	for _, e in ipairs(enemies) do
		if not e.dead then
			local rel = flat(e.pos - origin)
			local t = rel:Dot(dir)
			if t > -e.r and t < len + e.r then
				local perp = math.abs(rel.X * dir.Z - rel.Z * dir.X)
				if perp < w / 2 + e.r then cb(e) end
			end
		end
	end
end
local function coneHits(origin, dir, range, half, cb)
	local a0 = angleOf(dir)
	for _, e in ipairs(enemies) do
		if not e.dead then
			local d = d2(origin, e.pos)
			if d < range + e.r then
				local da = angleOf(flat(e.pos - origin)) - a0
				da = math.atan2(math.sin(da), math.cos(da))
				if math.abs(da) < half + math.atan2(e.r, math.max(d, 0.1)) then cb(e) end
			end
		end
	end
end

local onDied
local function hurtPlayer(plr, d)
	local c, hrp, hum = charOf(plr)
	local st, prof = PS[plr], profiles[plr]
	if not c or not st or not prof then return end
	if clock < st.iframeUntil or st.skillDash then return end
	local sd = C.SINS[prof.sin]
	if sd.takenMult then d = d * sd.takenMult end
	if st.blocking then
		d = d * 0.25
		st.mal = st.mal - 5
		fxAll("burst", { pos = hrp.Position + hrp.CFrame.LookVector * 2, color = C.rgb(255, 233, 168), n = 8, speed = 18 })
		if st.mal <= 0 then
			st.mal = 0
			st.stunUntil = clock + 0.9
			st.blocking = false
			fxTo(plr, "text", { pos = hrp.Position + Vector3.new(0, 4, 0), str = "GUARD BROKEN", color = C.rgb(255, 106, 106), big = true })
		end
	end
	if st.shield > 0 then
		local ab = math.min(st.shield, d)
		st.shield = st.shield - ab
		d = d - ab
		if d <= 0 then
			fxTo(plr, "text", { pos = hrp.Position + Vector3.new(0, 3.5, 0), str = "absorbed", color = C.SINS.greed.color })
			return
		end
	end
	d = math.max(1, math.floor(d + 0.5))
	hum.Health = hum.Health - d
	st.lastHurt = clock
	st.iframeUntil = clock + 0.1
	train(plr, "vit", d / 7)
	fxTo(plr, "text", { pos = hrp.Position + Vector3.new(0, 3.5, 0), str = "-" .. d, color = C.rgb(255, 93, 108) })
	notify(plr, "shake", { a = math.min(1, 0.15 + d / hum.MaxHealth * 3) })
end

-- ---------- projectiles & fields ----------
local function projPart(pos, r, color)
	return ePart({ Name = "Proj", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 2, r * 2, r * 2), CFrame = CFrame.new(pos), Color = color, Material = Enum.Material.Neon, CastShadow = false, Parent = W.fx })
end
local function enemyShot(pos, vel, r, dmg, color)
	local p = Vector3.new(pos.X, 3, pos.Z)
	eproj[#eproj + 1] = { pos = p, vel = vel, r = r, dmg = dmg, life = 2.6, part = projPart(p, r, color) }
end

local function explodeProj(p)
	if p.exploded then return end
	p.exploded = true
	aoe(flat(p.pos), p.explode, p.dmg * 0.6, p.o, p.owner)
	fxAll("disc", { pos = flat(p.pos), r = p.explode, color = p.color, dur = 0.25 })
	fxAll("burst", { pos = p.pos, color = p.color, n = 24, speed = 30 })
end

local function updateProjectiles(dt)
	local keep = {}
	for _, p in ipairs(pproj) do
		if p.homing then
			local best, bd = nil, 50
			for _, e in ipairs(enemies) do
				if not e.dead and not p.hit[e] then
					local d = d2(p.pos, e.pos)
					if d < bd then best, bd = e, d end
				end
			end
			if best then
				local ta = angleOf(flat(best.pos - p.pos))
				local ca = angleOf(p.vel)
				local da = math.atan2(math.sin(ta - ca), math.cos(ta - ca))
				local na = ca + clamp(da, -7 * dt, 7 * dt)
				p.vel = dirFromAngle(na) * p.vel.Magnitude
			end
		end
		p.pos = p.pos + p.vel * dt
		p.life = p.life - dt
		for _, e in ipairs(enemies) do
			if p.life > 0 and not e.dead and not p.hit[e] and d2(p.pos, e.pos) < p.r + e.r then
				p.hit[e] = true
				local o = copy(p.o)
				o.from = flat(p.pos - p.vel * 0.05)
				damageEnemy(e, p.dmg, o, p.owner)
				if p.explode then explodeProj(p) end
				p.pierce = p.pierce - 1
				if p.pierce < 0 then p.life = 0 end
			end
		end
		if p.life <= 0 then
			if p.explode then explodeProj(p) end
			p.part:Destroy()
		else
			p.part.CFrame = CFrame.new(p.pos)
			keep[#keep + 1] = p
		end
	end
	pproj = keep

	keep = {}
	for _, p in ipairs(eproj) do
		p.pos = p.pos + p.vel * dt
		p.life = p.life - dt
		for _, plr in ipairs(Players:GetPlayers()) do
			local c, hrp = charOf(plr)
			if c and p.life > 0 and d2(p.pos, hrp.Position) < p.r + WR.playerR then
				hurtPlayer(plr, p.dmg)
				p.life = 0
				fxAll("burst", { pos = p.pos, color = p.part.Color, n = 6, speed = 12 })
			end
		end
		if inVillage(p.pos) then p.life = 0 end
		if p.life > 0 then
			for _, k in ipairs(W.rocks) do
				if math.abs(p.pos.X - k.x) < k.r and math.abs(p.pos.Z - k.z) < k.r then
					local dx, dz = p.pos.X - k.x, p.pos.Z - k.z
					if math.sqrt(dx * dx + dz * dz) < k.r * 0.9 then p.life = 0 break end
				end
			end
		end
		if p.life <= 0 then
			p.part:Destroy()
		else
			p.part.CFrame = CFrame.new(p.pos)
			keep[#keep + 1] = p
		end
	end
	eproj = keep
end

local function updateFields(dt)
	local keep = {}
	for _, f in ipairs(fields) do
		f.tick = f.tick - dt
		for _, e in ipairs(enemies) do
			if not e.dead then
				local d = d2(e.pos, f.pos)
				if d < f.r + e.r then
					if f.pull > 0 and not e.boss and d > 1 then
						e.pos = e.pos + flat(f.pos - e.pos).Unit * f.pull * dt
					end
					if f.o.status then applyStatus(e, f.o.status, profiles[f.owner]) end
				end
			end
		end
		if f.tick <= 0 then
			f.tick = 0.25
			for _, e in ipairs(enemies) do
				if not e.dead and d2(e.pos, f.pos) < f.r + e.r then damageEnemy(e, f.dps * 0.25, { color = f.color }, f.owner) end
			end
		end
		if clock < f.untilT then keep[#keep + 1] = f end
	end
	fields = keep
end

-- ---------- skills ----------
local function castSkill(plr, sk, m, aim)
	local c, hrp = charOf(plr)
	if not c then return end
	local prof, st = profiles[plr], PS[plr]
	local color = sk.color
	local pow = C.skillPow(prof) * (sk.dmg or 1) * (1 + 0.12 * (m - 1)) * dmgMult(plr)
	local origin = flat(hrp.Position)
	local dir = aimDir(hrp, aim)
	local o = { status = sk.status, knock = sk.knock, lifesteal = sk.lifesteal, exec = sk.exec, vsCharm = sk.vsCharm, color = color, soulsOnHit = sk.soulsOnHit }

	if sk.kind == "proj" then
		local n = sk.count or 1
		local a0 = angleOf(dir)
		for i = 1, n do
			local a = a0
			if n > 1 then a = a0 + ((i - 1) / (n - 1) - 0.5) * (sk.spread or 0) end
			local dv = dirFromAngle(a)
			local pos = origin + dv * 2 + Vector3.new(0, 3, 0)
			pproj[#pproj + 1] = { pos = pos, vel = dv * sk.speed, r = sk.r, dmg = pow, life = sk.life, pierce = sk.pierce or 0, homing = sk.homing, explode = sk.explode, o = o, color = color, hit = {}, owner = plr, part = projPart(pos, sk.r, color) }
		end
	elseif sk.kind == "nova" then
		local at = origin
		if sk.at == "cursor" then at = cursorPoint(hrp, aim, WR.cursorRange) end
		local function fire()
			local center = at
			if sk.at == "self" then
				local _, h2 = charOf(plr)
				if not h2 then return end
				center = flat(h2.Position)
			end
			local oo = copy(o)
			oo.pull = sk.pull
			aoe(center, sk.rad, pow, oo, plr)
			if sk.heal then
				local _, _, hum = charOf(plr)
				if hum then healPlayer(plr, hum.MaxHealth * sk.heal, true) end
			end
			fxAll("ring", { pos = center, r0 = sk.rad * 0.2, r1 = sk.rad, color = color, dur = 0.4 })
			fxAll("disc", { pos = center, r = sk.rad, color = color, dur = 0.25 })
			fxAll("burst", { pos = center + Vector3.new(0, 1, 0), color = color, n = math.min(60, 16 + sk.rad), speed = sk.rad * 1.4 })
		end
		if sk.delay then
			fxAll("tele", { pos = at, r = sk.rad, dur = sk.delay, color = color, follow = (sk.at == "self") and hrp or nil })
			task.delay(sk.delay, fire)
		else
			fire()
		end
	elseif sk.kind == "cone" then
		coneHits(origin, dir, sk.range, sk.half, function(e) damageEnemy(e, pow, o, plr) end)
		fxAll("cone", { pos = origin, dir = dir, range = sk.range, half = sk.half, color = color, dur = 0.3 })
	elseif sk.kind == "beam" then
		local function fire()
			lineHits(origin, dir, sk.len, sk.width, function(e)
				local oo = copy(o)
				oo.from = origin
				damageEnemy(e, pow, oo, plr)
			end)
			fxAll("beam", { pos = origin, dir = dir, len = sk.len, w = sk.width, color = color, dur = 0.25 })
		end
		if sk.delay and sk.delay > 0 then
			fxAll("teleLine", { pos = origin, dir = dir, len = sk.len, w = sk.width, color = color, dur = sk.delay })
			task.delay(sk.delay, fire)
		else
			fire()
		end
	elseif sk.kind == "rain" then
		local cpt = cursorPoint(hrp, aim, WR.cursorRange)
		for i = 1, sk.n do
			task.delay((i - 1) * sk.interval, function()
				local rr = math.sqrt(rng:NextNumber()) * sk.area
				local aa = rng:NextNumber() * TAU
				local p = cpt + Vector3.new(math.cos(aa) * rr, 0, math.sin(aa) * rr)
				fxAll("tele", { pos = p, r = sk.rad, dur = 0.35, color = color })
				task.delay(0.35, function()
					aoe(p, sk.rad, pow, o, plr)
					fxAll("pillar", { pos = p, r = sk.rad, color = color, dur = 0.35 })
					fxAll("burst", { pos = p + Vector3.new(0, 1, 0), color = color, n = 16, speed = 26 })
				end)
			end)
		end
	elseif sk.kind == "dash" then
		local dur = sk.dist / 90
		st.skillDash = { untilT = clock + dur + 0.05, dmg = pow, o = o, hit = {}, w = sk.width, color = color }
		st.iframeUntil = math.max(st.iframeUntil, clock + dur + 0.15)
		notify(plr, "forceDash", { dir = dir, speed = 90, dur = dur })
		fxAll("burst", { pos = hrp.Position, color = color, n = 20, speed = 20 })
	elseif sk.kind == "blink" then
		local tpos = cursorPoint(hrp, aim, sk.range)
		for _, k in ipairs(W.rocks) do
			local rel = flat(tpos - Vector3.new(k.x, 0, k.z))
			if rel.Magnitude < k.r + 2 then tpos = Vector3.new(k.x, 0, k.z) + (rel.Magnitude > 0.01 and rel.Unit or Vector3.new(1, 0, 0)) * (k.r + 2) end
		end
		fxAll("burst", { pos = hrp.Position, color = color, n = 24, speed = 22 })
		moveCharTo(c, hrp, tpos)
		aoe(tpos, sk.rad, pow, o, plr)
		fxAll("ring", { pos = tpos, r0 = 1, r1 = sk.rad, color = color, dur = 0.35 })
		fxAll("burst", { pos = tpos + Vector3.new(0, 2, 0), color = color, n = 30, speed = 30 })
	elseif sk.kind == "vortex" then
		local cpt = cursorPoint(hrp, aim, WR.cursorRange)
		fields[#fields + 1] = { pos = cpt, r = sk.rad, untilT = clock + sk.dur, pull = sk.pull or 0, dps = pow * sk.dps, tick = 0, o = o, color = color, owner = plr }
		fxAll("field", { pos = cpt, r = sk.rad, dur = sk.dur, color = color, pull = (sk.pull or 0) > 0 })
	elseif sk.kind == "shield" then
		local _, _, hum = charOf(plr)
		st.shield = hum.MaxHealth * sk.amount
		st.shieldUntil = clock + sk.dur
		fxAll("ring", { pos = origin, r0 = 7, r1 = 3, color = color, dur = 0.4 })
		fxAll("burst", { pos = hrp.Position, color = color, n = 30, speed = 18 })
	end
end

local function trySkill(plr, key, aim)
	local c = charOf(plr)
	local prof, st = profiles[plr], PS[plr]
	if not c or not prof or not prof.created or clock < st.stunUntil then return end
	local sk = C.findSkill(prof, key)
	if not sk then return end
	if prof.level < sk.u then
		toast(plr, sk.name .. " unlocks at level " .. sk.u, T.ash, "lk" .. key)
		return
	end
	if (st.cd[sk.id] or 0) > clock then return end
	if st.mal < sk.cost then
		toast(plr, "Not enough Malice. Hold C to charge.", T.mal, "mal")
		return
	end
	st.mal = st.mal - sk.cost
	local m = C.mastery(prof, sk.id)
	local cd = sk.cd * (1 - 0.04 * (m - 1)) * (st.awaken and 0.7 or 1)
	st.cd[sk.id] = clock + cd
	notify(plr, "cd", { id = sk.id, dur = cd })
	prof.mastery[sk.id] = (prof.mastery[sk.id] or 0) + 1
	local after = C.mastery(prof, sk.id)
	if after > m then toast(plr, sk.name .. " reached mastery " .. after, sk.color) end
	markDirty(plr)
	castSkill(plr, sk, m, aim)
end

local function doMelee(plr, aim)
	local c, hrp = charOf(plr)
	local prof, st = profiles[plr], PS[plr]
	if not c or not prof or not prof.created then return end
	if clock < st.meleeAt or st.charging or st.blocking or clock < st.stunUntil or st.skillDash then return end
	local since = clock - st.lastSwing
	if since < 0.65 then st.combo = (st.combo + 1) % 3 else st.combo = 0 end
	st.lastSwing = clock
	local dir = aimDir(hrp, aim)
	local mult = ({ 1, 1.1, 1.7 })[st.combo + 1]
	local dmg = C.meleePow(prof) * mult * dmgMult(plr)
	local origin = flat(hrp.Position)
	local hit = 0
	local o = { knock = (st.combo == 2) and 34 or 7, charmChance = (prof.sin == "lust") and 0.15 or nil, color = C.rgb(255, 226, 196) }
	coneHits(origin, dir, WR.meleeRange, WR.meleeHalf, function(e)
		damageEnemy(e, dmg, o, plr)
		hit = hit + 1
	end)
	local a0 = angleOf(dir)
	for _, dm in ipairs(W.dummies) do
		if d2(origin, dm.pos) < WR.meleeRange + 1.5 then
			local da = angleOf(flat(dm.pos - origin)) - a0
			da = math.atan2(math.sin(da), math.cos(da))
			if math.abs(da) < WR.meleeHalf + 0.4 then
				hit = hit + 1
				fxTo(plr, "text", { pos = dm.pos + Vector3.new(0, 6.5, 0), str = tostring(math.floor(dmg + 0.5)), color = C.rgb(204, 204, 204) })
				fxAll("burst", { pos = dm.pos + Vector3.new(0, 4.3, 0), color = C.rgb(216, 199, 154), n = 6, speed = 10 })
			end
		end
	end
	if hit > 0 then train(plr, "str", math.min(3, hit)) end
	fxAll("slash", { pos = hrp.Position, dir = dir, r = WR.meleeRange * 0.75, color = (st.combo == 2) and C.SINS[prof.sin].color or T.bone, flip = st.combo % 2 == 1 })
	st.meleeAt = clock + ((st.combo == 2) and 0.46 or 0.26)
end

local function doDash(plr)
	local c, hrp = charOf(plr)
	local prof, st = profiles[plr], PS[plr]
	if not c or not prof then return end
	if clock < st.dashAt or clock < st.stunUntil or st.charging then return end
	st.dashAt = clock + 0.75
	st.dashUntil = clock + 0.22
	st.iframeUntil = math.max(st.iframeUntil, clock + 0.25)
	train(plr, "agi", 2)
	fxAll("burst", { pos = hrp.Position, color = T.bone, n = 8, speed = 12 })
end

local function toggleAwaken(plr)
	local c, hrp = charOf(plr)
	local prof, st = profiles[plr], PS[plr]
	if not c or not prof then return end
	if st.awaken then
		st.awaken = false
		st.awakenCdUntil = clock + 30
		return
	end
	if prof.level < 12 then return toast(plr, "Sin Awakening unlocks at level 12", T.ash, "awk") end
	if clock < st.awakenCdUntil then return toast(plr, "Awakening recovers in " .. math.ceil(st.awakenCdUntil - clock) .. "s", T.ash, "awk") end
	if st.mal < 40 then return toast(plr, "Need 40 Malice to awaken", T.mal, "awk") end
	st.awaken = true
	st.awakenUntil = clock + 20
	local col = C.SINS[prof.sin].color
	banner(plr, C.SINS[prof.sin].name .. " Awakened", "damage +40% · speed +25% · cooldowns -30%", col)
	fxAll("ring", { pos = flat(hrp.Position), r0 = 1, r1 = 30, color = col, dur = 0.6 })
	fxAll("burst", { pos = hrp.Position, color = col, n = 60, speed = 40 })
	fxAll("aura", { char = c, color = col, on = true })
end

-- ---------- spawning ----------
local function inArena(pos, pad)
	for i, g in ipairs(W.gates) do
		if d2(pos, g.pos) < WR.arenaR + (pad or 0) then return g end
	end
	return nil
end
local function spawnPoint(center, minD, maxD)
	for _ = 1, 12 do
		local a = rng:NextNumber() * TAU
		local d = rng:NextNumber(minD, maxD)
		local p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local ok = p.Magnitude < WR.R - 8 and not inVillage(p, 10) and not inArena(p, 6)
		if ok then
			for _, k in ipairs(W.rocks) do
				local dx, dz = k.x - p.X, k.z - p.Z
				if math.sqrt(dx * dx + dz * dz) < k.r + 4 then ok = false break end
			end
		end
		if ok then return p end
	end
	return nil
end
local function enemyTypeFor(l)
	local avail, tot = {}, 0
	for _, k in ipairs(C.ETYPE_ORDER) do
		if C.ETYPES[k].minL <= l then
			avail[#avail + 1] = k
			tot = tot + C.ETYPES[k].w
		end
	end
	local r = rng:NextNumber() * tot
	for _, k in ipairs(avail) do
		r = r - C.ETYPES[k].w
		if r <= 0 then return k end
	end
	return "imp"
end

local ELITE_NAMES = { "Ashmaw", "Grieveclaw", "Hollowtooth", "Cinderjaw", "Mourngrin", "Soot Widow" }
local function spawner()
	local total = 0
	for _, e in ipairs(enemies) do
		if not e.dead and not e.boss and not e.minion then total = total + 1 end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local prof, st = profiles[plr], PS[plr]
		local c, hrp = charOf(plr)
		if c and prof and prof.created and not st.gate then
			local pos = flat(hrp.Position)
			local near = 0
			for _, e in ipairs(enemies) do
				if not e.dead and not e.boss and not e.minion and d2(e.pos, pos) < 120 then near = near + 1 end
			end
			local target = inVillage(pos, 25) and 8 or 16
			if near < target and total < 60 then
				local p = spawnPoint(pos, 75, 110)
				if p then
					local l = C.enemyLevelAt(p.X, p.Z)
					makeEnemy(enemyTypeFor(l), l, p)
					total = total + 1
				end
			end
			if prof.mission and prof.mission.type == "elite" then
				local has = false
				for _, e in ipairs(enemies) do
					if not e.dead and e.elite and e.owner == plr then has = true break end
				end
				if not has then
					local p = spawnPoint(pos, 85, 120)
					if p then
						local l = math.max(C.enemyLevelAt(p.X, p.Z), prof.level)
						local ok = {}
						for _, k in ipairs(C.ETYPE_ORDER) do
							if C.ETYPES[k].minL <= l then ok[#ok + 1] = k end
						end
						local el = makeEnemy(pick(ok), l, p, { elite = true, owner = plr, name = pick(ELITE_NAMES), aggro = true })
						toast(plr, el.name .. " has risen. Follow the gold marker.", T.ember)
						notify(plr, "elite", { model = el.model })
					end
				end
			end
		end
	end
end

-- ---------- bosses ----------
local function fightPlayers(gate)
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local st = PS[plr]
		if st and st.gate == gate and charOf(plr) then list[#list + 1] = plr end
	end
	return list
end
local function bossNotify(gate, payload)
	for _, plr in ipairs(Players:GetPlayers()) do
		local st = PS[plr]
		if st and st.gate == gate then notify(plr, "boss", payload) end
	end
end

local function spawnBoss(i)
	local B = C.BOSSES[i]
	local g = W.gates[i]
	local lvl = B.req + 2
	for _, e in ipairs(enemies) do
		if not e.dead and not e.boss and d2(e.pos, g.pos) < WR.arenaR + 10 then removeEnemy(e) end
	end
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local c, hrp = charOf(plr)
		local prof = profiles[plr]
		if c and prof and prof.created and prof.level >= B.req and d2(hrp.Position, g.pos) < WR.arenaR then
			PS[plr].gate = i
			n = n + 1
		end
	end
	local hp = C.enemyHP(lvl) * 10 * (1 + 0.6 * math.max(0, n - 1))
	local start = g.pos - g.pos.Unit * 14
	local e = {
		boss = true, bi = i, gate = i, type = "imp", name = B.name, lvl = lvl, pos = flat(start), r = B.r, y = B.r,
		hp = hp, maxHp = hp, dmg = C.enemyDMG(lvl) * 1.25, speed = B.speed, st = newStatus(), burnDps = 0, burnTick = 0,
		kv = Vector3.new(0, 0, 0), face = Vector3.new(0, 0, -1), hitT = -9, atkAt = clock + 1.6, busyUntil = 0, touchAt = 0, wind = 0,
	}
	buildEnemyModel(e)
	enemies[#enemies + 1] = e
	activeBoss[i] = e
	local col = C.SINS[B.sin].color
	for _, plr in ipairs(fightPlayers(i)) do
		banner(plr, B.name, "Hollow Prince of " .. C.SINS[B.sin].name .. " · level " .. lvl, col)
		notify(plr, "boss", { name = B.name, color = col, frac = 1, hp = hp, show = true })
		notify(plr, "shake", { a = 0.8 })
	end
end

local function despawnBoss(i)
	local e = activeBoss[i]
	activeBoss[i] = nil
	if e then removeEnemy(e) end
	for _, m in ipairs(enemies) do
		if m.minion and m.gate == i then removeEnemy(m) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local st = PS[plr]
		if st and st.gate == i then
			st.gate = nil
			st.mustLeave = i
			notify(plr, "boss", { show = false })
		end
	end
end

bossDefeated = function(e)
	if e.dead then return end
	local i = e.bi
	local B = C.BOSSES[i]
	local col = C.SINS[B.sin].color
	e.dead = true
	fxAll("burst", { pos = Vector3.new(e.pos.X, e.y, e.pos.Z), color = col, n = 120, speed = 50 })
	fxAll("ring", { pos = e.pos, r0 = 2, r1 = 50, color = col, dur = 1 })
	if e.model then e.model:Destroy() end
	activeBoss[i] = nil
	for _, m in ipairs(enemies) do
		if m.minion and m.gate == i then removeEnemy(m) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local st, prof = PS[plr], profiles[plr]
		if st and prof and st.gate == i then
			st.gate = nil
			st.mustLeave = i
			notify(plr, "boss", { show = false })
			notify(plr, "shake", { a = 1 })
			if not C.hasBoss(prof, i) then
				prof.bosses[#prof.bosses + 1] = i
				local souls = 400 * i
				prof.spins = prof.spins + 3
				prof.souls = prof.souls + souls
				banner(plr, "Seal Broken", B.name .. " falls · +3 spins · +" .. souls .. " souls", col)
				gainXP(plr, math.floor(C.xpNeed(prof.level) * 1.2))
				if #prof.bosses == 7 then task.delay(2.6, function() notify(plr, "victory", {}) end) end
			else
				local souls = 120 * i
				prof.souls = prof.souls + souls
				banner(plr, B.name .. " falls again", "+" .. souls .. " souls", col)
				gainXP(plr, math.floor(C.xpNeed(prof.level) * 0.4))
			end
			markDirty(plr)
			task.spawn(Data.save, plr.UserId, prof)
		end
	end
end

local function updateBoss(e, dt)
	local B = C.BOSSES[e.bi]
	local col = C.SINS[B.sin].color
	local players = fightPlayers(e.gate)
	if #players == 0 then
		despawnBoss(e.gate)
		return
	end
	local target, tpos, td = nil, nil, 1e9
	for _, plr in ipairs(players) do
		local _, hrp = charOf(plr)
		local d = d2(hrp.Position, e.pos)
		if d < td then target, tpos, td = plr, flat(hrp.Position), d end
	end
	local enr = e.hp < e.maxHp * 0.5
	local sp = enr and 1.35 or 1
	local function alive() return not e.dead and activeBoss[e.gate] == e end

	for _, plr in ipairs(players) do
		local _, hrp = charOf(plr)
		if d2(hrp.Position, e.pos) < e.r + WR.playerR and clock > e.touchAt then
			e.touchAt = clock + 0.7
			hurtPlayer(plr, e.dmg * 0.6)
		end
	end
	if e.st.stun > clock or e.st.sleep > clock then return end

	if e.charge then
		e.pos = e.pos + e.charge.vel * dt
		for _, plr in ipairs(players) do
			local _, hrp = charOf(plr)
			if not e.charge.hit[plr] and d2(hrp.Position, e.pos) < e.r + WR.playerR + 0.8 then
				e.charge.hit[plr] = true
				hurtPlayer(plr, e.dmg * 1.6)
			end
		end
		if clock > e.charge.untilT then e.charge = nil end
		return
	end
	if e.pullUntil and clock < e.pullUntil then return end
	if e.spinUntil and clock < e.spinUntil then
		e.spinAcc = (e.spinAcc or 0) + dt
		while e.spinAcc > 0.085 do
			e.spinAcc = e.spinAcc - 0.085
			e.spin = e.spin + 0.33
			local k = enr and 3 or 2
			for j = 0, k - 1 do
				local a = e.spin + j * TAU / k
				enemyShot(e.pos, dirFromAngle(a) * 28, 1, e.dmg * 0.6, col)
			end
		end
		return
	end
	if clock < e.busyUntil then return end

	local toT = flat(tpos - e.pos)
	if toT.Magnitude > 0.1 then e.face = toT.Unit end
	if td > 18 then
		local s = e.speed * sp * ((e.st.slow > clock) and 0.6 or 1) * ((e.st.root > clock) and 0 or 1)
		e.pos = e.pos + e.face * s * dt
	end
	if clock < e.atkAt then return end
	e.atkAt = clock + rng:NextNumber(0.9, 1.5) / sp
	local atk = pick(B.atks)

	if atk == "slam" then
		local n = enr and 3 or 1
		for k = 1, n do
			task.delay((k - 1) * 0.4, function()
				if not alive() then return end
				local x = tpos
				local tp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
				if tp then x = flat(tp.Position) end
				local delay = enr and 0.7 or 0.9
				fxAll("tele", { pos = x, r = 14, dur = delay, color = T.danger, enemy = true })
				task.delay(delay, function()
					if not alive() then return end
					for _, plr in ipairs(fightPlayers(e.gate)) do
						local _, hrp = charOf(plr)
						if hrp and d2(hrp.Position, x) < 14.5 then hurtPlayer(plr, e.dmg * 1.4) end
					end
					fxAll("disc", { pos = x, r = 14, color = col, dur = 0.25 })
					fxAll("burst", { pos = x + Vector3.new(0, 1, 0), color = col, n = 24, speed = 30 })
				end)
			end)
		end
		e.busyUntil = clock + 0.5 + n * 0.4
	elseif atk == "burst" then
		e.busyUntil = clock + 0.6
		fxAll("ring", { pos = e.pos, r0 = e.r + 5, r1 = e.r, color = T.danger, dur = 0.5 })
		local function fire(off)
			if not alive() then return end
			local n = enr and 22 or 16
			for k = 0, n - 1 do
				enemyShot(e.pos, dirFromAngle(off + k * TAU / n) * 31, 1.1, e.dmg * 0.8, col)
			end
		end
		task.delay(0.5, function() fire(0) end)
		if enr then task.delay(0.9, function() fire(TAU / 44) end) end
	elseif atk == "aimed" then
		e.busyUntil = clock + 1
		for v = 0, 2 do
			task.delay(0.3 + v * 0.25, function()
				if not alive() then return end
				local tp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
				local aimAt = tp and flat(tp.Position) or tpos
				local a0 = angleOf(flat(aimAt - e.pos))
				for k = 0, 4 do
					enemyShot(e.pos, dirFromAngle(a0 + (k / 4 - 0.5) * 0.6) * 47, 0.9, e.dmg * 0.7, col)
				end
			end)
		end
	elseif atk == "charge" then
		local delay = enr and 0.55 or 0.75
		local dir = e.face
		e.busyUntil = clock + delay + 0.1
		fxAll("teleLine", { pos = e.pos, dir = dir, len = 77, w = e.r * 2, color = T.danger, dur = delay, enemy = true })
		task.delay(delay, function()
			if not alive() then return end
			e.charge = { untilT = clock + 0.6, vel = dir * 120, hit = {} }
		end)
	elseif atk == "summon" then
		e.busyUntil = clock + 0.8
		local n = enr and 5 or 3
		for k = 0, n - 1 do
			local a = k * TAU / n
			local l = math.max(1, e.lvl - 4)
			local mt = (l > 6) and pick({ "imp", "hound" }) or "imp"
			local mn = makeEnemy(mt, l, e.pos + Vector3.new(math.cos(a) * 11, 0, math.sin(a) * 11), { minion = true, gate = e.gate, aggro = true })
			fxAll("burst", { pos = Vector3.new(mn.pos.X, mn.y, mn.pos.Z), color = col, n = 14, speed = 18 })
		end
	elseif atk == "pull" then
		e.pullUntil = clock + 1.6
		for _, plr in ipairs(players) do notify(plr, "pull", { target = e.pos, dur = 1.6, speed = 20 }) end
		fxAll("field", { pos = e.pos, r = 34, dur = 1.6, color = T.danger, pull = true })
		task.delay(1.6, function()
			if not alive() then return end
			fxAll("tele", { pos = e.pos, r = 20, dur = 0.35, color = T.danger, enemy = true })
			task.delay(0.35, function()
				if not alive() then return end
				for _, plr in ipairs(fightPlayers(e.gate)) do
					local _, hrp = charOf(plr)
					if hrp and d2(hrp.Position, e.pos) < 20 then hurtPlayer(plr, e.dmg * 1.5) end
				end
				fxAll("disc", { pos = e.pos, r = 20, color = col, dur = 0.25 })
			end)
			e.busyUntil = clock + 0.5
		end)
	elseif atk == "spiral" then
		e.spinUntil = clock + 2.4
		e.spin = rng:NextNumber() * TAU
		e.spinAcc = 0
	end
end

-- ---------- enemy AI ----------
local function nearestPlayer(pos)
	local best, bhrp, bd = nil, nil, 1e9
	for _, plr in ipairs(Players:GetPlayers()) do
		local c, hrp = charOf(plr)
		local prof = profiles[plr]
		if c and prof and prof.created then
			local d = d2(hrp.Position, pos)
			if d < bd then best, bhrp, bd = plr, hrp, d end
		end
	end
	return best, bhrp, bd
end

local function resolveRocks(e)
	for _, k in ipairs(W.rocks) do
		local dx, dz = e.pos.X - k.x, e.pos.Z - k.z
		if math.abs(dx) < k.r + e.r and math.abs(dz) < k.r + e.r then
			local d = math.sqrt(dx * dx + dz * dz)
			local m = k.r * 0.95 + e.r
			if d < m and d > 0.01 then e.pos = Vector3.new(k.x + dx / d * m, 0, k.z + dz / d * m) end
		end
	end
end

local function updateEnemies(dt)
	for _, e in ipairs(enemies) do
		if not e.dead then
			-- burn ticks
			if e.st.burn > clock then
				e.burnTick = e.burnTick - dt
				if e.burnTick <= 0 then
					e.burnTick = 0.5
					local d = math.max(1, math.floor(e.burnDps * 0.5 + 0.5))
					e.hp = e.hp - d
					if e.lastHitBy then fxTo(e.lastHitBy, "text", { pos = Vector3.new(e.pos.X, e.y + e.r, e.pos.Z), str = tostring(d), color = C.rgb(255, 140, 74) }) end
					updateEnemyGui(e)
					if e.hp <= 0 then killEnemy(e, e.lastHitBy) end
				end
			end
		end
		if not e.dead then
			e.pos = e.pos + e.kv * dt
			e.kv = e.kv * (0.002 ^ dt)
			if e.boss then
				updateBoss(e, dt)
			else
				local plr, hrp, d = nearestPlayer(e.pos)
				if not e.minion and not e.elite and d > 160 then
					removeEnemy(e)
				else
					if d < 62 or e.hitT > clock - 5 then e.aggro = true end
					local disabled = e.st.stun > clock or e.st.sleep > clock
					local spd = e.speed * ((e.st.slow > clock) and 0.5 or 1) * ((e.st.root > clock) and 0 or 1)
					e.atkCd = e.atkCd - dt
					e.special = e.special - dt
					if disabled then
						if e.wind > 0 then e.wind = 0 setBodyColor(e) end
					elseif e.st.charm > clock or not hrp then
						e.wander = e.wander + rng:NextNumber(-2, 2) * dt
						e.pos = e.pos + dirFromAngle(e.wander) * spd * 0.3 * dt
						e.face = dirFromAngle(e.wander)
						e.wind = 0
					elseif not e.aggro then
						e.wander = e.wander + rng:NextNumber(-1.5, 1.5) * dt
						e.pos = e.pos + dirFromAngle(e.wander) * spd * 0.25 * dt
						e.face = dirFromAngle(e.wander)
					elseif e.charge then
						e.pos = e.pos + e.charge.vel * dt
						if not e.charge.hit and d2(e.pos, hrp.Position) < e.r + WR.playerR + 0.5 then
							e.charge.hit = true
							hurtPlayer(plr, e.dmg * 1.3)
						end
						if clock > e.charge.untilT then e.charge = nil end
					elseif e.wind > 0 then
						e.wind = e.wind - dt
						if e.wind <= 0 then
							e.wind = 0
							setBodyColor(e)
							if e.windKind == "melee" then
								if d2(e.pos, hrp.Position) < e.r + WR.playerR + 3.2 then hurtPlayer(plr, e.dmg) end
								fxAll("slash", { pos = Vector3.new(e.pos.X, e.y, e.pos.Z), dir = e.face, r = e.r + 2.5, color = T.danger })
							elseif e.windKind == "shoot" then
								enemyShot(e.pos, flat(hrp.Position - e.pos).Unit * 36, 0.85, e.dmg, C.ETYPES[e.type].color)
							elseif e.windKind == "leap" then
								e.charge = { untilT = clock + 0.22, vel = e.face * 86 }
							elseif e.windKind == "charge" then
								e.charge = { untilT = clock + 0.55, vel = e.face * 67 }
							end
							e.atkCd = (e.type == "wisp") and 2.2 or 1.1
						end
					else
						local to = flat(hrp.Position - e.pos)
						if to.Magnitude > 0.05 then e.face = to.Unit end
						if e.type == "wisp" then
							local want = 0
							if d > 36 then want = 1 elseif d < 26 then want = -1 end
							local side = Vector3.new(-e.face.Z, 0, e.face.X)
							e.pos = e.pos + e.face * spd * want * dt + side * spd * 0.4 * dt * math.sin(clock + e.wander)
							if d < 55 and e.atkCd <= 0 then
								e.wind = 0.45
								e.windKind = "shoot"
							end
						else
							if d > e.r + WR.playerR + 1.2 then e.pos = e.pos + e.face * spd * dt end
							if e.type == "hound" and d > 13 and d < 28 and e.special <= 0 then
								e.wind = 0.3
								e.windKind = "leap"
								e.special = rng:NextNumber(2.5, 4)
							elseif e.type == "brute" and d > 14 and d < 38 and e.special <= 0 then
								e.wind = 0.7
								e.windKind = "charge"
								e.special = rng:NextNumber(4, 6)
							elseif d < e.r + WR.playerR + 2.4 and e.atkCd <= 0 then
								e.wind = (e.type == "hound") and 0.25 or ((e.type == "brute") and 0.55 or 0.35)
								e.windKind = "melee"
							end
						end
						if e.wind > 0 then
							setBodyColor(e)
							if e.windKind == "charge" or e.windKind == "leap" then
								fxAll("teleLine", { pos = e.pos, dir = e.face, len = (e.windKind == "leap") and 19 or 36, w = e.r * 2, color = T.danger, dur = e.wind, enemy = true })
							end
						end
					end
				end
			end
		end
	end

	-- separation and boundaries
	local n = #enemies
	for i = 1, n do
		local a = enemies[i]
		if not a.dead then
			for j = i + 1, n do
				local b = enemies[j]
				if not b.dead then
					local dx, dz = b.pos.X - a.pos.X, b.pos.Z - a.pos.Z
					local d = math.sqrt(dx * dx + dz * dz)
					local m = a.r + b.r
					if d > 0.01 and d < m then
						local p = (m - d) / 2
						local wa = a.boss and 0 or 1
						local wb = b.boss and 0 or 1
						a.pos = a.pos - Vector3.new(dx / d * p * wa, 0, dz / d * p * wa)
						b.pos = b.pos + Vector3.new(dx / d * p * wb, 0, dz / d * p * wb)
					end
				end
			end
			resolveRocks(a)
			local dc = a.pos.Magnitude
			if dc > WR.R - a.r then a.pos = a.pos.Unit * (WR.R - a.r) end
			if dc < WR.villageR + a.r and dc > 0.01 then a.pos = a.pos.Unit * (WR.villageR + a.r) end
			if a.boss or a.minion then
				local g = W.gates[a.gate]
				local rel = flat(a.pos - g.pos)
				if rel.Magnitude > WR.arenaR - a.r then a.pos = g.pos + rel.Unit * (WR.arenaR - a.r) end
			else
				for gi, g in ipairs(W.gates) do
					local rel = flat(a.pos - g.pos)
					if rel.Magnitude < WR.arenaR + a.r and rel.Magnitude > 0.01 then a.pos = g.pos + rel.Unit * (WR.arenaR + a.r) end
				end
			end
		end
	end

	local keep = {}
	for _, e in ipairs(enemies) do
		if not e.dead and e.model and e.model.Parent then
			local y = e.y
			if e.type == "wisp" and not e.boss then y = e.y + math.sin(clock * 3 + e.phase) * 0.4 end
			local p = Vector3.new(e.pos.X, y, e.pos.Z)
			e.model:PivotTo(CFrame.lookAt(p, p + e.face))
			if e.flashUntil and clock > e.flashUntil then
				e.flashUntil = nil
				setBodyColor(e)
			end
			local s = statusText(e)
			if e.stLabel.Text ~= s then
				e.stLabel.Text = s
				setBodyColor(e)
			end
			keep[#keep + 1] = e
		elseif e.model then
			e.model:Destroy()
		end
	end
	enemies = keep
end

-- ---------- per-player tick ----------
local function updatePlayer(plr, dt)
	local prof, st = profiles[plr], PS[plr]
	if not prof or not st then return end
	local c, hrp, hum = charOf(plr)
	if not c then return end
	local pos = flat(hrp.Position)

	if st.skillDash then
		local s = st.skillDash
		for _, e in ipairs(enemies) do
			if not e.dead and not s.hit[e] and d2(e.pos, pos) < e.r + s.w / 2 then
				s.hit[e] = true
				damageEnemy(e, s.dmg, s.o, plr)
			end
		end
		fxAll("burst", { pos = hrp.Position, color = s.color, n = 2, speed = 4 })
		if clock > s.untilT then st.skillDash = nil end
	end

	local moved = st.lastPos and d2(pos, st.lastPos) or 0
	st.lastPos = pos
	if moved > 0.05 then
		st.idle = 0
		if clock > st.dashUntil and not st.skillDash and moved < 5 then
			st.runAcc = st.runAcc + moved
			if st.runAcc > 60 then
				st.runAcc = st.runAcc - 60
				train(plr, "agi", 1)
			end
		end
	else
		st.idle = st.idle + dt
	end

	local MM = C.maxMal(prof)
	local idleBoost = (prof.sin == "sloth" and st.idle > 1) and 3 or 1
	local altar = d2(pos, W.altarPos) < 13
	if st.charging and clock >= st.stunUntil then
		st.mal = st.mal + 42 * (altar and 1.6 or 1) * dt
		train(plr, "mal", dt * (altar and 3 or 1.4))
	else
		st.mal = st.mal + 3 * idleBoost * dt
	end
	if st.awaken then
		st.mal = st.mal - 5 * dt
		if clock > st.awakenUntil or st.mal <= 0 then
			st.awaken = false
			st.awakenCdUntil = clock + 45
			toast(plr, "Your awakening fades", C.SINS[prof.sin].color)
			fxAll("aura", { char = c, on = false })
		end
	end
	st.mal = clamp(st.mal, 0, MM)

	if inVillage(pos) then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.06 * dt)
	elseif clock - st.lastHurt > 5 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.012 * idleBoost * dt)
	end
	if st.shield > 0 and clock > st.shieldUntil then st.shield = 0 end

	local ws = C.moveSpeed(prof) * (st.awaken and 1.25 or 1)
	if st.charging or clock < st.stunUntil then
		ws = 0
	elseif st.blocking then
		ws = ws * 0.4
	end
	if math.abs(hum.WalkSpeed - ws) > 0.01 then hum.WalkSpeed = ws end

	-- world edge
	if pos.Magnitude > WR.R - 2 then moveCharTo(c, hrp, pos.Unit * (WR.R - 3)) end

	-- arenas
	if st.gate then
		if not activeBoss[st.gate] then
			st.gate = nil
			notify(plr, "boss", { show = false })
		else
			local g = W.gates[st.gate]
			local rel = flat(pos - g.pos)
			if rel.Magnitude > WR.arenaR - 1.5 then moveCharTo(c, hrp, g.pos + rel.Unit * (WR.arenaR - 2.5)) end
		end
	elseif prof.created then
		local g = inArena(pos, 0)
		if not g then st.mustLeave = nil end
		if g and st.mustLeave == g.i then g = nil end
		if g then
			local B = C.BOSSES[g.i]
			if prof.level < B.req then
				local rel = flat(pos - g.pos)
				if rel.Magnitude < 0.01 then rel = Vector3.new(1, 0, 0) end
				moveCharTo(c, hrp, g.pos + rel.Unit * (WR.arenaR + 2))
				toast(plr, "The seal of " .. C.SINS[B.sin].name .. " holds. Reach level " .. B.req .. " to enter.", C.SINS[B.sin].color, "seal")
			elseif activeBoss[g.i] then
				st.gate = g.i
				local e = activeBoss[g.i]
				notify(plr, "boss", { name = B.name, color = C.SINS[B.sin].color, frac = e.hp / e.maxHp, hp = e.hp, show = true })
			else
				spawnBoss(g.i)
			end
		end
	end
end

-- ---------- spins, slots, stats, shop ----------
local function rollSin(prof)
	if prof.pity >= C.PITY - 1 then return (rng:NextNumber() < 0.85) and "wrath" or "pride" end
	return C.weightedPick(C.SIN_ORDER, C.SINS, rng)
end

local function doSpin(plr, tab)
	local prof, st = profiles[plr], PS[plr]
	if not prof or prof.spins <= 0 or clock < st.spinAt then return end
	st.spinAt = clock + 1.4
	prof.spins = prof.spins - 1
	local result
	if tab == "aff" then
		result = C.weightedPick(C.AFF_ORDER, C.AFFS, rng)
		prof.aff = result
	else
		tab = "line"
		result = rollSin(prof)
		local r = C.SINS[result].rarity
		if r == "legendary" or r == "mythic" then prof.pity = 0 else prof.pity = prof.pity + 1 end
		prof.sin = result
	end
	st.cd = {}
	refreshHealth(plr, false)
	notify(plr, "spin", { tab = tab, result = result })
	markDirty(plr)
end

local function slotAction(plr, what, i)
	local prof = profiles[plr]
	if not prof or (i ~= 1 and i ~= 2) then return end
	if what == "store" and prof.slots[i] == "" then
		prof.slots[i] = prof.sin
	elseif what == "equip" and prof.slots[i] ~= "" and C.SINS[prof.slots[i]] then
		local t = prof.slots[i]
		prof.slots[i] = prof.sin
		prof.sin = t
		PS[plr].cd = {}
		refreshHealth(plr, false)
	elseif what == "release" then
		prof.slots[i] = ""
	end
	markDirty(plr)
end

local function allocate(plr, s, n)
	local prof = profiles[plr]
	if not prof or not C.STAT_INFO[s] or (n ~= 1 and n ~= 5) or prof.points < n then return end
	prof.points = prof.points - n
	prof.stats[s] = prof.stats[s] + n
	refreshHealth(plr, false)
	markDirty(plr)
end

local function spinPrice(prof) return 300 + prof.spinsBought * 100 end
local function buy(plr, item)
	local prof, st = profiles[plr], PS[plr]
	if not prof then return end
	local price
	if item == "spin" then price = spinPrice(prof)
	elseif item == "spin5" then price = math.floor((spinPrice(prof) * 5 + 1000) * 0.85)
	elseif item == "elixir" then price = 40 + prof.level * 6
	elseif item == "reroll" then price = 30 + prof.level * 3
	else return end
	if prof.souls < price then return toast(plr, "Not enough souls", T.blood) end
	prof.souls = prof.souls - price
	if item == "spin" then
		prof.spins = prof.spins + 1
		prof.spinsBought = prof.spinsBought + 1
		toast(plr, "+1 spin", T.ember)
	elseif item == "spin5" then
		prof.spins = prof.spins + 5
		prof.spinsBought = prof.spinsBought + 5
		toast(plr, "+5 spins", T.ember)
	elseif item == "elixir" then
		refreshHealth(plr, true)
		st.mal = C.maxMal(prof)
		toast(plr, "Restored", C.RARITY.uncommon.color)
	elseif item == "reroll" then
		prof.board = genMissions(prof)
		toast(plr, "The board has new postings", T.ember)
	end
	markDirty(plr)
end

-- ---------- remote handler ----------
Action.OnServerEvent:Connect(function(plr, act, a, b)
	local prof, st = profiles[plr], PS[plr]
	if not prof or not st or type(act) ~= "string" then return end
	if act == "ready" then
		StateR:FireClient(plr, prof)
		if not prof.created then notify(plr, "open", { what = "create" }) end
		if prof.noSave then toast(plr, "Saving is off: turn on Studio Access to API Services, or the DataStore failed to load.", T.ember) end
	elseif act == "enter" then
		if not prof.created then
			prof.created = true
			banner(plr, prof.name, C.SINS[prof.sin].name .. " bloodline · " .. C.AFFS[prof.aff].name, C.SINS[prof.sin].color)
			task.delay(1, function() toast(plr, "Hit the training dummies, take a mission from the board, then head out past the braziers.", T.ember) end)
			markDirty(plr)
		end
	elseif act == "melee" then doMelee(plr, a)
	elseif act == "skill" then
		if type(a) == "string" then trySkill(plr, a, b) end
	elseif act == "dash" then doDash(plr)
	elseif act == "charge" then st.charging = (a == true)
	elseif act == "block" then st.blocking = (a == true)
	elseif act == "awaken" then toggleAwaken(plr)
	elseif act == "spin" then doSpin(plr, a)
	elseif act == "slot" then
		if type(a) == "string" and type(b) == "number" then slotAction(plr, a, b) end
	elseif act == "stat" then allocate(plr, a, b)
	elseif act == "accept" then
		if prof.mission then return end
		for idx, m in ipairs(prof.board) do
			if m.id == a then
				prof.mission = m
				m.prog = 0
				table.remove(prof.board, idx)
				toast(plr, "Accepted: " .. m.text, C.RANK_COLORS[m.rank])
				markDirty(plr)
				break
			end
		end
	elseif act == "abandon" then
		prof.mission = nil
		for _, e in ipairs(enemies) do
			if e.elite and e.owner == plr then removeEnemy(e) end
		end
		markDirty(plr)
	elseif act == "buy" then buy(plr, a)
	end
end)

-- ---------- village prompts ----------
W.objects.shrine.prompt.Triggered:Connect(function(plr)
	if profiles[plr] then notify(plr, "open", { what = "spin" }) end
end)
W.objects.board.prompt.Triggered:Connect(function(plr)
	local prof = profiles[plr]
	if not prof then return end
	if not prof.board or #prof.board == 0 then
		prof.board = genMissions(prof)
		StateR:FireClient(plr, prof)
	end
	notify(plr, "open", { what = "board" })
end)
W.objects.ferry.prompt.Triggered:Connect(function(plr)
	if profiles[plr] then notify(plr, "open", { what = "shop" }) end
end)
W.objects.altar.prompt.Triggered:Connect(function(plr)
	toast(plr, "Hold C beside the altar. Malice training runs at double speed here.", T.mal)
end)

-- ---------- players ----------
local function migrate(data, plr)
	local base = C.newProfile(plr.DisplayName)
	for k, v in pairs(data) do base[k] = v end
	local fresh = C.newProfile(plr.DisplayName)
	for _, s in ipairs(C.STAT_ORDER) do
		base.stats[s] = base.stats[s] or fresh.stats[s]
		base.train[s] = base.train[s] or 0
	end
	if not C.SINS[base.sin] then base.sin = "sloth" end
	if not C.AFFS[base.aff] then base.aff = "hellfire" end
	if type(base.slots) ~= "table" then base.slots = { "", "" } end
	base.slots[1] = base.slots[1] or ""
	base.slots[2] = base.slots[2] or ""
	base.mastery = base.mastery or {}
	base.bosses = base.bosses or {}
	base.board = base.board or {}
	return base
end

onDied = function(plr)
	local prof, st = profiles[plr], PS[plr]
	if not prof then return end
	prof.deaths = prof.deaths + 1
	local lost = math.floor(prof.souls * 0.25)
	prof.souls = prof.souls - lost
	local had = prof.mission ~= nil
	prof.mission = nil
	for _, e in ipairs(enemies) do
		if e.elite and e.owner == plr then removeEnemy(e) end
	end
	if st then
		st.gate = nil
		st.awaken = false
		st.charging = false
		st.blocking = false
	end
	notify(plr, "boss", { show = false })
	notify(plr, "death", { lost = lost, mission = had })
	markDirty(plr)
	task.spawn(Data.save, plr.UserId, prof)
end

local function onCharacter(plr, c)
	local hum = c:WaitForChild("Humanoid", 10)
	if not hum then return end
	local function killRegen(ch)
		if ch.Name == "Health" and ch:IsA("Script") then ch:Destroy() end
	end
	for _, ch in ipairs(c:GetChildren()) do killRegen(ch) end
	c.ChildAdded:Connect(killRegen)
	local prof = profiles[plr]
	PS[plr] = newRuntime(PS[plr])
	if prof then
		hum.MaxHealth = C.maxHp(prof)
		hum.Health = hum.MaxHealth
		hum.WalkSpeed = C.moveSpeed(prof)
		PS[plr].mal = C.maxMal(prof)
	end
	hum.Died:Connect(function() onDied(plr) end)
end

local function onPlayerAdded(plr)
	local data, ok = Data.load(plr.UserId)
	if not plr.Parent then return end
	local prof
	if ok and type(data) == "table" then
		prof = migrate(data, plr)
	else
		prof = C.newProfile(plr.DisplayName)
		if not ok then prof.noSave = true end
	end
	if not prof.board or #prof.board == 0 then prof.board = genMissions(prof) end
	profiles[plr] = prof
	PS[plr] = newRuntime()

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local lv = Instance.new("IntValue")
	lv.Name = "Level"
	lv.Value = prof.level
	lv.Parent = ls
	local so = Instance.new("IntValue")
	so.Name = "Souls"
	so.Value = prof.souls
	so.Parent = ls
	ls.Parent = plr

	plr.CharacterAdded:Connect(function(c) onCharacter(plr, c) end)
	if plr.Character then onCharacter(plr, plr.Character) end
	markDirty(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, plr) end

Players.PlayerRemoving:Connect(function(plr)
	local prof = profiles[plr]
	if prof then Data.save(plr.UserId, prof) end
	for _, e in ipairs(enemies) do
		if e.elite and e.owner == plr then removeEnemy(e) end
	end
	profiles[plr] = nil
	PS[plr] = nil
	dirty[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if profiles[plr] then Data.save(plr.UserId, profiles[plr]) end
	end
end)

-- ---------- main loop ----------
local spawnT, sendT, attrT, saveT = 0, 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	clock = clock + dt
	for _, plr in ipairs(Players:GetPlayers()) do updatePlayer(plr, dt) end
	updateEnemies(dt)
	updateProjectiles(dt)
	updateFields(dt)

	spawnT = spawnT - dt
	if spawnT <= 0 then
		spawnT = 0.5
		spawner()
	end

	attrT = attrT - dt
	if attrT <= 0 then
		attrT = 0.1
		for _, plr in ipairs(Players:GetPlayers()) do
			local prof, st = profiles[plr], PS[plr]
			if prof and st then
				plr:SetAttribute("Malice", math.floor(st.mal))
				plr:SetAttribute("MaxMalice", C.maxMal(prof))
				plr:SetAttribute("Awakened", st.awaken)
				plr:SetAttribute("AwakenLeft", st.awaken and math.max(0, st.awakenUntil - clock) or 0)
				plr:SetAttribute("AwakenCd", math.max(0, st.awakenCdUntil - clock))
				plr:SetAttribute("Shield", math.floor(st.shield))
				plr:SetAttribute("Charging", st.charging)
				plr:SetAttribute("Stunned", clock < st.stunUntil)
			end
		end
		for i, e in pairs(activeBoss) do
			bossNotify(i, { name = e.name, color = C.SINS[C.BOSSES[i].sin].color, frac = math.max(0, e.hp / e.maxHp), hp = math.max(0, math.ceil(e.hp)), show = true })
		end
	end

	sendT = sendT - dt
	if sendT <= 0 then
		sendT = 0.25
		for plr in pairs(dirty) do
			local prof = profiles[plr]
			if prof and plr.Parent then
				StateR:FireClient(plr, prof)
				local ls = plr:FindFirstChild("leaderstats")
				if ls then
					ls.Level.Value = prof.level
					ls.Souls.Value = prof.souls
				end
			end
		end
		dirty = {}
	end

	saveT = saveT + dt
	if saveT > 60 then
		saveT = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			if profiles[plr] then task.spawn(Data.save, plr.UserId, profiles[plr]) end
		end
	end
end)
