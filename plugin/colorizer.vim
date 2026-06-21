if exists('g:loaded_colorizer')
  finish
endif

command! ColorizerAttachToBuffer lua require'colorizer'.attach_to_buffer(0)
command! ColorizerDetachFromBuffer lua require'colorizer'.detach_from_buffer(0)
command! ColorizerReloadAllBuffers lua require'colorizer'.reload_all_buffers()
command! ColorizerToggle lua local c = require'colorizer'
            \ if c.is_buffer_attached(0) then c.detach_from_buffer(0) else
            \ c.attach_to_buffer(0) end
command! ColorizerColorInfoToggle lua require'colorizer'.toggle_color_info(0)

let g:loaded_colorizer = 1
