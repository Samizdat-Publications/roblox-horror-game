--!strict
-- The rulebook taped inside the boat (DESIGN.md, The book and Amendments). Opens with R,
-- gamepad D-pad left, the Book button (HUD or MobileButtons) or by clicking the book taped
-- in the boat. It covers most of the view and stops your hands (BookState).
-- The page is tonight's: Rule 0, then every rule taped in so far, in rule order, each held
-- by tape (fresh tape and a pencil note for the rule taped in tonight). An amended rule shows
-- the printed line crossed out and the owner's new line under it in his second ink.
-- Every line of text comes from Core.Rulebook (Rulebook.page, Rulebook.TEXT).
-- On the title screen the same page shows the Lake Rules as printed, all seven ("lake").
-- Polish 3: an amendment that adds to a rule (its text starts with "And", like the
-- Neighbor's "AND ROW AWAY FROM IT") leaves the printed rule unstruck and adds the new line
-- in red ink under it; one that replaces the rule strikes the printed line. The rules are
-- not rotated (rotation stops clipping), the tape is translucent strips across the top
-- corners, and the list scrolls inside the paper.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local Rulebook = require(Shared:WaitForChild("Core"):WaitForChild("Rulebook")) :: any

local client = script.Parent.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local BookState = require(script.Parent:WaitForChild("BookState"))

local Rulebook_ = {}

Rulebook_.ALL = { "Hum", "WrongCatch", "Neighbor", "Knocking", "Watcher", "Finale" }

local gui: ScreenGui? = nil
local heading: TextLabel? = nil
local list: ScrollingFrame? = nil
local lastLines: { { [string]: any } } = {}

-- True when an amendment adds to the printed rule rather than replacing it.
function Rulebook_.additive(text: string): boolean
	local head = string.lower(string.sub(text, 1, 6))
	return string.find(head, "^and%s") ~= nil or string.find(head, "^also%s") ~= nil
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Tonight's page as plain lines: { number, text, amended?, fresh }. Text is English.
function Rulebook_.lines(page: string): { { [string]: any } }
	local rules: { string } = {}
	local amendments: { [string]: string } = {}
	local fresh: { [string]: boolean } = {}
	if page == "lake" then
		rules = table.clone(Rulebook_.ALL)
	else
		local info = LobbyClient.get().night
		if info then
			rules = table.clone(info.rules)
			amendments = info.amendments
			for _, r in info.newRules do
				fresh[r] = true
			end
		else
			rules = table.clone(ViewState.get().rules or {})
		end
	end
	local out = {}
	for _, line in Rulebook.page(Config, rules, amendments) do
		table.insert(out, {
			rule = line.rule,
			number = line.number,
			text = Rulebook.TEXT[line.text] or line.text,
			amended = if line.amended then Rulebook.TEXT[line.amended] or line.amended else nil,
			fresh = fresh[line.rule] == true,
		})
	end
	return out
end

local function clearList(l: ScrollingFrame)
	for _, c in l:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- Rotated strips can escape a scroll frame's clipping, so a strip is shown only while it is
-- inside the visible part of the list.
local function cullTape()
	local l = list
	if l == nil then
		return
	end
	local top = l.AbsolutePosition.Y
	local bottom = l.AbsolutePosition.Y + l.AbsoluteSize.Y
	for _, d in l:GetDescendants() do
		if d:IsA("Frame") and d.Name == "Tape" then
			local cy = d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2
			d.Visible = cy >= top and cy <= bottom
		end
	end
end

local function fill(page: string)
	local l, h = list, heading
	if l == nil or h == nil then
		return
	end
	h.Text = if page == "lake" then "The Lake Rules" else "The Lake Rules  (taped in the boat)"
	clearList(l)
	local size = Paper.fit(21, 14, 24)
	local lines = Rulebook_.lines(page)
	lastLines = lines
	for i, line in lines do
		local block = Instance.new("Frame")
		block.Name = "Rule" .. tostring(line.number)
		block.LayoutOrder = i
		block.BackgroundColor3 = Look.UI.paper:Lerp(Color3.new(1, 1, 1), 0.25)
		block.BackgroundTransparency = 0.1
		block.BorderSizePixel = 0
		block.Size = UDim2.new(1, -16, 0, 0)
		block.AutomaticSize = Enum.AutomaticSize.Y
		block.Parent = l
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0, 12)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = block
		local inner = Instance.new("UIListLayout")
		inner.SortOrder = Enum.SortOrder.LayoutOrder
		inner.Padding = UDim.new(0, 4)
		inner.Parent = block
		Paper.tape(block, Vector2.new(0.04, 0.02), line.fresh)
		Paper.tape(block, Vector2.new(0.96, 0.02), line.fresh)

		local t = Paper.text(block, "Printed", "", size, Paper.hand())
		t.LayoutOrder = 1
		t.RichText = true
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.Size = UDim2.fromScale(1, 0)
		if line.amended then
			local adds = Rulebook_.additive(line.amended)
			if adds then
				-- Adds to the rule: the printed line still stands.
				t.Text = esc(line.text)
			else
				-- Replaces it: crossed out in the owner's pen.
				t.Text = "<s>" .. esc(line.text) .. "</s>"
				t.TextTransparency = 0.35
			end
			local a = Paper.text(block, "Amended", line.amended, size + 1, Paper.hand())
			a.LayoutOrder = 2
			a.AutomaticSize = Enum.AutomaticSize.Y
			a.Size = UDim2.fromScale(1, 0)
			a.TextColor3 = Look.Palette.amendInk
			a:SetAttribute("Additive", adds)
		else
			t.Text = esc(line.text)
		end
		if line.fresh then
			local note = Paper.text(block, "Note", "taped in tonight", math.max(12, size - 6))
			note.LayoutOrder = 3
			note.TextColor3 = Look.UI.ink
			note.TextTransparency = 0.4
			note.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	l.CanvasPosition = Vector2.zero
	task.defer(cullTape)
end

-- For checks (DebugBot "book"): what the open page shows.
function Rulebook_.debugState(): { [string]: any }
	local amended, additive = 0, 0
	for _, line in lastLines do
		if line.amended then
			amended += 1
			if Rulebook_.additive(line.amended) then
				additive += 1
			end
		end
	end
	return {
		open = gui ~= nil and (gui :: ScreenGui).Enabled,
		lines = #lastLines,
		amended = amended,
		additive = additive,
	}
end

-- The book you can see in the boat: a little paper block on the thwart by the helm. Click
-- it to open the rulebook (a ClickDetector on a part this client made; Studio must check it
-- fires; R and the Book button do the same).
local function bookInTheBoat()
	local part: BasePart? = nil
	local last = 0
	local function syncVisibility(pp: BasePart)
		local hidden = LobbyClient.get().phase == "Title" or BoatFx.capsizing()
		pp.Transparency = if hidden then 1 else 0
		local cd = pp:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd.MaxActivationDistance = if hidden then 0 else 14
		end
	end
	RunService.Heartbeat:Connect(function()
		local p = part
		if p and p.Parent then
			syncVisibility(p :: BasePart)
		end
		local now = os.clock()
		if now - last < 0.1 then
			return
		end
		last = now
		local hull = BoatClient.hull()
		if hull == nil then
			return
		end
		if p == nil or p.Parent == nil then
			local np = Instance.new("Part")
			np.Name = "DeadCalmRulebookInBoat"
			np.Size = Vector3.new(1.2, 0.15, 1.6)
			np.Color = Look.UI.paper
			np.Material = Enum.Material.SmoothPlastic
			np.Anchored = true
			np.CanCollide = false
			np.CanTouch = false
			np.CastShadow = false
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 14
			cd.Parent = np
			cd.MouseClick:Connect(function()
				if LobbyClient.get().phase ~= "Title" and not BoatFx.capsizing() then
					BookState.open("rules")
				end
			end)
			np.Parent = Workspace
			part = np
			p = np
		end
		local pp = p :: BasePart
		syncVisibility(pp)
		-- On the stern thwart, beside the helm seat, a little crooked.
		pp.CFrame = hull.CFrame * CFrame.new(1.6, 1.25, 4.2) * CFrame.Angles(0, 0.35, 0)
	end)
end

function Rulebook_.init()
	local g, _sheet, body, close = Paper.bookPage("DeadCalmRulebook", 20, "The Lake Rules")
	gui = g
	heading = (g:FindFirstChild("Sheet") :: Frame):FindFirstChild("Heading") :: TextLabel
	local l = Instance.new("ScrollingFrame")
	l.Name = "Rules"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ScrollBarThickness = 6
	l.ScrollBarImageColor3 = Look.UI.ink
	l.CanvasSize = UDim2.new()
	l.AutomaticCanvasSize = Enum.AutomaticSize.Y
	l.ScrollingDirection = Enum.ScrollingDirection.Y
	l.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = l
	list = l
	l:GetPropertyChangedSignal("CanvasPosition"):Connect(cullTape)
	l:GetPropertyChangedSignal("AbsoluteSize"):Connect(cullTape)
	close.Activated:Connect(function()
		BookState.close()
	end)
	local dim = g:FindFirstChild("Dim") :: TextButton
	dim.Activated:Connect(function()
		BookState.close()
	end)
	BookState.onChange(function(page)
		local open = page == "rules" or page == "lake"
		if open then
			fill(page :: string)
		end
		g.Enabled = open
	end)
	-- A new page taped in while the book is open (night start): refill it.
	LobbyClient.onChange(function()
		local page = BookState.current()
		if page == "rules" then
			fill(page)
		end
	end)
	bookInTheBoat()
end

return Rulebook_
