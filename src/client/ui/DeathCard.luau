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
-- The card is built once, centered, sized from the screen width (about 70 percent, refit
-- only when the viewport changes), on a full-screen gui with no insets, and nothing moves it
-- while it is up (Neon saw it jump in the Neighbor recording, 11/26/2026). The ambience is
-- muted from the fade to black until the card goes (Scare polish 2).
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
DeathCard.READ = 5 -- seconds the card stays before it goes by itself (Scare polish 2: was 4)
DeathCard.MIN_READ = 0.6 -- a tap closes it only after this long (no accidental skips)
DeathCard.LIFT = 1.2 -- seconds for the black to lift into the drowned view
DeathCard.LEAD_IN = { Hum = 1.75 } :: { [string]: number }
-- Scare polish 2 (phones): the card is about 70 percent of the screen width, clamped, with
-- its height and text sizes following the width; dark ink on opaque paper with a dark edge.
DeathCard.WIDTH_SCALE = 0.7
DeathCard.MIN_WIDTH = 300
DeathCard.MAX_WIDTH = 980
DeathCard.ASPECT = 0.42 -- height / width
DeathCard.INK = Color3.fromRGB(14, 9, 5)
DeathCard.hold = false

local gui: ScreenGui? = nil
local black: Frame? = nil
local card: Frame? = nil
local line: TextLabel? = nil
local ruleLine: TextLabel? = nil
local lineCap: UITextSizeConstraint? = nil
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
	AudioDirector.muteAmbience("DeathCard", false)
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
	AudioDirector.muteAmbience("DeathCard", false)
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

-- Sizes the card from the screen: about 70 percent of the width (clamped, never wider than
-- the screen less a margin), height and text from that width. Only refit on a viewport
-- change, never while it animates.
local function fitCard()
	local c = card
	local cam = Workspace.CurrentCamera
	if c == nil or cam == nil then
		return
	end
	local vw = cam.ViewportSize.X
	if vw <= 10 then
		vw = 800
	end
	local w = math.clamp(math.floor(vw * DeathCard.WIDTH_SCALE), DeathCard.MIN_WIDTH, DeathCard.MAX_WIDTH)
	w = math.min(w, math.floor(vw - 24))
	local h = math.max(190, math.floor(w * DeathCard.ASPECT))
	c.Size = UDim2.fromOffset(w, h)
	local mainSize = math.clamp(math.floor(w / 17), 22, 54)
	local ruleSize = math.clamp(math.floor(w / 26), 18, 34)
	local l, r, cap = line, ruleLine, lineCap
	if l then
		l.TextSize = mainSize
		l.Size = UDim2.new(1, 0, 1, -(ruleSize + 14))
	end
	if cap then
		cap.MaxTextSize = mainSize
	end
	if r then
		r.TextSize = ruleSize
		r.Position = UDim2.new(0, 0, 1, -(ruleSize + 6))
		r.Size = UDim2.new(1, 0, 0, ruleSize + 4)
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
		-- No stray frog over the black or the card: the ambience is muted until it goes.
		AudioDirector.muteAmbience("DeathCard", true)
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
		UDim2.fromOffset(DeathCard.MIN_WIDTH, 190),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5),
		26
	)
	c.BackgroundTransparency = 0
	c.Rotation = -1.2
	c.ZIndex = 2
	c.Visible = false
	card = c
	local edge = Instance.new("UIStroke")
	edge.Color = DeathCard.INK
	edge.Thickness = 3
	edge.Transparency = 0.2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = c
	local main = Paper.text(c, "Line", "", 30, Paper.hand())
	main.Size = UDim2.new(1, 0, 1, -40)
	-- Scaled down to fit a long line, never above the size fitCard picks for this screen.
	main.TextScaled = true
	main.TextColor3 = DeathCard.INK
	main.TextXAlignment = Enum.TextXAlignment.Center
	main.TextYAlignment = Enum.TextYAlignment.Center
	main.LineHeight = 1.05
	main.ZIndex = 3
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 30
	cap.MinTextSize = 16
	cap.Parent = main
	line = main
	lineCap = cap
	-- The rule line in the same marker hand (the typewriter was too thin on a phone).
	local rl = Paper.text(c, "Rule", "", 22, Paper.hand())
	rl.Position = UDim2.new(0, 0, 1, -30)
	rl.Size = UDim2.new(1, 0, 0, 28)
	rl.TextColor3 = DeathCard.INK
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
