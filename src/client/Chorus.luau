--!strict
-- The frog chorus as one smooth number, shared by the sound (AudioDirector) and its visual
-- twin (Fireflies). The NightView carries the band (3 full, 2 thin, 1 sparse, 0 silent);
-- `level` climbs or falls toward it gradually (Look.Mix.chorusRisePerSecond), except the drop
-- to 0, which is instant: silence must be sudden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local ViewState = require(script.Parent:WaitForChild("ViewState"))

local Chorus = {}

local level = 3
local band = 3
local zeroAt: number? = nil
local riseListeners: { () -> () } = {}
local clock = 0

function Chorus.level(): number
	return level
end

function Chorus.band(): number
	return band
end

-- Seconds since the chorus died, or nil while it sings.
function Chorus.silentFor(): number?
	local z = zeroAt
	if z == nil then
		return nil
	end
	return clock - z
end

-- Called once each time the chorus comes back from silence.
function Chorus.onRise(fn: () -> ())
	table.insert(riseListeners, fn)
end

function Chorus.step(dt: number)
	clock += dt
	local raw = tonumber(ViewState.get().chorus) or 3
	local target = math.clamp(math.floor(raw + 0.5), 0, 3)
	if target == 0 then
		if band ~= 0 then
			zeroAt = clock
		end
		level = 0
	else
		if band == 0 then
			zeroAt = nil
			for _, fn in riseListeners do
				task.spawn(fn)
			end
		end
		local stepV = Look.Mix.chorusRisePerSecond * dt
		level += math.clamp(target - level, -stepV, stepV)
	end
	band = target
end

function Chorus.init()
	RunService.Heartbeat:Connect(Chorus.step)
end

return Chorus
