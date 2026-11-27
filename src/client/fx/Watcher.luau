--!strict
-- Rule 5, the Watcher on the Shore, on screen.
--   EntityCue     a too-tall, too-narrow figure stands among the trees at data.pos, still,
--                 with two pin-point eyes, facing the boat
--   EntityMoved   it steps closer (watcher-step); two or more steps at once is a lunge
--                 (watcher-lunge, faster)
--   EntityPass    watcher-pass, and then it is simply not there: it goes the moment it is
--                 off screen (or after a few seconds)
--   EntityFail    it is at the waterline: lanterns-die and watcher-fail
-- While this player stares straight at it (inside Config.Rules.Watcher.stareCone of the
-- camera's look) a thin tone rises (watcher-tone-loop) and a vignette darkens the edges of
-- the screen, deeper the longer the stare (full at stareLimit). Looking away clears both.
-- The drowned see the figure outlined through the trees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local ViewState = require(client:WaitForChild("ViewState"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local Common = require(script.Parent:WaitForChild("Common"))

local Watcher = {}

Watcher.HEIGHT = 13 -- studs: too tall
Watcher.WIDTH = 1.25 -- and too narrow
Watcher.STEP_SECONDS = 0.8
Watcher.LUNGE_SECONDS = 0.3
Watcher.GONE_AFTER = 6
Watcher.STAYS_AFTER_FAIL = 12

local figure: Common.Figure? = nil
local from: CFrame? = nil
local to: CFrame? = nil
local moveT = 1
local moveLen = Watcher.STEP_SECONDS
local lastStep: number? = nil
local leaving = false
local leaveAt = 0
local stare = 0 -- seconds of staring, 0..stareLimit
local tone: Sound? = nil
local vignette: { Frame } = {}
local vignetteRoot: Frame? = nil
local clock = 0
local failedAt = -math.huge

local function rootAt(pos: Vector3): CFrame
	local y = Common.groundY(pos.X, pos.Z)
	local feet = Vector3.new(pos.X, y - 0.2, pos.Z)
	local hull = BoatClient.hull()
	local look = if hull then Vector3.new(hull.Position.X, feet.Y, hull.Position.Z) else feet + Vector3.new(0, 0, -1)
	if (look - feet).Magnitude < 0.1 then
		look = feet + Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(feet, look)
end

local function remove()
	local f = figure
	figure = nil
	from, to = nil, nil
	leaving = false
	if f then
		f.model:Destroy()
	end
end

local function setVignette(level: number)
	local root = vignetteRoot
	if root == nil then
		return
	end
	root.Visible = level > 0.01
	for _, fr in vignette do
		fr.BackgroundTransparency = 1 - math.clamp(level, 0, 1) * 0.92
	end
end

local function buildVignette()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeadCalmVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = gui
	vignetteRoot = root
	-- Four edge bands fading toward the center (UIGradient: transparency 0 at the edge).
	local bands = {
		{ UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), 90 }, -- top, fades downward
		{ UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0.58), -90 }, -- bottom
		{ UDim2.fromScale(0.38, 1), UDim2.fromScale(0, 0), 0 }, -- left
		{ UDim2.fromScale(0.38, 1), UDim2.fromScale(0.62, 0), 180 }, -- right
	}
	for i, b in bands do
		local f = Instance.new("Frame")
		f.Name = "Band" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.Size = b[1]
		f.Position = b[2]
		f.Parent = root
		local g = Instance.new("UIGradient")
		g.Rotation = b[3]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		table.insert(vignette, f)
	end
end

-- True when the local camera looks straight at the figure (and the player is alive).
local function staring(): boolean
	local f = figure
	local cam = Workspace.CurrentCamera
	local pv = ViewState.me()
	if f == nil or cam == nil or leaving or (pv ~= nil and not pv.alive) or Common.isDrowned() then
		return false
	end
	local look = cam.CFrame.LookVector
	local yaw = math.atan2(look.X, look.Z)
	local diff = math.abs(Common.wrapAngle(yaw - Common.bearing(cam.CFrame.Position, f.root.Position)))
	return diff < Config.Rules.Watcher.stareCone
end

local function step(dt: number)
	clock += dt
	local f = figure
	if f then
		if moveT < 1 and from and to then
			moveT = math.min(1, moveT + dt / moveLen)
			local k = 1 - (1 - moveT) * (1 - moveT)
			Common.placeFigure(f, (from :: CFrame):Lerp(to :: CFrame, k))
		end
		if leaving then
			local cam = Workspace.CurrentCamera
			local onScreen = false
			if cam then
				local _, vis = cam:WorldToViewportPoint(f.root.Position + Vector3.new(0, Watcher.HEIGHT * 0.6, 0))
				onScreen = vis
			end
			if not onScreen or clock - leaveAt > Watcher.GONE_AFTER then
				remove()
			end
		end
	end
	local limit = Config.Rules.Watcher.stareLimit
	if staring() then
		stare = math.min(limit, stare + dt)
	else
		stare = math.max(0, stare - dt * 2.5)
	end
	local level = stare / limit
	setVignette(level)
	if level > 0.01 and tone == nil then
		tone = AudioDirector.loop("watcher-tone-loop", nil, 0)
	end
	local t = tone
	if t then
		t.Volume = AudioDirector.baseVolume("watcher-tone-loop") * level
		t.PlaybackSpeed = 1 + level * 0.12 -- the tone climbs as the stare goes on
		if level <= 0.01 then
			t:Destroy()
			tone = nil
		end
	end
end

local function moveTo(pos: Vector3, seconds: number)
	local f = figure
	if f == nil then
		return
	end
	from = f.root
	to = rootAt(pos)
	moveT = 0
	moveLen = seconds
end

function Watcher.handle(e: any)
	local data = e.data or {}
	local pos = if type(data.pos) == "table" then Common.water(data.pos) else nil
	if e.kind == "EntityCue" then
		remove()
		if pos == nil then
			return
		end
		local f = Common.figure("Watcher", { height = Watcher.HEIGHT, width = Watcher.WIDTH, eyes = true })
		figure = f
		Common.placeFigure(f, rootAt(pos))
		Common.outline(f.model)
		lastStep = tonumber(data.step)
		moveT = 1
	elseif e.kind == "EntityMoved" then
		if pos == nil or figure == nil then
			return
		end
		local stepN = tonumber(data.step)
		local lunge = lastStep ~= nil and stepN ~= nil and (lastStep :: number) - stepN >= 2
		lastStep = stepN
		local f = figure :: Common.Figure
		if lunge then
			AudioDirector.play("watcher-lunge", f.model.PrimaryPart)
			moveTo(pos, Watcher.LUNGE_SECONDS)
		else
			AudioDirector.play("watcher-step", f.model.PrimaryPart)
			moveTo(pos, Watcher.STEP_SECONDS)
		end
	elseif e.kind == "EntityPass" then
		AudioDirector.play("watcher-pass")
		leaving = true
		leaveAt = clock
	elseif e.kind == "EntityFail" then
		AudioDirector.play("lanterns-die")
		AudioDirector.play("watcher-fail")
		failedAt = os.clock()
		-- It stands at the waterline a while: the drowned see it there, outlined.
		local f = figure
		task.delay(Watcher.STAYS_AFTER_FAIL, function()
			if figure == f then
				remove()
			end
		end)
	elseif e.kind == "EntityStage" and data.stage == "Cooldown" then
		if not leaving and os.clock() - failedAt > Watcher.STAYS_AFTER_FAIL then
			remove()
		end
	end
end

function Watcher.reset()
	failedAt = -math.huge
	remove()
	stare = 0
end

function Watcher.init()
	buildVignette()
	RunService.RenderStepped:Connect(step)
end

-- Where the figure's eyes are, or nil (DebugBot frames it for captures).
function Watcher.focus(): Vector3?
	local f = figure
	if f == nil then
		return nil
	end
	return f.root.Position + Vector3.new(0, Watcher.HEIGHT * 0.85, 0)
end

-- For checks: how deep the stare is (0..1).
function Watcher.stareLevel(): number
	return stare / Config.Rules.Watcher.stareLimit
end

return Watcher
