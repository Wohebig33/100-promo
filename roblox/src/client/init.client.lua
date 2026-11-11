-- Sinborn client: input, aiming, local movement (dashes and pulls), HUD and effects.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local plr = Players.LocalPlayer
local Root = RS:WaitForChild("Sinborn")
local C = require(Root:WaitForChild("Config"))
local Remotes = Root:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")
local StateR = Remotes:WaitForChild("State")
local FXR = Remotes:WaitForChild("FX")
local Notify = Remotes:WaitForChild("Notify")
local UI = require(script:WaitForChild("UI"))
local FX = require(script:WaitForChild("FX"))

task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then break end
		task.wait(0.5)
	end
end)

local function send(...)
	Action:FireServer(...)
end
local ui = UI.new(C, send)

-- ---------- aiming ----------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function floorFolder()
	local s = workspace:FindFirstChild("Sinborn")
	return s and s:FindFirstChild("Floor")
end
local function rootPart()
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function aimPoint()
	local hrp = rootPart()
	if not hrp then return nil end
	local fallback = hrp.Position + hrp.CFrame.LookVector * 30
	if not UIS.MouseEnabled then return fallback end
	local f = floorFolder()
	if not f then return fallback end
	rayParams.FilterDescendantsInstances = { f }
	local m = UIS:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if hit then return hit.Position end
	return fallback
end

-- ---------- local movement ----------
local function applyVelocity(getDir, speed, dur)
	local hrp = rootPart()
	if not hrp then return end
	local att = Instance.new("Attachment")
	att.Name = "SinbornMove"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 100000
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	local d = getDir()
	lv.VectorVelocity = Vector3.new(d.X, 0, d.Z) * speed
	lv.Parent = hrp
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if os.clock() - t0 > dur or not lv.Parent then
			conn:Disconnect()
			lv:Destroy()
			att:Destroy()
			return
		end
		local nd = getDir()
		if nd then lv.VectorVelocity = Vector3.new(nd.X, 0, nd.Z) * speed end
	end)
end

local dashReady = 0
local function dash()
	if os.clock() < dashReady or plr:GetAttribute("Charging") or plr:GetAttribute("Stunned") then return end
	local c = plr.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = rootPart()
	if not hum or not hrp or hum.Health <= 0 then return end
	dashReady = os.clock() + 0.75
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		local a = aimPoint()
		dir = a and (a - hrp.Position) or hrp.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, -1) end
	dir = dir.Unit
	applyVelocity(function() return dir end, 80, 0.17)
	send("dash")
end

local shakeUntil, shakeAmp = 0, 0
local function shake(a)
	shakeAmp = math.max(shakeAmp, a)
	shakeUntil = os.clock() + 0.25
end

-- ---------- input ----------
local meleeHeld = false
local nextMelee = 0
local skillKeys = {
	[Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3", [Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Z] = "Z", [Enum.KeyCode.X] = "X",
}

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not ui.openName then meleeHeld = true end
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.K then
		ui:toggle("ledger")
		return
	end
	if ui.openName then return end
	if skillKeys[kc] then
		send("skill", skillKeys[kc], aimPoint())
	elseif kc == Enum.KeyCode.Q then
		dash()
	elseif kc == Enum.KeyCode.C then
		send("charge", true)
	elseif kc == Enum.KeyCode.F then
		send("block", true)
	elseif kc == Enum.KeyCode.G then
		send("awaken")
	elseif kc == Enum.KeyCode.J then
		meleeHeld = true
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.J then
		meleeHeld = false
	elseif input.KeyCode == Enum.KeyCode.C then
		send("charge", false)
	elseif input.KeyCode == Enum.KeyCode.F then
		send("block", false)
	end
end)

ui.onSlot = function(key)
	if key == "M1" then
		send("melee", aimPoint())
	elseif key == "G" then
		send("awaken")
	else
		send("skill", key, aimPoint())
	end
end
ui.onMelee = function(on) meleeHeld = on end
ui.onDash = dash
ui.onCharge = function(on) send("charge", on) end
ui.onBlock = function(on) send("block", on) end

-- ---------- server messages ----------
local eliteModel, eliteHighlight = nil, nil
StateR.OnClientEvent:Connect(function(prof)
	ui:setProfile(prof)
end)

Notify.OnClientEvent:Connect(function(kind, d)
	d = d or {}
	if kind == "toast" then
		ui:toast(d.text, d.color)
	elseif kind == "banner" then
		ui:banner(d.main, d.sub, d.color)
	elseif kind == "cd" then
		ui:cooldown(d.id, d.dur)
	elseif kind == "spin" then
		ui:spinResult(d.tab, d.result)
	elseif kind == "open" then
		if d.what == "create" then
			ui.spinTab = "line"
			ui:open("spin", true)
		else
			ui:open(d.what)
		end
	elseif kind == "forceDash" then
		applyVelocity(function() return d.dir end, d.speed, d.dur)
	elseif kind == "pull" then
		applyVelocity(function()
			local hrp = rootPart()
			if not hrp then return nil end
			local v = d.target - hrp.Position
			v = Vector3.new(v.X, 0, v.Z)
			if v.Magnitude < 2 then return Vector3.new(0, 0, 0) end
			return v.Unit
		end, d.speed, d.dur)
	elseif kind == "death" then
		meleeHeld = false
		ui.deathInfo = d
		ui:open("death")
	elseif kind == "boss" then
		ui:boss(d)
	elseif kind == "victory" then
		ui:open("victory")
	elseif kind == "elite" then
		eliteModel = d.model
		if eliteHighlight then eliteHighlight:Destroy() end
		if eliteModel then
			eliteHighlight = Instance.new("Highlight")
			eliteHighlight.FillTransparency = 1
			eliteHighlight.OutlineColor = C.THEME.ember
			eliteHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			eliteHighlight.Parent = eliteModel
		end
	elseif kind == "shake" then
		shake(d.a or 0.3)
	end
end)

FXR.OnClientEvent:Connect(function(kind, d)
	FX.play(kind, d)
end)

-- ---------- world dressing (local only) ----------
local sigil, sigilBase
local function gateLabels()
	local p = ui.prof
	local s = workspace:FindFirstChild("Sinborn")
	local gates = s and s:FindFirstChild("Gates")
	if not p or not gates then return end
	for _, gm in ipairs(gates:GetChildren()) do
		local i = gm:GetAttribute("Gate")
		local pillar = gm:FindFirstChild("Pillar")
		local lb = pillar and pillar:FindFirstChild("GateLabel")
		local t = lb and lb:FindFirstChild("Text")
		if i and t then
			local B = C.BOSSES[i]
			if C.hasBoss(p, i) then
				t.Text = "Seal broken\n" .. B.name
				t.TextColor3 = C.THEME.ash
			else
				t.Text = C.SINS[B.sin].name .. "\n" .. B.name .. "  ·  Lv " .. B.req .. "+"
				t.TextColor3 = (p.level >= B.req) and C.SINS[B.sin].color or C.THEME.ash
			end
		end
	end
end

local chargeAtt
local function chargeFx(on)
	local hrp = rootPart()
	if on and hrp and not chargeAtt then
		chargeAtt = Instance.new("Attachment")
		chargeAtt.Position = Vector3.new(0, -2, 0)
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(C.THEME.mal)
		pe.LightEmission = 1
		pe.Rate = 50
		pe.Speed = NumberRange.new(4, 9)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.SpreadAngle = Vector2.new(25, 25)
		pe.Lifetime = NumberRange.new(0.4, 0.8)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		pe.Parent = chargeAtt
		chargeAtt.Parent = hrp
	elseif not on and chargeAtt then
		chargeAtt:Destroy()
		chargeAtt = nil
	end
end

plr.CharacterAdded:Connect(function()
	chargeAtt = nil
	meleeHeld = false
end)

local slow = 0
RunService.RenderStepped:Connect(function(dt)
	ui:update(plr)
	if meleeHeld and not ui.openName and os.clock() > nextMelee then
		nextMelee = os.clock() + 0.2
		send("melee", aimPoint())
	end
	chargeFx(plr:GetAttribute("Charging") == true)

	local c = plr.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		if os.clock() < shakeUntil then
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * shakeAmp, (math.random() - 0.5) * shakeAmp, 0)
		elseif shakeAmp > 0 then
			shakeAmp = 0
			hum.CameraOffset = Vector3.new(0, 0, 0)
		end
	end

	if not sigil then
		local s = workspace:FindFirstChild("Sinborn")
		local v = s and s:FindFirstChild("Village")
		sigil = v and v:FindFirstChild("ShrineSigil")
		if sigil then sigilBase = sigil:GetPivot() end
	elseif sigil.Parent then
		sigil:PivotTo(sigilBase * CFrame.Angles(0, os.clock() * 0.6, 0))
	end

	slow = slow + dt
	if slow > 0.2 then
		slow = 0
		if eliteModel and not eliteModel.Parent then eliteModel = nil end
		ui:updateMinimap(plr, eliteModel)
		gateLabels()
	end
end)

send("ready")
