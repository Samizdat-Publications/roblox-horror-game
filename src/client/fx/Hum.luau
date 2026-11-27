--!strict
-- Rule 1, the Hum, on screen. The chorus dying is the view's job (chorus band 0, fireflies
-- freeze). This adds the hum itself:
--   EntityCue           a beat of dead quiet; the drowned see a vast shape under the hull
--   EntityStage Window  hum-rise, then hum-hold-loop; the lantern flame shivers and the
--                       floorboards buzz, building over a few seconds
--   EntityPass          the loop sinks away, hum-pass; buzz and shiver settle
--   EntityFail          hum-fail and the boat is thrown (a hard shake)

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Common = require(script.Parent:WaitForChild("Common"))

local Hum = {}

local loop: Sound? = nil
local shape: BasePart? = nil
local token = 0

local function stopLoop(fade: number)
	local l = loop
	loop = nil
	if l == nil then
		return
	end
	local v0 = l.Volume
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < fade and l.Parent do
			l.Volume = v0 * (1 - (os.clock() - t0) / fade)
			task.wait()
		end
		l:Destroy()
	end)
end

-- The thing under the boat: only the drowned see it.
local function showShape()
	if shape and shape.Parent then
		return
	end
	local hull = BoatClient.hull()
	if hull == nil then
		return
	end
	local p = Common.part(
		"UnderHull",
		Vector3.new(26, 7, 44),
		hull.CFrame * CFrame.new(0, -9, 0),
		Color3.fromRGB(8, 12, 14),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	Common.ghostOnly(p, 0.35)
	Common.outline(p)
	shape = p
	task.spawn(function()
		while p.Parent do
			local h = BoatClient.hull()
			if h then
				p.CFrame = h.CFrame * CFrame.new(0, -9 + math.sin(os.clock() * 0.6) * 0.6, 0)
			end
			task.wait()
		end
	end)
end

local function hideShape()
	local s = shape
	shape = nil
	if s then
		s:Destroy()
	end
end

function Hum.handle(e: any)
	local data = e.data or {}
	local kind = e.kind
	local stage = if kind == "EntityStage" then data.stage else nil
	if kind == "EntityStage" and stage ~= "Window" and stage ~= "Cooldown" then
		return -- the Cue, Pass and Fail stages come with their own events
	end
	token += 1
	local my = token
	if e.kind == "EntityCue" then
		showShape()
	elseif e.kind == "EntityStage" and data.stage == "Window" then
		showShape()
		AudioDirector.play("hum-rise")
		-- Build the visual tells over the rise, then hold.
		task.spawn(function()
			for i = 1, 20 do
				if token ~= my then
					return
				end
				BoatFx.buzz(i / 20)
				BoatFx.shiver(i / 20)
				task.wait(0.12)
			end
		end)
		task.delay(2.2, function()
			if token == my and loop == nil then
				loop = AudioDirector.loop("hum-hold-loop", nil)
			end
		end)
	elseif e.kind == "EntityPass" then
		stopLoop(2.5)
		AudioDirector.play("hum-pass")
		BoatFx.buzz(0)
		BoatFx.shiver(0)
		task.delay(2, function()
			if token == my then
				hideShape()
			end
		end)
	elseif e.kind == "EntityFail" then
		stopLoop(0.4)
		AudioDirector.play("hum-fail")
		BoatFx.shake(1.1, 1.6)
		BoatFx.buzz(0)
		BoatFx.shiver(0)
		task.delay(2, function()
			if token == my then
				hideShape()
			end
		end)
	elseif e.kind == "EntityStage" and data.stage == "Cooldown" then
		Hum.reset()
	end
end

function Hum.reset()
	token += 1
	stopLoop(0.3)
	hideShape()
	BoatFx.buzz(0)
	BoatFx.shiver(0)
end

return Hum
