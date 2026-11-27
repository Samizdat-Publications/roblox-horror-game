--!strict
-- The HUD is four small things (DESIGN.md): night, clock, quota, oil. Paper and ink, top
-- left, small. Reads the NightView from ViewState. While the outboard runs, a fifth line
-- says "Motor: on" (Neon could not tell the motor was running, 11/26/2026); it is hidden
-- while the local player is drowned.
-- S4: hidden on the title screen. Under the paper, two small buttons open the rulebook and
-- the Field Guide (mouse players; touch players have MobileButtons).
-- Polish 3 (Neon's finale review): the oil has its own thick bar on its own row, nothing
-- drawn over it; it pulses red as it drains low, and all through the finale (the lantern is
-- locked on and its oil is the clock: the label reads "Oil: locked on"). On the last night a
-- line under the quota says whether the owner's fish is aboard. The paper grows with its
-- rows (AutomaticSize).
-- Phone pass (11/26/2026): the oil label and its bar share one line; on screens under 450 px
-- tall the paper is compact (see HUD.COMPACT_BELOW). The Book and Guide row hides on touch
-- (Input.touch).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local UserInputService = game:GetService("UserInputService")

local ViewState = require(script.Parent.Parent:WaitForChild("ViewState"))
local LobbyClient = require(script.Parent.Parent:WaitForChild("LobbyClient"))
local Input = require(script.Parent.Parent:WaitForChild("Input"))
local BookState = require(script.Parent:WaitForChild("BookState"))

type NightView = Types.NightView

local HUD = {}

local function font(name: string): Font
	local ok, f = pcall(function()
		return Font.fromEnum((Enum.Font :: any)[name])
	end)
	if ok and f then
		return f
	end
	return Font.fromEnum(Enum.Font.SourceSans)
end

-- "10:42 PM" from game hours (22.0 is 10 PM, 29.0 is 5 AM).
function HUD.clockText(hours: number): string
	local h = math.floor(hours) % 24
	local m = math.floor((hours - math.floor(hours)) * 60)
	local suffix = if h >= 12 then "PM" else "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

-- M8 polish (Neon: the dawn banner overlapped the HUD paper): other screens can hide the HUD
-- for a while by key (fx/Finale under the dawn banner). Shown again when every key is off.
local hideKeys: { [string]: boolean } = {}
local hudGui: ScreenGui? = nil
local lobbyShows = true

local function applyEnabled()
	local g = hudGui
	if g then
		g.Enabled = lobbyShows and next(hideKeys) == nil
	end
end

function HUD.setHidden(key: string, on: boolean)
	hideKeys[key] = if on then true else nil
	applyEnabled()
end

function HUD.hidden(): boolean
	return next(hideKeys) ~= nil
end

local labels: { [string]: TextLabel } = {}
local oilFill: Frame? = nil
local oilBar: Frame? = nil
local paperFrame: Frame? = nil
local pulseClock = 0

HUD.OIL_BAR_HEIGHT = 14
HUD.PULSE_RED = Color3.fromRGB(205, 40, 28)
HUD.PULSE_BRIGHT = Color3.fromRGB(255, 96, 70)
-- M8 polish (Neon: on night 5 the bar "looks empty and black", then "snaps to full red at
-- 4 AM"): a full bar filled with ink read as an empty black slot. Outside the finale the oil
-- is now a lamp-oil amber on a pale ink track, so its real level reads from the first second
-- of every night; the finale's red takes over at the bell (the refill to full is real).
HUD.OIL_FILL = Color3.fromRGB(214, 140, 52)
local shownOil = 1 -- the oil fill as drawn (eased toward the real level)

-- 0..1: how hard the oil bar pulses right now (0 = steady). Finale v6 (Neon: "the oil bar
-- vanishes and becomes a static red square"): in the finale the bar stays a bar, filled red
-- (HUD.isRed), and pulses only once the oil is under Look.Finale.oilWarnFinale.
function HUD.oilPulse(view: NightView): number
	if view.phase == "Finale" then
		local w = Look.Finale.oilWarnFinale
		if view.oil < w then
			return 1 - math.clamp(view.oil / w, 0, 1) * 0.5
		end
		return 0
	end
	local warn = Look.Finale.oilWarn
	if view.lanternOn and view.oil < warn then
		return 1 - math.clamp(view.oil / warn, 0, 1) * 0.6
	end
	return 0
end

-- The last night's objective line, or nil on other nights (NightService adds the fields).
-- `short` (compact phone paper): "Fish: aboard" (Neon saw "Owner's fish: aboa" clipped).
function HUD.objectiveText(view: NightView, short: boolean?): string?
	local v: any = view
	if v.specialAboard == nil then
		return nil
	end
	local head = if short then "Fish: " else "Owner's fish: "
	return head .. (if v.specialAboard == true then "aboard" else "not yet")
end

-- The paper's width: wide enough for its longest line (text width plus the side padding and
-- a little slack for the paper's tilt), never narrower than `base`, never wider than `cap`.
function HUD.paperWidth(longestText: number, base: number, cap: number): number
	return math.clamp(math.ceil(longestText) + 16 + 8, base, math.max(base, cap))
end

local function label(parent: Instance, name: string, order: number, f: Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, Look.UI.hudTextSize + 4)
	t.BackgroundTransparency = 1
	t.FontFace = f
	t.TextSize = Look.UI.hudTextSize
	t.TextColor3 = Look.UI.ink
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = ""
	t.Parent = parent
	labels[name] = t
	return t
end

-- Compact on short screens (phones, under 450 px tall): smaller type, a narrower paper, the
-- night and the clock on one line, the oil label and bar on one line (phone check on the
-- 705 by 338 Galaxy A06, 11/26/2026).
HUD.COMPACT_BELOW = 450
HUD.COMPACT_TEXT = 14
local compact = false

function HUD.isCompact(viewportHeight: number): boolean
	return viewportHeight < HUD.COMPACT_BELOW
end

-- Widens the paper to its longest visible line (set up in HUD.init).
local paperBase = 180
local function fitPaper()
	local p = paperFrame
	if p == nil then
		return
	end
	local longest = 0
	for name, t in labels do
		if name ~= "Oil" and t.Visible then
			longest = math.max(longest, t.TextBounds.X)
		end
	end
	local cam = workspace.CurrentCamera
	local cap = if cam then cam.ViewportSize.X * 0.45 else 400
	p.Size = UDim2.fromOffset(HUD.paperWidth(longest, paperBase, cap), 0)
end

local function render(view: NightView)
	local nightText = if view.mode == "Endless"
		then string.format("Endless night %d", view.night)
		else string.format("Night %d", view.night)
	if compact then
		labels.Night.Text = nightText .. "   " .. HUD.clockText(view.clock)
		labels.Clock.Visible = false
	else
		labels.Night.Text = nightText
		labels.Clock.Visible = true
	end
	labels.Clock.Text = HUD.clockText(view.clock)
	-- Polish round 3: capped at the target once met (it read "Quota 5 / 3" after the finale).
	labels.Quota.Text = string.format("Quota %d / %d", math.min(view.banked, view.quota), view.quota)
	local objective = HUD.objectiveText(view, compact)
	local obj = labels.Objective
	obj.Visible = objective ~= nil
	obj.Text = objective or ""
	obj.TextColor3 = if (view :: any).specialAboard == true then Look.UI.ink else Look.Palette.amendInk
	local finale = view.phase == "Finale"
	-- The fill's size is eased toward the oil every frame (stepPulse), so the drain shows.
	-- The label stays "Oil" (a longer label squeezed the bar into a square in the finale).
	labels.Oil.Text = "Oil"
	labels.Oil.TextColor3 = if finale and not HUD.oilHeld() then Look.Palette.amendInk else Look.UI.ink
	local motor = labels.Motor
	-- Not for the drowned: a dead player has no motor to mind (Scare polish 2; the paper said
	-- "Motor: on" over the drowned view).
	local me = ViewState.me()
	local on = view.motorOn == true and (me == nil or me.alive ~= false)
	if motor then
		motor.Visible = on
	end
	fitPaper()
end

-- Polish round 2 (Neon finale v7: "at 4 AM the oil jumps from about 75 percent orange to full
-- red"). Both changes are real: Core refills the lantern at the bell and the finale paints the
-- bar red. Before, a gap over 0.25 snapped the fill in one frame and the colour flipped with
-- the phase. Now a jump (a refill, a new night) eases over OIL_EASE seconds, and the colour
-- crosses from amber to red over the same time.
HUD.OIL_EASE = 0.8
HUD.OIL_JUMP = 0.08 -- a change this big between two frames is a jump, not the drain
local oilEase: { from: number, to: number, t: number }? = nil
local lastOilTarget: number? = nil
local redMix = 0 -- 0 amber (night), 1 red (finale), eased
-- Polish round 3: fx/Finale holds the bar's night look (its colour and its drawn level) from the
-- cue until the first toll, so the red, the refill, the turn and the caption land as one beat.
local oilHolds: { [string]: boolean } = {}

function HUD.holdOil(key: string, on: boolean)
	oilHolds[key] = if on then true else nil
end

function HUD.oilHeld(): boolean
	return next(oilHolds) ~= nil
end

-- Smoothstep, 0..1.
function HUD.ease(u: number): number
	local x = math.clamp(u, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The drawn oil level this frame: follows the drain, eases over OIL_EASE across a jump.
local function stepOilLevel(target: number, dt: number): number
	local last = lastOilTarget
	lastOilTarget = target
	if last ~= nil and math.abs(target - last) > HUD.OIL_JUMP then
		oilEase = { from = shownOil, to = target, t = 0 }
	end
	local e = oilEase
	if e then
		e.to = target -- the drain goes on while it eases
		e.t += dt
		local u = e.t / HUD.OIL_EASE
		shownOil = e.from + (e.to - e.from) * HUD.ease(u)
		if u >= 1 then
			oilEase = nil
		end
	else
		shownOil += (target - shownOil) * math.clamp(dt * 6, 0, 1)
	end
	return shownOil
end

-- Every frame: the oil bar pulses red while it matters.
local function stepPulse(dt: number)
	local fill, bar = oilFill, oilBar
	if fill == nil or bar == nil then
		return
	end
	local view = ViewState.get()
	-- The drain shows: the fill eases toward the oil level instead of jumping with each update.
	local held = HUD.oilHeld()
	local target = if held then shownOil else math.clamp(view.oil, 0, 1)
	fill.Size = UDim2.fromScale(stepOilLevel(target, dt), 1)
	local red = view.phase == "Finale" and not held
	redMix = math.clamp(redMix + (if red then 1 else -1) * dt / HUD.OIL_EASE, 0, 1)
	local k = HUD.ease(redMix)
	local fillBase = HUD.OIL_FILL:Lerp(HUD.PULSE_RED, k)
	local trackBase = Look.UI.ink:Lerp(HUD.PULSE_RED, k)
	local trackAlpha = 0.8 - 0.02 * k
	local p = HUD.oilPulse(view)
	if p <= 0 then
		-- In the finale the bar is red all along (the oil is the clock); otherwise amber.
		fill.BackgroundColor3 = fillBase
		bar.BackgroundColor3 = trackBase
		bar.BackgroundTransparency = trackAlpha
		fill.BackgroundTransparency = 0
		return
	end
	-- Faster as the oil runs out: 1.2 to 3.5 pulses a second.
	local rate = 1.2 + 2.3 * (1 - math.clamp(view.oil, 0, 1))
	pulseClock += dt * rate * 2 * math.pi
	local w = 0.5 + 0.5 * math.sin(pulseClock)
	if red then
		-- Red throughout; the pulse flashes it toward a bright warning red and back.
		fill.BackgroundColor3 = fillBase:Lerp(HUD.PULSE_BRIGHT, w * p)
		fill.BackgroundTransparency = 0.25 * (1 - w) * p
	else
		fill.BackgroundColor3 = fillBase:Lerp(HUD.PULSE_RED, w * p)
		fill.BackgroundTransparency = 0
	end
	bar.BackgroundColor3 = HUD.PULSE_RED
	bar.BackgroundTransparency = 0.8 - 0.25 * w * p
end

function HUD.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeadCalmHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.Position = UDim2.fromOffset(12, 12)
	paper.Size = UDim2.fromOffset(180, 0)
	paper.AutomaticSize = Enum.AutomaticSize.Y
	paper.BackgroundColor3 = Look.UI.paper
	paper.BackgroundTransparency = Look.UI.hudPaperTransparency
	paper.BorderSizePixel = 0
	paper.Rotation = -1.5
	paper.Parent = gui
	paperFrame = paper

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = paper

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = paper

	local f = font(Look.UI.typewriterFont)
	label(paper, "Night", 1, f)
	label(paper, "Clock", 2, f)
	label(paper, "Quota", 3, f)
	local objective = label(paper, "Objective", 4, f)
	objective.Visible = false

	-- One line: the "Oil" label, then the bar filling the rest of the row (a UIFlexItem in a
	-- horizontal list). No text is ever drawn over the bar.
	local oilLine = Instance.new("Frame")
	oilLine.Name = "OilLine"
	oilLine.LayoutOrder = 5
	oilLine.BackgroundTransparency = 1
	oilLine.Size = UDim2.new(1, 0, 0, Look.UI.hudTextSize + 4)
	oilLine.Parent = paper
	local lineList = Instance.new("UIListLayout")
	lineList.FillDirection = Enum.FillDirection.Horizontal
	lineList.VerticalAlignment = Enum.VerticalAlignment.Center
	lineList.SortOrder = Enum.SortOrder.LayoutOrder
	lineList.Padding = UDim.new(0, 6)
	lineList.Parent = oilLine
	local oilRow = label(oilLine, "Oil", 1, f)
	oilRow.Text = "Oil"
	oilRow.Size = UDim2.fromScale(0, 1)
	oilRow.AutomaticSize = Enum.AutomaticSize.X
	local bar = Instance.new("Frame")
	bar.Name = "OilBar"
	bar.LayoutOrder = 2
	bar.Size = UDim2.new(0.6, 0, 0, HUD.OIL_BAR_HEIGHT)
	bar.BackgroundColor3 = Look.UI.ink
	bar.BackgroundTransparency = 0.75
	bar.BorderSizePixel = 0
	bar.Parent = oilLine
	pcall(function()
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = bar
	end)
	oilBar = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HUD.OIL_FILL
	fill.BorderSizePixel = 0
	fill.Parent = bar
	oilFill = fill

	local motor = label(paper, "Motor", 7, f)
	motor.Text = "Motor: on"
	motor.Visible = false

	-- The book and the guide, for mouse players.
	local row = Instance.new("Frame")
	row.Name = "Books"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 0)
	row.Size = UDim2.fromOffset(340, 30)
	row.Parent = gui
	local function small(name: string, text: string, x: number, w: number, onClick: () -> ())
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = text
		b.FontFace = f
		b.TextSize = 15
		b.TextColor3 = Look.UI.ink
		b.BackgroundColor3 = Look.UI.paper
		b.BackgroundTransparency = Look.UI.hudPaperTransparency
		b.BorderSizePixel = 0
		b.Position = UDim2.fromOffset(x, 0)
		b.Size = UDim2.fromOffset(w, 26)
		b.Parent = row
		b.Activated:Connect(onClick)
	end
	small("Book", "Book  R", 0, 72, function()
		BookState.toggle("rules")
	end)
	small("Guide", "Guide  G", 78, 72, function()
		BookState.toggle("guide")
	end)
	-- Polish round 3 (Neon hum-fail v5: no hint how to cut the motor or put out the lantern):
	-- the same toggles as the M and F keys (Input.toggle). Hidden on touch with the rest of the
	-- row; MobileButtons has its own Motor and Light buttons.
	small("Motor", "Motor  M", 156, 80, function()
		Input.toggle("ToggleMotor")
	end)
	small("Lantern", "Lantern  F", 242, 96, function()
		Input.toggle("ToggleLantern")
	end)

	local function layoutRow()
		local p = paperFrame
		if p then
			row.Position = UDim2.fromOffset(12, 12 + p.AbsoluteSize.Y + 6)
		end
		row.Visible = not Input.touch()
	end

	local function applySize()
		local cam = workspace.CurrentCamera
		compact = cam ~= nil and HUD.isCompact(cam.ViewportSize.Y)
		local ts = if compact then HUD.COMPACT_TEXT else Look.UI.hudTextSize
		paperBase = if compact then 150 else 180
		paper.Size = UDim2.fromOffset(paperBase, 0)
		for _, t in labels do
			t.TextSize = ts
			if t.Name ~= "Oil" then
				t.Size = UDim2.new(1, 0, 0, ts + 4)
			end
		end
		oilLine.Size = UDim2.new(1, 0, 0, ts + 4)
		bar.Size = UDim2.new(0.6, 0, 0, if compact then 10 else HUD.OIL_BAR_HEIGHT)
		pad.PaddingTop = UDim.new(0, if compact then 4 else 6)
		pad.PaddingBottom = UDim.new(0, if compact then 4 else 6)
		list.Padding = UDim.new(0, if compact then 1 else 2)
		render(ViewState.get())
	end
	applySize()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applySize)
	end
	layoutRow()
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(layoutRow)
	end)
	ViewState.onChange(function(v)
		render(v)
	end)
	paper:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRow)
	-- Text measures in only once the font has loaded: re-fit the paper when any line does.
	for name, t in labels do
		if name ~= "Oil" then
			t:GetPropertyChangedSignal("TextBounds"):Connect(fitPaper)
		end
	end
	game:GetService("RunService").Heartbeat:Connect(stepPulse)
	hudGui = gui
	LobbyClient.onChange(function(st)
		lobbyShows = st.phase ~= "Title"
		applyEnabled()
	end)
	applyEnabled()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return HUD
