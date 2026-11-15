-- AbilityMenu (LocalScript in StarterPlayer > StarterPlayerScripts)
--
-- Loads every ModuleScript in ReplicatedStorage > Abilities and gives
-- them one shared UI:
--   * HUD on the right edge showing each ability, its key and ON/OFF.
--     Click the HUD (or press the menu key, RightShift by default) to
--     open the menu.
--   * Menu: turn abilities on/off, use actions, and rebind every key to
--     any keyboard key, mouse button or controller button.
-- Keybinds are saved per player by the AbilitySettings server script.
--
-- ADDING AN ABILITY: drop a ModuleScript into ReplicatedStorage >
-- Abilities. It appears in the menu straight away, even mid play test.
-- The module returns a table like this (only Name, Type, Key and the
-- matching Enable/Disable or Activate are needed):
--
--   return {
--       Name = "Super jump",
--       Description = "Jump really high.",
--       Type = "Toggle",                 -- or "Action" (press to do something)
--       Key = Enum.KeyCode.J,            -- default key; players can rebind it
--       RequiredAttribute = "CanSuperJump", -- optional permission attribute
--       Binds = {                        -- optional extra rebindable keys
--           { Id = "Higher", Name = "Jump higher", Default = Enum.KeyCode.Equals },
--       },
--       Init = function(ctx) end,        -- optional, runs once when loaded
--       Enable = function(ctx) end,      -- Toggle: turned on (return false to refuse)
--       Disable = function(ctx) end,     -- Toggle: turned off
--       Activate = function(ctx) end,    -- Action: key pressed / Use clicked
--       OnBind = function(ctx, id) end,  -- optional: an extra bind was pressed
--       Destroy = function(ctx) end,     -- optional: module removed from folder
--   }
--
-- ctx gives the ability: ctx.Player, ctx.SetEnabled(bool), ctx.IsEnabled(),
-- ctx.IsBindDown(id), ctx.GetBindName(id), ctx.SetStatus(text) (shown in
-- the HUD while on) and ctx.Notify(text).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	FolderName = "Abilities",
	DefaultMenuKey = Enum.KeyCode.RightShift,
	SaveDelay = 2, -- seconds after the last change before saving
}

local COLORS = {
	Panel = Color3.fromRGB(20, 20, 24),
	Window = Color3.fromRGB(24, 24, 28),
	Card = Color3.fromRGB(33, 33, 39),
	Stroke = Color3.fromRGB(60, 60, 70),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(150, 150, 160),
	Button = Color3.fromRGB(50, 50, 58),
	Accent = Color3.fromRGB(60, 140, 255),
	On = Color3.fromRGB(46, 150, 88),
	OnText = Color3.fromRGB(110, 230, 150),
	RowOff = Color3.fromRGB(32, 32, 38),
	RowOn = Color3.fromRGB(30, 62, 44),
	Warning = Color3.fromRGB(240, 180, 70),
	Error = Color3.fromRGB(255, 92, 92),
	KeyBadge = Color3.fromRGB(55, 55, 64),
}

-- Friendlier names for keys whose enum names are long or unclear.
local SHORT_NAMES = {
	MouseButton1 = "Left click",
	MouseButton2 = "Right click",
	MouseButton3 = "Middle click",
	LeftShift = "L Shift",
	RightShift = "R Shift",
	LeftControl = "L Ctrl",
	RightControl = "R Ctrl",
	LeftAlt = "L Alt",
	RightAlt = "R Alt",
	LeftSuper = "L Win/Cmd",
	RightSuper = "R Win/Cmd",
	Space = "Space",
	Return = "Enter",
	Backspace = "Backspace",
	Tab = "Tab",
	CapsLock = "Caps Lock",
	LeftBracket = "[",
	RightBracket = "]",
	Semicolon = ";",
	Quote = "'",
	Comma = ",",
	Period = ".",
	Slash = "/",
	BackSlash = "\\",
	Minus = "-",
	Equals = "=",
	Backquote = "`",
	Up = "Up",
	Down = "Down",
	Left = "Left",
	Right = "Right",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "L Stick",
	ButtonR3 = "R Stick",
}

-- Mouse buttons arrive as UserInputTypes rather than KeyCodes.
local MOUSE_BINDS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local player = Players.LocalPlayer
local abilitiesFolder = ReplicatedStorage:WaitForChild(CONFIG.FolderName)
local remotesFolder = ReplicatedStorage:WaitForChild("CheatRemotes", 10)
local settingsRemote = remotesFolder and remotesFolder:WaitForChild("AbilitySettings", 10)

-- Keybind helpers -------------------------------------------------------

local function isValidBind(item)
	return typeof(item) == "EnumItem" and (item.EnumType == Enum.KeyCode or MOUSE_BINDS[item] == true)
end

local function serializeBind(bind)
	return bind and tostring(bind) or "none" -- e.g. "Enum.KeyCode.F"
end

-- Returns (bind or nil, isValid). "none" is a valid explicit "no key".
local function parseBind(text)
	if text == "none" then
		return nil, true
	end
	if type(text) ~= "string" then
		return nil, false
	end
	local enumName, itemName = string.match(text, "^Enum%.(%a+)%.(%w+)$")
	if enumName ~= "KeyCode" and enumName ~= "UserInputType" then
		return nil, false
	end
	local ok, item = pcall(function()
		return Enum[enumName][itemName]
	end)
	if ok and isValidBind(item) then
		return item, true
	end
	return nil, false
end

local function isGamepadKey(key)
	local name = key.Name
	return string.match(name, "^Button") ~= nil
		or string.match(name, "^DPad") ~= nil
		or string.match(name, "^Thumbstick") ~= nil
end

local function isBindDown(bind)
	if not bind then
		return false
	end
	if bind.EnumType == Enum.UserInputType then
		return UserInputService:IsMouseButtonPressed(bind)
	end
	if isGamepadKey(bind) then
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, bind)
	end
	if UserInputService:GetFocusedTextBox() then
		return false -- typing in chat shouldn't count
	end
	return UserInputService:IsKeyDown(bind)
end

local function inputMatches(input, bind)
	if not bind then
		return false
	end
	if bind.EnumType == Enum.UserInputType then
		return input.UserInputType == bind
	end
	return input.KeyCode == bind
end

local function bindDisplayName(bind)
	if not bind then
		return "None"
	end
	local short = SHORT_NAMES[bind.Name]
	if short then
		return short
	end
	if bind.EnumType == Enum.KeyCode and not isGamepadKey(bind) then
		-- Uses the player's keyboard layout (e.g. AZERTY) where possible.
		local ok, text = pcall(function()
			return UserInputService:GetStringForKeyCode(bind)
		end)
		if ok and type(text) == "string" and utf8.len(text) == 1 and text ~= " " then
			return string.upper(text)
		end
	end
	return bind.Name
end

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 3 })
	end)
end

-- State -------------------------------------------------------------------

local entries = {} -- loaded abilities, sorted by name
local entriesByModule = {}
local menuEntry = {
	id = "_menu",
	name = "Menu",
	bindList = { { id = "Main", name = "Open menu", default = CONFIG.DefaultMenuKey } },
	binds = { Main = CONFIG.DefaultMenuKey },
}
local savedBinds = {} -- [abilityId] = { [bindId] = "Enum.KeyCode.F" | "none" }
local hudVisible = true
local menuOpen = false
local capturing = nil -- { owner = entry, bindId = string } while waiting for a key
local captureEndedAt = 0

local refreshAll -- defined after the UI is built

-- Saving --------------------------------------------------------------------

local saveToken = 0
local function scheduleSave()
	if not settingsRemote then
		return
	end
	saveToken += 1
	local token = saveToken
	task.delay(CONFIG.SaveDelay, function()
		if token ~= saveToken then
			return
		end
		pcall(function()
			settingsRemote:InvokeServer("set", { binds = savedBinds, hudVisible = hudVisible })
		end)
	end)
end

local function rememberBind(owner, bindId)
	if type(savedBinds[owner.id]) ~= "table" then
		savedBinds[owner.id] = {}
	end
	savedBinds[owner.id][bindId] = serializeBind(owner.binds[bindId])
	scheduleSave()
end

local function applySavedBinds(owner)
	local saved = savedBinds[owner.id]
	for _, bindDef in ipairs(owner.bindList) do
		local bind = bindDef.default
		local text = type(saved) == "table" and saved[bindDef.id] or nil
		if text then
			local parsed, valid = parseBind(text)
			if valid then
				bind = parsed
			end
		end
		owner.binds[bindDef.id] = bind
	end
end

-- Every (owner, bindDef) pair, including the menu key.
local function allSlots()
	local slots = {}
	for _, bindDef in ipairs(menuEntry.bindList) do
		table.insert(slots, { owner = menuEntry, bindDef = bindDef })
	end
	for _, entry in ipairs(entries) do
		for _, bindDef in ipairs(entry.bindList) do
			table.insert(slots, { owner = entry, bindDef = bindDef })
		end
	end
	return slots
end

local function isBindShared(owner, bindId)
	local bind = owner.binds[bindId]
	if not bind then
		return false
	end
	for _, slot in ipairs(allSlots()) do
		if not (slot.owner == owner and slot.bindDef.id == bindId) and slot.owner.binds[slot.bindDef.id] == bind then
			return true
		end
	end
	return false
end

local function assignBind(owner, bindId, item)
	if owner ~= menuEntry and item == menuEntry.binds.Main then
		notify("Keybinds", bindDisplayName(item) .. " opens this menu. Pick another key or change the menu key first.")
		return
	end
	-- A key does one thing: take it off anything else that had it.
	for _, slot in ipairs(allSlots()) do
		local other, otherId = slot.owner, slot.bindDef.id
		if other.binds[otherId] == item and not (other == owner and otherId == bindId) then
			other.binds[otherId] = nil
			rememberBind(other, otherId)
			notify("Keybinds", string.format("%s removed from %s (%s)", bindDisplayName(item), other.name, slot.bindDef.name))
		end
	end
	owner.binds[bindId] = item
	rememberBind(owner, bindId)
end

local function clearBind(owner, bindId)
	if owner == menuEntry then
		return -- the menu always needs a key
	end
	owner.binds[bindId] = nil
	rememberBind(owner, bindId)
	refreshAll()
end

local function resetBinds()
	savedBinds = {}
	applySavedBinds(menuEntry)
	for _, entry in ipairs(entries) do
		applySavedBinds(entry)
	end
	scheduleSave()
	refreshAll()
	notify("Keybinds", "All keys reset to their defaults.")
end

-- Abilities -----------------------------------------------------------------

local function hasPermission(entry)
	local attribute = entry.def and entry.def.RequiredAttribute
	return attribute == nil or player:GetAttribute(attribute) == true
end

local function setEnabled(entry, on)
	local def = entry.def
	if not def or def.Type ~= "Toggle" or entry.error or on == entry.enabled then
		return
	end
	if on and not hasPermission(entry) then
		notify(entry.name, "You don't have this ability.")
		return
	end

	-- Set first so an ability calling ctx.SetEnabled from inside
	-- Enable/Disable doesn't loop.
	entry.enabled = on
	local handler = on and def.Enable or def.Disable
	if handler then
		local ok, result = pcall(handler, entry.ctx)
		if not ok then
			warn(string.format("[AbilityMenu] %s %s failed: %s", entry.name, on and "Enable" or "Disable", tostring(result)))
			entry.enabled = false
		elseif on and result == false then
			entry.enabled = false -- the ability refused (e.g. not spawned yet)
		end
	end

	if not hudVisible then
		notify(entry.name, entry.enabled and "On" or "Off")
	end
	refreshAll()
end

local function activate(entry)
	local def = entry.def
	if not def or def.Type ~= "Action" or entry.error then
		return
	end
	if not hasPermission(entry) then
		notify(entry.name, "You don't have this ability.")
		return
	end
	local ok, err = pcall(def.Activate, entry.ctx)
	if not ok then
		warn(string.format("[AbilityMenu] %s Activate failed: %s", entry.name, tostring(err)))
	end
end

local function triggerBind(entry, bindId)
	local def = entry.def
	if bindId == "Main" then
		if def.Type == "Toggle" then
			setEnabled(entry, not entry.enabled)
		else
			activate(entry)
		end
	elseif def.OnBind and (def.Type == "Action" or entry.enabled) then
		local ok, err = pcall(def.OnBind, entry.ctx, bindId)
		if not ok then
			warn(string.format("[AbilityMenu] %s OnBind failed: %s", entry.name, tostring(err)))
		end
	end
end

local function makeContext(entry)
	return {
		Player = player,
		Notify = function(text)
			notify(entry.name, tostring(text))
		end,
		SetEnabled = function(on)
			setEnabled(entry, on == true)
		end,
		IsEnabled = function()
			return entry.enabled
		end,
		IsBindDown = function(bindId)
			return isBindDown(entry.binds[bindId])
		end,
		GetBindName = function(bindId)
			return bindDisplayName(entry.binds[bindId])
		end,
		SetStatus = function(text)
			entry.status = text and tostring(text) or nil
			refreshAll()
		end,
	}
end

local function validateDefinition(def)
	if type(def) ~= "table" then
		return "the module must return a table"
	end
	if def.Type ~= "Toggle" and def.Type ~= "Action" then
		return 'Type must be "Toggle" or "Action"'
	end
	if def.Type == "Action" and type(def.Activate) ~= "function" then
		return "Action abilities need an Activate function"
	end
	return nil
end

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

local function stroke()
	return make("UIStroke", { Color = COLORS.Stroke, Thickness = 1 })
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
		VerticalAlignment = direction == Enum.FillDirection.Horizontal and Enum.VerticalAlignment.Center
			or Enum.VerticalAlignment.Top,
	})
end

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or COLORS.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	if not props.TextWrapped then
		props.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return make("TextLabel", props)
end

local function button(props)
	props.Font = Enum.Font.GothamBold
	props.TextSize = props.TextSize or 14
	props.TextColor3 = props.TextColor3 or COLORS.Text
	props.BackgroundColor3 = props.BackgroundColor3 or COLORS.Button
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return make("TextButton", props, { corner(6) })
end

local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Build the UI --------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "AbilityMenu",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- HUD (right edge)
local hud = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(220, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
	BackgroundTransparency = 0.15,
}, { corner(10), stroke(), padding(8), list(Enum.FillDirection.Vertical, 4) })
hud.Parent = gui

local hudHeader = make("TextButton", {
	LayoutOrder = 0,
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
})
hudHeader.Parent = hud
label({
	Size = UDim2.fromScale(0.5, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = COLORS.Muted,
	Text = "ABILITIES",
}).Parent = hudHeader
local hudHint = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.6, 1),
	TextSize = 11,
	TextColor3 = COLORS.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "",
})
hudHint.Parent = hudHeader

-- Menu window
local window = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.92, 0.84),
	BackgroundColor3 = COLORS.Window,
	Visible = false,
}, { corner(12), stroke(), make("UISizeConstraint", { MaxSize = Vector2.new(580, 600) }) })
window.Parent = gui

label({
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -70, 0, 24),
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	Text = "Abilities",
}).Parent = window
label({
	Position = UDim2.fromOffset(16, 38),
	Size = UDim2.new(1, -70, 0, 16),
	TextSize = 12,
	TextColor3 = COLORS.Muted,
	Text = "Click a key to rebind it, then press any key, mouse or controller button.",
}).Parent = window

local closeButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(32, 32),
	Text = "X",
	Modal = true, -- frees the mouse in first person while the menu is open
})
closeButton.Parent = window

local listFrame = make("ScrollingFrame", {
	Position = UDim2.fromOffset(12, 64),
	Size = UDim2.new(1, -24, 1, -64 - 60),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, {
	list(Enum.FillDirection.Vertical, 8),
	make("UIPadding", { PaddingRight = UDim.new(0, 10) }),
})
listFrame.Parent = window

local emptyLabel = label({
	LayoutOrder = 100000,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextWrapped = true,
	TextSize = 14,
	TextColor3 = COLORS.Muted,
	Text = "No abilities yet. Add ModuleScripts to ReplicatedStorage > Abilities.",
})
emptyLabel.Parent = listFrame

local footer = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(1, -24, 0, 36),
	BackgroundTransparency = 1,
}, { list(Enum.FillDirection.Horizontal, 8) })
footer.Parent = window

label({ LayoutOrder = 1, Size = UDim2.fromOffset(72, 32), TextSize = 13, TextColor3 = COLORS.Muted, Text = "Menu key" }).Parent =
	footer
local menuKeyButton = button({ LayoutOrder = 2, Size = UDim2.fromOffset(110, 32), TextSize = 13, Text = "" })
menuKeyButton.Parent = footer
local hudButton = button({ LayoutOrder = 3, Size = UDim2.fromOffset(92, 32), TextSize = 13, Text = "" })
hudButton.Parent = footer
local resetButton = button({ LayoutOrder = 4, Size = UDim2.fromOffset(104, 32), TextSize = 13, Text = "Reset keys" })
resetButton.Parent = footer

-- Keybind capture -----------------------------------------------------------

local function startCapture(owner, bindId)
	-- Ignore the click that just finished a capture (e.g. binding Left click).
	if os.clock() - captureEndedAt < 0.3 then
		return
	end
	capturing = { owner = owner, bindId = bindId }
	refreshAll()
end

-- Returns true if the input was used to finish a capture.
local function handleCapture(input, gameProcessed)
	-- Clicking or tapping on the UI (e.g. another key button) cancels
	-- instead of binding Left click. Click in the game world to bind it.
	local isUiClick = gameProcessed
		and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
	if isUiClick then
		capturing = nil
		refreshAll()
		return false
	end

	local item
	if input.KeyCode ~= Enum.KeyCode.Unknown then
		item = input.KeyCode
	elseif MOUSE_BINDS[input.UserInputType] then
		item = input.UserInputType
	else
		return false
	end
	local target = capturing
	capturing = nil
	captureEndedAt = os.clock()
	assignBind(target.owner, target.bindId, item)
	refreshAll()
	return true
end

local function refreshBindButton(owner, bindId, bindButton)
	if capturing and capturing.owner == owner and capturing.bindId == bindId then
		bindButton.Text = "Press a key..."
		bindButton.BackgroundColor3 = COLORS.Accent
		bindButton.TextColor3 = COLORS.Text
	else
		bindButton.Text = bindDisplayName(owner.binds[bindId])
		bindButton.BackgroundColor3 = COLORS.Button
		bindButton.TextColor3 = isBindShared(owner, bindId) and COLORS.Warning
			or owner.binds[bindId] and COLORS.Text
			or COLORS.Muted
	end
end

-- Cards (one per ability in the menu) --------------------------------------

local function createBindRow(entry, bindDef, order)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	})
	label({
		Size = UDim2.new(1, -150, 1, 0),
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		Text = bindDef.name,
	}).Parent = row

	local bindButton = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 0),
		Size = UDim2.fromOffset(110, 30),
		TextSize = 13,
		Text = "",
	})
	bindButton.Parent = row
	local clearButton = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(30, 30),
		TextSize = 12,
		Text = "X",
	})
	clearButton.Parent = row

	bindButton.Activated:Connect(function()
		startCapture(entry, bindDef.id)
	end)
	clearButton.Activated:Connect(function()
		if capturing then
			capturing = nil
		end
		clearBind(entry, bindDef.id)
	end)

	row.Parent = entry.ui.binds
	entry.ui.bindButtons[bindDef.id] = bindButton
end

local function createCard(entry)
	local card = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Card,
	}, { corner(8), padding(10), list(Enum.FillDirection.Vertical, 6) })

	local top = make("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	top.Parent = card

	local textColumn = make("Frame", {
		Size = UDim2.new(1, -96, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, { list(Enum.FillDirection.Vertical, 2) })
	textColumn.Parent = top

	local nameLabel = label({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = entry.name,
	})
	nameLabel.Parent = textColumn

	local descLabel = label({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		Text = "Loading...",
	})
	descLabel.Parent = textColumn

	local actionButton = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(84, 30),
		Text = "...",
	})
	actionButton.Parent = top

	local notice = label({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 12,
		TextColor3 = COLORS.Warning,
		Visible = false,
	})
	notice.Parent = card

	local bindsFrame = make("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, { list(Enum.FillDirection.Vertical, 4) })
	bindsFrame.Parent = card

	actionButton.Activated:Connect(function()
		local def = entry.def
		if not def then
			return
		end
		if def.Type == "Toggle" then
			setEnabled(entry, not entry.enabled)
		else
			menuOpen = false -- get out of the way of whatever the action opens
			activate(entry)
			refreshAll()
		end
	end)

	entry.ui = {
		card = card,
		name = nameLabel,
		desc = descLabel,
		action = actionButton,
		notice = notice,
		binds = bindsFrame,
		bindButtons = {},
	}
	card.Parent = listFrame
end

local function refreshCard(entry)
	local ui = entry.ui
	if not ui then
		return
	end
	ui.name.Text = entry.name
	ui.action.AutoButtonColor = true
	ui.action.TextColor3 = COLORS.Text

	if entry.error then
		ui.desc.Text = entry.module:GetFullName()
		ui.notice.Text = "Couldn't load: " .. entry.error
		ui.notice.TextColor3 = COLORS.Error
		ui.notice.Visible = true
		ui.action.Text = "Error"
		ui.action.BackgroundColor3 = COLORS.Button
		ui.action.AutoButtonColor = false
		ui.action.TextColor3 = COLORS.Error
		return
	end

	local def = entry.def
	if not def then
		ui.desc.Text = "Loading..."
		ui.action.Text = "..."
		return
	end

	ui.desc.Text = entry.description or ""
	ui.desc.Visible = ui.desc.Text ~= ""

	local allowed = hasPermission(entry)
	ui.notice.Visible = not allowed
	ui.notice.Text = "You don't have this ability."
	ui.notice.TextColor3 = COLORS.Warning

	if def.Type == "Toggle" then
		ui.action.Text = entry.enabled and "ON" or "OFF"
		ui.action.BackgroundColor3 = entry.enabled and COLORS.On or COLORS.Button
	else
		ui.action.Text = "Use"
		ui.action.BackgroundColor3 = COLORS.Accent
	end
	if not allowed then
		ui.action.BackgroundColor3 = COLORS.Button
		ui.action.TextColor3 = COLORS.Muted
		ui.action.AutoButtonColor = false
	end

	for bindId, bindButton in pairs(ui.bindButtons) do
		refreshBindButton(entry, bindId, bindButton)
	end
end

-- HUD rows --------------------------------------------------------------------

local function createHudRow(entry)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = COLORS.RowOff,
		Visible = false,
	}, { corner(6) })

	local badge = make("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(58, 20),
		BackgroundColor3 = COLORS.KeyBadge,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = COLORS.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, { corner(4) })
	badge.Parent = row

	local nameLabel = label({
		Position = UDim2.fromOffset(70, 0),
		Size = UDim2.new(1, -128, 1, 0),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = COLORS.Muted,
		Text = entry.name,
	})
	nameLabel.Parent = row

	local stateLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0, 50, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	stateLabel.Parent = row

	row.Parent = hud
	entry.hud = { row = row, badge = badge, name = nameLabel, state = stateLabel, wasOn = nil }
end

local function refreshHudRow(entry)
	local h = entry.hud
	if not h then
		return
	end
	local def = entry.def
	h.row.Visible = def ~= nil and not entry.error and hasPermission(entry)
	if not h.row.Visible then
		return
	end

	h.name.Text = entry.name
	h.badge.Text = bindDisplayName(entry.binds.Main)

	local on = def.Type == "Toggle" and entry.enabled
	if def.Type == "Toggle" then
		h.state.Text = on and (entry.status or "ON") or "OFF"
	else
		h.state.Text = ""
	end

	if h.wasOn ~= on then
		h.wasOn = on
		TweenService:Create(h.row, tweenInfo, { BackgroundColor3 = on and COLORS.RowOn or COLORS.RowOff }):Play()
		h.name.TextColor3 = on and COLORS.Text or COLORS.Muted
		h.state.TextColor3 = on and COLORS.OnText or COLORS.Muted
	end
end

-- Refresh -------------------------------------------------------------------

local function resort()
	table.sort(entries, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	for index, entry in ipairs(entries) do
		if entry.ui then
			entry.ui.card.LayoutOrder = index
		end
		if entry.hud then
			entry.hud.row.LayoutOrder = index
		end
	end
end

function refreshAll()
	for _, entry in ipairs(entries) do
		refreshCard(entry)
		refreshHudRow(entry)
	end

	window.Visible = menuOpen
	hud.Visible = hudVisible
	emptyLabel.Visible = #entries == 0
	hudHint.Text = "Menu: " .. bindDisplayName(menuEntry.binds.Main)
	hudButton.Text = hudVisible and "HUD: On" or "HUD: Off"
	refreshBindButton(menuEntry, "Main", menuKeyButton)
end

local function setMenuOpen(open)
	menuOpen = open
	if not open then
		capturing = nil
	end
	refreshAll()
end

-- Loading abilities ---------------------------------------------------------

local function loadAbility(module)
	if not module:IsA("ModuleScript") or entriesByModule[module] then
		return
	end

	local entry = {
		module = module,
		id = module.Name,
		name = module.Name,
		enabled = false,
		bindList = {},
		binds = {},
	}
	entriesByModule[module] = entry
	table.insert(entries, entry)
	createCard(entry)
	createHudRow(entry)
	resort()
	refreshAll()

	-- Load in its own thread so a slow or broken ability can't block the others.
	task.spawn(function()
		local ok, def = pcall(require, module)
		local problem = if ok then validateDefinition(def) else tostring(def)
		if entry.removed then
			return
		end
		if problem then
			entry.error = problem
			warn(string.format("[AbilityMenu] Couldn't load %s: %s", module:GetFullName(), problem))
			refreshAll()
			return
		end

		entry.name = type(def.Name) == "string" and def.Name or module.Name
		entry.description = type(def.Description) == "string" and def.Description or nil

		table.insert(entry.bindList, {
			id = "Main",
			name = def.Type == "Toggle" and "Turn on / off" or "Use",
			default = isValidBind(def.Key) and def.Key or nil,
		})
		if type(def.Binds) == "table" then
			for _, bind in ipairs(def.Binds) do
				if type(bind) == "table" and type(bind.Id) == "string" and bind.Id ~= "Main" then
					table.insert(entry.bindList, {
						id = bind.Id,
						name = type(bind.Name) == "string" and bind.Name or bind.Id,
						default = isValidBind(bind.Default) and bind.Default or nil,
					})
				end
			end
		end
		applySavedBinds(entry)
		for index, bindDef in ipairs(entry.bindList) do
			createBindRow(entry, bindDef, index)
		end

		entry.ctx = makeContext(entry)
		entry.def = def -- from here on the ability counts as loaded

		if type(def.Init) == "function" then
			local initOk, err = pcall(def.Init, entry.ctx)
			if not initOk then
				entry.error = "Init failed: " .. tostring(err)
				warn(string.format("[AbilityMenu] %s: %s", module:GetFullName(), entry.error))
			end
		end

		resort()
		refreshAll()
	end)
end

local function unloadAbility(module)
	local entry = entriesByModule[module]
	if not entry then
		return
	end
	entriesByModule[module] = nil
	entry.removed = true

	if entry.enabled then
		setEnabled(entry, false)
	end
	if entry.def and type(entry.def.Destroy) == "function" then
		pcall(entry.def.Destroy, entry.ctx)
	end
	if capturing and capturing.owner == entry then
		capturing = nil
	end

	local index = table.find(entries, entry)
	if index then
		table.remove(entries, index)
	end
	if entry.ui then
		entry.ui.card:Destroy()
	end
	if entry.hud then
		entry.hud.row:Destroy()
	end
	refreshAll()
end

-- Input ---------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if capturing then
		if handleCapture(input, gameProcessed) then
			return
		end
	end
	if gameProcessed then
		return
	end

	if inputMatches(input, menuEntry.binds.Main) then
		setMenuOpen(not menuOpen)
		return
	end

	for _, entry in ipairs(table.clone(entries)) do
		if entry.def and not entry.error then
			for _, bindDef in ipairs(entry.bindList) do
				if inputMatches(input, entry.binds[bindDef.id]) then
					triggerBind(entry, bindDef.id)
				end
			end
		end
	end
end)

hudHeader.Activated:Connect(function()
	setMenuOpen(not menuOpen)
end)
closeButton.Activated:Connect(function()
	setMenuOpen(false)
end)
menuKeyButton.Activated:Connect(function()
	startCapture(menuEntry, "Main")
end)
hudButton.Activated:Connect(function()
	hudVisible = not hudVisible
	scheduleSave()
	refreshAll()
end)
resetButton.Activated:Connect(resetBinds)

-- Losing a permission attribute turns that ability off.
player.AttributeChanged:Connect(function()
	for _, entry in ipairs(entries) do
		if entry.enabled and not hasPermission(entry) then
			setEnabled(entry, false)
		end
	end
	refreshAll()
end)

-- Start -----------------------------------------------------------------------

gui.Parent = player:WaitForChild("PlayerGui")

if settingsRemote then
	local ok, data = pcall(function()
		return settingsRemote:InvokeServer("get")
	end)
	if ok and type(data) == "table" then
		if type(data.binds) == "table" then
			savedBinds = data.binds
		end
		if type(data.hudVisible) == "boolean" then
			hudVisible = data.hudVisible
		end
	end
end
applySavedBinds(menuEntry)

for _, child in ipairs(abilitiesFolder:GetChildren()) do
	loadAbility(child)
end
abilitiesFolder.ChildAdded:Connect(loadAbility)
abilitiesFolder.ChildRemoved:Connect(unloadAbility)

refreshAll()
