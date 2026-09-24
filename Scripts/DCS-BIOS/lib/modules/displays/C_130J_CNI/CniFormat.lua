module("CniFormat", package.seeall)

-- Matching of CNI-MU element text against the printf formats the module's page scripts use.
-- Lua port of the format handling of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

--- @class CniFormatToken
--- @field kind integer
--- @field text string?

--- @class CniFormat
local CniFormat = {}

local LITERAL = 1
local ANY = 2 -- %s: any run of characters
local ONE = 3 -- %c: exactly one character
local INT = 4 -- %d and friends: a space-padded integer, or a run of placeholder characters
local FLOAT = 5 -- %f and friends: a space-padded decimal number, or a run of placeholder characters

local CONVERSION = "^%%([-+ #0]*%d*%.?%d*)([diufFgGeExXocs])"
local ANY_CONVERSION = "%%[-+ #0]*%d*%.?%d*[diufFgGeExXocs]"

local NEWLINE = 10
local MINUS = 45
local DOT = 46
local BRACKET = 93

--- Compiles a printf format into tokens.
--- An empty field is drawn as a run of placeholders ("-" for values the aircraft has not
--- computed, "]" for entry boxes), so every numeric conversion also accepts such a run.
--- @param fmt string
--- @return CniFormatToken[]
function CniFormat.compile(fmt)
	local tokens = {}
	local literal = {}

	local function flush()
		if #literal > 0 then
			tokens[#tokens + 1] = { kind = LITERAL, text = table.concat(literal) }
			literal = {}
		end
	end

	local i = 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local spec, conversion = fmt:match(CONVERSION, i)
			if spec ~= nil then
				flush()
				local kind = INT
				if conversion == "s" then
					kind = ANY
				elseif conversion == "c" then
					kind = ONE
				elseif conversion:match("[fFgGeE]") then
					kind = FLOAT
				end
				tokens[#tokens + 1] = { kind = kind }
				i = i + #spec + 2
			else
				-- a percent sign without a conversion is matched doubled, as the reference schema does
				literal[#literal + 1] = "%%"
				i = i + 1
			end
		else
			literal[#literal + 1] = c
			i = i + 1
		end
	end
	flush()

	return tokens
end

--- A string identifying the compiled form of a format, for comparing formats with each other
--- @param tokens CniFormatToken[]
--- @return string
function CniFormat.signature(tokens)
	local parts = {}
	for _, token in ipairs(tokens) do
		parts[#parts + 1] = token.kind == LITERAL and ("L" .. token.text) or tostring(token.kind)
	end
	return table.concat(parts, "\1")
end

local function is_space(b)
	return b == 32 or (b >= 9 and b <= 13)
end

local function is_digit(b)
	return b >= 48 and b <= 57
end

local function is_placeholder(b)
	return b == MINUS or b == BRACKET
end

local match_tokens

--- @param text string
--- @param pos integer
--- @param tokens CniFormatToken[]
--- @param ti integer
--- @param len integer
--- @param allow_dot boolean
--- @return boolean
local function match_number(text, pos, tokens, ti, len, allow_dot)
	-- a number: optional blanks, an optional sign and at least one digit
	local p = pos
	while p <= len and is_space(text:byte(p)) do
		p = p + 1
	end
	if p <= len and text:byte(p) == MINUS then
		p = p + 1
	end
	local e = p
	while e <= len do
		local b = text:byte(e)
		if not (is_digit(b) or (allow_dot and b == DOT)) then
			break
		end
		e = e + 1
		if match_tokens(text, e, tokens, ti + 1, len) then
			return true
		end
	end

	-- or a (possibly empty) run of placeholders
	e = pos
	if match_tokens(text, e, tokens, ti + 1, len) then
		return true
	end
	while e <= len and is_placeholder(text:byte(e)) do
		e = e + 1
		if match_tokens(text, e, tokens, ti + 1, len) then
			return true
		end
	end

	return false
end

--- @param text string
--- @param pos integer
--- @param tokens CniFormatToken[]
--- @param ti integer
--- @param len integer
--- @return boolean
match_tokens = function(text, pos, tokens, ti, len)
	local token = tokens[ti]
	if token == nil then
		return pos == len + 1
	end

	local kind = token.kind
	if kind == LITERAL then
		local stop = pos + #token.text - 1
		if stop > len or text:sub(pos, stop) ~= token.text then
			return false
		end
		return match_tokens(text, stop + 1, tokens, ti + 1, len)
	elseif kind == ANY then
		local stop = pos
		while stop <= len and text:byte(stop) ~= NEWLINE do
			stop = stop + 1
		end
		for e = stop, pos, -1 do
			if match_tokens(text, e, tokens, ti + 1, len) then
				return true
			end
		end
		return false
	elseif kind == ONE then
		if pos > len or text:byte(pos) == NEWLINE then
			return false
		end
		return match_tokens(text, pos + 1, tokens, ti + 1, len)
	end

	return match_number(text, pos, tokens, ti, len, kind == FLOAT)
end

--- Whether the text could have been produced by the format. A field drawn entirely as
--- placeholders is accepted by every format.
--- @param tokens CniFormatToken[]
--- @param text string
--- @return boolean
function CniFormat.accepts(tokens, text)
	if #tokens == 1 and tokens[1].kind == ANY then
		-- a bare "%s", the most common format, accepts anything on one line
		return text:find("\n", 1, true) == nil
	end
	if match_tokens(text, 1, tokens, 1, #text) then
		return true
	end
	return #text > 0 and text:find("^[%-%]]+$") ~= nil
end

--- @param formats CniFormatToken[][]
--- @param text string
--- @return boolean
function CniFormat.accepts_any(formats, text)
	for _, tokens in ipairs(formats) do
		if CniFormat.accepts(tokens, text) then
			return true
		end
	end
	return false
end

--- How much a list of formats constrains the text: the most literal characters outside the
--- conversions of any of them, capped at 3
--- @param fmts string[]?
--- @return integer
function CniFormat.specificity(fmts)
	if not fmts then
		return 0
	end
	local best = 0
	for _, f in ipairs(fmts) do
		local literal = f:gsub(ANY_CONVERSION, "")
		best = math.max(best, math.min(3, #literal))
	end
	return best
end

--- Whether a value still carries a printf conversion, i.e. is a format rather than text
--- @param value string
--- @return boolean
function CniFormat.has_conversion(value)
	return value:find(ANY_CONVERSION) ~= nil
end

--- Whether a format names its page number, like "2/%d" does for the second of several pages
--- @param fmt string
--- @return boolean
function CniFormat.pins_page_number(fmt)
	return fmt:find("^%d+/") ~= nil
end

return CniFormat
