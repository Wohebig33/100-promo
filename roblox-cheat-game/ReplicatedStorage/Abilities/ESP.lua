-- ESP (ModuleScript in ReplicatedStorage > Abilities)
-- Highlights other players through walls and shows their name, health
-- and distance. Roblox renders at most 31 Highlights at once.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SETTINGS = {
	MaxDistance = 1000, -- studs
	ShowTeammates = false,
	EnemyColor = Color3.fromRGB(255, 70, 70),
	TeamColor = Color3.fromRGB(70, 170, 255),
	FillTransparency = 0.6,
}

local ESP = {
	Name = "ESP",
	Description = "See other players through walls, with their name, health and distance.",
	Type = "Toggle",
	Key = Enum.KeyCode.G,
	RequiredAttribute = "CanSeeESP",
}

local player = Players.LocalPlayer
local enabled = false
local tracked = {} -- [Player] = { highlight, billboard, label }

local function isTeammate(other)
	return not player.Neutral and not other.Neutral and other.Team == player.Team
end

local function removeVisuals(other)
	local v = tracked[other]
	if v then
		v.highlight:Destroy()
		v.billboard:Destroy()
		tracked[other] = nil
	end
end

local function createVisuals(other)
	removeVisuals(other)
	local character = other.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end

	-- Created on the client, so only this player sees them.
	local highlight = Instance.new("Highlight")
	highlight.Name = "ESPHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = SETTINGS.FillTransparency
	highlight.OutlineTransparency = 0
	highlight.Adornee = character
	highlight.Enabled = false
	highlight.Parent = character

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ESPLabel"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.Enabled = false
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	tracked[other] = { highlight = highlight, billboard = billboard, label = label }
end

local function update()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	for other, v in pairs(tracked) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local distance = (myRoot and root) and (myRoot.Position - root.Position).Magnitude or 0

		local visible = enabled
			and v.highlight.Parent ~= nil
			and root ~= nil
			and hum ~= nil
			and hum.Health > 0
			and distance <= SETTINGS.MaxDistance
			and (SETTINGS.ShowTeammates or not isTeammate(other))

		v.highlight.Enabled = visible
		v.billboard.Enabled = visible

		if visible then
			local color = isTeammate(other) and SETTINGS.TeamColor or SETTINGS.EnemyColor
			v.highlight.FillColor = color
			v.highlight.OutlineColor = color
			v.label.TextColor3 = color
			v.label.Text = string.format(
				"%s\n%d HP  ·  %d studs",
				other.DisplayName,
				math.floor(hum.Health),
				math.floor(distance)
			)
		end
	end
end

local function watchPlayer(other)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		createVisuals(other)
	end)
	if other.Character then
		task.spawn(createVisuals, other)
	end
end

function ESP.Init()
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(removeVisuals)
	RunService.Heartbeat:Connect(update)
end

function ESP.Enable()
	enabled = true
end

function ESP.Disable()
	enabled = false
end

return ESP
