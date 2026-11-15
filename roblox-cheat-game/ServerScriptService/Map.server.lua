-- Map (Script in ServerScriptService)
-- Backend for the map: keeps each player's personal waypoints (saved
-- between sessions with DataStores) and handles teleport requests.
--
-- To keep waypoints while testing in Studio: Game Settings > Security >
-- "Enable Studio Access to API Services" (the place must be published).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local TeleportUtil = require(ServerScriptService:WaitForChild("TeleportUtil"))

local CONFIG = {
	RequiredAttribute = "CanTeleport",
	MaxWaypoints = 50,
	MaxNameLength = 24,
	DataStoreName = "Waypoints_v1",
	AutosaveInterval = 120, -- seconds
	TravelCooldown = 1, -- seconds between teleports per player
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

local mapRequest = getRemote("RemoteFunction", "MapRequest")
getRemote("RemoteEvent", "OpenMap") -- fired by the /map command

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Map] Waypoints won't be saved:", result)
	end
end

-- [Player] = { waypoints = {...}, dirty = bool, loadFailed = bool, lastTravel = number }
local sessions = {}

local function dataKey(player)
	return "player_" .. player.UserId
end

local function isValidWaypoint(wp)
	return type(wp) == "table"
		and type(wp.id) == "string"
		and type(wp.name) == "string"
		and TeleportUtil.isValidNumber(wp.x)
		and TeleportUtil.isValidNumber(wp.z)
		and (wp.y == nil or TeleportUtil.isValidNumber(wp.y))
end

-- Saving / loading ------------------------------------------------------

local function load(player)
	local session = { waypoints = {}, dirty = false, loadFailed = false, lastTravel = 0 }
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(dataKey(player))
		end)
		if ok then
			if type(saved) == "table" then
				for _, wp in ipairs(saved) do
					if isValidWaypoint(wp) and #session.waypoints < CONFIG.MaxWaypoints then
						table.insert(session.waypoints, wp)
					end
				end
			end
		else
			-- Don't save over data we couldn't read.
			session.loadFailed = true
			warn("[Map] Could not load waypoints for " .. player.Name .. ":", saved)
		end
	end
	if player.Parent then
		sessions[player] = session
	end
end

local function save(player, session)
	if not store or not session.dirty or session.loadFailed then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(dataKey(player), session.waypoints)
	end)
	if ok then
		session.dirty = false
	else
		warn("[Map] Could not save waypoints for " .. player.Name .. ":", err)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(load, player)
end
Players.PlayerAdded:Connect(load)

Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	sessions[player] = nil
	if session then
		save(player, session)
	end
end)

game:BindToClose(function()
	for player, session in pairs(sessions) do
		save(player, session)
	end
end)

task.spawn(function()
	while true do
		task.wait(CONFIG.AutosaveInterval)
		for player, session in pairs(sessions) do
			task.spawn(save, player, session)
		end
	end
end)

-- Helpers ---------------------------------------------------------------

local function round(n)
	return math.round(n * 10) / 10
end

local function newId()
	return string.sub(HttpService:GenerateGUID(false), 1, 8)
end

local function findWaypoint(session, id)
	for index, wp in ipairs(session.waypoints) do
		if wp.id == id then
			return wp, index
		end
	end
	return nil
end

-- Trims, shortens and filters a waypoint name. Returns nil if unusable.
local function cleanName(player, raw)
	if type(raw) ~= "string" or #raw > 200 then
		return nil
	end
	local text = string.match(raw, "^%s*(.-)%s*$")
	local length = utf8.len(text)
	if text == "" or length == nil then
		return nil
	end
	if length > CONFIG.MaxNameLength then
		text = string.sub(text, 1, utf8.offset(text, CONFIG.MaxNameLength + 1) - 1)
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PrivateChat)
		return result:GetNonChatStringForUserAsync(player.UserId)
	end)
	if not ok then
		warn("[Map] Could not filter waypoint name:", filtered)
		return nil
	end
	return filtered
end

local function travelTo(player, session, x, y, z)
	local now = os.clock()
	if now - session.lastTravel < CONFIG.TravelCooldown then
		return { ok = false, error = "Slow down, try again in a moment." }
	end

	local position
	if y ~= nil then
		position = Vector3.new(x, y, z)
	else
		position = TeleportUtil.groundPosition(player, x, z)
		if not position then
			return { ok = false, error = "No ground found there. Enter a Y coordinate instead." }
		end
	end

	local ok, err = TeleportUtil.teleport(player, position)
	if not ok then
		return { ok = false, error = err }
	end
	session.lastTravel = now
	return { ok = true, message = "Teleported to " .. TeleportUtil.formatPosition(position) }
end

-- Requests --------------------------------------------------------------

local handlers = {}

function handlers.list()
	return { ok = true }
end

function handlers.add(player, session, payload)
	if #session.waypoints >= CONFIG.MaxWaypoints then
		return { ok = false, error = string.format("You can only have %d waypoints.", CONFIG.MaxWaypoints) }
	end
	local x, y, z = payload.x, payload.y, payload.z
	if not (TeleportUtil.isValidNumber(x) and TeleportUtil.isValidNumber(z)) then
		return { ok = false, error = "Those coordinates are out of range." }
	end
	if y ~= nil and not TeleportUtil.isValidNumber(y) then
		return { ok = false, error = "That Y coordinate is out of range." }
	end

	local wp = {
		id = newId(),
		name = cleanName(player, payload.name) or ("Waypoint " .. (#session.waypoints + 1)),
		x = round(x),
		y = y and round(y) or nil,
		z = round(z),
	}
	table.insert(session.waypoints, wp)
	session.dirty = true
	return { ok = true, id = wp.id, message = "Added " .. wp.name }
end

function handlers.addHere(player, session, payload)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return { ok = false, error = "You need to be spawned in." }
	end
	local p = root.Position
	return handlers.add(player, session, { name = payload.name, x = p.X, y = p.Y, z = p.Z })
end

function handlers.rename(player, session, payload)
	local wp = findWaypoint(session, payload.id)
	if not wp then
		return { ok = false, error = "That waypoint no longer exists." }
	end
	local name = cleanName(player, payload.name)
	if not name then
		return { ok = false, error = "That name can't be used." }
	end
	wp.name = name
	session.dirty = true
	return { ok = true }
end

function handlers.remove(_player, session, payload)
	local wp, index = findWaypoint(session, payload.id)
	if not wp then
		return { ok = false, error = "That waypoint no longer exists." }
	end
	table.remove(session.waypoints, index)
	session.dirty = true
	return { ok = true, message = "Deleted " .. wp.name }
end

function handlers.travel(player, session, payload)
	local wp = findWaypoint(session, payload.id)
	if not wp then
		return { ok = false, error = "That waypoint no longer exists." }
	end
	return travelTo(player, session, wp.x, wp.y, wp.z)
end

function handlers.travelCoords(player, session, payload)
	local x, y, z = payload.x, payload.y, payload.z
	if not (TeleportUtil.isValidNumber(x) and TeleportUtil.isValidNumber(z)) then
		return { ok = false, error = "Those coordinates are out of range." }
	end
	if y ~= nil and not TeleportUtil.isValidNumber(y) then
		return { ok = false, error = "That Y coordinate is out of range." }
	end
	return travelTo(player, session, x, y, z)
end

mapRequest.OnServerInvoke = function(player, action, payload)
	if player:GetAttribute(CONFIG.RequiredAttribute) ~= true then
		return { ok = false, error = "You can't use the map." }
	end
	local handler = type(action) == "string" and handlers[action]
	if not handler then
		return { ok = false, error = "Unknown request." }
	end
	local session = sessions[player]
	if not session then
		return { ok = false, error = "Still loading your waypoints, try again in a moment." }
	end
	if type(payload) ~= "table" then
		payload = {}
	end

	local response = handler(player, session, payload)
	response.waypoints = session.waypoints
	return response
end
