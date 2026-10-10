-- Tiny test registry and assertions. No dependencies beyond Lua 5.1.
local H = { passes = 0, fails = 0, current = nil }

local function fail(msg)
	error({ testFailure = msg }, 0)
end

function H.test(name, fn)
	H.current = name
	local ok, err = xpcall(fn, function(e)
		if type(e) == "table" and e.testFailure then
			return e.testFailure
		end
		return debug.traceback(tostring(e), 2)
	end)
	if ok then
		H.passes = H.passes + 1
	else
		H.fails = H.fails + 1
		io.write("FAIL  ", name, "\n      ", tostring(err):gsub("\n", "\n      "), "\n")
	end
end

-- got == want
function H.eq(got, want, what)
	if got ~= want then
		fail(string.format("%s\n  got:  %s\n  want: %s", what or "values differ", tostring(got), tostring(want)))
	end
end

-- The queue string starts with spell `want`.
function H.first(queue, want)
	local head = queue:match("^([^,]+)")
	if head ~= want then
		fail(string.format("slot 1 should be %s\n  queue: [%s]", want, queue))
	end
end

-- The queue string contains / lacks a spell (whole names only).
local function hasSpell(queue, spell)
	for name in (queue .. ","):gmatch("%s*([^,]+),") do
		if name == spell then
			return true
		end
	end
	return false
end

function H.has(queue, spell)
	if not hasSpell(queue, spell) then
		fail(string.format("queue should contain %s\n  queue: [%s]", spell, queue))
	end
end

function H.lacks(queue, spell)
	if hasSpell(queue, spell) then
		fail(string.format("queue must not contain %s\n  queue: [%s]", spell, queue))
	end
end

function H.ok(value, what)
	if not value then
		fail(what or "expected a true value")
	end
end

function H.finish()
	io.write(string.format("\n%d passed, %d failed\n", H.passes, H.fails))
	os.exit(H.fails == 0 and 0 or 1)
end

return H
