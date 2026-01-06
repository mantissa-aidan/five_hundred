-- Debug Configuration System
-- Provides categorized logging to reduce console spam and focus on specific issues

local Debug = {
    -- Audio System
    AUDIO = true,              -- AudioManager play calls and sound loading
    
    -- UI Animations
    ANIMATION = false,          -- Animation progress and state changes
    BIDDING_ANIM = false,       -- Specific to bidding UI animation
    CHAT_ANIM = false,          -- Chat panel slide animation
    
    -- Game State
    GAME_STATE = false,          -- Game phase transitions (BIDDING, PLAYING, etc.)
    DEAL = false,               -- Card dealing animation
    
    -- User Interactions
    CARD_INTERACTION = false,   -- Drag/drop/click on cards
    BUTTON_INTERACTION = false, -- Button hover/click events
    
    -- System
    HOT_RELOAD = false,         -- Lurker hot-reload events
    LAYOUT = false,             -- UI layout calculations and resize
    
    -- Testing
    TEST_VERBOSE = false,       -- Verbose test output
}

--- Log a message if the category is enabled
-- @param category string Category name (must match a key in Debug table)
-- @param message string Message to log
-- @param ... any Additional arguments to format into message
function Debug:log(category, message, ...)
    if self[category] then
        if select("#", ...) > 0 then
            message = string.format(message, ...)
        end
        print(string.format("[%s] %s", category, message))
    end
end

--- Enable a debug category
-- @param category string Category to enable
function Debug:enable(category)
    if self[category] ~= nil then
        self[category] = true
        print(string.format("[DEBUG] Enabled category: %s", category))
    else
        print(string.format("[DEBUG] Warning: Unknown category '%s'", category))
    end
end

--- Disable a debug category
-- @param category string Category to disable
function Debug:disable(category)
    if self[category] ~= nil then
        self[category] = false
        print(string.format("[DEBUG] Disabled category: %s", category))
    else
        print(string.format("[DEBUG] Warning: Unknown category '%s'", category))
    end
end

--- Enable all debug categories
function Debug:enable_all()
    for key, _ in pairs(self) do
        if type(self[key]) == "boolean" then
            self[key] = true
        end
    end
    print("[DEBUG] All categories enabled")
end

--- Disable all debug categories
function Debug:disable_all()
    for key, _ in pairs(self) do
        if type(self[key]) == "boolean" then
            self[key] = false
        end
    end
    print("[DEBUG] All categories disabled")
end

--- Print current debug configuration
function Debug:print_config()
    print("[DEBUG] Current Configuration:")
    for key, value in pairs(self) do
        if type(value) == "boolean" then
            print(string.format("  %s: %s", key, value and "ON" or "OFF"))
        end
    end
end

return Debug
