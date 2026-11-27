--!strict
-- Rule 4, the Knocking, on screen.
--   EntityCue (round 1)          three slow knocks under the hull (knock-three-soft), and
--                                the boat jolts with each one
--   EntityStage Cue (hard=true)  round 2: three harder knocks (knock-three-hard), harder jolts
--   EntityStage Window           the answer window: a quiet "Q  Knock" hint (the book says
--                                how many; the screen never does)
--   EntityPass                   knock-pass, a soft settle
--   EntityFail                   water starts coming in (Flooding events and view.flood;
--                                BoatFx draws the water and the bailing)
-- The crew's own answers are heard on the hull from the server (EntityPresenter); the knocker
-- also feels a small jolt at once (Input calls Knocking.answered).
-- The drowned see a long shape under the keel while it knocks.

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Common = require(script.Parent:WaitForChild("Common"))

local Knocking = {}

local token = 0
local windowOpen = false
local shape: BasePart? = nil
local hintListeners: { (boolean) -> () } = {}

local function setWindow(open: boolean)
	if windowOpen == open then
		return
	end
	windowOpen = open
	for _, fn in hintListeners do
		task.spawn(fn, open)
	end
end

-- True while the crew can answer (for the hint).
function Knocking.windowOpen(): boolean
	return windowOpen
end

function Knocking.onWindow(fn: (boolean) -> ())
	table.insert(hintListeners, fn)
end

function Knocking.answered()
	BoatFx.shake(0.06, 0.15)
end

local function showShape()
	if shape and shape.Parent then
		return
	end
	local hull = BoatClient.hull()
	if hull == nil then
		return
	end
	local p = Common.part(
		"UnderKeel",
		Vector3.new(3, 3, 16),
		hull.CFrame * CFrame.new(0, -4, 0),
		Color3.fromRGB(8, 12, 14),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball }
	)
	Common.ghostOnly(p, 0.3)
	Common.outline(p)
	shape = p
	task.spawn(function()
		while p.Parent do
			local h = BoatClient.hull()
			if h then
				p.CFrame = h.CFrame * CFrame.new(math.sin(os.clock() * 0.8) * 0.5, -4, 0)
			end
			task.wait()
		end
	end)
end

local function hideShape()
	local s = shape
	shape = nil
	if s then
		s:Destroy()
	end
end

-- The library knocks are single thuds: the registry's `repeat` plays each three times, here
-- at the server's gap so the jolts line up. Destroying the sound cancels the rest.
local knockSound: Sound? = nil

local function stopKnocks()
	local k = knockSound
	knockSound = nil
	if k and k.Parent then
		k:Destroy()
	end
end

local function knocks(sound: string, gap: number, strength: number)
	token += 1
	local my = token
	stopKnocks()
	knockSound = AudioDirector.play(sound, BoatClient.hull(), { repeatGap = gap })
	task.spawn(function()
		for _ = 1, 3 do
			if token ~= my then
				return
			end
			BoatFx.shake(0.18 * strength, 0.3)
			task.wait(gap)
		end
	end)
end

function Knocking.handle(e: any)
	local data = e.data or {}
	local gap = tonumber(data.gap) or 1.1
	if e.kind == "EntityCue" then
		setWindow(false)
		showShape()
		knocks("knock-three-soft", gap, 1)
	elseif e.kind == "EntityStage" then
		if data.stage == "Cue" and data.hard == true then
			setWindow(false)
			knocks("knock-three-hard", gap, 2.2)
		elseif data.stage == "Window" then
			setWindow(true)
		elseif data.stage == "Cooldown" then
			setWindow(false)
			hideShape()
		end
	elseif e.kind == "EntityPass" then
		setWindow(false)
		AudioDirector.play("knock-pass", BoatClient.hull())
		BoatFx.shake(0.05, 0.4)
		task.delay(1.5, hideShape)
	elseif e.kind == "EntityFail" then
		setWindow(false)
		BoatFx.shake(0.35, 0.8)
		task.delay(1.5, hideShape)
	end
end

function Knocking.reset()
	token += 1
	stopKnocks()
	setWindow(false)
	hideShape()
end

return Knocking
