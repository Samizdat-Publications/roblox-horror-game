--!strict
--[[
==========================================================================================
  MONETIZATION STUBS. NOTHING HERE IS LIVE.

  Owner ruling (11/26/2026): never publish the game publicly, never buy anything, never
  create Developer Products or Game Passes. So this module has:
    * NO real Game Pass or product ids (every id below is 0 and never read by the engine),
    * NO purchase prompts (MarketplaceService is not even required here),
    * NOTHING pay to win: every idea below is a look, never a rule, a fish, a life, a hint
      or time. Every cosmetic in the game is earned by playing (Config.Cosmetics).

  Every function returns false or an empty list. If the owner ever decides to sell a
  cosmetic pass, this is the one place to wire it, and only after a design review.
==========================================================================================
]]

local MonetizationStubs = {}

-- Ideas only. Commented out on purpose: nothing in the game reads them.
MonetizationStubs.POSSIBLE_PASSES = {
	-- { key = "LanternPack", gamePassId = 0, what = "Extra lantern glass colors (look only)" },
	-- { key = "PaintPack", gamePassId = 0, what = "Extra boat paints (look only)" },
	-- { key = "HatPack", gamePassId = 0, what = "Extra hats (look only)" },
	-- { key = "RadioTunes", gamePassId = 0, what = "Extra songs on the dock radio at the title" },
} :: { { [string]: any } }

-- Would answer "does this player own pass `key`?". Always false.
function MonetizationStubs.ownsPass(_player: Player, _key: string): boolean
	return false
end

-- Would add the cosmetic ids a pass grants. Always none.
function MonetizationStubs.passCosmetics(_player: Player): { string }
	return {}
end

-- Would show a purchase prompt. Never does; returns false.
function MonetizationStubs.prompt(_player: Player, _key: string): boolean
	return false
end

-- True only if real ids were ever wired in. Always false.
function MonetizationStubs.enabled(): boolean
	return false
end

return MonetizationStubs
