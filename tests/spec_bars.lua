-- "Only suggest spells that are on your action bars" (ns.db.barOnly, on by default).
local M = require("wowmock")

local function mage()
	local T = M.new{ class = "MAGE", learn = false }
	T.learn({ "Pyroblast", "FireBlast", "Fireball" })
	T.refresh()
	T.W.inCombat = true
	T.target{ hp = 80 }
	return T
end

return function(H)
	H.test("bar-only off: spells missing from the bars are still suggested", function()
		local T = mage()
		T.ns.db.barOnly = false
		T.bars({ "FireBlast", "Fireball" })
		H.first(T.queue(), "Pyroblast")
	end)

	H.test("bar-only on, readable bars: a spell on no bar is skipped", function()
		local T = mage()
		H.eq(T.ns.db.barOnly, true, "default")
		T.bars({ "FireBlast", "Fireball" })
		local q = T.queue()
		H.lacks(q, "Pyroblast")
		H.first(q, "FireBlast")
	end)

	H.test("bar-only on: items and macros on the bars do not switch the filter off", function()
		local T = mage()
		T.bars({ "FireBlast", { item = true }, "Fireball" })
		H.lacks(T.queue(), "Pyroblast")
	end)

	H.test("bar-only on, a slot the client hides: the filter steps aside (no flicker)", function()
		local T = mage()
		T.bars({ "FireBlast", { hidden = true }, "Fireball" })
		H.first(T.queue(), "Pyroblast")
	end)

	H.test("bar-only on, empty bars: nothing is filtered", function()
		local T = mage()
		T.bars({})
		H.first(T.queue(), "Pyroblast")
	end)
end
