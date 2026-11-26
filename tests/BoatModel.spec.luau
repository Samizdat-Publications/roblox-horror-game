-- Core.BoatModel: top speeds, motor vs oars, drag, turning, reverse, the shore.
return function(t, Shared)
	local BoatModel = require(Shared.Core.BoatModel)
	local Config = require(Shared.Config)

	local function run(b, seconds, throttle, steer, opts)
		local dt = 0.1
		for _ = 1, math.floor(seconds / dt + 0.5) do
			BoatModel.step(Config, b, dt, throttle, steer, opts)
		end
		return b
	end

	t.test("oars reach row speed heading north", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 5, 1, 0)
		t.ok(math.abs(b.speed - Config.Boat.rowSpeed) < 1e-6, "row speed " .. b.speed)
		t.ok(math.abs(b.vel.x) < 1e-6 and b.vel.z > 0, "moving north")
		t.ok(b.pos.z > 30, "covered ground")
	end)

	t.test("the motor is nearly three times faster", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 5, 1, 0, { motorOn = true })
		t.ok(math.abs(b.speed - Config.Boat.motorSpeed) < 1e-6, "motor speed " .. b.speed)
		t.ok(Config.Boat.motorSpeed / Config.Boat.rowSpeed > 2.5, "ratio")
	end)

	t.test("speed multiplier applies to oars only", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 6, 1, 0, { speedMult = 1.2 })
		t.ok(math.abs(b.speed - Config.Boat.rowSpeed * 1.2) < 1e-6, "waxed oars")
		local m = run(BoatModel.new({ x = 0, z = 0 }, 0), 6, 1, 0, { motorOn = true, speedMult = 1.2 })
		t.ok(math.abs(m.speed - Config.Boat.motorSpeed) < 1e-6, "motor ignores oar bonus")
	end)

	t.test("drag brings the boat to still", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 5, 1, 0)
		run(b, 4, 0, 0)
		t.ok(BoatModel.isStill(Config, b), "still after coasting, speed " .. b.speed)
	end)

	t.test("reverse is half speed", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 5, -1, 0)
		t.ok(math.abs(b.speed + Config.Boat.rowSpeed * 0.5) < 1e-6, "reverse " .. b.speed)
		t.ok(b.pos.z < 0, "went backwards")
	end)

	t.test("steer turns at turnRate and wraps", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 1, 0, 1)
		t.ok(math.abs(b.heading - Config.Boat.turnRate) < 1e-6, "turned " .. b.heading)
		run(b, 10, 0, 1)
		t.ok(b.heading >= -math.pi and b.heading <= math.pi, "wrapped")
	end)

	t.test("inputs are clamped", function()
		local b = run(BoatModel.new({ x = 0, z = 0 }, 0), 5, 9, 0)
		t.ok(math.abs(b.speed - Config.Boat.rowSpeed) < 1e-6, "clamped throttle")
		t.eq(b.throttle, 1, "stored clamped throttle")
	end)

	t.test("the boat stops at the shore and stays on the water", function()
		local b = run(BoatModel.new({ x = 0, z = 400 }, 0), 30, 1, 0, { motorOn = true })
		t.ok(b.pos.z < Config.Lake.radiusZ, "did not cross the shore")
		t.eq(b.speed, 0, "lost its speed at the shore")
	end)

	t.test("toObs copies, never aliases", function()
		local b = BoatModel.new({ x = 1, z = 2 }, 0.5)
		local o = BoatModel.toObs(b)
		o.pos.x = 99
		t.eq(b.pos.x, 1, "obs is a copy")
		t.eq(o.heading, 0.5, "heading")
	end)
end
