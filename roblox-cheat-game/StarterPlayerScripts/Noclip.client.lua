-- Noclip (LocalScript in StarterPlayer > StarterPlayerScripts)
-- N toggles noclip: walk through walls and objects. You still stand on
-- floors (Humanoids detect the ground with raycasts, not collisions);
-- combine with flight (F) to move through floors and ceilings.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.N,
	RequiredAttribute = "CanNoclip",
}

local player = Players.LocalPlayer
local enabled = false
local disabledParts = {} -- parts we turned collision off on, to restore later

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Noclip", Text = text, Duration = 2 })
	end)
end

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

local function restoreCollisions()
	for part in pairs(disabledParts) do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(disabledParts)
end

local function setEnabled(on)
	if on and not hasAbility() then
		return
	end
	if on == enabled then
		return
	end
	enabled = on
	if not on then
		restoreCollisions()
	end
	notify(on and "On" or "Off")
end

-- Stepped runs right before physics, so collisions are off for every
-- physics step even if something turns them back on.
RunService.Stepped:Connect(function()
	if not enabled then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
			disabledParts[part] = true
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		setEnabled(not enabled)
	end
end)

player.CharacterAdded:Connect(function()
	-- The old character's parts are gone; stay on for the new one.
	table.clear(disabledParts)
end)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not hasAbility() then
		setEnabled(false)
	end
end)
