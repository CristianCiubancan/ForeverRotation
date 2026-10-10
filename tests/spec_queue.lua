-- Behaviour of the rotation queue, one rule per test. Each test builds a
-- fresh client, so nothing leaks between them.
local M = require("wowmock")

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- A level 60 character of `class` fighting a hostile mob in melee range.
local function fight(class, known)
	local T = M.new{ class = class, learn = known == nil }
	if known then
		T.learn(known)
		T.refresh()
	end
	T.W.inCombat = true
	T.target{ hp = 80 }
	return T
end

return function(H)
	H.test("unknown spells are never suggested", function()
		local T = fight("MAGE")
		T.forget({ "Pyroblast", "FireBlast" })
		T.refresh()
		local q = T.queue()
		H.lacks(q, "Pyroblast")
		H.lacks(q, "FireBlast")
	end)

	H.test("every class and spec: a spell appears at most once in the queue", function()
		for _, class in ipairs(CLASSES) do
			local T = fight(class)
			for _, spec in ipairs(T.ns.SpecList(class)) do
				T.ns.db.role = spec
				local ids = T.queueIds()
				local seen = {}
				for _, id in ipairs(ids) do
					H.ok(not seen[id], class .. " " .. spec .. ": duplicate " .. T.label(id) .. " in [" .. T.queue() .. "]")
					seen[id] = true
				end
			end
		end
	end)

	H.test("cooldown spell leaves the queue after a cast and returns when ready", function()
		local T = fight("MAGE", { "FireBlast", "Fireball" })
		H.first(T.queue(), "FireBlast")
		T.press("FireBlast")
		H.lacks(T.queue(), "FireBlast")
		T.advance(T.W.spells[T.id("FireBlast")].cooldown + 0.1)
		H.first(T.queue(), "FireBlast")
	end)

	H.test("secret cooldowns: the add-on's own timer still hides a spell on cooldown", function()
		local T = fight("MAGE", { "FireBlast", "Fireball" })
		T.W.secret.cooldowns = true
		T.press("FireBlast")
		H.lacks(T.queue(), "FireBlast")
		T.advance(T.W.spells[T.id("FireBlast")].cooldown + 0.1)
		H.first(T.queue(), "FireBlast")
	end)

	H.test("readable DoT: leaves the queue, comes back to refresh at 6 s left", function()
		local T = fight("WARRIOR", { "Rend", "HeroicStrike" })
		H.first(T.queue(), "Rend")
		T.press("Rend")
		H.lacks(T.queue(), "Rend")
		local left = T.ns.SPELL_HOLD[T.id("Rend")]
		T.advance(left - 5.9)
		H.first(T.queue(), "Rend")
	end)

	H.test("secret auras: the hold keeps a DoT out, a new target brings it back", function()
		local T = fight("WARRIOR", { "Rend", "HeroicStrike" })
		T.W.secret.auras = true
		T.press("Rend")
		H.lacks(T.queue(), "Rend")
		T.target{ hp = 100, guid = "mob-2" }
		T.fire("PLAYER_TARGET_CHANGED")
		H.first(T.queue(), "Rend")
	end)

	H.test("heals: none at full health, the matching heal goes first when hurt", function()
		local T = fight("PALADIN")
		local q = T.queue()
		H.lacks(q, "FlashofLight")
		H.lacks(q, "HolyLight")
		T.W.player.hp = 60
		H.first(T.queue(), "FlashofLight")
		T.W.player.hp = 75
		H.first(T.queue(), "HolyLight")
	end)

	H.test("a filler listed first gives slot 1 to a ready action below it", function()
		local T = fight("SHAMAN", { "LightningBolt", "EarthShock" })
		local steps = T.ns.GetAPL()
		local reordered = {}
		for _, s in ipairs(steps) do
			if s.key == "LightningBolt" then
				table.insert(reordered, 1, s)
			else
				reordered[#reordered + 1] = s
			end
		end
		T.ns.db.combatMode = "single"
		T.ns.SaveAPL(reordered, "SHAMAN", "caster", "single")
		H.eq(T.ns.GetAPL()[1].key, "LightningBolt", "list order")
		H.first(T.queue(), "EarthShock")
	end)

	H.test("slot 1 prefers an in-range spell over a higher one out of range", function()
		local T = fight("SHAMAN", { "Stormstrike", "EarthShock", "LightningBolt" })
		T.ns.db.role = "melee"
		T.ns.db.roleAuto = false
		H.first(T.queue(), "Stormstrike")
		T.W.target.distance = 15
		H.first(T.queue(), "EarthShock")
	end)

	H.test("finishers wait for combo points; the lookahead counts the builder's point", function()
		local T = fight("ROGUE")
		local q = T.queue()
		-- 0 points: a builder first, then Slice and Dice (needs 1) after it.
		H.first(q, "Hemorrhage")
		H.has(q, "SliceandDice")
		H.lacks(q, "Rupture")
		-- 5 points: Slice and Dice spends them first; with it up, Rupture.
		T.W.combo = 5
		H.first(T.queue(), "SliceandDice")
		T.aura("player", "SliceandDice", "HELPFUL", 20)
		H.first(T.queue(), "Rupture")
	end)

	H.test("proc spells only show when the client says they are usable", function()
		local T = fight("WARRIOR")
		H.lacks(T.queue(), "Overpower")
		T.W.procUp[T.id("Overpower")] = true
		H.has(T.queue(), "Overpower")
	end)

	H.test("auto mode switches to the AoE list at 3 enemies", function()
		local T = fight("MAGE")
		T.enemies(2)
		H.lacks(T.queue(), "ArcaneExplosion")
		T.enemies(3)
		T.advance(0.35)
		H.first(T.queue(), "ArcaneExplosion")
	end)

	H.test("execute range: Execute only below 20% target health", function()
		local T = fight("WARRIOR", { "Execute", "HeroicStrike" })
		H.lacks(T.queue(), "Execute")
		T.W.target.hp = 15
		H.first(T.queue(), "Execute")
	end)

	H.test("interrupt shows only while the target casts", function()
		local T = fight("WARRIOR")
		H.eq(T.ns.BuildInterrupt(), nil, "no cast, no kick")
		T.W.targetCasting = { name = "Fireball", startMs = T.W.now * 1000, endMs = T.W.now * 1000 + 2500 }
		H.eq(T.ns.BuildInterrupt(), T.id("Pummel"), "kick while casting")
	end)

	H.test("defense: missing long buff is suggested, gone once it is up", function()
		local T = fight("PALADIN")
		H.eq(T.def(), "DevotionAura", "first defense step")
		T.aura("player", "DevotionAura", "HELPFUL", 1800)
		H.ok(T.def() ~= "DevotionAura", "aura up: next defense step, got " .. T.def())
	end)
end
