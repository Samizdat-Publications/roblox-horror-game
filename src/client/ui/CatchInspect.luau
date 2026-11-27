--!strict
-- The catch, held up to the lantern: when the local player lands a fish, a copy of the fish
-- on their line hangs in front of the camera in side profile (head right, back up, as in the
-- Field Guide drawing), swaying gently.
-- It is lit by the world (the boat's lantern), so with the lantern out it is hard to see.
-- Beside it, the Field Guide opens as a half-screen card on the species the fish claims to
-- be: a drawing (the book-true fish the server built) and the facts to check. Keep (E) or
-- throw back (X); if time runs out the fish slips back into the lake (Core: a timeout throws
-- it back). Polish 3: over the last THRASH_SECONDS of the timer the held fish thrashes harder
-- and harder and the timer bar turns red, as the countdown; a timeout says "Too slow. It
-- slipped back." for a moment.
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
CatchInspect.THRASH_SECONDS = 3
CatchInspect.SLIPPED_TEXT = "Too slow. It slipped back."
CatchInspect.SLIPPED_SECONDS = 2.5

local TAIL_TEXT = { Forked = "forked", Round = "round", Square = "square", Uneven = "uneven, top lobe long" }

local card: Frame? = nil
local buttons: Frame? = nil
local timerFill: Frame? = nil
local viewport: ViewportFrame? = nil
local labels: { [string]: TextLabel } = {}
local held: Model? = nil
-- Where the held copy's pivot sits relative to its measured fish frame (see fishFrame).
local heldRel: CFrame? = nil
local original: Model? = nil
local openAt = 0
local clock = 0
local active = false
local localFolder: Folder? = nil
local slipped: TextLabel? = nil
local slippedToken = 0

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
		elseif x:IsA("Beam") or x:IsA("Light") then
			-- The line to the mouth, and a glowing fish's light (it would light the boat in
			-- pale green from the rod while the copy is held up).
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
	heldRel = nil
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
		elseif x:IsA("Light") then
			x.Enabled = true
		end
	end
	m.Name = "Inspect"
	return m
end

-- The fish's own frame, measured from its parts rather than assumed from the model's pivot
-- or axes: X is the side, Y the back (dorsal) side, Z points to the tail (so the head is
-- -Z, as in the Field Guide drawing). The origin is the middle of the fish's extent.
-- Returns the frame and the extent (side, height, length) in that frame.
local function fishFrame(m: Model): (CFrame, Vector3)
	local body = m.PrimaryPart or m:FindFirstChild("Body")
	local center: Vector3
	local bodyCf: CFrame
	if body and body:IsA("BasePart") then
		center, bodyCf = body.Position, body.CFrame
	else
		local cf = m:GetBoundingBox()
		center, bodyCf = cf.Position, cf
	end
	local function avg(prefix: string): Vector3?
		local sum, n = Vector3.zero, 0
		for _, x in m:GetChildren() do
			if x:IsA("BasePart") and string.sub(x.Name, 1, #prefix) == prefix then
				sum += x.Position
				n += 1
			end
		end
		return if n > 0 then sum / n else nil
	end
	-- Head direction: body center to the Mouth (head end), else tail to center.
	local head: Vector3? = nil
	local mouth = body and body:FindFirstChild("Mouth")
	if mouth and mouth:IsA("Attachment") then
		local d = mouth.WorldPosition - center
		if d.Magnitude > 1e-3 then
			head = d.Unit
		end
	end
	if head == nil then
		local tail = avg("Tail")
		if tail and (center - tail).Magnitude > 1e-3 then
			head = (center - tail).Unit
		end
	end
	-- Last resort: FishModel builds the head along the Body's LookVector (-Z).
	local headDir = head or bodyCf.LookVector
	-- Up: toward the back fins, else away from a belly fin, else the body's up.
	local up = bodyCf.UpVector
	local fins = avg("BackFin")
	local belly = avg("BellyFin")
	if fins then
		up = fins - center
	elseif belly then
		up = center - belly
	end
	up -= headDir * up:Dot(headDir)
	if up.Magnitude < 1e-3 then
		up = bodyCf.UpVector - headDir * bodyCf.UpVector:Dot(headDir)
	end
	up = up.Unit
	local back = -headDir
	local side = up:Cross(back)
	local frame = CFrame.fromMatrix(center, side, up, back)
	-- Extent of every visible part in that frame.
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, x in m:GetDescendants() do
		if x:IsA("BasePart") and x.Transparency < 1 then
			local rel = frame:ToObjectSpace(x.CFrame)
			local s = x.Size / 2
			for _, c in
				{
					Vector3.new(s.X, s.Y, s.Z),
					Vector3.new(-s.X, s.Y, s.Z),
					Vector3.new(s.X, -s.Y, s.Z),
					Vector3.new(s.X, s.Y, -s.Z),
					Vector3.new(-s.X, -s.Y, s.Z),
					Vector3.new(-s.X, s.Y, -s.Z),
					Vector3.new(s.X, -s.Y, -s.Z),
					Vector3.new(-s.X, -s.Y, -s.Z),
				}
			do
				local p = rel * c
				lo = lo:Min(p)
				hi = hi:Max(p)
			end
		end
	end
	if lo.X > hi.X then
		return frame, Vector3.one
	end
	return frame * CFrame.new((lo + hi) / 2), hi - lo
end

-- Inspect framing: distance from the camera, where on screen (0..1) the fish's middle sits,
-- the share of the screen height the fish fills, and the most of the screen width it may
-- span (the Field Guide card covers the right side).
local HOLD_DIST = 3
local HOLD_SCREEN = Vector2.new(0.29, 0.44)
local HOLD_HEIGHT = 1 / 3
local HOLD_MAX_WIDTH = 0.46

local function viewSize(cam: Camera, dist: number): Vector2
	local h = 2 * dist * math.tan(math.rad(cam.FieldOfView) / 2)
	local vp = cam.ViewportSize
	local aspect = if vp.Y > 0 then vp.X / vp.Y else 16 / 9
	return Vector2.new(h * aspect, h)
end

-- Scales the held copy to fill a third of the screen height (without running under the
-- card), then records where its pivot sits relative to the measured fish frame.
local function frameHeld(h: Model)
	local cam = Workspace.CurrentCamera
	local _, size = fishFrame(h)
	if cam then
		local view = viewSize(cam, HOLD_DIST)
		local s =
			math.min(view.Y * HOLD_HEIGHT / math.max(size.Y, 0.05), view.X * HOLD_MAX_WIDTH / math.max(size.Z, 0.05))
		pcall(function()
			h:ScaleTo(h:GetScale() * s)
		end)
	end
	local frame = fishFrame(h)
	heldRel = frame:ToObjectSpace(h:GetPivot())
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
				frameHeld(h)
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
	-- No key hints on a phone (found in the Device Simulator, 11/26/2026).
	local touch = Input.touch()
	local keep = Paper.button(b, "Keep", if touch then "Keep" else "Keep  (E)", UDim2.fromOffset(180, 56))
	keep.Position = UDim2.fromOffset(0, 0)
	local back =
		Paper.button(b, "ThrowBack", if touch then "Throw back" else "Throw back  (X)", UDim2.fromOffset(180, 56))
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

	local sl = Paper.text(g, "Slipped", CatchInspect.SLIPPED_TEXT, Paper.fit(26, 18, 32), Paper.hand())
	sl.AnchorPoint = Vector2.new(0.5, 0.5)
	sl.Position = UDim2.fromScale(0.5, 0.62)
	sl.Size = UDim2.new(0.8, 0, 0, Paper.fit(26, 18, 32) + 10)
	sl.TextXAlignment = Enum.TextXAlignment.Center
	sl.TextColor3 = Look.UI.paper
	sl.TextStrokeColor3 = Look.UI.ink
	sl.TextStrokeTransparency = 0.2
	sl.Visible = false
	slipped = sl
end

-- 0..1: how hard the held fish thrashes `left` seconds before the timer runs out.
function CatchInspect.thrash(left: number): number
	return math.clamp(1 - left / CatchInspect.THRASH_SECONDS, 0, 1)
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
	Events.on("Released", function(e)
		done(e)
		local data = e.data
		local sl = slipped
		if e.player == me.UserId and type(data) == "table" and data.timeout == true and sl then
			slippedToken += 1
			local my = slippedToken
			sl.Visible = true
			task.delay(CatchInspect.SLIPPED_SECONDS, function()
				if slippedToken == my then
					sl.Visible = false
				end
			end)
		end
	end)
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
		local secondsLeft = Config.Fishing.decideSeconds - (clock - openAt)
		local thrash = CatchInspect.thrash(secondsLeft)
		local tf = timerFill
		if tf then
			local left = 1 - (clock - openAt) / Config.Fishing.decideSeconds
			tf.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
			tf.BackgroundColor3 = Look.UI.paper:Lerp(Color3.fromRGB(205, 40, 28), thrash)
		end
		local h = held
		local cam = Workspace.CurrentCamera
		local rel = heldRel
		if h and cam and rel then
			local cf = cam.CFrame
			local view = viewSize(cam, HOLD_DIST)
			local ox = (HOLD_SCREEN.X - 0.5) * view.X
			local oy = (0.5 - HOLD_SCREEN.Y) * view.Y + 0.03 * math.sin(clock * 0.8)
			local pos = (cf * CFrame.new(ox, oy, -HOLD_DIST)).Position
			-- Clean side profile: the near side faces the camera, back up, head to the right
			-- of the screen and tail to the left (as in the Field Guide drawing).
			local toCam = (cf.Position - pos).Unit
			local up = cf.UpVector - toCam * cf.UpVector:Dot(toCam)
			up = if up.Magnitude > 1e-3 then up.Unit else cf.UpVector
			local back = toCam:Cross(up)
			local target = CFrame.fromMatrix(pos, toCam, up, back)
			-- A slow, gentle sway that never loses the profile.
			local sway = CFrame.Angles(0, math.sin(clock * 0.5) * 0.12, math.sin(clock * 0.37) * 0.05)
			-- The countdown: the fish fights harder as time runs out (yaw flips the tail,
			-- roll twists it, a little jump), faster and wider toward the end.
			if thrash > 0 then
				local f = 9 + 9 * thrash
				local yaw = math.sin(clock * f) * 0.45 * thrash
				local roll = math.sin(clock * f * 1.3 + 1) * 0.22 * thrash
				local hop = math.abs(math.sin(clock * f * 0.5)) * 0.12 * thrash
				sway = sway * CFrame.new(0, hop, 0) * CFrame.Angles(0, yaw, roll)
			end
			h:PivotTo(target * sway * rel)
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
