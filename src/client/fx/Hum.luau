--!strict
-- Rule 1, the Hum, on screen. The chorus dying is the view's job (chorus band 0, fireflies
-- freeze). This adds the hum itself:
--   EntityCue           a beat of dead quiet; the drowned see a vast shape under the hull
--   EntityStage Window  hum-rise, then hum-hold-loop; the lantern flame shivers and the
--                       floorboards buzz, building over a few seconds
--   EntityPass          the loop sinks away, hum-pass; buzz and shiver settle
--   EntityFail          the boat is thrown: hum-fail, about 1.2 s of violent roll and heave
--                       (BoatFx.capsize, the camera rolls with it), the held fish and a
--                       bucket go over the gunwale with hold-lost-splash; then the one taken
--                       is pulled under (BoatFx.plunge, death-drag) before the fade to black.
--                       The shape stays outlined for the drowned until the night moves on.

local Players = game:GetService("Players")

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local ViewState = require(client:WaitForChild("ViewState"))
local Common = require(script.Parent:WaitForChild("Common"))

local Hum = {}

Hum.THROWN = 1.2 -- seconds the boat is thrown before the taken one goes under
Hum.SHAPE_AFTER_FAIL = 20 -- the drowned keep seeing the shape this long after a fail

local loop: Sound? = nil
local shape: BasePart? = nil
local token = 0
local plungeToken = 0
local failedAt = -math.huge

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
		stopLoop(0.6)
		AudioDirector.play("hum-fail")
		BoatFx.buzz(0)
		BoatFx.shiver(0)
		-- The boat is thrown and the hold goes over the side.
		local hold = tonumber(ViewState.get().hold) or 0
		BoatFx.capsize(Hum.THROWN, math.max(1, hold))
		BoatFx.shake(0.5, Hum.THROWN + 0.4)
		-- Whoever is taken goes under (the others stay in the boat).
		local fx = data.effects
		local me = Players.LocalPlayer.UserId
		local taken = false
		if type(fx) == "table" and type(fx.kill) == "table" then
			for _, id in fx.kill do
				if id == me then
					taken = true
				end
			end
		end
		-- The plunge has its own token: the Cooldown stage that follows a fail must not
		-- cancel it. Only a new night (Hum.reset from RulesFx) does.
		plungeToken += 1
		local myPlunge = plungeToken
		if taken then
			task.delay(Hum.THROWN, function()
				if plungeToken == myPlunge then
					BoatFx.plunge()
					AudioDirector.play("death-drag")
				end
			end)
		end
		local at = os.clock()
		failedAt = at
		task.delay(Hum.SHAPE_AFTER_FAIL, function()
			if failedAt == at then
				hideShape()
			end
		end)
	elseif e.kind == "EntityStage" and data.stage == "Cooldown" then
		stopLoop(0.3)
		BoatFx.buzz(0)
		BoatFx.shiver(0)
		-- After a fail the drowned keep the outlined shape a while; otherwise it goes now.
		if os.clock() - failedAt > Hum.SHAPE_AFTER_FAIL then
			hideShape()
		end
	end
end

-- A new night: everything goes.
function Hum.reset()
	token += 1
	plungeToken += 1
	failedAt = -math.huge
	stopLoop(0.3)
	hideShape()
	BoatFx.buzz(0)
	BoatFx.shiver(0)
end

return Hum
