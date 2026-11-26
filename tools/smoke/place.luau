--[[
Opens the built place and checks its structure.

    lune run tools/smoke/place.luau [path]

Run it from the project root after `rojo build -o DeadCalm.rbxl`. Exit code 1 on any miss.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "DeadCalm.rbxl"
if not fs.isFile(path) then
	print("SMOKE: " .. path .. " not found (run rojo build -o DeadCalm.rbxl first)")
	process.exit(1)
end

local place = roblox.deserializePlace(fs.readFile(path))

local expected = {
	{ "ReplicatedStorage.Shared", "Folder" },
	{ "ReplicatedStorage.Shared.Config", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Core", "Folder" },
	{ "ReplicatedStorage.Shared.Core.Types", "ModuleScript" },
	{ "ReplicatedStorage.Shared.Core.Rng", "ModuleScript" },
	{ "ServerScriptService.Server", "Folder" },
	{ "ServerScriptService.Server.Main", "Script" },
	{ "ServerScriptService.Server.DebugDriver", "ModuleScript" },
	{ "StarterPlayer.StarterPlayerScripts.Client", "Folder" },
	{ "StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript" },
}

local failures = 0
for _, item in expected do
	local fullName, className = item[1], item[2]
	local node: any = place
	for part in string.gmatch(fullName, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	if node == nil then
		print("  MISSING " .. fullName)
		failures += 1
	elseif node.ClassName ~= className then
		print(string.format("  WRONG CLASS %s: expected %s, got %s", fullName, className, node.ClassName))
		failures += 1
	end
end

print(string.format("SMOKE: %d of %d checks passed", #expected - failures, #expected))
process.exit(if failures == 0 then 0 else 1)
