module("CniExecLamp", package.seeall)

-- Follows the CNI-MU EXEC annunciator, which the module does not export. The titles of the
-- modifiable pages carry "MOD " while a change waits to be executed and "ACT " once it has been,
-- so the lamp is latched on a MOD title and released when the same page comes back without it
-- or when an EXEC key is pressed.
-- Lua port of CniExecLamp.cs of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

--- @class CniExecLamp
--- @field armed boolean
--- @field private marked_page string?
--- @field private presses integer?
local CniExecLamp = {}

local MODIFIED_PREFIX = "MOD "
local ACTIVE_PREFIX = "ACT "

--- @return CniExecLamp
function CniExecLamp:new()
	local o = {
		armed = false,
		marked_page = nil,
		presses = nil,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

local function trim_start(text)
	return (text:gsub("^%s+", ""))
end

local function starts_with(text, prefix)
	return text:sub(1, #prefix) == prefix
end

--- The title without its marker, so that the bare, MOD and ACT forms of a page compare equal
--- @param title string?
--- @return string?
local function page_of(title)
	if title == nil then
		return nil
	end

	local text = trim_start(title)
	for _, marker in ipairs({ MODIFIED_PREFIX, ACTIVE_PREFIX }) do
		if starts_with(text, marker) then
			return trim_start(text:sub(#marker + 1))
		end
	end
	return text
end

function CniExecLamp:release()
	self.armed = false
	self.marked_page = nil
end

--- @param title string? the title of the page on screen
--- @param exec_presses integer? how many times an EXEC key has been pressed so far
--- @return boolean armed
function CniExecLamp:update(title, exec_presses)
	if exec_presses ~= nil then
		-- any difference, not an increase: the counter restarts with the mission
		if self.presses ~= nil and self.presses ~= exec_presses then
			self:release()
		end
		self.presses = exec_presses
	end

	local page = page_of(title)

	if title ~= nil and starts_with(trim_start(title), MODIFIED_PREFIX) then
		self.armed = true
		self.marked_page = page
	elseif self.armed and self.marked_page ~= nil and self.marked_page == page then
		self:release()
	end

	return self.armed
end

return CniExecLamp
