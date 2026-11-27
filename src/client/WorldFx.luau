--!strict
-- Purely visual, client-side light motion: the lantern flickers, and the dock beacon blinks
-- off twice every Look.Beacon.period seconds, in step for every client (server time).
-- The server owns whether the lantern is on (LanternOn attribute and light.Enabled).
-- While the lantern is out, a faint cool moonlight hangs high over the boat and the outdoor
-- ambient lifts a touch, so a phone in a bright room still reads the hull, the crew and the
-- water near the boat (Neon, 11/26/2026). It fades out as the lantern comes back: the
-- lantern stays the warm, bright thing.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local BoatFx = require(script.Parent:WaitForChild("BoatFx"))

local WorldFx = {}

-- Values live in Look.Moon (polish round 3 raised them a little for dim phones).
WorldFx.MOON = Look.Moon

-- fx/Finale's dawn owns the Lighting while it shows (Polish 3): the moon then leaves
-- OutdoorAmbient alone.
WorldFx.ambientOverride = false

local moonPart: BasePart? = nil
local moonLight: PointLight? = nil
local moonLevel = 0
local lastAmbientLevel = -1

local function moon(): (BasePart, PointLight)
	local p, l = moonPart, moonLight
	if p and l and p.Parent then
		return p, l
	end
	local np = Instance.new("Part")
	np.Name = "MoonRim"
	np.Anchored = true
	np.CanCollide = false
	np.CanQuery = false
	np.CanTouch = false
	np.CastShadow = false
	np.Transparency = 1
	np.Size = Vector3.new(0.2, 0.2, 0.2)
	np.Parent = Workspace
	local nl = Instance.new("PointLight")
	nl.Color = WorldFx.MOON.color
	nl.Range = WorldFx.MOON.range
	nl.Brightness = 0
	nl.Shadows = false
	nl.Parent = np
	moonPart, moonLight = np, nl
	return np, nl
end

-- 0..1: how much moonlight this frame (1 with the lantern out, 0 with it lit).
local function stepMoon(dt: number, lanternLit: boolean)
	local target = if lanternLit then 0 else 1
	local k = WorldFx.MOON.fadePerSecond * dt
	moonLevel += math.clamp(target - moonLevel, -k, k)
	local hull = BoatClient.hull()
	local p, l = moon()
	if hull then
		p.CFrame = CFrame.new(hull.Position + Vector3.new(0, WorldFx.MOON.height, 0))
	end
	l.Brightness = WorldFx.MOON.brightness * moonLevel
	l.Enabled = moonLevel > 0.01
	local q = math.floor(moonLevel * 20 + 0.5) / 20
	if WorldFx.ambientOverride then
		lastAmbientLevel = -1 -- written again once the dawn lets go
	elseif q ~= lastAmbientLevel then
		lastAmbientLevel = q
		Lighting.OutdoorAmbient = Look.Lighting.OutdoorAmbient:Lerp(WorldFx.MOON.ambient, q)
	end
end

function WorldFx.moonLevel(): number
	return moonLevel
end

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

-- M8 polish (Neon: the "off" lantern stayed orange): the lantern's glass ball reads its state.
-- Lit: deep orange Neon. Out: a dull brass (no Neon), and every light in it is off (the
-- PointLight, and the finale's SpotLight cone if there is one). Checked every frame and written
-- only where it differs, so a late server write (BoatService.setLantern) never wins.
function WorldFx.setGlow(glow: BasePart, lit: boolean)
	local color = if lit then Look.Lantern.glowLit else Look.Lantern.glowOut
	local mat = if lit then Enum.Material.Neon else Enum.Material.Metal
	local tr = if lit then 0 else 0.1
	if glow.Color ~= color then
		glow.Color = color
	end
	if glow.Material ~= mat then
		glow.Material = mat
	end
	if glow.Transparency ~= tr then
		glow.Transparency = tr
	end
	if not lit then
		for _, d in glow:GetDescendants() do
			if d:IsA("Light") and d.Enabled then
				d.Enabled = false
			end
		end
	end
end

function WorldFx.init()
	local beaconColor = Look.Beacon.Color
	local dimColor = beaconColor:Lerp(Color3.new(0, 0, 0), 0.75)
	RunService.RenderStepped:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()

		local glow = BoatClient.part("LanternGlow")
		local light = glow and glow:FindFirstChild("LanternLight")
		local lit = false
		local attr = BoatClient.attr("LanternOn")
		if type(attr) == "boolean" then
			lit = attr
		elseif light and light:IsA("PointLight") then
			lit = light.Enabled
		end
		if glow then
			WorldFx.setGlow(glow, lit)
		end
		stepMoon(dt, lit)
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
