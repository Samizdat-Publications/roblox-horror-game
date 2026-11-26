--!strict
-- The catch, held up to the lantern: when the local player lands a fish, a copy of the fish
-- on their line hangs in front of the camera, turning slowly so both sides and the top show.
-- It is lit by the world (the boat's lantern), so with the lantern out it is hard to see.
-- Beside it, the Field Guide opens as a half-screen card on the species the fish claims to
-- be: a drawing (the book-true fish the server built) and the facts to check. Keep (E) or
-- throw back (X); if time runs out the fish is kept.
--
-- The client never knows whether a fish is wrong. It only sees the shape.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local Events = require(client:WaitForChild("Events"))
local Input = require(client:WaitForChild("Input"))
local Paper = require(script.Parent:WaitForChild("Paper"))

local CatchInspect = {}

CatchInspect.FISHING_FOLDER = "DeadCalmFishing"
CatchInspect.GUIDE_FOLDER = "DeadCalmFieldGuide"

local TAIL_TEXT = { Forked = "forked", Round = "round", Square = "square", Uneven = "uneven, top lobe long" }

local card: Frame? = nil
local buttons: Frame? = nil
local timerFill: Frame? = nil
local viewport: ViewportFrame? = nil
local labels: { [string]: TextLabel } = {}
local held: Model? = nil
local original: Model? = nil
local openAt = 0
local clock = 0
local active = false
local localFolder: Folder? = nil

local function count(n: number, none: string): string
	if n <= 0 then
		return none
	end
	return tostring(n)
end

-- The Field Guide facts for a species, one line each.
function CatchInspect.facts(species: string): { string }
	local def = Config.Fish[species]
	if def == nil then
		return { "Not in the book." }
	end
	local t = def.traits
	local lines = {
		"Eyes: " .. tostring(t.eyes),
		"Back fins: " .. tostring(t.dorsal),
		"Bars: " .. count(t.stripes, "none"),
		"Whiskers: " .. count(t.barbels, "none"),
		"Tail: " .. (TAIL_TEXT[t.tail] or string.lower(t.tail)),
		"Eyes shine in the lantern: " .. (if t.eyeshine then "yes" else "no"),
		string.format("Pays %d", def.points),
	}
	return lines
end

local function setOriginalHidden(m: Model?, hidden: boolean)
	if m == nil then
		return
	end
	for _, x in m:GetDescendants() do
		if x:IsA("BasePart") then
			x.LocalTransparencyModifier = if hidden then 1 else 0
		elseif x:IsA("Beam") then
			x.Enabled = not hidden
		end
	end
end

local function close()
	active = false
	local h = held
	if h then
		h:Destroy()
	end
	held = nil
	setOriginalHidden(original, false)
	original = nil
	local c, b = card, buttons
	if c then
		c.Visible = false
	end
	if b then
		b.Visible = false
	end
	local vp = viewport
	if vp then
		vp:ClearAllChildren()
	end
end

local function fillGuide(species: string)
	local def = Config.Fish[species]
	labels.Name.Text = if def then def.name else species
	labels.Facts.Text = table.concat(CatchInspect.facts(species), "\n")
	labels.Note.Text = if def then def.note else ""
	local vp = viewport
	if vp == nil then
		return
	end
	vp:ClearAllChildren()
	local folder = ReplicatedStorage:FindFirstChild(CatchInspect.GUIDE_FOLDER)
	local src = folder and folder:FindFirstChild(species)
	if src == nil or not src:IsA("Model") then
		return
	end
	local m = src:Clone()
	m:PivotTo(CFrame.new())
	m.Parent = vp
	local cam = Instance.new("Camera")
	local len = (m:GetAttribute("Length") :: number?) or 2
	-- From the fish's right side (+X), a touch above, so the top fins and any top eye show.
	local eye = Vector3.new(len * 1.25, len * 0.3, 0)
	cam.CFrame = CFrame.lookAt(eye, Vector3.zero)
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
end

local function cloneFish(src: Model): Model
	local m = src:Clone()
	for _, x in m:GetDescendants() do
		if x:IsA("WeldConstraint") or x:IsA("Beam") then
			x:Destroy()
		elseif x:IsA("BasePart") then
			x.Anchored = true
			x.CanCollide = false
			x.LocalTransparencyModifier = 0
		end
	end
	m.Name = "Inspect"
	return m
end

local function open(species: string, serial: number?)
	close()
	active = true
	openAt = clock
	fillGuide(species)
	local c, b = card, buttons
	if c then
		c.Visible = true
	end
	if b then
		b.Visible = true
	end
	-- Find the fish on our line (it replicates with the same tick as the event).
	local me = Players.LocalPlayer
	task.spawn(function()
		local t0 = os.clock()
		while active and os.clock() - t0 < 3 do
			local folder = Workspace:FindFirstChild(CatchInspect.FISHING_FOLDER)
			local m = folder and folder:FindFirstChild("DeadCalmFish_" .. tostring(me.UserId))
			if m and m:IsA("Model") and (serial == nil or m:GetAttribute("Serial") == serial) then
				original = m
				setOriginalHidden(m, true)
				local h = cloneFish(m)
				h.Parent = localFolder
				held = h
				return
			end
			task.wait(0.1)
		end
	end)
end

local function decide(keep: boolean)
	if not active then
		return
	end
	Input.sendIntent("CatchDecision", nil, keep)
end
CatchInspect.decide = decide

function CatchInspect.isOpen(): boolean
	return active
end

local function build()
	local g = Paper.gui("DeadCalmCatch", 8)

	-- The Field Guide card, right half.
	local c =
		Paper.sheet(g, "FieldGuide", UDim2.fromScale(0.42, 0.8), UDim2.new(1, -20, 0.5, 0), Vector2.new(1, 0.5), 14)
	c.BackgroundTransparency = 0.04
	c.Rotation = 1.2
	c.Visible = false
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(470, 600)
	limit.Parent = c
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = c
	card = c

	local head = Paper.text(c, "Head", "FIELD GUIDE", 14)
	head.LayoutOrder = 1
	head.TextTransparency = 0.35
	local name = Paper.text(c, "Name", "", 28)
	name.LayoutOrder = 2
	labels.Name = name

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Drawing"
	vp.LayoutOrder = 3
	vp.Size = UDim2.fromScale(1, 0.3)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 190, 170)
	vp.LightColor = Color3.fromRGB(255, 245, 225)
	vp.LightDirection = Vector3.new(-1, -1, -0.5)
	-- A sepia tint so the drawing reads as ink on paper.
	vp.ImageColor3 = Color3.fromRGB(150, 125, 95)
	vp.Parent = c
	viewport = vp

	local facts = Paper.text(c, "Facts", "", 18)
	facts.LayoutOrder = 4
	facts.Size = UDim2.new(1, 0, 0, 7 * 22)
	facts.LineHeight = 1.05
	labels.Facts = facts
	local note = Paper.text(c, "Note", "", 16)
	note.LayoutOrder = 5
	note.Size = UDim2.new(1, 0, 0, 64)
	labels.Note = note
	local foot = Paper.text(c, "Foot", "Nothing in the book glows. Nothing in the book blinks.", 15, Paper.hand())
	foot.LayoutOrder = 6
	foot.Size = UDim2.new(1, 0, 0, 40)
	foot.TextColor3 = Look.Palette.amendInk

	-- Keep and throw back, under the held fish.
	local b = Instance.new("Frame")
	b.Name = "Choice"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.29, 0, 1, -40)
	b.Size = UDim2.fromOffset(380, 76)
	b.BackgroundTransparency = 1
	b.Visible = false
	b.Parent = g
	buttons = b
	local keep = Paper.button(b, "Keep", "Keep  (E)", UDim2.fromOffset(180, 56))
	keep.Position = UDim2.fromOffset(0, 0)
	local back = Paper.button(b, "ThrowBack", "Throw back  (X)", UDim2.fromOffset(180, 56))
	back.Position = UDim2.fromOffset(200, 0)
	keep.Activated:Connect(function()
		decide(true)
	end)
	back.Activated:Connect(function()
		decide(false)
	end)
	local bar = Instance.new("Frame")
	bar.Name = "Timer"
	bar.Position = UDim2.fromOffset(0, 66)
	bar.Size = UDim2.new(1, 0, 0, 5)
	bar.BackgroundColor3 = Look.UI.paper
	bar.BackgroundTransparency = 0.6
	bar.BorderSizePixel = 0
	bar.Parent = b
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Look.UI.paper
	fill.BorderSizePixel = 0
	fill.Parent = bar
	timerFill = fill
end

function CatchInspect.init()
	build()
	local folder = Instance.new("Folder")
	folder.Name = "DeadCalmInspect"
	folder.Parent = Workspace
	localFolder = folder

	local me = Players.LocalPlayer
	Events.on("Caught", function(e)
		if e.player ~= me.UserId then
			return
		end
		local data = e.data or {}
		local catch = data.catch
		if type(catch) ~= "table" then
			return
		end
		open(tostring(catch.species), tonumber(data.serial))
	end)
	local function done(e: Events.Event)
		if e.player == me.UserId then
			close()
		end
	end
	Events.on("Kept", done)
	Events.on("Released", done)
	Events.on("PlayerDied", done)
	Events.on("NightStarted", function()
		close()
	end)

	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		if not active then
			return
		end
		-- Safety: the view says the line is no longer deciding.
		local pv = ViewState.me()
		if pv and pv.fishing ~= "Deciding" and clock - openAt > 1.5 then
			close()
			return
		end
		local tf = timerFill
		if tf then
			local left = 1 - (clock - openAt) / Config.Fishing.decideSeconds
			tf.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
		end
		local h = held
		local cam = Workspace.CurrentCamera
		if h and cam then
			local len = (h:GetAttribute("Length") :: number?) or 2
			local dist = 2.4 + len * 0.55
			local cf = cam.CFrame
			local pos = (cf * CFrame.new(-dist * 0.42, -0.1, -dist)).Position
			-- Length across the screen, one side to the camera, the top tipped toward it.
			local base = CFrame.lookAt(pos, pos + cf.RightVector, cf.UpVector)
			local yaw = math.sin(clock * 0.6) * 0.55
			local tilt = -0.35 - 0.15 * math.sin(clock * 0.45)
			h:PivotTo(base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, tilt))
			-- Blinking eyelids, if this fish has them.
			if h:GetAttribute("Blinks") then
				local F = Look.Fish
				local period = (F.blinkEvery[1] + F.blinkEvery[2]) / 2
				local shut = (clock % period) < F.blinkFor
				for _, x in h:GetDescendants() do
					if x:IsA("BasePart") and x.Name == "Eyelid" then
						x.Transparency = if shut then 0 else 1
					end
				end
			end
		end
	end)
end

return CatchInspect
