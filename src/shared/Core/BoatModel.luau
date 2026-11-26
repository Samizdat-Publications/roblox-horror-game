--!strict
-- Pure boat kinematics. The simulator moves its boat with this; the server uses the same
-- step to compute the target velocity it drives the physical boat toward.
-- Heading uses the gaze convention: 0 faces +z (north), forward = (sin h, cos h).

local Types = require(script.Parent.Types)
local LakeMap = require(script.Parent.LakeMap)

type Vec2 = Types.Vec2

export type BoatState = {
	pos: Vec2,
	vel: Vec2,
	heading: number,
	speed: number, -- signed, along the heading
	throttle: number, -- last input, after clamping
	steer: number,
}

export type StepOpts = {
	motorOn: boolean?,
	speedMult: number?, -- Waxed Oars and similar (oars only)
}

local BoatModel = {}

local TAU = 2 * math.pi

function BoatModel.wrapAngle(a: number): number
	a = a % TAU
	if a > math.pi then
		a -= TAU
	end
	return a
end

function BoatModel.new(pos: Vec2, heading: number?): BoatState
	return {
		pos = { x = pos.x, z = pos.z },
		vel = { x = 0, z = 0 },
		heading = BoatModel.wrapAngle(heading or 0),
		speed = 0,
		throttle = 0,
		steer = 0,
	}
end

-- Top speed for the current propulsion.
function BoatModel.maxSpeed(cfg: any, opts: StepOpts?): number
	local o: StepOpts = opts or {}
	if o.motorOn then
		return cfg.Boat.motorSpeed
	end
	return cfg.Boat.rowSpeed * (o.speedMult or 1)
end

-- Advances the boat by dt. Throttle and steer are clamped to -1..1. Reverse is half speed.
-- Acceleration scales with top speed so the motor and the oars reach full speed in the
-- same time. With no throttle, drag slows the boat. The boat stops at the shore.
function BoatModel.step(cfg: any, b: BoatState, dt: number, throttle: number, steer: number, opts: StepOpts?): BoatState
	local B = cfg.Boat
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	b.throttle, b.steer = throttle, steer
	local top = BoatModel.maxSpeed(cfg, opts)
	if math.abs(throttle) > 0.01 then
		local target = if throttle > 0 then throttle * top else throttle * top * 0.5
		local accel = B.accel * top / B.rowSpeed
		local diff = target - b.speed
		local stepv = accel * dt
		if math.abs(diff) <= stepv then
			b.speed = target
		else
			b.speed += if diff > 0 then stepv else -stepv
		end
	else
		b.speed *= math.max(0, 1 - B.drag * dt)
		if math.abs(b.speed) < 0.01 then
			b.speed = 0
		end
	end
	b.heading = BoatModel.wrapAngle(b.heading + steer * B.turnRate * dt)
	local fx, fz = math.sin(b.heading), math.cos(b.heading)
	b.vel = { x = fx * b.speed, z = fz * b.speed }
	local nextPos = { x = b.pos.x + b.vel.x * dt, z = b.pos.z + b.vel.z * dt }
	if not LakeMap.inside(cfg, nextPos) or LakeMap.distanceToShore(cfg, nextPos) < 2 then
		-- Grounded: stay where we were and lose all speed.
		b.speed = 0
		b.vel = { x = 0, z = 0 }
	else
		b.pos = nextPos
	end
	return b
end

function BoatModel.speedOf(b: BoatState): number
	return math.abs(b.speed)
end

function BoatModel.isStill(cfg: any, b: BoatState): boolean
	return math.abs(b.speed) < cfg.Boat.stillSpeed
end

-- The observation Night expects.
function BoatModel.toObs(b: BoatState): Types.BoatObs
	return {
		pos = { x = b.pos.x, z = b.pos.z },
		vel = { x = b.vel.x, z = b.vel.z },
		heading = b.heading,
		throttle = b.throttle,
		steer = b.steer,
	}
end

return BoatModel
