if exists('g:loaded_colorizer')
  finish
endif

command! ReloadBufferColorizer lua require'colorizer'.reload_buffer()

let g:loaded_colorizer = 1
