--!strict
-- The drowned (DESIGN.md, Death and the drowned). Every dead crewmate floats near the boat as
-- a dim light that everyone can see (built here, on every client, from the NightView). When
-- the local player is one of them, after the death card:
--   * the camera floats over the boat (orbit with the mouse, the move keys, the stick or a
--     drag; zoom with W and S or the stick), a muffled ghost-loop plays
--   * they see outlines the living cannot (Common.setDrowned: the shape under the hull, the
--     Watcher through the trees, the Neighbor's boat through the fog)
--   * the cast button (click, Space, R2, or the touch button, retitled Bell) rings the ghost
--     bell, every Config.Ghost.bellCooldown seconds; a small paper tag shows when it is ready
-- GhostBell events ring a faint bell at that ghost's light, which flares for players with the
-- sound off. Everyone is back at the next night.

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
local Input = require(client:WaitForChild("Input"))
local Common = require(client:WaitForChild("fx"):WaitForChild("Common"))
local ui = client:WaitForChild("ui")
local Paper = require(ui:WaitForChild("Paper"))
local DeathCard = require(ui:WaitForChild("DeathCard"))

local Drowned = {}

Drowned.WISP_COLOR = Color3.fromRGB(170, 210, 230)
Drowned.ORBIT = { radius = 16, height = 9, minRadius = 8, maxRadius = 34 }

type Wisp = { part: BasePart, light: PointLight, index: number, flare: number }

local wisps: { [number]: Wisp } = {}
local active = false -- the local player is drowned and spectating
local yaw = 0
local radius = Drowned.ORBIT.radius
local lastBell = -math.huge
local ghostLoop: Sound? = nil
local tag: TextLabel? = nil
local clock = 0
local dragging = false

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
	if not active then
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
	yaw -= steer * dt * 1.2
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
end

local function setActive(on: boolean)
	if active == on then
		return
	end
	active = on
	Common.setDrowned(on)
	local cam = Workspace.CurrentCamera
	if on then
		local hull = BoatClient.hull()
		if hull and cam then
			local back = cam.CFrame.Position - hull.Position
			yaw = math.atan2(back.X, back.Z)
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

	DeathCard.onDone(function()
		local pv = ViewState.me()
		if pv and pv.alive == false then
			setActive(true)
		end
	end)
	-- Back at the next night (the view says alive again).
	ViewState.onChange(function()
		local pv = ViewState.me()
		if active and (pv == nil or pv.alive ~= false) then
			setActive(false)
		elseif not active and pv and pv.alive == false and not DeathCard.showing() then
			-- Joined dead, or the card was closed some other way.
			setActive(true)
		end
	end)
	Events.on("GhostBell", function(e)
		local id = e.player
		local w = if type(id) == "number" then wisps[id] else nil
		AudioDirector.play("ghost-bell", if w then w.part else BoatClient.hull())
		if w then
			w.flare = 1
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
	end)
	RunService:BindToRenderStep("DeadCalmDrowned", Enum.RenderPriority.Camera.Value + 1, stepCamera)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateTag()
		end
	end)
end

return Drowned
