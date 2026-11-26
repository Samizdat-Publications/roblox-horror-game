--!strict
--[[
Studio-only scenario driver for captures and checks. Inert outside Studio.

Call it from server-side Luau (the Studio command bar on the server during Play, or the
Studio MCP `execute_luau` tool), one line:

    return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hello")

That goes through the BindableFunction Main.server creates, so it reaches the live
server's copy of this module (and its state). For a stateless call, requiring by path also
works:

    return require(game:GetService("ServerScriptService").Server.DebugDriver).run("hello")

Scenarios:
    "hello"  returns "hello from DebugDriver", Config.TITLE
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

export type Opts = { [string]: any }

local DebugDriver = {}

DebugDriver.BINDABLE_NAME = "DeadCalmDebug"

local scenarios: { [string]: (opts: Opts) -> ...any } = {}

scenarios.hello = function(_opts: Opts)
	return "hello from DebugDriver", Config.TITLE
end

function DebugDriver.active(): boolean
	return RunService:IsStudio()
end

function DebugDriver.list(): { string }
	local names = {}
	for name in scenarios do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DebugDriver.run(name: string, opts: Opts?): ...any
	if not DebugDriver.active() then
		error("DebugDriver runs only in Studio", 2)
	end
	local scenario = scenarios[name]
	if scenario == nil then
		error(
			string.format("unknown DebugDriver scenario %q (have: %s)", name, table.concat(DebugDriver.list(), ", ")),
			2
		)
	end
	return scenario(opts or {})
end

return DebugDriver
