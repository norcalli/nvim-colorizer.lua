if exists('g:loaded_colorizer')
  finish
endif

command! ReloadBufferColorizer lua require'colorizer'.reload_buffer()
command! ColorizerAttachToBuffer lua require'colorizer'.attach_to_buffer(0)

let g:loaded_colorizer = 1
