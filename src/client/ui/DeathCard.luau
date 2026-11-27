--!strict
-- When the lake takes you: the screen fades to black with the death sound (a drag under, or
-- the boat going down), then a paper card says what you did and which rule it was. After a
-- while (or a click, a tap or any key) the card goes and you are one of the drowned.
-- Also the pull warning when you are in the water (Rule 0): a sound and a dark pulse.
--
-- DeathCard.hold = true keeps the card up (Studio scenario "death_card").

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local client = script.Parent.Parent
local Events = require(client:WaitForChild("Events"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local DeathTexts = require(script.Parent:WaitForChild("DeathTexts"))

local DeathCard = {}

DeathCard.FADE = 1.4 -- seconds to black
DeathCard.CARD_AFTER = 1.0 -- seconds of black before the card
DeathCard.READ = 7 -- seconds the card stays before it can go by itself
DeathCard.hold = false

local gui: ScreenGui? = nil
local black: Frame? = nil
local card: Frame? = nil
local line: TextLabel? = nil
local ruleLine: TextLabel? = nil
local showing = false
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
	if b then
		tween(b, 1.5, { BackgroundTransparency = 1 })
	end
	showing = false
	for _, fn in doneListeners do
		task.spawn(fn)
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

-- Shows the card for a text id. `rule` picks the sound.
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
	b.BackgroundTransparency = 1
	tween(b, DeathCard.FADE, { BackgroundTransparency = 0 })
	if rule == "Knocking" then
		AudioDirector.play("boat-sink")
	else
		AudioDirector.play("death-drag")
	end
	task.delay(DeathCard.FADE + DeathCard.CARD_AFTER, function()
		if token ~= my then
			return
		end
		AudioDirector.play("death-sting")
		c.Visible = true
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
	gui = g
	local bl = Instance.new("Frame")
	bl.Name = "Black"
	bl.BackgroundColor3 = Color3.new(0, 0, 0)
	bl.BackgroundTransparency = 1
	bl.BorderSizePixel = 0
	bl.Size = UDim2.fromScale(1, 1)
	bl.Parent = g
	black = bl

	local c = Paper.sheet(g, "Card", UDim2.fromOffset(460, 190), UDim2.fromScale(0.5, 0.46), Vector2.new(0.5, 0.5), 22)
	c.BackgroundTransparency = 0
	c.Rotation = -1.2
	c.Visible = false
	card = c
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(460, 190)
	size.Parent = c
	local main = Paper.text(c, "Line", "", 28, Paper.hand())
	main.Size = UDim2.new(1, 0, 1, -44)
	main.TextScaled = false
	line = main
	local rl = Paper.text(c, "Rule", "", 22)
	rl.Position = UDim2.new(0, 0, 1, -32)
	rl.Size = UDim2.new(1, 0, 0, 30)
	rl.TextXAlignment = Enum.TextXAlignment.Right
	ruleLine = rl
	-- Narrow phones: keep the card inside the screen.
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X < 520 then
		c.Size = UDim2.new(0.9, 0, 0, 190)
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
		local t = io.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.Touch
			or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1
		then
			local my = token
			task.delay(0.2, function()
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
	}
end

return DeathCard
