-- Tiny test runner for Edit-mode checks through execute_luau.
-- Each spec is a ModuleScript returning function(t, Shared). Shared is a fresh clone of
-- ReplicatedStorage.Shared so edited modules are never served from the require cache.
--
-- Run from execute_luau (Edit):
--   local tests = game.ServerScriptService.Tests
--   return require(tests.TestRunner:Clone()).runAll(tests)
local TestRunner = {}

function TestRunner.runAll(testsFolder: Instance): string
	local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):Clone()
	local passed, failed = 0, {}
	for _, spec in testsFolder:GetChildren() do
		if spec:IsA("ModuleScript") and spec.Name:match("%.spec$") then
			local fn = require(spec:Clone())
			local t = {}
			function t.test(name: string, body: () -> ())
				local ok, err = pcall(body)
				if ok then
					passed += 1
				else
					table.insert(failed, spec.Name .. " > " .. name .. ": " .. tostring(err))
				end
			end
			function t.ok(cond: any, msg: string?)
				if not cond then
					error(msg or "expected true", 2)
				end
			end
			function t.eq(a: any, b: any, msg: string?)
				if a ~= b then
					error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
				end
			end
			local ok, err = pcall(fn, t, shared)
			if not ok then
				table.insert(failed, spec.Name .. " crashed: " .. tostring(err))
			end
		end
	end
	local lines = { string.format("TESTS: %d passed, %d failed", passed, #failed) }
	for _, f in failed do
		table.insert(lines, "  FAIL " .. f)
	end
	return table.concat(lines, "\n")
end

return TestRunner
