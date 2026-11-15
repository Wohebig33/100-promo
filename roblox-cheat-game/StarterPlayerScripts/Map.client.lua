-- Map (LocalScript in StarterPlayer > StarterPlayerScripts)
-- M (or /map in chat) opens a full-screen top-down map with no edges.
--   Drag            pan
--   Scroll / pinch  zoom (also the + and - buttons)
--   Right-click     add a waypoint there (or press Place, then click)
--   Click waypoint  open it: Go here / rename / delete
-- The top-left panel teleports to typed coordinates (leave Y blank to
-- land on the ground) and saves a waypoint where you're standing.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	ToggleKey = Enum.KeyCode.M,
	RequiredAttribute = "CanTeleport",
	DefaultScale = 1, -- pixels per stud
	MinScale = 0.002, -- zoomed out: 1 pixel = 500 studs
	MaxScale = 20, -- zoomed in: 1 stud = 20 pixels
	ZoomStep = 1.25,
	GridSpacingPixels = 90, -- rough distance between grid lines
	ShowOtherPlayers = true,
	ClickRadius = 14, -- pixels
}

local COLORS = {
	Background = Color3.fromRGB(16, 18, 22),
	Grid = Color3.fromRGB(38, 42, 50),
	GridAxis = Color3.fromRGB(95, 105, 125),
	GridLabel = Color3.fromRGB(115, 120, 135),
	Panel = Color3.fromRGB(24, 24, 28),
	Stroke = Color3.fromRGB(60, 60, 70),
	Input = Color3.fromRGB(36, 36, 42),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(150, 150, 160),
	Button = Color3.fromRGB(50, 50, 58),
	Accent = Color3.fromRGB(60, 140, 255),
	Danger = Color3.fromRGB(210, 65, 65),
	Success = Color3.fromRGB(124, 214, 124),
	Error = Color3.fromRGB(255, 92, 92),
	Self = Color3.fromRGB(255, 255, 255),
	Other = Color3.fromRGB(255, 200, 60),
	Waypoint = Color3.fromRGB(80, 220, 140),
	WaypointSelected = Color3.fromRGB(255, 120, 220),
}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("CheatRemotes")
local mapRequest = remotes:WaitForChild("MapRequest")
local openMap = remotes:WaitForChild("OpenMap")

-- State -------------------------------------------------------------------

local isOpen = false
local center = Vector2.zero -- world (X, Z) shown at the middle of the map
local scale = CONFIG.DefaultScale
local waypoints = {}
local selectedId = nil
local placeMode = false
local dragInput, dragStart, dragCenterStart, dragMoved = nil, nil, nil, false
local pinchStartScale = nil
local waypointScreenPositions = {} -- [id] = Vector2 in map-local pixels

-- UI helpers ----------------------------------------------------------------

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

local function round()
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local function stroke(color, thickness)
	return make("UIStroke", { Color = color or COLORS.Stroke, Thickness = thickness or 1 })
end

local function padding(px)
	local u = UDim.new(0, px)
	return make("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

local function list(direction, gap)
	return make("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
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

local function textBox(props)
	props.Font = Enum.Font.Gotham
	props.TextSize = 14
	props.TextColor3 = COLORS.Text
	props.PlaceholderColor3 = COLORS.Muted
	props.BackgroundColor3 = COLORS.Input
	props.ClearTextOnFocus = false
	props.Text = props.Text or ""
	props.TextXAlignment = Enum.TextXAlignment.Left
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return make("TextBox", props, {
		corner(6),
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
end

-- Build the UI --------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "MapGui",
	ResetOnSpawn = false,
	Enabled = false,
	IgnoreGuiInset = true, -- AbsolutePosition then matches GetMouseLocation()
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local mapFrame = make("Frame", {
	Name = "Map",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.Background,
	BorderSizePixel = 0,
	Active = true, -- keeps clicks from reaching the game
	ClipsDescendants = true,
})
mapFrame.Parent = gui

local gridLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
gridLayer.Parent = mapFrame
local markerLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
markerLayer.Parent = mapFrame

-- Top-left: position + coordinate teleport
local coordsPanel = make("Frame", {
	Position = UDim2.fromOffset(12, 64),
	Size = UDim2.fromOffset(290, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
}, { corner(10), stroke(), padding(10), list(Enum.FillDirection.Vertical, 8) })
coordsPanel.Parent = gui

local positionLabel = label({
	LayoutOrder = 1,
	Text = "You: -",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	Size = UDim2.new(1, 0, 0, 18),
})
positionLabel.Parent = coordsPanel

label({
	LayoutOrder = 2,
	Text = "Teleport to coordinates (blank Y = ground)",
	TextSize = 12,
	TextColor3 = COLORS.Muted,
	Size = UDim2.new(1, 0, 0, 16),
}).Parent = coordsPanel

local inputRow = make("Frame", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
}, { list(Enum.FillDirection.Horizontal, 6) })
inputRow.Parent = coordsPanel

local xBox = textBox({ LayoutOrder = 1, PlaceholderText = "X", Size = UDim2.new(0.25, -5, 1, 0) })
local yBox = textBox({ LayoutOrder = 2, PlaceholderText = "Y", Size = UDim2.new(0.25, -5, 1, 0) })
local zBox = textBox({ LayoutOrder = 3, PlaceholderText = "Z", Size = UDim2.new(0.25, -5, 1, 0) })
local goButton = button({
	LayoutOrder = 4,
	Text = "Go",
	BackgroundColor3 = COLORS.Accent,
	Size = UDim2.new(0.25, -5, 1, 0),
})
xBox.Parent, yBox.Parent, zBox.Parent, goButton.Parent = inputRow, inputRow, inputRow, inputRow

local saveHereButton = button({
	LayoutOrder = 4,
	Text = "Save waypoint where I'm standing",
	TextSize = 13,
	Size = UDim2.new(1, 0, 0, 30),
})
saveHereButton.Parent = coordsPanel

-- Top-right: toolbar
local toolbar = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 64),
	Size = UDim2.fromOffset(0, 36),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = COLORS.Panel,
}, { corner(10), stroke(), padding(4), list(Enum.FillDirection.Horizontal, 4) })
toolbar.Parent = gui

local zoomInButton = button({ LayoutOrder = 1, Text = "+", TextSize = 18, Size = UDim2.fromOffset(32, 28) })
local zoomOutButton = button({ LayoutOrder = 2, Text = "-", TextSize = 18, Size = UDim2.fromOffset(32, 28) })
local centerButton = button({ LayoutOrder = 3, Text = "Me", Size = UDim2.fromOffset(44, 28) })
local placeButton = button({ LayoutOrder = 4, Text = "Place", Size = UDim2.fromOffset(64, 28) })
local closeButton = button({ LayoutOrder = 5, Text = "X", Size = UDim2.fromOffset(32, 28) })
for _, b in ipairs({ zoomInButton, zoomOutButton, centerButton, placeButton, closeButton }) do
	b.Parent = toolbar
end

-- Bottom-left: help + cursor coordinates
local cursorLabel = label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -32),
	Size = UDim2.fromOffset(320, 18),
	TextSize = 13,
	Text = "",
})
cursorLabel.Parent = gui

label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(1, -24, 0, 18),
	TextSize = 13,
	TextColor3 = COLORS.Muted,
	Text = "Drag to move  ·  Scroll, pinch or +/- to zoom  ·  Right-click or Place to add a waypoint  ·  Click a waypoint to travel",
}).Parent = gui

-- Top-center: toast messages
local toast = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(0, 32),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = COLORS.Panel,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = COLORS.Text,
	Text = "",
	Visible = false,
}, { corner(8), stroke(), make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
toast.Parent = gui

-- Bottom-center: selected waypoint
local popup = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -60),
	Size = UDim2.fromOffset(320, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
	Visible = false,
}, { corner(10), stroke(), padding(10), list(Enum.FillDirection.Vertical, 8) })
popup.Parent = gui

local nameBox = textBox({ LayoutOrder = 1, PlaceholderText = "Waypoint name", Size = UDim2.new(1, 0, 0, 30) })
nameBox.Parent = popup

local popupCoords = label({
	LayoutOrder = 2,
	TextSize = 13,
	TextColor3 = COLORS.Muted,
	Size = UDim2.new(1, 0, 0, 18),
})
popupCoords.Parent = popup

local popupButtons = make("Frame", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
}, { list(Enum.FillDirection.Horizontal, 6) })
popupButtons.Parent = popup

local travelButton = button({
	LayoutOrder = 1,
	Text = "Go here",
	BackgroundColor3 = COLORS.Accent,
	Size = UDim2.new(0.5, -4, 1, 0),
})
local deleteButton = button({
	LayoutOrder = 2,
	Text = "Delete",
	BackgroundColor3 = COLORS.Danger,
	Size = UDim2.new(0.25, -4, 1, 0),
})
local popupCloseButton = button({ LayoutOrder = 3, Text = "Close", Size = UDim2.new(0.25, -4, 1, 0) })
travelButton.Parent, deleteButton.Parent, popupCloseButton.Parent = popupButtons, popupButtons, popupButtons

-- Your own marker: a dot with a nub pointing where you face.
local selfMarker = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(22, 22),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, {
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = COLORS.Self,
	}, { round(), stroke(Color3.new(0, 0, 0), 2) }),
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -4),
		Size = UDim2.fromOffset(4, 8),
		BackgroundColor3 = COLORS.Self,
		BorderSizePixel = 0,
	}),
})
selfMarker.Parent = markerLayer

gui.Parent = player:WaitForChild("PlayerGui")

local overlays = { coordsPanel, toolbar, popup }

-- Object pools (so redrawing every frame doesn't create instances) -------

local gridLines, gridLabels, playerMarkers, waypointMarkers = {}, {}, {}, {}

local function pooled(pool, index, create)
	local item = pool[index]
	if not item then
		item = create()
		pool[index] = item
	end
	item.Visible = true
	return item
end

local function hideFrom(pool, index)
	for i = index, #pool do
		pool[i].Visible = false
	end
end

local function newGridLine()
	local line = make("Frame", { BorderSizePixel = 0, BackgroundColor3 = COLORS.Grid })
	line.Parent = gridLayer
	return line
end

local function newGridLabel()
	local text = label({ TextSize = 12, TextColor3 = COLORS.GridLabel, Size = UDim2.fromOffset(80, 16) })
	text.Parent = gridLayer
	return text
end

local function newPlayerMarker()
	local marker = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = COLORS.Other,
		ZIndex = 1,
	}, { round(), stroke(Color3.new(0, 0, 0), 1) })
	label({
		Name = "PlayerName",
		Position = UDim2.fromOffset(14, -4),
		Size = UDim2.fromOffset(160, 16),
		TextSize = 12,
		TextColor3 = COLORS.Other,
	}).Parent = marker
	marker.Parent = markerLayer
	return marker
end

local function newWaypointMarker()
	local marker = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		make("Frame", {
			Name = "Diamond",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			BackgroundColor3 = COLORS.Waypoint,
		}, { stroke(Color3.new(0, 0, 0), 1.5) }),
	})
	label({
		Name = "WaypointName",
		Position = UDim2.fromOffset(22, 2),
		Size = UDim2.fromOffset(180, 16),
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.4,
	}).Parent = marker
	marker.Parent = markerLayer
	return marker
end

-- Math --------------------------------------------------------------------

-- Smallest 1/2/5 x 10^n that's at least `minStuds`.
local function niceStep(minStuds)
	local magnitude = 10 ^ math.floor(math.log10(minStuds))
	for _, m in ipairs({ 1, 2, 5 }) do
		if m * magnitude >= minStuds then
			return m * magnitude
		end
	end
	return 10 * magnitude
end

local function formatGridNumber(n)
	local a = math.abs(n)
	if a >= 1e6 then
		return string.format("%gM", n / 1e6)
	elseif a >= 1e4 then
		return string.format("%gk", n / 1e3)
	end
	return string.format("%d", n)
end

local function formatCoord(n)
	return string.format("%.1f", n)
end

local function worldToMap(x, z, half)
	return Vector2.new((x - center.X) * scale + half.X, (z - center.Y) * scale + half.Y)
end

local function mapToWorld(localPos)
	return center + (localPos - mapFrame.AbsoluteSize / 2) / scale
end

local function getRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function isOver(guiObject, pos)
	if not guiObject.Visible then
		return false
	end
	local p, s = guiObject.AbsolutePosition, guiObject.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function pointerBlocked(pos)
	for _, overlay in ipairs(overlays) do
		if isOver(overlay, pos) then
			return true
		end
	end
	return false
end

-- Screen position (same space as AbsolutePosition with IgnoreGuiInset).
local function pointerPosition(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

local function zoomAt(screenPos, factor)
	local localPos = screenPos - mapFrame.AbsolutePosition
	local anchor = mapToWorld(localPos)
	scale = math.clamp(scale * factor, CONFIG.MinScale, CONFIG.MaxScale)
	center = anchor - (localPos - mapFrame.AbsoluteSize / 2) / scale
end

local function centerOnPlayer()
	local root = getRoot()
	if root then
		center = Vector2.new(root.Position.X, root.Position.Z)
	end
end

-- Drawing -------------------------------------------------------------------

local function renderGrid(size, half)
	local step = niceStep(CONFIG.GridSpacingPixels / scale)
	local lineCount, labelCount = 0, 0

	-- Vertical lines (constant X), labelled along the bottom.
	local minX, maxX = center.X - half.X / scale, center.X + half.X / scale
	local x = math.ceil(minX / step) * step
	while x <= maxX and lineCount < 150 do
		local sx = math.floor((x - center.X) * scale + half.X)
		lineCount += 1
		local line = pooled(gridLines, lineCount, newGridLine)
		line.Position = UDim2.fromOffset(sx, 0)
		line.Size = UDim2.new(0, x == 0 and 2 or 1, 1, 0)
		line.BackgroundColor3 = x == 0 and COLORS.GridAxis or COLORS.Grid

		labelCount += 1
		local text = pooled(gridLabels, labelCount, newGridLabel)
		text.Text = "x " .. formatGridNumber(x)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(sx + 4, size.Y - 72)
		x += step
	end

	-- Horizontal lines (constant Z), labelled along the right edge.
	local minZ, maxZ = center.Y - half.Y / scale, center.Y + half.Y / scale
	local z = math.ceil(minZ / step) * step
	while z <= maxZ and lineCount < 300 do
		local sy = math.floor((z - center.Y) * scale + half.Y)
		lineCount += 1
		local line = pooled(gridLines, lineCount, newGridLine)
		line.Position = UDim2.fromOffset(0, sy)
		line.Size = UDim2.new(1, 0, 0, z == 0 and 2 or 1)
		line.BackgroundColor3 = z == 0 and COLORS.GridAxis or COLORS.Grid

		labelCount += 1
		local text = pooled(gridLabels, labelCount, newGridLabel)
		text.Text = "z " .. formatGridNumber(z)
		text.TextXAlignment = Enum.TextXAlignment.Right
		text.Position = UDim2.fromOffset(size.X - 88, sy + 2)
		z += step
	end

	hideFrom(gridLines, lineCount + 1)
	hideFrom(gridLabels, labelCount + 1)
end

local function renderPlayers(half)
	local count = 0
	if CONFIG.ShowOtherPlayers then
		for _, other in ipairs(Players:GetPlayers()) do
			local root = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if root then
				count += 1
				local marker = pooled(playerMarkers, count, newPlayerMarker)
				local p = worldToMap(root.Position.X, root.Position.Z, half)
				marker.Position = UDim2.fromOffset(p.X, p.Y)
				marker.PlayerName.Text = other.DisplayName
			end
		end
	end
	hideFrom(playerMarkers, count + 1)

	local root = getRoot()
	selfMarker.Visible = root ~= nil
	if root then
		local pos = root.Position
		local p = worldToMap(pos.X, pos.Z, half)
		selfMarker.Position = UDim2.fromOffset(p.X, p.Y)
		local look = root.CFrame.LookVector
		selfMarker.Rotation = math.deg(math.atan2(look.X, -look.Z))
		positionLabel.Text = string.format(
			"You: %d, %d, %d",
			math.floor(pos.X),
			math.floor(pos.Y),
			math.floor(pos.Z)
		)
	end
end

local function renderWaypoints(size, half)
	table.clear(waypointScreenPositions)
	local margin = 16
	for index, wp in ipairs(waypoints) do
		local marker = pooled(waypointMarkers, index, newWaypointMarker)
		local p = worldToMap(wp.x, wp.z, half)
		local onScreen = p.X >= 0 and p.X <= size.X and p.Y >= 0 and p.Y <= size.Y
		if not onScreen then
			-- Pin off-screen waypoints to the edge so they're still clickable.
			p = Vector2.new(math.clamp(p.X, margin, size.X - margin), math.clamp(p.Y, margin, size.Y - margin))
		end

		local selected = wp.id == selectedId
		local color = selected and COLORS.WaypointSelected or COLORS.Waypoint
		local diamondSize = selected and 16 or (onScreen and 12 or 8)

		marker.Position = UDim2.fromOffset(p.X, p.Y)
		marker.Diamond.BackgroundColor3 = color
		marker.Diamond.BackgroundTransparency = onScreen and 0 or 0.35
		marker.Diamond.Size = UDim2.fromOffset(diamondSize, diamondSize)
		marker.WaypointName.Text = wp.name
		marker.WaypointName.TextColor3 = color
		marker.WaypointName.Visible = onScreen or selected

		waypointScreenPositions[wp.id] = p
	end
	hideFrom(waypointMarkers, #waypoints + 1)
end

RunService.RenderStepped:Connect(function()
	if not isOpen then
		return
	end
	local size = mapFrame.AbsoluteSize
	local half = size / 2
	renderGrid(size, half)
	renderWaypoints(size, half)
	renderPlayers(half)

	if UserInputService.MouseEnabled then
		local world = mapToWorld(UserInputService:GetMouseLocation() - mapFrame.AbsolutePosition)
		cursorLabel.Text = string.format("Cursor: x %d, z %d", math.floor(world.X), math.floor(world.Y))
	end
end)

-- Server requests -----------------------------------------------------------

local toastToken = 0
local function showToast(text, isError)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = isError and COLORS.Error or COLORS.Success
	toast.Visible = true
	task.delay(3, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

local function findWaypoint(id)
	for _, wp in ipairs(waypoints) do
		if wp.id == id then
			return wp
		end
	end
	return nil
end

local function selectWaypoint(wp)
	selectedId = wp and wp.id or nil
	popup.Visible = wp ~= nil
	if wp then
		nameBox.Text = wp.name
		popupCoords.Text = string.format(
			"x %s  ·  y %s  ·  z %s",
			formatCoord(wp.x),
			wp.y and formatCoord(wp.y) or "ground",
			formatCoord(wp.z)
		)
	end
end

local function request(action, payload)
	local ok, response = pcall(function()
		return mapRequest:InvokeServer(action, payload or {})
	end)
	if not ok or type(response) ~= "table" then
		showToast("Couldn't reach the server.", true)
		return nil
	end
	if type(response.waypoints) == "table" then
		waypoints = response.waypoints
		if selectedId then
			selectWaypoint(findWaypoint(selectedId))
		end
	end
	if not response.ok then
		showToast(response.error or "Something went wrong.", true)
		return nil
	end
	if response.message then
		showToast(response.message, false)
	end
	return response
end

local function setPlaceMode(on)
	placeMode = on
	placeButton.Text = on and "Placing" or "Place"
	placeButton.BackgroundColor3 = on and COLORS.Accent or COLORS.Button
end

local function waypointAt(localPos)
	local best, bestDist = nil, CONFIG.ClickRadius
	for _, wp in ipairs(waypoints) do
		local p = waypointScreenPositions[wp.id]
		if p then
			local dist = (p - localPos).Magnitude
			if dist <= bestDist then
				best, bestDist = wp, dist
			end
		end
	end
	return best
end

local function placeWaypointAt(screenPos)
	local world = mapToWorld(screenPos - mapFrame.AbsolutePosition)
	local response = request("add", { x = world.X, z = world.Y })
	if response and response.id then
		selectWaypoint(findWaypoint(response.id))
	end
end

local function handleClick(screenPos)
	local hit = waypointAt(screenPos - mapFrame.AbsolutePosition)
	if hit then
		selectWaypoint(hit)
	elseif placeMode then
		setPlaceMode(false)
		placeWaypointAt(screenPos)
	else
		selectWaypoint(nil)
	end
end

-- Open / close --------------------------------------------------------------

local function hasAbility()
	return player:GetAttribute(CONFIG.RequiredAttribute) == true
end

local function setOpen(open)
	if open and not hasAbility() then
		return
	end
	isOpen = open
	gui.Enabled = open
	dragInput = nil
	pinchStartScale = nil
	if open then
		centerOnPlayer()
		task.spawn(request, "list")
	else
		setPlaceMode(false)
		selectWaypoint(nil)
	end
end

-- Buttons -------------------------------------------------------------------

local function mapMiddle()
	return mapFrame.AbsolutePosition + mapFrame.AbsoluteSize / 2
end

zoomInButton.Activated:Connect(function()
	zoomAt(mapMiddle(), CONFIG.ZoomStep)
end)
zoomOutButton.Activated:Connect(function()
	zoomAt(mapMiddle(), 1 / CONFIG.ZoomStep)
end)
centerButton.Activated:Connect(centerOnPlayer)
placeButton.Activated:Connect(function()
	setPlaceMode(not placeMode)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
popupCloseButton.Activated:Connect(function()
	selectWaypoint(nil)
end)

travelButton.Activated:Connect(function()
	if selectedId and request("travel", { id = selectedId }) then
		setOpen(false)
	end
end)

deleteButton.Activated:Connect(function()
	local id = selectedId
	if id and request("remove", { id = id }) then
		selectWaypoint(nil)
	end
end)

nameBox.FocusLost:Connect(function()
	local wp = selectedId and findWaypoint(selectedId)
	if wp and nameBox.Text ~= wp.name then
		if not request("rename", { id = wp.id, name = nameBox.Text }) then
			nameBox.Text = wp.name
		end
	end
end)

goButton.Activated:Connect(function()
	local x, z = tonumber(xBox.Text), tonumber(zBox.Text)
	if not x or not z then
		showToast("Enter numbers for X and Z.", true)
		return
	end
	local y = nil
	local yText = string.match(yBox.Text, "^%s*(.-)%s*$")
	if yText ~= "" then
		y = tonumber(yText)
		if not y then
			showToast("Y must be a number, or blank to land on the ground.", true)
			return
		end
	end
	if request("travelCoords", { x = x, y = y, z = z }) then
		setOpen(false)
	end
end)

saveHereButton.Activated:Connect(function()
	local response = request("addHere")
	if response and response.id then
		selectWaypoint(findWaypoint(response.id))
	end
end)

-- Map input -----------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == CONFIG.ToggleKey then
		if not gameProcessed then
			setOpen(not isOpen)
		end
		return
	end
	if not isOpen then
		return
	end

	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		if dragInput or pinchStartScale then
			return
		end
		local pos = pointerPosition(input)
		if pointerBlocked(pos) or not isOver(mapFrame, pos) then
			return
		end
		dragInput, dragStart, dragCenterStart, dragMoved = input, pos, center, false
	elseif inputType == Enum.UserInputType.MouseButton2 then
		local pos = pointerPosition(input)
		if pointerBlocked(pos) or not isOver(mapFrame, pos) then
			return
		end
		local hit = waypointAt(pos - mapFrame.AbsolutePosition)
		if hit then
			selectWaypoint(hit)
		else
			placeWaypointAt(pos)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isOpen then
		return
	end
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseWheel then
		local pos = UserInputService:GetMouseLocation()
		if not pointerBlocked(pos) then
			zoomAt(pos, input.Position.Z > 0 and CONFIG.ZoomStep or 1 / CONFIG.ZoomStep)
		end
	elseif dragInput then
		local isMouseDrag = inputType == Enum.UserInputType.MouseMovement
			and dragInput.UserInputType == Enum.UserInputType.MouseButton1
		if isMouseDrag or input == dragInput then
			local delta = pointerPosition(input) - dragStart
			if delta.Magnitude > 4 then
				dragMoved = true
			end
			if dragMoved then
				center = dragCenterStart - delta / scale
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not dragInput then
		return
	end
	local ended = input == dragInput
		or (input.UserInputType == Enum.UserInputType.MouseButton1 and dragInput.UserInputType == Enum.UserInputType.MouseButton1)
	if not ended then
		return
	end
	local wasClick = not dragMoved
	local pos = pointerPosition(input)
	dragInput = nil
	if wasClick and isOpen then
		handleClick(pos)
	end
end)

UserInputService.TouchPinch:Connect(function(touchPositions, pinchScale, _velocity, state)
	if not isOpen then
		return
	end
	if state == Enum.UserInputState.Begin then
		pinchStartScale = scale
		dragInput = nil -- a pinch is never a click or a drag
	elseif state == Enum.UserInputState.Change and pinchStartScale and #touchPositions > 0 then
		local mid = Vector2.zero
		for _, p in ipairs(touchPositions) do
			mid += p
		end
		mid = mid / #touchPositions + GuiService:GetGuiInset()
		local target = math.clamp(pinchStartScale * pinchScale, CONFIG.MinScale, CONFIG.MaxScale)
		zoomAt(mid, target / scale)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		pinchStartScale = nil
	end
end)

openMap.OnClientEvent:Connect(function()
	setOpen(true)
end)

player:GetAttributeChangedSignal(CONFIG.RequiredAttribute):Connect(function()
	if not hasAbility() then
		setOpen(false)
	end
end)
