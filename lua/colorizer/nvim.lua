--- Module of magic functions for nvim
-- @module nvim

-- Equivalent to `echo vim.inspect(...)`
local function nvim_print(...)
	if select("#", ...) == 1 then
		vim.api.nvim_out_write(vim.inspect((...)))
	else
		vim.api.nvim_out_write(vim.inspect {...})
	end
	vim.api.nvim_out_write("\n")
end

--- Equivalent to `echo` EX command
local function nvim_echo(...)
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		vim.api.nvim_out_write(tostring(part))
		-- vim.api.nvim_out_write("\n")
		vim.api.nvim_out_write(" ")
	end
	vim.api.nvim_out_write("\n")
end

local window_options = {
	          arab = true;       arabic = true;   breakindent = true; breakindentopt = true;
	           bri = true;       briopt = true;            cc = true;           cocu = true;
	          cole = true;  colorcolumn = true; concealcursor = true;   conceallevel = true;
	           crb = true;          cuc = true;           cul = true;     cursorbind = true;
	  cursorcolumn = true;   cursorline = true;          diff = true;            fcs = true;
	           fdc = true;          fde = true;           fdi = true;            fdl = true;
	           fdm = true;          fdn = true;           fdt = true;            fen = true;
	     fillchars = true;          fml = true;           fmr = true;     foldcolumn = true;
	    foldenable = true;     foldexpr = true;    foldignore = true;      foldlevel = true;
	    foldmarker = true;   foldmethod = true;  foldminlines = true;    foldnestmax = true;
	      foldtext = true;          lbr = true;           lcs = true;      linebreak = true;
	          list = true;    listchars = true;            nu = true;         number = true;
	   numberwidth = true;          nuw = true; previewwindow = true;            pvw = true;
	relativenumber = true;    rightleft = true;  rightleftcmd = true;             rl = true;
	           rlc = true;          rnu = true;           scb = true;            scl = true;
	           scr = true;       scroll = true;    scrollbind = true;     signcolumn = true;
	         spell = true;   statusline = true;           stl = true;            wfh = true;
	           wfw = true;        winbl = true;      winblend = true;   winfixheight = true;
	   winfixwidth = true; winhighlight = true;         winhl = true;           wrap = true;
}

-- `nvim.$method(...)` redirects to `nvim.api.nvim_$method(...)`
-- `nvim.fn.$method(...)` redirects to `vim.api.nvim_call_function($method, {...})`
-- TODO `nvim.ex.$command(...)` is approximately `:$command {...}.join(" ")`
-- `nvim.print(...)` is approximately `echo vim.inspect(...)`
-- `nvim.echo(...)` is approximately `echo table.concat({...}, '\n')`
-- Both methods cache the inital lookup in the metatable, but there is a small overhead regardless.
return setmetatable({
	print = nvim_print;
	echo = nvim_echo;
	fn = setmetatable({}, {
		__index = function(self, k)
			local mt = getmetatable(self)
			local x = mt[k]
			if x ~= nil then
				return x
			end
			local f = function(...) return vim.api.nvim_call_function(k, {...}) end
			mt[k] = f
			return f
		end
	});
	buf = setmetatable({
	}, {
		__index = function(self, k)
			local mt = getmetatable(self)
			local x = mt[k]
			if x ~= nil then return x end
			local f
			if k == 'line' then
				f = function()
					local pos = vim.api.nvim_win_get_cursor(0)
					return vim.api.nvim_buf_get_lines(0, pos[1]-1, pos[1], 'line')[1]
				end
			elseif k == 'nr' then
				f = vim.api.nvim_get_current_buf
			end
			mt[k] = f
			return f
		end
	});
	ex = setmetatable({}, {
		__index = function(self, k)
			local mt = getmetatable(self)
			local x = mt[k]
			if x ~= nil then
				return x
			end
			local command = k:gsub("_$", "!")
			local f = function(...)
				return vim.api.nvim_command(table.concat(vim.tbl_flatten {command, ...}, " "))
			end
			mt[k] = f
			return f
		end
	});
	g = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_get_var(k)
		end;
		__newindex = function(_, k, v)
			if v == nil then
				return vim.api.nvim_del_var(k)
			else
				return vim.api.nvim_set_var(k, v)
			end
		end;
	});
	v = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_get_vvar(k)
		end;
		__newindex = function(_, k, v)
			return vim.api.nvim_set_vvar(k, v)
		end
	});
	b = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_buf_get_var(0, k)
		end;
		__newindex = function(_, k, v)
			if v == nil then
				return vim.api.nvim_buf_del_var(0, k)
			else
				return vim.api.nvim_buf_set_var(0, k, v)
			end
		end
	});
	w = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_win_get_var(0, k)
		end;
		__newindex = function(_, k, v)
			if v == nil then
				return vim.api.nvim_win_del_var(0, k)
			else
				return vim.api.nvim_win_set_var(0, k, v)
			end
		end
	});
	o = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_get_option(k)
		end;
		__newindex = function(_, k, v)
			return vim.api.nvim_set_option(k, v)
		end
	});
	-- TODO add warning if you try to use a window option here?
	bo = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_buf_get_option(0, k)
		end;
		__newindex = function(_, k, v)
			return vim.api.nvim_buf_set_option(0, k, v)
		end
	});
	wo = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_win_get_option(0, k)
		end;
		__newindex = function(_, k, v)
			-- passing v == nil will clear the value, just like above.
			return vim.api.nvim_win_set_option(0, k, v)
		end
	});
	env = setmetatable({}, {
		__index = function(_, k)
			return vim.api.nvim_call_function('getenv', {k})
		end;
		__newindex = function(_, k, v)
			return vim.api.nvim_call_function('setenv', {k, v})
		end
	});
}, {
	__index = function(self, k)
		local mt = getmetatable(self)
		local x = mt[k]
		if x ~= nil then
			return x
		end
		local f = vim.api['nvim_'..k]
		mt[k] = f
		return f
	end
})


