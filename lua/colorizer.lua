--- Highlights terminal CSI ANSI color codes.
-- @module colorizer
local nvim = require 'nvim'
local Trie = require 'trie'

local nvim_buf_add_highlight = vim.api.nvim_buf_add_highlight
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace

--- Default namespace used in `highlight_buffer` and `attach_to_buffer`.
-- The name is "terminal_highlight"
-- @see highlight_buffer
-- @see attach_to_buffer
local DEFAULT_NAMESPACE = nvim.create_namespace 'colorizer'

local COLOR_MAP
local COLOR_TRIE

--- Setup the COLOR_MAP and COLOR_TRIE
local function initialize_trie()
	if not COLOR_TRIE then
		COLOR_MAP = nvim.get_color_map()
		COLOR_TRIE = Trie()

		for k in pairs(COLOR_MAP) do
			COLOR_TRIE:insert(k)
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

local DEFAULT_OPTIONS = {
	RGB     = true;         -- #RGB hex codes
	RRGGBB  = true;         -- #RRGGBB hex codes
	names   = true;         -- "Name" codes like Blue
	rgb_fn  = false;        -- CSS rgb() and rgba() functions
	hsl_fn  = false;        -- CSS hsl() and hsla() functions
	css     = false;        -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
	css_fn  = false;        -- Enable all CSS *functions*: rgb_fn, hsl_fn
	-- Available modes: foreground, background
	mode    = 'background'; -- Set the display mode.
}

local HIGHLIGHT_NAME_PREFIX = "colorizer"
local MODE_NAMES = {
	background = 'mb';
	foreground = 'mf';
}

local HIGHLIGHT_CACHE = {}

--- Make a deterministic name for a highlight given these attributes
local function make_highlight_name(rgb, mode)
	return table.concat({HIGHLIGHT_NAME_PREFIX, MODE_NAMES[mode], rgb}, '_')
end

local function create_highlight(rgb_hex, options)
	local mode = options.mode or 'background'
	-- TODO validate rgb format?
	rgb_hex = rgb_hex:lower()
	local cache_key = table.concat({MODE_NAMES[mode], rgb_hex}, "_")
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

local SETUP_SETTINGS = {
	exclusions = {};
	default_options = DEFAULT_OPTIONS;
}

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
	local enable_names  = options.names
	local enable_RGB    = options.css or options.RGB
	local enable_RRGGBB = options.css or options.RRGGBB
	local enable_rgb    = options.css or options.css_fns or options.rgb_fn
	local enable_rgba   = options.css or options.css_fns or options.rgb_fn
	local enable_hsl    = options.css or options.css_fns or options.hsl_fn
	local enable_hsla   = options.css or options.css_fns or options.hsl_fn
	-- TODO do I have to put this here?
	initialize_trie()
	ns = ns or DEFAULT_NAMESPACE
	for current_linenum, line in ipairs(lines) do
		current_linenum = current_linenum - 1 + line_start
		-- Upvalues are options and current_linenum
		local function highlight_line_rgb_hex(match_start, rgb_hex, match_end)
			local highlight_name = create_highlight(rgb_hex, options)
			nvim_buf_add_highlight(buf, ns, highlight_name, current_linenum, match_start-1, match_end-1)
		end
		if enable_rgb then
			-- TODO this can have improved performance by either reusing my trie or
			-- doing a byte comp.
			-- Pattern for rgb() functions from CSS
			line:gsub("()rgb%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*%)()", function(match_start, r,g,b, match_end)
				if r:sub(-1,-1) == "%" then r = math.floor(r:sub(1,-2)/100*255) end
				if g:sub(-1,-1) == "%" then g = math.floor(g:sub(1,-2)/100*255) end
				if b:sub(-1,-1) == "%" then b = math.floor(b:sub(1,-2)/100*255) end
				local rgb_hex = ("%02x%02x%02x"):format(r,g,b)
				if #rgb_hex ~= 6 then
					return
				end
				highlight_line_rgb_hex(match_start, rgb_hex, match_end)
			end)
		end
		if enable_RGB then
			-- Pattern for #RGB, part 1. No trailing characters allowed
			line:gsub("()#([%da-fA-F][%da-fA-F][%da-fA-F])()%W", highlight_line_rgb_hex)
			-- Pattern for #RGB, part 2. Ending code.
			line:gsub("()#([%da-fA-F][%da-fA-F][%da-fA-F])()$", highlight_line_rgb_hex)
		end
		if enable_RRGGBB then
			-- Pattern for #RRGGBB
			line:gsub("()#([%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F])()", highlight_line_rgb_hex)
		end
		if enable_names then
			local i = 1
			while i < #line do
				-- TODO skip if the remaining length is less than the shortest length
				-- of an entry in our trie.
				local prefix = COLOR_TRIE:longest_prefix(line:sub(i))
				if prefix then
					local rgb = COLOR_MAP[prefix]
					local rgb_hex = bit.tohex(rgb):sub(-6)
					highlight_line_rgb_hex(i, rgb_hex, i+#prefix)
					i = i + #prefix
				else
					i = i + 1
				end
			end
		end
	end
end

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
			local lines = nvim_buf_get_lines(buf, firstline, new_lastline, true)
			highlight_buffer(buf, ns, lines, firstline, BUFFER_OPTIONS[buf])
--			highlight_buffer(buf, ns, lines, firstline, BUFFER_OPTIONS[buf] or options)
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
local function setup(filetypes, default_options)
	if not nvim.o.termguicolors then
		nvim.err_writeln("&termguicolors must be set")
		return
	end
	initialize_trie()
	FILETYPE_OPTIONS = {}
	SETUP_SETTINGS = {
		exclusions = {};
		default_options = merge(DEFAULT_OPTIONS, default_options or {});
	}
	-- Copy filetypes this so we can manipulate it freely.
	filetypes = merge(filetypes)
	-- This is just in case I accidentally reference the wrong thing here.
	default_options = SETUP_SETTINGS.default_options
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
	if filetypes.on_event then
		nvim.ex.autocmd(filetypes.on_event, " * lua COLORIZER_SETUP_HOOK()")
		filetypes.on_enter = nil
	end
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
					assert(MODE_NAMES[options.mode or 'background'], "colorizer: Invalid mode: "..tostring(options.mode))
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
	attach_to_buffer = attach_to_buffer;
	detach_from_buffer = detach_from_buffer;
	highlight_buffer = highlight_buffer;
	reload_all_buffers = reload_all_buffers;
	get_buffer_options = get_buffer_options;
	-- initialize = initialize_trie;
}

