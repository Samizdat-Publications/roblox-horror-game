--!strict
-- The HUD is four small things (DESIGN.md): night, clock, quota, oil. Paper and ink, top
-- left, small. Reads the NightView from ViewState. While the outboard runs, a fifth line
-- says "Motor: on" (Neon could not tell the motor was running, 11/26/2026).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local ViewState = require(script.Parent.Parent:WaitForChild("ViewState"))

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
local paperFrame: Frame? = nil

local function rowsHeight(rows: number): number
	return rows * (Look.UI.hudTextSize + 4) + (rows - 1) * 2 + 14
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
	labels.Night.Text = string.format("Night %d", view.night)
	labels.Clock.Text = HUD.clockText(view.clock)
	labels.Quota.Text = string.format("Quota %d / %d", view.banked, view.quota)
	local fill = oilFill
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(view.oil, 0, 1), 1)
	end
	local motor = labels.Motor
	local on = view.motorOn == true
	if motor and motor.Visible ~= on then
		motor.Visible = on
		local paper = paperFrame
		if paper then
			paper.Size = UDim2.fromOffset(150, rowsHeight(if on then 5 else 4))
		end
	end
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
	paper.Size = UDim2.fromOffset(150, rowsHeight(4))
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

	local oilRow = label(paper, "Oil", 4, f)
	oilRow.Text = "Oil"
	local bar = Instance.new("Frame")
	bar.Name = "OilBar"
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.fromScale(1, 0.5)
	bar.Size = UDim2.new(0.62, 0, 0, 8)
	bar.BackgroundColor3 = Look.UI.ink
	bar.BackgroundTransparency = 0.75
	bar.BorderSizePixel = 0
	bar.Parent = oilRow
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Look.UI.ink
	fill.BorderSizePixel = 0
	fill.Parent = bar
	oilFill = fill

	local motor = label(paper, "Motor", 5, f)
	motor.Text = "Motor: on"
	motor.Visible = false

	render(ViewState.get())
	ViewState.onChange(render)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return HUD
