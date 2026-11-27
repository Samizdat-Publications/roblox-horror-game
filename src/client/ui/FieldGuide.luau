--!strict
-- The Field Guide as its own page (G, gamepad D-pad right, the Guide button). It covers
-- most of the view and stops your hands like the rulebook (BookState). The eight species
-- down the left; the chosen one on the right: its name, a sepia drawing of the book-true
-- fish the server built (ReplicatedStorage.DeadCalmFieldGuide), the facts to check and the
-- owner's note. Left and right arrows or the gamepad shoulders turn the pages.
-- (The half-screen card beside a held fish at catch time is CatchInspect's.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local Paper = require(script.Parent:WaitForChild("Paper"))
local BookState = require(script.Parent:WaitForChild("BookState"))
local CatchInspect = require(script.Parent:WaitForChild("CatchInspect"))

local FieldGuide = {}

FieldGuide.GUIDE_FOLDER = "DeadCalmFieldGuide"

-- Book order: cheapest first, then by name.
function FieldGuide.order(): { string }
	local out = {}
	for key in Config.Fish do
		table.insert(out, key)
	end
	table.sort(out, function(a, b)
		local pa, pb = Config.Fish[a].points, Config.Fish[b].points
		if pa ~= pb then
			return pa < pb
		end
		return Config.Fish[a].name < Config.Fish[b].name
	end)
	return out
end

local species = FieldGuide.order()
local index = 1
local gui: ScreenGui? = nil
local nameLabel: TextLabel? = nil
local factsLabel: TextLabel? = nil
local noteLabel: TextLabel? = nil
local viewport: ViewportFrame? = nil
local tabs: { TextButton } = {}

local function draw(key: string)
	local vp = viewport
	if vp == nil then
		return
	end
	vp:ClearAllChildren()
	local folder = ReplicatedStorage:FindFirstChild(FieldGuide.GUIDE_FOLDER)
	local src = folder and folder:FindFirstChild(key)
	if src == nil or not src:IsA("Model") then
		return
	end
	local m = src:Clone()
	m:PivotTo(CFrame.new())
	m.Parent = vp
	local cam = Instance.new("Camera")
	local len = (m:GetAttribute("Length") :: number?) or 2
	cam.CFrame = CFrame.lookAt(Vector3.new(len * 1.25, len * 0.3, 0), Vector3.zero)
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
end

local function show(i: number)
	index = ((i - 1) % #species) + 1
	local key = species[index]
	local def = Config.Fish[key]
	local n, f, no = nameLabel, factsLabel, noteLabel
	if n then
		n.Text = if def then def.name else key
	end
	if f then
		f.Text = table.concat(CatchInspect.facts(key), "\n")
	end
	if no then
		no.Text = if def then def.note else ""
	end
	for j, b in tabs do
		b.BackgroundTransparency = if j == index then 0.05 else 0.6
	end
	draw(key)
end

function FieldGuide.debugState(): { [string]: any }
	return { open = gui ~= nil and (gui :: ScreenGui).Enabled, species = species[index] }
end

function FieldGuide.init()
	local g, _sheet, body, close = Paper.bookPage("DeadCalmFieldGuidePage", 20, "Field Guide")
	gui = g
	local textSize = Paper.fit(18, 12, 20)

	-- Left: the species, one tab each.
	local left = Instance.new("ScrollingFrame")
	left.Name = "Species"
	left.Size = UDim2.fromScale(0.3, 1)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 4
	left.ScrollBarImageColor3 = Look.UI.ink
	left.CanvasSize = UDim2.new()
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.Parent = body
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 4)
	ll.Parent = left
	for i, key in species do
		local b = Paper.button(left, key, Config.Fish[key].name, UDim2.new(1, -8, 0, textSize + 14))
		b.LayoutOrder = i
		b.TextSize = textSize
		b.TextWrapped = true
		b.Activated:Connect(function()
			show(i)
		end)
		table.insert(tabs, b)
	end

	-- Right: the page.
	local right = Instance.new("Frame")
	right.Name = "Page"
	right.Position = UDim2.fromScale(0.32, 0)
	right.Size = UDim2.fromScale(0.68, 1)
	right.BackgroundTransparency = 1
	right.Parent = body
	local name = Paper.text(right, "Name", "", Paper.fit(26, 16, 28))
	name.Size = UDim2.fromScale(1, 0.12)
	nameLabel = name
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Drawing"
	vp.Position = UDim2.fromScale(0, 0.12)
	vp.Size = UDim2.fromScale(0.55, 0.42)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 190, 170)
	vp.LightColor = Color3.fromRGB(255, 245, 225)
	vp.LightDirection = Vector3.new(-1, -1, -0.5)
	vp.ImageColor3 = Color3.fromRGB(150, 125, 95)
	vp.Parent = right
	viewport = vp
	local facts = Paper.text(right, "Facts", "", textSize)
	facts.Position = UDim2.fromScale(0.57, 0.12)
	facts.Size = UDim2.fromScale(0.43, 0.6)
	facts.LineHeight = 1.05
	factsLabel = facts
	local note = Paper.text(right, "Note", "", textSize)
	note.Position = UDim2.fromScale(0, 0.56)
	note.Size = UDim2.fromScale(0.56, 0.28)
	noteLabel = note
	local foot =
		Paper.text(right, "Foot", "Nothing in the book glows. Nothing in the book blinks.", textSize, Paper.hand())
	foot.Position = UDim2.fromScale(0, 0.86)
	foot.Size = UDim2.fromScale(1, 0.14)
	foot.TextColor3 = Look.Palette.amendInk

	close.Activated:Connect(function()
		BookState.close()
	end)
	local dim = g:FindFirstChild("Dim") :: TextButton
	dim.Activated:Connect(function()
		BookState.close()
	end)
	UserInputService.InputBegan:Connect(function(io)
		if BookState.current() ~= "guide" then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.Right or k == Enum.KeyCode.ButtonR1 or k == Enum.KeyCode.D then
			show(index + 1)
		elseif k == Enum.KeyCode.Left or k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.A then
			show(index - 1)
		end
	end)
	BookState.onChange(function(page)
		local open = page == "guide"
		if open then
			show(index)
		end
		g.Enabled = open
	end)
end

return FieldGuide
