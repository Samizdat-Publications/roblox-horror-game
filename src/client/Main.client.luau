--!strict
-- Client entry point: input, camera, audio, light motion and the HUD.
-- Prints exactly one line in normal operation; anything else is a warning or an error.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local client = script.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local Input = require(client:WaitForChild("Input"))
local Camera = require(client:WaitForChild("Camera"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local WorldFx = require(client:WaitForChild("WorldFx"))
local HUD = require(client:WaitForChild("ui"):WaitForChild("HUD"))

-- The default emote menu is off: our Wave lives in the callout wheel (S3).
local ok, err = pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
end)
if not ok then
	warn("[DeadCalm] could not turn off the emotes menu: " .. tostring(err))
end

ViewState.init()
Input.init()
Camera.init()
AudioDirector.init()
WorldFx.init()
HUD.init()

if RunService:IsStudio() then
	local DebugBot = require(client:WaitForChild("DebugBot"))
	DebugBot.init()
end

print("[DeadCalm] client up")
