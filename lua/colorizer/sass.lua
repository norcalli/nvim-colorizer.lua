local colorizer = require 'colorizer'
local nvim = require 'colorizer/nvim'

local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local nvim_get_current_buf = vim.api.nvim_get_current_buf


local M = {}

local LINE_DEFINITIONS = {}
local VARIABLE_DEFINITIONS = {}
local RECURSIVE_VARIABLES = {}

local function variable_matcher(line, i)
	local variable_name = line:sub(i):match("^%$([%w_]+)")
	if variable_name then
		local rgb_hex = VARIABLE_DEFINITIONS[variable_name]
		if rgb_hex then
			return #variable_name + 1, rgb_hex
		end
	end
end

local VALUE_PARSER = colorizer.parsers.compile {
	function(line,i) return colorizer.parsers.rgb_hex_parser(line,i,3,8) end;
	colorizer.parsers.color_name_parser;
	colorizer.parsers.css_function_parser;
}

local function update_from_lines(buf, buffer_variable_definitions, line_start, line_end)
	local variable_definitions_changed = false
	local lines = nvim_buf_get_lines(buf, line_start, line_end, false)
	for linenum = line_start, line_start + #lines - 1 do
		local existing_variable_name = buffer_variable_definitions[linenum]
		-- Invalidate any existing definitions for the lines we are processing.
		if existing_variable_name then
			VARIABLE_DEFINITIONS[existing_variable_name] = nil
			RECURSIVE_VARIABLES[existing_variable_name] = nil
			variable_definitions_changed = true
			buffer_variable_definitions[linenum] = nil
		end
	end
	for i, line in ipairs(lines) do
		local linenum = i + line_start - 1
		local variable_name, variable_value = line:match("^%s*%$([%w_]+)%s*:%s*(%S+)%s*$")
		-- Check if we got a variable definition
		if variable_name then
			-- Check for a recursive variable definition.
			local target_variable_name = variable_value:match("%$([%w_]+)")
			if target_variable_name then
				-- Update the recursive variable definition
				RECURSIVE_VARIABLES[variable_name] = target_variable_name
				-- Update the value.
				VARIABLE_DEFINITIONS[variable_name] = VARIABLE_DEFINITIONS[target_variable_name]
				variable_definitions_changed = true
			else
				-- If it's not recursive, then just update the value.
				local length, rgb_hex = VALUE_PARSER(variable_value, 1)
				if length then
					variable_definitions_changed = true
					buffer_variable_definitions[linenum] = variable_name
					VARIABLE_DEFINITIONS[variable_name] = rgb_hex
				end
			end
			-- Propagate changes to recursive dependents.
			-- TODO this isn't recursive, obviously. Only works for 1 depth.
			for varn, varv in pairs(RECURSIVE_VARIABLES) do
				if varv == variable_name then
					VARIABLE_DEFINITIONS[varn] = VARIABLE_DEFINITIONS[varv]
				end
			end
		end
	end
	return variable_definitions_changed
end

local function rehighlight_attached_buffers()
	-- Rehighlight all buffers
	for bufnr in pairs(LINE_DEFINITIONS) do
		colorizer.attach_to_buffer(bufnr)
	end
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

	LINE_DEFINITIONS[buf] = {}
	local buffer_variable_definitions = LINE_DEFINITIONS[buf]

	-- Parse the whole buffer to start.
	update_from_lines(buf, buffer_variable_definitions, 0, -1)
	rehighlight_attached_buffers()

	-- send_buffer: true doesn't actually do anything in Lua (yet)
	nvim.buf_attach(buf, false, {
		on_lines = function(event_type, buf, changed_tick, firstline, lastline, new_lastline)
			-- This is used to signal stopping the handler highlights
			if not colorizer.is_buffer_attached(buf) then
				return true
			end
			local variable_definitions_changed = update_from_lines(buf, buffer_variable_definitions, firstline, new_lastline)
			-- If the variable_definitions_changed then rehighlight all watched buffers.
			if variable_definitions_changed then
				rehighlight_attached_buffers()
			end
		end;
		on_detach = function()
			LINE_DEFINITIONS[buf] = nil
		end;
	})
end

M.variable_matcher = variable_matcher

return M
