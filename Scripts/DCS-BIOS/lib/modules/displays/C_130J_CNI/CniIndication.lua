module("CniIndication", package.seeall)

-- Parses a CNI-MU indication into a tree, keeping which elements are children of a container.
-- Lua port of the indication parsing of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

--- @class CniBlock
--- @field n integer position in document order, children included
--- @field k string element name; a GUID except for cni_title and cni_scratchpad
--- @field v string element text
--- @field c CniBlock[]? visible children of a container

--- @class CniIndication
local CniIndication = {}

local INDICATION_SPLIT = "-----------------------------------------"
local CHILDREN_START = "children are {"
local CHILDREN_END = "}"

--- Parses an indication, keeping the nesting: a toggle draws a container whose visible
--- children are its words, and which container was drawn is part of what the page shows.
--- @param indication string?
--- @return CniBlock[]? blocks top level blocks, or nil for an empty indication
--- @return integer total number of blocks including children
function CniIndication.parse(indication)
	if not indication or indication == "" then
		return nil, 0
	end

	local root = {}
	local stack = { root }
	local node, value_lines, total = nil, nil, 0

	local function flush()
		if not node then
			return nil
		end

		total = total + 1
		node.n = total
		node.v = value_lines and table.concat(value_lines, "\n") or ""
		value_lines = nil

		local list = stack[#stack]
		list[#list + 1] = node

		local done = node
		node = nil
		return done
	end

	if indication:sub(-1) ~= "\n" then
		indication = indication .. "\n"
	end

	for line in string.gmatch(indication, "([^\n]*)\n") do
		if line == INDICATION_SPLIT then
			flush()
			node = {}
		elseif line == CHILDREN_START then
			-- the node just closed is the container; everything up to the matching brace belongs to it
			local parent = flush()
			if parent then
				parent.c = {}
				stack[#stack + 1] = parent.c
			end
		elseif line == CHILDREN_END then
			flush()
			if #stack > 1 then
				table.remove(stack)
			end
		elseif node then
			if node.k == nil then
				node.k = line
			else
				value_lines = value_lines or {}
				value_lines[#value_lines + 1] = line
			end
		end
	end

	flush()
	return root, total
end

--- Blocks in document order, children directly after their container
--- @param blocks CniBlock[]?
--- @return CniBlock[]
function CniIndication.flatten(blocks)
	local flat = {}

	local function walk(nodes)
		for _, node in ipairs(nodes or {}) do
			flat[#flat + 1] = node
			walk(node.c)
		end
	end

	walk(blocks)
	return flat
end

--- The first top level block with the given name
--- @param blocks CniBlock[]?
--- @param name string
--- @return CniBlock?
function CniIndication.find_named(blocks, name)
	for _, block in ipairs(blocks or {}) do
		if block.k == name then
			return block
		end
	end
	return nil
end

return CniIndication
