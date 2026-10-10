-- Repository consistency that a release depends on.
local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

return function(H)
	H.test("release: both TOCs are identical and list existing files", function()
		local a, b = read("WoWForeverRot.toc"), read("WoWForeverRot_Camelot.toc")
		H.ok(a and b, "both TOC files must exist")
		H.eq(a, b, "WoWForeverRot.toc and WoWForeverRot_Camelot.toc must be identical")
		local count = 0
		for file in a:gmatch("[\r\n]([%w_]+%.lua)") do
			count = count + 1
			H.ok(read(file) ~= nil, file .. " is listed in the TOC but missing")
		end
		H.ok(count > 10, "TOC lists only " .. count .. " Lua files")
	end)

	H.test("release: VERSION.txt and the TOCs carry the same version", function()
		local version = (read("VERSION.txt") or ""):match("^%s*(%d+%.%d+%.%d+)")
		H.ok(version, "VERSION.txt must start with x.y.z")
		local tocVersion = read("WoWForeverRot.toc"):match("## Version: ([^\r\n]+)")
		H.eq(tocVersion, version, "## Version in the TOCs vs VERSION.txt")
	end)

	H.test("release: no CurseForge project ID in the TOCs", function()
		H.ok(not read("WoWForeverRot.toc"):find("X-Curse-Project-ID", 1, true),
			"X-Curse-Project-ID would let the CurseForge app replace this build with the original 1.5.72")
	end)
end
