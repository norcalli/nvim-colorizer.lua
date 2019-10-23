local colorizer = require 'colorizer'
local nvim = require 'colorizer/nvim'

local nvim_buf_add_highlight = vim.api.nvim_buf_add_highlight
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local band, lshift, bor, tohex = bit.band, bit.lshift, bit.bor, bit.tohex
local rshift = bit.rshift
local floor, min, max = math.floor, math.min, math.max


local M = {}

local LINE_DEFINITIONS = {}
local VARIABLE_DEFINITIONS = {}

local VALUE_PARSER = colorizer.parsers.compile {
	function(line,i) return colorizer.parsers.rgb_hex_parser(line,i,3,8) end;
	colorizer.parsers.color_name_parser;
	colorizer.parsers.css_function_parser;
}

local function variable_matcher(line, i)
	local variable_name = line:sub(i):match("^%$([%w_]+)")
	if variable_name then
		local rgb_hex = VARIABLE_DEFINITIONS[variable_name]
		print("variable_matcher", variable_name, rgb_hex)
		if rgb_hex then
			return #variable_name + 1, rgb_hex
		end
	end
end

local function update_from_lines(buf, line_start, line_end)
end


--- Attach to a buffer and continuously highlight changes.
-- @tparam[opt=0|nil] integer buf A value of 0 implies the current buffer.
-- @param[opt] options Configuration options as described in `setup`
-- @see setup
function M.attach_to_buffer(buf)
--function M.attach_to_buffer(buf, options)
	if buf == 0 or buf == nil then
		buf = nvim_get_current_buf()
	end
	-- colorizer.attach_to_buffer(buf)

	-- local options = colorizer.get_buffer_options()

	-- options.custom_matcher = variable_matcher
	-- print(vim.inspect(options))

	LINE_DEFINITIONS[buf] = {}
	local buffer_variable_definitions = LINE_DEFINITIONS[buf]

	local function update_from_lines(line_start, line_end)
		local variable_definitions_changed = false
		-- nvim_buf_clear_namespace(buf, ns, line_start, line_end)
		local lines = nvim_buf_get_lines(buf, line_start, line_end, true)
		for linenum = line_start, line_start + #lines - 1 do
			local existing_variable_name = buffer_variable_definitions[linenum]
			if existing_variable_name then
				VARIABLE_DEFINITIONS[existing_variable_name] = nil
				variable_definitions_changed = true
				buffer_variable_definitions[linenum] = nil
			end
		end
		for i, line in ipairs(lines) do
			local linenum = i + line_start - 1
			local variable_name, variable_value = line:match("^%s*%$([%w_]+)%s*:%s*(%S+)%s*$")
			if variable_name then
				print("matched variable definition", variable_name, variable_value)
				for j = 1, #variable_value do
					local length, rgb_hex = VALUE_PARSER(variable_value, j)
					if length then
						variable_definitions_changed = true
						print("parsed variable value", variable_name, length, rgb_hex)
						buffer_variable_definitions[linenum] = variable_name
						VARIABLE_DEFINITIONS[variable_name] = rgb_hex
						print(vim.inspect(LINE_DEFINITIONS):gsub("\n", ''))
						break
					end
				end
			end
		end
		return variable_definitions_changed
	end

	update_from_lines(1, -1)
	for bufnr in pairs(LINE_DEFINITIONS) do
		colorizer.attach_to_buffer(bufnr)
	end

	-- send_buffer: true doesn't actually do anything in Lua (yet)
	nvim.buf_attach(buf, false, {
		on_lines = function(event_type, buf, changed_tick, firstline, lastline, new_lastline)
			-- This is used to signal stopping the handler highlights
			if not colorizer.is_buffer_attached(buf) then
				return true
			end
			local variable_definitions_changed = update_from_lines(firstline, new_lastline)
			if variable_definitions_changed then
				-- colorizer.attach_to_buffer(buf)
				for bufnr in pairs(LINE_DEFINITIONS) do
					colorizer.attach_to_buffer(bufnr)
				end
			end
			-- TODO can this get out of sync with highlighting order if it updates the database
			-- and then the highlight happens afterwards?
			-- colorizer.highlight_buffer(buf, ns, lines, firstline, BUFFER_OPTIONS[buf])
		end;
		on_detach = function()
			LINE_DEFINITIONS[buf] = nil
		end;
	})

	-- return colorizer.attach_to_buffer(buf, options)
end

M.variable_matcher = variable_matcher

return M
