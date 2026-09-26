module("TempPath", package.seeall)

--- @class TempPath
--- Temporary files for tests that write to disk
TempPath = {}

--- Returns the path of a temporary file the tests may write to.
---
--- os.tmpname() is enough where it gives a full path, as it does on Linux. On Windows it gives a
--- bare name like "\s1a2." in the root of the current drive, which a normal user may not write
--- to, so there the name is placed in the TEMP directory instead.
--- @return string path the path of the temporary file
function TempPath.new()
	local name = os.tmpname()
	local temp = os.getenv("TEMP") or os.getenv("TMP")
	local bare = name:sub(1, 1) == "\\" and not name:find(":", 1, true)
	if bare and temp then
		return temp .. name
	end
	return name
end

return TempPath
