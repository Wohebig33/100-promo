-- ServerList (LocalScript in StarterPlayer > StarterPlayerScripts)
-- L (or typing /servers in chat) opens a list of this game's running
-- servers. Click Join to teleport to one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.L,
	RequiredAttribute = "CanServerHop",
}

local COLORS = {
	Panel = Color3.fromRGB(24, 24, 28),
	Stroke = Color3.fromRGB(60, 60, 70),
	Row = Color3.fromRGB(36, 36, 42),
	RowCurrent = Color3.fromRGB(32, 48, 40),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(150, 150, 160),
	Button = Color3.fromRGB(50, 50, 58),
	Accent = Color3.fromRGB(60, 140, 255),
	Disabled = Color3.fromRGB(70, 70, 78),
}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CheatRemotes")
local getServerList = remotes:WaitForChild("GetServerList")
local joinServer = remotes:WaitForChild("JoinServer")
local openServerList = remotes:WaitForChild("OpenServerList")

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

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

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or COLORS.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return make("TextLabel", props)
end

local function button(props)
	props.Font = Enum.Font.GothamBold
	props.TextSize = props.TextSize or 14
	props.TextColor3 = COLORS.Text
	props.BackgroundColor3 = props.BackgroundColor3 or COLORS.Button
	return make("TextButton", props, { corner(6) })
end

-- Build the window -----------------------------------------------------

local gui = make("ScreenGui", {
	Name = "ServerListGui",
	ResetOnSpawn = false,
	Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local panel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.7),
	BackgroundColor3 = COLORS.Panel,
}, {
	corner(10),
	make("UIStroke", { Color = COLORS.Stroke, Thickness = 1 }),
	make("UISizeConstraint", { MaxSize = Vector2.new(400, 460) }),
})
panel.Parent = gui

label({
	Text = "Servers",
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -150, 0, 28),
}).Parent = panel

local closeButton = button({
	Text = "X",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(28, 28),
})
closeButton.Parent = panel

local refreshButton = button({
	Text = "Refresh",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -48, 0, 12),
	Size = UDim2.fromOffset(80, 28),
})
refreshButton.Parent = panel

local status = label({
	Text = "",
	TextSize = 13,
	TextColor3 = COLORS.Muted,
	Position = UDim2.fromOffset(16, 44),
	Size = UDim2.new(1, -32, 0, 18),
})
status.Parent = panel

local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 70),
	Size = UDim2.new(1, -24, 1, -82),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
list.Parent = panel

gui.Parent = player:WaitForChild("PlayerGui")

-- Rows -----------------------------------------------------------------

local joining = false

local function clearRows()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function addRow(server, order)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = server.isCurrent and COLORS.RowCurrent or COLORS.Row,
	}, { corner(8) })

	label({
		Text = "Server " .. string.sub(server.jobId, 1, 8),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -110, 0, 20),
	}).Parent = row

	label({
		Text = string.format("%d / %d players", server.players, server.maxPlayers)
			.. (server.isCurrent and "  ·  you are here" or ""),
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		Position = UDim2.fromOffset(12, 27),
		Size = UDim2.new(1, -110, 0, 18),
	}).Parent = row

	local full = server.players >= server.maxPlayers
	local canJoin = not server.isCurrent and not full

	local joinButton = button({
		Text = server.isCurrent and "Current" or full and "Full" or "Join",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(80, 32),
		BackgroundColor3 = canJoin and COLORS.Accent or COLORS.Disabled,
		AutoButtonColor = canJoin,
	})
	joinButton.Parent = row

	if canJoin then
		joinButton.Activated:Connect(function()
			if joining then
				return
			end
			joining = true
			joinButton.Text = "Joining..."
			joinButton.BackgroundColor3 = COLORS.Disabled
			joinServer:FireServer(server.jobId)

			-- If the teleport fails, let them try again.
			task.delay(6, function()
				joining = false
				if joinButton.Parent then
					joinButton.Text = "Join"
					joinButton.BackgroundColor3 = COLORS.Accent
				end
			end)
		end)
	end

	row.Parent = list
end

-- Loading --------------------------------------------------------------

local loading = false

local function refresh()
	if loading then
		return
	end
	loading = true
	status.Text = "Loading servers..."
	clearRows()

	local ok, response = pcall(function()
		return getServerList:InvokeServer()
	end)
	loading = false

	if not ok or type(response) ~= "table" then
		status.Text = "Couldn't load servers. Try again."
		return
	end
	if not response.ok then
		status.Text = response.error or "Server list unavailable."
		return
	end

	local servers = response.servers
	status.Text = string.format("%d server%s online", #servers, #servers == 1 and "" or "s")
		.. (response.isStudio and "  ·  teleporting is disabled in Studio" or "")
	for index, server in ipairs(servers) do
		addRow(server, index)
	end
end

local function setOpen(open)
	if open and not hasAbility() then
		return
	end
	gui.Enabled = open
	if open then
		refresh()
	end
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)
refreshButton.Activated:Connect(refresh)
openServerList.OnClientEvent:Connect(function()
	setOpen(true)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		setOpen(not gui.Enabled)
	end
end)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not hasAbility() then
		setOpen(false)
	end
end)
