-- local function print( ... )
--     local tbl = {...}
--     local len = #tbl
--     for i = 1, len do
--         tbl[ i ] = tostring( tbl[ i ] )
--     end
--     Logger:Info( table.concat(tbl, "\t" ) )
-- end

-- local submodule = require "./submodule.lua"

-- print("Got from submodule:", submodule)
-- Promise.delay(1):await()

-- print("I am", __package )
-- require "b"

local data = require "submodule"
print(data)

return "this package is da best"
