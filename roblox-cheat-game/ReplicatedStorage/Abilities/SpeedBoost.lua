-- Speed boost (ModuleScript in ReplicatedStorage > Abilities)
-- Multiplies your walk speed. While on, the Faster / Slower keys change
-- the multiplier. The HUD shows the current multiplier.

local Players = game:GetService("Players")

local SETTINGS = {
	DefaultMultiplier = 3,
	MinMultiplier = 1.5,
	MaxMultiplier = 10,
	Step = 0.5,
}

local SpeedBoost = {
	Name = "Speed boost",
	Description = "Walk faster. Use the Faster and Slower keys while it's on.",
	Type = "Toggle",
	Key = Enum.KeyCode.B,
	RequiredAttribute = "CanSpeedBoost",
	Binds = {
		{ Id = "Faster", Name = "Faster", Default = Enum.KeyCode.RightBracket },
		{ Id = "Slower", Name = "Slower", Default = Enum.KeyCode.LeftBracket },
	},
}

local player = Players.LocalPlayer
local ctx
local enabled = false
local multiplier = SETTINGS.DefaultMultiplier
local humanoid = nil
local baseSpeed = nil -- the WalkSpeed the game set, restored when off
local appliedSpeed = nil
local speedConnection = nil

local function showStatus()
	ctx.SetStatus(string.format("x%g", multiplier))
end

local function apply()
	if not (enabled and humanoid and baseSpeed) then
		return
	end
	appliedSpeed = baseSpeed * multiplier
	humanoid.WalkSpeed = appliedSpeed
end

local function attach(newHumanoid)
	if speedConnection then
		speedConnection:Disconnect()
	end
	humanoid = newHumanoid
	baseSpeed = humanoid.WalkSpeed
	appliedSpeed = nil

	-- If the game changes WalkSpeed while boosted (e.g. a slow effect),
	-- treat that as the new base speed and boost on top of it. The
	-- tolerance is because WalkSpeed is stored with less precision.
	speedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if appliedSpeed == nil or math.abs(humanoid.WalkSpeed - appliedSpeed) > 0.01 then
			baseSpeed = humanoid.WalkSpeed
			apply()
		end
	end)
	apply()
end

function SpeedBoost.Init(context)
	ctx = context
	showStatus()

	local function onCharacterAdded(character)
		attach(character:WaitForChild("Humanoid"))
	end
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

function SpeedBoost.Enable()
	enabled = true
	if humanoid then
		baseSpeed = humanoid.WalkSpeed
	end
	apply()
end

function SpeedBoost.Disable()
	enabled = false
	if humanoid and baseSpeed then
		appliedSpeed = nil
		humanoid.WalkSpeed = baseSpeed
	end
end

function SpeedBoost.OnBind(_, bindId)
	local delta = bindId == "Faster" and SETTINGS.Step or bindId == "Slower" and -SETTINGS.Step or 0
	multiplier = math.clamp(multiplier + delta, SETTINGS.MinMultiplier, SETTINGS.MaxMultiplier)
	apply()
	showStatus()
end

return SpeedBoost
