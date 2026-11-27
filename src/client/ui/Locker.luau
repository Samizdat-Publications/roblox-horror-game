--!strict
-- The Locker (S5): a paper page from the title screen where you pick what you wear and what
-- the boat wears when you are the host. Three rows (lantern, boat paint, hat), one card per
-- item: a swatch, the name, and either "Wearing", "Tap to wear" or how to earn it. Locked
-- items cannot be picked; the server checks again (Core.Profile.equip).
-- Opened from the title (the Locker button, K, gamepad R1); it is a BookState page
-- ("locker"), so Escape, gamepad B, the dim around it or Close shuts it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local client = script.Parent.Parent
local ProfileClient = require(client:WaitForChild("ProfileClient"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local BookState = require(script.Parent:WaitForChild("BookState"))

local Locker = {}

local gui: ScreenGui? = nil
local list: ScrollingFrame? = nil
local note: TextLabel? = nil
local firstButton: GuiObject? = nil

local function gamepad(): boolean
	return UserInputService.GamepadEnabled and #UserInputService:GetConnectedGamepads() > 0
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function card(parent: Instance, it: ProfileClient.Item, order: number, h: number): TextButton
	local b = Paper.button(parent, "Item_" .. it.id, "", UDim2.fromOffset(math.floor(h * 2.6), h))
	b.LayoutOrder = order
	b.AutoButtonColor = it.unlocked
	b.BackgroundTransparency = if it.unlocked then 0.05 else 0.35
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = if it.equipped then 4 else 2
		stroke.Color = if it.equipped then Look.Palette.amendInk else Look.UI.ink
	end
	local sw = Instance.new("Frame")
	sw.Name = "Swatch"
	sw.AnchorPoint = Vector2.new(0, 0.5)
	sw.Position = UDim2.new(0, 8, 0.5, 0)
	sw.Size = UDim2.fromOffset(math.floor(h * 0.55), math.floor(h * 0.55))
	sw.BackgroundColor3 = it.color
	sw.BackgroundTransparency = if it.unlocked then 0 else 0.6
	sw.BorderSizePixel = 0
	sw.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = sw
	local textSize = Paper.fit(15, 11, 17)
	local label = Paper.text(b, "Label", "", textSize)
	label.Position = UDim2.fromOffset(math.floor(h * 0.55) + 16, 4)
	label.Size = UDim2.new(1, -(math.floor(h * 0.55) + 22), 1, -8)
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTransparency = if it.unlocked then 0 else 0.35
	local second = if it.equipped then "Wearing" elseif it.unlocked then "Tap to wear" else it.text
	label.Text = it.name .. "\n" .. second
	b.Activated:Connect(function()
		if it.unlocked and not it.equipped then
			if ProfileClient.equip(it.slot, it.id) then
				AudioDirector.play("ui-pencil-scratch")
			end
		end
	end)
	return b
end

local function fill()
	local f, n = list, note
	if f == nil or n == nil then
		return
	end
	clear(f)
	firstButton = nil
	local s = ProfileClient.get()
	local h = Paper.fit(54, 40, 62)
	local order = 0
	for _, slot in s.slots do
		order += 1
		local head = Paper.text(f, "Head_" .. slot, s.slotNames[slot] or slot, Paper.fit(20, 14, 22), Paper.hand())
		head.LayoutOrder = order
		order += 1
		local row = Instance.new("Frame")
		row.Name = "Row_" .. slot
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, h)
		row.LayoutOrder = order
		row.Parent = f
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(math.floor(h * 2.6), h)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row
		local i = 0
		for _, it in s.items do
			if it.slot == slot then
				i += 1
				local b = card(row, it, i, h)
				if firstButton == nil then
					firstButton = b
				end
			end
		end
	end
	local lines = {}
	table.insert(lines, "You earn these on the lake. The boat wears the host's lantern and paint.")
	if not s.ready then
		table.insert(lines, "Your locker is still loading.")
	elseif s.memory then
		table.insert(lines, "This is a test place: what you earn lasts only until the server closes.")
	elseif not s.canSave then
		table.insert(lines, "Your saved locker could not be reached. You can play; nothing new is saved this time.")
	end
	n.Text = table.concat(lines, " ")
end

function Locker.isOpen(): boolean
	return BookState.current() == "locker"
end

function Locker.toggle()
	BookState.toggle("locker")
end

function Locker.init()
	local g, _sheet, body, close = Paper.bookPage("DeadCalmLocker", 21, "Locker")
	gui = g
	local nt = Paper.text(body, "Note", "", Paper.fit(14, 11, 16))
	nt.Size = UDim2.new(1, 0, 0, Paper.fit(14, 11, 16) * 3 + 8)
	nt.TextTransparency = 0.2
	note = nt
	local top = Paper.fit(14, 11, 16) * 3 + 14
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "List"
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Position = UDim2.fromOffset(0, top)
	sc.Size = UDim2.new(1, 0, 1, -top)
	sc.CanvasSize = UDim2.new()
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollBarThickness = 6
	sc.ScrollBarImageColor3 = Look.UI.ink
	sc.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = sc
	list = sc

	close.Activated:Connect(function()
		BookState.close()
	end)
	local dim = g:FindFirstChild("Dim") :: TextButton
	dim.Activated:Connect(function()
		BookState.close()
	end)
	BookState.onChange(function(page)
		local open = page == "locker"
		if open then
			fill()
			if gamepad() and firstButton then
				GuiService.SelectedObject = firstButton
			end
		elseif GuiService.SelectedObject and g:IsAncestorOf(GuiService.SelectedObject) then
			GuiService.SelectedObject = nil
		end
		g.Enabled = open
	end)
	ProfileClient.onChange(function()
		if Locker.isOpen() then
			local sel = GuiService.SelectedObject
			local selName = if sel and g:IsAncestorOf(sel) then sel.Name else nil
			fill()
			if selName and list then
				local again = list:FindFirstChild(selName, true)
				if again and again:IsA("GuiObject") then
					GuiService.SelectedObject = again
				end
			end
		end
	end)
end

function Locker.gui(): ScreenGui?
	return gui
end

return Locker
