--!strict
-- What happens to your boat, on screen, for players with the sound off (brief, 11/26/2026):
--   * buzz(level): the floorboards visibly buzz (a rapid small offset on local floor slats)
--     and the camera trembles a hair. The Hum drives it.
--   * shiver(level): the lantern flame shivers fast (WorldFx reads lanternFactor).
--   * shake(amount, seconds): a knock or a blow on the hull shakes the camera.
--   * flicker(seconds): the lantern nearly dies for a moment (the fake-out).
--   * the water in the boat rises with view.flood, and every bailing crewmate throws a scoop
--     of it over the side with a sound.
-- The slats and the water are local parts that follow the hull every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent
local BoatClient = require(client:WaitForChild("BoatClient"))
local ViewState = require(client:WaitForChild("ViewState"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Common = require(client:WaitForChild("fx"):WaitForChild("Common"))

local BoatFx = {}

BoatFx.SLATS = 5
BoatFx.FLOOD_DEPTH = 1.35 -- water depth in the boat when full
BoatFx.SCOOP_EVERY = 1.1

local buzzLevel = 0
local buzzTarget = 0
local shiverLevel = 0
local shiverTarget = 0
local shakeAmp = 0
local shakeUntil = 0
local shakeLen = 0.0001
local flickerUntil = 0
local clock = 0
local rnd = Random.new()

local slats: { { part: BasePart, offset: CFrame, seed: number } } = {}
local water: BasePart? = nil
local floodLoop: Sound? = nil
local leak = false
local scoopT: { [number]: number } = {}

function BoatFx.buzz(level: number)
	buzzTarget = math.clamp(level, 0, 1)
end

function BoatFx.shiver(level: number)
	shiverTarget = math.clamp(level, 0, 1)
end

-- A one-off shake. Overlapping shakes keep the stronger one.
function BoatFx.shake(amount: number, seconds: number)
	local now = clock
	local left = math.max(0, shakeUntil - now)
	local current = if left > 0 then shakeAmp * (left / shakeLen) else 0
	if amount >= current then
		shakeAmp = amount
		shakeUntil = now + seconds
		shakeLen = math.max(seconds, 0.0001)
	end
end

function BoatFx.flicker(seconds: number)
	flickerUntil = math.max(flickerUntil, clock + seconds)
end

-- Multiplier for the lantern's brightness this frame (WorldFx applies it).
function BoatFx.lanternFactor(): number
	if clock < flickerUntil then
		-- Nearly out, catching twice.
		local n = math.noise(clock * 18, 4.2)
		return math.clamp(0.08 + n * 0.5, 0.02, 0.5)
	end
	if shiverLevel > 0.01 then
		local n = math.noise(clock * 38, 1.3)
		return 1 - shiverLevel * (0.45 + n * 0.6)
	end
	return 1
end

function BoatFx.setLeak(on: boolean)
	leak = on
end

function BoatFx.reset()
	buzzTarget, buzzLevel = 0, 0
	shiverTarget, shiverLevel = 0, 0
	shakeAmp, shakeUntil = 0, 0
	flickerUntil = 0
	leak = false
	local l = floodLoop
	if l then
		l:Destroy()
		floodLoop = nil
	end
end

local function buildSlats(hull: BasePart)
	for _, s in slats do
		s.part:Destroy()
	end
	slats = {}
	local wood = Look.Palette.boatWood:Lerp(Look.Palette.boatTrim, 0.35)
	for i = 1, BoatFx.SLATS do
		local x = -1.8 + (i - 1) * (3.6 / (BoatFx.SLATS - 1))
		local offset = CFrame.new(x, 0.29, 0.2)
		local p = Common.part(
			"FloorSlat" .. i,
			Vector3.new(0.72, 0.07, 10.4),
			hull.CFrame * offset,
			wood,
			Enum.Material.WoodPlanks
		)
		table.insert(slats, { part = p, offset = offset, seed = i * 7.3 })
	end
end

local function stepWater(hull: BasePart, flood: number)
	local w = water
	if w == nil or w.Parent == nil then
		w = Common.part(
			"BoatWater",
			Vector3.new(4.4, 0.1, 11.4),
			hull.CFrame,
			Look.Palette.water:Lerp(Look.Palette.fog, 0.3),
			Enum.Material.SmoothPlastic,
			{ transparency = 0.25, reflectance = 0.15 }
		)
		water = w
	end
	local wp = w :: BasePart
	if flood <= 0.005 then
		wp.Transparency = 1
		return
	end
	local depth = math.max(0.08, flood * BoatFx.FLOOD_DEPTH)
	wp.Size = Vector3.new(4.4, depth, 11.4)
	local slosh = math.sin(clock * 1.3) * 0.03
	wp.CFrame = hull.CFrame * CFrame.new(0, 0.26 + depth / 2, 0.2) * CFrame.Angles(slosh, 0, slosh * 0.6)
	wp.Transparency = 0.25
end

-- A scoop of water thrown over the side by a bailing crewmate (a visual tell for the sound).
local function scoop(hull: BasePart, side: number)
	local from = hull.CFrame * CFrame.new(side * 1.2, 1.2, rnd:NextNumber(-3, 3))
	local blob = Common.part(
		"Scoop",
		Vector3.new(0.5, 0.35, 0.5),
		from,
		Look.Palette.water:Lerp(Color3.new(1, 1, 1), 0.25),
		Enum.Material.SmoothPlastic,
		{ transparency = 0.35, shape = Enum.PartType.Ball }
	)
	local out = hull.CFrame.RightVector * side
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			local t = os.clock() - t0
			blob.CFrame = from + out * (t * 6) + Vector3.new(0, 2.2 * t - 6 * t * t, 0)
			blob.Transparency = 0.35 + t
			task.wait()
		end
		blob:Destroy()
	end)
	AudioDirector.play("bail-scoop", hull)
end

local function stepFlood(dt: number, hull: BasePart)
	local view = ViewState.get()
	local flood = tonumber(view.flood) or 0
	stepWater(hull, flood)
	local wantLoop = flood > 0.005 and leak
	if wantLoop and floodLoop == nil then
		floodLoop = AudioDirector.loop("flood-in-loop", hull)
	elseif not wantLoop and floodLoop then
		local l = floodLoop :: Sound
		l:Destroy()
		floodLoop = nil
	end
	for i, p in view.players or {} do
		if type(p) == "table" and p.bailing and p.alive and flood > 0.005 then
			local id = tonumber(p.id) or i
			scoopT[id] = (scoopT[id] or rnd:NextNumber(0, 0.5)) - dt
			if (scoopT[id] :: number) <= 0 then
				scoopT[id] = BoatFx.SCOOP_EVERY
				scoop(hull, if i % 2 == 0 then -1 else 1)
			end
		elseif type(p) == "table" then
			scoopT[tonumber(p.id) or i] = nil
		end
	end
end

function BoatFx.init()
	local builtFor: BasePart? = nil
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local k = math.min(1, dt * 4)
		buzzLevel += (buzzTarget - buzzLevel) * k
		shiverLevel += (shiverTarget - shiverLevel) * k
		local hull = BoatClient.hull()
		if hull == nil then
			return
		end
		if builtFor ~= hull then
			buildSlats(hull)
			builtFor = hull
		end
		for _, s in slats do
			local j = CFrame.new()
			if buzzLevel > 0.01 then
				local a = buzzLevel * 0.045
				j = CFrame.new(
					math.noise(clock * 55, s.seed) * a,
					math.abs(math.noise(clock * 61, s.seed + 3)) * a * 1.6,
					math.noise(clock * 47, s.seed + 9) * a
				)
			end
			s.part.CFrame = hull.CFrame * s.offset * j
		end
		stepFlood(dt, hull)
	end)
	-- Camera shake after the camera scripts have placed the camera (Enum.RenderPriority.Camera
	-- is 200), so the offset lands on this frame.
	RunService:BindToRenderStep("DeadCalmBoatShake", Enum.RenderPriority.Camera.Value + 2, function()
		local cam = Workspace.CurrentCamera
		if cam == nil then
			return
		end
		local amp = 0
		local left = shakeUntil - clock
		if left > 0 then
			amp = shakeAmp * (left / shakeLen)
		end
		amp += buzzLevel * 0.02
		if amp <= 0.0005 then
			return
		end
		local t = clock * 30
		local off = Vector3.new(math.noise(t, 0.1), math.noise(t, 5.7), math.noise(t, 9.9)) * amp
		local roll = math.noise(t, 13.1) * amp * 0.06
		cam.CFrame = cam.CFrame * CFrame.new(off) * CFrame.Angles(0, 0, roll)
	end)
end

return BoatFx
