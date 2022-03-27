--- Reload plugin module from scratch, restoring highlight for attached buffers.
local function reload()
    local c = require'colorizer'
    local oldbufs = {}
    for k, _ in pairs(c.BUFFER_OPTIONS) do
        table.insert(oldbufs, k)
    end
    package.loaded.colorizer = nil
    c = require'colorizer'
    for _, buf in ipairs(oldbufs) do
        c.attach_to_buffer(buf)
    end
end

return reload
