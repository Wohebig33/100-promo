-- Flight (ModuleScript in ReplicatedStorage > Abilities)
-- Fly where the camera points. WASD moves; Up / Down / Boost are
-- rebindable in the ability menu.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SETTINGS = {
	Speed = 60,
	BoostMultiplier = 2.5,
	Acceleration = 8, -- higher = snappier start/stop
}

local Flight = {
	Name = "Flight",
	Description = "Fly where the camera points. WASD to move.",
	Type = "Toggle",
	Key = Enum.KeyCode.F,
	RequiredAttribute = "CanFly",
	Binds = {
		{ Id = "Up", Name = "Fly up", Default = Enum.KeyCode.Space },
		{ Id = "Down", Name = "Fly down", Default = Enum.KeyCode.LeftControl },
		{ Id = "Boost", Name = "Boost", Default = Enum.KeyCode.LeftShift },
	},
}

local player = Players.LocalPlayer
local ctx
local flying = false
local humanoid, root
local attachment, linearVelocity, alignOrientation
local currentVelocity = Vector3.zero

local function destroyMovers()
	if linearVelocity then linearVelocity:Destroy() end
	if alignOrientation then alignOrientation:Destroy() end
	if attachment then attachment:Destroy() end
	linearVelocity, alignOrientation, attachment = nil, nil, nil
end

local function stop()
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

local function start()
	if flying then
		return true
	end
	if not (humanoid and root and humanoid.Health > 0) then
		return false
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
	return true
end

local function getInputDirection(camera)
	local cf = camera.CFrame
	local dir = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
	end
	if ctx.IsBindDown("Up") then dir += Vector3.yAxis end
	if ctx.IsBindDown("Down") then dir -= Vector3.yAxis end
	if dir.Magnitude > 0 then
		dir = dir.Unit
	end
	return dir
end

function Flight.Init(context)
	ctx = context

	RunService.RenderStepped:Connect(function(dt)
		if not flying then
			return
		end
		if not (root and root.Parent) then
			ctx.SetEnabled(false)
			return
		end
		local camera = workspace.CurrentCamera

		local speed = SETTINGS.Speed
		if ctx.IsBindDown("Boost") then
			speed *= SETTINGS.BoostMultiplier
		end

		local target = getInputDirection(camera) * speed
		currentVelocity = currentVelocity:Lerp(target, math.clamp(dt * SETTINGS.Acceleration, 0, 1))
		linearVelocity.VectorVelocity = currentVelocity

		-- Stay upright, facing the camera's horizontal direction.
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-3 then
			alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		end
	end)

	local function onCharacterAdded(character)
		ctx.SetEnabled(false)
		humanoid = character:WaitForChild("Humanoid")
		root = character:WaitForChild("HumanoidRootPart")
		humanoid.Died:Connect(function()
			ctx.SetEnabled(false)
		end)
	end
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

function Flight.Enable()
	return start() -- returning false tells the menu it couldn't turn on
end

function Flight.Disable()
	stop()
end

return Flight
