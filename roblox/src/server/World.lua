-- Builds the Pit: ground, Limbo village, seven sealed arenas, rocks, trees and lava pools.
-- Everything is generated from code so the place needs no hand-built map.

local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")
local C = require(RS:WaitForChild("Sinborn"):WaitForChild("Config"))

local World = {}
local T = C.THEME
local rgb = C.rgb

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Shape and Size first, so the CFrame lands where it was asked to.
	if props.Shape then p.Shape = props.Shape end
	if props.Size then p.Size = props.Size end
	-- CanQuery can only turn off once CanCollide is off.
	if props.CanCollide ~= nil then p.CanCollide = props.CanCollide end
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Shape" and k ~= "Size" and k ~= "CanCollide" then p[k] = v end
	end
	p.Parent = props.Parent
	return p
end
World.part = part

-- Flat disc whose top surface sits at pos.Y.
local function disc(parent, pos, radius, thick, color, material, name)
	return part({
		Name = name or "Disc", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, radius * 2, radius * 2),
		CFrame = CFrame.new(pos.X, pos.Y - thick / 2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color, Material = material or Enum.Material.Slate, Parent = parent,
	})
end
World.disc = disc

local function bar(parent, a, b, thick, color, name)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	return part({
		Name = name or "Bar", Size = Vector3.new(thick, 0.12, len), CFrame = CFrame.lookAt(mid, b),
		Color = color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false, Parent = parent,
	})
end

-- A {7/3} heptagram made of neon bars, grouped in a model.
local function heptagram(parent, center, radius, color, rot, thick, name)
	local m = Instance.new("Model")
	m.Name = name or "Heptagram"
	local pts = {}
	for i = 0, 6 do
		local k = (i * 3) % 7
		local a = (rot or 0) - math.pi / 2 + k * math.pi * 2 / 7
		pts[i + 1] = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
	end
	for i = 1, 7 do
		bar(m, pts[i], pts[(i % 7) + 1], thick or 0.4, color)
	end
	m.Parent = parent
	return m
end
World.heptagram = heptagram

local function ring(parent, center, radius, segs, color, height, name)
	local m = Instance.new("Model")
	m.Name = name or "Ring"
	for i = 0, segs - 1 do
		local a1 = i / segs * math.pi * 2
		local a2 = (i + 0.55) / segs * math.pi * 2
		local p1 = center + Vector3.new(math.cos(a1) * radius, height or 0.1, math.sin(a1) * radius)
		local p2 = center + Vector3.new(math.cos(a2) * radius, height or 0.1, math.sin(a2) * radius)
		bar(m, p1, p2, 0.6, color)
	end
	m.Parent = parent
	return m
end

local function label(parent, text, color, size, offset, font)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(size and size[1] or 260, size and size[2] or 60)
	bb.StudsOffset = offset or Vector3.new(0, 6, 0)
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBold
	t.TextStrokeTransparency = 0.3
	t.Parent = bb
	bb.Parent = parent
	return bb
end
World.label = label

local function prompt(parent, action, object, key)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	p.Parent = parent
	return p
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = rgb(70, 40, 45)
	Lighting.OutdoorAmbient = rgb(90, 45, 50)
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.GlobalShadows = true
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("PostEffect") then c:Destroy() end
	end
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.38
	atm.Offset = 0.1
	atm.Color = rgb(120, 40, 40)
	atm.Decay = rgb(40, 10, 14)
	atm.Glare = 0
	atm.Haze = 2
	atm.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 0.9
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = rgb(255, 225, 220)
	cc.Contrast = 0.12
	cc.Saturation = 0.05
	cc.Parent = Lighting
end

function World.build()
	setupLighting()
	local old = workspace:FindFirstChild("Sinborn")
	if old then old:Destroy() end
	local base = workspace:FindFirstChild("Baseplate")
	if base then base:Destroy() end
	for _, s in ipairs(workspace:GetChildren()) do
		if s:IsA("SpawnLocation") then s:Destroy() end
	end

	local root = Instance.new("Folder")
	root.Name = "Sinborn"
	root.Parent = workspace
	local function folder(n)
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = root
		return f
	end
	local floor = folder("Floor")
	local deco = folder("Decor")
	local village = folder("Village")
	local gatesF = folder("Gates")
	local enemiesF = folder("Enemies")
	local fxF = folder("FX")

	local R = C.WORLD.R
	local W = { root = root, floor = floor, enemies = enemiesF, fx = fxF, rocks = {}, gates = {}, dummies = {}, objects = {} }

	-- ground and rim
	disc(floor, Vector3.new(0, 0, 0), R + 4, 6, rgb(32, 22, 25), Enum.Material.Slate, "Ground")
	local rim = Random.new(99)
	for i = 0, 89 do
		local a = i / 90 * math.pi * 2
		local h = rim:NextNumber(10, 26)
		local p = part({
			Name = "Rim", Size = Vector3.new(rim:NextNumber(8, 14), h, rim:NextNumber(6, 10)),
			CFrame = CFrame.new(math.cos(a) * (R + 2), h / 2 - 1, math.sin(a) * (R + 2)) * CFrame.Angles(rim:NextNumber(-0.3, 0.3), -a, rim:NextNumber(-0.3, 0.3)),
			Color = rgb(28, 16, 18), Material = Enum.Material.Basalt, Parent = deco,
		})
		p.CanCollide = true
	end

	-- village
	local VR = C.WORLD.villageR
	disc(floor, Vector3.new(0, 0.2, 0), VR, 0.4, rgb(48, 36, 38), Enum.Material.Cobblestone, "VillageFloor")
	disc(floor, Vector3.new(0, 0.25, 0), 14, 0.1, rgb(38, 26, 28), Enum.Material.Slate, "VillageCore")
	heptagram(village, Vector3.new(0, 0.32, 0), 12, rgb(110, 22, 30), 0, 0.5, "FloorSigil")
	ring(village, Vector3.new(0, 0.22, 0), VR, 48, rgb(90, 22, 28), 0.25, "VillageEdge")

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LimboSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 0.45, 8)
	spawn.Color = rgb(60, 44, 46)
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = village
	for _, d in ipairs(spawn:GetChildren()) do
		if d:IsA("Decal") then d:Destroy() end
	end

	-- braziers, one per sin
	for i = 1, 7 do
		local a = -math.pi / 2 + (i - 1) * math.pi * 2 / 7
		local pos = Vector3.new(math.cos(a) * (VR - 4), 0, math.sin(a) * (VR - 4))
		local col = C.SINS[C.SIN_ORDER[i]].color
		part({ Name = "BrazierStand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.2, 2.2), CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(30, 20, 22), Material = Enum.Material.Metal, Parent = village })
		local bowl = part({ Name = "Brazier", Size = Vector3.new(3, 0.6, 3), CFrame = CFrame.new(pos + Vector3.new(0, 4.2, 0)), Color = col, Material = Enum.Material.Neon, CanCollide = false, Parent = village })
		local fire = Instance.new("Fire")
		fire.Color = col
		fire.SecondaryColor = rgb(255, 230, 200)
		fire.Size = 5
		fire.Heat = 9
		fire.Parent = bowl
		local light = Instance.new("PointLight")
		light.Color = col
		light.Range = 18
		light.Brightness = 2
		light.Parent = bowl
	end

	-- shrine
	local shrinePos = Vector3.new(0, 0, -26)
	local shrine = part({ Name = "Shrine", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 10, 10), CFrame = CFrame.new(shrinePos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(18, 11, 12), Material = Enum.Material.Basalt, Parent = village })
	local sig = Instance.new("Model")
	sig.Name = "ShrineSigil"
	heptagram(sig, shrinePos + Vector3.new(0, 4.5, 0), 4, T.ember, 0, 0.35, "Outer")
	heptagram(sig, shrinePos + Vector3.new(0, 4.5, 0), 2.6, T.blood, 0, 0.3, "Inner")
	local core = part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(shrinePos + Vector3.new(0, 4.5, 0)), Color = T.ember, Material = Enum.Material.Neon, CanCollide = false, Parent = sig })
	sig.PrimaryPart = core
	sig.Parent = village
	local sl = Instance.new("PointLight")
	sl.Color = T.ember
	sl.Range = 20
	sl.Brightness = 3
	sl.Parent = core
	label(shrine, "Shrine of the Heptagram", T.ember, { 240, 34 }, Vector3.new(0, 9, 0), Enum.Font.GothamBold)
	W.objects.shrine = { pos = shrinePos, prompt = prompt(shrine, "Spin", "Shrine of the Heptagram") }

	-- board
	local boardPos = Vector3.new(-26, 0, 6)
	part({ Name = "BoardPost", Size = Vector3.new(0.8, 6, 0.8), CFrame = CFrame.new(boardPos + Vector3.new(0, 3, 0)), Color = rgb(61, 42, 30), Material = Enum.Material.Wood, Parent = village })
	local board = part({ Name = "Board", Size = Vector3.new(7, 4.5, 0.6), CFrame = CFrame.lookAt(boardPos + Vector3.new(0, 5, 0), Vector3.new(0, 5, 0)), Color = rgb(74, 51, 34), Material = Enum.Material.Wood, Parent = village })
	for i = -1, 1 do
		part({ Name = "Paper", Size = Vector3.new(1.6, 2.2, 0.1), CFrame = board.CFrame * CFrame.new(i * 2.1, 0.1 + (i % 2) * 0.2, -0.36), Color = rgb(217, 201, 168), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = village })
	end
	label(board, "Board of Penance", T.bone, { 220, 30 }, Vector3.new(0, 4, 0))
	W.objects.board = { pos = boardPos, prompt = prompt(board, "Missions", "Board of Penance") }

	-- ferryman
	local fPos = Vector3.new(26, 0, 6)
	local robe = part({ Name = "Ferryman", Size = Vector3.new(3, 6, 3), CFrame = CFrame.lookAt(fPos + Vector3.new(0, 3, 0), Vector3.new(0, 3, 0)), Color = rgb(23, 23, 28), Material = Enum.Material.Fabric, Parent = village })
	part({ Name = "Hood", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = robe.CFrame * CFrame.new(0, 3.8, 0), Color = rgb(18, 18, 22), Material = Enum.Material.Fabric, Parent = village })
	for _, sx in ipairs({ -0.4, 0.4 }) do
		part({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = robe.CFrame * CFrame.new(sx, 3.9, -1.1), Color = T.soul, Material = Enum.Material.Neon, CanCollide = false, Parent = village })
	end
	part({ Name = "Staff", Size = Vector3.new(0.3, 8, 0.3), CFrame = robe.CFrame * CFrame.new(2, 1, -0.5), Color = rgb(90, 74, 58), Material = Enum.Material.Wood, Parent = village })
	local lantern = part({ Name = "Lantern", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = robe.CFrame * CFrame.new(2, 5.4, -0.5), Color = T.soul, Material = Enum.Material.Neon, CanCollide = false, Parent = village })
	local ll = Instance.new("PointLight")
	ll.Color = T.soul
	ll.Range = 14
	ll.Brightness = 2
	ll.Parent = lantern
	label(robe, "The Ferryman", T.soul, { 200, 30 }, Vector3.new(0, 6.5, 0))
	W.objects.ferry = { pos = fPos, prompt = prompt(robe, "Trade", "The Ferryman") }

	-- altar
	local aPos = Vector3.new(0, 0, 26)
	local altar = part({ Name = "Altar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 7, 7), CFrame = CFrame.new(aPos + Vector3.new(0, 1.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(44, 33, 36), Material = Enum.Material.Basalt, Parent = village })
	local flame = part({ Name = "AltarFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), CFrame = CFrame.new(aPos + Vector3.new(0, 3.3, 0)), Color = T.mal, Material = Enum.Material.Neon, CanCollide = false, Parent = village })
	local af = Instance.new("Fire")
	af.Color = T.mal
	af.SecondaryColor = rgb(200, 170, 255)
	af.Size = 4
	af.Parent = flame
	local al = Instance.new("PointLight")
	al.Color = T.mal
	al.Range = 16
	al.Brightness = 2
	al.Parent = flame
	local zone = disc(village, aPos + Vector3.new(0, 0.42, 0), 13, 0.05, T.mal, Enum.Material.Neon, "AltarZone")
	zone.Transparency = 0.82
	zone.CanCollide = false
	zone.CanQuery = false
	label(altar, "Altar of Malice", T.mal, { 200, 30 }, Vector3.new(0, 5, 0))
	W.objects.altar = { pos = aPos, prompt = prompt(altar, "Read", "Altar of Malice") }
	W.altarPos = aPos

	-- training dummies
	local dummyPos = { Vector3.new(-38, 0, -17), Vector3.new(-43, 0, -7), Vector3.new(-32, 0, -7) }
	for _, p in ipairs(dummyPos) do
		part({ Name = "DummyPost", Size = Vector3.new(0.6, 5, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)), Color = rgb(74, 51, 34), Material = Enum.Material.Wood, Parent = village })
		local body = part({ Name = "Dummy", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = CFrame.new(p + Vector3.new(0, 4.3, 0)), Color = rgb(179, 154, 100), Material = Enum.Material.Fabric, Parent = village })
		part({ Name = "DummyArms", Size = Vector3.new(4, 0.5, 0.5), CFrame = CFrame.new(p + Vector3.new(0, 4, 0)), Color = rgb(138, 116, 68), Material = Enum.Material.Wood, CanCollide = false, Parent = village })
		W.dummies[#W.dummies + 1] = { pos = p, part = body }
	end
	label(village:FindFirstChild("Dummy"), "Training dummies", T.ash, { 200, 26 }, Vector3.new(-2, 4, 0))

	-- arenas
	for i, g in ipairs(C.GATES) do
		local B = C.BOSSES[i]
		local col = C.SINS[B.sin].color
		local pos = Vector3.new(g.x, 0, g.z)
		local gm = Instance.new("Model")
		gm.Name = "Gate" .. i
		disc(floor, pos + Vector3.new(0, 0.15, 0), C.WORLD.arenaR, 0.3, rgb(22, 14, 16), Enum.Material.Basalt, "Arena" .. i)
		heptagram(gm, pos + Vector3.new(0, 0.32, 0), C.WORLD.arenaR * 0.85, col, i, 0.5, "Sigil")
		ring(gm, pos, C.WORLD.arenaR, 40, col, 0.35, "Seal")
		local pillar = part({ Name = "Pillar", Size = Vector3.new(3, 14, 3), CFrame = CFrame.new(pos + Vector3.new(0, 7, 0) + (pos.Unit * -(C.WORLD.arenaR + 4))), Color = rgb(28, 18, 20), Material = Enum.Material.Basalt, Parent = gm })
		local cap = part({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = pillar.CFrame * CFrame.new(0, 8, 0), Color = col, Material = Enum.Material.Neon, CanCollide = false, Parent = gm })
		local pl = Instance.new("PointLight")
		pl.Color = col
		pl.Range = 24
		pl.Brightness = 2
		pl.Parent = cap
		local lb = label(pillar, C.SINS[B.sin].name .. "\n" .. B.name .. "  ·  Lv " .. B.req .. "+", col, { 300, 64 }, Vector3.new(0, 11, 0), Enum.Font.GothamBold)
		lb.Name = "GateLabel"
		gm:SetAttribute("Gate", i)
		gm.Parent = gatesF
		W.gates[i] = { pos = pos, i = i, model = gm }
	end

	-- rocks, trees, pools (seeded)
	local rnd = Random.new(1337)
	local function okSpot(x, z, pad)
		local dc = math.sqrt(x * x + z * z)
		if dc < VR + 10 + pad or dc > R - 10 then return false end
		for _, g in ipairs(C.GATES) do
			local dx, dz = x - g.x, z - g.z
			if math.sqrt(dx * dx + dz * dz) < C.WORLD.arenaR + 8 + pad then return false end
		end
		return true
	end
	local tries = 0
	while #W.rocks < 150 and tries < 900 do
		tries = tries + 1
		local a = rnd:NextNumber() * math.pi * 2
		local d = math.sqrt(rnd:NextNumber()) * R
		local x, z = math.cos(a) * d, math.sin(a) * d
		local r = rnd:NextNumber(2.2, 6.5)
		local ok = okSpot(x, z, r)
		if ok then
			for _, k in ipairs(W.rocks) do
				local dx, dz = k.x - x, k.z - z
				if math.sqrt(dx * dx + dz * dz) < k.r + r + 9 then ok = false break end
			end
		end
		if ok then
			local h = r * rnd:NextNumber(0.9, 1.7)
			part({ Name = "Rock", Size = Vector3.new(r * 2, h, r * 2 * rnd:NextNumber(0.8, 1.1)),
				CFrame = CFrame.new(x, h / 2 - 0.3, z) * CFrame.Angles(rnd:NextNumber(-0.15, 0.15), rnd:NextNumber() * 6.28, rnd:NextNumber(-0.15, 0.15)),
				Color = rgb(44, 33, 36), Material = Enum.Material.Basalt, Parent = deco })
			W.rocks[#W.rocks + 1] = { x = x, z = z, r = r * 1.05 }
		end
	end
	local trees = 0
	tries = 0
	while trees < 110 and tries < 400 do
		tries = tries + 1
		local a = rnd:NextNumber() * math.pi * 2
		local d = math.sqrt(rnd:NextNumber()) * R
		local x, z = math.cos(a) * d, math.sin(a) * d
		if okSpot(x, z, 2) then
			trees = trees + 1
			local s = rnd:NextNumber(0.8, 1.5)
			local tm = Instance.new("Model")
			tm.Name = "DeadTree"
			part({ Name = "Trunk", Size = Vector3.new(0.8 * s, 7 * s, 0.8 * s), CFrame = CFrame.new(x, 3.5 * s, z) * CFrame.Angles(rnd:NextNumber(-0.1, 0.1), 0, rnd:NextNumber(-0.1, 0.1)), Color = rgb(43, 29, 28), Material = Enum.Material.Wood, Parent = tm })
			for b = 1, 3 do
				local ba = rnd:NextNumber() * 6.28
				part({ Name = "Branch", Size = Vector3.new(0.4 * s, 0.4 * s, 4 * s), CanCollide = false,
					CFrame = CFrame.new(x, (4.5 + b) * s, z) * CFrame.Angles(0, ba, 0) * CFrame.Angles(0.5, 0, 0) * CFrame.new(0, 0, -1.6 * s),
					Color = rgb(43, 29, 28), Material = Enum.Material.Wood, Parent = tm })
			end
			tm.Parent = deco
		end
	end
	local pools = 0
	tries = 0
	while pools < 30 and tries < 200 do
		tries = tries + 1
		local a = rnd:NextNumber() * math.pi * 2
		local d = math.sqrt(rnd:NextNumber()) * R
		local x, z = math.cos(a) * d, math.sin(a) * d
		local r = rnd:NextNumber(4, 9)
		if okSpot(x, z, r) then
			pools = pools + 1
			local p = disc(deco, Vector3.new(x, 0.08, z), r, 0.1, rgb(255, 90, 30), Enum.Material.Neon, "EmberPool")
			p.Transparency = 0.25
			p.CanCollide = false
			if pools % 2 == 0 then
				local l = Instance.new("PointLight")
				l.Color = rgb(255, 100, 40)
				l.Range = r * 2.2
				l.Brightness = 1.5
				l.Parent = p
			end
		end
	end

	return W
end

return World
