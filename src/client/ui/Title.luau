--!strict
-- The title screen (LobbyState phase "Title"): the game's name over the dark lake seen from
-- the dock, Play, the difficulty (Normal or Nightmare), the Lake Rules page, and the owner's
-- title tape. The first player in the server is the host: only the host can pick the
-- difficulty and start; everyone else sees the host's choice and waits.
-- Mouse and touch: the buttons. Keyboard: Enter plays, N toggles the difficulty, L opens the
-- Lake Rules. Gamepad: A plays, X toggles the difficulty, Y opens the Lake Rules (the
-- buttons are also selectable).

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

local Title = {}

local gui: ScreenGui? = nil
local playBtn: TextButton? = nil
local diffBtn: TextButton? = nil
local rulesBtn: TextButton? = nil
local status: TextLabel? = nil
local diffNote: TextLabel? = nil
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
	local st = Paper.text(sheet, "Status", "", Paper.fit(16, 11, 18), Paper.hand())
	st.LayoutOrder = 7
	st.Size = UDim2.new(1, 0, 0, Paper.fit(16, 11, 18) * 2 + 6)
	st.TextColor3 = Look.Palette.amendInk
	status = st

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
		end
	end)

	LobbyClient.onChange(function(s)
		refresh()
		setShown(s.phase == "Title")
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
