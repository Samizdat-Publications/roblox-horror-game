--!strict
-- One small hint at the bottom of the screen: what the interact key or the cast button does
-- right now (bank the hold at the dock, refill the lantern, cast, wait for the bite).
-- Polish 3 (Neon's finale review): no hint at all during the finale, and no fishing hint
-- while the motor runs (the rule verbs, bail and knock, still show then).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local Knocking = require(client:WaitForChild("fx"):WaitForChild("Knocking"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local DeathCard = require(script.Parent:WaitForChild("DeathCard"))

local Prompt = {}

-- The hint for a moment, or "" for none. Pure: easy to read and to check.
function Prompt.textFor(
	phase: string,
	atDock: boolean,
	safe: boolean,
	hold: number,
	oil: number,
	refills: number,
	touch: boolean
): string
	local castKey = if touch then "Tap Cast" else "Click or Space"
	local useKey = if touch then "Tap Use" else "E"
	if phase == "Deciding" or phase == "Bite" or phase == "Reeling" then
		return ""
	end
	if atDock and hold > 0 then
		return string.format("%s  Bank the hold (%d)", useKey, hold)
	end
	if atDock and refills > 0 and oil < 0.9 then
		return useKey .. "  Refill the lantern"
	end
	if phase == "Waiting" then
		return "Wait for the bite.  X  Reel in"
	end
	if phase == "Idle" and not safe then
		return castKey .. "  Hold to cast, let go to throw"
	end
	if phase == "Idle" and safe then
		return "Row out of the beacon light to fish."
	end
	return ""
end

function Prompt.init()
	local gui = Paper.gui("DeadCalmPrompt", 4)
	local t = Paper.text(gui, "Hint", "", 18)
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 1, -40)
	t.Size = UDim2.fromOffset(520, 26)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextColor3 = Look.UI.paper
	t.TextStrokeColor3 = Look.UI.ink
	t.TextStrokeTransparency = 0.35
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- The moment a fail lands (the boat thrown) or the death card is up, no hint at all
		-- (Neon saw "Hold to cast" stay on through the Hum fail, 11/26/2026).
		if BoatFx.capsizing() or BoatFx.plunging() or DeathCard.showing() then
			t.Text = ""
			acc = 0
			return
		end
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local view = ViewState.get()
		local pv = ViewState.me()
		local seated = BoatClient.mySeat() ~= nil
		if
			pv == nil
			or not pv.alive
			or not seated
			or view.phase == "Cleared"
			or view.phase == "Failed"
			or view.phase == "Finale"
		then
			t.Text = ""
			return
		end
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		-- The rules' verbs come first: bail while the boat takes water, knock while it listens.
		-- (The hint names the key, never the answer: how many knocks is the book's business.)
		if (tonumber(view.flood) or 0) > 0.005 and pv.fishing ~= "Deciding" then
			t.Text = if touch then "Hold Use  Bail" else "Hold E  Bail"
			return
		end
		if Knocking.windowOpen() then
			t.Text = if touch then "Tap Knock  Knock on the hull" else "Q  Knock on the hull"
			return
		end
		if view.motorOn then
			t.Text = ""
			return
		end
		t.Text = Prompt.textFor(
			pv.fishing,
			ViewState.atDock(),
			view.safe,
			view.hold,
			view.oil,
			view.refills,
			UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		)
	end)
end

return Prompt
