-- Core.Rulebook: text ids, the page, amendment policies from the run seed, tapes and
-- death cards (every death id Core can send has a card).
return function(t, Shared)
	local Rulebook = require(Shared.Core.Rulebook)
	local Config = require(Shared.Config)

	local ALL = { "Hum", "WrongCatch", "Neighbor", "Knocking", "Watcher", "Finale" }

	local function count(m)
		local n = 0
		for _ in m do
			n += 1
		end
		return n
	end

	t.test("rule text ids, printed and amended, all have English", function()
		t.eq(Rulebook.ruleText(Config, "Hum"), "Rule.Hum", "printed")
		t.eq(Rulebook.ruleText(Config, "Hum", "LanternOut"), "Rule.Hum", "printed variant")
		t.eq(Rulebook.ruleText(Config, "Hum", "LanternLit"), "Rule.Hum.LanternLit", "amended")
		for _, r in ALL do
			t.ok(Rulebook.TEXT["Rule." .. r] ~= nil, "text for " .. r)
		end
		t.ok(Rulebook.TEXT["Rule.Water"] ~= nil, "Rule 0")
		for rule, variants in Config.Amendments do
			for i = 2, #variants do
				local id = Rulebook.ruleText(Config, rule, variants[i])
				t.ok(Rulebook.TEXT[id] ~= nil, "text for " .. id)
			end
		end
	end)

	t.test("no em dashes and no gore words in any text", function()
		for id, text in Rulebook.TEXT do
			t.ok(not string.find(text, "\u{2014}"), "em dash in " .. id)
			local lower = string.lower(text)
			for _, w in { "blood", "gore", "corpse", "kill" } do
				t.ok(not string.find(lower, "%f[%a]" .. w .. "%f[%A]"), w .. " in " .. id)
			end
		end
	end)

	t.test("the page: Rule 0 first, then rules in number order, amendments marked", function()
		local page = Rulebook.page(Config, { "Watcher", "Hum", "Knocking" }, { Knocking = "AnswerOne" })
		t.eq(page[1].rule, "Water", "Rule 0")
		t.eq(page[2].rule, "Hum", "Rule 1")
		t.eq(page[3].rule, "Knocking", "Rule 4")
		t.eq(page[4].rule, "Watcher", "Rule 5")
		t.eq(page[3].amended, "Rule.Knocking.AnswerOne", "amended")
		t.eq(page[2].amended, nil, "Hum as printed")
	end)

	t.test("taped rules: Story accumulates, Endless has every rule but the Finale", function()
		t.eq(#Rulebook.taped(Config, "Story", 1), 1, "night 1")
		t.eq(#Rulebook.taped(Config, "Story", 4), 5, "night 4")
		t.eq(#Rulebook.taped(Config, "Story", 5), 6, "night 5 adds the Finale")
		local e = Rulebook.taped(Config, "Endless", 9)
		t.eq(#e, 5, "endless")
		for _, r in e do
			t.ok(r ~= "Finale", "no finale in Endless")
		end
	end)

	t.test("Normal first run: one amendment on night 5 only, drawn from the seed", function()
		local rules = Rulebook.taped(Config, "Story", 5)
		local picked = {}
		for seed = 1, 200 do
			for night = 1, 4 do
				local am = Rulebook.amendments(Config, {
					seed = seed,
					difficulty = "Normal",
					mode = "Story",
					night = night,
					rules = Rulebook.taped(Config, "Story", night),
					firstRun = true,
				})
				t.eq(count(am), 0, "by the book on night " .. night)
			end
			local am = Rulebook.amendments(
				Config,
				{ seed = seed, difficulty = "Normal", mode = "Story", night = 5, rules = rules, firstRun = true }
			)
			t.eq(count(am), 1, "one on night 5")
			for rule, variant in am do
				picked[rule] = true
				t.ok(variant ~= Config.Amendments[rule][1], "not the printed variant")
			end
			local again = Rulebook.amendments(
				Config,
				{ seed = seed, difficulty = "Normal", mode = "Story", night = 5, rules = rules, firstRun = true }
			)
			for rule, variant in am do
				t.eq(again[rule], variant, "same seed, same amendment")
			end
		end
		t.eq(count(picked), 4, "every amendable rule can be the one")
	end)

	t.test("Nightmare: amendments from night 2, several per night, any amendable rule", function()
		local perNight = { 0, 0, 0, 0, 0 }
		local multi = 0
		for seed = 1, 200 do
			for night = 1, 5 do
				local am = Rulebook.amendments(Config, {
					seed = seed,
					difficulty = "Nightmare",
					mode = "Story",
					night = night,
					rules = Rulebook.taped(Config, "Story", night),
					firstRun = true,
				})
				perNight[night] += count(am)
				if count(am) >= 2 then
					multi += 1
				end
				for rule in am do
					t.ok(rule ~= "WrongCatch" and rule ~= "Finale", "only amendable rules")
				end
			end
		end
		t.eq(perNight[1], 0, "night 1 by the book (amendFromNight 2)")
		t.ok(perNight[2] > 0 and perNight[5] > perNight[2], "more rules, more amendments")
		t.ok(multi > 0, "sometimes more than one")
	end)

	t.test("Normal later runs use the random policy from night 5", function()
		local multi = 0
		for seed = 1, 200 do
			local am = Rulebook.amendments(Config, {
				seed = seed,
				difficulty = "Normal",
				mode = "Story",
				night = 5,
				rules = Rulebook.taped(Config, "Story", 5),
				firstRun = false,
			})
			if count(am) ~= 1 then
				multi += 1
			end
		end
		t.ok(multi > 0, "not always exactly one")
	end)

	t.test("tapes: the night, plus the amendment tape when the book changed", function()
		local p = { mode = "Story", night = 3, amendments = {} }
		t.eq(table.concat(Rulebook.tapes(p :: any), ","), "Night3", "plain")
		p.amendments = { Hum = "LanternLit" }
		t.eq(table.concat(Rulebook.tapes(p :: any), ","), "Night3,Amendment", "amended")
		local e = { mode = "Endless", night = 9, amendments = {} }
		t.eq(Rulebook.tapes(e :: any)[1], "Endless", "endless")
		for _, id in
			{ "Night1", "Night2", "Night3", "Night4", "Night5", "Endless", "Amendment", "NightFailed", "RunCleared" }
		do
			t.ok(Rulebook.TEXT["Tape." .. id] ~= nil, "tape text " .. id)
		end
	end)

	t.test("death cards: every id Core sends maps to its rule; unknown ids fall back", function()
		for _, id in Rulebook.DEATHS do
			local card = Rulebook.deathCard(id)
			t.eq(card.text, id, "card " .. id)
			t.ok(Rulebook.TEXT[id] ~= nil, "English for " .. id)
			t.eq(card.ruleText, "Rule." .. card.rule, "names the rule")
			t.eq(card.number, Rulebook.NUMBERS[card.rule], "rule number")
		end
		t.eq(Rulebook.deathText("Hum", "Reeling"), "Death.Hum.Reeling", "id")
		t.eq(Rulebook.deathCard("Death.Hum.Reeling").number, 1, "Rule 1")
		t.eq(Rulebook.deathCard("Death.Nope.Nope").text, "Death.Unknown", "fallback")
		t.eq(Rulebook.deathCard("garbage").text, "Death.Unknown", "fallback")
	end)

	t.test("every death cause in the rule modules has a card", function()
		-- Causes the modules use (kept in sync by hand with Core/entities and Night).
		local causes = {
			Water = { "Drag" },
			Hum = { "Reeling", "Motor", "Moving", "LanternLit", "LanternDark", "Noise" },
			Neighbor = { "Waved", "Closed", "Beacon" },
			Knocking = { "Sunk" },
			Watcher = { "Reached" },
			Finale = { "Still", "Dark", "Waved", "Closed", "Beacon" },
		}
		for rule, list in causes do
			for _, c in list do
				local id = Rulebook.deathText(rule, c)
				t.eq(Rulebook.deathCard(id).text, id, "card for " .. id)
			end
		end
	end)
end
