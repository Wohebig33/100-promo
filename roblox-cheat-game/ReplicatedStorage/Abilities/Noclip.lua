-- Noclip (ModuleScript in ReplicatedStorage > Abilities)
-- Walk through walls and objects. You still stand on floors (Humanoids
-- find the ground with raycasts, not collisions); combine with Flight to
-- pass through floors and ceilings.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Noclip = {
	Name = "Noclip",
	Description = "Walk through walls. Turn on Flight too to go through floors.",
	Type = "Toggle",
	Key = Enum.KeyCode.N,
	RequiredAttribute = "CanNoclip",
}

local player = Players.LocalPlayer
local enabled = false
local disabledParts = {} -- parts we turned collision off on, to restore later

local function restoreCollisions()
	for part in pairs(disabledParts) do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(disabledParts)
end

function Noclip.Init()
	-- Stepped runs right before physics, so collisions stay off every step
	-- even if something turns them back on.
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

	player.CharacterAdded:Connect(function()
		table.clear(disabledParts) -- old parts are gone; stay on for the new body
	end)
end

function Noclip.Enable()
	enabled = true
end

function Noclip.Disable()
	enabled = false
	restoreCollisions()
end

return Noclip
