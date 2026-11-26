--!strict
-- The reel bar: shown while the local player's line is in the bite or the fight. A safe
-- band wanders along the bar (zoneLo..zoneHi from the NightView); the ink mark is the line
-- tension; the strip below fills with progress. Holding the reel raises tension, letting go
-- lowers it. A short note says what just happened to the line (the visual twin of the
-- fishing sounds): a bite, a snap, a lost fish.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local Events = require(client:WaitForChild("Events"))
local Paper = require(script.Parent:WaitForChild("Paper"))

local ReelBar = {}

ReelBar.WIDTH = 320

-- What a lost line says. Second person, short, practical.
ReelBar.LOST_TEXT = {
	Moving = "Too much way on. Hold still to cast.",
	DockLight = "Nothing bites in the beacon light.",
	Snap = "The line snapped.",
	Slack = "Too slack. It threw the hook.",
	Missed = "Missed the bite.",
	Cut = "Line in.",
	Bailing = "You let the line go to bail.",
} :: { [string]: string }

local root: Frame? = nil
local zone: Frame? = nil
local mark: Frame? = nil
local fill: Frame? = nil
local status: TextLabel? = nil
local note: TextLabel? = nil
local noteUntil = 0
local shownTension = 0
local clock = 0

local function showNote(text: string, seconds: number)
	local n = note
	if n then
		n.Text = text
		n.Visible = true
		noteUntil = clock + seconds
	end
end

function ReelBar.init()
	local gui = Paper.gui("DeadCalmReel", 5)

	local n = Paper.text(gui, "Note", "", 20, Paper.hand())
	n.AnchorPoint = Vector2.new(0.5, 1)
	n.Position = UDim2.new(0.5, 0, 1, -190)
	n.Size = UDim2.fromOffset(460, 30)
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.TextColor3 = Look.UI.paper
	n.TextStrokeColor3 = Look.UI.ink
	n.TextStrokeTransparency = 0.3
	n.Visible = false
	note = n

	local sheet = Paper.sheet(
		gui,
		"Reel",
		UDim2.fromOffset(ReelBar.WIDTH + 16, 70),
		UDim2.new(0.5, 0, 1, -110),
		Vector2.new(0.5, 1),
		8
	)
	sheet.Rotation = 0.8
	sheet.Visible = false
	root = sheet

	local s = Paper.text(sheet, "Status", "Reel", 16)
	s.Size = UDim2.new(1, 0, 0, 18)
	status = s

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(0, 22)
	bar.Size = UDim2.new(1, 0, 0, 18)
	bar.BackgroundColor3 = Look.UI.ink
	bar.BackgroundTransparency = 0.8
	bar.BorderSizePixel = 0
	bar.Parent = sheet

	local z = Instance.new("Frame")
	z.Name = "Zone"
	z.Size = UDim2.fromScale(0.3, 1)
	z.BackgroundColor3 = Color3.fromRGB(70, 110, 70)
	z.BackgroundTransparency = 0.35
	z.BorderSizePixel = 0
	z.Parent = bar
	zone = z

	local m = Instance.new("Frame")
	m.Name = "Tension"
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = UDim2.fromScale(0.35, 0.5)
	m.Size = UDim2.new(0, 4, 1, 8)
	m.BackgroundColor3 = Look.UI.ink
	m.BorderSizePixel = 0
	m.Parent = bar
	mark = m

	local strip = Instance.new("Frame")
	strip.Name = "Progress"
	strip.Position = UDim2.fromOffset(0, 46)
	strip.Size = UDim2.new(1, 0, 0, 6)
	strip.BackgroundColor3 = Look.UI.ink
	strip.BackgroundTransparency = 0.8
	strip.BorderSizePixel = 0
	strip.Parent = sheet
	local f = Instance.new("Frame")
	f.Name = "Fill"
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = Look.UI.ink
	f.BorderSizePixel = 0
	f.Parent = strip
	fill = f

	Events.onAny(function(e)
		local me = Players.LocalPlayer
		if e.player ~= me.UserId then
			return
		end
		local data = e.data or {}
		if e.kind == "Bite" then
			showNote("Bite! Reel now.", 1.8)
		elseif e.kind == "HookLost" then
			local text = ReelBar.LOST_TEXT[tostring(data.why)]
			if text then
				showNote(text, 2.5)
			end
		elseif e.kind == "Caught" then
			showNote("Got it. Hold it up to the light.", 2)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local nn = note
		if nn and nn.Visible and clock >= noteUntil then
			nn.Visible = false
		end
		local pv = ViewState.me()
		local phase = if pv then pv.fishing else "Idle"
		local show = phase == "Bite" or phase == "Reeling"
		local r = root
		if r == nil then
			return
		end
		r.Visible = show
		if not show or pv == nil then
			return
		end
		local st = status
		if st then
			st.Text = if phase == "Bite" then "Bite! Hold to set the hook." else "Hold to reel. Let go to ease off."
		end
		-- Smooth the mark between views (at most 10 a second).
		shownTension += (pv.tension - shownTension) * math.min(1, dt * 14)
		local zz, mm, ff = zone, mark, fill
		if zz then
			zz.Position = UDim2.fromScale(pv.zoneLo, 0)
			zz.Size = UDim2.fromScale(math.max(0, pv.zoneHi - pv.zoneLo), 1)
		end
		if mm then
			mm.Position = UDim2.fromScale(math.clamp(shownTension, 0, 1), 0.5)
			local inside = pv.tension >= pv.zoneLo and pv.tension <= pv.zoneHi
			mm.BackgroundColor3 = if inside then Look.UI.ink else Look.Palette.amendInk
		end
		if ff then
			ff.Size = UDim2.fromScale(math.clamp(pv.progress, 0, 1), 1)
		end
	end)
end

return ReelBar
