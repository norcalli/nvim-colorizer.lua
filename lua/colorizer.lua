--- Highlights terminal CSI ANSI color codes.
-- @module colorizer
local nvim = require 'colorizer/nvim'
local Trie = require 'colorizer/trie'
local bit = require 'bit'
local ffi = require 'ffi'

local vim = vim
local nvim_buf_add_highlight = vim.api.nvim_buf_add_highlight
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local band, lshift, bor, tohex = bit.band, bit.lshift, bit.bor, bit.tohex
local rshift = bit.rshift
local floor, min, max = math.floor, math.min, math.max

local COLOR_MAP
local COLOR_TRIE
local COLOR_NAME_MINLEN, COLOR_NAME_MAXLEN
local COLOR_NAME_SETTINGS = {
	lowercase = false;
	strip_digits = false;
}

--- Setup the COLOR_MAP and COLOR_TRIE
local function initialize_trie()
	if not COLOR_TRIE then
		COLOR_MAP = {}
		COLOR_TRIE = Trie()
		for k, v in pairs(nvim.get_color_map()) do
			if not (COLOR_NAME_SETTINGS.strip_digits and k:match("%d+$")) then
				COLOR_NAME_MINLEN = COLOR_NAME_MINLEN and min(#k, COLOR_NAME_MINLEN) or #k
				COLOR_NAME_MAXLEN = COLOR_NAME_MAXLEN and max(#k, COLOR_NAME_MAXLEN) or #k
				local rgb_hex = tohex(v, 6)
				COLOR_MAP[k] = rgb_hex
				COLOR_TRIE:insert(k)
				if COLOR_NAME_SETTINGS.lowercase then
					local lowercase = k:lower()
					COLOR_MAP[lowercase] = rgb_hex
					COLOR_TRIE:insert(lowercase)
				end
			end
		end
	end
end

local function merge(...)
	local res = {}
	for i = 1,select("#", ...) do
		local o = select(i, ...)
		for k,v in pairs(o) do
			res[k] = v
		end
	end
	return res
end

local DEFAULT_OPTIONS = {
	RGB      = true;         -- #RGB hex codes
	RRGGBB   = true;         -- #RRGGBB hex codes
	names    = true;         -- "Name" codes like Blue
	RRGGBBAA = false;        -- #RRGGBBAA hex codes
	rgb_fn   = false;        -- CSS rgb() and rgba() functions
	hsl_fn   = false;        -- CSS hsl() and hsla() functions
	css      = false;        -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
	css_fn   = false;        -- Enable all CSS *functions*: rgb_fn, hsl_fn
	-- Available modes: foreground, background
	mode     = 'background'; -- Set the display mode.
}

-- -- TODO use rgb as the return value from the matcher functions
-- -- instead of the rgb_hex. Can be the highlight key as well
-- -- when you shift it left 8 bits. Use the lower 8 bits for
-- -- indicating which highlight mode to use.
-- ffi.cdef [[
-- typedef struct { uint8_t r, g, b; } colorizer_rgb;
-- ]]
-- local rgb_t = ffi.typeof 'colorizer_rgb'

-- Create a lookup table where the bottom 4 bits are used to indicate the
-- category and the top 4 bits are the hex value of the ASCII byte.
local BYTE_CATEGORY = ffi.new 'uint8_t[256]'
local CATEGORY_DIGIT    = lshift(1, 0);
local CATEGORY_ALPHA    = lshift(1, 1);
local CATEGORY_HEX      = lshift(1, 2);
local CATEGORY_ALPHANUM = bor(CATEGORY_ALPHA, CATEGORY_DIGIT)
do
	local b = string.byte
	for i = 0, 255 do
		local v = 0
		-- Digit is bit 1
		if i >= b'0' and i <= b'9' then
			v = bor(v, lshift(1, 0))
			v = bor(v, lshift(1, 2))
			v = bor(v, lshift(i - b'0', 4))
		end
		local lowercase = bor(i, 0x20)
		-- Alpha is bit 2
		if lowercase >= b'a' and lowercase <= b'z' then
			v = bor(v, lshift(1, 1))
			if lowercase <= b'f' then
				v = bor(v, lshift(1, 2))
				v = bor(v, lshift(lowercase - b'a'+10, 4))
			end
		end
		BYTE_CATEGORY[i] = v
	end
end

local function byte_is_hex(byte)
	return band(BYTE_CATEGORY[byte], CATEGORY_HEX) ~= 0
end

local function byte_is_alphanumeric(byte)
	local category = BYTE_CATEGORY[byte]
	return band(category, CATEGORY_ALPHANUM) ~= 0
end

local function parse_hex(b)
	return rshift(BYTE_CATEGORY[b], 4)
end

local function percent_or_hex(v)
	if v:sub(-1,-1) == "%" then
		return tonumber(v:sub(1,-2))/100*255
	end
	local x = tonumber(v)
	if x > 255 then return end
	return x
end

--- Determine whether to use black or white text
-- Ref: https://stackoverflow.com/a/1855903/837964
-- https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
local function color_is_bright(r, g, b)
	-- Counting the perceptive luminance - human eye favors green color
	local luminance = (0.299*r + 0.587*g + 0.114*b)/255
	if luminance > 0.5 then
		return true -- Bright colors, black font
	else
		return false -- Dark colors, white font
	end
end

-- https://gist.github.com/mjackson/5311256
local function hue_to_rgb(p, q, t)
	if t < 0 then t = t + 1 end
	if t > 1 then t = t - 1 end
	if t < 1/6 then return p + (q - p) * 6 * t end
	if t < 1/2 then return q end
	if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
	return p
end

local function hsl_to_rgb(h, s, l)
	if h > 1 or s > 1 or l > 1 then return end
	if s == 0 then
		local r = l * 255
		return r, r, r
	end
	local q
	if l < 0.5 then
		q = l * (1 + s)
	else
		q = l + s - l * s
	end
	local p = 2 * l - q
	return 255*hue_to_rgb(p, q, h + 1/3), 255*hue_to_rgb(p, q, h), 255*hue_to_rgb(p, q, h - 1/3)
end

local function rgb_to_hsl(r, g, b)
	r = r / 255
	g = g / 255
	b = b / 255
	local c_max = max(r, g, b)
	local c_min = min(r, g, b)
	local chroma = c_max - c_min
	if chroma == 0 then
		return 0, 0, 0
	end
	local l = (c_max + c_min) / 2
	local s = chroma / (1 - math.abs(2*l-1))
	local h
	if c_max == r then
		h = ((g - b) / chroma) % 6
	elseif c_max == g then
		h = (b - r) / chroma + 2;
	elseif c_max == b then
		h = (r - g) / chroma + 4;
	end

	h = floor(h * 60)
	s = floor(s * 100)
	l = floor(l * 100)
	return h, s, l
end

local function color_name_parser(line, i)
	if i > 1 and byte_is_alphanumeric(line:byte(i-1)) then
		return
	end
	if #line < i + COLOR_NAME_MINLEN - 1 then return end
	local prefix = COLOR_TRIE:longest_prefix(line, i)
	if prefix then
		-- Check if there is a letter here so as to disallow matching here.
		-- Take the Blue out of Blueberry
		-- Line end or non-letter.
		local next_byte_index = i + #prefix
		if #line >= next_byte_index and byte_is_alphanumeric(line:byte(next_byte_index)) then
			return
		end
		return #prefix, COLOR_MAP[prefix]
	end
end

-- Converts a number to its rgb parts
local function num_to_rgb(n)
	n = tonumber(n)
	return band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF)
end

-- Converts a number to its rgb parts
local function rgb_to_num(r, g, b)
	return bor(lshift(band(r, 0xFF), 16), lshift(band(g, 0xFF), 8), band(b, 0xFF))
end

-- Converts a number to its rgb parts
local function rgb_to_hex(r, g, b)
	return tohex(rgb_to_num(r, g, b), 6)
end

local b_hash = ("#"):byte()
local function rgb_hex_parser(line, i, minlen, maxlen)
	if i > 1 and byte_is_alphanumeric(line:byte(i-1)) then
		return
	end
	if line:byte(i) ~= b_hash then
		return
	end
	local j = i + 1
	if #line < j + minlen - 1 then return end
	local n = j + maxlen
	local alpha
	local v = 0
	while j <= min(n, #line) do
		local b = line:byte(j)
		if not byte_is_hex(b) then break end
		if j - i >= 7 then
			alpha = parse_hex(b) + lshift(alpha or 0, 4)
		else
			v = parse_hex(b) + lshift(v, 4)
		end
		j = j + 1
	end
	if #line >= j and byte_is_alphanumeric(line:byte(j)) then
		return
	end
	local length = j - i
	if length ~= 4 and length ~= 7 and length ~= 9 then return end
	if alpha then
		alpha = tonumber(alpha)/255
		local r, g, b = num_to_rgb(v)
		return 9, rgb_to_hex(floor(r*alpha), floor(g*alpha), floor(b*alpha))
	end
	local rgb_hex = line:sub(i+1, i+length-1)
	if length == 4 then
		local x = tonumber(rgb_hex, 16)
		local r,g,b = band(rshift(x, 8), 0xF), band(rshift(x, 4), 0xF), band(x, 0xF)
		r, g, b = bor(r, lshift(r, 4)), bor(g, lshift(g, 4)), bor(b, lshift(b, 4))
		return 4, rgb_to_hex(r,g,b)
	end
	return 7, rgb_hex
end

-- TODO consider removing the regexes here
-- TODO this might not be the best approach to alpha channel.
-- Things like pumblend might be useful here.
local css_fn = {}
do
	local CSS_RGB_FN_MINIMUM_LENGTH = #'rgb(0,0,0)' - 1
	local CSS_RGBA_FN_MINIMUM_LENGTH = #'rgba(0,0,0,0)' - 1
	local CSS_HSL_FN_MINIMUM_LENGTH = #'hsl(0,0%,0%)' - 1
	local CSS_HSLA_FN_MINIMUM_LENGTH = #'hsla(0,0%,0%,0)' - 1
	function css_fn.rgb(line, i)
		if #line < i + CSS_RGB_FN_MINIMUM_LENGTH then return end
		local r, g, b, match_end = line:sub(i):match("^rgb%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*%)()")
		if not match_end then return end
		r = percent_or_hex(r) if not r then return end
		g = percent_or_hex(g) if not g then return end
		b = percent_or_hex(b) if not b then return end
		return match_end - 1, rgb_to_hex(r, g, b)
	end
	function css_fn.hsl(line, i)
		if #line < i + CSS_HSL_FN_MINIMUM_LENGTH then return end
		local h, s, l, match_end = line:sub(i):match("^hsl%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*%)()")
		if not match_end then return end
		h = tonumber(h) if h > 360 then return end
		s = tonumber(s) if s > 100 then return end
		l = tonumber(l) if l > 100 then return end
		local r, g, b = hsl_to_rgb(h/360, s/100, l/100)
		if r == nil or g == nil or b == nil then return end
		return match_end - 1, rgb_to_hex(floor(r), floor(g), floor(b))
	end
	function css_fn.rgba(line, i)
		if #line < i + CSS_RGBA_FN_MINIMUM_LENGTH then return end
		local r, g, b, a, match_end = line:sub(i):match("^rgba%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*([.%d]+)%s*%)()")
		if not match_end then return end
		a = tonumber(a) if not a or a > 1 then return end
		r = percent_or_hex(r) if not r then return end
		g = percent_or_hex(g) if not g then return end
		b = percent_or_hex(b) if not b then return end
		return match_end - 1, rgb_to_hex(floor(r*a), floor(g*a), floor(b*a))
	end
	function css_fn.hsla(line, i)
		if #line < i + CSS_HSLA_FN_MINIMUM_LENGTH then return end
		local h, s, l, a, match_end = line:sub(i):match("^hsla%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*,%s*([.%d]+)%s*%)()")
		if not match_end then return end
		a = tonumber(a) if not a or a > 1 then return end
		h = tonumber(h) if h > 360 then return end
		s = tonumber(s) if s > 100 then return end
		l = tonumber(l) if l > 100 then return end
		local r, g, b = hsl_to_rgb(h/360, s/100, l/100)
		if r == nil or g == nil or b == nil then return end
		return match_end - 1, rgb_to_hex(floor(r*a), floor(g*a), floor(b*a))
	end
end
local css_function_parser, rgb_function_parser, hsl_function_parser
do
	local CSS_FUNCTION_TRIE = Trie {'rgb', 'rgba', 'hsl', 'hsla'}
	local RGB_FUNCTION_TRIE = Trie {'rgb', 'rgba'}
	local HSL_FUNCTION_TRIE = Trie {'hsl', 'hsla'}
	css_function_parser = function(line, i)
		local prefix = CSS_FUNCTION_TRIE:longest_prefix(line:sub(i))
		if prefix then
			return css_fn[prefix](line, i)
		end
	end
	rgb_function_parser = function(line, i)
		local prefix = RGB_FUNCTION_TRIE:longest_prefix(line:sub(i))
		if prefix then
			return css_fn[prefix](line, i)
		end
	end
	hsl_function_parser = function(line, i)
		local prefix = HSL_FUNCTION_TRIE:longest_prefix(line:sub(i))
		if prefix then
			return css_fn[prefix](line, i)
		end
	end
end

local function compile_matcher(matchers)
	local parse_fn = matchers[1]
	for j = 2, #matchers do
		local old_parse_fn = parse_fn
		local new_parse_fn = matchers[j]
		parse_fn = function(line, i)
			local length, rgb_hex = new_parse_fn(line, i)
			if length then return length, rgb_hex end
			return old_parse_fn(line, i)
		end
	end
	return parse_fn
end

--- Default namespace used in `highlight_buffer` and `attach_to_buffer`.
-- The name is "terminal_highlight"
-- @see highlight_buffer
-- @see attach_to_buffer
local DEFAULT_NAMESPACE = nvim.create_namespace "colorizer"
local HIGHLIGHT_NAME_PREFIX = "colorizer"
local HIGHLIGHT_MODE_NAMES = {
	background = "mb";
	foreground = "mf";
}
local HIGHLIGHT_CACHE = {}

--- Make a deterministic name for a highlight given these attributes
local function make_highlight_name(rgb, mode)
	return table.concat({HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb}, '_')
end

local function create_highlight(rgb_hex, options)
	local mode = options.mode or 'background'
	-- TODO validate rgb format?
	rgb_hex = rgb_hex:lower()
	local cache_key = HIGHLIGHT_MODE_NAMES[mode].."_"..rgb_hex
	local highlight_name = HIGHLIGHT_CACHE[cache_key]
	-- Look up in our cache.
	if not highlight_name then
		-- Create the highlight
		highlight_name = make_highlight_name(rgb_hex, mode)
		if mode == 'foreground' then
			nvim.ex.highlight(highlight_name, "guifg=#"..rgb_hex)
		else
			-- Guess the foreground color based on the background color's brightness.
			local r, g, b = num_to_rgb(tonumber(rgb_hex, 16))
			local fg_color
			if color_is_bright(r,g,b) then
				fg_color = "Black"
			else
				fg_color = "White"
			end
			nvim.ex.highlight(highlight_name, "guifg="..fg_color, "guibg=#"..rgb_hex)
		end
		HIGHLIGHT_CACHE[cache_key] = highlight_name
	end
	return highlight_name
end

local MATCHER_CACHE = {}
-- Return a function which is called a "loop parse function," meaning that it
-- can be used in a loop to check if there is a valid match in a string at the
-- specified index for any known color functions as specified by {options}.
--
-- Returns: fn(line: string, index: int) -> (length, rgb_hex): (int, string)
local function make_matcher(options)
	local enable_names    = options.css or options.names
	local enable_RGB      = options.css or options.RGB
	local enable_RRGGBB   = options.css or options.RRGGBB
	local enable_RRGGBBAA = options.css or options.RRGGBBAA
	local enable_rgb      = options.css or options.css_fns or options.rgb_fn
	local enable_hsl      = options.css or options.css_fns or options.hsl_fn

	local matcher_key = bor(
	lshift(enable_names    and 1 or 0, 0),
	lshift(enable_RGB      and 1 or 0, 1),
	lshift(enable_RRGGBB   and 1 or 0, 2),
	lshift(enable_RRGGBBAA and 1 or 0, 3),
	lshift(enable_rgb      and 1 or 0, 4),
	lshift(enable_hsl      and 1 or 0, 5))

	if matcher_key == 0 then return end

	local loop_parse_fn = MATCHER_CACHE[matcher_key]
	if loop_parse_fn then
		return loop_parse_fn
	end

	local loop_matchers = {}
	if enable_names then
		table.insert(loop_matchers, color_name_parser)
	end
	do
		local valid_lengths = {[3] = enable_RGB, [6] = enable_RRGGBB, [8] = enable_RRGGBBAA}
		local minlen, maxlen
		for k, v in pairs(valid_lengths) do
			if v then
				minlen = minlen and min(k, minlen) or k
				maxlen = maxlen and max(k, maxlen) or k
			end
		end
		if minlen then
			table.insert(loop_matchers, function(line, i)
				local length, rgb_hex = rgb_hex_parser(line, i, minlen, maxlen)
				if length and valid_lengths[length-1] then
					return length, rgb_hex
				end
			end)
		end
	end
	if enable_rgb and enable_hsl then
		table.insert(loop_matchers, css_function_parser)
	elseif enable_rgb then
		table.insert(loop_matchers, rgb_function_parser)
	elseif enable_hsl then
		table.insert(loop_matchers, hsl_function_parser)
	end
	loop_parse_fn = compile_matcher(loop_matchers)
	MATCHER_CACHE[matcher_key] = loop_parse_fn
	return loop_parse_fn
end

--[[-- Highlight the buffer region.
Highlight starting from `line_start` (0-indexed) for each line described by `lines` in the
buffer `buf` and attach it to the namespace `ns`.

@tparam integer buf buffer id.
@tparam[opt=DEFAULT_NAMESPACE] integer ns the namespace id. Create it with `vim.api.create_namespace`
@tparam {string,...} lines the lines to highlight from the buffer.
@tparam integer line_start should be 0-indexed
@param options Configuration options as described in `setup`
@see setup
]]
local function highlight_buffer(buf, ns, lines, line_start, options)
	-- TODO do I have to put this here?
	initialize_trie()
	ns = ns or DEFAULT_NAMESPACE
	local loop_parse_fn = make_matcher(options)
	for current_linenum, line in ipairs(lines) do
		current_linenum = current_linenum - 1 + line_start
		-- Upvalues are options and current_linenum
		local i = 1
		while i < #line do
			local length, rgb_hex = loop_parse_fn(line, i)
			if length then
				local highlight_name = create_highlight(rgb_hex, options)
				nvim_buf_add_highlight(buf, ns, highlight_name, current_linenum, i-1, i+length-1)
				i = i + length
			else
				i = i + 1
			end
		end
	end
end

---
-- USER FACING FUNCTIONALITY
---

local SETUP_SETTINGS = {
	exclusions = {};
	default_options = DEFAULT_OPTIONS;
}
local BUFFER_OPTIONS = {}
local FILETYPE_OPTIONS = {}

local function rehighlight_buffer(buf, options)
	local ns = DEFAULT_NAMESPACE
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	assert(options)
	nvim_buf_clear_namespace(buf, ns, 0, -1)
	local lines = nvim_buf_get_lines(buf, 0, -1, true)
	highlight_buffer(buf, ns, lines, 0, options)
end

local function new_buffer_options(buf)
	local filetype = nvim.buf_get_option(buf, 'filetype')
	return FILETYPE_OPTIONS[filetype] or SETUP_SETTINGS.default_options
end

--- Check if attached to a buffer.
-- @tparam[opt=0|nil] integer buf A value of 0 implies the current buffer.
-- @return true if attached to the buffer, false otherwise.
local function is_buffer_attached(buf)
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	return BUFFER_OPTIONS[buf] ~= nil
end

--- Attach to a buffer and continuously highlight changes.
-- @tparam[opt=0|nil] integer buf A value of 0 implies the current buffer.
-- @param[opt] options Configuration options as described in `setup`
-- @see setup
local function attach_to_buffer(buf, options)
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	local already_attached = BUFFER_OPTIONS[buf] ~= nil
	local ns = DEFAULT_NAMESPACE
	if not options then
		options = new_buffer_options(buf)
	end
	BUFFER_OPTIONS[buf] = options
	rehighlight_buffer(buf, options)
	if already_attached then
		return
	end
	-- send_buffer: true doesn't actually do anything in Lua (yet)
	nvim.buf_attach(buf, false, {
		on_lines = function(event_type, buf, changed_tick, firstline, lastline, new_lastline)
			-- This is used to signal stopping the handler highlights
			if not BUFFER_OPTIONS[buf] then
				return true
			end
			nvim_buf_clear_namespace(buf, ns, firstline, new_lastline)
			local lines = nvim_buf_get_lines(buf, firstline, new_lastline, false)
			highlight_buffer(buf, ns, lines, firstline, BUFFER_OPTIONS[buf])
		end;
		on_detach = function()
			BUFFER_OPTIONS[buf] = nil
		end;
	})
end

--- Stop highlighting the current buffer.
-- @tparam[opt=0|nil] integer buf A value of 0 or nil implies the current buffer.
-- @tparam[opt=DEFAULT_NAMESPACE] integer ns the namespace id.
local function detach_from_buffer(buf, ns)
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	nvim_buf_clear_namespace(buf, ns or DEFAULT_NAMESPACE, 0, -1)
	BUFFER_OPTIONS[buf] = nil
end


--- Easy to use function if you want the full setup without fine grained control.
-- Setup an autocmd which enables colorizing for the filetypes and options specified.
--
-- By default highlights all FileTypes.
--
-- Example config:
-- ```
-- { 'scss', 'html', css = { rgb_fn = true; }, javascript = { no_names = true } }
-- ```
--
-- You can combine an array and more specific options.
-- Possible options:
-- - `no_names`: Don't highlight names like Blue
-- - `rgb_fn`: Highlight `rgb(...)` functions.
-- - `mode`: Highlight mode. Valid options: `foreground`,`background`
--
-- @param[opt={'*'}] filetypes A table/array of filetypes to selectively enable and/or customize. By default, enables all filetypes.
-- @tparam[opt] {[string]=string} default_options Default options to apply for the filetypes enable.
-- @usage require'colorizer'.setup()
local function setup(filetypes, user_default_options)
	if not nvim.o.termguicolors then
		nvim.err_writeln("&termguicolors must be set")
		return
	end
	FILETYPE_OPTIONS = {}
	SETUP_SETTINGS = {
		exclusions = {};
		default_options = merge(DEFAULT_OPTIONS, user_default_options or {});
	}
	-- Initialize this AFTER setting COLOR_NAME_SETTINGS
	initialize_trie()
	function COLORIZER_SETUP_HOOK()
		local filetype = nvim.bo.filetype
		if SETUP_SETTINGS.exclusions[filetype] then
			return
		end
		local options = FILETYPE_OPTIONS[filetype] or SETUP_SETTINGS.default_options
		attach_to_buffer(nvim_get_current_buf(), options)
	end
	nvim.ex.augroup("ColorizerSetup")
	nvim.ex.autocmd_()
	if not filetypes then
		nvim.ex.autocmd("FileType * lua COLORIZER_SETUP_HOOK()")
	else
		for k, v in pairs(filetypes) do
			local filetype
			local options = SETUP_SETTINGS.default_options
			if type(k) == 'string' then
				filetype = k
				if type(v) ~= 'table' then
					nvim.err_writeln("colorizer: Invalid option type for filetype "..filetype)
				else
					options = merge(SETUP_SETTINGS.default_options, v)
					assert(HIGHLIGHT_MODE_NAMES[options.mode or 'background'], "colorizer: Invalid mode: "..tostring(options.mode))
				end
			else
				filetype = v
			end
			-- Exclude
			if filetype:sub(1,1) == '!' then
				SETUP_SETTINGS.exclusions[filetype:sub(2)] = true
			else
				FILETYPE_OPTIONS[filetype] = options
				-- TODO What's the right mode for this? BufEnter?
				nvim.ex.autocmd("FileType", filetype, "lua COLORIZER_SETUP_HOOK()")
			end
		end
	end
	nvim.ex.augroup("END")
end

--- Reload all of the currently active highlighted buffers.
local function reload_all_buffers()
	for buf, buffer_options in pairs(BUFFER_OPTIONS) do
		attach_to_buffer(buf)
	end
end

--- Return the currently active buffer options.
-- @tparam[opt=0|nil] integer buf A value of 0 or nil implies the current buffer.
local function get_buffer_options(buf)
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	return merge({}, BUFFER_OPTIONS[buf])
end

local partial_bar = "▅"
local full_bar = "█"
local empty_bar = "▁"

-- starting: string
-- finish: function(r,g,b)
--
-- returns: bufnr, winnr
local function color_picker(starting, on_change)
	if _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_ then
		print("There is already a color picker running.")
		return
	end
	assert(type(on_change) == 'function')

	local api = vim.api
	local bufnr = api.nvim_create_buf(false, true)

	local function progress_bar(x, m, fill)
		m = m - 1
		local pos = floor(x * m)
		local cursor
		if x == 0 then
			cursor = empty_bar
		elseif floor(x * m) == x * m then
			cursor = full_bar
		else
			cursor = fill and partial_bar or full_bar
		end
		local pre = fill and full_bar or empty_bar
		return pre:rep(pos)..cursor..empty_bar:rep(m - pos)
	end

	local function render_bars(focus, w, rgb, values, limits, styles)
		local ns = DEFAULT_NAMESPACE
		api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		local lines = {
			"#"..rgb_to_hex(unpack(rgb));
		}
		for i = 1, #values do
			local v = values[i]
			local m = limits[i] or 1
			local s = styles[i]
			lines[#lines+1] = progress_bar(v/m, w, s).." = "..v
		end
		api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		api.nvim_buf_add_highlight(bufnr, ns, 'Underlined', focus + 1, 0, w*#empty_bar)
	end

	local bar_width = 10

	local function clamp(x, x0, x1)
		return min(max(x, x0), x1)
	end

	local mode = 0

	local rgb = {
		focus = 0;
		values = {0, 0, 0};
		limits = {255, 255, 255};
		styles = {false, false, false};
	}
	local hsl = {
		focus = 0;
		values = {0, 0, 0};
		limits = {360, 100, 100};
		styles = {false, true, true};
	}

	function rgb.init(r,g,b)
		rgb.values = {floor(r),floor(g),floor(b)}
	end
	function rgb.rgb()
		return rgb.values
	end

	function hsl.init(r,g,b)
		hsl.values = {rgb_to_hsl(r,g,b)}
		-- hsl.h, hsl.s, hsl.l = rgb_to_hsl(r,g,b)
		hsl.focus = hsl.focus or 0
	end
	function hsl.rgb()
		local h,s,l = unpack(hsl.values)
		return {hsl_to_rgb(h/360, s/100, l/100)}
	end

	local modes = { rgb; hsl; }

	-- Long name to avoid collisions. Amusing hack for lack of lua callbacks in keymappings.
	function _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_(S)
		local cmode = modes[mode + 1]
		local changed = false
		if S.focus then
			cmode.focus = clamp(cmode.focus+S.focus, 0, 2)
		elseif S.value then
			local i = cmode.focus+1
			local values = cmode.values
			values[i] = clamp(values[i]+S.value, 0, cmode.limits[i])
			changed = true
		elseif S.set then
			local i = cmode.focus+1
			local values = cmode.values
			values[i] = floor(S.set * cmode.limits[i])
			changed = true
		elseif S.mode then
			local values = cmode.rgb()
			mode = (mode + S.mode) % 2
			cmode = modes[mode + 1]
			cmode.init(unpack(values))
			changed = true
		end
		local rgbvals = cmode.rgb()
		if changed then
			on_change(rgbvals)
		end
		render_bars(cmode.focus, bar_width, rgbvals, cmode.values, cmode.limits, cmode.styles)
	end

	api.nvim_buf_set_keymap(bufnr, 'n', 'j', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{focus=1}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', 'k', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{focus=-1}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', 'l', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{value=1}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', 'h', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{value=-1}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', 'L', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{value=10}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', 'H', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{value=-10}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '<TAB>', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{mode=1}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '0', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{set=0}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '1', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{set=0.25}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '2', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{set=0.50}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '3', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{set=0.75}<cr>', {noremap=true})
	api.nvim_buf_set_keymap(bufnr, 'n', '4', '<cmd>lua _PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{set=1}<cr>', {noremap=true})

	api.nvim_buf_attach(bufnr, false, {
		on_detach = function()
			on_change(modes[mode+1].rgb(), true)
			_PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_ = nil
		end
	})

	if starting then
		assert(type(starting) == 'string')
		-- Make a matcher which works for all inputs.
		local matcher = make_matcher{css=true}
		local length, rgb_hex = matcher(starting, 1)
		if length then
			modes[mode+1].init(num_to_rgb(tonumber(rgb_hex, 16)))
		else
			print("Invalid starting color:", starting)
			modes[mode+1].init(0, 0, 0)
		end
	else
		modes[mode+1].init(0, 0, 0)
	end

	attach_to_buffer(bufnr)
	api.nvim_buf_set_option(bufnr, 'undolevels', -1)
	-- TODO(ashkan): skip sending first on_change?
	_PICKER_ASHKAN_KIANI_COPYRIGHT_2020_LONG_NAME_HERE_{}

	local winnr = api.nvim_open_win(bufnr, true, {
		style = 'minimal';
		-- anchor = 'NW';
		width = bar_width + 10;
		relative = 'cursor';
		row = 0; col = 0;
		height = 4;
	})
	return bufnr, winnr
end

-- TODO(ashkan): Match the replacement type to the type of the input.
local function color_picker_on_cursor(config)
	config = config or {}
	assert(type(config) == 'table')
	local match_format = not config.rgb_hex

	local api = vim.api
	local bufnr = api.nvim_get_current_buf()
	local pos = api.nvim_win_get_cursor(0)
	local row, col = unpack(pos)
	local line = api.nvim_get_current_line()
	local matcher = make_matcher{css=true}
	local start, length, rgb_hex

	-- TODO(ashkan): How much should I backpedal? Is too much a problem? I don't
	-- think it could be since the color must contain the cursor.
	for i = col+1, max(col-50, 1), -1 do
		local l, hex = matcher(line, i)
		-- Check that col is bounded by i and i+l
		if l and (i + l) > col+1 then
			start, length, rgb_hex = i, l, hex
			break
		end
	end

	local function startswith(s, n)
		return s:sub(1, #n) == n
	end

	-- TODO(ashkan): make insertion on no color found configurable.
	-- Currently, it doesn't insert unless you modify something, which is pretty
	-- nice.
	start = start or col+1
	local prefix = line:sub(1, start-1)
	local suffix = line:sub(start+(length or 0))
	local matched = line:sub(start, start+length)
	local formatter = function(rgb)
		return "#"..rgb_to_hex(unpack(rgb))
	end
	if match_format then
		-- TODO(ashkan): make matching the result optional?
		if startswith(matched, "rgba") then
			-- TODO(ashkan): support alpha?
			formatter = function(rgb)
				return string.format("rgba(%d, %d, %d, 1)", unpack(rgb))
			end
		elseif startswith(matched, "rgb") then
			formatter = function(rgb)
				return string.format("rgb(%d, %d, %d)", unpack(rgb))
			end
		elseif startswith(matched, "hsla") then
			formatter = function(rgb)
				return string.format("hsla(%d, %d%%, %d%%, 1)", rgb_to_hsl(unpack(rgb)))
			end
		elseif startswith(matched, "hsl") then
			formatter = function(rgb)
				return string.format("hsl(%d, %d%%, %d%%)", rgb_to_hsl(unpack(rgb)))
			end
			-- elseif startswith(matched, "#") and length == 4 then
			-- elseif startswith(matched, "#") and length == 7 then
			-- else
		end
	end
	-- Disable live previews on long lines.
	-- TODO(ashkan): enable this when you can to nvim_buf_set_text instead of set_lines.
	-- TODO(ashkan): is 200 a fair number?
	if #line > 200 then
		return color_picker(rgb_hex and "#"..rgb_hex, vim.schedule_wrap(function(rgb, is_last)
			if is_last then
				api.nvim_buf_set_lines(bufnr, row-1, row, true, {prefix..formatter(rgb)..suffix})
			end
		end))
	end
	return color_picker(rgb_hex and "#"..rgb_hex, vim.schedule_wrap(function(rgb, is_last)
		-- Since we're modifying it perpetually, we don't need is_last, and this
		-- avoids modifying when nothing has changed.
		if is_last then return end
		api.nvim_buf_set_lines(bufnr, row-1, row, true, {prefix..formatter(rgb)..suffix})
	end))
end

--- @export
return {
	DEFAULT_NAMESPACE = DEFAULT_NAMESPACE;
	color_picker = color_picker;
	color_picker_on_cursor = color_picker_on_cursor;
	setup = setup;
	is_buffer_attached = is_buffer_attached;
	attach_to_buffer = attach_to_buffer;
	detach_from_buffer = detach_from_buffer;
	highlight_buffer = highlight_buffer;
	reload_all_buffers = reload_all_buffers;
	get_buffer_options = get_buffer_options;
	create_highlight = create_highlight;
}


-- vim:noet sw=3 ts=3
