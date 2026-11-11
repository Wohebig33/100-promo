-- Client-side visual effects. The server sends (kind, data); this draws neon shapes locally.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FX = {}
local folder = Instance.new("Folder")
folder.Name = "SinbornLocalFX"
folder.Parent = workspace
FX.folder = folder

local GROUND = 0.35
local auras = {}

local function neon(size, cf, color, transparency, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = transparency or 0
	p.Parent = folder
	return p
end

local function flatDisc(pos, r, color, transparency, y)
	local d = math.max(0.1, r * 2)
	return neon(Vector3.new(0.08, d, d), CFrame.new(pos.X, y or GROUND, pos.Z) * CFrame.Angles(0, 0, math.rad(90)), color, transparency, Enum.PartType.Cylinder)
end

local function tween(inst, t, props, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function fade(p, t)
	tween(p, t, { Transparency = 1 })
	Debris:AddItem(p, t + 0.05)
end

local function flatLook(pos, dir, y)
	local o = Vector3.new(pos.X, y, pos.Z)
	return CFrame.lookAt(o, o + Vector3.new(dir.X, 0, dir.Z))
end

local handlers = {}

handlers.ring = function(d)
	local p = flatDisc(d.pos, d.r0, d.color, 0.25, GROUND + 0.05)
	local s = math.max(0.1, d.r1 * 2)
	tween(p, d.dur, { Size = Vector3.new(0.08, s, s), Transparency = 1 })
	Debris:AddItem(p, d.dur + 0.05)
end

handlers.disc = function(d)
	local p = flatDisc(d.pos, d.r, d.color, 0.45, GROUND + 0.04)
	fade(p, d.dur or 0.25)
end

handlers.tele = function(d)
	local outer = flatDisc(d.pos, d.r, d.color, d.enemy and 0.7 or 0.8, GROUND)
	local inner = flatDisc(d.pos, 0.05, d.color, d.enemy and 0.45 or 0.6, GROUND + 0.02)
	local s = d.r * 2
	tween(inner, d.dur, { Size = Vector3.new(0.08, s, s) }, Enum.EasingStyle.Linear)
	if d.follow then
		local t0 = os.clock()
		local conn
		conn = game:GetService("RunService").RenderStepped:Connect(function()
			if os.clock() - t0 > d.dur or not d.follow.Parent then
				conn:Disconnect()
				return
			end
			local p = d.follow.Position
			outer.CFrame = CFrame.new(p.X, GROUND, p.Z) * CFrame.Angles(0, 0, math.rad(90))
			inner.CFrame = CFrame.new(p.X, GROUND + 0.02, p.Z) * CFrame.Angles(0, 0, math.rad(90))
		end)
	end
	Debris:AddItem(outer, d.dur)
	Debris:AddItem(inner, d.dur)
end

handlers.teleLine = function(d)
	local base = flatLook(d.pos, d.dir, GROUND)
	local outer = neon(Vector3.new(d.w, 0.08, d.len), base * CFrame.new(0, 0, -d.len / 2), d.color, d.enemy and 0.7 or 0.8)
	local inner = neon(Vector3.new(d.w, 0.1, 0.05), base * CFrame.new(0, 0.02, -0.025), d.color, d.enemy and 0.45 or 0.6)
	tween(inner, d.dur, { Size = Vector3.new(d.w, 0.1, d.len), CFrame = base * CFrame.new(0, 0.02, -d.len / 2) }, Enum.EasingStyle.Linear)
	Debris:AddItem(outer, d.dur)
	Debris:AddItem(inner, d.dur)
end

handlers.beam = function(d)
	local base = flatLook(d.pos, d.dir, 3)
	local h = math.max(1.2, d.w * 0.5)
	local p = neon(Vector3.new(d.w, h, d.len), base * CFrame.new(0, 0, -d.len / 2), d.color, 0.15)
	local core = neon(Vector3.new(d.w * 0.3, h * 0.4, d.len), base * CFrame.new(0, 0, -d.len / 2), Color3.new(1, 1, 1), 0.1)
	tween(p, d.dur, { Size = Vector3.new(d.w * 0.3, h * 0.3, d.len), Transparency = 1 })
	fade(core, d.dur)
	Debris:AddItem(p, d.dur + 0.05)
end

handlers.cone = function(d)
	local a0 = math.atan2(d.dir.Z, d.dir.X)
	local n = 5
	for i = 0, n - 1 do
		local a = a0 + (i / (n - 1) - 0.5) * 2 * d.half
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = flatLook(d.pos, dir, 2)
		local p = neon(Vector3.new(d.range * 0.2, 0.3, d.range * 0.3), base * CFrame.new(0, 0, -d.range * 0.3), d.color, 0.3)
		tween(p, d.dur, { CFrame = base * CFrame.new(0, 0, -d.range * 0.85), Size = Vector3.new(d.range * 0.35, 0.3, d.range * 0.3), Transparency = 1 })
		Debris:AddItem(p, d.dur + 0.05)
	end
end

handlers.slash = function(d)
	local a0 = math.atan2(d.dir.Z, d.dir.X)
	local n = 6
	local y = d.pos.Y
	for i = 0, n - 1 do
		local t = i / (n - 1)
		if d.flip then t = 1 - t end
		local a = a0 + (t - 0.5) * 2
		local p = Vector3.new(d.pos.X + math.cos(a) * d.r, y, d.pos.Z + math.sin(a) * d.r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local part = neon(Vector3.new(0.25, 0.25, d.r * 0.45), CFrame.lookAt(p, p + tangent), d.color, 1)
		task.delay(i * 0.018, function()
			part.Transparency = 0.1
			fade(part, 0.14)
		end)
	end
end

handlers.pillar = function(d)
	local w = d.r * 0.8
	local p = neon(Vector3.new(40, w, w), CFrame.new(d.pos.X, 20, d.pos.Z) * CFrame.Angles(0, 0, math.rad(90)), d.color, 0.2, Enum.PartType.Cylinder)
	tween(p, d.dur, { Size = Vector3.new(40, w * 0.2, w * 0.2), Transparency = 1 })
	Debris:AddItem(p, d.dur + 0.05)
	local disc = flatDisc(d.pos, d.r, d.color, 0.4, GROUND + 0.05)
	fade(disc, d.dur)
end

handlers.field = function(d)
	local p = flatDisc(d.pos, d.r, d.color, 0.82, GROUND)
	local ring = flatDisc(d.pos, d.r * 0.6, d.color, 0.7, GROUND + 0.02)
	local s = d.r * 2
	if d.pull then
		ring.Size = Vector3.new(0.08, s, s)
		tween(ring, 0.6, { Size = Vector3.new(0.08, 0.2, 0.2) })
		task.spawn(function()
			local t = 0
			while t < d.dur - 0.6 and ring.Parent do
				task.wait(0.6)
				t = t + 0.6
				ring.Size = Vector3.new(0.08, s, s)
				tween(ring, 0.6, { Size = Vector3.new(0.08, 0.2, 0.2) })
			end
		end)
	else
		tween(ring, d.dur, { Size = Vector3.new(0.08, s, s) }, Enum.EasingStyle.Sine)
	end
	task.delay(d.dur - 0.3, function()
		if p.Parent then fade(p, 0.3) end
		if ring.Parent then fade(ring, 0.3) end
	end)
end

handlers.burst = function(d)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(d.pos)
	holder.Parent = folder
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(d.color)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Rate = 0
	pe.Speed = NumberRange.new((d.speed or 15) * 0.3, d.speed or 15)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Lifetime = NumberRange.new(0.25, 0.6)
	pe.Drag = 4
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = holder
	pe:Emit(math.min(80, d.n or 10))
	Debris:AddItem(holder, 1.2)
end

local textCount = 0
handlers.text = function(d)
	if textCount > 40 then return end
	textCount = textCount + 1
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(d.pos + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5))
	holder.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextSize = d.big and 26 or 19
	t.Text = d.str
	t.TextColor3 = d.color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.Parent = bb
	bb.Parent = holder
	tween(holder, 0.9, { CFrame = holder.CFrame + Vector3.new(0, 3, 0) })
	tween(t, 0.9, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quint)
	task.delay(0.95, function()
		holder:Destroy()
		textCount = textCount - 1
	end)
end

handlers.aura = function(d)
	local c = d.char
	if not c then return end
	if auras[c] then
		auras[c]:Destroy()
		auras[c] = nil
	end
	if d.on then
		local hrp = c:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local att = Instance.new("Attachment")
		att.Name = "SinAura"
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(d.color)
		pe.LightEmission = 1
		pe.Rate = 40
		pe.Speed = NumberRange.new(2, 6)
		pe.Acceleration = Vector3.new(0, 6, 0)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Lifetime = NumberRange.new(0.4, 0.9)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.Parent = att
		local light = Instance.new("PointLight")
		light.Color = d.color
		light.Range = 14
		light.Brightness = 2
		light.Parent = att
		att.Parent = hrp
		auras[c] = att
	end
end

function FX.play(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then warn("[Sinborn FX] " .. kind .. ": " .. tostring(err)) end
	end
end

return FX
