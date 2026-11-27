--!strict
-- Rule 6, the Lake Wakes (night 5), on screen (DESIGN.md; Core entities/Finale).
-- Rebuilt in Polish 3 from Neon's finale review (docs/critic/11-26-2026-finale-neon.md, 1.5/10):
--
--   The turn (EntityCue at 4 AM): the night card is already gone (NightCards hides it on this
--     cue) and the tape is cut (AudioDirector cuts tapes on any cue). Every water and ambient
--     sound drops to dead silence (AudioDirector.muteAmbience, and AudioDirector.hush for the
--     motor, the lantern and the music) for Look.Finale.silence seconds; then the dock bell
--     tolls three slow times, non-spatial so it is heard at full strength anywhere on the
--     lake (finale-bell), one Sound per toll, each cut as the next starts; a bell swings on a
--     post at the dock end, and a large line says "The bell. Go home." The hush holds until
--     Look.Finale.afterBell after the last toll; only then do the motor and the chase return.
--   Finale v2 (Neon 2/10, docs/critic/11-26-2026-finale-v2-neon.md): the beacon's shaft and a
--     fog-proof column billboard go up at the cue itself, so home shows from the bell on.
--   The run: the locked lantern throws a warm cone over the bow and the water (a SpotLight
--     in an Attachment on LanternGlow, shadows on), and pale flecks on the water slide past
--     in it so the speed reads. The real dock beacon has a tall pulsing shaft, a column drawn
--     over the fog and a halo sized in studs, all blinking twice with the beacon. Neighbor
--     boats (swaying lanterns, a
--     slow-waving figure, the creak of oars) and false beacons (a flickering light on a pole
--     with a thin whine) are drawn from Core's EntityMoved hazards, pulled closer than Core
--     holds them so they read through the fog (the gap beyond the kill distance is scaled by
--     Look.Finale.pull, so a strike still lands where it looks like it should). A toll
--     through water marks each one appearing.
--   The chase: a pursuit layer under the motor (finale-chase-drone, finale-chase-under) whose
--     pulse quickens as the boat slows; the screen edges close in as the boat sits still
--     toward the stop limit.
--   Strike (EntityStrike): a hard shake and the lake's groan; the finale goes on.
--   Dawn (EntityPass, data.home): the Lighting warms from night to a sunrise over
--     Look.Dawn.seconds (Look.Dawn), the fog lifts and warms, the water comes back with the
--     dawn cue and birds, and a bold paper banner says "Dawn. You made it home."
--   EntityFail: the hazards fade and the water sounds come back (the night's end card follows).
-- This module never writes a SoundGroup: sound goes through AudioDirector only.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local WorldFx = require(client:WaitForChild("WorldFx"))
local Common = require(script.Parent:WaitForChild("Common"))
local Paper = require(client:WaitForChild("ui"):WaitForChild("Paper"))

local Finale = {}

Finale.WAVE_PERIOD = 3.6 -- the Neighbor's wave: a little too slow
Finale.FOLLOW = 4 -- how quickly a drawn hazard closes on where it should be drawn
Finale.KEY = "Finale" -- AudioDirector mute and hush key
Finale.CAPTION = "The bell. Go home."
Finale.BANNER = "Dawn. You made it home."
Finale.WAKE = { count = 34, every = 0.06, life = 1.3, ahead = { 7, 38 }, minSpeed = 3 }
Finale.CAPTION_COLOR = Color3.fromRGB(255, 238, 228)

type Hazard = {
	form: string,
	model: Model,
	parts: { { part: BasePart, offset: CFrame } },
	figure: Common.Figure?,
	lamp: BasePart?,
	light: PointLight?,
	lanternPost: CFrame?, -- the Neighbor boat's lantern hangs from here (it sways)
	sound: Sound?,
	target: Vector3, -- where Core holds it
	drawn: Vector3, -- where it is drawn (pulled closer, smoothed)
	phase: number,
}

local hazards: { [number]: Hazard } = {}
local active = false
local phase = "Off" -- "Off" | "Silence" | "Bell" | "Run" | "Dawn"
local clock = 0
local conn: RBXScriptConnection? = nil
local cueToken = 0
local stopLimit = Config.Rules.Finale.stopLimit

-- The locked lantern and its cone.
local lock: { BasePart } = {}
local flame: BasePart? = nil
local coneAim: Attachment? = nil
local coneLight: SpotLight? = nil

-- The bell on its post.
local bell: { post: BasePart, bell: BasePart, swing: number }? = nil

-- The real beacon's shaft and halo.
local shaft: BasePart? = nil
local halo: BillboardGui? = nil
local column: BillboardGui? = nil -- drawn over the fog: home from anywhere

-- The chase.
local drone: Sound? = nil
local under: Sound? = nil
local speed = 0
local lastHullPos: Vector3? = nil
local stillFor = 0
local fear = 0 -- 0..1, smoothed

-- Wake flecks.
local wake: { { part: BasePart, born: number } } = {}
local wakeT = 0

-- Screen.
local gui: ScreenGui? = nil
local caption: TextLabel? = nil
local banner: Frame? = nil
local bannerText: TextLabel? = nil
local vignetteRoot: Frame? = nil
local vignette: { Frame } = {}
local vignetteLevel = 0

-- Dawn: the Lighting as it was, to put back.
local saved: { [string]: any }? = nil

----------------------------------------------------------------------------------------
-- Screen: the caption, the dawn banner, the vignette

local function screen(): ScreenGui
	local g = gui
	if g and g.Parent then
		return g
	end
	local n = Instance.new("ScreenGui")
	n.Name = "DeadCalmFinale"
	n.ResetOnSpawn = false
	n.IgnoreGuiInset = true
	n.DisplayOrder = 9
	n.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = n

	-- The vignette: four edge bands fading toward the middle (no image asset).
	local root = Instance.new("Frame")
	root.Name = "Vignette"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = n
	vignetteRoot = root
	vignette = {}
	local bands = {
		{ UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), -90 },
		{ UDim2.fromScale(0.4, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.4, 1), UDim2.fromScale(0.6, 0), 180 },
	}
	for i, b in bands do
		local f = Instance.new("Frame")
		f.Name = "Band" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.Size = b[1]
		f.Position = b[2]
		f.Parent = root
		local grad = Instance.new("UIGradient")
		grad.Rotation = b[3]
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.65),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = f
		table.insert(vignette, f)
	end

	-- The bell's line: large, pale, a dark stroke, readable on any sky.
	local size = Paper.fit(60, 34, 80)
	local c = Instance.new("TextLabel")
	c.Name = "Caption"
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.3)
	c.Size = UDim2.new(0.9, 0, 0, size + 16)
	c.BackgroundTransparency = 1
	c.FontFace = Paper.hand()
	c.TextSize = size
	c.TextColor3 = Finale.CAPTION_COLOR
	c.TextWrapped = true
	c.Text = ""
	c.Visible = false
	c.Parent = n
	local stroke = Instance.new("UIStroke")
	stroke.Color = Look.Palette.silhouette
	stroke.Thickness = math.max(3, math.floor(size / 14))
	stroke.Parent = c
	local scale = Instance.new("UIScale")
	scale.Parent = c
	caption = c

	-- The dawn banner: a bold sheet of paper near the top.
	local bh = Paper.fit(52, 30, 68)
	local b =
		Paper.sheet(n, "Banner", UDim2.new(0.7, 0, 0, bh + 30), UDim2.fromScale(0.5, 0.16), Vector2.new(0.5, 0.5), 12)
	b.BackgroundTransparency = 0.02
	b.Rotation = -1.5
	b.Visible = false
	local bLimit = Instance.new("UISizeConstraint")
	bLimit.MaxSize = Vector2.new(760, 200)
	bLimit.Parent = b
	local edge = Instance.new("UIStroke")
	edge.Color = Look.UI.ink
	edge.Thickness = 3
	edge.Parent = b
	local bt = Paper.text(b, "Text", Finale.BANNER, bh, Paper.hand())
	bt.Size = UDim2.fromScale(1, 1)
	bt.TextXAlignment = Enum.TextXAlignment.Center
	bt.TextYAlignment = Enum.TextYAlignment.Center
	banner = b
	bannerText = bt
	return n
end

local function showCaption(text: string, hold: number)
	screen()
	local c = caption
	if c == nil then
		return
	end
	c.Text = text
	c.TextTransparency = 0
	local st = c:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	c.Visible = true
	local sc = c:FindFirstChildOfClass("UIScale")
	if sc then
		-- A short punch in, so it lands with the bell.
		sc.Scale = 1.25
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	local my = text
	task.delay(hold, function()
		if c.Text == my and c.Visible then
			local info = TweenInfo.new(1.2)
			TweenService:Create(c, info, { TextTransparency = 1 }):Play()
			if st then
				TweenService:Create(st, info, { Transparency = 1 }):Play()
			end
		end
	end)
end

local function hideCaption()
	local c = caption
	if c then
		c.Visible = false
		c.Text = ""
	end
end

local function showBanner()
	screen()
	local b, t = banner, bannerText
	if b == nil or t == nil then
		return
	end
	b.BackgroundTransparency = 0.02
	t.TextTransparency = 0
	local st = b:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0
	end
	b.Visible = true
	task.delay(5.5, function()
		if b.Visible then
			local info = TweenInfo.new(1.5)
			TweenService:Create(b, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(t, info, { TextTransparency = 1 }):Play()
			if st then
				TweenService:Create(st, info, { Transparency = 1 }):Play()
			end
		end
	end)
end

local function hideBanner()
	local b = banner
	if b then
		b.Visible = false
	end
end

local function setVignette(level: number)
	vignetteLevel = level
	local root = vignetteRoot
	if root == nil then
		return
	end
	root.Visible = level > 0.01
	for _, f in vignette do
		f.BackgroundTransparency = 1 - math.clamp(level, 0, 1) * 0.95
	end
end

----------------------------------------------------------------------------------------
-- Places

local function dockPoint(): Vector3
	local d = BoatClient.find("Dock", "DockEnd")
	if d then
		return d.Position
	end
	local e = Config.Lake.dockEnd
	return Vector3.new(e.x, Config.Lake.waterY + 2, e.z)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

----------------------------------------------------------------------------------------
-- The bell

-- The toll now ringing (at most one at a time) and how many have rung this finale.
local toll: Sound? = nil
local tolls = 0

local function cutToll(seconds: number)
	local s = toll
	toll = nil
	if s == nil or s.Parent == nil then
		return
	end
	if seconds <= 0 then
		s:Destroy()
		return
	end
	local tw = TweenService:Create(s, TweenInfo.new(seconds), { Volume = 0 })
	tw.Completed:Once(function()
		s:Destroy()
	end)
	tw:Play()
end

local function ringBell()
	local at = dockPoint()
	if bell == nil then
		local post = Common.part(
			"FinaleBellPost",
			Vector3.new(0.5, 9, 0.5),
			CFrame.new(at + Vector3.new(-3, 4.5, 0)),
			Look.Palette.dockPost
		)
		local b = Common.part(
			"FinaleBell",
			Vector3.new(2, 2.2, 2),
			CFrame.new(at + Vector3.new(-3, 7.5, 0)),
			Look.Palette.bell,
			Enum.Material.Metal
		)
		bell = { post = post, bell = b, swing = 0 }
	end
	local F = Look.Finale
	local my = cueToken
	for i = 0, F.bellStrokes - 1 do
		task.delay(i * F.bellGap, function()
			if not active or cueToken ~= my then
				return
			end
			-- One Sound per toll: the last one's echo is cut as the next one starts.
			cutToll(F.bellCut)
			-- finale-bell is non-spatial (SoundRegistry): heard at full strength anywhere.
			toll = AudioDirector.play("finale-bell", nil, { volume = F.bellVolume })
			tolls += 1
			local bl = bell
			if bl then
				bl.swing = 1
			end
		end)
	end
end

local function stepBell(dt: number)
	local bl = bell
	if bl == nil then
		return
	end
	bl.swing = math.max(0, bl.swing - dt * 0.6)
	local base = bl.post.CFrame * CFrame.new(0, 4.5, 0)
	local a = math.sin(clock * 5) * 0.6 * bl.swing
	bl.bell.CFrame = base * CFrame.Angles(a, 0, 0) * CFrame.new(0, -1.3, 0)
end

----------------------------------------------------------------------------------------
-- The locked lantern and its cone

-- Finale v2: the cone lives ON the lantern (an Attachment in LanternGlow, welded to the
-- hull, so it never lags a frame). The lantern's local -Z is the bow (BoatHull); the
-- attachment pitches `tilt` degrees down and the SpotLight shines from its Front face.
-- The old invisible FinaleCone part is gone: it drew nothing (no visible beam).
local function makeCone(glow: BasePart)
	local old = coneAim
	if old then
		old:Destroy()
	end
	local C = Look.Finale.cone
	local att = Instance.new("Attachment")
	att.Name = "FinaleConeAim"
	att.CFrame = CFrame.new(0, 0, -0.5) * CFrame.Angles(-math.rad(C.tilt), 0, 0)
	att.Parent = glow
	local spot = Instance.new("SpotLight")
	spot.Name = "FinaleCone"
	spot.Face = Enum.NormalId.Front
	spot.Angle = C.angle
	spot.Range = C.range
	spot.Brightness = C.brightness
	spot.Color = C.color
	spot.Shadows = C.shadows
	spot.Parent = att
	coneAim, coneLight = att, spot
end

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
	makeCone(glow)
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
	local oil = math.clamp(tonumber(ViewState.get().oil) or 0, 0, 1)
	local lit = ViewState.get().lanternOn == true and oil > 0
	local f = flame
	if f then
		local s = 0.12 + 0.5 * oil
		local flick = 1 + 0.08 * math.sin(clock * 23) + 0.05 * math.sin(clock * 37)
		f.Size = Vector3.new(s, s * 1.4, s) * flick
		f.CFrame = glow.CFrame
		f.Color = Look.Palette.lantern:Lerp(Color3.fromRGB(190, 60, 30), 1 - oil)
		f.Transparency = if lit then 0.05 else 1
	end
	if coneAim and coneAim.Parent ~= glow then
		makeCone(glow) -- the boat was rebuilt: a new cone on the new lantern
	end
	local spot = coneLight
	if spot then
		local C = Look.Finale.cone
		local gutter = if oil < 0.15 then 0.6 + 0.4 * math.abs(math.sin(clock * 17)) else 1
		spot.Brightness = C.brightness * (0.35 + 0.65 * oil) * gutter
		spot.Enabled = lit
	end
end

local function clearLock()
	for _, p in lock do
		p:Destroy()
	end
	lock = {}
	for _, inst in { flame, coneAim } do
		if inst then
			inst:Destroy()
		end
	end
	flame, coneAim, coneLight = nil, nil, nil
end

----------------------------------------------------------------------------------------
-- Wake flecks: pale bits on the water in the cone that the boat passes, so speed reads.

local function stepWake(dt: number, alive: boolean)
	local hull = BoatClient.hull()
	local W = Finale.WAKE
	local keep = {}
	for _, w in wake do
		local age = clock - w.born
		if age >= W.life or w.part.Parent == nil then
			w.part:Destroy()
		else
			w.part.Transparency = 0.35 + 0.65 * (age / W.life)
			table.insert(keep, w)
		end
	end
	wake = keep
	if hull == nil or not alive or speed < W.minSpeed or ViewState.get().lanternOn ~= true then
		return
	end
	wakeT -= dt
	if wakeT > 0 or #wake >= W.count then
		return
	end
	wakeT = W.every
	local look = flat(hull.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, 1)
	local right = look:Cross(Vector3.new(0, 1, 0))
	local d = W.ahead[1] + math.random() * (W.ahead[2] - W.ahead[1])
	local side = (math.random() * 2 - 1) * (2 + d * 0.35)
	local pos = flat(hull.Position) + look * d + right * side + Vector3.new(0, Config.Lake.waterY + 0.07, 0)
	local p = Common.part(
		"FinaleWake",
		Vector3.new(0.25, 0.05, 0.9 + math.random() * 1.2),
		CFrame.lookAt(pos, pos + look),
		Color3.fromRGB(214, 204, 182),
		Enum.Material.SmoothPlastic,
		{ transparency = 0.35 }
	)
	table.insert(wake, { part = p, born = clock })
end

local function clearWake()
	for _, w in wake do
		w.part:Destroy()
	end
	wake = {}
end

----------------------------------------------------------------------------------------
-- The real dock beacon: a tall steady shaft and a halo that grows as you come in.

local function buildShaft()
	local lamp = BoatClient.find("Dock", "BeaconLamp")
	if lamp == nil or shaft ~= nil then
		return
	end
	local S, H, K = Look.Finale.beaconShaft, Look.Finale.beaconHalo, Look.Finale.beaconColumn
	local p = Common.part(
		"FinaleBeaconShaft",
		Vector3.new(S.height, S.width, S.width),
		CFrame.new(lamp.Position + Vector3.new(0, S.height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Look.Beacon.Color,
		Enum.Material.Neon,
		{ shape = Enum.PartType.Cylinder, transparency = S.transparency }
	)
	shaft = p
	local bb = Instance.new("BillboardGui")
	bb.Name = "FinaleBeaconHalo"
	bb.Adornee = lamp
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 2000
	bb.Size = UDim2.new(H.studs, H.minPixels, H.studs, H.minPixels)
	bb.Parent = p
	for i, k in { 1, 0.62, 0.32 } do
		local f = Instance.new("Frame")
		f.Name = "Ring" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(k, k)
		f.BackgroundColor3 = Look.Beacon.Color:Lerp(Color3.new(1, 1, 1), 0.25 * i)
		f.BackgroundTransparency = 0.85 - 0.25 * i
		f.BorderSizePixel = 0
		f.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	halo = bb
	-- The column: a tall thin billboard over the lamp, drawn on top so the fog never hides
	-- it. Brightest at the lamp, fading out toward the top, like a beam into the fog.
	local cb = Instance.new("BillboardGui")
	cb.Name = "FinaleBeaconColumn"
	cb.Adornee = lamp
	cb.AlwaysOnTop = true
	cb.LightInfluence = 0
	cb.MaxDistance = 3000
	cb.Size = UDim2.new(K.width, K.minPixels, K.studs, 0)
	cb.StudsOffsetWorldSpace = Vector3.new(0, K.studs / 2, 0)
	cb.Parent = p
	local beam = Instance.new("Frame")
	beam.Name = "Beam"
	beam.Size = UDim2.fromScale(1, 1)
	beam.BorderSizePixel = 0
	beam.BackgroundColor3 = Look.Beacon.Color:Lerp(Color3.new(1, 1, 1), 0.2)
	beam.BackgroundTransparency = 0
	beam.Parent = cb
	local grad = Instance.new("UIGradient")
	grad.Rotation = -90 -- keypoint 0 at the bottom (the lamp)
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = beam
	column = cb
end

local function stepShaft()
	local p, bb = shaft, halo
	if p == nil then
		return
	end
	local dark = WorldFx.beaconDark(Workspace:GetServerTimeNow())
	local S, K = Look.Finale.beaconShaft, Look.Finale.beaconColumn
	-- A slow breath on top of the beacon's double blink.
	local breath = 0.5 + 0.5 * math.sin(clock * 2 * math.pi * K.pulseHz)
	p.Transparency = if dark then 0.92 else S.transparency + 0.15 * (1 - breath)
	if bb then
		bb.Enabled = not dark
	end
	local cb = column
	if cb then
		local beam = cb:FindFirstChild("Beam")
		local cam = Workspace.CurrentCamera
		local near = 1
		if cam then
			local d = (flat(cam.CFrame.Position) - flat(p.Position)).Magnitude
			near = math.clamp((d - K.hideWithin) / 60, 0, 1)
		end
		local a = (1 - K.alpha) * (0.7 + 0.3 * breath) * near -- opacity at the lamp
		cb.Enabled = not dark and a > 0.01
		if beam and beam:IsA("Frame") then
			beam.BackgroundTransparency = 1 - a
		end
	end
end

local function clearShaft(fade: number)
	local p = shaft
	if column then
		column.Enabled = false -- a billboard does not fade with its part
	end
	shaft, halo, column = nil, nil, nil
	if p then
		if fade > 0 then
			Common.fadeOut(p, fade)
		else
			p:Destroy()
		end
	end
end

----------------------------------------------------------------------------------------
-- Hazards: Neighbor boats and false beacons

local function facing(pos: Vector3): CFrame
	local hull = BoatClient.hull()
	local look = if hull then hull.Position else pos + Vector3.new(0, 0, 1)
	local f = Vector3.new(look.X, pos.Y, look.Z)
	if (f - pos).Magnitude < 0.1 then
		f = pos + Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(pos, f)
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
	local hullPart = piece("Hull", Vector3.new(4.2, 0.5, 11), CFrame.new(0, 0.1, 0), dark, Enum.Material.WoodPlanks)
	piece("SideL", Vector3.new(0.35, 1.4, 11), CFrame.new(-2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("SideR", Vector3.new(0.35, 1.4, 11), CFrame.new(2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("Stern", Vector3.new(4.6, 1.4, 0.35), CFrame.new(0, 0.75, 5.5), dark, Enum.Material.WoodPlanks)
	piece("Post", Vector3.new(0.25, 4.6, 0.25), CFrame.new(0, 2.6, -5.6), dark)
	-- The lantern hangs from the post's arm and sways (not in `parts`: stepped on its own).
	local glow = Common.part(
		"Lantern",
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(pos),
		Look.Palette.lantern:Lerp(Color3.fromRGB(255, 230, 190), 0.3),
		Enum.Material.Neon,
		{ parent = m, shape = Enum.PartType.Ball }
	)
	local light = Instance.new("PointLight")
	light.Color = Look.Palette.lantern
	light.Range = Look.Finale.hazardLightRange
	light.Brightness = Look.Finale.hazardLightBrightness
	light.Shadows = false
	light.Parent = glow
	local fig = Common.figure("Rower", { height = 6.4, width = 1.7, seated = true })
	fig.model.Parent = m
	Common.outline(m)
	local snd = AudioDirector.loop("neighbor-oarlock-loop", hullPart)
	return {
		form = "Boat",
		model = m,
		parts = parts,
		figure = fig,
		lamp = glow,
		light = light,
		lanternPost = CFrame.new(0, 4.9, -6.2),
		sound = snd,
		target = pos,
		drawn = pos,
		phase = math.random() * 10,
	}
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
	-- Never outlined: the drowned see an outline on the real beacon only (Drowned.luau).
	local snd = AudioDirector.loop("finale-hazard-whine", lamp)
	return {
		form = "FalseBeacon",
		model = m,
		parts = parts,
		figure = nil,
		lamp = lamp,
		light = light,
		lanternPost = nil,
		sound = snd,
		target = pos,
		drawn = pos,
		phase = math.random() * 10,
	}
end

local function dropHazard(id: number, fade: number)
	local h = hazards[id]
	hazards[id] = nil
	if h == nil then
		return
	end
	local s = h.sound
	if s then
		s:Destroy()
	end
	if fade > 0 then
		Common.fadeOut(h.model, fade)
	else
		h.model:Destroy()
	end
end

local function clearHazards(fade: number)
	for id in hazards do
		dropHazard(id, fade)
	end
end

-- Where a hazard is drawn: pulled toward the boat (only the gap beyond its kill distance).
function Finale.pulled(boat: Vector3, at: Vector3, form: string): Vector3
	local N = Config.Rules.Neighbor
	local kill = if form == "FalseBeacon" then N.falseBeaconKill else N.killDist
	local off = flat(at - boat)
	local d = off.Magnitude
	if d <= kill or d < 1e-3 then
		return at
	end
	local shown = kill + (d - kill) * Look.Finale.pull
	local p = flat(boat) + off.Unit * shown
	return Vector3.new(p.X, at.Y, p.Z)
end

local function stepHazards(dt: number)
	local hull = BoatClient.hull()
	for _, h in hazards do
		local want = if hull then Finale.pulled(hull.Position, h.target, h.form) else h.target
		h.drawn = h.drawn:Lerp(want, math.clamp(dt * Finale.FOLLOW, 0, 1))
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
		local lamp, light = h.lamp, h.light
		if h.form == "Boat" and lamp and h.lanternPost then
			-- A swaying lantern on a short hook.
			local sway = math.sin(clock * 1.7 + h.phase) * 0.35
			local sway2 = math.sin(clock * 1.2 + h.phase * 2) * 0.2
			lamp.CFrame = root * (h.lanternPost :: CFrame) * CFrame.Angles(sway, 0, sway2) * CFrame.new(0, -0.9, 0)
		elseif h.form == "FalseBeacon" and lamp and light then
			-- It flickers like a flame, never the beacon's clean double blink.
			local n = math.noise(clock * 6 + h.phase, h.phase)
			local out = math.noise(clock * 1.3, h.phase * 3) > 0.32
			local k = if out then 0.05 else math.clamp(0.75 + n, 0.35, 1.2)
			light.Brightness = Look.Beacon.Brightness * k
			lamp.Material = if k < 0.3 then Enum.Material.SmoothPlastic else Enum.Material.Neon
		end
	end
end

----------------------------------------------------------------------------------------
-- The chase: the pursuit layer and the closing edges

local function startChase()
	if drone == nil then
		drone = AudioDirector.loop("finale-chase-drone", nil)
	end
	if under == nil then
		under = AudioDirector.loop("finale-chase-under", nil)
	end
end

local function fadeAndDestroy(s: Sound?, seconds: number)
	if s == nil then
		return
	end
	if seconds <= 0 then
		s:Destroy()
		return
	end
	local v0 = s.Volume
	task.spawn(function()
		local t0 = os.clock()
		while s.Parent and os.clock() - t0 < seconds do
			s.Volume = v0 * (1 - (os.clock() - t0) / seconds)
			task.wait()
		end
		s:Destroy()
	end)
end

local function stopChase(seconds: number)
	fadeAndDestroy(drone, seconds)
	fadeAndDestroy(under, seconds)
	drone, under = nil, nil
end

local function stepChase(dt: number, alive: boolean)
	local hull = BoatClient.hull()
	if hull then
		local pos = flat(hull.Position)
		local last = lastHullPos
		if last and dt > 0 then
			local v = (pos - last).Magnitude / dt
			speed += (v - speed) * math.clamp(dt * 6, 0, 1)
		end
		lastHullPos = pos
	end
	local view = ViewState.get()
	local still = Config.Boat.stillSpeed
	if phase == "Run" and not view.safe and speed < still then
		stillFor += dt
	else
		stillFor = 0
	end
	-- Fear: slow is uneasy, sitting still toward the stop limit is worse.
	local slow = math.clamp((still * 3 - speed) / (still * 3), 0, 1)
	local want = 0
	if phase == "Run" and alive and not view.safe then
		want = math.max(slow * 0.45, math.clamp(stillFor / math.max(0.5, stopLimit), 0, 1))
	end
	local rate = if want > fear then 2.5 else 1.2
	fear += math.clamp(want - fear, -rate * dt, rate * dt)
	setVignette(fear * Look.Finale.vignetteMax)
	local d = drone
	if d then
		local trem = d:FindFirstChildWhichIsA("TremoloSoundEffect")
		if trem then
			local F = Look.Finale
			trem.Frequency = F.pulseCalm + (F.pulseScared - F.pulseCalm) * fear
		end
	end
end

----------------------------------------------------------------------------------------
-- Dawn

-- LightingController's Atmosphere and ColorCorrection (names from LightingController).
local function lightingTargets(): (Atmosphere?, ColorCorrectionEffect?)
	local atmo = Lighting:FindFirstChild("DeadCalmAtmosphere")
	local cc = Lighting:FindFirstChild("DeadCalmColor")
	return if atmo and atmo:IsA("Atmosphere") then atmo else nil,
		if cc and cc:IsA("ColorCorrectionEffect") then cc else nil
end

local LIGHT_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation" }
local ATMO_PROPS = { "Density", "Offset", "Haze", "Glare", "Color", "Decay" }
local CC_PROPS = { "Brightness", "Contrast", "Saturation", "TintColor" }

local function saveLighting()
	if saved ~= nil then
		return
	end
	local atmo, cc = lightingTargets()
	local s: { [string]: any } = { lighting = {}, atmo = {}, cc = {} }
	for _, k in LIGHT_PROPS do
		s.lighting[k] = (Lighting :: any)[k]
	end
	if atmo then
		for _, k in ATMO_PROPS do
			s.atmo[k] = (atmo :: any)[k]
		end
	end
	if cc then
		for _, k in CC_PROPS do
			s.cc[k] = (cc :: any)[k]
		end
	end
	saved = s
end

local function restoreLighting()
	local s = saved
	saved = nil
	WorldFx.ambientOverride = false
	if s == nil then
		return
	end
	local atmo, cc = lightingTargets()
	for k, v in s.lighting do
		(Lighting :: any)[k] = v
	end
	if atmo then
		for k, v in s.atmo do
			(atmo :: any)[k] = v
		end
	end
	if cc then
		for k, v in s.cc do
			(cc :: any)[k] = v
		end
	end
end

local function dawn()
	phase = "Dawn"
	local D = Look.Dawn
	saveLighting()
	WorldFx.ambientOverride = true
	local info = TweenInfo.new(D.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local atmo, cc = lightingTargets()
	local goal: { [string]: any } = {}
	for _, k in LIGHT_PROPS do
		goal[k] = (D :: any)[k]
	end
	TweenService:Create(Lighting, info, goal):Play()
	if atmo then
		TweenService:Create(atmo, info, D.atmosphere):Play()
	end
	if cc then
		TweenService:Create(cc, info, D.colorCorrection):Play()
	end
	-- The water and the morning come back.
	AudioDirector.muteAmbience(Finale.KEY, false, 2.5)
	AudioDirector.play("dawn-cue")
	task.delay(0.9, function()
		if phase == "Dawn" then
			AudioDirector.play("dawn-birds")
		end
	end)
	showBanner()
end

----------------------------------------------------------------------------------------

local function step(dt: number)
	clock += dt
	local me = ViewState.me()
	local alive = me == nil or me.alive ~= false
	if active then
		stepLock()
		stepShaft()
		stepWake(dt, alive)
	end
	stepChase(dt, alive)
	stepHazards(dt)
	stepBell(dt)
end

local function ensureLoop()
	if conn == nil then
		conn = RunService.Heartbeat:Connect(step)
	end
end

local function endFinale(fade: number)
	active = false
	cueToken += 1
	if phase ~= "Dawn" then
		phase = "Off"
	end
	clearLock()
	clearWake()
	clearHazards(fade)
	clearShaft(fade)
	stopChase(math.min(fade, 1.5))
	stillFor = 0
	fear = 0
	setVignette(0)
	cutToll(0.6)
	AudioDirector.hush(Finale.KEY, false)
end

local function onCue(data: { [string]: any })
	active = true
	phase = "Silence"
	stopLimit = tonumber(data.stopLimit) or Config.Rules.Finale.stopLimit
	cueToken += 1
	tolls = 0
	local my = cueToken
	screen()
	hideBanner()
	-- Dead silence: the water, the frogs, the motor, the lantern, the music.
	AudioDirector.muteAmbience(Finale.KEY, true, 0.08)
	AudioDirector.hush(Finale.KEY, true)
	clearLock()
	buildLock()
	-- Home shows from the moment of the bell: the beacon's shaft and column go up now.
	buildShaft()
	local F = Look.Finale
	task.delay(F.silence, function()
		if cueToken ~= my or not active then
			return
		end
		-- The tolls, still hushed: nothing but the bell until the last stroke has rung.
		phase = "Bell"
		ringBell()
		showCaption(Finale.CAPTION, F.captionHold)
		task.delay((F.bellStrokes - 1) * F.bellGap + F.afterBell, function()
			if cueToken ~= my or not active then
				return
			end
			phase = "Run"
			AudioDirector.hush(Finale.KEY, false)
			startChase()
		end)
	end)
end

function Finale.handle(e: any)
	local kind = e.kind
	local data = if type(e.data) == "table" then e.data else {}
	ensureLoop()
	if kind == "EntityCue" then
		onCue(data)
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
			local hull = BoatClient.hull()
			-- Drawn where it should be at once (no slide in from Core's far position).
			h.drawn = if hull then Finale.pulled(hull.Position, pos, h.form) else pos
			hazards[id] = h
			-- Never over the bell: the toll through water marks hazards once the run is on.
			if phase == "Run" then
				AudioDirector.play("finale-hazard-toll", h.drawn)
			end
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
		else
			AudioDirector.muteAmbience(Finale.KEY, false, 2)
		end
	elseif kind == "EntityFail" then
		endFinale(2)
		AudioDirector.muteAmbience(Finale.KEY, false, 2)
	end
end

function Finale.reset()
	endFinale(0)
	phase = "Off"
	AudioDirector.muteAmbience(Finale.KEY, false)
	restoreLighting()
	local bl = bell
	bell = nil
	if bl then
		bl.post:Destroy()
		bl.bell:Destroy()
	end
	hideCaption()
	hideBanner()
	lastHullPos = nil
	speed = 0
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
	local audio = AudioDirector.debugState()
	return {
		active = active,
		phase = phase,
		boats = boats,
		beacons = beacons,
		locked = #lock > 0,
		cone = coneLight ~= nil and (coneLight :: SpotLight).Enabled,
		coneOnLantern = coneAim ~= nil and (coneAim :: Attachment).Parent ~= nil,
		shaft = shaft ~= nil,
		column = column ~= nil and (column :: BillboardGui).Enabled,
		tolls = tolls,
		tollPlaying = toll ~= nil and (toll :: Sound).Parent ~= nil,
		wake = #wake,
		chase = drone ~= nil,
		speed = math.floor(speed * 10 + 0.5) / 10,
		stillFor = math.floor(stillFor * 10 + 0.5) / 10,
		vignette = math.floor(vignetteLevel * 100 + 0.5) / 100,
		ambienceMute = audio.mute,
		hush = audio.hush,
		ambience = if type(audio.groups) == "table" then audio.groups.Ambience else nil,
		dawn = saved ~= nil,
		caption = caption ~= nil and (caption :: TextLabel).Visible,
	}
end

return Finale
