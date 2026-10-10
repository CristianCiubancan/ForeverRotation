-- Minimal WoW client for offline tests. Lua 5.1, like the game.
--
-- M.new{ class = "MAGE" } compiles the add-on files once, then runs them in a
-- fresh environment with a fake client, so every instance starts from a clean
-- state (no leftover holds, cooldowns or caches). The UI files are not loaded:
-- the queue builders, the event handlers in Core.lua and Physics.lua, and the
-- bar index in Glow.lua are.
--
-- The world is plain data in T.W. Tests change it, then call T.queue() /
-- T.def() or T.press(spell) to drive the real UNIT_SPELLCAST_SUCCEEDED path.
--
-- Started from the mock in timgellings-cmd/ForeverRotation (MIT), extended to
-- every class, the spellbook, cooldowns, power, ranges, events and timers.
local M = {}

local ADDON_FILES = {
	"Locale.lua",
	"API.lua",
	"Data.lua",
	"Physics.lua",
	"Lists.lua",
	"APL.lua",
	"Glow.lua",
	"Rotations.lua",
	"Core.lua",
}

local CLASS_NAMES = {
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER = "Hunter",
	ROGUE = "Rogue",
	PRIEST = "Priest",
	SHAMAN = "Shaman",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	DRUID = "Druid",
}
M.CLASS_NAMES = CLASS_NAMES

local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

-- Primary power per class: 0 mana, 1 rage, 3 energy.
local PRIMARY_POWER = { WARRIOR = 1, ROGUE = 3 }

-- Yards. Everything harmful not listed here reaches 30 yd.
local RANGE = {
	-- melee
	Bloodthirst = 5, Cleave = 5, Disarm = 5, Execute = 5, Hamstring = 5, HeroicStrike = 5,
	MortalStrike = 5, Overpower = 5, Pummel = 5, Rend = 5, Revenge = 5, ShieldBash = 5,
	ShieldSlam = 5, Slam = 5, SunderArmor = 5, VictoryRush = 5, MockingBlow = 5, SpearingStrike = 5,
	Whirlwind = 5, ThunderClap = 5, DemoralizingShout = 5,
	CrusaderStrike = 5, HolyStrike = 5, Consecration = 5,
	Ambush = 5, Backstab = 5, CheapShot = 5, Eviscerate = 5, ExposeArmor = 5, Garrote = 5,
	GhostlyStrike = 5, Gouge = 5, Hemorrhage = 5, Kick = 5, KidneyShot = 5, Mutilate = 5,
	Riposte = 5, Rupture = 5, SinisterStrike = 5,
	Bash = 5, Claw = 5, FerociousBite = 5, Lacerate = 5, MangleBear = 5, MangleCat = 5,
	Maul = 5, Rake = 5, Ravage = 5, Rip = 5, Shred = 5, Swipe = 5, DemoralizingRoar = 5,
	Stormstrike = 5, RaptorStrike = 5, WingClip = 5, MongooseBite = 5, Counterattack = 5,
	-- short
	Judgement = 10, HammerofJustice = 10, SwiftJudgement = 10, ArcaneExplosion = 10,
	FrostNova = 10, ConeofCold = 10, BlastWave = 10, HolyNova = 10, FireNova = 10,
	-- charges and shocks
	Charge = 25, Intercept = 25, FeralCharge = 25, FeralChargeCat = 25,
	EarthShock = 20, FlameShock = 20, FrostShock = 20, HammerofWrath = 30,
	-- hunter shots
	ArcaneShot = 35, AimedShot = 35, MultiShot = 35, SerpentSting = 35, ViperSting = 35,
	ScorpidSting = 35, ConcussiveShot = 35, HuntersMark = 100, AutoShot = 35,
}

local function noop() end

-- Any method on a fake frame works and returns another fake frame, so UI
-- setup inside pcall never matters. Events and scripts are recorded.
local function newFrame(registry)
	local f = { _events = {}, _scripts = {} }
	function f:RegisterEvent(e)
		self._events[e] = true
	end
	function f:UnregisterEvent(e)
		self._events[e] = nil
	end
	function f:SetScript(kind, fn)
		self._scripts[kind] = fn
	end
	function f:GetScript(kind)
		return self._scripts[kind]
	end
	function f:IsShown()
		return false
	end
	if registry then
		registry[#registry + 1] = f
	end
	return setmetatable(f, {
		__index = function()
			return function()
				return newFrame(nil)
			end
		end,
	})
end

local function splitCamel(key)
	local s = key:gsub("(%l)(%u)", "%1 %2")
	return s
end

local chunks

local function compileAddon(repo)
	if chunks then
		return chunks
	end
	chunks = {}
	for _, file in ipairs(ADDON_FILES) do
		chunks[#chunks + 1] = { file = file, fn = assert(loadfile(repo .. "/" .. file)) }
	end
	return chunks
end

-- Build the fake client into env. W is the world; T gets helper functions.
local function install(env, W, T, frames, timers)
	local SECRET = setmetatable({}, { __tostring = function()
		return "SECRET"
	end })
	W.SECRET = SECRET
	local function hide(kind, value)
		if W.secret[kind] then
			return SECRET
		end
		return value
	end

	env._G = env
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		T.log[#T.log + 1] = table.concat(parts, " ")
	end
	env.GetTime = function()
		return W.now
	end
	env.time = function()
		return math.floor(W.now)
	end
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.strsub, env.strlower, env.strupper, env.strfind, env.strmatch = string.sub, string.lower, string.upper, string.find, string.match
	env.gsub, env.format, env.tinsert, env.tremove = string.gsub, string.format, table.insert, table.remove
	env.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	env.CopyTable = function(t)
		local o = {}
		for k, v in pairs(t) do
			o[k] = v
		end
		return o
	end
	env.GetLocale = function()
		return "enUS"
	end
	env.GetBuildInfo = function()
		return "1.60.1", "00000", "Jan 1 2026", 16001
	end
	env.issecretvalue = function(v)
		return v == SECRET
	end
	env.canaccessvalue = function(v)
		return v ~= SECRET
	end

	-- Timers run when the test advances the clock (T.advance / T.flush).
	env.C_Timer = {
		After = function(delay, fn)
			timers[#timers + 1] = { at = W.now + (tonumber(delay) or 0), fn = fn }
		end,
		NewTicker = function()
			return { Cancel = noop }
		end,
	}
	env.CreateFrame = function()
		return newFrame(frames)
	end
	env.SlashCmdList = {}

	-- Units --------------------------------------------------------------
	local function U(unit)
		if unit == "player" then
			return W.player
		end
		if unit == "targettarget" and W.target and W.target.targetsPlayer then
			return W.player
		end
		return W.units[unit] or (unit == "target" and W.target) or nil
	end
	env.UnitExists = function(u)
		return U(u) ~= nil
	end
	env.UnitIsDead = function(u)
		return U(u) and U(u).dead or false
	end
	env.UnitIsDeadOrGhost = env.UnitIsDead
	env.UnitCanAttack = function(_, u)
		return U(u) and U(u).hostile or false
	end
	env.UnitReaction = function(_, u)
		if not U(u) then
			return nil
		end
		return U(u).hostile and 2 or 5
	end
	env.UnitHealth = function(u)
		if not U(u) then
			return 0
		end
		return hide("health", U(u).hp or 100)
	end
	env.UnitHealthMax = function(u)
		return U(u) and 100 or 0
	end
	env.UnitPower = function(u, kind)
		if u ~= "player" then
			return 0
		end
		kind = kind or W.primaryPower
		return hide("power", W.power[kind] or 0)
	end
	env.UnitPowerMax = function(u, kind)
		if u ~= "player" then
			return 0
		end
		kind = kind or W.primaryPower
		return W.powerMax[kind] or 100
	end
	env.UnitLevel = function(u)
		return U(u) and (U(u).level or 60) or 0
	end
	env.UnitAffectingCombat = function(u)
		if u == "player" then
			return W.inCombat
		end
		local unit = U(u)
		if not unit then
			return false
		end
		if unit.combat ~= nil then
			return unit.combat
		end
		return W.inCombat and unit.hostile or false
	end
	env.UnitGUID = function(u)
		return U(u) and (U(u).guid or ("guid-" .. u)) or nil
	end
	env.UnitIsUnit = function(a, b)
		return a == b or (U(a) ~= nil and U(a) == U(b))
	end
	env.UnitClassification = function(u)
		return U(u) and U(u).classification or "normal"
	end
	env.UnitCreatureType = function(u)
		return U(u) and U(u).creature or "Humanoid"
	end
	env.UnitClass = function(u)
		if u ~= "player" then
			return nil
		end
		return CLASS_NAMES[W.class], W.class, CLASS_IDS[W.class]
	end
	env.UnitRace = function()
		return W.race.name, W.race.name, W.race.id
	end
	env.UnitFactionGroup = function()
		return W.race.faction, W.race.faction
	end
	env.UnitCastingInfo = function(u)
		local c = (u == "player" and W.casting) or (u == "target" and W.targetCasting) or nil
		if not c then
			return nil
		end
		return c.name, c.name, nil, c.startMs, c.endMs, false, nil, c.notInterruptible
	end
	env.UnitChannelInfo = function()
		return nil
	end
	env.UnitAttackSpeed = function()
		return W.swing.main, W.swing.off
	end
	env.UnitRangedDamage = function()
		return W.swing.ranged
	end
	env.IsCurrentSpell = function()
		return false
	end
	env.IsAutoRepeatSpell = function()
		return false
	end
	env.GetComboPoints = function()
		return W.combo
	end
	env.GetTotemInfo = function(slot)
		local t = W.totems[slot]
		if not t then
			return false
		end
		return true, t.name, t.start, t.duration
	end
	env.CheckInteractDistance = function(u, index)
		local unit = U(u)
		if not unit then
			return false
		end
		local d = unit.distance or 4
		if index == 3 then
			return d <= 10
		elseif index == 2 then
			return d <= 11
		end
		return d <= 28
	end
	env.IsMounted = function()
		return false
	end
	env.UnitOnTaxi = env.IsMounted
	env.IsResting = env.IsMounted
	env.GetInstanceInfo = function()
		return "Mock", "none"
	end
	env.GetInventoryItemID = function(_, slot)
		return (slot == 16 or slot == 17 or slot == 18) and 1000 + slot or nil
	end
	env.GetWeaponEnchantInfo = function()
		return false, 0, 0, 0, false, 0, 0, 0
	end
	env.GetNumShapeshiftForms = function()
		return 0
	end
	env.C_AddOns = {
		IsAddOnLoaded = function()
			return false
		end,
	}
	env.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }

	-- Spells -------------------------------------------------------------
	local function spellInfo(id)
		return W.spells[id]
	end
	local function knownList()
		local ids = {}
		for id in pairs(W.known) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		return ids
	end
	local function isKnown(id)
		return W.known[id] == true
	end
	env.IsPlayerSpell = isKnown
	env.IsSpellKnown = isKnown
	env.IsSpellKnownOrOverridesKnown = isKnown
	local function costOf(id)
		return W.costs[id]
	end
	local function affordable(id)
		local c = costOf(id)
		if not c then
			return true
		end
		return (W.power[c.type] or 0) >= c.cost
	end
	local function cooldownOf(id)
		local cd = W.cd[id]
		if not cd then
			return 0, 0
		end
		return cd.start, cd.duration
	end
	env.C_Spell = {
		GetSpellInfo = function(x)
			if type(x) == "number" then
				local s = spellInfo(x)
				if not s then
					return nil
				end
				return { name = s.name, spellID = x, maxRange = s.range, castTime = s.castMs or 0, iconID = 100000 + x }
			end
			if type(x) ~= "string" then
				return nil
			end
			local fallback
			for id, s in pairs(W.spells) do
				if s.name == x then
					if isKnown(id) then
						return { name = s.name, spellID = id, maxRange = s.range, castTime = s.castMs or 0, iconID = 100000 + id }
					end
					fallback = fallback or id
				end
			end
			if fallback then
				local s = W.spells[fallback]
				return { name = s.name, spellID = fallback, maxRange = s.range, castTime = s.castMs or 0, iconID = 100000 + fallback }
			end
		end,
		GetOverrideSpell = function(id)
			return id
		end,
		IsSpellUsable = function(id)
			if not isKnown(id) then
				return false, false
			end
			if W.procOnly[id] and not W.procUp[id] then
				return false, false
			end
			if not affordable(id) then
				return false, true
			end
			return true, false
		end,
		GetSpellCooldown = function(id)
			local start, duration = cooldownOf(id)
			return { startTime = hide("cooldowns", start), duration = hide("cooldowns", duration), isEnabled = true }
		end,
		GetSpellBaseCooldown = nil,
		IsSpellHelpful = function(id)
			return W.helpful[id] == true
		end,
		IsSpellHarmful = function(id)
			return W.harmful[id] == true
		end,
		GetSpellPowerCost = function(id)
			local c = costOf(id)
			if not c then
				return {}
			end
			return { { type = c.type, cost = c.cost, minCost = c.cost } }
		end,
		IsSpellInRange = function(id, unit)
			local s = spellInfo(id)
			local target = U(unit or "target")
			if not s or not target then
				return nil
			end
			local reach = s.range or 0
			if reach <= 0 then
				reach = 5
			end
			return (target.distance or 4) <= reach
		end,
		GetSpellTexture = function(id)
			return 100000 + id
		end,
	}
	env.GetSpellBaseCooldown = function(id)
		local s = spellInfo(id)
		return math.floor(((s and s.cooldown) or 0) * 1000), 1500
	end
	env.C_SpellBook = {
		GetNumSpellBookSkillLines = function()
			return 1
		end,
		GetSpellBookSkillLineInfo = function()
			return { itemIndexOffset = 0, numSpellBookItems = #knownList() }
		end,
		GetSpellBookItemInfo = function(index, bank)
			if bank ~= 0 then
				return nil
			end
			local id = knownList()[index]
			if not id then
				return nil
			end
			return { name = W.spells[id] and W.spells[id].name, spellID = id }
		end,
		IsSpellInSpellBook = isKnown,
		FindSpellBookSlotForSpell = function(id)
			for i, known in ipairs(knownList()) do
				if known == id then
					return i
				end
			end
		end,
	}

	-- Auras --------------------------------------------------------------
	-- W.auras[unit] = { { name, spellId, expirationTime, applications, filter, dispelName, isStealable } }
	local function aurasFor(unit, filter)
		local out = {}
		local list = W.auras[unit]
		if unit == "targettarget" and W.target and W.target.targetsPlayer then
			list = W.auras.player
		end
		for _, a in ipairs(list or {}) do
			if a.expirationTime == nil or a.expirationTime > W.now then
				if (filter or "HELPFUL"):find(a.filter, 1, true) then
					out[#out + 1] = a
				end
			end
		end
		return out
	end
	local function hidden(a)
		return { name = SECRET, spellId = SECRET, expirationTime = SECRET, applications = SECRET, dispelName = SECRET }
	end
	env.C_UnitAuras = {
		GetAuraDataByIndex = function(unit, i, filter)
			local a = aurasFor(unit, filter)[i]
			if a and W.secret.auras then
				return hidden(a)
			end
			return a
		end,
		GetAuraDataBySpellName = function(unit, name, filter)
			if W.secret.auras then
				return nil
			end
			for _, a in ipairs(aurasFor(unit, filter)) do
				if a.name == name then
					return a
				end
			end
		end,
		GetPlayerAuraBySpellID = function(id)
			if W.secret.auras then
				return nil
			end
			for _, a in ipairs(aurasFor("player", "HELPFUL")) do
				if a.spellId == id then
					return a
				end
			end
		end,
	}
end

-- Names, schools and ranges for every spell ID the add-on knows about.
local function buildSpellbook(ns, W)
	local function add(id, key, className)
		if type(id) ~= "number" or W.spells[id] then
			return
		end
		local hint = ns.SPELL_NAME_HINT and ns.SPELL_NAME_HINT[id]
		local name = type(hint) == "table" and hint.enUS or nil
		if type(name) == "table" then
			name = name[1]
		end
		name = name or (key and splitCamel(key)) or ("Spell " .. id)
		W.spells[id] = { key = key or ("Spell" .. id), name = name, className = className, range = 0, cooldown = 0 }
	end
	local classKeys = {}
	local classNames = {}
	for className in pairs(ns.Spell) do
		classNames[#classNames + 1] = className
	end
	table.sort(classNames)
	for _, className in ipairs(classNames) do
		local spells = ns.Spell[className]
		local keys = {}
		for key in pairs(spells) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		classKeys[className] = keys
		for _, key in ipairs(keys) do
			add(spells[key], key, className)
		end
	end
	for _, r in ipairs(ns.RACIALS or {}) do
		add(r.id, r.key, "Racial")
	end
	for _, list in pairs(ns.WEAPON_BUFFS or {}) do
		for _, entry in ipairs(list) do
			add(entry.id, entry.key, "Weapon")
		end
	end
	for _, id in pairs(ns.INTERRUPTS or {}) do
		add(id)
	end
	for _, id in pairs(ns.PURGES or {}) do
		add(id)
	end
	for _, list in pairs(ns.CLEANSE or {}) do
		for _, entry in ipairs(list) do
			add(entry.id)
		end
	end

	-- Schools come from how the default lists use each spell.
	local function scanSteps(steps)
		for _, step in ipairs(steps or {}) do
			local opt = step.opt or {}
			if step.id then
				if opt.hostile then
					W.harmful[step.id] = true
				end
				if opt.heal then
					W.helpful[step.id] = true
				end
				if opt.proc then
					W.procOnly[step.id] = true
				end
			end
		end
	end
	for _, root in ipairs({ ns.APLDefaults, ns.DefDefaults }) do
		for _, specs in pairs(root or {}) do
			for _, steps in pairs(specs) do
				scanSteps(steps)
			end
		end
	end
	for _, specs in pairs(ns.APLModes or {}) do
		for _, modes in pairs(specs) do
			for _, steps in pairs(modes) do
				scanSteps(steps)
			end
		end
	end
	for _, id in pairs(ns.INTERRUPTS or {}) do
		W.harmful[id] = true
	end
	for _, id in pairs(ns.PURGES or {}) do
		W.harmful[id] = true
	end
	for id in pairs(ns.HEAL_SPELL_IDS or {}) do
		W.helpful[id] = true
	end
	for id in pairs(ns.MAINTENANCE_BUFF_IDS or {}) do
		W.helpful[id] = true
	end

	for id, s in pairs(W.spells) do
		if W.harmful[id] then
			s.range = RANGE[s.key] or 30
		elseif W.helpful[id] then
			s.range = 40
		end
		s.cooldown = (ns.COOLDOWNS and ns.COOLDOWNS[id]) or 0
	end
	return classKeys
end

local function defaultWorld(class)
	return {
		now = 1000,
		class = class,
		race = { name = "Human", id = 1, faction = "Alliance" },
		player = { hp = 100, level = 60 },
		target = nil,
		units = {},
		auras = {},
		known = {},
		spells = {},
		harmful = {},
		helpful = {},
		procOnly = {},
		procUp = {},
		costs = {},
		cd = {},
		power = { [0] = 100, [1] = 50, [3] = 100 },
		powerMax = { [0] = 100, [1] = 100, [3] = 100 },
		primaryPower = PRIMARY_POWER[class] or 0,
		combo = 0,
		totems = {},
		swing = { main = 2.6, off = nil, ranged = 2.8 },
		secret = { auras = false, health = false, power = false, cooldowns = false },
		inCombat = false,
	}
end

-- opts: class (token), repo (path, default "."), learn (default true), race.
function M.new(opts)
	opts = opts or {}
	local class = opts.class or "WARRIOR"
	local W = defaultWorld(class)
	if opts.race then
		W.race = opts.race
	end
	local T = { W = W, log = {} }
	local frames, timers = {}, {}
	local env = setmetatable({}, { __index = _G })
	install(env, W, T, frames, timers)

	local ns = {}
	for _, c in ipairs(compileAddon(opts.repo or ".")) do
		if c.file == "Core.lua" then
			-- UI.lua / Options.lua are not loaded: give Core the calls it makes.
			ns.UI = { Create = noop }
		end
		setfenv(c.fn, env)
		c.fn("WoWForeverRot", ns)
	end
	T.ns, T.env = ns, env
	T.classKeys = buildSpellbook(ns, W)
	local S = ns.Spell[CLASS_NAMES[class]]
	T.S = S

	function T.id(spell)
		if type(spell) == "number" then
			return spell
		end
		return S[spell] or error("unknown spell key for " .. class .. ": " .. tostring(spell))
	end
	function T.label(id)
		local s = W.spells[id]
		return s and s.key or tostring(id)
	end

	-- Clock and timers.
	function T.flush()
		for _ = 1, 10000 do
			local pick
			for i, t in ipairs(timers) do
				if t.at <= W.now then
					pick = i
					break
				end
			end
			if not pick then
				return
			end
			local t = table.remove(timers, pick)
			t.fn()
		end
		error("timer loop did not settle")
	end
	function T.advance(seconds)
		W.now = W.now + seconds
		T.flush()
	end
	function T.fire(event, ...)
		for _, f in ipairs(frames) do
			if f._events[event] and f._scripts.OnEvent then
				f._scripts.OnEvent(f, event, ...)
			end
		end
		T.flush()
	end

	-- Spellbook.
	function T.learn(keys)
		for _, key in ipairs(keys) do
			W.known[T.id(key)] = true
		end
	end
	function T.learnAll()
		for _, key in ipairs(T.classKeys[CLASS_NAMES[class]]) do
			W.known[S[key]] = true
		end
	end
	function T.forget(keys)
		if not keys then
			W.known = {}
			return
		end
		for _, key in ipairs(keys) do
			W.known[T.id(key)] = nil
		end
	end
	function T.refresh()
		ns.API.InvalidateSpells(true)
		ns.API.RebuildSpellBookIndex(true)
		T.flush()
	end

	-- World helpers.
	function T.target(fields)
		if fields == false then
			W.target = nil
			return
		end
		W.target = { hp = 100, hostile = true, distance = 4, guid = "mob-1" }
		for k, v in pairs(fields or {}) do
			W.target[k] = v
		end
		W.auras.target = nil
	end
	function T.aura(unit, spell, filter, remain, stacks)
		local id = T.id(spell)
		W.auras[unit] = W.auras[unit] or {}
		local list = W.auras[unit]
		for i = #list, 1, -1 do
			if list[i].spellId == id then
				table.remove(list, i)
			end
		end
		list[#list + 1] = {
			name = W.spells[id] and W.spells[id].name or tostring(id),
			spellId = id,
			expirationTime = remain and (W.now + remain) or nil,
			applications = stacks or 1,
			filter = filter or "HELPFUL",
		}
	end
	function T.unaura(unit, spell)
		local id = T.id(spell)
		for i = #(W.auras[unit] or {}), 1, -1 do
			if W.auras[unit][i].spellId == id then
				table.remove(W.auras[unit], i)
			end
		end
	end
	function T.enemies(n, distance)
		for i = 1, 40 do
			W.units["nameplate" .. i] = nil
		end
		for i = 1, n do
			W.units["nameplate" .. i] = { hp = 100, hostile = true, distance = distance or 6, guid = "plate-" .. i, combat = true }
		end
	end
	function T.cost(spell, kind, amount)
		W.costs[T.id(spell)] = { type = kind, cost = amount }
	end

	local function freshCaches()
		ns.InvalidateAPLCache()
		ns.API.WipeAuraScans()
	end
	local function labels(ids)
		local out = {}
		for i, id in ipairs(ids) do
			out[i] = T.label(id)
		end
		return table.concat(out, ", ")
	end
	function T.queueIds()
		freshCaches()
		return ns.BuildQueue()
	end
	function T.queue()
		return labels(T.queueIds())
	end
	function T.def()
		freshCaches()
		local id = ns.BuildDefense()
		return id and T.label(id) or "-"
	end

	-- Find the list step for a spell in the active list (for press effects).
	local function stepFor(id)
		for _, step in ipairs(ns.GetAPL() or {}) do
			if step.id == id then
				return step
			end
		end
		for _, step in ipairs(ns.GetDef() or {}) do
			if step.id == id then
				return step
			end
		end
	end

	-- Cast a spell the way the game would: spend, start the cooldown, apply
	-- the aura the list expects, then fire UNIT_SPELLCAST_SUCCEEDED.
	function T.press(spell)
		local id = T.id(spell)
		local s = W.spells[id] or {}
		local c = W.costs[id]
		if c then
			W.power[c.type] = math.max(0, (W.power[c.type] or 0) - c.cost)
		end
		if s.cooldown and s.cooldown > 0 then
			W.cd[id] = { start = W.now, duration = s.cooldown }
		end
		local step = stepFor(id)
		local opt = step and step.opt or {}
		if opt.nodebuff and W.target then
			local debuff = opt.nodebuff == true and id or opt.nodebuff
			local holdFor = ns.SPELL_HOLD and ns.SPELL_HOLD[id]
			T.aura("target", debuff, "HARMFUL", (holdFor and holdFor > 0) and holdFor or 15)
		end
		if opt.nobuff then
			T.aura("player", id, "HELPFUL", ns.IsMaintenanceBuff(id) and 1800 or 30)
		end
		if opt.comboMin then
			W.combo = 0
		elseif ns.COMBO_BUILDERS and ns.COMBO_BUILDERS[id] then
			W.combo = math.min(5, W.combo + 1)
		end
		T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. id, id)
	end

	if opts.learn ~= false then
		T.learnAll()
	end
	T.fire("PLAYER_LOGIN")
	T.refresh()
	return T
end

return M
