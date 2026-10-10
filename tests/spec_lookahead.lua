-- Engine v2: slots 2-3 are what the HUD expects after slot 1 is pressed.
-- Each later slot is checked at the time it can actually be pressed
-- (cooldowns, holds, aura time left, mana and energy). Slot 1 is unchanged.
local M = require("wowmock")

local function client(class, known)
	local T = M.new{ class = class, learn = false }
	T.learn(known)
	T.refresh()
	T.W.inCombat = true
	T.target{ hp = 80 }
	return T
end

return function(H)
	H.test("lookahead: a cooldown ending during slot 1's GCD shows in slot 2", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.cooldown("FireBlast", 1.0)
		H.eq(T.queue(), "Pyroblast, FireBlast, Frostbolt", "queue")
	end)

	H.test("lookahead: a cooldown ending a few seconds later comes after what is ready sooner", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.cooldown("FireBlast", 5.0)
		H.eq(T.queue(), "Pyroblast, Frostbolt, FireBlast", "queue")
	end)

	H.test("lookahead: a cooldown far away stays out of the HUD", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.W.spells[T.id("FireBlast")].cooldown = 30
		T.cooldown("FireBlast", 20)
		H.eq(T.queue(), "Pyroblast, Frostbolt", "queue")
	end)

	H.test("lookahead: filling slots 2-3 never changes the next tick's slot 1", function()
		local T = client("WARRIOR", { "Rend", "MortalStrike", "HeroicStrike" })
		T.W.secret.auras = true
		T.press("Rend")
		T.advance(1.5)
		local first = T.queue()
		T.advance(0.2)
		H.eq(T.queue(), first, "next tick")
	end)

	H.test("lookahead: a long cast in slot 1 pushes slot 2 further out", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.castTime("Pyroblast", 6)
		T.cooldown("FireBlast", 5.0)
		H.eq(T.queue(), "Pyroblast, FireBlast, Frostbolt", "queue")
	end)

	H.test("lookahead: a DoT running out during slot 1 is refreshed in slot 2", function()
		local T = client("WARRIOR", { "MortalStrike", "Rend", "HeroicStrike" })
		T.aura("target", "Rend", "HARMFUL", 7)
		H.eq(T.queue(), "MortalStrike, Rend, HeroicStrike", "queue")
	end)

	H.test("lookahead: slot 1 ignores the future (DoT with 7 s left is not refreshed now)", function()
		local T = client("WARRIOR", { "Rend", "HeroicStrike" })
		T.aura("target", "Rend", "HARMFUL", 7)
		H.first(T.queue(), "HeroicStrike")
	end)

	H.test("mana: slots 2-3 skip what slot 1 leaves you unable to pay", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.W.power[0] = 50
		T.cost("Pyroblast", 0, 40)
		T.cost("FireBlast", 0, 20)
		T.cost("Frostbolt", 0, 10)
		H.eq(T.queue(), "Pyroblast, Frostbolt", "queue")
	end)

	H.test("energy: the next affordable spender comes first, the expensive one after regen", function()
		local T = client("ROGUE", { "Hemorrhage", "GhostlyStrike", "SinisterStrike" })
		T.W.power[3] = 70
		T.cost("Hemorrhage", 3, 35)
		T.cost("GhostlyStrike", 3, 50)
		T.cost("SinisterStrike", 3, 45)
		H.eq(T.queue(), "Hemorrhage, SinisterStrike, GhostlyStrike", "queue")
	end)

	-- Regressions from the 1.6.0 review -------------------------------------

	H.test("pass: a spell whose debuff never lands does not repeat forever", function()
		-- Scorch stacks Fire Vulnerability; without the talent it never appears.
		local T = client("MAGE", { "Scorch", "Frostbolt", "Fireball" })
		T.aura("target", "FrostNova", "HARMFUL", 60)
		local seen = {}
		for _ = 1, 6 do
			local ids = T.queueIds()
			seen[#seen + 1] = T.label(ids[1])
			T.press(ids[1])
			T.unaura("target", "FireVulnerability")
			T.advance(1.6)
		end
		local text = table.concat(seen, " ")
		H.ok(text:find("Frostbolt", 1, true), "slot 1 should move on from Scorch: " .. text)
	end)

	H.test("pass: a DoT still in flight does not jump back to slot 1, its hold survives", function()
		local T = client("HUNTER", { "SerpentSting", "ArcaneShot", "AutoShot" })
		T.ns.db.roleAuto = false
		T.ns.db.role = "range"
		T.target{ hp = 80, distance = 20 }
		T.aura("target", "ConcussiveShot", "HARMFUL", 60)
		T.press("SerpentSting")
		T.unaura("target", "SerpentSting")
		T.advance(0.2)
		local hold = T.ns.API.HoldRemain(T.id("SerpentSting"))
		H.ok(T.queue():match("^[^,]+") ~= "SerpentSting", "slot 1: " .. T.queue())
		H.ok(T.ns.API.HoldRemain(T.id("SerpentSting")) >= hold - 0.01, "hold was cleared by building the queue")
	end)

	H.test("power: a cost the client hides keeps the live 'not enough rage' answer", function()
		local T = client("WARRIOR", { "Rend", "MortalStrike", "HeroicStrike" })
		T.W.power[1] = 10
		T.cost("Rend", 1, 10)
		T.cost("MortalStrike", 1, 30)
		local real = T.env.C_Spell.GetSpellPowerCost
		T.env.C_Spell.GetSpellPowerCost = function(id)
			local list = real(id)
			for _, c in ipairs(list) do
				c.cost, c.type = T.W.SECRET, T.W.SECRET
			end
			return list
		end
		H.lacks(T.queue(), "MortalStrike")
	end)

	H.test("energy: refill stops at the cap before each later spend", function()
		-- 100 energy, free slot 1, 45 spent at 1 s: 65 at 2 s (not 75).
		local T = client("ROGUE", { "Hemorrhage", "GhostlyStrike", "Mutilate", "Backstab" })
		T.W.power[3] = 100
		T.cost("GhostlyStrike", 3, 45)
		T.cost("Mutilate", 3, 66)
		T.cost("Backstab", 3, 60)
		H.eq(T.queue(), "Hemorrhage, GhostlyStrike, Backstab", "queue")
	end)

	H.test("mana: projected for slot 2 while slot 1 is being cast", function()
		local T = client("MAGE", { "Pyroblast", "FireBlast", "Frostbolt" })
		T.W.power[0] = 50
		T.cost("Pyroblast", 0, 40)
		T.cost("FireBlast", 0, 20)
		T.cost("Frostbolt", 0, 10)
		T.W.casting = { name = T.W.spells[T.id("Pyroblast")].name, startMs = T.W.now * 1000, endMs = (T.W.now + 3) * 1000 }
		H.eq(T.queue(), "Pyroblast, Frostbolt", "queue")
	end)

	H.test("slot 1: a buff still listed at 0 s left is treated as before (not missing)", function()
		local T = M.new{ class = "DRUID", learn = false }
		T.learn({ "CatForm", "TigersFury", "Claw", "Shred" })
		T.refresh()
		T.W.inCombat = true
		T.ns.db.roleAuto = false
		T.ns.db.role = "hybrid"
		T.aura("player", "CatForm", "HELPFUL")
		T.target{ hp = 80 }
		local id = T.id("TigersFury")
		local aura = { name = T.W.spells[id].name, spellId = id, expirationTime = T.W.now, applications = 1, filter = "HELPFUL" }
		local U = T.env.C_UnitAuras
		local byId, byName = U.GetPlayerAuraBySpellID, U.GetAuraDataBySpellName
		U.GetPlayerAuraBySpellID = function(x)
			if x == id then
				return aura
			end
			return byId(x)
		end
		U.GetAuraDataBySpellName = function(unit, name, filter)
			if unit == "player" and name == aura.name then
				return aura
			end
			return byName(unit, name, filter)
		end
		H.lacks(T.queue():match("^[^,]+") or "", "TigersFury")
	end)

	H.test("energy: slot 1 still follows the live client (no projection)", function()
		local T = client("ROGUE", { "Hemorrhage", "SinisterStrike" })
		T.W.power[3] = 40
		T.cost("Hemorrhage", 3, 35)
		T.cost("SinisterStrike", 3, 45)
		H.first(T.queue(), "Hemorrhage")
	end)
end
