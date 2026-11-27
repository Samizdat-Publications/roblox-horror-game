--!strict
-- Purely visual, client-side light motion: the lantern flickers, and the dock beacon blinks
-- off twice every Look.Beacon.period seconds, in step for every client (server time).
-- The server owns whether the lantern is on (LanternOn attribute and light.Enabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local BoatFx = require(script.Parent:WaitForChild("BoatFx"))

local WorldFx = {}

-- True while the beacon is in one of its two dark blinks.
function WorldFx.beaconDark(t: number): boolean
	local b = Look.Beacon
	local phase = t % b.period
	if phase < b.blinkOn then
		return true
	end
	local second = b.blinkOn + b.blinkGap
	return phase >= second and phase < second + b.blinkOn
end

function WorldFx.init()
	local beaconColor = Look.Beacon.Color
	local dimColor = beaconColor:Lerp(Color3.new(0, 0, 0), 0.75)
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()

		local glow = BoatClient.part("LanternGlow")
		local light = glow and glow:FindFirstChild("LanternLight")
		if light and light:IsA("PointLight") and light.Enabled then
			local n = math.noise(now * Look.Lantern.flickerSpeed, 0.37) -- about -0.5..0.5
			local k = Look.Lantern.flickerLow + (1 - Look.Lantern.flickerLow) * (0.5 + n)
			-- BoatFx: the Hum makes the flame shiver; the fake-out nearly puts it out.
			light.Brightness = Look.Lantern.Brightness
				* math.clamp(k, Look.Lantern.flickerLow, 1)
				* BoatFx.lanternFactor()
		end

		local lamp = BoatClient.find("Dock", "BeaconLamp")
		local bl = lamp and lamp:FindFirstChild("BeaconLight")
		if lamp and bl and bl:IsA("PointLight") then
			local dark = WorldFx.beaconDark(now)
			bl.Enabled = not dark
			lamp.Color = if dark then dimColor else beaconColor
			lamp.Material = if dark then Enum.Material.SmoothPlastic else Enum.Material.Neon
		end
	end)
end

return WorldFx
