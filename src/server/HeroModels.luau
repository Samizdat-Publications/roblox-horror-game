--!strict
-- M9 hero models: Blender meshes (tools/blender/*.py) laid over the part-built boat, lantern,
-- steeple, shack and dead trees, and handed to the client for the Watcher.
--
-- Each mesh comes from AssetRegistry: AssetService:CreateMeshPartAsync on its meshId, or
-- InsertService:LoadAsset on its Model id if that fails. A mesh that is id 0 or will not
-- load changes nothing: its part-built version stays visible and is the game. A mesh that
-- loads is placed in the exact frame its parts were built in, never collides, never blocks a
-- raycast, and the parts it covers turn see-through but keep their collision (HeroLook.hide).
--
-- Runs once after the world and the boat are built (Main.server.luau, in its own thread, so
-- a slow load never holds up the lobby). HeroModels.status says what loaded, for checks.

local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Config = require(Shared:WaitForChild("Config"))
local HeroLook = require(Shared:WaitForChild("HeroLook"))
local Look = require(Shared:WaitForChild("Look"))

local world = script.Parent:WaitForChild("world")
local Parts = require(world:WaitForChild("Parts"))
local Landmarks = require(world:WaitForChild("Landmarks"))
local Dock = require(world:WaitForChild("Dock"))

local HeroModels = {}

-- name -> "mesh" | "model" | "fallback: <why>"
HeroModels.status = {} :: { [string]: string }

local templates: { [string]: MeshPart } = {}

local function vec(t: { number }?, default: Vector3): Vector3
	if t == nil or #t < 3 then
		return default
	end
	return Vector3.new(t[1], t[2], t[3])
end

-- One loaded copy of a hero mesh, sized and set up, not parented. Nil when it is id 0 or
-- does not load (the reason goes in HeroModels.status).
local function template(name: string): MeshPart?
	local have = templates[name]
	if have then
		return have
	end
	local e = AssetRegistry.get(name)
	if e == nil or e.id == 0 then
		HeroModels.status[name] = "fallback: id 0"
		return nil
	end
	local part: MeshPart? = nil
	local how = "mesh"
	local meshId = e.meshId
	if meshId and meshId ~= 0 then
		local ok, res = pcall(function()
			return AssetService:CreateMeshPartAsync(
				(Content :: any).fromAssetId(meshId),
				{ CollisionFidelity = Enum.CollisionFidelity.Box }
			)
		end)
		if ok and typeof(res) == "Instance" and res:IsA("MeshPart") then
			part = res
		else
			warn("[DeadCalm] hero " .. name .. ": mesh load failed, trying the model (" .. tostring(res) .. ")")
		end
	end
	if part == nil then
		how = "model"
		local ok, res = pcall(function()
			return InsertService:LoadAsset(e.id)
		end)
		if ok and typeof(res) == "Instance" then
			local found = res:FindFirstChildWhichIsA("MeshPart", true)
			if found then
				found.Parent = nil
				part = found
			end
			res:Destroy()
		end
	end
	if part == nil then
		HeroModels.status[name] = "fallback: load failed"
		warn("[DeadCalm] hero " .. name .. " did not load; the part-built version stays")
		return nil
	end
	local p = part :: MeshPart
	p.Name = HeroLook.PREFIX .. name
	p.Size = vec(e.size, p.Size)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.Color = Color3.new(1, 1, 1) -- vertex colours carry the palette
	p.Material = HeroLook.Material[name] or Enum.Material.SmoothPlastic
	templates[name] = p
	HeroModels.status[name] = how
	return p
end

local function centerOf(name: string): Vector3
	local e = AssetRegistry.get(name)
	return vec(e and e.center, Vector3.zero)
end

local function hide(part: Instance)
	if part:IsA("BasePart") then
		part.Transparency = 1
		part:SetAttribute(HeroLook.HIDDEN_ATTR, true)
	end
end

-- Place a copy of `name` at frame * center, anchored, in `parent`. Nil when not loaded.
local function placeAt(name: string, frame: CFrame, parent: Instance): MeshPart?
	local t = template(name)
	if t == nil then
		return nil
	end
	local p = t:Clone()
	p.CFrame = frame * CFrame.new(centerOf(name)) * HeroLook.MESH_TURN
	p.Parent = parent
	return p
end

----------------------------------------------------------------------------------------
-- The boat

-- Weld a placed mesh to the hull so it rides with the boat.
local function ride(p: MeshPart, hull: BasePart)
	p.Anchored = false
	p.CollisionGroup = "Boat"
	local w = Instance.new("WeldConstraint")
	w.Part0 = hull
	w.Part1 = p
	w.Parent = p
end

function HeroModels.applyBoat(b: any)
	local model: Model, hull: BasePart = b.model, b.hull
	for _, name in { "BoatShell", "BoatInterior", "Lantern" } do
		local p = placeAt(name, hull.CFrame, model)
		if p == nil then
			continue
		end
		ride(p, hull)
		if name == "BoatShell" then
			-- Plain mesh: the boat paint colours it. Start from the planks' colour now (the host's
			-- paint may already be on), and tell Cosmetics what bare wood is.
			p.Name = HeroLook.SHELL_PART
			p:SetAttribute("DeadCalmWood", Look.Palette.boatWood)
			local side = model:FindFirstChild("SidePort")
			p.Color = if side and side:IsA("BasePart") then side.Color else Look.Palette.boatWood
		elseif name == "Lantern" then
			-- Like the part-built post: no black wedge of shadow down the boat.
			p.CastShadow = false
		end
		for _, pn in HeroLook.hide[name] or {} do
			local part = model:FindFirstChild(pn)
			if part then
				hide(part)
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- The world

local function applySteeple(root: Instance)
	local folder = root:FindFirstChild("Landmarks")
	local steeple = folder and folder:FindFirstChild("Steeple")
	if steeple == nil then
		return
	end
	local mesh = placeAt("Steeple", Landmarks.steepleFrame(Config, Parts), steeple)
	if mesh == nil then
		return
	end
	for _, d in steeple:GetChildren() do
		if d ~= mesh and not HeroLook.steepleKeep[d.Name] then
			hide(d)
		end
	end
end

local function applyShack(root: Instance)
	local dock = root:FindFirstChild("Dock")
	local shack = dock and dock:FindFirstChild("Shack")
	if shack == nil then
		return
	end
	if placeAt("Shack", Dock.shackBase(Config), shack) == nil then
		return
	end
	for _, pn in HeroLook.hide.Shack do
		local part = shack:FindFirstChild(pn)
		if part then
			hide(part)
		end
	end
end

-- The two ends of a Shore beam (built from a to b, a little longer so joints overlap).
local function beamEnds(beam: BasePart): (Vector3, Vector3)
	local len = beam.Size.Z - beam.Size.X * 0.6
	return beam.CFrame * Vector3.new(0, 0, len / 2), beam.CFrame * Vector3.new(0, 0, -len / 2)
end

local function applyTrees(root: Instance)
	local shore = root:FindFirstChild("Shore")
	local trees = shore and shore:FindFirstChild("Trees")
	if trees == nil then
		return
	end
	local variants: { string } = {}
	for _, name in HeroLook.TREE_VARIANTS do
		if template(name) then
			table.insert(variants, name)
		end
	end
	if #variants == 0 then
		return
	end
	for _, tree in trees:GetChildren() do
		if not (tree:IsA("Model") and string.sub(tree.Name, -4) == "Dead") then
			continue
		end
		local trunk, top = tree:FindFirstChild("Trunk"), tree:FindFirstChild("TrunkTop")
		if not (trunk and trunk:IsA("BasePart") and top and top:IsA("BasePart")) then
			continue
		end
		local p0, p1 = beamEnds(trunk)
		local _, p2 = beamEnds(top)
		local h = (p1 - p0).Magnitude + (p2 - p1).Magnitude
		local index = tonumber(string.match(tree.Name, "%d+")) or 1
		local name = variants[(index % #variants) + 1]
		local t = template(name) :: MeshPart
		local k = h / HeroLook.TREE_HEIGHT
		local p = t:Clone()
		p.Size = t.Size * k
		local yaw = (index * 2.39996) % (2 * math.pi) -- golden-angle turns, so neighbours differ
		p.CFrame = CFrame.new(p0) * CFrame.Angles(0, yaw, 0) * CFrame.new(centerOf(name) * k) * HeroLook.MESH_TURN
		p.Parent = tree
		for _, d in tree:GetChildren() do
			if d ~= p then
				hide(d)
			end
		end
	end
end

-- Copies of the meshes the client dresses itself (the Watcher), in ReplicatedStorage.
local function shareWithClients()
	local t = template("Watcher")
	if t == nil then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild(HeroLook.FOLDER)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = HeroLook.FOLDER
		folder.Parent = ReplicatedStorage
	end
	local copy = t:Clone()
	copy.Name = "Watcher"
	copy:SetAttribute("CenterX", centerOf("Watcher").X)
	copy:SetAttribute("CenterY", centerOf("Watcher").Y)
	copy:SetAttribute("CenterZ", centerOf("Watcher").Z)
	copy.Parent = folder
end

function HeroModels.applyWorld(root: Instance)
	applySteeple(root)
	applyShack(root)
	applyTrees(root)
end

-- Everything, once. Never errors: a failure leaves that piece part-built.
function HeroModels.start(worldRoot: Instance?, boat: any?)
	local ok, err = pcall(function()
		shareWithClients()
		if boat then
			HeroModels.applyBoat(boat)
		end
		if worldRoot then
			HeroModels.applyWorld(worldRoot)
		end
	end)
	if not ok then
		warn("[DeadCalm] hero models: " .. tostring(err))
	end
end

return HeroModels
