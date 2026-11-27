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
-- Finale v6 (Neon finale-v5 2/10, docs/critic/11-26-2026-finale-v5-neon.md), overriding the
--   notes above where they differ: the line "The bell. Go home." comes 0.4 s AFTER the first
--   toll is heard; no music on the run home (the pursuit layer is only a low pulse, and
--   finale-chase-under is gone), the water stays silent until dawn; the shaft and the sky
--   column are gone: home is a modest light post with a small halo at the dock end, and false
--   beacons wear the same halo but blink wrong (steady or one flicker); the wake is soft
--   foam behind the stern (polish round 2; it was thin streaks ahead of the bow); the real
--   Steeple Cat lies on the hold lid while it is aboard.
-- M8 polish (Neon finale-v6 3/10, docs/M8-POLISH.md items 6 to 8): the dawn eases in by hand
--   over 3 s in stages (horizon, then fog, then the banner); the Steeple Cat lies on the floor
--   boards clear of the rods and stays in the boat through the dawn; the HUD hides under the
--   banner.
-- Readable strange boats (11/27/2026, Look.Finale.hazardGlow): the lantern hangs at the stern
--   behind the standing figure inside a soft glow, so the figure is a black cut-out against
--   it at any range. Rounds 2 to 4 (Neon on the stills): the hull lies turned so it reads as
--   a boat, the figure wears a long coat and a brimmed hat, the lantern hangs by his shoulder
--   in a small amber glow, no drawn eyes. See Look.Finale.hazardGlow.
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
local HUD = require(client:WaitForChild("ui"):WaitForChild("HUD"))

local Finale = {}

Finale.WAVE_PERIOD = 3.6 -- the Neighbor's wave: a little too slow
-- Polish round 2: a strange boat's figure stands on its floor boards 2.2 studs behind the bow
-- post (the lantern hangs ahead of it at 4 studs up), and the lantern sways slowly.
-- 11/27/2026 (readable boats, round 2): mid-boat, just in front of its lantern pole.
Finale.HAZARD_FIGURE = CFrame.new(0, 0.15, -0.4)
Finale.HAZARD_SWAY = { speed = 0.9, angle = 0.22 }
Finale.FOLLOW = 4 -- how quickly a drawn hazard closes on where it should be drawn
Finale.KEY = "Finale" -- AudioDirector mute and hush key
Finale.HOME_PITCH = math.rad(-6) -- the view's pitch at the end of the turn toward home
Finale.CAPTION = "The bell. Go home."
Finale.BANNER = "Dawn. You made it home."
-- Polish round 2 (Neon finale v7: "flat green streaks sliding across the water", seen in
-- the orchestrator's frames as thin bright green and white diagonals): those were the v6
-- wake streaks, pale SmoothPlastic slivers scattered 7 to 38 studs AHEAD of the bow in the
-- lantern cone, tinted green by the night grade. Gone. The wake is now soft low-contrast foam
-- left on the water behind the stern: a ParticleEmitter on an invisible strip at the transom,
-- flat on the water (engine smoke texture, not an uploaded id), lit by the scene so it stays
-- dim, more of it the faster the boat goes.
Finale.WAKE = {
	behind = 6.4, -- studs behind the hull center (the transom is at about 5.5)
	width = 3.2,
	minSpeed = 3,
	fullSpeed = 12, -- the most foam at and above this speed
	rate = 9, -- particles a second at full speed
	color = Color3.fromRGB(150, 160, 156),
	transparency = { 0.7, 1 },
	size = { 1.1, 3.4 },
	lifetime = { 1.6, 2.6 },
	texture = "rbxasset://textures/particles/smoke_main.dds",
}
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
	halo: BillboardGui?, -- false beacons: the same halo as home
	blink: string?, -- false beacons: "Steady" or "Single" (never the real double blink)
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

-- The real beacon's light post and its halo.
local shaft: BasePart? = nil
local halo: BillboardGui? = nil

-- The chase.
local drone: Sound? = nil
local under: Sound? = nil
local speed = 0
local lastHullPos: Vector3? = nil
local stillFor = 0
local fear = 0 -- 0..1, smoothed

-- The stern foam (the wake).
local wakeStrip: BasePart? = nil
local wakeFoam: ParticleEmitter? = nil

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

local bannerAt: number? = nil -- os.clock() when the dawn banner went up (nil when it is not)

-- When the dawn banner went up (os.clock()), or nil. NightCards waits on it for the run card.
function Finale.bannerShownAt(): number?
	return bannerAt
end

-- Puts the dawn banner away now, fading over `fade` seconds (the run card is coming in).
function Finale.dismissBanner(fade: number)
	local b, t = banner, bannerText
	if b == nil or t == nil or not b.Visible then
		return
	end
	local st = b:FindFirstChildOfClass("UIStroke")
	local info = TweenInfo.new(fade)
	TweenService:Create(b, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(t, info, { TextTransparency = 1 }):Play()
	if st then
		TweenService:Create(st, info, { Transparency = 1 }):Play()
	end
	local at = bannerAt
	task.delay(fade, function()
		if b.Visible and bannerAt == at then
			b.Visible = false
			HUD.setHidden(Finale.KEY, false)
		end
	end)
end

local function showBanner()
	screen()
	bannerAt = os.clock()
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
	-- M8 polish (Neon: the banner overlapped the HUD paper): the HUD hides under the banner
	-- and comes back once it has faded.
	HUD.setHidden(Finale.KEY, true)
	task.delay(Look.Dawn.bannerHold, function()
		if b.Visible then
			local info = TweenInfo.new(1.5)
			TweenService:Create(b, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(t, info, { TextTransparency = 1 }):Play()
			if st then
				TweenService:Create(st, info, { Transparency = 1 }):Play()
			end
			task.delay(1.5, function()
				if b.Visible then
					b.Visible = false
					HUD.setHidden(Finale.KEY, false)
				end
			end)
		end
	end)
end

local function hideBanner()
	bannerAt = nil
	local b = banner
	if b then
		b.Visible = false
	end
	HUD.setHidden(Finale.KEY, false)
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
-- The wake: soft foam left on the water behind the stern while the boat runs.

local function buildWake(): ParticleEmitter
	local W = Finale.WAKE
	local strip = Common.part(
		"FinaleWakeStrip",
		Vector3.new(W.width, 0.05, 0.6),
		CFrame.new(),
		Color3.new(),
		nil,
		{ transparency = 1 }
	)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "SternFoam"
	pe.Texture = W.texture
	pe.Color = ColorSequence.new(W.color)
	pe.Size = NumberSequence.new(W.size[1], W.size[2])
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, W.transparency[1]),
		NumberSequenceKeypoint.new(1, W.transparency[2]),
	})
	pe.Lifetime = NumberRange.new(W.lifetime[1], W.lifetime[2])
	-- Flat on the water: a slow upward emission with the sprite facing its velocity.
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Speed = NumberRange.new(0.04, 0.08)
	pe.SpreadAngle = Vector2.new(0, 0)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-15, 15)
	pe.LightInfluence = 1
	pe.LightEmission = 0
	pe.LockedToPart = false
	pe.Rate = 0
	pe.Parent = strip
	wakeStrip = strip
	wakeFoam = pe
	return pe
end

local function stepWake(_dt: number, alive: boolean)
	local hull = BoatClient.hull()
	local W = Finale.WAKE
	if hull == nil then
		local old = wakeFoam
		if old then
			old.Rate = 0
		end
		return
	end
	local current, old = wakeStrip, wakeFoam
	local pe: ParticleEmitter = if current and current.Parent and old then old else buildWake()
	local strip = wakeStrip
	if strip == nil then
		return
	end
	local look = flat(hull.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local at = flat(hull.Position) - look * W.behind + Vector3.new(0, Config.Lake.waterY + 0.08, 0)
	strip.CFrame = CFrame.lookAt(at, at + look)
	local k = math.clamp((speed - W.minSpeed) / math.max(0.1, W.fullSpeed - W.minSpeed), 0, 1)
	local on = alive and speed >= W.minSpeed
	pe.Rate = if on then W.rate * (0.35 + 0.65 * k) else 0
end

local function clearWake()
	local strip = wakeStrip
	wakeStrip, wakeFoam = nil, nil
	if strip then
		-- Let the foam already on the water fade on its own.
		local pe = strip:FindFirstChildOfClass("ParticleEmitter")
		if pe then
			pe.Rate = 0
		end
		task.delay(Finale.WAKE.lifetime[2] + 0.2, function()
			strip:Destroy()
		end)
	end
end

----------------------------------------------------------------------------------------
-- The real dock beacon, finale v6 (Neon 2/10: the sky column out-shone the false beacons and
-- made them pointless). Now a modest warm light post at the dock end, near the water, with a
-- small halo drawn over the fog so home still shows across the lake. It double-blinks with the
-- beacon (WorldFx.beaconDark): the rulebook's tell. The false beacons wear the same halo and
-- blink wrong (steady, or one flicker). The view turns to face home at the first toll.

-- A small halo of three soft rings, sized in studs with a pixel floor so it never vanishes in
-- the distance and never fills the screen up close. Shared by the real and the false beacons.
local function makeHalo(name: string, adornee: BasePart, color: Color3): BillboardGui
	local H = Look.Finale.beaconHalo
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = H.maxDistance
	bb.Size = UDim2.new(H.studs, H.minPixels, H.studs, H.minPixels)
	for i, k in { 1, 0.6, 0.3 } do
		local f = Instance.new("Frame")
		f.Name = "Ring" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(k, k)
		f.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2 * i)
		f.BackgroundTransparency = H.ringTransparency[i]
		f.BorderSizePixel = 0
		f.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	bb.Parent = adornee
	return bb
end

local postLamp: BasePart? = nil

local function buildShaft()
	if shaft ~= nil then
		return
	end
	local S = Look.Finale.beaconShaft
	local at = dockPoint()
	local base = Vector3.new(at.X + S.offset.X, Config.Lake.waterY, at.Z + S.offset.Z)
	local p = Common.part(
		"FinaleBeaconPost",
		Vector3.new(S.height, S.width, S.width),
		CFrame.new(base + Vector3.new(0, S.height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Look.Palette.dockPost,
		Enum.Material.Wood,
		{ shape = Enum.PartType.Cylinder }
	)
	shaft = p
	local lamp = Common.part(
		"FinaleBeaconPostLamp",
		Vector3.new(S.lamp, S.lamp * 1.2, S.lamp),
		CFrame.new(base + Vector3.new(0, S.height + S.lamp * 0.6, 0)),
		Look.Beacon.Color,
		Enum.Material.Neon,
		{ parent = p }
	)
	local light = Instance.new("PointLight")
	light.Color = Look.Beacon.Color
	light.Range = S.lightRange
	light.Brightness = S.lightBrightness
	light.Shadows = false
	light.Parent = lamp
	postLamp = lamp
	halo = makeHalo("FinaleBeaconHalo", lamp, Look.Beacon.Color)
end

local function stepShaft()
	local lamp, bb = postLamp, halo
	if shaft == nil or lamp == nil then
		return
	end
	local dark = WorldFx.beaconDark(Workspace:GetServerTimeNow())
	lamp.Material = if dark then Enum.Material.SmoothPlastic else Enum.Material.Neon
	lamp.Transparency = if dark then 0.5 else 0
	local light = lamp:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = not dark
	end
	if bb then
		bb.Enabled = not dark
	end
end

local function clearShaft(fade: number)
	local p = shaft
	if halo then
		halo.Enabled = false -- a billboard does not fade with its part
	end
	shaft, halo, postLamp = nil, nil, nil
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
	-- Polish round 2 (Neon finale v7: "tiny yellow specks"): a readable silhouette. The hull is
	-- dark wood (lighter than before so its own lantern can pick it out), the lantern's
	-- PointLight is short (Look.Finale.hazardLightRange, about 20) and bright so it lights this
	-- boat and its still standing figure, not the lake; the lantern sways slowly on its hook
	-- and the boat creaks as you pass (finale-hazard-creak). Distances are Core's, unchanged.
	local dark = Look.Palette.silhouette:Lerp(Look.Palette.boatTrim, Look.Finale.hazardHullTone)
	local parts = {}
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material?): BasePart
		local p = Common.part(name, size, CFrame.new(pos) * offset, color, mat, { parent = m })
		table.insert(parts, { part = p, offset = offset })
		return p
	end
	-- 11/27/2026 (readable boats, round 2): the hull lies turned Look.Finale.hazardYaw off facing
	-- you, so its length, its bow and its shipped oars read; the root still faces you.
	local turn = CFrame.Angles(0, Look.Finale.hazardYaw, 0)
	local hullPart =
		piece("Hull", Vector3.new(4.2, 0.5, 11), turn * CFrame.new(0, 0.1, 0), dark, Enum.Material.WoodPlanks)
	-- Round 3: taller sides (the figure stands inside, not on top) and a pointed bow.
	piece("SideL", Vector3.new(0.35, 1.8, 11), turn * CFrame.new(-2.2, 0.95, 0), dark, Enum.Material.WoodPlanks)
	piece("SideR", Vector3.new(0.35, 1.8, 11), turn * CFrame.new(2.2, 0.95, 0), dark, Enum.Material.WoodPlanks)
	piece("Stern", Vector3.new(4.6, 1.8, 0.35), turn * CFrame.new(0, 0.95, 5.5), dark, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		piece(
			if sx < 0 then "BowL" else "BowR",
			Vector3.new(0.35, 1.8, 3.2),
			turn * CFrame.new(sx * 1.1, 0.95, -6.6) * CFrame.Angles(0, sx * math.rad(45), 0),
			dark,
			Enum.Material.WoodPlanks
		)
	end
	-- Round 4: the bow and stern tips rise above the sides, so the sheer reads side-on.
	piece("BowTip", Vector3.new(0.4, 2.8, 0.4), turn * CFrame.new(0, 1.4, -7.6), dark, Enum.Material.Wood)
	piece("SternTip", Vector3.new(4.6, 0.5, 0.5), turn * CFrame.new(0, 2.05, 5.5), dark, Enum.Material.Wood)
	-- Shipped oars, angled out and down over each side.
	for _, sx in { -1, 1 } do
		piece(
			if sx < 0 then "OarL" else "OarR",
			Vector3.new(0.22, 0.22, 7.2),
			turn * CFrame.new(sx * 3.1, 1.2, 0.6) * CFrame.Angles(math.rad(6), sx * math.rad(58), 0),
			dark,
			Enum.Material.Wood
		)
	end
	-- The lantern pole stands just behind the figure (in the root frame: away from you), so its
	-- lantern hangs behind the figure's head and shoulders, inside its glow.
	-- Round 3 (Neon: "a saint's halo" with no source): the pole stands off his right shoulder,
	-- so the lantern itself shows beside his head while its glow still backs his silhouette.
	piece("Post", Vector3.new(0.22, 6.2, 0.22), CFrame.new(1.5, 3.1, 1.3), dark)
	piece("Arm", Vector3.new(0.7, 0.16, 0.16), CFrame.new(1.2, 6.1, 1.3), dark)
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
	-- The glow around the lantern, drawn over the fog but depth tested (AlwaysOnTop off), so the
	-- figure in front of it cuts a black shape out of it at any range.
	local HG = Look.Finale.hazardGlow
	local bb = Instance.new("BillboardGui")
	bb.Name = "Glow"
	bb.Adornee = glow
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = HG.maxDistance
	bb.Size = UDim2.new(HG.studs, HG.minPixels, HG.studs, HG.minPixels)
	-- Many faint stacked discs, each a little smaller: the overlaps build a smooth falloff toward
	-- the middle with no visible bands, and no image asset.
	local n = HG.rings
	for i = 1, n do
		local k = 1 - ((i - 1) / (n - 1)) ^ 0.8 * 0.85
		local f = Instance.new("Frame")
		f.Name = "Ring" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(k, k)
		f.BackgroundColor3 = HG.color
		f.BackgroundTransparency = HG.ringTransparency
		f.BorderSizePixel = 0
		f.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	bb.Parent = glow
	-- A still standing figure at the bow, facing you, between you and its lantern: a little too
	-- tall, a silhouette with pin eyes (DESIGN.md palette), nothing more.
	local HF = Look.Finale.hazardFigure
	local fig = Common.figure("Stander", { height = HF.height, width = HF.width, eyes = true })
	fig.model.Parent = m
	-- Round 2: a long coat and a wide brimmed hat, so it reads as a person out on the water
	-- (a dark fisherman), not a stick figure. Heights follow Common.figure's proportions.
	do
		local h, w = HF.height, HF.width
		local legH, torsoH, headH = h * 0.46, h * 0.36, h * 0.12
		local headTop = legH + torsoH + headH + h * 0.01
		local black = Look.Palette.silhouette
		local function wear(name: string, size: Vector3, at: CFrame)
			local p = Common.part(name, size, CFrame.new(), black, Enum.Material.SmoothPlastic, { parent = fig.model })
			fig.locals[p] = at
		end
		local coatBottom = h * 0.17
		local coatH = legH + torsoH - coatBottom
		wear("Coat", Vector3.new(w * 1.12, coatH, w * 0.62), CFrame.new(0, coatBottom + coatH / 2, 0))
		-- Round 4: the coat's hem flares, and the head and hat lean a few degrees (it watches).
		wear("Hem", Vector3.new(w * 1.4, h * 0.12, w * 0.8), CFrame.new(0, coatBottom + h * 0.06, 0))
		local neck = CFrame.new(0, legH + torsoH, 0) * CFrame.Angles(0, 0, math.rad(-9))
		for p, at in fig.locals do
			if p.Name == "Head" or string.sub(p.Name, 1, 3) == "Eye" then
				fig.locals[p] = neck * CFrame.new(0, -(legH + torsoH), 0) * at
			end
		end
		wear("Brim", Vector3.new(w * 1.3, 0.08, w * 1.3), neck * CFrame.new(0, headTop - legH - torsoH + 0.03, 0))
		local crownH = h * 0.07
		wear(
			"Crown",
			Vector3.new(w * 0.56, crownH, w * 0.56),
			neck * CFrame.new(0, headTop - legH - torsoH + 0.06 + crownH / 2, 0)
		)
	end
	-- Round 4 (Neon: big drawn eyes looked "cartoonish"; a blank shadow under a hat is scarier):
	-- no drawn eyes. Only Common.figure's own tiny pin eyes remain, seen when it is close.
	Common.outline(m)
	local snd = AudioDirector.loop("finale-hazard-creak", hullPart)
	return {
		form = "Boat",
		model = m,
		parts = parts,
		figure = fig,
		lamp = glow,
		light = light,
		lanternPost = CFrame.new(0.95, 6.05, 1.3),
		sound = snd,
		target = pos,
		drawn = pos,
		phase = math.random() * 10,
	}
end

-- Finale v6: a false beacon is built like home's light post (same post, same lamp, same halo)
-- so from across the water it could be home. Only the blink tells: "Steady" (never goes dark)
-- or "Single" (one dark flicker per period), never the beacon's clean double blink.
local function buildBeacon(pos: Vector3, id: number): Hazard
	local S = Look.Finale.beaconShaft
	local m = Instance.new("Model")
	m.Name = "FinaleFalseBeacon"
	m.Parent = Common.folder()
	local parts = {}
	local postOffset = CFrame.new(0, S.height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local pole = Common.part(
		"Pole",
		Vector3.new(S.height, S.width, S.width),
		CFrame.new(pos) * postOffset,
		Look.Palette.dockPost,
		Enum.Material.Wood,
		{ parent = m, shape = Enum.PartType.Cylinder }
	)
	table.insert(parts, { part = pole, offset = postOffset })
	local lampOffset = CFrame.new(0, S.height + S.lamp * 0.6, 0)
	local lamp = Common.part(
		"Lamp",
		Vector3.new(S.lamp, S.lamp * 1.2, S.lamp),
		CFrame.new(pos) * lampOffset,
		Look.Beacon.Color,
		Enum.Material.Neon,
		{ parent = m }
	)
	table.insert(parts, { part = lamp, offset = lampOffset })
	local light = Instance.new("PointLight")
	light.Color = Look.Beacon.Color
	light.Range = S.lightRange
	light.Brightness = S.lightBrightness
	light.Shadows = false
	light.Parent = lamp
	-- Never outlined: the drowned see an outline on the real beacon only (Drowned.luau).
	local snd = AudioDirector.loop("finale-hazard-whine", lamp)
	local bb = makeHalo("FinaleFalseHalo", lamp, Look.Beacon.Color)
	return {
		form = "FalseBeacon",
		model = m,
		parts = parts,
		figure = nil,
		lamp = lamp,
		light = light,
		lanternPost = nil,
		sound = snd,
		halo = bb,
		blink = if id % 2 == 0 then "Steady" else "Single",
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
	local bb = h.halo
	if bb then
		bb.Enabled = false -- a billboard does not fade with its part
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
			-- Standing still mid-boat, just in front of its lantern pole, facing the player's boat
			-- (the root faces it; a figure faces its root's -Z). No wave: it only watches.
			Common.placeFigure(fig, root * Finale.HAZARD_FIGURE)
		end
		local lamp, light = h.lamp, h.light
		if h.form == "Boat" and lamp and h.lanternPost then
			-- A slow sway on a short hook.
			local S = Finale.HAZARD_SWAY
			local sway = math.sin(clock * S.speed + h.phase) * S.angle
			local sway2 = math.sin(clock * S.speed * 0.7 + h.phase * 2) * S.angle * 0.55
			lamp.CFrame = root * (h.lanternPost :: CFrame) * CFrame.Angles(sway, 0, sway2) * CFrame.new(0, -0.9, 0)
		elseif h.form == "FalseBeacon" and lamp and light then
			-- It blinks wrong: steady (a faint shimmer, never dark) or one dark flicker per
			-- period. Never the beacon's clean double blink.
			local B = Look.Finale.falseBlink
			local dark = h.blink == "Single" and ((clock + h.phase) % B.period) < B.dark
			local k = if dark then 0 else 1 + B.shimmer * math.noise(clock * 5 + h.phase, h.phase)
			light.Brightness = Look.Finale.beaconShaft.lightBrightness * k
			light.Enabled = not dark
			lamp.Material = if dark then Enum.Material.SmoothPlastic else Enum.Material.Neon
			lamp.Transparency = if dark then 0.5 else 0
			local bb = h.halo
			if bb then
				bb.Enabled = not dark
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- The chase: the pursuit layer and the closing edges

-- Finale v6 (Neon: "ambient synth music fades in at 00:20, killing the eerie silence"): no
-- music on the run home. Only the low pulse (finale-chase-drone, at a quarter of its old level
-- in SoundRegistry) under the motor, plus the hazards' own sounds. finale-chase-under (the
-- slowed finale-bed) no longer plays; `under` stays for a clean stop of an older loop.
local function startChase()
	if drone == nil then
		drone = AudioDirector.loop("finale-chase-drone", nil)
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
-- The owner's fish on deck (finale v6, Neon: "a smooth grey oval posing as the special fish").
-- While the Steeple Cat is in the hold, the real fish model (the server's Field Guide drawing,
-- the same FishModel the catch uses) lies on the hold lid, and the one plain hold token it
-- stands for is hidden on this client (LocalTransparencyModifier). No model: nothing shows.

Finale.GUIDE_FOLDER = "DeadCalmFieldGuide"
-- M8 polish (Neon: "the fish clips across the two fishing rods", and it "deletes itself" at
-- dawn): the cat lies on the floor boards along the port side, beside the hold box (hull
-- frame: the box spans x -1.1..1.1, the port side is at x -2.3, the floor top is y 0.33; the
-- mid thwart ends at z -0.7 and the stern thwart starts at z 3.7), clear of every rod (the
-- port and starboard rods sit at z -1.4, the helm rod leans out to starboard). It stays in
-- the boat through the dawn, after the owner has taken the hold.
Finale.DECK_CAT = { length = 2.4, offset = Vector3.new(-1.7, 0.34, 1.6), yaw = 0 }

local deckCat: Model? = nil
local deckRel: CFrame = CFrame.identity -- pivot relative to the bounding box center
local deckLift = 0 -- half the fish's thickness lying on its side
local hiddenToken: BasePart? = nil

local function clearDeckCat()
	local m = deckCat
	deckCat = nil
	if m then
		m:Destroy()
	end
	local t = hiddenToken
	hiddenToken = nil
	if t and t.Parent then
		t.LocalTransparencyModifier = 0
	end
end

local function buildDeckCat(): Model?
	local folder = ReplicatedStorage:FindFirstChild(Finale.GUIDE_FOLDER)
	local src = folder and folder:FindFirstChild(Config.Rules.Finale.needSpecies)
	if src == nil or not src:IsA("Model") then
		return nil
	end
	local m = src:Clone()
	m.Name = "FinaleDeckCat"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	-- Fit its length (the Field Guide fish runs along Z) to the hold lid.
	local _, size = m:GetBoundingBox()
	local long = math.max(size.X, size.Y, size.Z)
	if long > 1e-3 then
		m:ScaleTo(m:GetScale() * Finale.DECK_CAT.length / long)
	end
	local cf, scaled = m:GetBoundingBox()
	deckRel = cf:Inverse() * m:GetPivot()
	deckLift = scaled.X / 2 -- on its side its width stands up
	m.Parent = Common.folder()
	return m
end

local function stepDeckCat()
	local view: any = ViewState.get()
	local hull = BoatClient.hull()
	local aboard = active and view.specialAboard == true and (tonumber(view.hold) or 0) > 0
	-- At dawn the cat that was aboard stays where it lies (the hold token is banked by then).
	-- The view that banks the hold may land a moment before the pass event: inside the dock
	-- light a cat already shown is kept too.
	local atDawn = deckCat ~= nil and (phase == "Dawn" or (active and view.safe == true))
	local want = (aboard or atDawn) and hull ~= nil
	if not want or hull == nil then
		if deckCat or hiddenToken then
			clearDeckCat()
		end
		return
	end
	if deckCat == nil then
		deckCat = buildDeckCat()
		if deckCat == nil then
			return
		end
	end
	if aboard and (hiddenToken == nil or hiddenToken.Parent == nil) then
		local boat = BoatClient.model()
		for i = 8, 1, -1 do
			local t = boat and boat:FindFirstChild("HoldFish" .. i, true)
			if t and t:IsA("BasePart") then
				t.LocalTransparencyModifier = 1
				hiddenToken = t
				break
			end
		end
	end
	local D = Finale.DECK_CAT
	local at = hull.CFrame
		* CFrame.new(D.offset + Vector3.new(0, deckLift, 0))
		* CFrame.Angles(0, math.rad(D.yaw), math.pi / 2)
	local m = deckCat :: Model
	m:PivotTo(at * deckRel)
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

-- M8 polish: the dawn eases in by hand (no TweenService), one stage after another: the horizon
-- (the Lighting colours, the sky's ClockTime, the fog's colour and the colour grade) warms over
-- the whole Look.Dawn.seconds; the fog lifts and thins (Density, Offset, Haze) from fogDelay of
-- the way in; the banner shows at the end. Values are lerped from what was on screen.
local dawnT0: number? = nil
local dawnBannerShown = false
local FOG_PROPS = { Density = true, Offset = true, Haze = true }

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

local function mix(a: any, b: any, k: number): any
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return (a :: Color3):Lerp(b :: Color3, k)
	elseif type(a) == "number" and type(b) == "number" then
		return a + (b - a) * k
	end
	return if k >= 1 then b else a
end

-- 0..1 for the horizon and for the fog at `u` (0..1 of the way through the dawn).
function Finale.dawnStages(u: number): (number, number)
	local D = Look.Dawn
	local f = D.fogDelay or 0
	return smooth(u), smooth((u - f) / math.max(1e-3, 1 - f))
end

-- The sky clock at horizon progress `kH` (0..1), from the night's clock `night`: up to
-- Look.Dawn.clockFrom over the first clockLead of the ease (all still night to the eye), then on
-- to Look.Dawn.ClockTime. Continuous from the very first frame (polish round 3: no jump).
function Finale.dawnClock(night: number, kH: number): number
	local D = Look.Dawn
	local goal = D.ClockTime
	local mid = D.clockFrom or goal
	local from = night
	if from > goal then
		from -= 24 -- the night clock is before midnight: run forward through it
	end
	mid = math.max(from, mid)
	local lead = math.clamp(D.clockLead or 0, 0, 0.9)
	local c: number
	if lead > 0 and kH < lead then
		c = from + (mid - from) * (kH / lead)
	else
		c = mid + (goal - mid) * math.clamp((kH - lead) / (1 - lead), 0, 1)
	end
	return if c < 0 then c + 24 else c
end

local function stepDawn()
	local t0, s = dawnT0, saved
	if t0 == nil or s == nil then
		return
	end
	local D = Look.Dawn
	local u = math.clamp((clock - t0) / math.max(0.01, D.seconds), 0, 1)
	local kH, kF = Finale.dawnStages(u)
	local atmo, cc = lightingTargets()
	local light: any = Lighting
	local dawnLook: any = D
	for _, k in LIGHT_PROPS do
		if k == "ClockTime" then
			light.ClockTime = Finale.dawnClock(s.lighting.ClockTime, kH)
		else
			light[k] = mix(s.lighting[k], dawnLook[k], kH)
		end
	end
	if atmo then
		local a: any = atmo
		local goals: any = D.atmosphere
		for _, k in ATMO_PROPS do
			if goals[k] ~= nil and s.atmo[k] ~= nil then
				a[k] = mix(s.atmo[k], goals[k], if FOG_PROPS[k] then kF else kH)
			end
		end
	end
	if cc then
		local c: any = cc
		local goals: any = D.colorCorrection
		for _, k in CC_PROPS do
			if goals[k] ~= nil and s.cc[k] ~= nil then
				c[k] = mix(s.cc[k], goals[k], kH)
			end
		end
	end
	if u >= 1 then
		dawnT0 = nil -- done: the values stay at the dawn
		if not dawnBannerShown then
			dawnBannerShown = true
			showBanner()
		end
	end
end

local function dawn()
	phase = "Dawn"
	saveLighting()
	WorldFx.ambientOverride = true
	dawnT0 = clock
	dawnBannerShown = false
	stepDawn()
	-- The water and the morning come back.
	AudioDirector.muteAmbience(Finale.KEY, false, 2.5)
	AudioDirector.play("dawn-cue")
	task.delay(0.9, function()
		if phase == "Dawn" then
			AudioDirector.play("dawn-birds")
		end
	end)
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
	stepDeckCat()
	stepDawn()
	stepChase(dt, alive)
	stepHazards(dt)
	stepBell(dt)
end

local function ensureLoop()
	if conn == nil then
		conn = RunService.Heartbeat:Connect(step)
	end
end

local function endFinale(fade: number, keepCat: boolean?)
	active = false
	cueToken += 1
	if phase ~= "Dawn" then
		phase = "Off"
	end
	clearLock()
	clearWake()
	if not keepCat then
		clearDeckCat()
	end
	clearHazards(fade)
	clearShaft(fade)
	stopChase(math.min(fade, 1.5))
	stillFor = 0
	fear = 0
	setVignette(0)
	cutToll(0.6)
	AudioDirector.hush(Finale.KEY, false)
	AudioDirector.boostLayer("motorIdle", 1)
	HUD.holdOil(Finale.KEY, false)
end

-- At the first toll the view eases round to face home (the dock beacon) over `seconds`, so every
-- player, on a phone too, knows which way to go. Found 11/26/2026: the crew is usually looking
-- at its bobber off the side of the boat when the bell rings, and Neon read the run home as
-- "no direction home". The player's own look takes over again as soon as it finishes.
-- Polish round 3 (Neon finale v8: "the camera snaps"): the old ease set the pitch to the goal on
-- the first frame and took a fixed share of the turn per frame (frame-rate bound, 8 percent of
-- up to half a turn in one frame). Now each frame takes the share of what is left that a
-- smoothstep from the current view calls for, for yaw and pitch alike: it starts at rest from
-- wherever the player was looking and ends exactly on home, at any frame rate. Writing a share
-- of what is left (not an absolute angle) keeps the boat's own turn (Camera) on top of it.
local function faceHome(seconds: number)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local e = Config.Lake.dockEnd
	local start = os.clock()
	local done = 0 -- eased share of the turn already made
	local name = "DeadCalmFaceHome"
	pcall(function()
		RunService:UnbindFromRenderStep(name)
	end)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
		local t = math.clamp((os.clock() - start) / math.max(0.05, seconds), 0, 1)
		local want = smooth(t)
		local k = if want >= 1 then 1 else math.clamp((want - done) / math.max(1e-4, 1 - done), 0, 1)
		done = want
		local cf = cam.CFrame
		local pos = cf.Position
		local lv = cf.LookVector
		local curYaw = math.atan2(-lv.X, -lv.Z)
		local curPitch = math.asin(math.clamp(lv.Y, -1, 1))
		local toX, toZ = e.x - pos.X, e.z - pos.Z
		local goalYaw = math.atan2(-toX, -toZ)
		local d = goalYaw - curYaw
		if d > math.pi then
			d -= 2 * math.pi
		elseif d < -math.pi then
			d += 2 * math.pi
		end
		local yaw = curYaw + d * k
		local pitch = curPitch + (Finale.HOME_PITCH - curPitch) * k
		cam.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		if t >= 1 then
			RunService:UnbindFromRenderStep(name)
		end
	end)
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
	-- The oil bar keeps its night look (amber, its level) until the first toll (polish round 3).
	HUD.holdOil(Finale.KEY, true)
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
		-- Polish round 3 (Neon finale v8: the turn came in four beats, clock, red bar, camera,
		-- bell): everything lands on the first toll the moment it is actually heard (the Sound
		-- may take a moment to load and start; wait for it, at most F.captionWaitMax): the oil
		-- bar turns red (eased, HUD.OIL_EASE), the view eases toward home from wherever it is,
		-- and the line shows (F.captionAfterToll, now 0).
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < F.captionWaitMax do
				local s = toll
				if s and s.Parent and s.IsPlaying and s.TimePosition > 0 then
					break
				end
				task.wait()
			end
			if F.captionAfterToll > 0 then
				task.wait(F.captionAfterToll)
			end
			if cueToken == my and active then
				HUD.holdOil(Finale.KEY, false)
				faceHome(F.faceHomeSeconds)
				showCaption(Finale.CAPTION, F.captionHold)
			end
		end)
		task.delay((F.bellStrokes - 1) * F.bellGap + F.afterBell, function()
			if cueToken ~= my or not active then
				return
			end
			phase = "Run"
			AudioDirector.hush(Finale.KEY, false)
			AudioDirector.boostLayer("motorIdle", Look.Finale.runMotorBoost)
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
			h = if data.form == "FalseBeacon" then buildBeacon(pos, id) else buildBoat(pos)
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
		local home = data.home == true
		if home then
			phase = "Dawn" -- before endFinale, so the cat on the floor stays (stepDeckCat)
		end
		endFinale(2.5, home)
		if home then
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
	dawnT0 = nil
	dawnBannerShown = false
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
		halo = halo ~= nil and (halo :: BillboardGui).Enabled,
		tolls = tolls,
		tollPlaying = toll ~= nil and (toll :: Sound).Parent ~= nil,
		wake = if wakeFoam then (wakeFoam :: ParticleEmitter).Rate else 0,
		deckCat = deckCat ~= nil,
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
