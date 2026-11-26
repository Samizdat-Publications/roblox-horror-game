--!strict
-- The night's title card at the start, and the clear or fail card at the end, with a short
-- dry tally per player from NightResult. Simple for now (S2); the rulebook, the tapes on
-- screen and the full end-of-night card come in S4.

local Players = game:GetService("Players")

local client = script.Parent.Parent
local Events = require(client:WaitForChild("Events"))
local Paper = require(script.Parent:WaitForChild("Paper"))

local NightCards = {}

NightCards.FAIL_TEXT = {
	QuotaShort = "Five o'clock and the cooler is short.",
	CrewLost = "The lake has the whole crew.",
	Sunk = "The boat went down.",
} :: { [string]: string }

local endCard: Frame? = nil
local endHead: TextLabel? = nil
local endBody: TextLabel? = nil
local nightNumber = 1
local titleToken = 0

local function plural(n: number, one: string, many: string): string
	return if n == 1 then one else string.format(many, n)
end

-- Dry lines about one player's night. Empty list for a quiet night.
function NightCards.tallyLines(t: { [string]: any }): { string }
	local out = {}
	local n = tonumber(t.brokeSilence) or 0
	if n > 0 then
		table.insert(out, plural(n, "Broke the silence once", "Broke the silence %d times"))
	end
	n = tonumber(t.keptWrong) or 0
	if n > 0 then
		table.insert(out, plural(n, "Kept a fish that was not in the book", "Kept %d fish that were not in the book"))
	end
	n = math.floor(tonumber(t.bailedSeconds) or 0)
	if n > 0 then
		table.insert(out, string.format("Bailed for %d seconds", n))
	end
	n = tonumber(t.knocksAnswered) or 0
	if n > 0 then
		table.insert(out, plural(n, "Knocked back once", "Knocked back %d times"))
	end
	n = tonumber(t.timesStaredAtWatcher) or 0
	if n > 0 then
		table.insert(out, plural(n, "Stared at the shore once", "Stared at the shore %d times"))
	end
	n = tonumber(t.deaths) or 0
	if n > 0 then
		table.insert(out, "Went into the lake")
	end
	return out
end

local function nameOf(id: any): string
	local p = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
	return if p then p.DisplayName else "A crewman"
end

local function showEnd(cleared: boolean, reason: string?, result: any)
	local card, head, body = endCard, endHead, endBody
	if card == nil or head == nil or body == nil then
		return
	end
	head.Text = if cleared
		then string.format("Dawn. Night %d is done.", nightNumber)
		else string.format("Night %d failed.", nightNumber)
	local lines = {}
	if not cleared then
		table.insert(lines, NightCards.FAIL_TEXT[reason or ""] or "The night got away from you.")
	end
	if type(result) == "table" then
		table.insert(
			lines,
			string.format("Banked %s of %s.", tostring(result.banked or 0), tostring(result.quota or 0))
		)
		table.insert(lines, string.format("Fish landed: %s.", tostring(result.caught or 0)))
		table.insert(lines, "")
		for _, t in (if type(result.tallies) == "table" then result.tallies else {}) do
			if type(t) == "table" then
				local tl = NightCards.tallyLines(t)
				table.insert(
					lines,
					nameOf(t.player) .. ": " .. (if #tl > 0 then table.concat(tl, ". ") .. "." else "A quiet night.")
				)
			end
		end
	end
	if not cleared then
		table.insert(lines, "")
		table.insert(lines, "The lake gives you this night again.")
	end
	body.Text = table.concat(lines, "\n")
	card.Visible = true
end

function NightCards.init()
	local gui = Paper.gui("DeadCalmNightCards", 10)

	local t =
		Paper.sheet(gui, "Title", UDim2.fromOffset(300, 64), UDim2.fromScale(0.5, 0.22), Vector2.new(0.5, 0.5), 10)
	t.Rotation = -1.5
	t.Visible = false
	local tt = Paper.text(t, "Text", "", 30, Paper.hand())
	tt.Size = UDim2.fromScale(1, 1)
	tt.TextXAlignment = Enum.TextXAlignment.Center
	tt.TextYAlignment = Enum.TextYAlignment.Center

	local e = Paper.sheet(gui, "End", UDim2.fromOffset(520, 340), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5), 18)
	e.BackgroundTransparency = 0.03
	e.Rotation = 0.8
	e.Visible = false
	endCard = e
	local h = Paper.text(e, "Head", "", 30, Paper.hand())
	h.Size = UDim2.new(1, 0, 0, 40)
	endHead = h
	local b = Paper.text(e, "Body", "", 18)
	b.Position = UDim2.fromOffset(0, 50)
	b.Size = UDim2.new(1, 0, 1, -50)
	endBody = b

	Events.on("NightStarted", function(ev)
		local data = ev.data or {}
		nightNumber = tonumber(data.night) or nightNumber
		e.Visible = false
		titleToken += 1
		local token = titleToken
		tt.Text = string.format("Night %d", nightNumber)
		t.Visible = true
		task.delay(4, function()
			if titleToken == token then
				t.Visible = false
			end
		end)
	end)
	Events.on("NightCleared", function(ev)
		local data = ev.data or {}
		showEnd(true, nil, data.result)
	end)
	Events.on("NightFailed", function(ev)
		local data = ev.data or {}
		showEnd(false, if type(data.reason) == "string" then data.reason else nil, data.result)
	end)
end

return NightCards
