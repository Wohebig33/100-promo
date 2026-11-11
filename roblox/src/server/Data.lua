-- Saves and loads player profiles with DataStoreService.
-- In Studio this only works after Game Settings > Security > "Enable Studio Access to API Services".
-- When a load fails, the profile is flagged so it is never saved over real data.

local DSS = game:GetService("DataStoreService")

local Data = {}
local okStore, store = pcall(function()
	return DSS:GetDataStore("SinbornSave_v1")
end)

local function key(userId)
	return "u_" .. tostring(userId)
end

-- Returns (data or nil, loadedOk)
function Data.load(userId)
	if not okStore or not store then return nil, false end
	for attempt = 1, 3 do
		local ok, res = pcall(function()
			return store:GetAsync(key(userId))
		end)
		if ok then return res, true end
		warn("[Sinborn] load failed (attempt " .. attempt .. "): " .. tostring(res))
		task.wait(1)
	end
	return nil, false
end

function Data.save(userId, prof)
	if not okStore or not store or not prof or prof.noSave then return false end
	local copy = {}
	for k, v in pairs(prof) do
		if k ~= "noSave" then copy[k] = v end
	end
	local ok, err = pcall(function()
		store:SetAsync(key(userId), copy)
	end)
	if not ok then warn("[Sinborn] save failed: " .. tostring(err)) end
	return ok
end

return Data
