--!strict
-- Cosmetics in the world (docs/DESIGN.md, Progress and cosmetics). Earned by playing, never
-- bought. Which ones a player has is Core.Profile's call; this module only shows them:
--   * lantern: the boat lantern's light and its glowing ball
--   * paint: the boat's outer planks (sides, transom, bow)
--   * hat: a simple part hat on the character's head (an Accessory, so the floating hat on
--     a death is this hat)
-- The boat is shared, so it wears the host's lantern and paint (LobbyService says who).
-- Names, how-to-earn lines and swatch colors go to the client in the Profile payload, so
-- the Locker panel never needs its own copy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local BoatService = require(script.Parent:WaitForChild("BoatService"))

local Cosmetics = {}

export type Item = {
	name: string,
	color: Color3, -- the swatch; for a lantern the light, for paint the planks
	glow: Color3?, -- lantern: the glowing ball (deeper than the light; bloom washes it)
	brim: Color3?, -- hat: the brim
}

Cosmetics.ITEMS = {
	lantern = {
		Amber = { name = "Amber", color = Color3.fromRGB(255, 180, 90), glow = Color3.fromRGB(255, 118, 36) },
		BoneWhite = {
			name = "Bone White",
			color = Color3.fromRGB(255, 236, 206),
			glow = Color3.fromRGB(236, 214, 178),
		},
		MarshGreen = {
			name = "Marsh Green",
			color = Color3.fromRGB(196, 226, 120),
			glow = Color3.fromRGB(128, 186, 52),
		},
		BlueHour = {
			name = "Blue Hour",
			color = Color3.fromRGB(150, 182, 255),
			glow = Color3.fromRGB(70, 104, 220),
		},
	},
	paint = {
		BareWood = { name = "Bare Wood", color = Look.Palette.boatWood },
		Oxblood = { name = "Oxblood", color = Color3.fromRGB(96, 32, 28) },
		HullBlack = { name = "Hull Black", color = Color3.fromRGB(30, 30, 32) },
		RobinEgg = { name = "Robin Egg", color = Color3.fromRGB(120, 176, 172) },
	},
	hat = {
		None = { name = "No hat", color = Color3.fromRGB(180, 170, 150) },
		BucketHat = {
			name = "Bucket Hat",
			color = Color3.fromRGB(98, 94, 66),
			brim = Color3.fromRGB(84, 80, 56),
		},
		Souwester = {
			name = "Sou'wester",
			color = Color3.fromRGB(214, 168, 40),
			brim = Color3.fromRGB(196, 150, 32),
		},
	},
} :: { [string]: { [string]: Item } }

Cosmetics.SLOT_NAMES = { lantern = "Lantern", paint = "Boat paint", hat = "Hat" } :: { [string]: string }

-- The planks that take paint (the floor, thwarts and trim stay wood).
-- HeroBoatShell is the M9 hull mesh (HeroModels) when it loads; it carries DeadCalmWood itself.
Cosmetics.PAINTED = { "SidePort", "SideStarboard", "Transom", "BowPort", "BowStarboard", "HeroBoatShell" }

Cosmetics.HAT_NAME = "DeadCalmHat"
Cosmetics.STOWED = "DeadCalmStowed" -- attribute on an avatar hat hidden under ours

function Cosmetics.item(slot: string, id: string): Item?
	local s = Cosmetics.ITEMS[slot]
	return if s then s[id] else nil
end

-- The catalog for the client: every item in Config order, with whether this profile has it.
function Cosmetics.catalog(profile: any, unlockText: { [string]: string }): { { [string]: any } }
	local out = {}
	for _, slot in { "lantern", "paint", "hat" } do
		for _, id in (Config.Cosmetics :: any)[slot] or {} do
			local it = Cosmetics.item(slot, id)
			local got = profile.unlocked[slot] ~= nil and profile.unlocked[slot][id] == true
			table.insert(out, {
				slot = slot,
				id = id,
				name = if it then it.name else id,
				color = if it then it.color else Color3.new(0.5, 0.5, 0.5),
				text = unlockText[slot .. "." .. id] or "",
				unlocked = got,
				equipped = profile.equipped[slot] == id,
			})
		end
	end
	return out
end

----------------------------------------------------------------------------------------
-- The boat

local appliedBoat = { lantern = "", paint = "" }

function Cosmetics.applyBoat(lantern: string?, paint: string?)
	local ok, b = pcall(BoatService.get)
	if not ok or b == nil then
		return
	end
	local L = Cosmetics.item("lantern", lantern or "Amber") or Cosmetics.ITEMS.lantern.Amber
	b.lanternLight.Color = L.color
	b.lanternGlow.Color = L.glow or L.color
	local P = Cosmetics.item("paint", paint or "BareWood") or Cosmetics.ITEMS.paint.BareWood
	for _, name in Cosmetics.PAINTED do
		local part = b.model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			if part:GetAttribute("DeadCalmWood") == nil then
				part:SetAttribute("DeadCalmWood", part.Color)
			end
			if paint == nil or paint == "BareWood" then
				local wood = part:GetAttribute("DeadCalmWood")
				part.Color = if typeof(wood) == "Color3" then wood else P.color
			else
				part.Color = P.color
			end
		end
	end
	appliedBoat.lantern = lantern or "Amber"
	appliedBoat.paint = paint or "BareWood"
	b.model:SetAttribute("Lantern", appliedBoat.lantern)
	b.model:SetAttribute("Paint", appliedBoat.paint)
end

function Cosmetics.boatState(): { lantern: string, paint: string }
	return table.clone(appliedBoat)
end

----------------------------------------------------------------------------------------
-- Hats

local function quietPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder -- runs along the part's X axis
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	return p
end

-- The handle's X axis points down the head (see the attachment below), so +X is lower.
local SHAPES: { [string]: { crown: Vector3, brim: Vector3, brimOffset: CFrame, lift: number } } = {
	BucketHat = {
		crown = Vector3.new(0.75, 1.35, 1.35),
		brim = Vector3.new(0.12, 1.9, 1.9),
		brimOffset = CFrame.new(0.32, 0, 0),
		lift = 0.3,
	},
	Souwester = {
		crown = Vector3.new(0.7, 1.3, 1.3),
		brim = Vector3.new(0.12, 2.0, 2.0),
		-- A little lower at the back, like a rain hat.
		brimOffset = CFrame.new(0.3, 0, 0.12) * CFrame.Angles(0, math.rad(8), 0),
		lift = 0.28,
	},
}

local function stowAvatarHats(character: Model, stow: boolean)
	for _, acc in character:GetChildren() do
		if acc:IsA("Accessory") and acc.Name ~= Cosmetics.HAT_NAME and acc.AccessoryType == Enum.AccessoryType.Hat then
			local h = acc:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then
				if stow and h:GetAttribute(Cosmetics.STOWED) == nil then
					h:SetAttribute(Cosmetics.STOWED, h.Transparency)
					h.Transparency = 1
				elseif not stow then
					local t = h:GetAttribute(Cosmetics.STOWED)
					if type(t) == "number" then
						h.Transparency = t
					end
					h:SetAttribute(Cosmetics.STOWED, nil)
				end
			end
		end
	end
end

local function buildHat(id: string): Accessory?
	local shape = SHAPES[id]
	local it = Cosmetics.item("hat", id)
	if shape == nil or it == nil then
		return nil
	end
	local acc = Instance.new("Accessory")
	acc.Name = Cosmetics.HAT_NAME
	acc.AccessoryType = Enum.AccessoryType.Hat
	local handle = quietPart("Handle", shape.crown, it.color)
	handle.CFrame = CFrame.new()
	handle.Parent = acc
	local brim = quietPart("Brim", shape.brim, it.brim or it.color)
	brim.CFrame = handle.CFrame * shape.brimOffset
	brim.Parent = handle
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = brim
	w.Parent = handle
	-- Matches the head's HatAttachment; turns the cylinders upright and lifts the crown.
	local att = Instance.new("Attachment")
	att.Name = "HatAttachment"
	att.CFrame = CFrame.new(shape.lift, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
	att.Parent = handle
	acc:SetAttribute("HatId", id)
	return acc
end

-- Puts the chosen hat on the player's character (or takes ours off for "None").
function Cosmetics.applyHat(player: Player, id: string?)
	local character = player.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local old = character:FindFirstChild(Cosmetics.HAT_NAME)
	if old and old:GetAttribute("HatId") == id then
		return
	end
	if old then
		old:Destroy()
	end
	if id == nil or id == "None" or humanoid == nil then
		stowAvatarHats(character, false)
		return
	end
	local acc = buildHat(id)
	if acc == nil then
		stowAvatarHats(character, false)
		return
	end
	local ok, err = pcall(function()
		humanoid:AddAccessory(acc)
	end)
	if not ok then
		acc:Destroy()
		warn("[DeadCalm] hat: " .. tostring(err))
		return
	end
	-- No matching attachment on this head: weld it on top by hand.
	local handle = acc:FindFirstChild("Handle") :: BasePart?
	local head = character:FindFirstChild("Head")
	if handle and head and head:IsA("BasePart") then
		local welded = false
		for _, d in handle:GetChildren() do
			if d:IsA("JointInstance") then
				welded = true
			end
		end
		if not welded then
			handle.CFrame = head.CFrame
				* CFrame.new(0, head.Size.Y / 2 + (SHAPES[id] :: any).lift, 0)
				* CFrame.Angles(0, 0, math.rad(-90))
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = head
			wc.Part1 = handle
			wc.Parent = handle
		end
	end
	stowAvatarHats(character, true)
end

return Cosmetics
