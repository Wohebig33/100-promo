-- Speed boost (ModuleScript in ReplicatedStorage > Abilities)
-- Multiplies your walk speed. Set the multiplier with the slider in the
-- ability menu, or with the Faster / Slower keys while it's on (they move
-- the slider too). The HUD shows the current multiplier.

local Players = game:GetService("Players")

local SpeedBoost = {
	Name = "Speed boost",
	Description = "Walk faster. Use the slider, or the Faster and Slower keys while it's on.",
	Type = "Toggle",
	Key = Enum.KeyCode.B,
	RequiredAttribute = "CanSpeedBoost",
	Binds = {
		{ Id = "Faster", Name = "Faster", Default = Enum.KeyCode.RightBracket },
		{ Id = "Slower", Name = "Slower", Default = Enum.KeyCode.LeftBracket },
	},
	Settings = {
		{ Id = "Multiplier", Name = "Speed", Min = 1.5, Max = 10, Step = 0.5, Default = 3, Suffix = "x" },
	},
}

local KEY_STEP = 0.5 -- how much one Faster / Slower press changes the multiplier

local player = Players.LocalPlayer
local ctx
local enabled = false
local humanoid = nil
local baseSpeed = nil -- the WalkSpeed the game set, restored when off
local appliedSpeed = nil
local speedConnection = nil

local function getMultiplier()
	return ctx.GetSetting("Multiplier") or 3
end

local function showStatus()
	ctx.SetStatus(string.format("x%g", getMultiplier()))
end

local function apply()
	if not (enabled and humanoid and baseSpeed) then
		return
	end
	appliedSpeed = baseSpeed * getMultiplier()
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

-- Faster / Slower keys: move the slider; OnSettingChanged applies it.
function SpeedBoost.OnBind(_, bindId)
	if bindId == "Faster" then
		ctx.SetSetting("Multiplier", getMultiplier() + KEY_STEP)
	elseif bindId == "Slower" then
		ctx.SetSetting("Multiplier", getMultiplier() - KEY_STEP)
	end
end

function SpeedBoost.OnSettingChanged(_, settingId)
	if settingId == "Multiplier" then
		apply()
		showStatus()
	end
end

return SpeedBoost
