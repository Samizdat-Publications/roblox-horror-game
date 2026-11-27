--!strict
-- The harmless scares (Config.Fakeouts), on screen and in the ears. Each one a cue that is
-- almost a rule's, and each with a small visual tell for players with the sound off.
-- `only` is respected by the server: this client gets a fake-out only if it is meant to.
--   LoonScream      fake-loon-scream from the shore point
--   BranchSnap      fake-branch-snap from the shore point
--   FishJump        fake-fish-jump at the gunwale: a dark fish arcs out and splashes
--   SingleKnock     fake-single-knock on the hull and one small jolt (not three)
--   ChorusDip       nothing here: the view's chorus band dips (sound and fireflies follow)
--   BuoyClank       fake-buoy-clank at the old buoy (nearly a bell)
--   LanternFlicker  fake-lantern-flicker and the lantern nearly goes out for a moment
--   FireflyLight    a far warm light on the shore that drifts apart into fireflies

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Common = require(script.Parent:WaitForChild("Common"))

local Fakeouts = {}

local rnd = Random.new()

local function ripple(at: Vector3, size: number)
	local ring = Common.part(
		"Ripple",
		Vector3.new(0.05, size, size),
		CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Look.Palette.fog:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Cylinder, transparency = 0.5 }
	)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.4 do
			local t = (os.clock() - t0) / 1.4
			local s = size * (1 + t * 2.5)
			ring.Size = Vector3.new(0.05, s, s)
			ring.Transparency = 0.5 + t * 0.5
			task.wait()
		end
		ring:Destroy()
	end)
end

local function fishJump(at: Vector3)
	local hull = BoatClient.hull()
	local away = if hull
		then (Vector3.new(at.X, 0, at.Z) - Vector3.new(hull.Position.X, 0, hull.Position.Z))
		else Vector3.zero
	local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
	local fish = Common.part(
		"JumpingFish",
		Vector3.new(0.6, 0.7, 2),
		CFrame.new(at),
		Color3.fromRGB(24, 28, 26),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	ripple(at, 1.2)
	task.spawn(function()
		local t0 = os.clock()
		local len = 0.75
		while os.clock() - t0 < len do
			local t = (os.clock() - t0) / len
			local p = at + dir * (t * 3.5) + Vector3.new(0, math.sin(t * math.pi) * 2.6, 0)
			local tilt = (0.5 - t) * 1.6
			fish.CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(tilt, 0, 0)
			task.wait()
		end
		ripple(at + dir * 3.5, 1.6)
		fish:Destroy()
	end)
end

-- A warm light low on the shore, like a lantern. Then it comes apart: just fireflies.
local function fireflyLight(at: Vector3)
	local y = Common.groundY(at.X, at.Z) + 3
	local center = Vector3.new(at.X, y, at.Z)
	local core = Common.part(
		"FarLight",
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(center),
		Look.Palette.lantern,
		Enum.Material.Neon,
		{ shape = Enum.PartType.Ball, transparency = 0.2 }
	)
	local light = Instance.new("PointLight")
	light.Color = Look.Palette.lantern
	light.Range = 24
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = core
	local specks: { { part: BasePart, dir: Vector3 } } = {}
	for i = 1, 14 do
		local p = Common.part(
			"Speck" .. i,
			Vector3.new(0.3, 0.3, 0.3),
			CFrame.new(center),
			Look.Fireflies.color,
			Enum.Material.Neon,
			{ shape = Enum.PartType.Ball, transparency = 1 }
		)
		local d = Vector3.new(rnd:NextNumber(-1, 1), rnd:NextNumber(-0.3, 0.6), rnd:NextNumber(-1, 1))
		table.insert(specks, { part = p, dir = if d.Magnitude > 0.01 then d.Unit else Vector3.new(0, 1, 0) })
	end
	task.spawn(function()
		task.wait(4)
		local t0 = os.clock()
		local len = 5
		while os.clock() - t0 < len do
			local t = (os.clock() - t0) / len
			core.Transparency = 0.2 + t * 0.8
			light.Brightness = 1.6 * (1 - t)
			for i, s in specks do
				local wob = Vector3.new(math.sin(os.clock() * 2 + i), math.cos(os.clock() * 1.7 + i), 0) * 0.3
				s.part.CFrame = CFrame.new(center + s.dir * (t * 9) + wob)
				s.part.Transparency = if t < 0.7 then 0.1 else 0.1 + (t - 0.7) * 3
			end
			task.wait()
		end
		core:Destroy()
		for _, s in specks do
			s.part:Destroy()
		end
	end)
end

function Fakeouts.handle(e: any)
	local data = e.data or {}
	local id = tostring(data.id)
	local pos = if type(data.pos) == "table" then Common.water(data.pos, 0.5) else nil
	local hull = BoatClient.hull()
	if id == "LoonScream" then
		AudioDirector.play("fake-loon-scream", pos)
	elseif id == "BranchSnap" then
		AudioDirector.play("fake-branch-snap", pos)
	elseif id == "FishJump" then
		local at = pos or (if hull then hull.Position + Vector3.new(4, 0, 0) else nil)
		if at then
			AudioDirector.play("fake-fish-jump", at)
			fishJump(Vector3.new(at.X, 0, at.Z))
		end
	elseif id == "SingleKnock" then
		AudioDirector.play("fake-single-knock", AudioDirector.under() or hull)
		BoatFx.shake(0.18, 0.3)
	elseif id == "BuoyClank" then
		AudioDirector.play("fake-buoy-clank", pos)
	elseif id == "LanternFlicker" then
		AudioDirector.play("fake-lantern-flicker", BoatClient.part("LanternGlow"))
		BoatFx.flicker(tonumber(data.seconds) or 0.6)
	elseif id == "FireflyLight" then
		if pos then
			fireflyLight(pos)
		end
	end
	-- ChorusDip: the view's chorus band does it.
end

return Fakeouts
