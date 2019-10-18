# colorizer.lua

[![luadoc](https://img.shields.io/badge/luadoc-0.1-blue)](https://norcalli.github.io/luadoc/nvim-colorizer.lua/modules/colorizer.html)

A high-performance color highlighter for Neovim which has **no external dependencies**! Written in performant Luajit.

![Demo.mp4](https://raw.githubusercontent.com/norcalli/github-assets/master/nvim-colorizer.lua-demo-short.mp4)

## Installation and Usage

Use your plugin manager or clone directly into your `runtimepath`.

```vim
Plug 'norcalli/nvim-colorizer.lua'
```

As long as you have `malloc()` and `free()` on your system, this will work. Which includes Linux, OSX, and Windows.

One line setup. This will create an `autocmd` for `FileType *` to highlight every filetype.

```vim
lua require'colorizer'.setup()
```

### Why another highlighter?

This has no external dependencies, which means you install it and it works. Other colorizers typically were synchronous and slow, as well. Being written with performance in mind and leveraging the excellent LuaJIT and a handwritten parser, updates can be done in real time. There are plugins such as [hexokinase](https://github.com/RRethy/vim-hexokinase) which have good performance, but it has some difficulty with becoming out of sync. The downside is that *this only works for Neovim*, and that will never change.

Additionally, having a Lua API that's available means users can use this as a library to do custom highlighting themselves.

### Customization

The available highlight modes are `foreground`, `background`. The default is
`background`.

Full options list:
- `no_names`: Disable parsing names like "Blue"
- `rgb_fn`: Enable parsing `rgb(...)` functions.
- `mode`: Highlight mode. Valid options: `foreground`,`background`

For basic setup, you can use a command like the following.

```lua
-- Attaches to every FileType mode
require 'colorizer'.setup()

-- Attach to certain Filetypes, add special configuration for `html`
-- Use `background` for everything else.
require 'colorizer'.setup {
  'css';
  'javascript';
  html = {
	  mode = 'foreground';
  }
}

-- Use the `default_options` as the second parameter, which uses
-- `foreground` for every mode. This is the inverse of the previous
-- setup configuration.
require 'colorizer'.setup({
  'css';
  'javascript';
  html = { mode = 'background' };
}, { mode = 'foreground' })

-- Use the `default_options` as the second parameter, which uses
-- `foreground` for every mode. This is the inverse of the previous
-- setup configuration.
require 'colorizer'.setup {
  '*'; -- Highlight all files, but customize some others.
  css = { rgb_fn = true; }; -- Enable parsing rgb(...) functions in css.
  html = { no_names = true; } -- Disable parsing "names" like Blue or Gray
}
```


For lower level interface, see the [LuaDocs for API details](https://norcalli.github.io/luadoc/nvim-colorizer.lua/modules/colorizer.html) or use `:h colorizer.lua` once installed.

## TODO

- [ ] Add more display modes?
- [ ] Use a more space efficient trie implementation.
- [ ] Create a COMMON_SETUP which does obvious things like enable `rgb_fn` for css
