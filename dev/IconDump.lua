local addonName, ns = ...

-- Developer add-on (WoWForeverRot_IconDump.toc), never shipped to players.
-- /wfrdump: for every spell the main add-on knows, record the client's name and icon
-- FileDataID into WoWForeverIconDumpDB. SavedVariables reach disk on /reload or logout.
-- This TOC loads its own copy of Locale/API/Data, so it has a private ns with no db.

WoWForeverIconDumpDB = WoWForeverIconDumpDB or {}
ns.db = ns.db or {}

local function collectEntries()
	local out = {}
	local function add(category, class, key, id)
		if type(id) == "number" then
			out[#out + 1] = { category = category, class = class, key = key, id = id }
		end
	end
	for class, spells in pairs(ns.Spell or {}) do
		for key, id in pairs(spells) do
			add("spell", class, key, id)
		end
	end
	for _, racial in ipairs(ns.RACIALS or {}) do
		add("racial", nil, racial.key, racial.id)
	end
	for class, id in pairs(ns.INTERRUPTS or {}) do
		add("interrupt", class, nil, id)
	end
	for class, id in pairs(ns.PURGES or {}) do
		add("purge", class, nil, id)
	end
	for class, list in pairs(ns.CLEANSE or {}) do
		for _, entry in ipairs(list) do
			add("cleanse", class, nil, entry.id)
		end
	end
	for id in pairs(ns.SPELL_NAME_HINT or {}) do
		add("hint", nil, nil, id)
	end
	table.sort(out, function(a, b)
		if a.category ~= b.category then
			return a.category < b.category
		end
		local ac, bc = a.class or "", b.class or ""
		if ac ~= bc then
			return ac < bc
		end
		local ak, bk = a.key or "", b.key or ""
		if ak ~= bk then
			return ak < bk
		end
		return a.id < b.id
	end)
	return out
end

-- Uses the addon's own guarded readers (SpellName/SpellIcon), so restricted values are
-- never stored. Resolve maps a static ID to the one in the player's spellbook, which is
-- how Forever's remapped IDs show up.
local function describe(entry)
	entry.name = ns.API.SpellName(entry.id)
	entry.icon = ns.API.SpellIcon(entry.id)
	entry.hint = ns.API.HintName(entry.id)
	local resolved = ns.API.Resolve(entry.id)
	if resolved and resolved ~= entry.id then
		entry.resolvedID = resolved
		entry.resolvedName = ns.API.SpellName(resolved)
		entry.resolvedIcon = ns.API.SpellIcon(resolved)
	end
end

local pending = false

function ns.DumpIcons()
	if pending then
		ns.Print("Icon dump already running.")
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("Icon dump: leave combat first.")
		return
	end
	local entries = collectEntries()
	if C_Spell and C_Spell.RequestLoadSpellData then
		for i = 1, #entries do
			pcall(C_Spell.RequestLoadSpellData, entries[i].id)
		end
	end
	pending = true
	ns.Print(("Icon dump: loading %d spells..."):format(#entries))
	C_Timer.After(2, function()
		pending = false
		local withIcon, notInClient, failed = 0, 0, 0
		for i = 1, #entries do
			local entry = entries[i]
			if not pcall(describe, entry) then
				failed = failed + 1
			end
			if entry.icon then
				withIcon = withIcon + 1
			end
			if not entry.name then
				notInClient = notInClient + 1
			end
		end
		local version, build = GetBuildInfo()
		local _, playerClass = UnitClass("player")
		WoWForeverIconDumpDB = {
			version = 1,
			build = tostring(version) .. "." .. tostring(build),
			locale = GetLocale(),
			playerClass = playerClass,
			dumpedAt = time(),
			entries = entries,
		}
		ns.Print(("Icon dump: %d spells, %d with icon, %d not in client, %d errors. Type /reload to save it to disk.")
			:format(#entries, withIcon, notInClient, failed))
	end)
end

SLASH_WFRDUMP1 = "/wfrdump"
SlashCmdList.WFRDUMP = function()
	ns.DumpIcons()
end
