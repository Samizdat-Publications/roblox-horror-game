--!strict
-- Client view of the boat and the world anchors the server built. Everything is looked up
-- lazily and re-resolved when missing, so it works with streaming and late replication.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BoatClient = {}

BoatClient.BOAT_NAME = "DeadCalmBoat"
BoatClient.WORLD_NAME = "DeadCalmWorld"

function BoatClient.model(): Model?
	local m = Workspace:FindFirstChild(BoatClient.BOAT_NAME)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

function BoatClient.part(name: string): BasePart?
	local m = BoatClient.model()
	if m == nil then
		return nil
	end
	local p = m:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

function BoatClient.hull(): BasePart?
	return BoatClient.part("Hull")
end

-- Name of the seat the local player sits in, from the attribute BoatService keeps.
function BoatClient.mySeat(): string?
	local m = BoatClient.model()
	local me = Players.LocalPlayer
	if m == nil or me == nil then
		return nil
	end
	for _, child in m:GetChildren() do
		if child:IsA("Seat") and child:GetAttribute("OccupantUserId") == me.UserId then
			return child.Name
		end
	end
	return nil
end

function BoatClient.attr(name: string): any
	local m = BoatClient.model()
	return if m then m:GetAttribute(name) else nil
end

-- A part in the world folder by path, e.g. find("Dock", "Shack", "ShackRadio").
function BoatClient.find(...: string): BasePart?
	local node: Instance? = Workspace:FindFirstChild(BoatClient.WORLD_NAME)
	for _, name in { ... } do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	if node and node:IsA("BasePart") then
		return node
	end
	return nil
end

-- Heading of the boat (atan2(look.x, look.z)) and its position, or nil.
function BoatClient.pose(): (Vector3?, number?)
	local h = BoatClient.hull()
	if h == nil then
		return nil, nil
	end
	local look = h.CFrame.LookVector
	return h.Position, math.atan2(look.X, look.Z)
end

return BoatClient
