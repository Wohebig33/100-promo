-- SpeedBoost (LocalScript in StarterPlayer > StarterPlayerScripts)
-- B toggles the speed boost. While it's on, ] makes you faster and
-- [ makes you slower.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.B,
	FasterKey = Enum.KeyCode.RightBracket,
	SlowerKey = Enum.KeyCode.LeftBracket,
	RequiredAttribute = "CanSpeedBoost",
	DefaultMultiplier = 3,
	MinMultiplier = 1.5,
	MaxMultiplier = 10,
	MultiplierStep = 0.5,
}

local player = Players.LocalPlayer
local enabled = false
local multiplier = CONFIG.DefaultMultiplier
local humanoid = nil
local baseSpeed = nil -- the WalkSpeed the game set, restored when off
local appliedSpeed = nil
local speedConnection = nil

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Speed boost", Text = text, Duration = 2 })
	end)
end

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
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
		speedConnection = nil
	end
	humanoid = newHumanoid
	baseSpeed = humanoid.WalkSpeed
	appliedSpeed = nil

	-- If the game changes WalkSpeed while boosted (e.g. a slow effect),
	-- treat that as the new base speed and boost on top of it.
	speedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		-- Tolerance because WalkSpeed is stored with less precision than Lua numbers.
		if appliedSpeed == nil or math.abs(humanoid.WalkSpeed - appliedSpeed) > 0.01 then
			baseSpeed = humanoid.WalkSpeed
			apply()
		end
	end)
	apply()
end

local function setEnabled(on)
	if on and not hasAbility() then
		return
	end
	if on == enabled then
		return
	end
	enabled = on
	if on then
		if humanoid then
			baseSpeed = humanoid.WalkSpeed
		end
		apply()
		notify(string.format("On (x%g)", multiplier))
	else
		if humanoid and baseSpeed then
			appliedSpeed = nil
			humanoid.WalkSpeed = baseSpeed
		end
		notify("Off")
	end
end

local function changeMultiplier(delta)
	multiplier = math.clamp(multiplier + delta, CONFIG.MinMultiplier, CONFIG.MaxMultiplier)
	apply()
	notify(string.format("x%g", multiplier))
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		setEnabled(not enabled)
	elseif enabled and input.KeyCode == CONFIG.FasterKey then
		changeMultiplier(CONFIG.MultiplierStep)
	elseif enabled and input.KeyCode == CONFIG.SlowerKey then
		changeMultiplier(-CONFIG.MultiplierStep)
	end
end)

local function onCharacterAdded(character)
	attach(character:WaitForChild("Humanoid"))
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not hasAbility() then
		setEnabled(false)
	end
end)
