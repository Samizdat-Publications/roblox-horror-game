--[[
Pacing simulation (placeholder). The cloud helper replaces this file with the real
bot-night sim once src/shared/Core/Night.luau exists.

    lune run tools/sim/pacing.luau [--fast]

Until then it skips with exit 0. If Night.luau exists while this placeholder is still
here, it fails, so the gate cannot pass without a real pacing sim.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local fast = false
for _, arg in process.args do
	if arg == "--fast" then
		fast = true
	else
		print("pacing sim: unknown argument " .. arg)
		process.exit(2)
	end
end

if not fs.isFile("src/shared/Core/Night.luau") then
	print("pacing sim: no Night module yet (skipped)")
	process.exit(0)
end

print(
	string.format(
		"pacing sim: src/shared/Core/Night.luau exists but tools/sim/pacing.luau is still the placeholder%s. Write the real sim.",
		if fast then " (--fast)" else ""
	)
)
process.exit(1)
