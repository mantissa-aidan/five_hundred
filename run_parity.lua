
-- Run Parity Tests Standalone
package.path = package.path .. ";five_hundred_love/?.lua;?.lua;five_hundred_love/src/?.lua"

local TestRunner = require "five_hundred_love.tests.test_parity"

print("Starting Parity Check...")
local passed = TestRunner.run()

if passed then
    os.exit(0)
else
    os.exit(1)
end
