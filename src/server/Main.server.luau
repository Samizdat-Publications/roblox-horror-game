--!strict
-- Server entry point. World building and services start here in later milestones.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

print("[DeadCalm] server up")

if RunService:IsStudio() then
	local DebugDriver = require(script.Parent:WaitForChild("DebugDriver")) :: any
	-- A BindableFunction is an Instance, so command bar or execute_luau code in any server
	-- context can reach this live copy of DebugDriver (see the top of DebugDriver.luau).
	local old = ServerScriptService:FindFirstChild(DebugDriver.BINDABLE_NAME)
	if old then
		old:Destroy()
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = DebugDriver.BINDABLE_NAME
	bindable.OnInvoke = function(name: string, opts: { [string]: any }?)
		return DebugDriver.run(name, opts)
	end
	bindable.Parent = ServerScriptService
end
