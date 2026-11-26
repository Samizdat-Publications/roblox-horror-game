--!strict
-- Paper and ink: small helpers every UI module builds from (DESIGN.md: handwriting for the
-- rules, typewriter for the Field Guide). Fonts fall back to SourceSans if missing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local Paper = {}

function Paper.font(name: string): Font
	local ok, f = pcall(function()
		return Font.fromEnum((Enum.Font :: any)[name])
	end)
	if ok and f then
		return f
	end
	return Font.fromEnum(Enum.Font.SourceSans)
end

function Paper.typewriter(): Font
	return Paper.font(Look.UI.typewriterFont)
end

function Paper.hand(): Font
	return Paper.font(Look.UI.handFont)
end

function Paper.gui(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- A sheet of paper. `pad` is the inner margin in pixels.
function Paper.sheet(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2, pad: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = Look.UI.paper
	f.BackgroundTransparency = Look.UI.hudPaperTransparency
	f.BorderSizePixel = 0
	f.Parent = parent
	local p = pad or 8
	local ui = Instance.new("UIPadding")
	ui.PaddingLeft = UDim.new(0, p)
	ui.PaddingRight = UDim.new(0, p)
	ui.PaddingTop = UDim.new(0, p)
	ui.PaddingBottom = UDim.new(0, p)
	ui.Parent = f
	return f
end

function Paper.text(parent: Instance, name: string, text: string, size: number, font: Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.FontFace = font or Paper.typewriter()
	t.TextSize = size
	t.TextColor3 = Look.UI.ink
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Size = UDim2.new(1, 0, 0, size + 6)
	t.Text = text
	t.Parent = parent
	return t
end

function Paper.button(parent: Instance, name: string, text: string, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.BackgroundColor3 = Look.UI.paper
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.FontFace = Paper.typewriter()
	b.TextSize = 20
	b.TextColor3 = Look.UI.ink
	b.Text = text
	b.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Look.UI.ink
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	return b
end

-- "10:42 PM" from game hours (22.0 is 10 PM, 29.0 is 5 AM).
function Paper.clockText(hours: number): string
	local h = math.floor(hours) % 24
	local m = math.floor((hours - math.floor(hours)) * 60)
	local suffix = if h >= 12 then "PM" else "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

return Paper
