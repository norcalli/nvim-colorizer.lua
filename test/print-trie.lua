-- TODO this is kinda shitty
local function dirname(str,sep)
	sep=sep or'/'
	return str:match("(.*"..sep..")")
end

local script_dir = dirname(arg[0])
package.path = script_dir.."/../lua/?.lua;"..package.path

local Trie = require 'trie'
local nvim = require 'nvim'

local tohex = bit.tohex
local min, max = math.min, math.max

local COLOR_NAME_SETTINGS = {
	lowercase = false;
	strip_digits = true;
}
COLOR_MAP = {}
COLOR_TRIE = Trie()
for k, v in pairs(nvim.get_color_map()) do
	if not (COLOR_NAME_SETTINGS.strip_digits and k:match("%d+$")) then
		COLOR_NAME_MINLEN = COLOR_NAME_MINLEN and min(#k, COLOR_NAME_MINLEN) or #k
		COLOR_NAME_MAXLEN = COLOR_NAME_MAXLEN and max(#k, COLOR_NAME_MAXLEN) or #k
		COLOR_MAP[k] = tohex(v, 6)
		COLOR_TRIE:insert(k)
		if COLOR_NAME_SETTINGS.lowercase then
			local lowercase = k:lower()
			COLOR_MAP[lowercase] = tohex(v, 6)
			COLOR_TRIE:insert(lowercase)
		end
	end
end

print(COLOR_TRIE)
