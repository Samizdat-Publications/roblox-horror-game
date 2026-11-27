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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local UserInputService = game:GetService("UserInputService")

local ViewState = require(script.Parent.Parent:WaitForChild("ViewState"))
local LobbyClient = require(script.Parent.Parent:WaitForChild("LobbyClient"))
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

local labels: { [string]: TextLabel } = {}
local oilFill: Frame? = nil
local oilBar: Frame? = nil
local paperFrame: Frame? = nil
local pulseClock = 0

HUD.OIL_BAR_HEIGHT = 14
HUD.PULSE_RED = Color3.fromRGB(205, 40, 28)

-- 0..1: how hard the oil bar pulses right now (0 = steady ink).
function HUD.oilPulse(view: NightView): number
	if view.phase == "Finale" then
		return 1
	end
	local warn = Look.Finale.oilWarn
	if view.lanternOn and view.oil < warn then
		return 1 - math.clamp(view.oil / warn, 0, 1) * 0.6
	end
	return 0
end

-- The last night's objective line, or nil on other nights (NightService adds the fields).
function HUD.objectiveText(view: NightView): string?
	local v: any = view
	if v.specialAboard == nil then
		return nil
	end
	return if v.specialAboard == true then "Owner's fish: aboard" else "Owner's fish: not yet"
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

local function render(view: NightView)
	labels.Night.Text = if view.mode == "Endless"
		then string.format("Endless night %d", view.night)
		else string.format("Night %d", view.night)
	labels.Clock.Text = HUD.clockText(view.clock)
	labels.Quota.Text = string.format("Quota %d / %d", view.banked, view.quota)
	local objective = HUD.objectiveText(view)
	local obj = labels.Objective
	obj.Visible = objective ~= nil
	obj.Text = objective or ""
	obj.TextColor3 = if (view :: any).specialAboard == true then Look.UI.ink else Look.Palette.amendInk
	local fill = oilFill
	local finale = view.phase == "Finale"
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(view.oil, 0, 1), 1)
	end
	labels.Oil.Text = if finale then "Oil: locked on" else "Oil"
	labels.Oil.TextColor3 = if finale then Look.Palette.amendInk else Look.UI.ink
	local motor = labels.Motor
	-- Not for the drowned: a dead player has no motor to mind (Scare polish 2; the paper said
	-- "Motor: on" over the drowned view).
	local me = ViewState.me()
	local on = view.motorOn == true and (me == nil or me.alive ~= false)
	if motor then
		motor.Visible = on
	end
end

-- Every frame: the oil bar pulses red while it matters.
local function stepPulse(dt: number)
	local fill, bar = oilFill, oilBar
	if fill == nil or bar == nil then
		return
	end
	local view = ViewState.get()
	local p = HUD.oilPulse(view)
	if p <= 0 then
		fill.BackgroundColor3 = Look.UI.ink
		bar.BackgroundColor3 = Look.UI.ink
		bar.BackgroundTransparency = 0.75
		return
	end
	-- Faster as the oil runs out: 1.2 to 3.5 pulses a second.
	local rate = 1.2 + 2.3 * (1 - math.clamp(view.oil, 0, 1))
	pulseClock += dt * rate * 2 * math.pi
	local w = 0.5 + 0.5 * math.sin(pulseClock)
	fill.BackgroundColor3 = Look.Palette.amendInk:Lerp(HUD.PULSE_RED, w * p)
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

	local oilRow = label(paper, "Oil", 5, f)
	oilRow.Text = "Oil"
	-- The bar has its own row: no text is ever drawn over it.
	local bar = Instance.new("Frame")
	bar.Name = "OilBar"
	bar.LayoutOrder = 6
	bar.Size = UDim2.new(1, 0, 0, HUD.OIL_BAR_HEIGHT)
	bar.BackgroundColor3 = Look.UI.ink
	bar.BackgroundTransparency = 0.75
	bar.BorderSizePixel = 0
	bar.Parent = paper
	oilBar = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Look.UI.ink
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
	row.Size = UDim2.fromOffset(150, 30)
	row.Parent = gui
	local function small(name: string, text: string, x: number, page: string)
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
		b.Size = UDim2.fromOffset(72, 26)
		b.Parent = row
		b.Activated:Connect(function()
			BookState.toggle(page)
		end)
	end
	small("Book", "Book  R", 0, "rules")
	small("Guide", "Guide  G", 78, "guide")

	local function layoutRow()
		local p = paperFrame
		if p then
			row.Position = UDim2.fromOffset(12, 12 + p.AbsoluteSize.Y + 6)
		end
		row.Visible = not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end
	render(ViewState.get())
	layoutRow()
	ViewState.onChange(function(v)
		render(v)
	end)
	paper:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRow)
	game:GetService("RunService").Heartbeat:Connect(stepPulse)
	LobbyClient.onChange(function(st)
		gui.Enabled = st.phase ~= "Title"
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return HUD
