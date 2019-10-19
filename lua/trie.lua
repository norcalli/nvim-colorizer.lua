--- Trie implementation in luajit
-- Copyright © 2019 Ashkan Kiani

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
local ffi = require 'ffi'
local bit = require 'bit'

local bnot = bit.bnot
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

ffi.cdef [[
struct Trie {
	bool is_leaf;
	struct Trie* character[62];
};
void *malloc(size_t size);
void free(void *ptr);
]]

local Trie_t = ffi.typeof('struct Trie')
local Trie_ptr_t = ffi.typeof('$ *', Trie_t)
local Trie_size = ffi.sizeof(Trie_t)

local function byte_to_index(b)
	-- 0-9 starts at string.byte('0') == 0x30 == 48 == 0b0011_0000
	-- A-Z starts at string.byte('A') == 0x41 == 65 == 0b0100_0001
	-- a-z starts at string.byte('a') == 0x61 == 97 == 0b0110_0001

	-- This works for mapping characters to
	-- 0-9 A-Z a-z in that order
	-- Letters have bit 0x40 set, so we use that as an indicator for
	-- an additional offset from the space of the digits, and then
	-- add the 10 allocated for the range of digits.
	-- Then, within that indicator for letters, we subtract another
	-- (65 - 97) which is the difference between lower and upper case
	-- and add back another 26 to allocate for the range of uppercase
	-- letters.
	-- return b - 0x30
	-- 	+ rshift(b, 6) * (
	-- 		0x30 - 0x41
	-- 		+ 10
	-- 		+ band(1, rshift(b, 5)) * (
	-- 			0x61 - 0x41
	-- 			+ 26
	-- 		))
	return b - 0x30 - rshift(b, 6) * (7 + band(1, rshift(b, 5)) * 6)
end

local function insensitive_byte_to_index(b)
	-- return b - 0x30
	-- 	+ rshift(b, 6) * (
	-- 		0x30 - 0x61
	-- 		+ 10
	-- 	)
	b = bor(b, 0x20)
	return b - 0x30 - rshift(b, 6) * 39
end

local function verify_byte_to_index()
	local chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
	for i = 1, #chars do
		local c = chars:sub(i,i)
		local index = byte_to_index(string.byte(c))
		assert((i-1) == index, vim.inspect{index=index,c=c})
	end
end

local function trie_create()
	local ptr = ffi.C.malloc(Trie_size)
	ffi.fill(ptr, Trie_size)
	return ffi.cast(Trie_ptr_t, ptr)
end

local INDEX_LOOKUP_TABLE = ffi.new 'uint8_t[256]'
local CHAR_LOOKUP_TABLE = ffi.new('char[62]', '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz')
do
	local b = string.byte
	for i = 0, 255 do
		if i >= b'0' and i <= b'9' then
			INDEX_LOOKUP_TABLE[i] = i - b'0'
		elseif i >= b'A' and i <= b'Z' then
			INDEX_LOOKUP_TABLE[i] = i - b'A' + 10
		elseif i >= b'a' and i <= b'z' then
			INDEX_LOOKUP_TABLE[i] = i - b'a' + 10 + 26
		else
			INDEX_LOOKUP_TABLE[i] = 255
		end
	end
end

local function trie_insert(trie, value)
	if trie == nil then return false end
	local node = trie
	for i = 1, #value do
		local index = INDEX_LOOKUP_TABLE[value:byte(i)]
		if index == 255 then
			return false
		end
		if node.character[index] == nil then
			node.character[index] = trie_create()
		end
		node = node.character[index]
	end
	node.is_leaf = true
	return node, trie
end

local function trie_search(trie, value)
	if trie == nil then return false end
	local node = trie
	for i = 1, #value do
		local index = INDEX_LOOKUP_TABLE[value:byte(i)]
		if index == 255 then
			return
		end
		local child = node.character[index]
		if child == nil then
			return false
		end
		node = child
	end
	return node.is_leaf
end

local function trie_longest_prefix(trie, value)
	if trie == nil then return false end
	local node = trie
	local last_i = nil
	for i = 1, #value do
		local index = INDEX_LOOKUP_TABLE[value:byte(i)]
		if index == 255 then
			break
		end
		local child = node.character[index]
		if child == nil then
			break
		end
		if child.is_leaf then
			last_i = i
		end
		node = child
	end
	if last_i then
		return value:sub(1, last_i)
	end
end

local function trie_extend(trie, t)
	assert(type(t) == 'table')
	for _, v in ipairs(t) do
		trie_insert(trie, v)
	end
end

--- Printing utilities

local function index_to_char(index)
	if index < 0 or index > 61 then return end
	return CHAR_LOOKUP_TABLE[index]
end

local function trie_as_table(trie)
	if trie == nil then
		return nil
	end
	local children = {}
	for i = 0, 61 do
		local child = trie.character[i]
		if child ~= nil then
			local child_table = trie_as_table(child)
			child_table.c = index_to_char(i)
			table.insert(children, child_table)
		end
	end
	return {
		is_leaf = trie.is_leaf;
		children = children;
	}
end

local function print_trie_table(s)
	local mark
	if not s then
		return {'nil'}
	end
	if s.c then
		if s.is_leaf then
			mark = s.c.."*"
		else
			mark = s.c.."─"
		end
	else
		mark = "├─"
	end
	if #s.children == 0 then
		return {mark}
	end
	local lines = {}
	for _, child in ipairs(s.children) do
		local child_lines = print_trie_table(child)
		for _, child_line in ipairs(child_lines) do
			table.insert(lines, child_line)
		end
	end
	for i, v in ipairs(lines) do
		if v:match("^[%w%d]") then
			if i == 1 then
				lines[i] = mark.."─"..v
			elseif i == #lines then
				lines[i] = "└──"..v
			else
				lines[i] = "├──"..v
			end
		else
			if i == 1 then
				lines[i] = mark.."─"..v
			elseif #s.children > 1 then
				lines[i] = "│  "..v
			else
				lines[i] = "   "..v
			end
		end
	end
	return lines
end

local function trie_destroy(trie)
	if trie == nil then
		return
	end
	for i = 0, 61 do
		local child = trie.character[i]
		if child ~= nil then
			trie_destroy(child)
		end
	end
	ffi.C.free(trie)
end

local Trie_mt = {
	__new = function(_, init)
		local trie = trie_create()
		if type(init) == 'table' then
			trie_extend(trie, init)
		end
		return trie
	end;
	__index = {
		insert = trie_insert;
		search = trie_search;
		longest_prefix = trie_longest_prefix;
		extend = trie_extend;
	};
	__tostring = function(trie)
		if trie == nil then
			return 'nil'
		end
		return table.concat(print_trie_table(trie_as_table(trie)), '\n')
	end;
	__gc = trie_destroy;
}

return ffi.metatype('struct Trie', Trie_mt)

-- local tests = {
-- 	"cat";
-- 	"car";
-- 	"celtic";
-- 	"carb";
-- 	"carb0";
-- 	"CART0";
-- 	"CaRT0";
-- 	"Cart0";
-- 	"931";
-- 	"191";
-- 	"121";
-- 	"cardio";
-- 	"call";
-- 	"calcium";
-- 	"calciur";
-- 	"carry";
-- 	"dog";
-- 	"catdog";
-- }
-- local trie = Trie()
-- for i, v in ipairs(tests) do
-- 	trie:insert(v)
-- end

-- print(trie)
-- print(trie.character[0])
-- print("catdo", trie:longest_prefix("catdo"))
-- print("catastrophic", trie:longest_prefix("catastrophic"))

-- local COLOR_MAP = vim.api.nvim_get_color_map()
-- local start = os.clock()
-- for k, v in pairs(COLOR_MAP) do
-- 	insert(trie, k)
-- end
-- print(os.clock() - start)

-- print(table.concat(print_trie_table(trie_as_table(trie)), '\n'))
