-- To-do List for PUNRI. All data stays on the SD card; no network is used.
local start = punri.dofile("organizer.lua")
start({name = "To-do List", tasks = true})
