--!strict
-- First person, locked, while seated. Reports gaze yaw (atan2(look.x, look.z)) at
-- Config.Net.gazeHz. In Studio, DebugDriver can set fixed scriptable shots for captures.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local Events = require(script.Parent:WaitForChild("Events"))

local Camera = {}

local gazeRemote: RemoteEvent? = nil
local shotActive = false
local snapToSeat = false

local function camera(): Camera
	local cam = Workspace.CurrentCamera
	assert(cam, "no CurrentCamera")
	return cam
end

local function steeplePoint(): Vector3
	local s = Config.Lake.steeple
	return Vector3.new(s.x, Config.Lake.waterY + 12, s.z)
end

-- A fixed CFrame for a capture shot, or nil if the boat is not there yet.
function Camera.shotCFrame(shot: string): CFrame?
	local lake = Config.Lake
	local wy = lake.waterY
	local hull = BoatClient.hull()
	local boatPos = if hull then hull.Position else Vector3.new(lake.dockEnd.x, wy, lake.dockEnd.z + 9)
	if shot == "bow" then
		if hull == nil then
			return nil
		end
		return hull.CFrame * CFrame.new(0, Look.Shots.bowHeight, -9.5) * CFrame.Angles(math.rad(-4), 0, 0)
	elseif shot == "dock" then
		local foot = lake.dockFoot
		local from = Vector3.new(foot.x + 3, wy + 6, foot.z - 14)
		return CFrame.lookAt(from, boatPos + Vector3.new(0, 2, 0))
	elseif shot == "shore" then
		-- From the east shore by the reeds, looking back across the water at the boat.
		local a = math.atan2(lake.reeds.z / lake.radiusZ, lake.reeds.x / lake.radiusX)
		local from = Vector3.new(math.cos(a) * (lake.radiusX + 6), wy + 7, math.sin(a) * (lake.radiusZ + 6))
		return CFrame.lookAt(from, boatPos + Vector3.new(0, 2, 0))
	elseif shot == "steeple" then
		local target = steeplePoint()
		local d = Vector3.new(-target.X, 0, -target.Z).Unit
		local from = target + d * 70 + Vector3.new(0, -6, 0)
		return CFrame.lookAt(from, target)
	elseif shot == "title" then
		-- The title screen: from just behind the boat at the dock, low over the water, the
		-- boat and its lantern on the left third, the fog and the far steeple ahead.
		local dock = lake.dockEnd
		local from = Vector3.new(dock.x - 10, wy + 5.5, dock.z - 12)
		local target = steeplePoint()
		local look = CFrame.lookAt(from, Vector3.new(target.X, wy + 6, target.Z))
		return look * CFrame.Angles(0, math.rad(8), 0)
	elseif shot == "top" then
		return CFrame.lookAt(boatPos + Vector3.new(0, Look.Shots.topHeight, 0.01), boatPos)
	end
	return nil
end

function Camera.applyShot(shot: string): (boolean, { [string]: any }?)
	local cam = camera()
	if shot == "reset" then
		shotActive = false
		cam.CameraType = Enum.CameraType.Custom
		local char = Players.LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
		Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		return true, { shot = "reset" }
	end
	local cf = Camera.shotCFrame(shot)
	if cf == nil then
		return false, nil
	end
	shotActive = true
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = Look.Shots.fieldOfView
	cam.CFrame = cf
	local p = cf.Position
	local l = cf.LookVector
	return true, { x = p.X, y = p.Y, z = p.Z, lx = l.X, ly = l.Y, lz = l.Z }
end

function Camera.init()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	gazeRemote = Remotes.wait("Gaze")

	-- Jumping would throw a seated player out of the boat. Humanoid state is set per side,
	-- so the client that owns the character disables it here.
	local function onCharacter(char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	Events.on("NightStarted", function()
		snapToSeat = true
	end)

	-- The view turns with the boat. Without this, a seated first-person camera keeps its world
	-- direction when the boat turns, so after turning for home the player stares at the side of
	-- the boat (found in Studio and by Neon on the finale, 11/26/2026). Each frame, after the
	-- default camera has run, the camera is turned by however much the seat turned. The player's
	-- own mouse or touch look still works on top of it.
	local lastSeat: BasePart? = nil
	local lastYaw = 0
	local function seatYaw(seat: BasePart): number
		local lv = seat.CFrame.LookVector
		return math.atan2(-lv.X, -lv.Z)
	end
	RunService:BindToRenderStep("DeadCalmBoatYaw", Enum.RenderPriority.Camera.Value + 1, function()
		local seatName = BoatClient.mySeat()
		local found = if seatName then BoatClient.part(seatName) else nil
		local seat: BasePart? = if found and found:IsA("BasePart") then found else nil
		if shotActive or seat == nil then
			lastSeat = nil
			return
		end
		local yaw = seatYaw(seat)
		local cam = camera()
		local cf = cam.CFrame
		if lastSeat ~= seat or snapToSeat then
			lastSeat = seat
			lastYaw = yaw
			snapToSeat = false
			local clv = cf.LookVector
			if math.abs(clv.X) + math.abs(clv.Z) > 1e-4 then
				local camYaw = math.atan2(-clv.X, -clv.Z)
				local turn = yaw - camYaw
				if turn > math.pi then
					turn -= 2 * math.pi
				elseif turn < -math.pi then
					turn += 2 * math.pi
				end
				if math.abs(turn) > 1e-4 then
					cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, turn, 0) * cf.Rotation
				end
			end
			return
		end
		local delta = yaw - lastYaw
		lastYaw = yaw
		if delta > math.pi then
			delta -= 2 * math.pi
		elseif delta < -math.pi then
			delta += 2 * math.pi
		end
		if math.abs(delta) < 1e-5 or math.abs(delta) > 1 then
			return -- no turn, or a teleport: leave the view alone
		end
		cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, delta, 0) * cf.Rotation
	end)

	local acc = 0
	local gap = 1 / Config.Net.gazeHz
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < gap then
			return
		end
		acc = 0
		if shotActive then
			-- A fixed shot (the title screen, a capture) keeps its own camera.
			local cam = camera()
			if cam.CameraType ~= Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Scriptable
			end
			return
		end
		if BoatClient.mySeat() == nil then
			return
		end
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
		local look = camera().CFrame.LookVector
		local r = gazeRemote
		if r then
			r:FireServer(math.atan2(look.X, look.Z))
		end
	end)

	if RunService:IsStudio() then
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(Remotes.DEBUG_FOLDER, 10)
			local remote = folder and folder:FindFirstChild("DebugCamera")
			if remote == nil or not remote:IsA("RemoteEvent") then
				return
			end
			remote.OnClientEvent:Connect(function(shot: any)
				if type(shot) ~= "string" then
					return
				end
				local ok, info = Camera.applyShot(shot)
				remote:FireServer(if ok then shot else "failed:" .. shot, info)
			end)
		end)
	end
end

return Camera
