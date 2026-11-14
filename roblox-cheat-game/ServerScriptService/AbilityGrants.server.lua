-- AbilityGrants (Script in ServerScriptService)
-- Grants the cheat abilities to players. The client scripts check these
-- attributes, so this is the one place to control who gets what
-- (e.g. tie it to a game pass, round state, team, or pickup).

local Players = game:GetService("Players")

local GRANT_TO_EVERYONE = true

local ABILITIES = {
	"CanFly",
	"CanSeeESP",
	"CanAimAssist",
}

local function grant(player)
	if not GRANT_TO_EVERYONE then
		return
	end
	for _, ability in ipairs(ABILITIES) do
		player:SetAttribute(ability, true)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	grant(player)
end
Players.PlayerAdded:Connect(grant)
