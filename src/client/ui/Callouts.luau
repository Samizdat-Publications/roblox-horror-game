--!strict
-- Callouts: a wheel of the fixed phrases in Config.Callouts (no free text anywhere), opened
-- with C, gamepad D-pad up or the Call touch button (Input). Picking one sends a Callout
-- intent; Wave also sends the Wave intent (a friendly wave, and how the Neighbor gets you).
-- Every Callout event shows a speech tag over the speaker's head with the callout-blip, and a
-- line in a small feed at the bottom left (so a callout from behind you is not missed).
-- The Neighbor's fake callouts (data.fake, player = data.as) are shown exactly the same way:
-- this module never looks at `fake`.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local Events = require(client:WaitForChild("Events"))
local Input = require(client:WaitForChild("Input"))
local ViewState = require(client:WaitForChild("ViewState"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Paper = require(script.Parent:WaitForChild("Paper"))

local Callouts = {}

Callouts.TEXT = {
	FrogsStopped = "Frogs stopped.",
	LanternOut = "Lantern out.",
	LanternOn = "Lantern on.",
	HoldStill = "Hold still.",
	KnockOnce = "Knock once.",
	KnockTwice = "Knock twice.",
	DontKnock = "Don't knock.",
	DontWave = "Don't wave.",
	DontLook = "Don't look.",
	LookAtIt = "Look at it.",
	ThrowItBack = "Throw it back.",
	GoHome = "Go home.",
	Wave = "(waves)",
} :: { [string]: string }

Callouts.TAG_SECONDS = 4
Callouts.FEED_LINES = 4
Callouts.FEED_SECONDS = 7

local wheel: Frame? = nil
local buttons: { TextButton } = {}
local open = false
local feed: Frame? = nil
local feedItems: { { label: TextLabel, at: number } } = {}
local tags: { [number]: BillboardGui } = {}

function Callouts.text(phrase: any): string
	return Callouts.TEXT[tostring(phrase)] or tostring(phrase)
end

function Callouts.isOpen(): boolean
	return open
end

function Callouts.setOpen(on: boolean)
	local w = wheel
	if w == nil then
		return
	end
	if on then
		local pv = ViewState.me()
		if pv ~= nil and pv.alive == false then
			return -- the drowned only ring the bell
		end
	end
	open = on
	w.Visible = on
	if on and UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) and buttons[1] then
		GuiService.SelectedObject = buttons[1]
	elseif not on and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(w) then
		GuiService.SelectedObject = nil
	end
end

function Callouts.toggle()
	Callouts.setOpen(not open)
end

-- Says a phrase (the same path the wheel takes). Returns true if it was sent.
function Callouts.choose(phrase: string): boolean
	if Callouts.TEXT[phrase] == nil then
		return false
	end
	local pv = ViewState.me()
	if pv ~= nil and pv.alive == false then
		return false
	end
	Input.sendIntent("Callout", nil, nil, phrase)
	if phrase == "Wave" then
		Input.sendIntent("Wave")
	end
	Callouts.setOpen(false)
	return true
end

local function nameOf(id: any): string
	local p = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
	if p == Players.LocalPlayer then
		return "You"
	end
	return if p then p.DisplayName else "Someone"
end

local function pushFeed(text: string)
	local f = feed
	if f == nil then
		return
	end
	local l = Paper.text(f, "Line", text, 17)
	l.TextColor3 = Look.UI.paper
	l.TextStrokeColor3 = Look.UI.ink
	l.TextStrokeTransparency = 0.35
	l.Size = UDim2.new(1, 0, 0, 22)
	l.LayoutOrder = math.floor(os.clock() * 100)
	table.insert(feedItems, { label = l, at = os.clock() })
	while #feedItems > Callouts.FEED_LINES do
		local old = table.remove(feedItems, 1)
		if old then
			old.label:Destroy()
		end
	end
end

local function showTag(id: number, text: string)
	local p = Players:GetPlayerByUserId(id)
	local char = p and p.Character
	local head = char and char:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local old = tags[id]
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "CalloutTag"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(190, 38)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	local paper = Instance.new("TextLabel")
	paper.Name = "Text"
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = Look.UI.paper
	paper.BackgroundTransparency = 0.1
	paper.BorderSizePixel = 0
	paper.FontFace = Paper.hand()
	paper.TextSize = 22
	paper.TextColor3 = Look.UI.ink
	paper.Text = text
	paper.Parent = bb
	bb.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tags[id] = bb
	AudioDirector.play("callout-blip", head)
	task.delay(Callouts.TAG_SECONDS, function()
		if tags[id] == bb then
			tags[id] = nil
		end
		bb:Destroy()
	end)
end

local function onCallout(e: any)
	local data = e.data or {}
	local id = e.player
	if type(id) ~= "number" then
		return
	end
	local text = Callouts.text(data.phrase)
	showTag(id, text)
	pushFeed(nameOf(id) .. ": " .. text)
end

local function buildWheel(gui: ScreenGui)
	local w = Instance.new("Frame")
	w.Name = "Wheel"
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	w.Position = UDim2.fromScale(0.5, 0.5)
	w.Size = UDim2.fromOffset(440, 440)
	w.BackgroundTransparency = 1
	w.Visible = false
	w.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = w
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.Y < 520 then
		scale.Scale = math.max(0.6, cam.ViewportSize.Y / 520)
	end
	local center =
		Paper.sheet(w, "Center", UDim2.fromOffset(110, 44), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 4)
	local ct = Paper.text(center, "Text", "Say", 22, Paper.hand())
	ct.Size = UDim2.fromScale(1, 1)
	ct.TextXAlignment = Enum.TextXAlignment.Center
	ct.TextYAlignment = Enum.TextYAlignment.Center
	local n = #Config.Callouts
	for i, phrase in Config.Callouts do
		local a = (i - 1) / n * 2 * math.pi - math.pi / 2
		local b = Paper.button(w, phrase, Callouts.text(phrase), UDim2.fromOffset(132, 36))
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, math.cos(a) * 168, 0.5, math.sin(a) * 168)
		b.TextSize = 17
		b.LayoutOrder = i
		b.Activated:Connect(function()
			Callouts.choose(phrase)
		end)
		table.insert(buttons, b)
	end
	wheel = w
end

function Callouts.init()
	local gui = Paper.gui("DeadCalmCallouts", 12)
	buildWheel(gui)
	local f = Instance.new("Frame")
	f.Name = "Feed"
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, 16, 1, -110)
	f.Size = UDim2.fromOffset(340, 100)
	f.BackgroundTransparency = 1
	f.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = f
	feed = f

	Input.setCalloutHandler(Callouts.toggle)
	Events.on("Callout", onCallout)
	Events.on("PlayerDied", function(e)
		if e.player ~= Players.LocalPlayer.UserId and type(e.player) == "number" then
			pushFeed(nameOf(e.player) .. " is gone.")
		end
	end)
	UserInputService.InputBegan:Connect(function(io)
		if open and (io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.ButtonB) then
			Callouts.setOpen(false)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for i = #feedItems, 1, -1 do
				local item = feedItems[i]
				local age = now - item.at
				if age > Callouts.FEED_SECONDS then
					item.label:Destroy()
					table.remove(feedItems, i)
				elseif age > Callouts.FEED_SECONDS - 1.5 then
					item.label.TextTransparency = (age - (Callouts.FEED_SECONDS - 1.5)) / 1.5
					item.label.TextStrokeTransparency = 0.35 + item.label.TextTransparency * 0.65
				end
			end
		end
	end)
end

return Callouts
