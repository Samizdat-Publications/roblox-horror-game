--!strict
-- Rule 6, the Lake Wakes (night 5), on screen (DESIGN.md; Core entities/Finale):
--   EntityCue (the bell, 4 AM): the dock bell rings by itself (bell-dock-solo at the dock,
--     three strokes, a bell swinging on a post at the dock end, and a line of text for
--     players with the sound off); every water sound stops (the Ambience sound group fades
--     out, lake-silence-drop, then finale-bed); the lantern is locked on: a dark band clamps
--     the lantern and the flame inside it shrinks and reddens as the oil runs down (the HUD
--     shows "Oil (locked)").
--   EntityMoved (data.hazard, form, pos, appear, gone): Neighbor boats (a dark rowboat with
--     its own lantern and a figure waving a little too slowly, drifting toward your light)
--     and false beacons (a steady light on a pole that never blinks), each drawn where Core
--     says and smoothed between updates, gone when Core says. The drowned see them outlined.
--   EntityStrike: the lake takes someone and the finale goes on: a hard shake and a groan
--     (the death card and the drowned view come from PlayerDied as always).
--   EntityPass (home with the Steeple Cat): dawn. The view warms toward the dawn color,
--     dawn-cue plays, the hazards fade, the water sounds come back.
--   EntityFail: the hazards fade and the sound comes back (the night's end card follows).
-- Sounds only through AudioDirector's public functions; the Ambience fade is a SoundGroup
-- volume, restored on pass, fail and reset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local ViewState = require(client:WaitForChild("ViewState"))
local Common = require(script.Parent:WaitForChild("Common"))

local Finale = {}

Finale.WAVE_PERIOD = 3.6 -- the Neighbor's wave: a little too slow
Finale.FOLLOW = 1.6 -- how quickly a drawn hazard closes on its reported position
Finale.AMBIENCE_GROUP = "DeadCalmAmbience"
Finale.DAWN_SECONDS = 6

type Hazard = {
	form: string,
	model: Model,
	parts: { { part: BasePart, offset: CFrame } },
	figure: Common.Figure?,
	target: Vector3,
	drawn: Vector3,
	phase: number,
}

local hazards: { [number]: Hazard } = {}
local active = false
local clock = 0
local conn: RBXScriptConnection? = nil
local bed: Sound? = nil
local ambienceWas: number? = nil
local lock: { BasePart } = {}
local flame: BasePart? = nil
local bell: { post: BasePart, bell: BasePart, swing: number }? = nil
local caption: TextLabel? = nil
local dawnFx: ColorCorrectionEffect? = nil

local function ambienceGroup(): SoundGroup?
	local g = SoundService:FindFirstChild(Finale.AMBIENCE_GROUP)
	if g and g:IsA("SoundGroup") then
		return g
	end
	return nil
end

local function fadeAmbience(to: number?, seconds: number)
	local g = ambienceGroup()
	if g == nil then
		return
	end
	if to == nil then
		-- Back to what it was.
		local was = ambienceWas
		ambienceWas = nil
		if was == nil then
			return
		end
		TweenService:Create(g, TweenInfo.new(seconds), { Volume = was }):Play()
		return
	end
	if ambienceWas == nil then
		ambienceWas = g.Volume
	end
	TweenService:Create(g, TweenInfo.new(seconds), { Volume = to }):Play()
end

local function dockPoint(): Vector3
	local d = BoatClient.find("Dock", "DockEnd")
	if d then
		return d.Position
	end
	local e = Config.Lake.dockEnd
	return Vector3.new(e.x, Config.Lake.waterY + 2, e.z)
end

local function showCaption(text: string, seconds: number)
	local c = caption
	if c == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "DeadCalmFinaleCaption"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 9
		gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		local t = Instance.new("TextLabel")
		t.Name = "Caption"
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.fromScale(0.5, 0.16)
		t.Size = UDim2.new(0.8, 0, 0, 34)
		t.BackgroundTransparency = 1
		t.FontFace = Font.fromEnum(Enum.Font.PermanentMarker)
		t.TextSize = 26
		t.TextColor3 = Look.Palette.paper
		t.TextStrokeTransparency = 0.3
		t.TextWrapped = true
		t.Parent = gui
		caption = t
		c = t
	end
	local label = c :: TextLabel
	label.Text = text
	label.TextTransparency = 0
	label.Visible = true
	local my = text
	task.delay(seconds, function()
		if label.Text == my then
			TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
		end
	end)
end

----------------------------------------------------------------------------------------
-- The bell

local function ringBell()
	local at = dockPoint()
	if bell == nil then
		local post = Common.part(
			"FinaleBellPost",
			Vector3.new(0.4, 7, 0.4),
			CFrame.new(at + Vector3.new(-3, 3.5, 0)),
			Look.Palette.dockPost
		)
		local b = Common.part(
			"FinaleBell",
			Vector3.new(1.4, 1.6, 1.4),
			CFrame.new(at + Vector3.new(-3, 6, 0)),
			Look.Palette.bell,
			Enum.Material.Metal
		)
		bell = { post = post, bell = b, swing = 0 }
	end
	for i = 0, 2 do
		task.delay(i * 1.6, function()
			if not active then
				return
			end
			AudioDirector.play("bell-dock-solo", at)
			local bl = bell
			if bl then
				bl.swing = 1
			end
		end)
	end
	showCaption("The dock bell is ringing by itself.", 5)
end

----------------------------------------------------------------------------------------
-- The locked lantern

local function buildLock()
	local glow = BoatClient.part("LanternGlow")
	if glow == nil then
		return
	end
	local dark = Look.Palette.silhouette:Lerp(Look.Palette.buoyCage, 0.5)
	for i, y in { -0.25, 0.25 } do
		local band =
			Common.part("FinaleLock" .. i, Vector3.new(0.12, 0.95, 0.95), glow.CFrame, dark, Enum.Material.Metal, {
				shape = Enum.PartType.Cylinder,
			})
		band:SetAttribute("Y", y)
		table.insert(lock, band)
	end
	flame = Common.part(
		"FinaleFlame",
		Vector3.new(0.4, 0.4, 0.4),
		glow.CFrame,
		Look.Palette.lantern,
		Enum.Material.Neon,
		{ shape = Enum.PartType.Ball }
	)
end

local function stepLock()
	local glow = BoatClient.part("LanternGlow")
	if glow == nil then
		return
	end
	for _, band in lock do
		local y = (band:GetAttribute("Y") :: number?) or 0
		-- A cylinder's axis is its X: stand it up so it rings the lantern.
		band.CFrame = glow.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2)
	end
	local f = flame
	if f then
		local oil = math.clamp(tonumber(ViewState.get().oil) or 0, 0, 1)
		local s = 0.12 + 0.5 * oil
		local flick = 1 + 0.08 * math.sin(clock * 23) + 0.05 * math.sin(clock * 37)
		f.Size = Vector3.new(s, s * 1.4, s) * flick
		f.CFrame = glow.CFrame
		f.Color = Look.Palette.lantern:Lerp(Color3.fromRGB(190, 60, 30), 1 - oil)
		f.Transparency = if oil <= 0 then 1 else 0.05
	end
end

----------------------------------------------------------------------------------------
-- Hazards: Neighbor boats and false beacons

local function facing(pos: Vector3): CFrame
	local hull = BoatClient.hull()
	local look = if hull then hull.Position else pos + Vector3.new(0, 0, 1)
	local flat = Vector3.new(look.X, pos.Y, look.Z)
	if (flat - pos).Magnitude < 0.1 then
		flat = pos + Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(pos, flat)
end

local function buildBoat(pos: Vector3): Hazard
	local m = Instance.new("Model")
	m.Name = "FinaleNeighbor"
	m.Parent = Common.folder()
	local dark = Look.Palette.silhouette:Lerp(Look.Palette.boatTrim, 0.35)
	local parts = {}
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material?): BasePart
		local p = Common.part(name, size, CFrame.new(pos) * offset, color, mat, { parent = m })
		table.insert(parts, { part = p, offset = offset })
		return p
	end
	piece("Hull", Vector3.new(4.2, 0.5, 11), CFrame.new(0, 0.1, 0), dark, Enum.Material.WoodPlanks)
	piece("SideL", Vector3.new(0.35, 1.4, 11), CFrame.new(-2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("SideR", Vector3.new(0.35, 1.4, 11), CFrame.new(2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("Stern", Vector3.new(4.6, 1.4, 0.35), CFrame.new(0, 0.75, 5.5), dark, Enum.Material.WoodPlanks)
	piece("Post", Vector3.new(0.25, 4, 0.25), CFrame.new(0, 2.4, -6.3), dark)
	local glow = piece(
		"Lantern",
		Vector3.new(0.75, 0.75, 0.75),
		CFrame.new(0, 4.3, -6.8),
		Look.Palette.lantern:Lerp(Color3.fromRGB(255, 230, 190), 0.3),
		Enum.Material.Neon
	)
	glow.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Look.Palette.lantern
	light.Range = 30
	light.Brightness = 2
	light.Shadows = false
	light.Parent = glow
	local fig = Common.figure("Rower", { height = 6.4, width = 1.7, seated = true })
	fig.model.Parent = m
	Common.outline(m)
	return { form = "Boat", model = m, parts = parts, figure = fig, target = pos, drawn = pos, phase = clock }
end

local function buildBeacon(pos: Vector3): Hazard
	local m = Instance.new("Model")
	m.Name = "FinaleFalseBeacon"
	m.Parent = Common.folder()
	local parts = {}
	local pole = Common.part(
		"Pole",
		Vector3.new(0.5, 14, 0.5),
		CFrame.new(pos + Vector3.new(0, 7, 0)),
		Look.Palette.silhouette,
		nil,
		{ parent = m }
	)
	table.insert(parts, { part = pole, offset = CFrame.new(0, 7, 0) })
	local lamp = Common.part(
		"Lamp",
		Vector3.new(2.5, 3, 2.5),
		CFrame.new(pos + Vector3.new(0, 15, 0)),
		Look.Beacon.Color,
		Enum.Material.Neon,
		{ parent = m }
	)
	table.insert(parts, { part = lamp, offset = CFrame.new(0, 15, 0) })
	local light = Instance.new("PointLight")
	light.Color = Look.Beacon.Color
	light.Range = Look.Beacon.Range
	light.Brightness = Look.Beacon.Brightness
	light.Shadows = false
	light.Parent = lamp
	Common.outline(m)
	return { form = "FalseBeacon", model = m, parts = parts, figure = nil, target = pos, drawn = pos, phase = clock }
end

local function dropHazard(id: number, fade: number)
	local h = hazards[id]
	hazards[id] = nil
	if h then
		if fade > 0 then
			Common.fadeOut(h.model, fade)
		else
			h.model:Destroy()
		end
	end
end

local function clearHazards(fade: number)
	for id in hazards do
		dropHazard(id, fade)
	end
end

local function stepHazards(dt: number)
	for _, h in hazards do
		local k = math.clamp(dt * Finale.FOLLOW, 0, 1)
		h.drawn = h.drawn:Lerp(h.target, k)
		local bob = math.sin(clock * 1.1 + h.phase) * 0.15
		local root = if h.form == "Boat" then facing(h.drawn) * CFrame.new(0, bob, 0) else CFrame.new(h.drawn)
		for _, item in h.parts do
			item.part.CFrame = root * item.offset
		end
		local fig = h.figure
		if fig then
			local wave = math.sin((clock + h.phase) * 2 * math.pi / Finale.WAVE_PERIOD) * 0.35
			Common.placeFigure(fig, root * CFrame.new(0, 0.4, 0.5), math.rad(150), wave)
		end
	end
end

----------------------------------------------------------------------------------------

local function step(dt: number)
	clock += dt
	if active then
		stepLock()
	end
	stepHazards(dt)
	local bl = bell
	if bl then
		bl.swing = math.max(0, bl.swing - dt * 0.7)
		local base = bl.post.CFrame * CFrame.new(0, 3.5, 0)
		local a = math.sin(clock * 6) * 0.5 * bl.swing
		bl.bell.CFrame = base * CFrame.Angles(a, 0, 0) * CFrame.new(0, -1.2, 0)
	end
end

local function ensureLoop()
	if conn == nil then
		conn = RunService.Heartbeat:Connect(step)
	end
end

local function clearLock()
	for _, p in lock do
		p:Destroy()
	end
	lock = {}
	local f = flame
	flame = nil
	if f then
		f:Destroy()
	end
end

local function stopBed()
	local b = bed
	bed = nil
	if b then
		local v0 = b.Volume
		task.spawn(function()
			local t0 = os.clock()
			while b.Parent and os.clock() - t0 < 2 do
				b.Volume = v0 * (1 - (os.clock() - t0) / 2)
				task.wait()
			end
			b:Destroy()
		end)
	end
end

local function dawn()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local cc = dawnFx
	if cc == nil or cc.Parent == nil then
		local n = Instance.new("ColorCorrectionEffect")
		n.Name = "DeadCalmDawn"
		n.TintColor = Color3.new(1, 1, 1)
		n.Parent = cam
		dawnFx = n
		cc = n
	end
	local info = TweenInfo.new(Finale.DAWN_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(cc :: ColorCorrectionEffect, info, {
		TintColor = Color3.new(1, 1, 1):Lerp(Look.Palette.dawn, 0.55),
		Brightness = 0.12,
		Contrast = 0.05,
	}):Play()
	AudioDirector.play("dawn-cue")
	showCaption("Dawn. You made it home with the owner's fish.", 6)
end

local function endFinale(fade: number)
	active = false
	clearLock()
	clearHazards(fade)
	stopBed()
	fadeAmbience(nil, 3)
end

function Finale.handle(e: any)
	local kind = e.kind
	local data = if type(e.data) == "table" then e.data else {}
	ensureLoop()
	if kind == "EntityCue" then
		active = true
		ringBell()
		fadeAmbience(0, 1.2)
		AudioDirector.play("lake-silence-drop")
		task.delay(2.5, function()
			if active and bed == nil then
				bed = AudioDirector.loop("finale-bed", nil)
			end
		end)
		clearLock()
		buildLock()
	elseif kind == "EntityMoved" then
		local id = tonumber(data.hazard)
		if id == nil then
			return
		end
		if data.gone then
			dropHazard(id, 1.5)
			return
		end
		if type(data.pos) ~= "table" then
			return
		end
		local pos = Common.water(data.pos, 0)
		local h = hazards[id]
		if h == nil then
			h = if data.form == "FalseBeacon" then buildBeacon(pos) else buildBoat(pos)
			hazards[id] = h
		else
			h.target = pos
		end
	elseif kind == "EntityStrike" then
		BoatFx.shake(1.0, 1.2)
		AudioDirector.play("lake-groan")
	elseif kind == "EntityPass" then
		endFinale(2.5)
		if data.home == true then
			dawn()
		end
	elseif kind == "EntityFail" then
		endFinale(2)
	end
end

function Finale.reset()
	endFinale(0)
	local cc = dawnFx
	dawnFx = nil
	if cc then
		cc:Destroy()
	end
	local bl = bell
	bell = nil
	if bl then
		bl.post:Destroy()
		bl.bell:Destroy()
	end
	local c = caption
	if c then
		c.Visible = false
	end
end

-- For checks: what the finale shows right now.
function Finale.debugState(): { [string]: any }
	local boats, beacons = 0, 0
	for _, h in hazards do
		if h.form == "Boat" then
			boats += 1
		else
			beacons += 1
		end
	end
	local g = ambienceGroup()
	return {
		active = active,
		boats = boats,
		beacons = beacons,
		locked = #lock > 0,
		ambience = if g then g.Volume else nil,
		dawn = dawnFx ~= nil,
	}
end

return Finale
