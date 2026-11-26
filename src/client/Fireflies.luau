--!strict
-- Fireflies: the visual twin of the frog chorus, for players with the sound off. Small Neon
-- specks drift near the nearest shore and around the boat. Many at bands 2 and 3, a few at
-- band 1; when the chorus dies they freeze in place, hold a moment, then fade. Local parts
-- only (client side), never replicated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local LakeMap = require(Shared:WaitForChild("Core"):WaitForChild("LakeMap"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local Chorus = require(script.Parent:WaitForChild("Chorus"))

type Fly = {
	part: BasePart,
	home: Vector3,
	seed: number,
	speed: number,
	alpha: number, -- 0..1 visibility
	shore: boolean,
	frozenPos: Vector3?,
	frozenGlow: number,
}

local Fireflies = {}

local flies: { Fly } = {}
local rnd = Random.new()
local clock = 0

-- How many flies should be lit at a chorus level (0..3).
function Fireflies.wanted(level: number): number
	local n = Look.Fireflies.count
	if level <= 0 then
		return 0
	elseif level < 1 then
		return math.floor(n * 0.15 * level + 0.5)
	elseif level < 2 then
		return math.floor(n * (0.15 + 0.4 * (level - 1)) + 0.5)
	end
	return math.floor(n * (0.55 + 0.45 * math.min(1, level - 2)) + 0.5)
end

local function center(): Vector3
	local pos = BoatClient.pose()
	if pos then
		return pos
	end
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

local function placeHome(f: Fly)
	local lake = Config.Lake
	local c = center()
	local F = Look.Fireflies
	if f.shore then
		local near = LakeMap.nearestShorePoint(Config, { x = c.X, z = c.Z })
		local a = math.atan2(near.z / lake.radiusZ, near.x / lake.radiusX)
			+ rnd:NextNumber(-F.shoreSpread, F.shoreSpread)
		local k = rnd:NextNumber(0.97, 1.03)
		f.home = Vector3.new(
			math.cos(a) * lake.radiusX * k,
			lake.waterY + rnd:NextNumber(1.5, 8),
			math.sin(a) * lake.radiusZ * k
		)
	else
		local a = rnd:NextNumber(0, 2 * math.pi)
		local r = rnd:NextNumber(F.boatRing[1], F.boatRing[2])
		f.home = Vector3.new(c.X + math.cos(a) * r, lake.waterY + rnd:NextNumber(1.2, 5), c.Z + math.sin(a) * r)
	end
end

local function step(dt: number)
	clock += dt
	local F = Look.Fireflies
	local level = Chorus.level()
	local silent = Chorus.silentFor()
	local want = Fireflies.wanted(level)
	local c = center()
	for i, f in flies do
		local glow
		if silent ~= nil then
			-- Freeze where they are, hold, then fade.
			if f.frozenPos == nil then
				f.frozenPos = f.part.Position
				f.frozenGlow = 0.5 + 0.5 * math.sin(clock * f.speed + f.seed)
			end
			if silent > F.freezeHold then
				f.alpha = math.max(0, f.alpha - dt / F.freezeFade)
			end
			glow = f.frozenGlow
			f.part.CFrame = CFrame.new(f.frozenPos :: Vector3)
		else
			f.frozenPos = nil
			local target = if i <= want then 1 else 0
			local stepV = F.fadePerSecond * dt
			f.alpha += math.clamp(target - f.alpha, -stepV, stepV)
			if f.alpha <= 0 and (f.home - c).Magnitude > F.relocateDist then
				placeHome(f)
			end
			local t = clock * 0.18
			local off = Vector3.new(
				math.noise(t, f.seed) * 4,
				math.noise(t * 1.3, f.seed + 5.3) * 1.5,
				math.noise(t, f.seed + 9.7) * 4
			)
			f.part.CFrame = CFrame.new(f.home + off)
			-- A slow blink: mostly dim, a soft flash now and then.
			local s = 0.5 + 0.5 * math.sin(clock * f.speed + f.seed)
			glow = s * s * s
		end
		f.part.Transparency = 1 - f.alpha * (0.25 + 0.75 * glow)
	end
end

function Fireflies.init()
	local folder = Instance.new("Folder")
	folder.Name = "DeadCalmFireflies"
	folder.Parent = Workspace
	local F = Look.Fireflies
	for i = 1, F.count do
		local p = Instance.new("Part")
		p.Name = "Firefly"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(F.size, F.size, F.size)
		p.Material = Enum.Material.Neon
		p.Color = F.color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Parent = folder
		local f: Fly = {
			part = p,
			home = Vector3.zero,
			seed = rnd:NextNumber(0, 100),
			speed = rnd:NextNumber(0.6, 1.4),
			alpha = 0,
			shore = i % 2 == 0,
			frozenPos = nil,
			frozenGlow = 0,
		}
		placeHome(f)
		table.insert(flies, f)
	end
	RunService.RenderStepped:Connect(step)
end

return Fireflies
