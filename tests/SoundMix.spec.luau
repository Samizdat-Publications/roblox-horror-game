-- Core.SoundMix: chorus bands, motor masking, radio by distance, cue ducking, the drowned.
return function(t, Shared)
	local SoundMix = require(Shared.Core.SoundMix)
	local Config = require(Shared.Config)
	local M = Config.Mix

	local function view(over)
		local v = { chorus = 3, motorOn = false }
		for k, x in over or {} do
			v[k] = x
		end
		return v
	end
	local far = { distToDock = 1000, alive = true }

	local function near(a, b, msg)
		t.ok(math.abs(a - b) < 1e-9, string.format("%s: %.4f vs %.4f", msg, a, b))
	end

	t.test("each band plays exactly one chorus layer", function()
		local expect = { [3] = "ChorusFull", [2] = "ChorusThin", [1] = "ChorusSparse" }
		for band, layer in expect do
			local m = SoundMix.targets(Config, view({ chorus = band }), far)
			for _, other in { "ChorusFull", "ChorusThin", "ChorusSparse" } do
				near(m[other], if other == layer then M.chorus else 0, "band " .. band .. " " .. other)
			end
		end
	end)

	t.test("band 0 is dead quiet: no chorus, no crickets, lower bed", function()
		local m = SoundMix.targets(Config, view({ chorus = 0 }), far)
		near(m.ChorusFull + m.ChorusThin + m.ChorusSparse + m.Crickets, 0, "silent")
		near(m.Bed, M.bedSilent, "bed drops")
		t.ok(M.bedSilent < M.bed, "silence is quieter")
	end)

	t.test("crickets thin with the band", function()
		local a = SoundMix.targets(Config, view({ chorus = 3 }), far).Crickets
		local b = SoundMix.targets(Config, view({ chorus = 1 }), far).Crickets
		t.ok(a > b and b > 0, "crickets follow")
	end)

	t.test("the motor masks the chorus and plays itself", function()
		local m = SoundMix.targets(Config, view({ motorOn = true }), far)
		near(m.ChorusFull, M.chorus * (1 - Config.Boat.motorSoundMask), "masked")
		near(m.Motor, M.motor, "motor layer")
		near(SoundMix.targets(Config, view(), far).Motor, 0, "no motor when off")
	end)

	t.test("the radio fades with distance from the dock", function()
		local function radio(d)
			return SoundMix.targets(Config, view(), { distToDock = d, alive = true }).Radio
		end
		near(radio(0), M.radio, "full at the dock")
		near(radio(M.radioNear), M.radio, "full at near")
		near(radio(M.radioFar), 0, "gone at far")
		local last = radio(M.radioNear)
		for d = M.radioNear + 10, M.radioFar, 10 do
			local r = radio(d)
			t.ok(r <= last + 1e-12, "monotonic at " .. d)
			last = r
		end
	end)

	t.test("a rule cue ducks every layer", function()
		local base = SoundMix.targets(Config, view(), { distToDock = 0, alive = true })
		local ducked = SoundMix.targets(Config, view(), { distToDock = 0, alive = true, cue = 1 })
		for _, layer in SoundMix.LAYERS do
			near(ducked[layer], base[layer] * (1 - M.cueDuck), layer)
		end
	end)

	t.test("the drowned hear a muffled lake", function()
		local base = SoundMix.targets(Config, view(), far)
		local dead = SoundMix.targets(Config, view(), { distToDock = 1000, alive = false })
		near(dead.Bed, base.Bed * (1 - M.drownedMuffle), "muffled bed")
	end)

	t.test("approach moves at most rate * dt and lands on target", function()
		near(SoundMix.approach(0, 1, 0.1, 0.8), 0.08, "step up")
		near(SoundMix.approach(1, 0, 0.1, 0.8), 0.92, "step down")
		near(SoundMix.approach(0.5, 0.52, 0.1, 0.8), 0.52, "snaps when close")
	end)
end
