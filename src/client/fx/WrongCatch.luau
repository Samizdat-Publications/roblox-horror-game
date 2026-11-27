--!strict
-- Rule 2, Wrong Catch, on screen. The wrong fish itself is shown by FishingService and
-- CatchInspect (built from its traits). This is what keeping one costs:
--   EntityCue    the dock cooler settles as its lid closes (nothing new is revealed)
--   EntityFail   some time later the cooler knocks from inside, three times, jumping on the
--                dock with each knock; then a wet thump (cooler-eaten) and the banked
--                total drops in the HUD
-- The cooler is a server part; this client only jiggles its own copy of its position and
-- always puts it back.

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))

local WrongCatch = {}

WrongCatch.KNOCK_GAP = 0.8

local busy = false
local token = 0

local function cooler(): BasePart?
	return BoatClient.find("Dock", "DockCooler")
end

local function nearCooler(c: BasePart): boolean
	local hull = BoatClient.hull()
	return hull ~= nil and (hull.Position - c.Position).Magnitude < 60
end

-- One jump of the cooler (and any lid parts welded or named after it).
local function jump(c: BasePart, strength: number)
	local home = c.CFrame
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.22 do
			local t = (os.clock() - t0) / 0.22
			local lift = math.sin(t * math.pi) * 0.25 * strength
			local tilt = math.sin(t * math.pi * 2) * 0.05 * strength
			c.CFrame = home * CFrame.new(0, lift, 0) * CFrame.Angles(tilt, 0, tilt * 0.5)
			task.wait()
		end
		c.CFrame = home
	end)
end

function WrongCatch.handle(e: any)
	local c = cooler()
	if e.kind == "EntityCue" then
		AudioDirector.play("cooler-close", c or BoatClient.hull(), { volume = 0.5, speed = 0.85 })
	elseif e.kind == "EntityFail" then
		if busy then
			return
		end
		busy = true
		token += 1
		local my = token
		task.spawn(function()
			-- The registry plays cooler-knock-inside three times (`repeat`); here at
			-- KNOCK_GAP so the jumps line up (it used to start three times: nine knocks).
			local knock = AudioDirector.play(
				"cooler-knock-inside",
				cooler() or BoatClient.hull(),
				{ repeatGap = WrongCatch.KNOCK_GAP }
			)
			for i = 1, 3 do
				if token ~= my then
					if knock and knock.Parent then
						knock:Destroy()
					end
					break
				end
				local cc = cooler()
				if cc then
					jump(cc, 1 + i * 0.25)
					if nearCooler(cc) then
						BoatFx.shake(0.12, 0.25)
					end
				end
				task.wait(WrongCatch.KNOCK_GAP)
			end
			if token == my then
				AudioDirector.play("cooler-eaten", cooler() or BoatClient.hull())
			end
			busy = false
		end)
	end
end

function WrongCatch.reset()
	token += 1
	busy = false
end

return WrongCatch
