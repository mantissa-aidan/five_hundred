local Config = {
    -- Window Settings
    window = {
        width = 1280,
        height = 800,
        title = "Five Hundred",
        resizable = true
    },
    
    -- Layout Settings
    layout = {
        chat_width = 300,
        card_scale = 0.9,
        hand_overlap = 40,
        padding = 10
    },
    
    -- Game Logic Settings
    game = {
        ai_delay = 0.5, -- seconds between bot moves
        animation_speed = 0.4 -- seconds for card fly animation
    },
    
    -- Visual Settings
    colors = {
        background = {0.05, 0.4, 0.1}, -- Green Felt
        chat_bg = {0.1, 0.1, 0.15, 1.0},
        
        -- Chat Avatars
        avatar = {
            ["You"] = {0.2, 0.6, 1.0},
            ["Bot 1"] = {0.8, 0.4, 0.4},
            ["Partner"] = {0.4, 0.8, 0.4},
            ["Bot 3"] = {1.0, 0.8, 0.2},
            ["System"] = {0.5, 0.5, 0.5}
        }
    },
    
    -- Debug Settings
    debug = {
        auto_start = false,
        show_bot_hands = true,
        hot_reload = true -- Set to true to enable hot reloading (can cause stutters on Windows if interval is too low)
    }
}

return Config
