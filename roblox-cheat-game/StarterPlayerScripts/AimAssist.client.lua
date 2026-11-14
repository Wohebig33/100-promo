-- AimAssist (LocalScript in StarterPlayer > StarterPlayerScripts)
-- H toggles aim assist. While enabled, hold right mouse button to pull
-- the camera toward the nearest valid target inside the FOV circle
-- (measured from screen center / crosshair).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.H,
	HoldButton = Enum.UserInputType.MouseButton2,
	RequiredAttribute = "CanAimAssist",
	FOVRadius = 150, -- pixels from screen center
	Smoothness = 0.25, -- 0..1 per frame at 60 FPS; 1 = instant snap
	MaxDistance = 500, -- studs
	TargetPart = "Head", -- falls back to HumanoidRootPart
	TeamCheck = true,
	WallCheck = true,
	ShowFOVCircle = true,
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local enabled = false

-- FOV circle
local gui = Instance.new("ScreenGui")
gui.Name = "AimAssistGui"
gui.IgnoreGuiInset = true -- so scale 0.5 == viewport center
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local circle = Instance.new("Frame")
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.Position = UDim2.fromScale(0.5, 0.5)
circle.Size = UDim2.fromOffset(CONFIG.FOVRadius * 2, CONFIG.FOVRadius * 2)
circle.BackgroundTransparency = 1
circle.Visible = false
circle.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = circle

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Color = Color3.new(1, 1, 1)
stroke.Transparency = 0.3
stroke.Parent = circle

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

local function isTeammate(other)
	return not player.Neutral and not other.Neutral and other.Team == player.Team
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLineOfSight(part)
	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	rayParams.FilterDescendantsInstances = ignore

	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, part.Position - origin, rayParams)
	return result == nil or result.Instance:IsDescendantOf(part.Parent)
end

local function getBestTarget()
	local center = camera.ViewportSize / 2
	local bestPart, bestScreenDist = nil, CONFIG.FOVRadius

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not (CONFIG.TeamCheck and isTeammate(other)) then
			local character = other.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			local part = character
				and (character:FindFirstChild(CONFIG.TargetPart) or character:FindFirstChild("HumanoidRootPart"))

			if hum and hum.Health > 0 and part then
				local worldDist = (part.Position - camera.CFrame.Position).Magnitude
				if worldDist <= CONFIG.MaxDistance then
					local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
						if screenDist < bestScreenDist and (not CONFIG.WallCheck or hasLineOfSight(part)) then
							bestPart, bestScreenDist = part, screenDist
						end
					end
				end
			end
		end
	end

	return bestPart
end

-- Runs right after the default camera update so our adjustment sticks.
RunService:BindToRenderStep("AimAssist", Enum.RenderPriority.Camera.Value + 1, function(dt)
	circle.Visible = enabled and CONFIG.ShowFOVCircle

	if not enabled or not UserInputService:IsMouseButtonPressed(CONFIG.HoldButton) then
		return
	end

	local target = getBestTarget()
	if not target then
		return
	end

	local camCF = camera.CFrame
	local goal = CFrame.lookAt(camCF.Position, target.Position)
	-- Frame-rate independent smoothing.
	local alpha = 1 - (1 - CONFIG.Smoothness) ^ (dt * 60)
	camera.CFrame = camCF:Lerp(goal, alpha)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey and hasAbility() then
		enabled = not enabled
	end
end)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not hasAbility() then
		enabled = false
	end
end)
