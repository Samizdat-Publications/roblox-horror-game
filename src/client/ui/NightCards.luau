--!strict
-- The night's cards (S4):
--   * Night start (Polish 3, Neon: the old card covered half the screen for 13 s): a small
--     strip at the top, "Night N" in the owner's hand and one or two short lines (which try,
--     the quota, on the last night the owner's fish, the rule taped in tonight, "the book
--     changed" in his second ink). Gone after START_SECONDS, on a tap or click, or at once
--     when the finale's bell rings. The tape's words are no longer printed (the tape plays).
--   * Night end: cleared or failed, banked, fish landed, a dry tally line per player, then
--     what comes next from Core.Run's outcome (next night, the same night again with the
--     tries left, or the run is over).
--   * The run's end: the run-cleared card (with the owner's run-cleared tape) or the
--     run-over card, the run's totals, and for the host a button back to the title.
-- The death card goes first: the end card waits for it, then a few seconds of the drowned
-- view for a drowned player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))
local Rulebook = require(Shared:WaitForChild("Core"):WaitForChild("Rulebook")) :: any

local client = script.Parent.Parent
local Events = require(client:WaitForChild("Events"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local DeathCard = require(script.Parent:WaitForChild("DeathCard"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local ViewState = require(client:WaitForChild("ViewState"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local Finale = require(client:WaitForChild("fx"):WaitForChild("Finale"))

local NightCards = {}

-- Seconds of the drowned view (the boat from above, the outlines) between a death card and
-- the night's end card, when the local player is one of the drowned.
NightCards.DROWNED_BEAT = 4
NightCards.START_SECONDS = 4 -- the night start strip
-- Polish round 2 (Neon finale v7: tiny cramped text on the end screens, the HUD back on top of
-- the victory card, the card over the dock at once):
--   * the end cards size to their text: a width that fits the screen (CARD_WIDTH), the height
--     from the text (AutomaticSize); no UIScale shrinking them on phones any more;
--   * body text is Paper.fit(BODY_TEXT): at least 18 px on the 705 by 338 phone, larger on
--     big screens; on short screens (under COMPACT_BELOW px tall) the stat lines pair up;
--   * the gameplay HUD hides while any end card is up (HUD key HUD_KEY);
--   * the run-cleared card waits for the dawn banner, then Look.Dawn.runCardAfterBanner more
--     seconds of the dock in daylight; the banner is put away as the card comes in.
NightCards.BODY_TEXT = { 20, 18, 24 } -- Paper.fit(base, lo, hi)
NightCards.HEAD_TEXT = { 32, 22, 40 }
NightCards.CARD_WIDTH = { share = 0.9, min = 300, max = 640 }
NightCards.COMPACT_BELOW = 450
NightCards.HUD_KEY = "EndCard"
NightCards.BANNER_WAIT = 12 -- at most this long waiting for the dawn banner before the run card

NightCards.FAIL_TEXT = {
	QuotaShort = "Five o'clock and the cooler is short.",
	CrewLost = "The lake has the whole crew.",
	Sunk = "The boat went down.",
	SpecialOrder = "Dawn, and no Steeple Cat. The owner wanted one fish.",
	NotHome = "Dawn caught you on the water with the owner's fish.",
} :: { [string]: string }

local TRY = { [2] = "Second try.", [3] = "Third try.", [4] = "Fourth try." }

local endCard: Frame? = nil
local endHead: TextLabel? = nil
local endBody: TextLabel? = nil
local startCard: Frame? = nil
local startHead: TextLabel? = nil
local startBody: TextLabel? = nil
local runCard: Frame? = nil
local runHead: TextLabel? = nil
local runBody: TextLabel? = nil
local runButton: TextButton? = nil
local nightNumber = 1
local endToken = 0
local startToken = 0

local TIMES = { [2] = "twice", [3] = "three times", [4] = "four times", [5] = "five times" }

-- "once", "twice", "three times", then "%d times".
local function plural(n: number, one: string, many: string): string
	if n == 1 then
		return one
	end
	local word = TIMES[n]
	if word and string.find(many, "%d times", 1, true) then
		return (string.gsub(many, "%%d times", word))
	end
	return string.format(many, n)
end

local function compactScreen(): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and cam.ViewportSize.Y < NightCards.COMPACT_BELOW
end

-- On short screens the stat lines pair up ("A   B") so the card fits the screen.
function NightCards.pairLines(lines: { string }): { string }
	local out = {}
	local i = 1
	while i <= #lines do
		local a, b = lines[i], lines[i + 1]
		if b ~= nil and a ~= "" and b ~= "" then
			table.insert(out, a .. "   " .. b)
			i += 2
		else
			table.insert(out, a)
			i += 1
		end
	end
	return out
end

-- Sizes an end card to the screen and its text: the width from the viewport, text sizes from
-- Paper.fit, the height from the text itself.
local function fitCard(card: Frame, head: TextLabel, body: TextLabel)
	local cam = workspace.CurrentCamera
	local vw = if cam then cam.ViewportSize.X else 800
	local W = NightCards.CARD_WIDTH
	card.Size = UDim2.fromOffset(math.floor(math.clamp(vw * W.share, W.min, W.max)), 0)
	local H, B = NightCards.HEAD_TEXT, NightCards.BODY_TEXT
	head.TextSize = Paper.fit(H[1], H[2], H[3])
	body.TextSize = Paper.fit(B[1], B[2], B[3])
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

-- What comes after this night, in one line, from Core.Run's outcome.
function NightCards.nextLine(outcome: string?, run: { [string]: any }?, nights: number?): string?
	local endless = run ~= nil and run.mode == "Endless"
	if outcome == "NextNight" and endless then
		local n = tonumber((run :: any).night)
		return if n then string.format("Endless night %d next. It gets worse.", n) else "The next night is coming."
	elseif outcome == "RunOver" and endless then
		return "The lake does not give Endless nights back. The run is over."
	elseif outcome == "NextNight" then
		local n = if run then tonumber(run.night) else nil
		if n and nights and n >= nights then
			return "Last night next. The owner has a special order."
		end
		return if n then string.format("Night %d next.", n) else "The next night is coming."
	elseif outcome == "RetryNight" then
		local left = if run then tonumber(run.retriesLeft) else nil
		if left == nil then
			return "The lake gives you this night again."
		elseif left == 0 then
			return "The lake gives you this night again. That was the last one it gives."
		end
		return string.format(
			"The lake gives you this night again. %s left after this.",
			if left == 1 then "One more try" else tostring(left) .. " more tries"
		)
	elseif outcome == "RunOver" then
		return "No more tries. The run is over."
	end
	return nil
end

-- Waits (at most `seconds`) for the lobby to report this night's outcome.
local function awaitOutcome(seconds: number): LobbyClient.State
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		local s = LobbyClient.get()
		if s.outcome ~= nil or not s.runNight then
			return s
		end
		task.wait(0.1)
	end
	return LobbyClient.get()
end

local function showEnd(cleared: boolean, reason: string?, result: any, s: LobbyClient.State)
	local card, head, body = endCard, endHead, endBody
	if card == nil or head == nil or body == nil then
		return
	end
	local nightName =
		string.format(if s.run and s.run.mode == "Endless" then "Endless night %d" else "Night %d", nightNumber)
	head.Text = if cleared then string.format("Dawn. %s is done.", nightName) else nightName .. " failed."
	local lines = {}
	if not cleared then
		table.insert(lines, NightCards.FAIL_TEXT[reason or ""] or "The night got away from you.")
	end
	if type(result) == "table" then
		local banked = string.format("Banked %s of %s.", tostring(result.banked or 0), tostring(result.quota or 0))
		local landed = string.format("Fish landed: %s.", tostring(result.caught or 0))
		if compactScreen() then
			table.insert(lines, banked .. " " .. landed)
		else
			table.insert(lines, banked)
			table.insert(lines, landed)
			table.insert(lines, "")
		end
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
	local nextLine = if s.runNight then NightCards.nextLine(s.outcome, s.run, s.nights) else nil
	if nextLine then
		table.insert(lines, "")
		table.insert(lines, nextLine)
	elseif not cleared and not s.runNight then
		table.insert(lines, "")
		table.insert(lines, "The lake gives you this night again.")
	end
	body.Text = table.concat(lines, "\n")
	fitCard(card, head, body)
	card.Visible = true
end

-- The run's end: cleared (the owner's run-cleared tape) or over.
local function showRun(cleared: boolean, s: LobbyClient.State)
	local card, head, body, btn = runCard, runHead, runBody, runButton
	if card == nil or head == nil or body == nil or btn == nil then
		return
	end
	local e = endCard
	if e then
		e.Visible = false
	end
	head.Text = if cleared then "Dawn. The run is cleared." else "The run is over."
	local t = s.totals or {}
	local lines = {}
	if t.mode == "Endless" then
		local best = tonumber(t.bestNight) or 0
		head.Text = "The Endless run is over."
		table.insert(
			lines,
			if best > 0
				then string.format("You lasted to the end of Endless night %d.", best)
				else "The first Endless night took you. It is not like the others."
		)
		table.insert(lines, "")
		local stats = {
			string.format("Fish banked: %s", tostring(t.fishBanked or 0)),
			string.format("Scares lived through: %s", tostring(t.scaresSurvived or 0)),
			string.format("Taken by the lake: %s", tostring(t.deaths or 0)),
		}
		for _, l in (if compactScreen() then NightCards.pairLines(stats) else stats) do
			table.insert(lines, l)
		end
		body.Text = table.concat(lines, "\n")
		btn.Visible = LobbyClient.isHost()
		fitCard(card, head, body)
		card.Visible = true
		AudioDirector.play("night-failed-sting")
		return
	end
	if cleared then
		table.insert(lines, Rulebook.TEXT["Tape.RunCleared"] or "")
	else
		table.insert(lines, "Five nights is a long time on this lake. Start again from night one.")
	end
	table.insert(lines, "")
	local stats = {
		string.format("Nights cleared: %s of %s", tostring(t.nightsCleared or 0), tostring(s.nights or 5)),
		string.format("Fish banked: %s", tostring(t.fishBanked or 0)),
		string.format("Scares lived through: %s", tostring(t.scaresSurvived or 0)),
		string.format("Taken by the lake: %s", tostring(t.deaths or 0)),
		string.format("Difficulty: %s", tostring(t.difficulty or s.difficulty)),
	}
	for _, l in (if compactScreen() then NightCards.pairLines(stats) else stats) do
		table.insert(lines, l)
	end
	body.Text = table.concat(lines, "\n")
	btn.Visible = LobbyClient.isHost()
	fitCard(card, head, body)
	card.Visible = true
	if cleared then
		AudioDirector.play("run-cleared")
		task.delay(1.5, function()
			if card.Visible then
				AudioDirector.playTape("tape-run-cleared")
			end
		end)
	else
		AudioDirector.play("night-failed-sting")
	end
end

-- Hides every card and cancels a pending end card (Studio scenario reset, the title).
function NightCards.hide()
	endToken += 1
	startToken += 1
	for _, c in { endCard, startCard, runCard } do
		if c then
			c.Visible = false
		end
	end
end

local function showStart(night: number)
	local card, head, body = startCard, startHead, startBody
	if card == nil or head == nil or body == nil then
		return
	end
	startToken += 1
	local token = startToken
	-- The lobby's page for this night may land a moment after NightStarted.
	local t0 = os.clock()
	local s = LobbyClient.get()
	while (s.night == nil or s.night.night ~= night) and os.clock() - t0 < 1 do
		task.wait(0.1)
		s = LobbyClient.get()
	end
	if token ~= startToken then
		return
	end
	local info = if s.night and s.night.night == night then s.night else nil
	local endless = info ~= nil and info.mode == "Endless"
	head.Text = string.format(if endless then "Endless night %d" else "Night %d", night)
	local first = {}
	local run = s.run
	if endless then
		table.insert(first, "Any rule, any night. One try.")
	elseif s.runNight and run then
		local attempt = tonumber(run.attempt) or 1
		table.insert(first, string.format("Night %d of %d.", night, s.nights or 5))
		if attempt > 1 then
			table.insert(first, TRY[attempt] or "Another try.")
		end
	end
	local finaleNight = false
	if info then
		for _, r in info.rules do
			if r == "Finale" then
				finaleNight = true
			end
		end
	end
	local quota = if info then info.quota else ViewState.get().quota
	if quota and finaleNight then
		-- Night 5 needs both: the quota and the owner's one fish (Neon read them as a clash).
		table.insert(first, string.format("Quota %d, and the owner's Steeple Cat.", quota))
	elseif quota then
		table.insert(first, string.format("Quota %d.", quota))
	end
	local second = {}
	local amended = false
	if info then
		for _, r in info.newRules do
			local n = Rulebook.NUMBERS[r]
			if n then
				table.insert(second, string.format("Taped in tonight: Rule %d.", n))
			end
		end
		amended = next(info.amendments) ~= nil
	end
	if amended then
		table.insert(
			second,
			string.format('<font color="#%s">The owner changed the book (R).</font>', Look.Palette.amendInk:ToHex())
		)
	end
	local text = table.concat(first, " ")
	if #second > 0 then
		text ..= "\n" .. table.concat(second, " ")
	end
	body.Text = text
	card.Visible = true
	task.delay(NightCards.START_SECONDS, function()
		if startToken == token then
			card.Visible = false
		end
	end)
end

-- Puts the night start strip away now (the finale's bell).
function NightCards.hideStart()
	startToken += 1
	local c = startCard
	if c then
		c.Visible = false
	end
end

function NightCards.init()
	local gui = Paper.gui("DeadCalmNightCards", 10)

	-- Night start: a small strip at the top middle, tap to put away.
	local st = Paper.sheet(gui, "Start", UDim2.fromScale(0.5, 0), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), 8)
	st.AutomaticSize = Enum.AutomaticSize.Y
	st.Rotation = -0.8
	st.BackgroundTransparency = 0.08
	st.Visible = false
	local stLimit = Instance.new("UISizeConstraint")
	stLimit.MaxSize = Vector2.new(440, 140)
	stLimit.MinSize = Vector2.new(260, 0)
	stLimit.Parent = st
	local stList = Instance.new("UIListLayout")
	stList.SortOrder = Enum.SortOrder.LayoutOrder
	stList.Padding = UDim.new(0, 2)
	stList.Parent = st
	startCard = st
	local big = Paper.fit(26, 18, 30)
	local sh = Paper.text(st, "Head", "", big, Paper.hand())
	sh.LayoutOrder = 1
	sh.Size = UDim2.new(1, 0, 0, big + 4)
	sh.TextXAlignment = Enum.TextXAlignment.Center
	startHead = sh
	local small = Paper.fit(15, 11, 17)
	local sb = Paper.text(st, "Body", "", small)
	sb.LayoutOrder = 2
	sb.RichText = true
	sb.AutomaticSize = Enum.AutomaticSize.Y
	sb.Size = UDim2.fromScale(1, 0)
	sb.TextXAlignment = Enum.TextXAlignment.Center
	startBody = sb
	st.Active = true
	st.InputBegan:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			startToken += 1
			st.Visible = false
		end
	end)

	-- Night end.
	-- Sized to its text (fitCard on show): a width from the screen, AutomaticSize Y.
	local function stack(card: Frame, gap: number)
		card.AutomaticSize = Enum.AutomaticSize.Y
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, gap)
		list.Parent = card
	end
	local function autoText(t: TextLabel, order: number)
		t.LayoutOrder = order
		t.Size = UDim2.fromScale(1, 0)
		t.AutomaticSize = Enum.AutomaticSize.Y
	end
	local e = Paper.sheet(gui, "End", UDim2.fromOffset(520, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 18)
	e.BackgroundTransparency = 0.03
	e.Rotation = 0.8
	e.Visible = false
	stack(e, 8)
	endCard = e
	local h = Paper.text(e, "Head", "", 30, Paper.hand())
	autoText(h, 1)
	endHead = h
	local b = Paper.text(e, "Body", "", 18)
	autoText(b, 2)
	endBody = b

	-- The run's end.
	local r = Paper.sheet(gui, "Run", UDim2.fromOffset(560, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), 18)
	r.BackgroundTransparency = 0.02
	r.Rotation = -0.6
	r.Visible = false
	stack(r, 8)
	runCard = r
	local rh = Paper.text(r, "Head", "", 34, Paper.hand())
	autoText(rh, 1)
	runHead = rh
	local rb = Paper.text(r, "Body", "", 18)
	autoText(rb, 2)
	runBody = rb
	local btn = Paper.button(r, "Title", "Back to the title", UDim2.fromOffset(240, 40))
	btn.LayoutOrder = 3
	btn.Activated:Connect(function()
		LobbyClient.send("Title")
	end)
	runButton = btn

	-- The gameplay HUD stays hidden while any end card is up.
	local function syncHud()
		HUD.setHidden(NightCards.HUD_KEY, e.Visible or r.Visible)
	end
	e:GetPropertyChangedSignal("Visible"):Connect(syncHud)
	r:GetPropertyChangedSignal("Visible"):Connect(syncHud)

	-- The finale's bell: nothing on screen but the bell and its line.
	Events.on("EntityCue", function(ev)
		if ev.entity == "Finale" then
			NightCards.hideStart()
		end
	end)
	Events.on("NightStarted", function(ev)
		local data = ev.data or {}
		nightNumber = tonumber(data.night) or nightNumber
		e.Visible = false
		r.Visible = false
		endToken += 1
		task.spawn(showStart, nightNumber)
	end)
	-- The death card goes first: the end card waits for it (at most 15 s), then, for a
	-- drowned player, a few seconds of the drowned view. A new night cancels the wait.
	local function afterDeathCard(fn: () -> ())
		endToken += 1
		local my = endToken
		task.spawn(function()
			local t0 = os.clock()
			local hadCard = DeathCard.showing()
			while DeathCard.showing() and os.clock() - t0 < 15 do
				hadCard = true
				task.wait(0.25)
			end
			local pv = ViewState.me()
			if hadCard or (pv ~= nil and pv.alive == false) then
				task.wait(NightCards.DROWNED_BEAT)
			end
			if endToken == my then
				fn()
			end
		end)
	end
	Events.on("NightCleared", function(ev)
		local data = ev.data or {}
		afterDeathCard(function()
			local s = awaitOutcome(2)
			if s.outcome == "RunCleared" then
				-- The finale's dawn first (fx/Finale: the sunrise and its banner), then a few
				-- seconds of the dock in daylight, then the run card (the banner goes as it comes).
				local my = endToken
				local t0 = os.clock()
				while Finale.bannerShownAt() == nil and os.clock() - t0 < NightCards.BANNER_WAIT do
					task.wait(0.1)
				end
				local shownAt = Finale.bannerShownAt()
				local left = if shownAt then shownAt + Look.Dawn.runCardAfterBanner - os.clock() else 3
				if left > 0 then
					task.wait(left)
				end
				if endToken ~= my then
					return
				end
				Finale.dismissBanner(0.6)
				showRun(true, LobbyClient.get())
			else
				showEnd(true, nil, data.result, s)
			end
		end)
	end)
	Events.on("NightFailed", function(ev)
		local data = ev.data or {}
		afterDeathCard(function()
			local s = awaitOutcome(2)
			showEnd(false, if type(data.reason) == "string" then data.reason else nil, data.result, s)
			-- The sting and the owner's "Rough night" come with the card, never over a death.
			AudioDirector.play("night-failed-sting")
			local tok = endToken
			if s.outcome == "RunOver" then
				task.delay(6, function()
					if endToken == tok then
						showRun(false, LobbyClient.get())
					end
				end)
				return
			end
			task.delay(1.2, function()
				if endToken == tok then
					AudioDirector.playTape("tape-night-failed")
				end
			end)
		end)
	end)
	LobbyClient.onChange(function(s)
		if s.phase == "Title" then
			NightCards.hide()
		end
	end)
end

return NightCards
