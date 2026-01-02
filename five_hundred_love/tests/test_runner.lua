-- Test Runner Framework for Five Hundred Love
-- Minimal testing framework for Lua

-- Set up package path
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

local TestRunner = {}
TestRunner.tests = {}
TestRunner.current_suite = nil
TestRunner.stats = {passed = 0, failed = 0, errors = 0}
TestRunner.failures = {}

-- ANSI colors for terminal output
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    red = "\27[31m",
    yellow = "\27[33m",
    blue = "\27[34m",
    bold = "\27[1m"
}

function TestRunner.describe(name, fn)
    local old_suite = TestRunner.current_suite
    TestRunner.current_suite = name
    fn()
    TestRunner.current_suite = old_suite
end

function TestRunner.it(name, fn)
    local full_name = TestRunner.current_suite and (TestRunner.current_suite .. " > " .. name) or name
    table.insert(TestRunner.tests, {name = full_name, fn = fn})
end

function TestRunner.run()
    print(colors.bold .. "\n=== Running Tests ===" .. colors.reset .. "\n")

    for _, test in ipairs(TestRunner.tests) do
        local success, err = pcall(test.fn)
        if success then
            TestRunner.stats.passed = TestRunner.stats.passed + 1
            print(colors.green .. "  ✓ " .. colors.reset .. test.name)
        else
            TestRunner.stats.failed = TestRunner.stats.failed + 1
            print(colors.red .. "  ✗ " .. colors.reset .. test.name)
            print(colors.red .. "    Error: " .. tostring(err) .. colors.reset)
            table.insert(TestRunner.failures, {name = test.name, error = err})
        end
    end

    print("\n" .. colors.bold .. "=== Results ===" .. colors.reset)
    print(colors.green .. "  Passed: " .. TestRunner.stats.passed .. colors.reset)
    if TestRunner.stats.failed > 0 then
        print(colors.red .. "  Failed: " .. TestRunner.stats.failed .. colors.reset)
    else
        print("  Failed: 0")
    end

    if #TestRunner.failures > 0 then
        print("\n" .. colors.red .. colors.bold .. "Failed Tests:" .. colors.reset)
        for _, f in ipairs(TestRunner.failures) do
            print(colors.red .. "  - " .. f.name .. colors.reset)
            print("    " .. tostring(f.error))
        end
    end

    print("")

    return TestRunner.stats.failed == 0
end

-- Assertion helpers
function TestRunner.assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "Assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function TestRunner.assert_true(value, msg)
    if not value then
        error((msg or "Assertion failed") .. ": expected true, got " .. tostring(value))
    end
end

function TestRunner.assert_false(value, msg)
    if value then
        error((msg or "Assertion failed") .. ": expected false, got " .. tostring(value))
    end
end

function TestRunner.assert_nil(value, msg)
    if value ~= nil then
        error((msg or "Assertion failed") .. ": expected nil, got " .. tostring(value))
    end
end

function TestRunner.assert_not_nil(value, msg)
    if value == nil then
        error((msg or "Assertion failed") .. ": expected non-nil value")
    end
end

function TestRunner.assert_error(fn, msg)
    local success, _ = pcall(fn)
    if success then
        error((msg or "Expected error") .. ": function did not throw")
    end
end

function TestRunner.assert_table_length(t, expected_length, msg)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    if count ~= expected_length then
        error((msg or "Table length mismatch") .. ": expected " .. expected_length .. ", got " .. count)
    end
end

function TestRunner.assert_contains(t, value, msg)
    for _, v in pairs(t) do
        if v == value then return end
    end
    error((msg or "Table does not contain value") .. ": " .. tostring(value))
end

-- Reset for fresh test runs
function TestRunner.reset()
    TestRunner.tests = {}
    TestRunner.stats = {passed = 0, failed = 0, errors = 0}
    TestRunner.failures = {}
    TestRunner.current_suite = nil
end

return TestRunner
