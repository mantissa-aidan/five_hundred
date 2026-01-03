require "love.filesystem"
require "love.timer"

local channel = love.thread.getChannel("ai_load")
local path = ... -- passed as arg

if not love.filesystem.getInfo(path) then
    channel:push({error = "Weights file not found: " .. path})
    return
end

-- Load JSON library
-- Note: Threads have separate environments, ensuring package.path finds src
-- Love2D module loader usually handles this if requiring relative to main.lua
local status, json = pcall(require, "src.ext.json")
if not status then
    -- Try to adjust package path if needed?
    -- Usually "love ." sets root correctly.
    channel:push({error = "Failed to load json lib: " .. tostring(json)})
    return
end

-- Read File
local content = love.filesystem.read(path)
if not content then
    channel:push({error = "Failed to read file"})
    return
end

-- Decode JSON
local status, data = pcall(json.decode, content)
if not status then
    channel:push({error = "JSON Decode Error: " .. tostring(data)})
    return
end

-- Send Data
channel:push(data)
