--!strict
-- The title screen (LobbyState phase "Title"): the game's name over the dark lake seen from
-- the dock, Play, the difficulty (Normal or Nightmare), the Lake Rules page, and the owner's
-- title tape. The first player in the server is the host: only the host can pick the
-- difficulty and start; everyone else sees the host's choice and waits.
-- S5: Endless Nights (host only, once the host has cleared a run), the Locker (cosmetics,
-- everyone) and a small paper list of the best Endless nights (display names only).
-- Mouse and touch: the buttons. Keyboard: Enter plays, N toggles the difficulty, L opens the
-- Lake Rules, K opens the Locker (Endless Nights is its button only: E is the boat's
-- interact key). Gamepad: A plays, X toggles the
-- difficulty, Y opens the Lake Rules, R1 opens the Locker (the buttons are also
-- selectable).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local LobbyClient = require(client:WaitForChild("LobbyClient"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Input = require(client:WaitForChild("Input"))
local Camera = require(client:WaitForChild("Camera"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local BookState = require(script.Parent:WaitForChild("BookState"))
local ProfileClient = require(client:WaitForChild("ProfileClient"))
local Locker = require(script.Parent:WaitForChild("Locker"))

local Title = {}

local gui: ScreenGui? = nil
local playBtn: TextButton? = nil
local diffBtn: TextButton? = nil
local rulesBtn: TextButton? = nil
local status: TextLabel? = nil
local diffNote: TextLabel? = nil
local endlessBtn: TextButton? = nil
local lockerBtn: TextButton? = nil
local boardSheet: Frame? = nil
local boardText: TextLabel? = nil
local newNote: TextLabel? = nil
local newItems: { string } = {}
local shown = false
local theme: Sound? = nil

Title.DIFF_NOTE = {
	Normal = "The book as printed. Three tries if a night goes wrong.",
	Nightmare = "Shorter warnings, more of them, and the owner changes the book early. Two tries.",
} :: { [string]: string }

local function gamepad(): boolean
	return UserInputService.GamepadEnabled and #UserInputService:GetConnectedGamepads() > 0
end

local function refresh()
	local s = LobbyClient.get()
	local host = LobbyClient.isHost()
	local pad = gamepad()
	local p, d, r, st, dn = playBtn, diffBtn, rulesBtn, status, diffNote
	if p == nil or d == nil or r == nil or st == nil or dn == nil then
		return
	end
	p.Text = if pad then "Play  (A)" else "Play"
	p.Visible = host
	d.Text = "Difficulty: " .. s.difficulty .. (if pad and host then "  (X)" else "")
	d.Active = host
	d.AutoButtonColor = host
	r.Text = if pad then "The Lake Rules  (Y)" else "The Lake Rules"
	dn.Text = Title.DIFF_NOTE[s.difficulty] or ""
	local e = endlessBtn
	if e then
		e.Visible = host and s.endlessOpen
		e.Text = "Endless Nights"
	end
	local lk = lockerBtn
	if lk then
		lk.Text = if pad then "Locker  (R1)" else "Locker  (K)"
	end
	local bt = boardText
	if bt then
		local lines = {}
		if #s.board == 0 then
			table.insert(lines, "Nobody has lasted an Endless night yet.")
		else
			for _, row in s.board do
				table.insert(lines, string.format("%d. %s, night %d", row.rank, row.name, row.night))
			end
		end
		if s.memorySaves then
			table.insert(lines, "")
			table.insert(lines, "Test place: this list lasts only until the server closes.")
		end
		bt.Text = table.concat(lines, "\n")
	end
	local nn = newNote
	if nn then
		nn.Text = if #newItems > 0 then "New in your locker: " .. table.concat(newItems, ", ") .. "." else ""
		nn.Visible = #newItems > 0
	end
	if host then
		st.Text = if #s.players > 1
			then string.format("You have the boat. %d aboard.", #s.players)
			else "You have the boat. Others can join before you start."
	else
		st.Text = string.format("Waiting for %s to start.", s.hostName or "the host")
	end
end

local function setShown(on: boolean)
	local g = gui
	if g == nil or shown == on then
		return
	end
	shown = on
	g.Enabled = on
	Input.setBlocked("title", on)
	local bs = boardSheet
	if bs then
		bs.Visible = on
	end
	if on then
		Camera.applyShot("title")
		AudioDirector.stopTape(false)
		AudioDirector.playTape("tape-title")
		if theme == nil then
			theme = AudioDirector.loop("title-theme", nil)
		end
		if gamepad() and playBtn then
			GuiService.SelectedObject = if LobbyClient.isHost() then playBtn else rulesBtn
		end
	else
		Camera.applyShot("reset")
		local t = theme
		theme = nil
		if t then
			t:Destroy()
		end
		AudioDirector.stopTape(false)
		if GuiService.SelectedObject and g:IsAncestorOf(GuiService.SelectedObject) then
			GuiService.SelectedObject = nil
		end
	end
end

function Title.shown(): boolean
	return shown
end

local function play()
	if shown and LobbyClient.isHost() and BookState.current() == nil then
		AudioDirector.play("ui-stamp")
		LobbyClient.send("Mode", "Story")
		LobbyClient.send("Start")
	end
end

local function toggleDifficulty()
	if shown and LobbyClient.isHost() and BookState.current() == nil then
		local s = LobbyClient.get()
		AudioDirector.play("ui-pencil-scratch")
		LobbyClient.send("Difficulty", if s.difficulty == "Normal" then "Nightmare" else "Normal")
	end
end

local function lakeRules()
	if shown then
		BookState.toggle("lake")
	end
end

local function endless()
	local s = LobbyClient.get()
	if shown and LobbyClient.isHost() and s.endlessOpen and BookState.current() == nil then
		AudioDirector.play("ui-stamp")
		LobbyClient.send("Mode", "Endless")
		LobbyClient.send("Start")
	end
end

local function locker()
	if shown then
		newItems = {}
		Locker.toggle()
		refresh()
	end
end

function Title.init()
	local g = Paper.gui("DeadCalmTitle", 15)
	g.IgnoreGuiInset = true
	g.Enabled = false
	gui = g
	-- A soft dark wash so the paper reads over the lake.
	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = Look.Palette.water
	wash.BackgroundTransparency = 0.35
	wash.BorderSizePixel = 0
	wash.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = wash

	local sheet =
		Paper.sheet(g, "Sheet", UDim2.fromScale(0.46, 0.84), UDim2.new(0, 24, 0.5, 0), Vector2.new(0, 0.5), 16)
	sheet.BackgroundTransparency = 0.04
	sheet.Rotation = -1.2
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 0)
	limit.MaxSize = Vector2.new(520, 600)
	limit.Parent = sheet
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Paper.fit(10, 4, 12))
	list.Parent = sheet

	local big = Paper.fit(44, 26, 52)
	local name = Paper.text(sheet, "Name", Config.TITLE, big, Paper.hand())
	name.LayoutOrder = 1
	name.Size = UDim2.new(1, 0, 0, big + 8)
	local sub = Paper.text(
		sheet,
		"Sub",
		"Night shift on Blackwater Lake. Fill the cooler. Follow the rules.",
		Paper.fit(18, 12, 20)
	)
	sub.LayoutOrder = 2
	sub.Size = UDim2.new(1, 0, 0, Paper.fit(18, 12, 20) * 2 + 8)

	local bh = Paper.fit(46, 34, 52)
	local p = Paper.button(sheet, "Play", "Play", UDim2.new(1, 0, 0, bh))
	p.LayoutOrder = 3
	p.TextSize = Paper.fit(24, 16, 26)
	p.Activated:Connect(play)
	playBtn = p
	local d = Paper.button(sheet, "Difficulty", "Difficulty: Normal", UDim2.new(1, 0, 0, bh))
	d.LayoutOrder = 4
	d.TextSize = Paper.fit(20, 14, 22)
	d.Activated:Connect(toggleDifficulty)
	diffBtn = d
	local dn = Paper.text(sheet, "DifficultyNote", "", Paper.fit(15, 11, 17))
	dn.LayoutOrder = 5
	dn.Size = UDim2.new(1, 0, 0, Paper.fit(15, 11, 17) * 2 + 6)
	dn.TextTransparency = 0.25
	diffNote = dn
	local r = Paper.button(sheet, "LakeRules", "The Lake Rules", UDim2.new(1, 0, 0, bh))
	r.LayoutOrder = 6
	r.TextSize = Paper.fit(20, 14, 22)
	r.Activated:Connect(lakeRules)
	rulesBtn = r
	local e = Paper.button(sheet, "Endless", "Endless Nights", UDim2.new(1, 0, 0, bh))
	e.LayoutOrder = 7
	e.TextSize = Paper.fit(20, 14, 22)
	e.Visible = false
	e.Activated:Connect(endless)
	endlessBtn = e
	local st = Paper.text(sheet, "Status", "", Paper.fit(16, 11, 18), Paper.hand())
	st.LayoutOrder = 8
	st.Size = UDim2.new(1, 0, 0, Paper.fit(16, 11, 18) * 2 + 6)
	st.TextColor3 = Look.Palette.amendInk
	status = st

	-- Right side: the Locker button and the best Endless nights.
	local side = Paper.sheet(g, "Board", UDim2.fromScale(0.3, 0.6), UDim2.new(1, -24, 0.5, 0), Vector2.new(1, 0.5), 12)
	side.BackgroundTransparency = 0.06
	side.Rotation = 1.4
	local sideLimit = Instance.new("UISizeConstraint")
	sideLimit.MinSize = Vector2.new(190, 0)
	sideLimit.MaxSize = Vector2.new(340, 440)
	sideLimit.Parent = side
	local sideList = Instance.new("UIListLayout")
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Padding = UDim.new(0, Paper.fit(8, 4, 10))
	sideList.Parent = side
	local lk = Paper.button(side, "Locker", "Locker", UDim2.new(1, 0, 0, Paper.fit(40, 30, 46)))
	lk.LayoutOrder = 1
	lk.TextSize = Paper.fit(18, 13, 20)
	lk.Activated:Connect(locker)
	lockerBtn = lk
	local nn = Paper.text(side, "NewItems", "", Paper.fit(14, 10, 16), Paper.hand())
	nn.LayoutOrder = 2
	nn.Size = UDim2.new(1, 0, 0, Paper.fit(14, 10, 16) * 2 + 6)
	nn.TextColor3 = Look.Palette.amendInk
	nn.Visible = false
	newNote = nn
	local bh2 = Paper.fit(18, 13, 20)
	local bhead = Paper.text(side, "BoardHead", "Longest Endless nights", bh2, Paper.hand())
	bhead.LayoutOrder = 3
	local btx = Paper.text(side, "BoardRows", "", Paper.fit(14, 10, 16))
	btx.LayoutOrder = 4
	btx.Size = UDim2.new(1, 0, 1, -(Paper.fit(40, 30, 46) + bh2 + Paper.fit(14, 10, 16) * 2 + 40))
	btx.TextTruncate = Enum.TextTruncate.AtEnd
	boardText = btx
	side.Visible = false
	boardSheet = side

	UserInputService.InputBegan:Connect(function(io, processed)
		if not shown or BookState.current() ~= nil then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.ButtonA or (k == Enum.KeyCode.Return and not processed) then
			play()
		elseif k == Enum.KeyCode.ButtonX or (k == Enum.KeyCode.N and not processed) then
			toggleDifficulty()
		elseif k == Enum.KeyCode.ButtonY or (k == Enum.KeyCode.L and not processed) then
			lakeRules()
		elseif k == Enum.KeyCode.ButtonR1 or (k == Enum.KeyCode.K and not processed) then
			locker()
		end
	end)

	LobbyClient.onChange(function(s)
		refresh()
		setShown(s.phase == "Title")
	end)
	ProfileClient.onChange(function(prof)
		for _, key in prof.new do
			local slot, id = string.match(key, "^(%w+)%.(%w+)$")
			local it = if slot and id then ProfileClient.item(slot, id) else nil
			table.insert(newItems, if it then it.name else key)
		end
		refresh()
	end)
	-- Until the server answers, show nothing (a Studio scenario may already be running).
	task.delay(3, function()
		if LobbyClient.ready() then
			setShown(LobbyClient.get().phase == "Title")
		end
	end)
	refresh()
end

return Title
