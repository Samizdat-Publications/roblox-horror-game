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

-- A text size that reads on the smallest phone (338 px tall) and does not shout on a
-- monitor: `base` at 600 px of screen height, scaled with the height, clamped.
function Paper.fit(base: number, lo: number?, hi: number?): number
	local cam = workspace.CurrentCamera
	local h = if cam then cam.ViewportSize.Y else 600
	return math.floor(math.clamp(base * h / 600, lo or 12, hi or base * 1.3))
end

-- An open book page that covers most of the view (the rulebook, the Field Guide, the Lake
-- Rules): a full-screen dim behind a large sheet, a heading, and a Close button. Returns
-- the gui, the sheet, the body frame (fill it) and the close button.
function Paper.bookPage(name: string, order: number, heading: string): (ScreenGui, Frame, Frame, TextButton)
	local gui = Paper.gui(name, order)
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Selectable = false
	dim.Parent = gui
	local sheet =
		Paper.sheet(gui, "Sheet", UDim2.fromScale(0.92, 0.9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 12)
	sheet.BackgroundTransparency = 0.02
	-- Polish 3: no rotation. ClipsDescendants is ignored under a rotated ancestor (creator
	-- docs, GuiObject.ClipsDescendants), so a crooked page let the rule list run past the
	-- paper's bottom edge instead of scrolling inside it.
	sheet.Rotation = 0
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(820, 680)
	limit.Parent = sheet
	local head = Paper.text(sheet, "Heading", heading, Paper.fit(30, 18, 34), Paper.hand())
	head.Size = UDim2.new(1, -110, 0, Paper.fit(30, 18, 34) + 8)
	local close = Paper.button(sheet, "Close", "Close", UDim2.fromOffset(96, 40))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.TextSize = Paper.fit(18, 14, 20)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	local top = Paper.fit(30, 18, 34) + 14
	body.Position = UDim2.fromOffset(0, top)
	body.Size = UDim2.new(1, 0, 1, -top)
	body.Parent = sheet
	return gui, sheet, body, close
end

-- A strip of tape across a top corner of `parent` (Polish 3: translucent, only slightly
-- crooked, straddling the top edge, with a faint sheen). anchor.X picks the corner (below
-- 0.5 is the left); anchor.Y is ignored. Returns the strip.
function Paper.tape(parent: Instance, anchor: Vector2, fresh: boolean): Frame
	local left = anchor.X < 0.5
	local t = Instance.new("Frame")
	t.Name = "Tape"
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.new(if left then 0 else 1, if left then 22 else -22, 0, 1)
	t.Size = UDim2.fromOffset(58, 17)
	t.Rotation = if left then -7 else 6
	t.BackgroundColor3 = if fresh then Color3.fromRGB(252, 246, 214) else Color3.fromRGB(236, 226, 190)
	t.BackgroundTransparency = if fresh then 0.4 else 0.55
	t.BorderSizePixel = 0
	t.ZIndex = 3
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	sheen.Parent = t
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(160, 145, 110)
	edge.Transparency = 0.75
	edge.Thickness = 1
	edge.Parent = t
	t.Parent = parent
	return t
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
