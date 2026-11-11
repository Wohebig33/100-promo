-- Sinborn HUD and menus, built entirely in code.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local UI = {}
UI.__index = UI

local function font(name, fallback)
	local ok, f = pcall(function() return Enum.Font[name] end)
	if ok and f then return f end
	return fallback
end
local F_DISPLAY = font("GrenzeGotisch", Enum.Font.Fantasy)
local F_BODY = Enum.Font.Gotham
local F_MED = Enum.Font.GothamMedium
local F_BOLD = Enum.Font.GothamBold
local F_MONO = font("RobotoMono", Enum.Font.Code)

local function new(class, props, children)
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then o[k] = v end
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = o end
	end
	if props and props.Parent then o.Parent = props.Parent end
	return o
end
local function corner(px) return new("UICorner", { CornerRadius = UDim.new(0, px or 3) }) end
local function stroke(color, th) return new("UIStroke", { Color = color, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(px, py)
	return new("UIPadding", { PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), PaddingTop = UDim.new(0, py or px), PaddingBottom = UDim.new(0, py or px) })
end
local function list(dir, gap, halign)
	return new("UIListLayout", { FillDirection = dir or Enum.FillDirection.Vertical, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = halign or Enum.HorizontalAlignment.Left })
end
local function hex(c) return "#" .. c:ToHex() end

function UI.new(C, send)
	local self = setmetatable({}, UI)
	self.C, self.send, self.T = C, send, C.THEME
	local T = C.THEME
	self.prof = nil
	self.cdUntil, self.cdDur = {}, {}
	self.spinning = false
	self.spinTab = "line"
	self.creation = false
	self.openName = nil

	local plr = Players.LocalPlayer
	local gui = new("ScreenGui", { Name = "SinbornUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = plr:WaitForChild("PlayerGui") })
	self.gui = gui

	local function txt(props)
		local base = { BackgroundTransparency = 1, Font = F_BODY, TextColor3 = T.bone, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center }
		for k, v in pairs(props) do base[k] = v end
		return new("TextLabel", base)
	end
	self.txt = txt
	local function btn(text, primary, props)
		local b = new("TextButton", { AutoButtonColor = true, BackgroundColor3 = primary and T.blood or T.stone2, Font = F_BOLD, TextSize = 14, TextColor3 = primary and Color3.new(1, 1, 1) or T.bone, Text = text, Size = UDim2.fromOffset(120, 34) })
		corner(2).Parent = b
		stroke(primary and C.rgb(122, 15, 25) or T.seam, 1).Parent = b
		if props then
			for k, v in pairs(props) do b[k] = v end
		end
		return b
	end
	self.btn = btn
	local function barFrame(parent, color, h, labelText)
		local bg = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h), Parent = parent }, { stroke(T.seam), corner(2) })
		local fill = new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), Parent = bg }, { corner(2) })
		local l, v
		if labelText then
			l = txt({ Text = labelText, Font = F_MONO, TextSize = 11, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromOffset(6, 0), TextStrokeTransparency = 0.5, ZIndex = 2, Parent = bg })
			v = txt({ Text = "", Font = F_MONO, TextSize = 11, Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.fromScale(0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.5, ZIndex = 2, Parent = bg })
		end
		return bg, fill, v
	end

	-- ---------- HUD ----------
	local hud = new("Frame", { Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	self.hud = hud
	local box = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(300, 140), Parent = hud }, { list(nil, 4) })
	local who = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = box })
	self.hName = txt({ Font = F_DISPLAY, TextSize = 28, Size = UDim2.new(0, 10, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = who })
	self.hRank = txt({ Font = F_BOLD, TextSize = 11, TextColor3 = T.ash, Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 4), TextXAlignment = Enum.TextXAlignment.Right, Parent = who })
	self.hLine = txt({ RichText = true, Font = F_BOLD, TextSize = 12, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = box })
	local _, hpFill, hpTxt = barFrame(box, T.hp, 16, "HP")
	hpFill.Parent.LayoutOrder = 3
	local _, malFill, malTxt = barFrame(box, T.mal, 16, "MALICE")
	malFill.Parent.LayoutOrder = 4
	local _, xpFill = barFrame(box, T.xp, 6)
	xpFill.Parent.LayoutOrder = 5
	self.hpFill, self.hpTxt, self.malFill, self.malTxt, self.xpFill = hpFill, hpTxt, malFill, malTxt, xpFill
	local trainRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 6, Parent = box }, { list(Enum.FillDirection.Horizontal, 6) })
	self.trainUi = {}
	for i, s in ipairs(C.STAT_ORDER) do
		local cell = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.25, -5, 1, 0), LayoutOrder = i, Parent = trainRow })
		local l = txt({ Font = F_MONO, TextSize = 10, TextColor3 = T.ash, Size = UDim2.new(1, 0, 0, 12), Text = C.STAT_INFO[s].short, Parent = cell })
		local bg = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 3), Parent = cell })
		local f = new("Frame", { BackgroundColor3 = T.bone, BackgroundTransparency = 0.3, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bg })
		self.trainUi[s] = { l = l, f = f }
	end

	local purse = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(200, 28), Parent = hud }, { list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) })
	local function chip(color, order)
		local f = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromOffset(10, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = purse }, { corner(2), stroke(T.seam), pad(8, 0) })
		return txt({ Font = F_MONO, TextSize = 14, TextColor3 = color, Size = UDim2.new(0, 10, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = f })
	end
	self.hSouls = chip(T.soul, 1)
	self.hSpins = chip(T.ember, 2)

	-- minimap
	local mini = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 42), Size = UDim2.fromOffset(150, 150), ClipsDescendants = true, Parent = hud }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(T.seam) })
	self.mini = mini
	local function mapPos(x, z)
		local s = 0.5 / (C.WORLD.R + 10)
		return UDim2.fromScale(0.5 + x * s, 0.5 + z * s)
	end
	self.mapPos = mapPos
	local vs = C.WORLD.villageR / (C.WORLD.R + 10)
	new("Frame", { BackgroundColor3 = T.seam, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(vs, vs), Parent = mini }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	self.gateDots = {}
	local gs = C.WORLD.arenaR / (C.WORLD.R + 10)
	for i, g in ipairs(C.GATES) do
		local col = C.SINS[C.BOSSES[i].sin].color
		local d = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = mapPos(g.x, g.z), Size = UDim2.fromScale(gs, gs), Parent = mini }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(col, 2) })
		self.gateDots[i] = d
	end
	self.enemyDots = {}
	for i = 1, 40 do
		self.enemyDots[i] = new("Frame", { BackgroundColor3 = T.hp, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 3), Visible = false, Parent = mini })
	end
	self.markDot = new("Frame", { BackgroundColor3 = T.ember, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), Visible = false, ZIndex = 3, Parent = mini }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	self.meDot = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(7, 7), ZIndex = 4, Parent = mini }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	-- mission tracker
	local mission = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Position = UDim2.fromOffset(12, 154), Size = UDim2.fromOffset(280, 10), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = hud }, { stroke(T.seam), pad(10, 7), list(nil, 2) })
	new("Frame", { BackgroundColor3 = T.ember, BorderSizePixel = 0, Position = UDim2.new(0, -10, 0, -7), Size = UDim2.new(0, 3, 1, 14), Parent = mission })
	self.mission = mission
	self.mLbl = txt({ Font = F_BOLD, TextSize = 10, TextColor3 = T.ember, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 1, Parent = mission })
	self.mTxt = txt({ TextSize = 13, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2, Parent = mission })

	-- toasts
	self.toasts = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 204), Size = UDim2.fromOffset(330, 300), Parent = hud }, { list(nil, 6, Enum.HorizontalAlignment.Right) })
	self.toastN = 0

	-- boss bar
	local bossbar = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(460, 52), Visible = false, Parent = hud })
	self.bossbar = bossbar
	self.bossName = txt({ Font = F_DISPLAY, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), TextStrokeTransparency = 0.4, Parent = bossbar })
	local bbg = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 12), Parent = bossbar }, { stroke(T.seam) })
	self.bossFill = new("Frame", { BackgroundColor3 = T.blood, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bbg })
	self.bossHp = txt({ Font = F_MONO, TextSize = 10, Size = UDim2.new(1, -6, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.4, ZIndex = 2, Parent = bbg })

	-- banner
	local banner = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(1, 0, 0, 110), Parent = hud })
	self.bannerMain = txt({ Font = F_DISPLAY, TextSize = 64, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 74), TextTransparency = 1, TextStrokeTransparency = 1, Parent = banner })
	self.bannerSub = txt({ Font = F_BOLD, TextSize = 13, TextColor3 = T.ash, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 20), TextTransparency = 1, TextStrokeTransparency = 1, Parent = banner })

	-- hint
	self.hint = txt({ Font = F_MED, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(300, 26), BackgroundTransparency = 0.25, BackgroundColor3 = Color3.new(0, 0, 0), Visible = false, Parent = hud })
	corner(2).Parent = self.hint

	-- skill bar
	self.skillbar = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(10, 64), AutomaticSize = Enum.AutomaticSize.X, Parent = hud }, { list(Enum.FillDirection.Horizontal, 6) })
	self.slots = {}

	-- touch controls
	if UIS.TouchEnabled then
		local tc = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -110, 1, -90), Size = UDim2.fromOffset(200, 150), Parent = hud })
		local function tb(text, pos, onDown, onUp)
			local b = btn(text, false, { Position = pos, Size = UDim2.fromOffset(62, 62), TextSize = 12, BackgroundTransparency = 0.2, Parent = tc })
			b.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then onDown() end
			end)
			if onUp then
				b.InputEnded:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then onUp() end
				end)
			end
		end
		tb("Strike", UDim2.fromOffset(130, 80), function() if self.onMelee then self.onMelee(true) end end, function() if self.onMelee then self.onMelee(false) end end)
		tb("Dash", UDim2.fromOffset(60, 80), function() if self.onDash then self.onDash() end end)
		tb("Charge", UDim2.fromOffset(130, 10), function() if self.onCharge then self.onCharge(true) end end, function() if self.onCharge then self.onCharge(false) end end)
		tb("Block", UDim2.fromOffset(60, 10), function() if self.onBlock then self.onBlock(true) end end, function() if self.onBlock then self.onBlock(false) end end)
		tb("Stats", UDim2.fromOffset(-10, 80), function() self:toggle("ledger") end)
	end

	-- ---------- modal shell ----------
	local dim = new("Frame", { Name = "Modal", BackgroundColor3 = C.rgb(5, 3, 4), BackgroundTransparency = 0.25, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	self.dim = dim
	local panel = new("Frame", { BackgroundColor3 = T.stone, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.9), ZIndex = 21, Parent = dim }, { stroke(T.seam, 1), new("UISizeConstraint", { MaxSize = Vector2.new(640, 680) }) })
	self.panelTitle = txt({ Font = F_DISPLAY, TextSize = 36, Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -80, 0, 40), ZIndex = 22, Parent = panel })
	self.closeBtn = new("TextButton", { BackgroundTransparency = 1, Text = "×", Font = F_BOLD, TextSize = 28, TextColor3 = T.ash, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(36, 36), ZIndex = 22, Parent = panel })
	self.closeBtn.MouseButton1Click:Connect(function()
		if not self.spinning then self:close() end
	end)
	self.body = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(22, 60), Size = UDim2.new(1, -44, 1, -76), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = T.seam, ZIndex = 22, Parent = panel })

	return self
end

-- ---------- modal helpers ----------
function UI:clearBody()
	for _, c in ipairs(self.body:GetChildren()) do c:Destroy() end
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = self.body
	self.order = 0
end
function UI:add(inst)
	self.order = self.order + 1
	inst.LayoutOrder = self.order
	inst.ZIndex = 22
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = 23 end
	end
	inst.Parent = self.body
	return inst
end
function UI:para(text, color, size)
	return self:add(self.txt({ Text = text, TextColor3 = color or self.T.ash, TextSize = size or 14, TextWrapped = true, Size = UDim2.new(1, -8, 0, 10), AutomaticSize = Enum.AutomaticSize.Y, RichText = true }))
end
function UI:heading(text)
	return self:add(self.txt({ Text = string.upper(text), Font = F_BOLD, TextColor3 = self.T.ash, TextSize = 11, Size = UDim2.new(1, 0, 0, 24), TextYAlignment = Enum.TextYAlignment.Bottom }))
end
function UI:row(h)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, -8, 0, h or 36)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 8)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	return f
end
function UI:card(h)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = self.T.stone2
	f.Size = UDim2.new(1, -8, 0, h or 60)
	local s = Instance.new("UIStroke")
	s.Color = self.T.seam
	s.Parent = f
	return f
end

function UI:open(name, creation)
	self.openName = name
	self.creation = creation == true
	self.dim.Visible = true
	self.closeBtn.Visible = not self.creation
	self:render()
end
function UI:close()
	self.openName = nil
	self.creation = false
	self.dim.Visible = false
end
function UI:toggle(name)
	if self.openName == name then self:close() else self:open(name) end
end

function UI:render()
	if not self.openName or not self.prof then return end
	self:clearBody()
	local n = self.openName
	if n == "spin" then self:renderSpin()
	elseif n == "ledger" then self:renderLedger()
	elseif n == "board" then self:renderBoard()
	elseif n == "shop" then self:renderShop()
	elseif n == "death" then self:renderDeath()
	elseif n == "victory" then self:renderVictory() end
	for _, d in ipairs(self.body:GetDescendants()) do
		if d:IsA("GuiObject") and d.ZIndex < 23 then d.ZIndex = 23 end
	end
end

-- ---------- spin ----------
function UI:renderSpin()
	local C, T, p = self.C, self.T, self.prof
	self.panelTitle.Text = "Shrine of the Heptagram"
	self:para("Each spin replaces what you carry. Store a bloodline in the Reliquary before you gamble it away.")
	local tabs = self:add(self:row(34))
	for i, t in ipairs({ { "line", "Bloodline" }, { "aff", "Affinity" } }) do
		local b = self.btn(t[2], self.spinTab == t[1], { Size = UDim2.fromOffset(120, 30), LayoutOrder = i, Parent = tabs })
		b.MouseButton1Click:Connect(function()
			if self.spinning then return end
			self.spinTab = t[1]
			self:render()
		end)
	end
	local reel = self:add(Instance.new("Frame"))
	reel.BackgroundColor3 = C.rgb(20, 12, 14)
	reel.Size = UDim2.new(1, -8, 0, 140)
	local rs = Instance.new("UIStroke")
	rs.Color = T.seam
	rs.Parent = reel
	self.reel = reel
	self.reelRar = self.txt({ Font = F_BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 14), Parent = reel })
	self.reelName = self.txt({ Font = F_DISPLAY, TextSize = 56, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, 32), Parent = reel })
	self.reelPassive = self.txt({ TextSize = 12, TextColor3 = T.ash, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 92), Parent = reel })
	if not self.spinning then
		local isLine = self.spinTab == "line"
		local def = isLine and C.SINS[p.sin] or C.AFFS[p.aff]
		self:setReel(def, (isLine and ("Bloodline of " .. def.name) or (def.name .. " affinity")) .. ". " .. def.passive)
	end
	local controls = self:add(self:row(38))
	self.txt({ Font = F_MONO, TextSize = 12, TextColor3 = T.ash, Size = UDim2.fromOffset(220, 30), LayoutOrder = 1, Text = p.spins .. " spin" .. (p.spins == 1 and "" or "s") .. " left" .. (self.spinTab == "line" and ("  ·  pity " .. p.pity .. "/" .. C.PITY) or ""), Parent = controls })
	local sb = self.btn(p.spins > 0 and "Spin (1)" or "No spins", true, { LayoutOrder = 2, Parent = controls })
	sb.Active = p.spins > 0 and not self.spinning
	sb.AutoButtonColor = sb.Active
	if not sb.Active then sb.BackgroundTransparency = 0.5 end
	sb.MouseButton1Click:Connect(function()
		if self.spinning or self.prof.spins <= 0 then return end
		self.spinning = true
		self.animating = false
		self.send("spin", self.spinTab)
		self:render()
		task.delay(3, function()
			if self.spinning and not self.animating then
				self.spinning = false
				self:render()
			end
		end)
	end)
	local db = self.btn(self.creation and "Enter the Pit" or "Done", false, { LayoutOrder = 3, Size = UDim2.fromOffset(140, 34), Parent = controls })
	db.MouseButton1Click:Connect(function()
		if self.spinning then return end
		if self.creation then self.send("enter") end
		self:close()
	end)

	self:heading("Odds")
	local isLine = self.spinTab == "line"
	local order = isLine and C.SIN_ORDER or C.AFF_ORDER
	local tbl = isLine and C.SINS or C.AFFS
	local tot = 0
	for _, k in ipairs(order) do tot = tot + tbl[k].w end
	local grid = self:add(Instance.new("Frame"))
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 10)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -6, 0, 22)
	gl.CellPadding = UDim2.fromOffset(8, 4)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i, k in ipairs(order) do
		local d = tbl[k]
		local r = C.RARITY[d.rarity]
		self.txt({ RichText = true, TextSize = 13, LayoutOrder = i, Text = string.format('<b><font color="%s">%s</font></b>  <font color="%s">%d%% %s</font>', hex(d.color), d.name, hex(r.color), math.floor(100 * d.w / tot + 0.5), r.name), Parent = grid })
	end

	if isLine then
		self:heading("Reliquary")
		local slots = self:add(self:row(96))
		for i = 1, 2 do
			local s = p.slots[i]
			local card = self:card(92)
			card.Size = UDim2.new(0.5, -8, 0, 92)
			card.LayoutOrder = i
			card.Parent = slots
			self.txt({ Font = F_MONO, TextSize = 11, TextColor3 = T.ash, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 14), Text = "Slot " .. i .. (s == "" and " · empty" or ""), Parent = card })
			if s ~= "" and C.SINS[s] then
				self.txt({ Font = F_DISPLAY, TextSize = 26, TextColor3 = C.SINS[s].color, Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 28), Text = C.SINS[s].name, Parent = card })
				local eq = self.btn("Equip", false, { Position = UDim2.fromOffset(10, 56), Size = UDim2.fromOffset(80, 28), TextSize = 12, Parent = card })
				eq.MouseButton1Click:Connect(function() if not self.spinning then self.send("slot", "equip", i) end end)
				local rl = self.btn("Release", false, { Position = UDim2.fromOffset(98, 56), Size = UDim2.fromOffset(80, 28), TextSize = 12, Parent = card })
				rl.MouseButton1Click:Connect(function() if not self.spinning then self.send("slot", "release", i) end end)
			else
				local st = self.btn("Store " .. C.SINS[p.sin].name, false, { Position = UDim2.fromOffset(10, 52), Size = UDim2.fromOffset(150, 30), TextSize = 12, Parent = card })
				st.MouseButton1Click:Connect(function() if not self.spinning then self.send("slot", "store", i) end end)
			end
		end
	end
end

function UI:setReel(def, sub)
	if not self.reelName or not self.reelName.Parent then return end
	local r = self.C.RARITY[def.rarity]
	self.reelRar.Text = string.upper(r.name)
	self.reelRar.TextColor3 = r.color
	self.reelName.Text = def.name
	self.reelName.TextColor3 = def.color
	self.reelPassive.Text = sub or ""
end

function UI:spinResult(tab, result)
	local C = self.C
	local isLine = tab == "line"
	local order = isLine and C.SIN_ORDER or C.AFF_ORDER
	local tbl = isLine and C.SINS or C.AFFS
	self.spinning = true
	self.animating = true
	task.spawn(function()
		for step = 1, 22 do
			self:setReel(tbl[C.weightedPick(order, tbl)], "")
			task.wait(0.04 + step * step * 0.0003)
		end
		local def = tbl[result]
		self:setReel(def, (isLine and ("Bloodline of " .. def.name) or (def.name .. " affinity")) .. ". " .. def.passive)
		if self.reel and self.reel.Parent then
			self.reel.BackgroundColor3 = C.RARITY[def.rarity].color
			TweenService:Create(self.reel, TweenInfo.new(0.9), { BackgroundColor3 = C.rgb(20, 12, 14) }):Play()
		end
		self.spinning = false
		self.animating = false
		if self.openName == "spin" then
			local keepReel = def
			self:render()
			self:setReel(keepReel, (isLine and ("Bloodline of " .. keepReel.name) or (keepReel.name .. " affinity")) .. ". " .. keepReel.passive)
		end
		self:buildSkillbar()
	end)
end

-- ---------- ledger ----------
function UI:renderLedger()
	local C, T, p = self.C, self.T, self.prof
	local sd = C.SINS[p.sin]
	self.panelTitle.Text = p.name
	self:para(string.format('<font color="%s">%s</font> (<font color="%s">%s</font>) · <font color="%s">%s</font> · %s · Lv %d · %d kills', hex(sd.color), sd.name, hex(C.RARITY[sd.rarity].color), C.RARITY[sd.rarity].name, hex(C.AFFS[p.aff].color), C.AFFS[p.aff].name, C.rankName(p.level), p.level, p.kills), T.bone, 13)
	self:para(sd.passive, T.ash, 13)
	self:heading("Stats" .. (p.points > 0 and ("  ·  " .. p.points .. " points to spend") or ""))
	local grid = self:add(Instance.new("Frame"))
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 10)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -6, 0, 104)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i, s in ipairs(C.STAT_ORDER) do
		local info = C.STAT_INFO[s]
		local card = self:card(104)
		card.LayoutOrder = i
		card.Parent = grid
		local bonus = sd.bonus[s] and string.format(' <font color="%s" size="11">×%s</font>', hex(sd.color), tostring(sd.bonus[s])) or ""
		self.txt({ RichText = true, Font = F_BOLD, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -60, 0, 20), Text = info.name .. bonus, Parent = card })
		self.txt({ Font = F_MONO, TextSize = 20, Position = UDim2.new(1, -60, 0, 4), Size = UDim2.fromOffset(50, 24), TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(p.stats[s]), Parent = card })
		self.txt({ TextSize = 11, TextColor3 = T.ash, TextWrapped = true, Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 28), TextYAlignment = Enum.TextYAlignment.Top, Text = info.d, Parent = card })
		self.txt({ Font = F_MONO, TextSize = 11, TextColor3 = T.ash, Position = UDim2.fromOffset(10, 56), Size = UDim2.new(1, -20, 0, 14), Text = "Training " .. math.floor(p.train[s]) .. "/" .. C.trainNeed(p, s), Parent = card })
		for j, n in ipairs({ 1, 5 }) do
			local b = self.btn("+" .. n, false, { Position = UDim2.fromOffset(10 + (j - 1) * 58, 72), Size = UDim2.fromOffset(50, 26), TextSize = 12, Parent = card })
			if p.points < n then
				b.BackgroundTransparency = 0.6
				b.AutoButtonColor = false
			end
			b.MouseButton1Click:Connect(function()
				if self.prof.points >= n then self.send("stat", s, n) end
			end)
		end
	end
	self:heading("Skill tree")
	for _, sk in ipairs(C.currentSkills(p)) do
		local card = self:add(self:card(58))
		local locked = p.level < sk.u
		local m = C.mastery(p, sk.id)
		local uses = p.mastery[sk.id] or 0
		self.txt({ Font = F_MONO, TextSize = 13, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 24, 1, 0), Text = sk.key, Parent = card })
		self.txt({ Font = F_BOLD, TextColor3 = locked and T.ash or sk.color, Position = UDim2.fromOffset(40, 8), Size = UDim2.new(1, -190, 0, 18), Text = sk.name, Parent = card })
		self.txt({ TextSize = 11, TextColor3 = T.ash, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(40, 27), Size = UDim2.new(1, -190, 0, 28), Text = sk.desc, Parent = card })
		local right
		if locked then
			right = "Unlocks Lv " .. sk.u
		else
			local next = C.MAST[m + 1]
			right = '<font color="' .. hex(T.ember) .. '">Mastery ' .. m .. "/5</font>\n" .. (next and (uses .. "/" .. next .. " uses") or "Mastered")
		end
		self.txt({ RichText = true, Font = F_MONO, TextSize = 11, TextColor3 = T.ash, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(140, 50), Text = right .. "\n" .. sk.cost .. " MAL · " .. sk.cd .. "s", Parent = card })
	end
	self:heading("Seals of the Hollow Princes")
	local seals = self:add(self:row(46))
	for i, b in ipairs(C.BOSSES) do
		local done = C.hasBoss(p, i)
		local col = C.SINS[b.sin].color
		local f = Instance.new("TextLabel")
		f.Size = UDim2.fromOffset(44, 44)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = done and 0.5 or 1
		f.Font = F_DISPLAY
		f.TextSize = 22
		f.Text = string.sub(C.SINS[b.sin].name, 1, 1)
		f.TextColor3 = done and col or T.seam
		f.LayoutOrder = i
		local s = Instance.new("UIStroke")
		s.Color = done and col or T.seam
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		f.Parent = seals
	end
end

-- ---------- board ----------
function UI:missionCard(m, active)
	local C, T = self.C, self.T
	local card = self:add(self:card(58))
	self.txt({ Font = F_DISPLAY, TextSize = 34, TextColor3 = C.RANK_COLORS[m.rank], TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 40, 1, 0), Text = C.RANK_LETTERS[m.rank], Parent = card })
	self.txt({ Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -170, 0, 20), TextWrapped = true, Text = m.text, Parent = card })
	local reward = m.xp .. " XP · " .. m.souls .. " souls" .. (m.spin > 0 and " · 1 spin" or "")
	if active then reward = m.prog .. "/" .. m.n .. " · " .. reward end
	self.txt({ Font = F_MONO, TextSize = 11, TextColor3 = T.ash, Position = UDim2.fromOffset(54, 30), Size = UDim2.new(1, -170, 0, 18), Text = reward, Parent = card })
	local b = self.btn(active and "Abandon" or "Accept", not active, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 30), TextSize = 12, Parent = card })
	if not active and self.prof.mission then
		b.BackgroundTransparency = 0.6
		b.AutoButtonColor = false
	end
	b.MouseButton1Click:Connect(function()
		if active then
			self.send("abandon")
		elseif not self.prof.mission then
			self.send("accept", m.id)
			self:close()
		end
	end)
end

function UI:renderBoard()
	local p = self.prof
	self.panelTitle.Text = "Board of Penance"
	self:para("One mission at a time. Rewards scale with rank. A and S rank always pay a spin.")
	if p.mission then
		self:heading("Active")
		self:missionCard(p.mission, true)
	end
	self:heading("Posted")
	for _, m in ipairs(p.board or {}) do self:missionCard(m, false) end
	if not p.board or #p.board == 0 then self:para("No postings. Come back after your current mission.") end
end

-- ---------- shop ----------
function UI:renderShop()
	local p, T = self.prof, self.T
	self.panelTitle.Text = "The Ferryman"
	self:para('"Souls for passage, souls for chance. The price climbs with every coin you spend."')
	self:para("You carry " .. p.souls .. " souls", T.soul, 13)
	local sp = 300 + p.spinsBought * 100
	local items = {
		{ "spin", "Heptagram Spin", "One spin at the Shrine, for bloodline or affinity.", sp },
		{ "spin5", "Bundle of five spins", "Five spins. Raises the single-spin price by five steps.", math.floor((sp * 5 + 1000) * 0.85) },
		{ "elixir", "Elixir of Blood", "Fully restores HP and Malice.", 40 + p.level * 6 },
		{ "reroll", "Fresh postings", "Replaces the missions on the Board of Penance.", 30 + p.level * 3 },
	}
	for _, it in ipairs(items) do
		local card = self:add(self:card(56))
		self.txt({ Font = F_BOLD, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -150, 0, 18), Text = it[2], Parent = card })
		self.txt({ TextSize = 12, TextColor3 = T.ash, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -150, 0, 18), TextWrapped = true, Text = it[3], Parent = card })
		local b = self.btn(it[4] .. " souls", true, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 30), TextSize = 12, Parent = card })
		if p.souls < it[4] then
			b.BackgroundTransparency = 0.6
			b.AutoButtonColor = false
		end
		b.MouseButton1Click:Connect(function()
			if self.prof.souls >= it[4] then self.send("buy", it[1]) end
		end)
	end
end

-- ---------- death / victory ----------
function UI:renderDeath()
	self.panelTitle.Text = "Claimed"
	local d = self.deathInfo or { lost = 0 }
	self:para("The Pit took " .. d.lost .. " souls" .. (d.mission and " and your mission is lost" or "") .. ". Your bloodline, levels and stats remain. You will rise in Limbo.", self.T.bone, 15)
	local b = self:add(self.btn("Rise again", true, { Size = UDim2.fromOffset(160, 36) }))
	b.MouseButton1Click:Connect(function() self:close() end)
end
function UI:renderVictory()
	self.panelTitle.Text = "Sin Lord"
	self:para("All seven seals are broken. The Pit kneels to you. Keep hunting, spin for the rarest blood, and push your stats higher.", self.T.bone, 15)
	local b = self:add(self.btn("Continue", true, { Size = UDim2.fromOffset(160, 36) }))
	b.MouseButton1Click:Connect(function() self:close() end)
end

-- ---------- HUD updates ----------
function UI:setProfile(p)
	local first = self.prof == nil
	local changedLine = (not self.prof) or self.prof.sin ~= p.sin or self.prof.aff ~= p.aff or self.prof.level ~= p.level
	self.prof = p
	self.hud.Visible = true
	if first or changedLine then self:buildSkillbar() end
	local C, T = self.C, self.T
	local sd = C.SINS[p.sin]
	local ad = C.AFFS[p.aff]
	self.hName.Text = p.name
	self.hName.TextColor3 = sd.color
	self.hRank.Text = string.upper(C.rankName(p.level)) .. " · LV " .. p.level
	self.hLine.Text = string.format('<font color="%s">%s</font> <font color="%s">%s</font> · <font color="%s">%s</font>', hex(sd.color), sd.name, hex(C.RARITY[sd.rarity].color), C.RARITY[sd.rarity].name, hex(ad.color), ad.name)
	self.xpFill.Size = UDim2.fromScale(p.level >= C.LEVEL_CAP and 1 or math.clamp(p.xp / C.xpNeed(p.level), 0, 1), 1)
	self.hSouls.Text = "Souls " .. p.souls
	self.hSpins.Text = "Spins " .. p.spins
	for _, s in ipairs(C.STAT_ORDER) do
		local u = self.trainUi[s]
		u.l.Text = C.STAT_INFO[s].short .. " " .. math.floor(C.eff(p, s) + 0.5)
		u.f.Size = UDim2.fromScale(math.clamp(p.train[s] / C.trainNeed(p, s), 0, 1), 1)
	end
	if p.mission then
		self.mission.Visible = true
		self.mLbl.Text = C.RANK_LETTERS[p.mission.rank] .. "-RANK MISSION"
		self.mLbl.TextColor3 = C.RANK_COLORS[p.mission.rank]
		self.mTxt.Text = p.mission.text .. " (" .. p.mission.prog .. "/" .. p.mission.n .. ")"
	else
		self.mission.Visible = false
	end
	for i, d in ipairs(self.gateDots) do
		local st = d:FindFirstChildOfClass("UIStroke")
		if st then st.Color = C.hasBoss(p, i) and T.seam or C.SINS[C.BOSSES[i].sin].color end
	end
	if self.openName and not self.spinning then self:render() end
end

function UI:buildSkillbar()
	local C, T, p = self.C, self.T, self.prof
	if not p then return end
	for _, c in ipairs(self.skillbar:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	self.slots = {}
	local small = self.gui.AbsoluteSize.X < 700
	local w, h = small and 44 or 58, small and 52 or 64
	local function mk(order, key, glyph, name, color, id, cost, unlock)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = Color3.new(0, 0, 0)
		b.BackgroundTransparency = 0.2
		b.Size = UDim2.fromOffset(w, h)
		b.LayoutOrder = order
		b.ClipsDescendants = true
		local s = Instance.new("UIStroke")
		s.Color = T.seam
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = b
		self.txt({ Font = F_MONO, TextSize = 10, TextColor3 = T.ash, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(20, 12), Text = key, Parent = b })
		if cost then self.txt({ Font = F_MONO, TextSize = 9, TextColor3 = C.rgb(167, 119, 255), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 0, 3), Size = UDim2.fromOffset(24, 12), TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(cost), Parent = b }) end
		self.txt({ Font = F_DISPLAY, TextSize = small and 20 or 24, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, small and 12 or 14), Size = UDim2.new(1, 0, 0, 24), Text = glyph, Parent = b })
		if not small then self.txt({ TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Position = UDim2.new(0, 2, 1, -22), Size = UDim2.new(1, -4, 0, 20), Text = name, Parent = b }) end
		local cd = Instance.new("Frame")
		cd.BackgroundColor3 = Color3.new(0, 0, 0)
		cd.BackgroundTransparency = 0.3
		cd.BorderSizePixel = 0
		cd.AnchorPoint = Vector2.new(0, 1)
		cd.Position = UDim2.fromScale(0, 1)
		cd.Size = UDim2.fromScale(1, 0)
		cd.ZIndex = 2
		cd.Parent = b
		local cdt = self.txt({ Font = F_MONO, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 0.4, ZIndex = 3, Text = "", Parent = b })
		b.Parent = self.skillbar
		local slot = { b = b, stroke = s, cd = cd, cdt = cdt, id = id, unlock = unlock, color = color, key = key }
		self.slots[#self.slots + 1] = slot
		b.MouseButton1Click:Connect(function()
			if self.onSlot then self.onSlot(key) end
		end)
		return slot
	end
	mk(0, "M1", "St", "Strike", T.bone, nil, nil, 1)
	for i, sk in ipairs(C.currentSkills(p)) do
		local words = {}
		for w2 in string.gmatch(sk.name, "[%a]+") do words[#words + 1] = string.sub(w2, 1, 1) end
		mk(i, sk.key, table.concat(words, "", 1, math.min(2, #words)), sk.name, sk.color, sk.id, sk.cost, sk.u)
	end
	mk(10, "G", "Aw", "Awaken", C.SINS[p.sin].color, "awaken", nil, 12)
end

function UI:cooldown(id, dur)
	self.cdUntil[id] = os.clock() + dur
	self.cdDur[id] = dur
end

function UI:update(player)
	local p = self.prof
	if not p then return end
	local C, T = self.C, self.T
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local mh = math.max(1, hum.MaxHealth)
		self.hpFill.Size = UDim2.fromScale(math.clamp(hum.Health / mh, 0, 1), 1)
		local sh = player:GetAttribute("Shield") or 0
		self.hpTxt.Text = math.ceil(math.max(0, hum.Health)) .. "/" .. math.floor(mh) .. (sh > 0 and (" +" .. sh) or "")
	end
	local mal = player:GetAttribute("Malice") or 0
	local mm = player:GetAttribute("MaxMalice") or 100
	self.malFill.Size = UDim2.fromScale(math.clamp(mal / math.max(1, mm), 0, 1), 1)
	self.malTxt.Text = mal .. "/" .. mm
	local now = os.clock()
	for _, s in ipairs(self.slots) do
		local locked = p.level < (s.unlock or 1)
		local frac, label = 0, ""
		if s.id == "awaken" then
			local cdl = player:GetAttribute("AwakenCd") or 0
			if player:GetAttribute("Awakened") then
				label = tostring(math.ceil(player:GetAttribute("AwakenLeft") or 0))
			elseif cdl > 0 then
				frac = cdl / 45
				label = tostring(math.ceil(cdl))
			end
		elseif s.id then
			local u = self.cdUntil[s.id]
			if u and u > now then
				frac = (u - now) / math.max(0.01, self.cdDur[s.id])
				local left = u - now
				label = left < 1 and string.format("%.1f", left) or tostring(math.ceil(left))
			end
		end
		if locked then
			frac = 1
			label = "Lv" .. s.unlock
		end
		s.cd.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1))
		s.cdt.Text = label
		s.stroke.Color = (not locked and frac <= 0) and s.color or T.seam
	end
	if mal < 20 and not player:GetAttribute("Charging") and char and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position.Magnitude > C.WORLD.villageR then
		self.hint.Visible = true
		self.hint.Text = "Hold C to charge Malice"
	else
		self.hint.Visible = false
	end
end

function UI:updateMinimap(player, elite)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then self.meDot.Position = self.mapPos(hrp.Position.X, hrp.Position.Z) end
	local folder = workspace:FindFirstChild("Sinborn")
	folder = folder and folder:FindFirstChild("Enemies")
	local i = 0
	self.markDot.Visible = false
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local pp = m:IsA("Model") and m.PrimaryPart
			if pp then
				if m.Name == "Boss" or m.Name == "Elite" then
					if m == elite or m.Name == "Boss" then
						self.markDot.Visible = true
						self.markDot.Position = self.mapPos(pp.Position.X, pp.Position.Z)
					end
				elseif i < #self.enemyDots then
					i = i + 1
					local d = self.enemyDots[i]
					d.Visible = true
					d.Position = self.mapPos(pp.Position.X, pp.Position.Z)
				end
			end
		end
	end
	for j = i + 1, #self.enemyDots do self.enemyDots[j].Visible = false end
end

function UI:toast(text, color)
	self.toastN = self.toastN + 1
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 0.2
	f.Size = UDim2.fromOffset(10, 10)
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.LayoutOrder = -self.toastN
	local s = Instance.new("UIStroke")
	s.Color = self.T.seam
	s.Parent = f
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 12)
	p.PaddingTop = UDim.new(0, 7)
	p.PaddingBottom = UDim.new(0, 7)
	p.Parent = f
	local edge = Instance.new("Frame")
	edge.BackgroundColor3 = color or self.T.blood
	edge.BorderSizePixel = 0
	edge.AnchorPoint = Vector2.new(1, 0)
	edge.Position = UDim2.new(1, 12, 0, -7)
	edge.Size = UDim2.new(0, 3, 1, 14)
	edge.Parent = f
	local t = self.txt({ TextSize = 13, Text = text, TextWrapped = true, Size = UDim2.fromOffset(10, 16), AutomaticSize = Enum.AutomaticSize.XY, Parent = f })
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = Vector2.new(300, 200)
	c.Parent = t
	f.Parent = self.toasts
	local kids = {}
	for _, k in ipairs(self.toasts:GetChildren()) do
		if k:IsA("Frame") then kids[#kids + 1] = k end
	end
	if #kids > 5 then
		table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for idx = 6, #kids do kids[idx]:Destroy() end
	end
	task.delay(3.4, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			f:Destroy()
		end
	end)
end

function UI:banner(main, sub, color)
	self.bannerN = (self.bannerN or 0) + 1
	local n = self.bannerN
	self.bannerMain.Text = main
	self.bannerMain.TextColor3 = color or self.T.bone
	self.bannerSub.Text = string.upper(sub or "")
	for _, l in ipairs({ self.bannerMain, self.bannerSub }) do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.5
	end
	task.delay(2.6, function()
		if self.bannerN ~= n then return end
		for _, l in ipairs({ self.bannerMain, self.bannerSub }) do
			TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function UI:boss(d)
	if not d.show then
		self.bossbar.Visible = false
		return
	end
	self.bossbar.Visible = true
	if d.name then self.bossName.Text = d.name end
	if d.color then
		self.bossName.TextColor3 = d.color
		self.bossFill.BackgroundColor3 = d.color
	end
	self.bossFill.Size = UDim2.fromScale(math.clamp(d.frac or 1, 0, 1), 1)
	self.bossHp.Text = tostring(d.hp or "")
end

return UI
