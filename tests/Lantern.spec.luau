-- Core.Lantern: toggle, burn, low and out, forced out, lock, refill.
return function(t, Shared)
	local Lantern = require(Shared.Core.Lantern)
	local Config = require(Shared.Config)

	local function kinds(events)
		local out = {}
		for _, e in events do
			table.insert(out, e.kind)
		end
		return table.concat(out, ",")
	end

	local function burn(l, seconds)
		local all = {}
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			for _, e in Lantern.step(Config, l, 0.1) do
				table.insert(all, e)
			end
		end
		return all
	end

	t.test("starts full and off, toggles", function()
		local l = Lantern.new(Config)
		t.eq(l.on, false, "off")
		t.eq(l.oil, 1, "full")
		t.eq(l.refills, Config.Lantern.refillsPerNight, "refills")
		local e = Lantern.toggle(l)
		t.eq(kinds(e), "LanternChanged", "event")
		t.eq(e[1].data.on, true, "on")
		t.eq(e[1].data.forced, false, "not forced")
		t.eq(#Lantern.setOn(l, true), 0, "no event when unchanged")
	end)

	t.test("a full lantern lasts burnSeconds, OilLow once, then OilOut", function()
		local l = Lantern.new(Config)
		Lantern.setOn(l, true)
		local events = burn(l, Config.Lantern.burnSeconds - 1)
		t.eq(kinds(events), "OilLow", "only low so far")
		t.ok(l.on, "still lit")
		events = burn(l, 2)
		t.eq(kinds(events), "OilOut,LanternChanged", "ran out")
		t.eq(l.on, false, "out")
		t.eq(#Lantern.setOn(l, true), 0, "cannot light without oil")
	end)

	t.test("no burn while off", function()
		local l = Lantern.new(Config)
		burn(l, 100)
		t.eq(l.oil, 1, "no oil used")
	end)

	t.test("burnMult stretches the oil", function()
		local l = Lantern.new(Config, nil, 1.25)
		Lantern.setOn(l, true)
		burn(l, Config.Lantern.burnSeconds + 5)
		t.ok(l.on and l.oil > 0, "trimmed wick still burning")
	end)

	t.test("forced out cannot be relit until the timer runs", function()
		local l = Lantern.new(Config)
		Lantern.setOn(l, true)
		local e = Lantern.forceOut(Config, l)
		t.eq(e[1].data.forced, true, "forced")
		t.eq(#Lantern.setOn(l, true), 0, "refused while forced")
		burn(l, Config.Lantern.forcedOutSeconds + 0.2)
		t.eq(#Lantern.setOn(l, true), 1, "relit after the timer")
	end)

	t.test("locked on cannot be turned off", function()
		local l = Lantern.new(Config)
		t.eq(kinds(Lantern.lockOn(l)), "LanternChanged", "lit by the lock")
		t.eq(#Lantern.setOn(l, false), 0, "cannot turn off")
		t.ok(l.on, "still on")
	end)

	t.test("refill uses a can and resets the low warning", function()
		local l = Lantern.new(Config)
		t.eq(#Lantern.refill(l), 0, "no refill when full")
		Lantern.setOn(l, true)
		burn(l, Config.Lantern.burnSeconds * 0.9)
		t.eq(kinds(Lantern.refill(l)), "OilRefilled", "refilled")
		t.eq(l.oil, 1, "full again")
		t.eq(l.refills, 0, "can used")
		t.eq(l.lowSent, false, "low warning reset")
		burn(l, 50)
		t.eq(#Lantern.refill(l), 0, "no cans left")
	end)
end
