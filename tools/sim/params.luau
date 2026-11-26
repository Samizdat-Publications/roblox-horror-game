--[[
Story night parameters for the simulations (Core.Run builds these from Core M5 on; this
mirrors its rules): rules accumulate night by night, the quota and the real scare budget
scale with crew size, warnings scale with crew size, Normal difficulty, the book as
printed unless `amendments` is given.

    local params = require("./params")
    local p = params.story(cfg, Quota, night, crew, seed, amendments?)
]]

local params = {}

function params.story(cfg: any, Quota: any, night: number, crew: number, seed: number, amendments: any?)
	local rules, newRules = {}, {}
	for n = 1, night do
		for _, r in cfg.Nights[n].newRules do
			table.insert(rules, r)
			if n == night then
				table.insert(newRules, r)
			end
		end
	end
	local N = cfg.Nights[night]
	local ids = {}
	for p = 1, crew do
		table.insert(ids, p)
	end
	return {
		seed = seed,
		night = night,
		mode = "Story",
		difficulty = "Normal",
		playerIds = ids,
		rules = rules,
		newRules = newRules,
		amendments = amendments or {},
		supplies = {},
		real = math.max(1, math.floor(N.real * cfg.Scaling.budget[crew] + 0.5)),
		fake = N.fake,
		quietGap = N.quietGap,
		quota = Quota.scaled(cfg, N.quota, crew),
		maxConcurrent = N.maxConcurrent,
		warningScale = cfg.Scaling.warning[crew],
	}
end

-- Loads the Core modules the bots need.
function params.core(Shared: any, req: (any) -> any)
	return {
		Night = req(Shared.Core.Night),
		BoatModel = req(Shared.Core.BoatModel),
		LakeMap = req(Shared.Core.LakeMap),
		Rng = req(Shared.Core.Rng),
		WrongCatch = req(Shared.Core.WrongCatch),
		Director = req(Shared.Core.Director),
	}
end

return params
