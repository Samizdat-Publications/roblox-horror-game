-- Core.Validate: every client-to-server remote, good and bad payloads.
return function(t, Shared)
	local Validate = require(Shared.Core.Validate)
	local Config = require(Shared.Config)

	local junk = { nil, true, "x", {}, 0 / 0, math.huge, -math.huge }

	t.test("BoatInput clamps finite numbers and rejects junk", function()
		local ok, v = Validate.BoatInput(Config, 2, -0.5)
		t.ok(ok, "valid")
		t.eq(v.throttle, 1, "clamped")
		t.eq(v.steer, -0.5, "steer")
		for _, j in junk do
			t.ok(not Validate.BoatInput(Config, j, 0), "junk throttle " .. tostring(j))
			t.ok(not Validate.BoatInput(Config, 0, j), "junk steer " .. tostring(j))
		end
	end)

	t.test("Gaze wraps to [-pi, pi) and rejects absurd values", function()
		local ok, yaw = Validate.Gaze(Config, 3 * math.pi / 2)
		t.ok(ok, "valid")
		t.ok(math.abs(yaw + math.pi / 2) < 1e-9, "wrapped " .. tostring(yaw))
		t.ok(not Validate.Gaze(Config, 100), "too many turns")
		for _, j in junk do
			if j ~= 0 then
				t.ok(not Validate.Gaze(Config, j), "junk " .. tostring(j))
			end
		end
	end)

	t.test("every intent kind accepts its correct shape", function()
		local args = {
			num01 = { 0.5, nil, nil },
			flag = { nil, true, nil },
			callout = { nil, nil, Config.Callouts[1] },
			none = { nil, nil, nil },
		}
		for kind, shape in Validate.INTENTS do
			local a = args[shape]
			local ok, v = Validate.Intent(Config, kind, a[1], a[2], a[3])
			t.ok(ok, kind .. ": " .. tostring(v))
			t.eq(v.kind, kind, "kind kept")
			t.eq(v.player, nil, "Net adds the player, not the client")
		end
	end)

	t.test("intent kinds match the Types contract list", function()
		local expected = {
			"ToggleLantern",
			"ToggleMotor",
			"Cast",
			"ReelHold",
			"CutLine",
			"CatchDecision",
			"Bank",
			"RefillOil",
			"Knock",
			"Wave",
			"BailHold",
			"GhostBell",
			"Callout",
		}
		local n = 0
		for _ in Validate.INTENTS do
			n += 1
		end
		t.eq(n, #expected, "count")
		for _, k in expected do
			t.ok(Validate.INTENTS[k] ~= nil, k)
		end
	end)

	t.test("intents reject bad kinds and bad fields", function()
		t.ok(not Validate.Intent(Config, "Catch"), "a client cannot send a catch")
		t.ok(not Validate.Intent(Config, "SetQuota"), "unknown")
		t.ok(not Validate.Intent(Config, 5), "non-string kind")
		t.ok(not Validate.Intent(Config, string.rep("A", 100)), "long kind")
		t.ok(not Validate.Intent(Config, "Cast", 1.5), "cast power over 1")
		t.ok(not Validate.Intent(Config, "Cast", -0.1), "cast power under 0")
		t.ok(not Validate.Intent(Config, "Cast", 0 / 0), "cast NaN")
		t.ok(not Validate.Intent(Config, "ReelHold", nil, "yes"), "flag must be boolean")
		t.ok(not Validate.Intent(Config, "CatchDecision"), "flag missing")
		t.ok(not Validate.Intent(Config, "Callout", nil, nil, "hello everyone"), "free text refused")
		t.ok(not Validate.Intent(Config, "Callout", nil, nil, 3), "non-string phrase")
	end)

	t.test("lobby actions", function()
		t.ok(Validate.Lobby(Config, "Start"), "start")
		t.ok(Validate.Lobby(Config, "Difficulty", "Nightmare"), "difficulty")
		t.ok(not Validate.Lobby(Config, "Difficulty", "Easy"), "unknown difficulty")
		t.ok(Validate.Lobby(Config, "Mode", "Endless"), "mode")
		t.ok(not Validate.Lobby(Config, "Mode", 2), "bad mode")
		t.ok(Validate.Lobby(Config, "Supply", "OilCan"), "supply")
		t.ok(not Validate.Lobby(Config, "Supply", "Robux"), "unknown supply")
		t.ok(Validate.Lobby(Config, "Ready", false), "ready")
		t.ok(not Validate.Lobby(Config, "Ready", "no"), "ready needs boolean")
		t.ok(not Validate.Lobby(Config, "Kick", 1), "unknown action")
	end)

	t.test("cosmetics must name a real slot and id", function()
		t.ok(Validate.Cosmetic(Config, "lantern", "BoneWhite"), "valid")
		t.ok(not Validate.Cosmetic(Config, "lantern", "Gold"), "unknown id")
		t.ok(not Validate.Cosmetic(Config, "wings", "BoneWhite"), "unknown slot")
		t.ok(not Validate.Cosmetic(Config, nil, nil), "missing")
	end)

	t.test("remote dispatch refuses server-to-client names", function()
		t.ok(Validate.remote(Config, "BoatInput", 0, 0), "BoatInput")
		t.ok(Validate.remote(Config, "Intent", "Bank"), "Intent")
		for _, name in { "View", "Events", "LobbyState", "Profile", "Nope" } do
			t.ok(not Validate.remote(Config, name, {}), name)
		end
	end)
end
