if exists('g:loaded_colorizer')
  finish
endif

command! ColorizerAttachToBuffer lua require'colorizer'.attach_to_buffer(0)
command! ColorizerDetachFromBuffer lua require'colorizer'.detach_from_buffer(0)
command! ColorizerReloadAllBuffers lua require'colorizer'.reload_all_buffers()

let g:loaded_colorizer = 1
