-- ServerList (Script in ServerScriptService)
-- Every running server registers itself in a MemoryStore sorted map and
-- refreshes the entry on a heartbeat. Clients ask for the list and pick a
-- server to teleport to.
--
-- Requirements:
--   * The place must be published.
--   * To test the list in Studio: Game Settings > Security >
--     "Enable Studio Access to API Services".
--   * Teleporting only works in a live game, not in Studio.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local CONFIG = {
	MapName = "ServerList_v1",
	HeartbeatInterval = 15, -- seconds between registry updates
	EntryLifetime = 45, -- dead servers drop off after this many seconds
	CacheSeconds = 5, -- how long a fetched list is reused
	MaxServers = 100,
	JoinCooldown = 5, -- seconds between join attempts per player
	RequiredAttribute = "CanServerHop",
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
local getServerList = getRemote("RemoteFunction", "GetServerList")
local joinServer = getRemote("RemoteEvent", "JoinServer")

local isStudio = RunService:IsStudio()
local isPrivateServer = game.PrivateServerId ~= ""
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
local map = MemoryStoreService:GetSortedMap(CONFIG.MapName)

local function tell(player, text, isError)
	feedback:FireClient(player, text, isError == true)
end

local function hasAbility(player)
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

-- Registry -------------------------------------------------------------

local function publish()
	if isPrivateServer then
		return -- don't advertise private/reserved servers
	end
	local ok, err = pcall(function()
		map:SetAsync(jobId, {
			players = #Players:GetPlayers(),
			maxPlayers = Players.MaxPlayers,
			updated = os.time(),
		}, CONFIG.EntryLifetime)
	end)
	if not ok then
		warn("[ServerList] Could not publish this server:", err)
	end
end

task.spawn(function()
	while true do
		publish()
		task.wait(CONFIG.HeartbeatInterval)
	end
end)

game:BindToClose(function()
	pcall(function()
		map:RemoveAsync(jobId)
	end)
end)

-- Reading the list -----------------------------------------------------

local cachedOthers, cacheTime = {}, -math.huge

local function fetchOtherServers()
	if os.clock() - cacheTime < CONFIG.CacheSeconds then
		return cachedOthers
	end

	local ok, entries = pcall(function()
		return map:GetRangeAsync(Enum.SortDirection.Ascending, CONFIG.MaxServers)
	end)
	if not ok then
		warn("[ServerList] Could not read server list:", entries)
		return cachedOthers
	end

	local others = {}
	for _, entry in ipairs(entries) do
		local value = entry.value
		if entry.key ~= jobId and type(value) == "table" then
			table.insert(others, {
				jobId = entry.key,
				players = tonumber(value.players) or 0,
				maxPlayers = tonumber(value.maxPlayers) or 0,
				isCurrent = false,
			})
		end
	end
	table.sort(others, function(a, b)
		return a.players > b.players
	end)

	cachedOthers, cacheTime = others, os.clock()
	return others
end

local function buildList()
	local list = {
		{
			jobId = jobId,
			players = #Players:GetPlayers(),
			maxPlayers = Players.MaxPlayers,
			isCurrent = true,
		},
	}
	for _, server in ipairs(fetchOtherServers()) do
		table.insert(list, server)
	end
	return list
end

getServerList.OnServerInvoke = function(player)
	if not hasAbility(player) then
		return { ok = false, error = "You can't use the server list." }
	end
	return { ok = true, servers = buildList(), isStudio = isStudio }
end

-- Joining --------------------------------------------------------------

local lastJoin = {}

joinServer.OnServerEvent:Connect(function(player, targetJobId)
	if type(targetJobId) ~= "string" or #targetJobId > 64 then
		return
	end
	if not hasAbility(player) then
		tell(player, "You can't use the server list.", true)
		return
	end
	if targetJobId == jobId then
		tell(player, "You're already in that server.", true)
		return
	end

	local now = os.clock()
	if lastJoin[player] and now - lastJoin[player] < CONFIG.JoinCooldown then
		tell(player, "Slow down, try again in a few seconds.", true)
		return
	end
	lastJoin[player] = now

	if isStudio then
		tell(player, "Teleporting only works in a live game, not in Studio.", true)
		return
	end

	local known = false
	for _, server in ipairs(fetchOtherServers()) do
		if server.jobId == targetJobId then
			known = true
			break
		end
	end
	if not known then
		tell(player, "That server is no longer available. Refresh the list.", true)
		return
	end

	tell(player, "Teleporting...")
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = targetJobId
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		tell(player, "Teleport failed: " .. tostring(err), true)
	end
end)

TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
	tell(player, "Teleport failed: " .. tostring(message), true)
end)

Players.PlayerAdded:Connect(publish)
Players.PlayerRemoving:Connect(function(player)
	lastJoin[player] = nil
	task.defer(publish)
end)
