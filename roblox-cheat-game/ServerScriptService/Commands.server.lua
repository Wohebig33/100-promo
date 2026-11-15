-- Commands (Script in ServerScriptService)
-- Minecraft-style chat commands. Type them into the normal chat box:
--   /kill                 kill yourself
--   /kill <player>        kill a player (partial username or display name works)
--   /kill @a              kill everyone
--   /kill @r              kill a random player
--   /kill @p              kill the nearest other player
--   /kill @s              kill yourself
--   /servers              open the server list
-- Killing *other* players needs admin unless AnyoneCanKillOthers is true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local CONFIG = {
	AnyoneCanKillOthers = false,
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

local COMMANDS = {
	kill = cmdKill,
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
