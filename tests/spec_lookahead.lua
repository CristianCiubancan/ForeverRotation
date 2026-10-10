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

	H.test("energy: slot 1 still follows the live client (no projection)", function()
		local T = client("ROGUE", { "Hemorrhage", "SinisterStrike" })
		T.W.power[3] = 40
		T.cost("Hemorrhage", 3, 35)
		T.cost("SinisterStrike", 3, 45)
		H.first(T.queue(), "Hemorrhage")
	end)
end
