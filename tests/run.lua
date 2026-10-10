-- Offline tests. Run from the repo root with Lua 5.1 (the game's version):
--   lua5.1 tests/run.lua
--   lua5.1 tests/run.lua --update-golden   (rewrite tests/golden/*.txt)
-- Not listed in any TOC: the game never loads this folder.
package.path = "./tests/?.lua;" .. package.path

local H = require("harness")
local update = false
for _, a in ipairs(arg or {}) do
	if a == "--update-golden" then
		update = true
	end
end

require("spec_repo")(H)
require("spec_queue")(H)
require("spec_bars")(H)
require("spec_lookahead")(H)
require("golden").run(H, update)

if update then
	io.write("golden files rewritten in tests/golden/\n")
end
H.finish()
