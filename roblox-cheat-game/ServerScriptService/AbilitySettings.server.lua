-- AbilitySettings (Script in ServerScriptService)
-- Saves each player's ability-menu settings (keybinds, HUD on/off)
-- between sessions with DataStores. Also makes sure the
-- ReplicatedStorage > Abilities folder exists.
--
-- To save while testing in Studio: Game Settings > Security >
-- "Enable Studio Access to API Services" (the place must be published).
-- Without it everything still works; settings just reset each session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	DataStoreName = "AbilitySettings_v1",
	MaxBinds = 300,
	SetCooldown = 1, -- seconds between saves accepted from one player
}

if not ReplicatedStorage:FindFirstChild("Abilities") then
	local folder = Instance.new("Folder")
	folder.Name = "Abilities"
	folder.Parent = ReplicatedStorage
end

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

local settingsRemote = getRemote("RemoteFunction", "AbilitySettings")

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[AbilitySettings] Settings won't be saved:", result)
	end
end

-- [Player] = { data = {...}, loaded = bool, loadFailed = bool, dirty = bool, lastSet = number }
local sessions = {}

local function defaultData()
	return { binds = {}, hudVisible = true }
end

-- Keeps only { [string] = { [string] = string } } with short strings.
local function sanitizeBinds(binds)
	local clean, count = {}, 0
	if type(binds) ~= "table" then
		return clean
	end
	for abilityId, map in pairs(binds) do
		if type(abilityId) == "string" and #abilityId <= 64 and type(map) == "table" then
			local inner = {}
			for bindId, value in pairs(map) do
				if type(bindId) == "string" and #bindId <= 64 and type(value) == "string" and #value <= 64 then
					count += 1
					if count > CONFIG.MaxBinds then
						return clean
					end
					inner[bindId] = value
				end
			end
			clean[abilityId] = inner
		end
	end
	return clean
end

local function key(player)
	return "player_" .. player.UserId
end

local function load(player)
	local session = { data = defaultData(), loaded = false, loadFailed = false, dirty = false, lastSet = 0 }
	sessions[player] = session
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok and type(saved) == "table" then
			session.data.binds = sanitizeBinds(saved.binds)
			if type(saved.hudVisible) == "boolean" then
				session.data.hudVisible = saved.hudVisible
			end
		elseif not ok then
			session.loadFailed = true -- don't overwrite data we couldn't read
			warn("[AbilitySettings] Could not load settings for " .. player.Name .. ":", saved)
		end
	end
	session.loaded = true
end

local function save(player, session)
	if not store or not session.dirty or session.loadFailed then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(key(player), session.data)
	end)
	if ok then
		session.dirty = false
	else
		warn("[AbilitySettings] Could not save settings for " .. player.Name .. ":", err)
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
		task.wait(60)
		for player, session in pairs(sessions) do
			task.spawn(save, player, session)
		end
	end
end)

settingsRemote.OnServerInvoke = function(player, action, payload)
	local session = sessions[player]
	-- Give the DataStore a moment if the player just joined.
	local waited = 0
	while session and not session.loaded and waited < 10 do
		waited += task.wait(0.1)
	end
	if not (session and session.loaded) then
		return nil
	end

	if action == "get" then
		return session.data
	elseif action == "set" and type(payload) == "table" then
		local now = os.clock()
		if now - session.lastSet < CONFIG.SetCooldown then
			return false
		end
		session.lastSet = now
		session.data.binds = sanitizeBinds(payload.binds)
		if type(payload.hudVisible) == "boolean" then
			session.data.hudVisible = payload.hudVisible
		end
		session.dirty = true -- written by the autosave loop or when they leave
		return true
	end
	return nil
end
