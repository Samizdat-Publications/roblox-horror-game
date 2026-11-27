--!strict
-- Which page of the book is open: nil (shut), "rules" (the rulebook taped in the boat),
-- "guide" (the Field Guide) or "lake" (the Lake Rules from the title screen).
-- DESIGN.md: opening the book covers most of your view and stops your hands. So while a
-- page is open Input is blocked (no casting, reeling, steering, lantern, motor, knocking or
-- bailing) and, during a night, the server is told (Lobby "Book"), so the night sees
-- PlayerObs.bookOpen and refuses intents that need hands.
-- Keys: R and G (gamepad D-pad left and right) open or switch; the same key again, Escape,
-- gamepad B or the Close button shuts it.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local client = script.Parent.Parent
local Input = require(client:WaitForChild("Input"))
local Events = require(client:WaitForChild("Events"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))

local BookState = {}

local page: string? = nil
local listeners: { (string?) -> () } = {}

local function notify()
	for _, fn in listeners do
		task.spawn(fn, page)
	end
end

function BookState.current(): string?
	return page
end

function BookState.onChange(fn: (string?) -> ())
	table.insert(listeners, fn)
end

-- Opens a page (or switches to it). Returns true when it is open.
-- Pages that belong to the title screen: the Lake Rules and the Locker (S5).
local TITLE_PAGES: { [string]: boolean } = { lake = true, locker = true }

function BookState.open(p: string): boolean
	if p ~= "rules" and p ~= "guide" and not TITLE_PAGES[p] then
		return false
	end
	-- On the title screen only the Lake Rules and the Locker open; in a night only the boat's book.
	local onTitle = LobbyClient.get().phase == "Title"
	if onTitle ~= (TITLE_PAGES[p] == true) then
		return false
	end
	if page == p then
		return true
	end
	local was = page
	page = p
	Input.setBlocked("book", true)
	if not TITLE_PAGES[p] and (was == nil or TITLE_PAGES[was]) then
		LobbyClient.send("Book", 1)
	end
	AudioDirector.play(if was == nil then "ui-book-open" else "ui-page-turn")
	notify()
	return true
end

function BookState.close()
	if page == nil then
		return
	end
	local was = page
	page = nil
	Input.setBlocked("book", false)
	if not TITLE_PAGES[was] then
		LobbyClient.send("Book", 0)
	end
	AudioDirector.play("ui-book-close")
	notify()
end

-- The same key again shuts the book; the other key turns to the other page.
function BookState.toggle(p: string)
	if page == p then
		BookState.close()
	else
		BookState.open(p)
	end
end

function BookState.init()
	Input.setBookHandler(BookState.toggle)
	UserInputService.InputBegan:Connect(function(io)
		if page ~= nil and (io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.ButtonB) then
			BookState.close()
		end
	end)
	-- A death, or the run ending, shuts the book.
	Events.on("PlayerDied", function(e)
		if e.player == Players.LocalPlayer.UserId then
			BookState.close()
		end
	end)
	LobbyClient.onChange(function(s)
		local onTitle = s.phase == "Title"
		if page ~= nil and onTitle ~= (TITLE_PAGES[page] == true) then
			BookState.close()
		end
	end)
end

return BookState
