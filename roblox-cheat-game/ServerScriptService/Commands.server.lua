-- Commands (Script in ServerScriptService)
-- Minecraft-style chat commands. Type them into the normal chat box:
--   /kill                 kill yourself
--   /kill <player>        kill a player (partial username or display name works)
--   /kill @a              kill everyone
--   /kill @r              kill a random player
--   /kill @p              kill the nearest other player
--   /kill @s              kill yourself
--   /tp <x> <y> <z>       teleport to coordinates (~ and ~5 mean relative to you)
--   /tp <player>          teleport to a player
--   /tp <who> <player>    teleport players to a player
--   /tp <who> <x> <y> <z> teleport players to coordinates
--   /map                  open the map
--   /servers              open the server list
-- Killing or teleporting *other* players needs admin unless the
-- matching AnyoneCan... option below is true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local TeleportUtil = require(ServerScriptService:WaitForChild("TeleportUtil"))

local CONFIG = {
	AnyoneCanKillOthers = false,
	AnyoneCanTeleportOthers = false,
	-- UserIds allowed to target other players. The game's owner and anyone
	-- with the "IsAdmin" attribute are always admins. In Studio, everyone is.
	Admins = {
		-- 123456789,
	},
}

local function getRemote(className, name)
	local folder = ReplicatedStorage:FindFirstChild("CheatRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CheatRemotes"
		folder.Parent = ReplicatedStorage
	end
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	return remote
end

local feedback = getRemote("RemoteEvent", "CommandFeedback")
local openServerList = getRemote("RemoteEvent", "OpenServerList")
local openMap = getRemote("RemoteEvent", "OpenMap")

local function tell(player, text, isError)
	feedback:FireClient(player, text, isError == true)
end

local function isAdmin(player)
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if table.find(CONFIG.Admins, player.UserId) then
		return true
	end
	return player:GetAttribute("IsAdmin") == true
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function nearestOther(sender)
	local myRoot = rootOf(sender)
	if not myRoot then
		return nil
	end
	local best, bestDist = nil, math.huge
	for _, other in ipairs(Players:GetPlayers()) do
		local root = other ~= sender and rootOf(other)
		if root then
			local dist = (root.Position - myRoot.Position).Magnitude
			if dist < bestDist then
				best, bestDist = other, dist
			end
		end
	end
	return best
end

-- Returns a list of players, or nil plus an error message.
local function resolveTargets(sender, selector)
	if selector == "" or selector == "@s" then
		return { sender }
	end

	local lower = string.lower(selector)
	if lower == "@a" then
		return Players:GetPlayers()
	elseif lower == "@r" then
		local all = Players:GetPlayers()
		return { all[math.random(#all)] }
	elseif lower == "@p" then
		local nearest = nearestOther(sender)
		if not nearest then
			return nil, "No other players found."
		end
		return { nearest }
	end

	local partial = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local name, display = string.lower(other.Name), string.lower(other.DisplayName)
		if name == lower or display == lower then
			return { other }
		end
		if string.sub(name, 1, #lower) == lower or string.sub(display, 1, #lower) == lower then
			table.insert(partial, other)
		end
	end

	if #partial == 1 then
		return partial
	elseif #partial == 0 then
		return nil, string.format("No player found matching '%s'.", selector)
	end
	return nil, string.format("'%s' matches %d players. Type more of the name.", selector, #partial)
end

local function kill(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0 -- bypasses ForceFields, like Minecraft's /kill
		return true
	end
	return false
end

local function cmdKill(sender, args)
	local targets, err = resolveTargets(sender, args[1] or "")
	if not targets then
		tell(sender, err, true)
		return
	end

	if not (CONFIG.AnyoneCanKillOthers or isAdmin(sender)) then
		for _, target in ipairs(targets) do
			if target ~= sender then
				tell(sender, "You don't have permission to kill other players.", true)
				return
			end
		end
	end

	local killed = {}
	for _, target in ipairs(targets) do
		if kill(target) then
			table.insert(killed, target.DisplayName)
		end
	end

	if #killed == 0 then
		tell(sender, "No living targets found.", true)
	elseif #killed == 1 then
		tell(sender, "Killed " .. killed[1])
	else
		tell(sender, string.format("Killed %d players", #killed))
	end
end

local function cmdServers(sender)
	if sender:GetAttribute("CanServerHop") ~= true then
		tell(sender, "You can't use the server list.", true)
		return
	end
	openServerList:FireClient(sender)
end

-- /tp ---------------------------------------------------------------------

-- "10" -> 10, "~" -> base, "~5" -> base + 5
local function parseCoordinate(token, base)
	if token == "~" then
		return base
	end
	local offset = string.match(token, "^~(.+)$")
	local value = tonumber(offset or token)
	if not value then
		return nil
	end
	return offset and base + value or value
end

local function parsePosition(sender, x, y, z)
	local root = rootOf(sender)
	local base = root and root.Position or Vector3.zero
	local px = parseCoordinate(x, base.X)
	local py = parseCoordinate(y, base.Y)
	local pz = parseCoordinate(z, base.Z)
	if not (px and py and pz) then
		return nil, "Coordinates must be numbers, ~ or ~<offset>."
	end
	local position = Vector3.new(px, py, pz)
	if not TeleportUtil.isValidPosition(position) then
		return nil, "Those coordinates are out of range."
	end
	return position
end

local function resolveOne(sender, selector)
	local found, err = resolveTargets(sender, selector)
	if not found then
		return nil, err
	end
	if #found ~= 1 then
		return nil, "The destination must be a single player."
	end
	return found[1]
end

local TP_USAGE = "Usage: /tp <x> <y> <z>  |  /tp <player>  |  /tp <who> <player>  |  /tp <who> <x> <y> <z>"

local function cmdTp(sender, args)
	if sender:GetAttribute("CanTeleport") ~= true then
		tell(sender, "You can't teleport.", true)
		return
	end

	local targets, destination, err
	if #args == 1 then
		targets = { sender }
		destination, err = resolveOne(sender, args[1])
	elseif #args == 2 then
		targets, err = resolveTargets(sender, args[1])
		if targets then
			destination, err = resolveOne(sender, args[2])
		end
	elseif #args == 3 then
		targets = { sender }
		destination, err = parsePosition(sender, args[1], args[2], args[3])
	elseif #args == 4 then
		targets, err = resolveTargets(sender, args[1])
		if targets then
			destination, err = parsePosition(sender, args[2], args[3], args[4])
		end
	end
	if not (targets and destination) then
		tell(sender, err or TP_USAGE, true)
		return
	end

	if not (CONFIG.AnyoneCanTeleportOthers or isAdmin(sender)) then
		for _, target in ipairs(targets) do
			if target ~= sender then
				tell(sender, "You don't have permission to teleport other players.", true)
				return
			end
		end
	end

	local position, placeName
	if typeof(destination) == "Vector3" then
		position, placeName = destination, TeleportUtil.formatPosition(destination)
	else
		local destRoot = rootOf(destination)
		if not destRoot then
			tell(sender, destination.DisplayName .. " isn't spawned in.", true)
			return
		end
		-- Land just behind them instead of inside them.
		position = (destRoot.CFrame * CFrame.new(0, 0, 3)).Position
		placeName = destination.DisplayName
	end

	local moved, lastError = {}, nil
	for _, target in ipairs(targets) do
		if target ~= destination then
			local ok, teleportErr = TeleportUtil.teleport(target, position)
			if ok then
				table.insert(moved, target.DisplayName)
			else
				lastError = teleportErr
			end
		end
	end

	if #moved == 0 then
		tell(sender, lastError or "Nobody was teleported.", true)
	elseif #moved == 1 then
		tell(sender, string.format("Teleported %s to %s", moved[1], placeName))
	else
		tell(sender, string.format("Teleported %d players to %s", #moved, placeName))
	end
end

local function cmdMap(sender)
	if sender:GetAttribute("CanTeleport") ~= true then
		tell(sender, "You can't use the map.", true)
		return
	end
	openMap:FireClient(sender)
end

local COMMANDS = {
	kill = cmdKill,
	tp = cmdTp,
	map = cmdMap,
	servers = cmdServers,
}

local function parseArgs(text)
	local args = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(args, word)
	end
	table.remove(args, 1) -- drop the "/command" itself
	return args
end

-- TextChatCommands are intercepted before the message is sent, so the
-- command text never shows up in chat for other players.
local folder = Instance.new("Folder")
folder.Name = "CustomCommands"
folder.Parent = TextChatService

for name, handler in pairs(COMMANDS) do
	local command = Instance.new("TextChatCommand")
	command.Name = name .. "Command"
	command.PrimaryAlias = "/" .. name
	command.Parent = folder

	command.Triggered:Connect(function(textSource, text)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player then
			handler(player, parseArgs(text))
		end
	end)
end
