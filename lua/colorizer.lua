--- Highlights terminal CSI ANSI color codes.
-- @module colorizer
local nvim = require 'colorizer/nvim'
local Trie = require 'colorizer/trie'
local bit = require 'bit'
local ffi = require 'ffi'

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
		local r = floor(band(v, 0xFF)*alpha)
		local g = floor(band(rshift(v, 8), 0xFF)*alpha)
		local b = floor(band(rshift(v, 16), 0xFF)*alpha)
		v = bor(lshift(r, 16), lshift(g, 8), b)
		return 9, tohex(v, 6)
	end
	return length, line:sub(i+1, i+length-1)
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
		local rgb_hex = tohex(bor(lshift(r, 16), lshift(g, 8), b), 6)
		return match_end - 1, rgb_hex
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
		local rgb_hex = tohex(bor(lshift(floor(r), 16), lshift(floor(g), 8), floor(b)), 6)
		return match_end - 1, rgb_hex
	end
	function css_fn.rgba(line, i)
		if #line < i + CSS_RGBA_FN_MINIMUM_LENGTH then return end
		local r, g, b, a, match_end = line:sub(i):match("^rgba%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*([.%d]+)%s*%)()")
		if not match_end then return end
		a = tonumber(a) if not a or a > 1 then return end
		r = percent_or_hex(r) if not r then return end
		g = percent_or_hex(g) if not g then return end
		b = percent_or_hex(b) if not b then return end
		local rgb_hex = tohex(bor(lshift(floor(r*a), 16), lshift(floor(g*a), 8), floor(b*a)), 6)
		return match_end - 1, rgb_hex
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
		local rgb_hex = tohex(bor(lshift(floor(r*a), 16), lshift(floor(g*a), 8), floor(b*a)), 6)
		return match_end - 1, rgb_hex
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
	local cache_key = table.concat({HIGHLIGHT_MODE_NAMES[mode], rgb_hex}, "_")
	local highlight_name = HIGHLIGHT_CACHE[cache_key]
	-- Look up in our cache.
	if not highlight_name then
		if #rgb_hex == 3 then
			rgb_hex = table.concat {
				rgb_hex:sub(1,1):rep(2);
				rgb_hex:sub(2,2):rep(2);
				rgb_hex:sub(3,3):rep(2);
			}
		end
		-- Create the highlight
		highlight_name = make_highlight_name(rgb_hex, mode)
		if mode == 'foreground' then
			nvim.ex.highlight(highlight_name, "guifg=#"..rgb_hex)
		else
			local r, g, b = rgb_hex:sub(1,2), rgb_hex:sub(3,4), rgb_hex:sub(5,6)
			r, g, b = tonumber(r,16), tonumber(g,16), tonumber(b,16)
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

--- @export
return {
	DEFAULT_NAMESPACE = DEFAULT_NAMESPACE;
	setup = setup;
	is_buffer_attached = is_buffer_attached;
	attach_to_buffer = attach_to_buffer;
	detach_from_buffer = detach_from_buffer;
	highlight_buffer = highlight_buffer;
	reload_all_buffers = reload_all_buffers;
	get_buffer_options = get_buffer_options;
}

