--!strict
-- When the lake takes you: the screen fades to black with the death sound (a drag under, or
-- the boat going down), then a paper card says what you did and what you should have done,
-- and which rule it was. After DeathCard.READ seconds (or a click, a tap or any key) the card
-- goes, the black lifts, and you are one of the drowned (Drowned takes the camera).
-- Also the pull warning when you are in the water (Rule 0): a sound and a dark pulse.
--
-- Some fails show you something first (the Hum throws the boat and pulls the camera under):
-- DeathCard.LEAD_IN[rule] holds the fade back that long.
--
-- The card is built once, centered, at a fixed size (offset pixels, narrowed only on small
-- screens), on a full-screen gui with no insets, and nothing moves it while it is up
-- (Neon saw it jump in the Neighbor recording, 11/26/2026).
--
-- DeathCard.hold = true keeps the card up (Studio scenario "death_card").

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local client = script.Parent.Parent
local Events = require(client:WaitForChild("Events"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local DeathTexts = require(script.Parent:WaitForChild("DeathTexts"))

local DeathCard = {}

DeathCard.FADE = 1.2 -- seconds to black
DeathCard.CARD_AFTER = 0.8 -- seconds of black before the card
DeathCard.READ = 4 -- seconds the card stays before it goes by itself
DeathCard.MIN_READ = 0.6 -- a tap closes it only after this long (no accidental skips)
DeathCard.LIFT = 1.2 -- seconds for the black to lift into the drowned view
DeathCard.LEAD_IN = { Hum = 1.75 } :: { [string]: number }
DeathCard.WIDTH = 480
DeathCard.HEIGHT = 200
DeathCard.hold = false

local gui: ScreenGui? = nil
local black: Frame? = nil
local card: Frame? = nil
local line: TextLabel? = nil
local ruleLine: TextLabel? = nil
local showing = false
local cardAt = 0
local token = 0
local doneListeners: { () -> () } = {}

function DeathCard.showing(): boolean
	return showing
end

-- Called once the card is gone and the player is one of the drowned.
function DeathCard.onDone(fn: () -> ())
	table.insert(doneListeners, fn)
end

local function tween(inst: Instance, seconds: number, props: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props):Play()
end

local function finish(my: number)
	if token ~= my or not showing then
		return
	end
	token += 1
	local b, c = black, card
	if c then
		c.Visible = false
	end
	showing = false
	-- The drowned camera starts under the black, then the black lifts into it.
	for _, fn in doneListeners do
		task.spawn(fn)
	end
	if b then
		tween(b, DeathCard.LIFT, { BackgroundTransparency = 1 })
	end
end

function DeathCard.close()
	token += 1
	showing = false
	local b, c = black, card
	if c then
		c.Visible = false
	end
	if b then
		b.BackgroundTransparency = 1
	end
end

-- A one-shot that comes in over a few frames instead of starting at full volume (the
-- sting's first transient read as a pop in Neon's review).
local function playSoft(name: string)
	local s = AudioDirector.play(name)
	if s then
		local v = s.Volume
		s.Volume = 0
		tween(s, 0.18, { Volume = v })
	end
end

-- Keeps the card a fixed size: full size on normal screens, narrower on small phones.
local function fitCard()
	local c = card
	local cam = Workspace.CurrentCamera
	if c == nil or cam == nil then
		return
	end
	local w = cam.ViewportSize.X
	if w > 10 and w < DeathCard.WIDTH + 40 then
		c.Size = UDim2.fromOffset(math.floor(w - 32), DeathCard.HEIGHT)
	else
		c.Size = UDim2.fromOffset(DeathCard.WIDTH, DeathCard.HEIGHT)
	end
end

-- Shows the card for a text id. `rule` picks the sound and the lead-in.
function DeathCard.show(textId: any, rule: string?)
	local b, c, l, r = black, card, line, ruleLine
	if b == nil or c == nil or l == nil or r == nil then
		return
	end
	token += 1
	local my = token
	showing = true
	local main, ruleText = DeathTexts.card(textId)
	l.Text = main
	r.Text = ruleText
	c.Visible = false
	fitCard()
	b.BackgroundTransparency = 1
	local lead = if rule then DeathCard.LEAD_IN[rule] or 0 else 0
	task.delay(lead, function()
		if token ~= my then
			return
		end
		tween(b, DeathCard.FADE, { BackgroundTransparency = 0 })
		if rule == "Knocking" then
			AudioDirector.play("boat-sink")
		elseif rule ~= "Hum" then
			-- The Hum plays its own drag as the camera goes under (fx/Hum).
			AudioDirector.play("death-drag")
		end
	end)
	task.delay(lead + DeathCard.FADE + DeathCard.CARD_AFTER, function()
		if token ~= my then
			return
		end
		b.BackgroundTransparency = 0
		playSoft("death-sting")
		c.Visible = true
		cardAt = os.clock()
		task.delay(DeathCard.READ, function()
			while DeathCard.hold and token == my do
				task.wait(0.5)
			end
			finish(my)
		end)
	end)
end

local function pulse()
	local b = black
	if b == nil or showing then
		return
	end
	b.BackgroundTransparency = 0.45
	tween(b, 1.2, { BackgroundTransparency = 1 })
end

function DeathCard.init()
	local g = Paper.gui("DeadCalmDeathCard", 30)
	g.IgnoreGuiInset = true
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.None
	end)
	gui = g
	local bl = Instance.new("Frame")
	bl.Name = "Black"
	bl.BackgroundColor3 = Color3.new(0, 0, 0)
	bl.BackgroundTransparency = 1
	bl.BorderSizePixel = 0
	bl.Size = UDim2.fromScale(1, 1)
	bl.Parent = g
	black = bl

	local c = Paper.sheet(
		g,
		"Card",
		UDim2.fromOffset(DeathCard.WIDTH, DeathCard.HEIGHT),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5),
		22
	)
	c.BackgroundTransparency = 0
	c.Rotation = -1.2
	c.ZIndex = 2
	c.Visible = false
	card = c
	local main = Paper.text(c, "Line", "", 24, Paper.hand())
	main.Size = UDim2.new(1, 0, 1, -40)
	main.TextScaled = false
	main.TextXAlignment = Enum.TextXAlignment.Center
	main.TextYAlignment = Enum.TextYAlignment.Center
	main.ZIndex = 3
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 24
	cap.MinTextSize = 14
	cap.Parent = main
	line = main
	local rl = Paper.text(c, "Rule", "", 22)
	rl.Position = UDim2.new(0, 0, 1, -30)
	rl.Size = UDim2.new(1, 0, 0, 28)
	rl.TextXAlignment = Enum.TextXAlignment.Right
	rl.ZIndex = 3
	ruleLine = rl
	fitCard()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitCard)
	end

	local me = Players.LocalPlayer
	Events.on("PlayerDied", function(e)
		if e.player ~= me.UserId then
			return
		end
		local data = e.data or {}
		DeathCard.show(data.text, if type(data.rule) == "string" then data.rule else nil)
	end)
	Events.on("DragWarning", function(e)
		if e.player == me.UserId or e.only == me.UserId then
			AudioDirector.play("water-pull-warning")
			pulse()
		end
	end)
	Events.on("NightStarted", function()
		DeathCard.close()
	end)
	-- A click, a tap or a key puts the card away once it has been up a moment.
	UserInputService.InputBegan:Connect(function(io, processed)
		local cc = card
		if processed or not showing or DeathCard.hold or cc == nil or not cc.Visible then
			return
		end
		if os.clock() - cardAt < DeathCard.MIN_READ then
			return
		end
		local t = io.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1
		then
			local my = token
			task.delay(0.1, function()
				finish(my)
			end)
		end
	end)
end

-- For checks.
function DeathCard.debugState(): { [string]: any }
	local l, r, c = line, ruleLine, card
	return {
		showing = showing,
		cardVisible = c ~= nil and c.Visible,
		text = if l then l.Text else nil,
		rule = if r then r.Text else nil,
		gui = gui ~= nil,
		position = if c then tostring(c.Position) else nil,
		size = if c then tostring(c.AbsoluteSize) else nil,
	}
end

return DeathCard
