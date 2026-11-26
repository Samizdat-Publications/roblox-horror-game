--!strict
-- Server entry point: builds the world and the night look, opens the remotes, launches the
-- boat and the fishing gear, seats every player who joins (there is no lobby until S4), and
-- runs the night (NightService) once the first player is seated.
-- Prints exactly one line in normal operation; anything else is a warning or an error.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local server = script.Parent
local WorldBuilder = require(server:WaitForChild("WorldBuilder"))
local LightingController = require(server:WaitForChild("LightingController"))
local BoatService = require(server:WaitForChild("BoatService"))
local Net = require(server:WaitForChild("Net"))
local FishingService = require(server:WaitForChild("FishingService"))
local NightService = require(server:WaitForChild("NightService"))

local startupWarnings: { string } = {}

WorldBuilder.build()
for _, w in LightingController.apply() do
	table.insert(startupWarnings, w)
end
Net.init()
BoatService.init(WorldBuilder.context())
FishingService.init()

-- Seat a fresh character in the first free seat. Seat:Sit can miss while the character is
-- still loading, so retry a few times and say so loudly if it never works.
local function seatWhenReady(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if humanoid == nil or root == nil then
		warn("[DeadCalm] could not seat " .. player.Name .. ": character has no Humanoid or root")
		return
	end
	-- Seen in Studio on 11/26/2026: a Sit right after CharacterAdded takes, then the character is
	-- pulled back to the spawn while its appearance finishes loading. So wait for the appearance,
	-- then only count it as seated once the seat has held for two seconds.
	local waited = 0
	while not player:HasAppearanceLoaded() and waited < 10 do
		waited += task.wait(0.25)
	end
	task.wait(0.5)
	for _ = 1, 10 do
		if player.Character ~= character or character.Parent == nil then
			return
		end
		local seatName = BoatService.seatPlayer(player)
		if seatName == nil then
			local msg = "could not seat " .. player.Name .. ": the boat is full"
			table.insert(startupWarnings, msg)
			warn("[DeadCalm] " .. msg)
			return
		end
		local held = 0
		while held < 2 and humanoid.SeatPart ~= nil and humanoid.SeatPart.Name == seatName do
			held += task.wait(0.25)
		end
		if held >= 2 then
			return
		end
		task.wait(0.5)
	end
	local msg = "Seat:Sit never took for " .. player.Name
	table.insert(startupWarnings, msg)
	warn("[DeadCalm] " .. msg)
end

local function onPlayer(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	NightService.onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(seatWhenReady, player, character)
	end)
	if player.Character then
		task.spawn(seatWhenReady, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

-- The boat moves every frame; the night steps at Config.Night.tick inside NightService.
RunService.Heartbeat:Connect(function(dt: number)
	BoatService.step(dt)
	NightService.tick(dt)
end)
NightService.startWhenReady(15)

print("[DeadCalm] server up")

if RunService:IsStudio() then
	local DebugDriver = require(server:WaitForChild("DebugDriver")) :: any
	DebugDriver.warnings = startupWarnings
	DebugDriver.init()
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
