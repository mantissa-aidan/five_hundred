#!/usr/bin/env lua
-- Main Test Runner for Five Hundred Love
-- Run this file to execute all tests

-- Set up package paths
package.path = package.path .. ";five_hundred_love/?.lua;?.lua"

-- Mock 'love' table if missing (for headless testing)
if not love then
    love = {
        filesystem = {
            read = function(path)
                local f = io.open(path, "r")
                if not f then return nil end
                local c = f:read("*a")
                f:close()
                return c
            end
        },
        math = math,
        graphics = {
            getWidth = function() return 1920 end,
            getHeight = function() return 1080 end,
            setColor = function() end,
            rectangle = function() end,
            print = function() end,
            printf = function() end,
            push = function() end,
            pop = function() end,
            translate = function() end,
            rotate = function() end,
            setScissor = function() end,
        },
        mouse = {
            getPosition = function() return 0, 0 end
        }
    }
end

local TestRunner = require "tests.test_runner"

-- ANSI colors
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    red = "\27[31m",
    yellow = "\27[33m",
    blue = "\27[34m",
    bold = "\27[1m",
    cyan = "\27[36m"
}

print(colors.bold .. colors.cyan)
print("╔═══════════════════════════════════════════════════════════╗")
print("║           Five Hundred Love - Test Suite                  ║")
print("╚═══════════════════════════════════════════════════════════╝")
print(colors.reset)

-- Track overall stats
local total_passed = 0
local total_failed = 0
local suite_results = {}

-- List of test modules to run
local test_modules = {
    {name = "Card Tests", path = "tests.test_card"},
    {name = "Deck Tests", path = "tests.test_deck"},
    {name = "Player Tests", path = "tests.test_player"},
    {name = "Team Tests", path = "tests.test_team"},
    {name = "Bid Tests", path = "tests.test_bid"},
    {name = "Game Tests", path = "tests.test_game"},
    {name = "Strategy Tests", path = "tests.test_strategy"},
    {name = "View Logic Tests", path = "tests.test_view_logic"},
    {name = "Regression Tests", path = "tests.test_regression"},
}

-- Run each test module
for _, module in ipairs(test_modules) do
    print(colors.bold .. colors.blue .. "\n▶ Running: " .. module.name .. colors.reset)
    print(string.rep("-", 50))

    -- Reset test runner state
    TestRunner.reset()

    -- Load the test module
    local success, err = pcall(function()
        require(module.path)
    end)

    if not success then
        print(colors.red .. "  ✗ Failed to load test module: " .. tostring(err) .. colors.reset)
        total_failed = total_failed + 1
        table.insert(suite_results, {name = module.name, passed = 0, failed = 1, error = err})
    else
        -- Run the tests
        local test_success = TestRunner.run()

        total_passed = total_passed + TestRunner.stats.passed
        total_failed = total_failed + TestRunner.stats.failed

        table.insert(suite_results, {
            name = module.name,
            passed = TestRunner.stats.passed,
            failed = TestRunner.stats.failed
        })
    end
end

-- Print summary
print(colors.bold .. colors.cyan)
print("\n╔═══════════════════════════════════════════════════════════╗")
print("║                    TEST SUMMARY                           ║")
print("╚═══════════════════════════════════════════════════════════╝")
print(colors.reset)

for _, result in ipairs(suite_results) do
    local status_color = result.failed > 0 and colors.red or colors.green
    local status_icon = result.failed > 0 and "✗" or "✓"
    print(string.format("  %s%s %s%s: %d passed, %d failed",
        status_color, status_icon, colors.reset,
        result.name, result.passed, result.failed))
end

print(string.rep("═", 60))
print(colors.bold .. string.format("TOTAL: %s%d passed%s, %s%d failed%s",
    colors.green, total_passed, colors.reset .. colors.bold,
    total_failed > 0 and colors.red or colors.reset, total_failed, colors.reset))

if total_failed == 0 then
    print(colors.bold .. colors.green .. "\n✓ All tests passed!" .. colors.reset)
    os.exit(0)
else
    print(colors.bold .. colors.red .. "\n✗ Some tests failed!" .. colors.reset)
    os.exit(1)
end
