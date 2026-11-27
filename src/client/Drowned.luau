--!strict
-- The drowned (DESIGN.md, Death and the drowned). Every dead crewmate floats near the boat as
-- a dim light that everyone can see (built here, on every client, from the NightView); your
-- own light carries a small "You". When the local player is one of them, after the death
-- card (the boat still rocking for a few seconds as the view opens):
--   * the camera floats over the boat in a high three-quarter view that slowly circles it
--     (turn it with the mouse, the move keys, the stick or a drag; zoom with W and S or the
--     stick), the view is tinted cold blue-green and a dim cold light hangs over the boat so
--     the hull and the crew read even with the lantern out, a muffled ghost-loop plays
--     (the view was pure black in the first Studio run, 11/26/2026)
--   * they see outlines the living cannot (Common.setDrowned: the shape under the hull, the
--     Watcher through the trees, the Neighbor's boat through the fog)
--   * the cast button (click, Space, R2, or the touch button, retitled Bell) rings the ghost
--     bell, every Config.Ghost.bellCooldown seconds; a small paper tag shows when it is ready
-- GhostBell events ring a faint bell at that ghost's light, which flares for players with the
-- sound off. Everyone is back at the next night.
-- S4: a player who joined while a night was running watches from the same view until the
-- next night (LobbyState.waiting), with a tag saying so and no bell (they are not crew yet).

-- Polish 3 (Hydrogen review, row 2: the drowned as spotters):
--   * a GhostBell sends a ripple ring across the water from that ghost's light, and the
--     living get a pale marker at the edge of the screen toward it for a few seconds;
--   * the drowned see a faint outline on the real dock beacon, and only on it (false
--     beacons are never outlined), so they can tell the crew which light is home.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local client = script.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local Events = require(client:WaitForChild("Events"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Input = require(client:WaitForChild("Input"))
local Common = require(client:WaitForChild("fx"):WaitForChild("Common"))
local ui = client:WaitForChild("ui")
local Paper = require(ui:WaitForChild("Paper"))
local DeathCard = require(ui:WaitForChild("DeathCard"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))

local Drowned = {}

Drowned.RIPPLE = { from = 3, to = 70, life = 3.2, segments = 36, color = Color3.fromRGB(170, 215, 235) }
Drowned.CUE_SECONDS = 3
Drowned.BEACON_OUTLINE = 0.5 -- outline transparency on the real beacon (faint)

Drowned.WISP_COLOR = Color3.fromRGB(170, 210, 230)
Drowned.ORBIT = { radius = 18, height = 12, minRadius = 9, maxRadius = 34, drift = 0.07 }
Drowned.TINT = Color3.fromRGB(150, 215, 210) -- cold blue-green over the drowned view
Drowned.LIGHT = { color = Color3.fromRGB(150, 200, 215), range = 42, brightness = 1.1, height = 22 }

type Wisp = { part: BasePart, light: PointLight, index: number, flare: number }

local wisps: { [number]: Wisp } = {}
local active = false -- the local player is drowned and spectating
local waiting = false -- joined mid-night: spectating until the next night
local yaw = 0
local radius = Drowned.ORBIT.radius
local lastBell = -math.huge
local ghostLoop: Sound? = nil
local tag: TextLabel? = nil
local clock = 0
local dragging = false
local sightFx: { Instance } = {} -- the tint and the cold light, while spectating
local sightLight: BasePart? = nil
local beaconMark: Highlight? = nil
local cueGui: ScreenGui? = nil
local cues: { { frame: Frame, at: Vector3, t0: number } } = {}

function Drowned.active(): boolean
	return active
end

local function myId(): number
	return Players.LocalPlayer.UserId
end

local function wispFor(id: number, index: number): Wisp
	local w = wisps[id]
	if w and w.part.Parent then
		return w
	end
	local p = Common.part(
		"Drowned_" .. tostring(id),
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(),
		Drowned.WISP_COLOR,
		Enum.Material.Neon,
		{ shape = Enum.PartType.Ball, transparency = 0.55 }
	)
	local light = Instance.new("PointLight")
	light.Color = Drowned.WISP_COLOR
	light.Range = 9
	light.Brightness = 0.5
	light.Shadows = false
	light.Parent = p
	-- Your own light says so (Neon took it for a mystery orb, 11/26/2026).
	if id == myId() then
		local bb = Instance.new("BillboardGui")
		bb.Name = "YouTag"
		bb.Size = UDim2.fromOffset(60, 24)
		bb.StudsOffset = Vector3.new(0, 1.3, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 120
		bb.Parent = p
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.FontFace = Paper.hand()
		t.TextSize = 20
		t.TextColor3 = Drowned.WISP_COLOR
		t.TextStrokeTransparency = 0.3
		t.Text = "You"
		t.Parent = bb
	end
	local nw: Wisp = { part = p, light = light, index = index, flare = 0 }
	wisps[id] = nw
	return nw
end

local function stepWisps(dt: number)
	local view = ViewState.get()
	local hull = BoatClient.hull()
	local dead: { [number]: number } = {}
	local i = 0
	for _, p in view.players or {} do
		if type(p) == "table" and p.alive == false and type(p.id) == "number" then
			i += 1
			dead[p.id] = i
		end
	end
	for id, w in wisps do
		if dead[id] == nil then
			w.part:Destroy()
			wisps[id] = nil
		end
	end
	if hull == nil then
		return
	end
	for id, index in dead do
		local w = wispFor(id, index)
		w.index = index
		local a = index * 2.1 + clock * 0.25
		local off = Vector3.new(math.cos(a) * 5, 3.2 + math.sin(clock * 1.3 + index) * 0.4, math.sin(a) * 6)
		w.part.CFrame = CFrame.new(hull.Position + off)
		w.flare = math.max(0, w.flare - dt * 0.8)
		w.light.Brightness = 0.5 + w.flare * 3
		w.light.Range = 9 + w.flare * 14
		w.part.Transparency = 0.55 - w.flare * 0.4
	end
end

local function updateTag()
	local t = tag
	if t == nil then
		return
	end
	if not active then
		t.Visible = false
		return
	end
	t.Visible = true
	if waiting then
		t.Text = "You join the crew at the next night."
		return
	end
	local left = Config.Ghost.bellCooldown - (os.clock() - lastBell)
	if left <= 0 then
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		t.Text = if touch then "Tap Bell  Ring the bell" else "Click or Space  Ring the bell"
	else
		t.Text = string.format("The bell rings again in %d", math.ceil(left))
	end
end

-- Rings the ghost bell if it has cooled down (the server checks again).
function Drowned.ring(): boolean
	if not active or waiting then
		return false
	end
	if os.clock() - lastBell < Config.Ghost.bellCooldown then
		return false
	end
	lastBell = os.clock()
	Input.sendIntent("GhostBell")
	return true
end

local function stepCamera(dt: number)
	if not active then
		return
	end
	local cam = Workspace.CurrentCamera
	local hull = BoatClient.hull()
	if cam == nil or hull == nil then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local throttle, steer = Input.readDevices()
	yaw -= steer * dt * 1.2 + Drowned.ORBIT.drift * dt
	radius = math.clamp(radius - throttle * dt * 12, Drowned.ORBIT.minRadius, Drowned.ORBIT.maxRadius)
	if dragging then
		-- Right mouse held: hold the cursor still and turn with its movement.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
	local mb = UserInputService.MouseBehavior
	if mb == Enum.MouseBehavior.LockCenter or mb == Enum.MouseBehavior.LockCurrentPosition then
		yaw -= UserInputService:GetMouseDelta().X * 0.004
	end
	local center = hull.Position + Vector3.new(0, 1.5, 0)
	local from = center
		+ Vector3.new(
			math.sin(yaw) * radius,
			Drowned.ORBIT.height * radius / Drowned.ORBIT.radius,
			math.cos(yaw) * radius
		)
	cam.CFrame = CFrame.lookAt(from, center)
	local l = sightLight
	if l then
		l.CFrame = CFrame.new(hull.Position + Vector3.new(0, Drowned.LIGHT.height, 0))
	end
end

-- The drowned's own look: a cold tint on this camera and a dim light over the boat.
local function setSight(on: boolean)
	for _, inst in sightFx do
		inst:Destroy()
	end
	sightFx = {}
	sightLight = nil
	if not on then
		return
	end
	local cam = Workspace.CurrentCamera
	if cam then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "DeadCalmDrownedTint"
		cc.TintColor = Drowned.TINT
		cc.Brightness = 0.06
		cc.Contrast = 0.12
		cc.Saturation = -0.35
		cc.Parent = cam
		table.insert(sightFx, cc)
	end
	local hull = BoatClient.hull()
	local at = if hull then hull.Position else Vector3.zero
	local p = Common.part(
		"DrownedLight",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(at + Vector3.new(0, Drowned.LIGHT.height, 0)),
		Color3.new(),
		nil,
		{ transparency = 1 }
	)
	local light = Instance.new("PointLight")
	light.Color = Drowned.LIGHT.color
	light.Range = Drowned.LIGHT.range
	light.Brightness = Drowned.LIGHT.brightness
	light.Shadows = false
	light.Parent = p
	table.insert(sightFx, p)
	sightLight = p
end

-- The real dock beacon, faintly outlined for the drowned only.
local function setBeaconMark(on: boolean)
	local hl = beaconMark
	if not on then
		beaconMark = nil
		if hl then
			hl:Destroy()
		end
		return
	end
	if hl and hl.Parent then
		return
	end
	local lamp = BoatClient.find("Dock", "BeaconLamp")
	if lamp == nil then
		return
	end
	local n = Instance.new("Highlight")
	n.Name = "DeadCalmRealBeacon"
	n.Adornee = lamp
	n.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	n.FillTransparency = 1
	n.OutlineColor = Common.OUTLINE
	n.OutlineTransparency = Drowned.BEACON_OUTLINE
	n.Parent = Common.folder()
	beaconMark = n
end

-- A ring of short flat segments spreading over the water from `center`, fading.
local function ripple(center: Vector3)
	local R = Drowned.RIPPLE
	local c = Vector3.new(center.X, Config.Lake.waterY + 0.1, center.Z)
	local segs: { BasePart } = {}
	for i = 1, R.segments do
		segs[i] = Common.part(
			"GhostRipple",
			Vector3.new(1, 0.08, 0.35),
			CFrame.new(c),
			R.color,
			Enum.Material.Neon,
			{ transparency = 0.3 }
		)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < R.life and segs[1].Parent do
			local t = (os.clock() - t0) / R.life
			local r = R.from + (R.to - R.from) * (1 - (1 - t) * (1 - t))
			local len = 2 * math.pi * r / R.segments * 1.05
			for i, sg in segs do
				local a = (i - 1) * 2 * math.pi / R.segments
				sg.Size = Vector3.new(len, 0.08, 0.35)
				sg.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
					* CFrame.Angles(0, -a + math.pi / 2, 0)
				sg.Transparency = 0.3 + t * 0.7
			end
			task.wait()
		end
		for _, sg in segs do
			sg:Destroy()
		end
	end)
end

-- A pale marker at the screen edge toward a ringing ghost (the living only).
local function edgeCue(at: Vector3)
	local g = cueGui
	if g == nil then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "BellCue"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(54, 54)
	f.BackgroundColor3 = Drowned.WISP_COLOR
	f.BackgroundTransparency = 0.55
	f.BorderSizePixel = 0
	f.Parent = g
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = Drowned.WISP_COLOR
	stroke.Thickness = 3
	stroke.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Paper.hand()
	t.TextSize = 16
	t.TextColor3 = Color3.fromRGB(20, 30, 36)
	t.Text = "bell"
	t.Parent = f
	table.insert(cues, { frame = f, at = at, t0 = os.clock() })
end

local function stepCues()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local vp = cam.ViewportSize
	local margin = 44
	local keep = {}
	for _, c in cues do
		local age = os.clock() - c.t0
		if age > Drowned.CUE_SECONDS or c.frame.Parent == nil then
			c.frame:Destroy()
			continue
		end
		local p, onScreen = cam:WorldToViewportPoint(c.at)
		local x, y = p.X, p.Y
		if not onScreen or p.Z < 0 then
			-- Behind or off screen: point from the middle toward it, pinned to the edge.
			local rel = cam.CFrame:PointToObjectSpace(c.at)
			local dx, dy = rel.X, -rel.Y
			if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then
				dy = 1
			end
			local sx = (vp.X / 2 - margin) / math.max(math.abs(dx), 1e-3)
			local sy = (vp.Y / 2 - margin) / math.max(math.abs(dy), 1e-3)
			local k = math.min(sx, sy)
			x, y = vp.X / 2 + dx * k, vp.Y / 2 + dy * k
		end
		c.frame.Position = UDim2.fromOffset(math.clamp(x, margin, vp.X - margin), math.clamp(y, margin, vp.Y - margin))
		local fade = math.clamp(age / Drowned.CUE_SECONDS, 0, 1)
		local pulse = 0.5 + 0.5 * math.sin(age * 8)
		c.frame.BackgroundTransparency = 0.45 + 0.4 * fade + 0.1 * pulse
		local st = c.frame:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = fade
		end
		table.insert(keep, c)
	end
	cues = keep
end

local function setActive(on: boolean)
	if active == on then
		return
	end
	active = on
	Common.setDrowned(on)
	setSight(on)
	setBeaconMark(on)
	local cam = Workspace.CurrentCamera
	if on then
		-- The fail's camera effects (thrown, under the surface) end here, and the boat is
		-- still rocking from it for a few seconds as the view opens.
		BoatFx.clearCamera()
		BoatFx.rock()
		local hull = BoatClient.hull()
		if hull then
			-- Behind the boat and to one side: a three-quarter view of the hull and the crew.
			local hl = hull.CFrame.LookVector
			yaw = math.atan2(-hl.X, -hl.Z) + 0.7
		end
		radius = Drowned.ORBIT.radius
		ghostLoop = AudioDirector.loop("ghost-loop", nil)
		pcall(function()
			ContextActionService:SetTitle("DeadCalmCast", "Bell")
		end)
		Input.setGhostHandler(Drowned.ring)
	else
		local g = ghostLoop
		ghostLoop = nil
		if g then
			g:Destroy()
		end
		pcall(function()
			ContextActionService:SetTitle("DeadCalmCast", "Cast")
		end)
		Input.setGhostHandler(nil)
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			local char = Players.LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
		end
		Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	updateTag()
end

-- Joined mid-night: watch from the drowned view until the next night (LobbyClient).
function Drowned.setWaiting(on: boolean)
	if waiting == on then
		return
	end
	waiting = on
	if on then
		setActive(true)
	else
		local pv = ViewState.me()
		if active and (pv == nil or pv.alive ~= false) then
			setActive(false)
		end
	end
	updateTag()
end

function Drowned.init()
	local gui = Paper.gui("DeadCalmDrowned", 6)
	local t = Paper.text(gui, "Bell", "", 18)
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 1, -70)
	t.Size = UDim2.fromOffset(420, 26)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextColor3 = Drowned.WISP_COLOR
	t.TextStrokeTransparency = 0.4
	t.Visible = false
	tag = t
	local cg = Instance.new("ScreenGui")
	cg.Name = "DeadCalmBellCue"
	cg.ResetOnSpawn = false
	cg.IgnoreGuiInset = true
	cg.DisplayOrder = 7
	cg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	cueGui = cg

	DeathCard.onDone(function()
		local pv = ViewState.me()
		if pv and pv.alive == false then
			setActive(true)
		end
	end)
	-- Back at the next night (the view says alive again).
	ViewState.onChange(function()
		local pv = ViewState.me()
		if active and not waiting and (pv == nil or pv.alive ~= false) then
			setActive(false)
		elseif not active and pv and pv.alive == false and not DeathCard.showing() then
			-- Joined dead, or the card was closed some other way.
			setActive(true)
		end
	end)
	LobbyClient.onChange(function()
		Drowned.setWaiting(LobbyClient.waiting())
	end)
	Events.on("GhostBell", function(e)
		local id = e.player
		local w = if type(id) == "number" then wisps[id] else nil
		AudioDirector.play("ghost-bell", if w then w.part else BoatClient.hull())
		if w then
			w.flare = 1
		end
		-- Every client sees the ripple; the living also get the edge marker toward it.
		local from = if w then w.part.Position else nil
		local hull = BoatClient.hull()
		if from == nil and hull then
			from = hull.Position
		end
		if from then
			ripple(from)
			if not active then
				edgeCue(from)
			end
		end
		if id == myId() then
			lastBell = os.clock()
		end
	end)
	UserInputService.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			if active then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
	end)
	-- A drag on a phone turns the view too.
	UserInputService.InputChanged:Connect(function(io, processed)
		if active and not processed and io.UserInputType == Enum.UserInputType.Touch then
			yaw -= io.Delta.X * 0.006
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		stepWisps(dt)
		stepCues()
	end)
	RunService:BindToRenderStep("DeadCalmDrowned", Enum.RenderPriority.Camera.Value + 1, stepCamera)
	-- The Neighbor's silhouette in the boat (a server model) is outlined for the drowned.
	local outlinedSilhouettes: { [Instance]: boolean } = {}
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateTag()
			local m = BoatClient.model()
			local sil = m and m:FindFirstChild("NeighborInTheBoat")
			if sil and not outlinedSilhouettes[sil] then
				outlinedSilhouettes[sil] = true
				Common.outline(sil)
				sil.Destroying:Once(function()
					outlinedSilhouettes[sil] = nil
				end)
			end
		end
	end)
end

return Drowned
