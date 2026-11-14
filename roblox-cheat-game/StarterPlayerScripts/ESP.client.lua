-- ESP (LocalScript in StarterPlayer > StarterPlayerScripts)
-- G toggles ESP: highlights other players through walls and shows
-- name / health / distance above their heads.
-- Note: Roblox renders at most 31 Highlights at once.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.G,
	RequiredAttribute = "CanSeeESP",
	MaxDistance = 1000, -- studs
	ShowTeammates = false,
	EnemyColor = Color3.fromRGB(255, 70, 70),
	TeamColor = Color3.fromRGB(70, 170, 255),
	FillTransparency = 0.6,
}

local player = Players.LocalPlayer
local enabled = false
local tracked = {} -- [Player] = { highlight, billboard, label }

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

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
	highlight.FillTransparency = CONFIG.FillTransparency
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

RunService.Heartbeat:Connect(function()
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
			and distance <= CONFIG.MaxDistance
			and (CONFIG.ShowTeammates or not isTeammate(other))

		v.highlight.Enabled = visible
		v.billboard.Enabled = visible

		if visible then
			local color = isTeammate(other) and CONFIG.TeamColor or CONFIG.EnemyColor
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
end)

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

for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(removeVisuals)

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
