-- Flight (LocalScript in StarterPlayer > StarterPlayerScripts)
-- F toggles flight. WASD moves relative to the camera, Space rises,
-- LeftControl descends, hold LeftShift to boost.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.F,
	Speed = 60,
	BoostMultiplier = 2.5,
	Acceleration = 8, -- higher = snappier start/stop
	RequiredAttribute = "CanFly",
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local flying = false
local humanoid, root
local attachment, linearVelocity, alignOrientation
local currentVelocity = Vector3.zero

local function canFly()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

local function destroyMovers()
	if linearVelocity then linearVelocity:Destroy() end
	if alignOrientation then alignOrientation:Destroy() end
	if attachment then attachment:Destroy() end
	linearVelocity, alignOrientation, attachment = nil, nil, nil
end

local function stopFlying()
	if not flying then
		return
	end
	flying = false
	destroyMovers()
	currentVelocity = Vector3.zero
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function startFlying()
	if flying or not canFly() then
		return
	end
	if not (humanoid and root and humanoid.Health > 0) then
		return
	end
	flying = true

	attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Parent = root

	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 50
	alignOrientation.CFrame = root.CFrame
	alignOrientation.Parent = root

	humanoid.PlatformStand = true
end

local function getInputDirection()
	local cf = camera.CFrame
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
	if dir.Magnitude > 0 then
		dir = dir.Unit
	end
	return dir
end

RunService.RenderStepped:Connect(function(dt)
	if not flying then
		return
	end
	if not canFly() or not (root and root.Parent) then
		stopFlying()
		return
	end

	local speed = CONFIG.Speed
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		speed *= CONFIG.BoostMultiplier
	end

	local targetVelocity = getInputDirection() * speed
	currentVelocity = currentVelocity:Lerp(targetVelocity, math.clamp(dt * CONFIG.Acceleration, 0, 1))
	linearVelocity.VectorVelocity = currentVelocity

	-- Keep the character upright, facing the camera's horizontal direction.
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		if flying then
			stopFlying()
		else
			startFlying()
		end
	end
end)

local function onCharacterAdded(character)
	stopFlying()
	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")
	humanoid.Died:Connect(stopFlying)
end

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not canFly() then
		stopFlying()
	end
end)
