-- AbilityHUD (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Small panel on the right edge of the screen listing your abilities,
-- their keys, and whether each one is on. K hides/shows it.
--
-- The ability scripts set "<Name>Active" attributes on the local player
-- (client-side only, nothing is replicated); this script just watches
-- them. If you change a key in an ability's CONFIG, update it here too.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.K,
	ShowInactive = true, -- false = only list abilities that are on
}

local ABILITIES = {
	{ name = "Flight", key = "F", can = "CanFly", active = "FlightActive" },
	{ name = "ESP", key = "G", can = "CanSeeESP", active = "ESPActive" },
	{ name = "Aim assist", key = "H", can = "CanAimAssist", active = "AimAssistActive" },
	{ name = "Noclip", key = "N", can = "CanNoclip", active = "NoclipActive" },
	{
		name = "Speed",
		key = "B",
		can = "CanSpeedBoost",
		active = "SpeedBoostActive",
		detail = "SpeedBoostMultiplier",
	},
}

local COLORS = {
	Panel = Color3.fromRGB(20, 20, 24),
	Stroke = Color3.fromRGB(60, 60, 70),
	RowOff = Color3.fromRGB(32, 32, 38),
	RowOn = Color3.fromRGB(30, 62, 44),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(140, 140, 150),
	On = Color3.fromRGB(110, 230, 150),
	KeyBadge = Color3.fromRGB(55, 55, 64),
}

local player = Players.LocalPlayer
local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function make(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

-- Build ---------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "AbilityHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local panel = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(190, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
	BackgroundTransparency = 0.15,
}, {
	corner(10),
	make("UIStroke", { Color = COLORS.Stroke, Thickness = 1 }),
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}),
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})
panel.Parent = gui

make("TextLabel", {
	LayoutOrder = 0,
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "ABILITIES",
}).Parent = panel

local rows = {}

for index, ability in ipairs(ABILITIES) do
	local row = make("Frame", {
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = COLORS.RowOff,
	}, { corner(6) })

	local badge = make("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(22, 20),
		BackgroundColor3 = COLORS.KeyBadge,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLORS.Text,
		Text = ability.key,
	}, { corner(4) })
	badge.Parent = row

	local nameLabel = make("TextLabel", {
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -90, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = ability.name,
	})
	nameLabel.Parent = row

	local stateLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0, 52, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "OFF",
	})
	stateLabel.Parent = row

	row.Parent = panel
	rows[ability] = { row = row, name = nameLabel, state = stateLabel, wasOn = nil }
end

gui.Parent = player:WaitForChild("PlayerGui")

-- Update ----------------------------------------------------------------

local hiddenByUser = false

local function refresh()
	local anyVisible = false

	for _, ability in ipairs(ABILITIES) do
		local ui = rows[ability]
		local has = player:GetAttribute(ability.can) == true
		local on = has and player:GetAttribute(ability.active) == true
		local visible = has and (CONFIG.ShowInactive or on)
		ui.row.Visible = visible
		anyVisible = anyVisible or visible

		local stateText = on and "ON" or "OFF"
		if on and ability.detail then
			local value = player:GetAttribute(ability.detail)
			if value then
				stateText = string.format("x%g", value)
			end
		end
		ui.state.Text = stateText

		if ui.wasOn ~= on then
			ui.wasOn = on
			TweenService:Create(ui.row, tweenInfo, { BackgroundColor3 = on and COLORS.RowOn or COLORS.RowOff }):Play()
			ui.name.TextColor3 = on and COLORS.Text or COLORS.Muted
			ui.state.TextColor3 = on and COLORS.On or COLORS.Muted
		end
	end

	panel.Visible = anyVisible and not hiddenByUser
end

player.AttributeChanged:Connect(refresh)
refresh()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		hiddenByUser = not hiddenByUser
		refresh()
	end
end)
