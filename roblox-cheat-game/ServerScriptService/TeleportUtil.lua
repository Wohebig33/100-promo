-- TeleportUtil (ModuleScript in ServerScriptService)
-- Shared teleport helpers used by Commands (/tp) and Map (waypoints).

local Players = game:GetService("Players")

local TeleportUtil = {}

-- Physics gets unstable very far from the origin, so cap coordinates.
TeleportUtil.MaxCoordinate = 100000

function TeleportUtil.isValidNumber(n)
	return type(n) == "number" and n == n and math.abs(n) <= TeleportUtil.MaxCoordinate
end

function TeleportUtil.isValidPosition(position)
	return typeof(position) == "Vector3"
		and TeleportUtil.isValidNumber(position.X)
		and TeleportUtil.isValidNumber(position.Y)
		and TeleportUtil.isValidNumber(position.Z)
		and position.Y > workspace.FallenPartsDestroyHeight + 10
end

function TeleportUtil.formatPosition(position)
	return string.format("%.1f, %.1f, %.1f", position.X, position.Y, position.Z)
end

-- Height of the HumanoidRootPart above the floor when standing.
local function standingHeight(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2 + 0.5
	end
	return 3.5
end

-- Returns the Y of the highest surface at (x, z), or nil if there's nothing there.
function TeleportUtil.findGroundY(x, z)
	local ignore = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(Vector3.new(x, 5000, z), Vector3.new(0, -10000, 0), params)
	return result and result.Position.Y or nil
end

-- Position that puts the player standing on the ground at (x, z), or nil.
function TeleportUtil.groundPosition(player, x, z)
	local groundY = TeleportUtil.findGroundY(x, z)
	if not groundY then
		return nil
	end
	return Vector3.new(x, groundY + standingHeight(player), z)
end

-- Moves the player's character so its HumanoidRootPart is at `position`.
-- Returns true, or false plus a reason.
function TeleportUtil.teleport(player, position)
	if not TeleportUtil.isValidPosition(position) then
		return false, "Those coordinates are out of range."
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then
		return false, "Can't teleport a player who isn't alive."
	end

	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(position)
		end)
	end

	local rotation = root.CFrame - root.Position
	character:PivotTo(CFrame.new(position) * rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

return TeleportUtil
