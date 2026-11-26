--!strict
-- Client entry point: input, camera, audio, light motion, fireflies, the HUD, the reel bar,
-- the catch held up to the lantern, the hints and the night cards.
-- Prints exactly one line in normal operation; anything else is a warning or an error.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local client = script.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local Events = require(client:WaitForChild("Events"))
local Chorus = require(client:WaitForChild("Chorus"))
local Fireflies = require(client:WaitForChild("Fireflies"))
local Input = require(client:WaitForChild("Input"))
local Camera = require(client:WaitForChild("Camera"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local WorldFx = require(client:WaitForChild("WorldFx"))
local ui = client:WaitForChild("ui")
local HUD = require(ui:WaitForChild("HUD"))
local ReelBar = require(ui:WaitForChild("ReelBar"))
local CatchInspect = require(ui:WaitForChild("CatchInspect"))
local Prompt = require(ui:WaitForChild("Prompt"))
local NightCards = require(ui:WaitForChild("NightCards"))

-- The default emote menu is off: our Wave lives in the callout wheel (S3).
local ok, err = pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
end)
if not ok then
	warn("[DeadCalm] could not turn off the emotes menu: " .. tostring(err))
end

ViewState.init()
Events.init()
Input.init()
Camera.init()
Chorus.init()
AudioDirector.init()
WorldFx.init()
Fireflies.init()
HUD.init()
ReelBar.init()
CatchInspect.init()
Prompt.init()
NightCards.init()

if RunService:IsStudio() then
	local DebugBot = require(client:WaitForChild("DebugBot"))
	DebugBot.init()
end

print("[DeadCalm] client up")
