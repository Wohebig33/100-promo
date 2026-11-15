-- Aim assist (ModuleScript in ReplicatedStorage > Abilities)
-- While on, hold the Aim key to pull the camera toward the nearest valid
-- target inside the circle in the middle of the screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SETTINGS = {
	FOVRadius = 150, -- pixels from screen center
	Smoothness = 0.25, -- 0..1 per frame at 60 FPS; 1 = instant snap
	MaxDistance = 500, -- studs
	TargetPart = "Head", -- falls back to HumanoidRootPart
	TeamCheck = true,
	WallCheck = true,
	ShowFOVCircle = true,
}

local AimAssist = {
	Name = "Aim assist",
	Description = "Hold the aim key to pull your camera toward the nearest enemy inside the circle.",
	Type = "Toggle",
	Key = Enum.KeyCode.H,
	RequiredAttribute = "CanAimAssist",
	Binds = {
		{ Id = "Aim", Name = "Hold to aim", Default = Enum.UserInputType.MouseButton2 },
	},
}

local player = Players.LocalPlayer
local ctx
local enabled = false
local circle

local function isTeammate(other)
	return not player.Neutral and not other.Neutral and other.Team == player.Team
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLineOfSight(camera, part)
	local ignore = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	rayParams.FilterDescendantsInstances = ignore

	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, part.Position - origin, rayParams)
	return result == nil or result.Instance:IsDescendantOf(part.Parent)
end

local function getBestTarget(camera)
	local center = camera.ViewportSize / 2
	local bestPart, bestScreenDist = nil, SETTINGS.FOVRadius

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not (SETTINGS.TeamCheck and isTeammate(other)) then
			local character = other.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			local part = character
				and (character:FindFirstChild(SETTINGS.TargetPart) or character:FindFirstChild("HumanoidRootPart"))

			if hum and hum.Health > 0 and part then
				local worldDist = (part.Position - camera.CFrame.Position).Magnitude
				if worldDist <= SETTINGS.MaxDistance then
					local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen then
						local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
						if screenDist < bestScreenDist and (not SETTINGS.WallCheck or hasLineOfSight(camera, part)) then
							bestPart, bestScreenDist = part, screenDist
						end
					end
				end
			end
		end
	end

	return bestPart
end

function AimAssist.Init(context)
	ctx = context

	local gui = Instance.new("ScreenGui")
	gui.Name = "AimAssistGui"
	gui.IgnoreGuiInset = true -- so scale 0.5 == viewport center
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromOffset(SETTINGS.FOVRadius * 2, SETTINGS.FOVRadius * 2)
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

	-- Runs right after the default camera update so the adjustment sticks.
	RunService:BindToRenderStep("AimAssist", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not enabled or not ctx.IsBindDown("Aim") then
			return
		end
		local camera = workspace.CurrentCamera
		local target = getBestTarget(camera)
		if not target then
			return
		end
		local camCF = camera.CFrame
		local goal = CFrame.lookAt(camCF.Position, target.Position)
		local alpha = 1 - (1 - SETTINGS.Smoothness) ^ (dt * 60) -- frame-rate independent
		camera.CFrame = camCF:Lerp(goal, alpha)
	end)
end

function AimAssist.Enable()
	enabled = true
	circle.Visible = SETTINGS.ShowFOVCircle
end

function AimAssist.Disable()
	enabled = false
	circle.Visible = false
end

return AimAssist
