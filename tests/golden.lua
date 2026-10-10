-- Golden queue snapshots: every class × spec × mode in a fixed set of
-- situations, one file per class in tests/golden/. A changed line is a
-- changed suggestion: review the diff, then rewrite with --update-golden.
local M = require("wowmock")

local G = {}

G.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local MODES = { "auto", "single", "aoe", "burst" }
local PRESSES = 6

-- Make `spec` the list ns.ActiveSpec() picks.
local function activate(T, class, spec)
	local db = T.ns.db
	db.roleAuto = false
	if class == "DRUID" and (spec == "damage" or spec == "cat" or spec == "bear") then
		db.role = "hybrid"
		if spec == "cat" then
			T.aura("player", "CatForm", "HELPFUL")
		elseif spec == "bear" then
			T.aura("player", "BearForm", "HELPFUL")
		end
	else
		db.role = spec
	end
end

local SCENARIOS = {
	{ "pull", function(T)
		T.W.inCombat = false
		T.target{}
	end },
	{ "fight", function(T)
		T.target{ hp = 80 }
	end },
	{ "execute", function(T)
		T.target{ hp = 15 }
	end },
	{ "hurt", function(T)
		T.target{ hp = 80 }
		T.W.player.hp = 40
	end },
	{ "aoe", function(T)
		T.target{ hp = 80 }
		T.enemies(4)
	end },
	{ "far", function(T)
		T.target{ hp = 80, distance = 25 }
	end },
	{ "secret", function(T)
		T.target{ hp = 80 }
		T.W.secret.auras = true
		T.W.secret.cooldowns = true
	end },
}

local function client(class, spec, mode)
	local T = M.new{ class = class }
	T.W.inCombat = true
	activate(T, class, spec)
	T.ns.db.combatMode = mode
	return T
end

function G.build(class)
	local lines = {}
	local probe = M.new{ class = class }
	for _, spec in ipairs(probe.ns.SpecList(class)) do
		for _, mode in ipairs(MODES) do
			local prefix = string.format("%-7s %-6s ", spec, mode)
			for _, sc in ipairs(SCENARIOS) do
				local T = client(class, spec, mode)
				sc[2](T)
				T.advance(0.35)
				lines[#lines + 1] = prefix .. string.format("%-9s Q=%s | D=%s", sc[1], T.queue(), T.def())
			end
			-- Press slot 1 every GCD and record what the HUD shows next.
			local T = client(class, spec, mode)
			T.target{ hp = 80 }
			T.advance(0.35)
			for n = 1, PRESSES do
				local ids = T.queueIds()
				lines[#lines + 1] = prefix .. string.format("press%-4d Q=%s", n, T.queue())
				if #ids == 0 then
					break
				end
				T.press(ids[1])
				T.advance(1.5)
			end
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

local function splitLines(text)
	local out = {}
	for line in (text or ""):gmatch("([^\n]*)\n") do
		out[#out + 1] = line
	end
	return out
end

function G.run(H, update)
	for _, class in ipairs(G.CLASSES) do
		local path = "tests/golden/" .. class .. ".txt"
		H.test("golden " .. class, function()
			local got = G.build(class)
			if update then
				writeFile(path, got)
				return
			end
			local want = readFile(path)
			H.ok(want ~= nil, path .. " missing: run with --update-golden")
			if got == want then
				return
			end
			local a, b = splitLines(want), splitLines(got)
			local diffs = {}
			for i = 1, math.max(#a, #b) do
				if a[i] ~= b[i] then
					diffs[#diffs + 1] = string.format("line %d\n  was: %s\n  now: %s", i, a[i] or "(none)", b[i] or "(none)")
					if #diffs >= 8 then
						break
					end
				end
			end
			H.ok(false, path .. " changed. First differences:\n" .. table.concat(diffs, "\n"))
		end)
	end
end

return G
