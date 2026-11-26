--!strict
-- Applies the night look from Look.Lighting at server start: Lighting properties, one
-- Atmosphere, ColorCorrection, Bloom and a Sky with no stars or moon. Idempotent.
-- Lighting properties set on the server replicate to every client.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local LightingController = {}

local function setAll(inst: Instance, props: { [string]: any }, warnings: { string })
	for key, value in props do
		if type(value) ~= "table" then
			local ok, err = pcall(function()
				(inst :: any)[key] = value
			end)
			if not ok then
				local msg = string.format("Lighting: could not set %s.%s (%s)", inst.ClassName, key, tostring(err))
				table.insert(warnings, msg)
				warn("[DeadCalm] " .. msg)
			end
		end
	end
end

local function fresh(className: string, name: string): Instance
	local old = Lighting:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local inst = Instance.new(className :: any)
	inst.Name = name
	return inst
end

function LightingController.apply(): { string }
	local warnings: { string } = {}
	local L = Look.Lighting
	setAll(Lighting, L, warnings)

	-- Our own effects only: remove any other Atmosphere, Sky or post effect so ours win.
	for _, child in Lighting:GetChildren() do
		if
			(child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("PostEffect"))
			and string.sub(child.Name, 1, 8) ~= "DeadCalm"
		then
			child:Destroy()
		end
	end

	local atmo = fresh("Atmosphere", "DeadCalmAtmosphere")
	setAll(atmo, L.atmosphere, warnings)
	atmo.Parent = Lighting

	local cc = fresh("ColorCorrectionEffect", "DeadCalmColor")
	setAll(cc, L.colorCorrection, warnings)
	cc.Parent = Lighting

	local bloom = fresh("BloomEffect", "DeadCalmBloom")
	setAll(bloom, L.bloom, warnings)
	bloom.Parent = Lighting

	local sky = fresh("Sky", "DeadCalmSky")
	setAll(sky, L.sky, warnings)
	sky.Parent = Lighting

	return warnings
end

return LightingController
