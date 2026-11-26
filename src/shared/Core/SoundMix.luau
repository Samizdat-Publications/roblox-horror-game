--!strict
-- What the ambience layers should be, from the NightView and a few local facts.
-- Pure: the client's AudioDirector reads the targets and smooths toward them with
-- SoundMix.approach. Numbers live in cfg.Mix (and cfg.Boat.motorSoundMask).

local Types = require(script.Parent.Types)

type NightView = Types.NightView

-- Facts only this client knows.
export type MixFacts = {
	distToDock: number, -- studs from the listener to cfg.Lake.dockEnd
	alive: boolean, -- false for the drowned
	cue: number?, -- 0..1, how strongly a rule cue is sounding right now (ducks the rest)
}

export type MixTargets = {
	Bed: number,
	ChorusFull: number,
	ChorusThin: number,
	ChorusSparse: number,
	Crickets: number,
	Motor: number,
	Radio: number,
}

local SoundMix = {}

SoundMix.LAYERS = { "Bed", "ChorusFull", "ChorusThin", "ChorusSparse", "Crickets", "Motor", "Radio" }

-- 1 at or inside `near`, 0 at or beyond `far`, smoothstep between.
local function falloff(d: number, near: number, far: number): number
	if d <= near then
		return 1
	elseif d >= far then
		return 0
	end
	local t = 1 - (d - near) / (far - near)
	return t * t * (3 - 2 * t)
end
SoundMix.falloff = falloff

function SoundMix.targets(cfg: any, view: NightView, facts: MixFacts): MixTargets
	local M = cfg.Mix
	local band = math.clamp(math.floor(view.chorus + 0.5), 0, 3)
	local out: MixTargets = {
		Bed = if band == 0 then M.bedSilent else M.bed,
		ChorusFull = if band == 3 then M.chorus else 0,
		ChorusThin = if band == 2 then M.chorus else 0,
		ChorusSparse = if band == 1 then M.chorus else 0,
		Crickets = M.crickets * band / 3,
		Motor = if view.motorOn then M.motor else 0,
		Radio = M.radio * falloff(facts.distToDock, M.radioNear, M.radioFar),
	}
	-- The motor hides most of the chorus: the crew cannot hear trouble coming.
	if view.motorOn then
		local keep = 1 - cfg.Boat.motorSoundMask
		out.ChorusFull *= keep
		out.ChorusThin *= keep
		out.ChorusSparse *= keep
		out.Crickets *= keep
	end
	-- Rule cues duck everything else.
	local cue = math.clamp(facts.cue or 0, 0, 1)
	local mult = 1 - M.cueDuck * cue
	if not facts.alive then
		mult *= 1 - M.drownedMuffle
	end
	if mult ~= 1 then
		for _, layer in SoundMix.LAYERS do
			(out :: any)[layer] *= mult
		end
	end
	return out
end

-- Moves current toward target by at most rate * dt (for the client's smoothing).
function SoundMix.approach(current: number, target: number, dt: number, rate: number): number
	local stepv = rate * dt
	if math.abs(target - current) <= stepv then
		return target
	end
	return current + (if target > current then stepv else -stepv)
end

return SoundMix
