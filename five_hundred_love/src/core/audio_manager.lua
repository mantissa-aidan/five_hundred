local Utils = require "src.core.utils"
local Debug = require "src.config.debug"

local AudioManager = Utils.class("AudioManager")

AudioManager.SOUNDS = {
    CARD_SLIDE = "slide_1.wav",
    CARD_FLIP = "flip.wav",
    CARD_HOVER = "card_hover.wav",
    DEAL = "deal_2.wav",
    CLICK = "click.wav",
    ALERT = "alert.wav",
    WIN = "win.wav",
    LOSE = "lose.wav",
    SHUFFLE = "shuffle.wav",
    INVALID = "wrong.wav",
    
    -- Bidding
    BID_MADE = "bid_made.wav",
    BID_WON = "bid_won.wav", -- Contract won
    BID_LOST = "bid_lost.wav", -- Contract set?
    
    -- Trick
    TRICK_WON = "trick_won.wav",
    TRICK_LOST = "trick_lost.wav",
    
    -- UI Sounds
    BTN_HOVER_1 = "button_hover.wav",
    BTN_CLICK_1 = "button_click.wav",
    
    BID_HOVER = "button_hover.wav",
    BID_CLICK = "button_click.wav",
    
    NEXT_TRICK_HOVER = "button_hover.wav",
    NEXT_TRICK_CLICK = "button_click.wav"
}

function AudioManager:init()
    self.sources = {}
    self.active_sources = {}
    self.enabled = true
    self.volume = 1.0
    
    self:load_assets()
end

function AudioManager:update(dt)
    -- Clean up finished sources
    for i = #self.active_sources, 1, -1 do
        local s = self.active_sources[i]
        if not s:isPlaying() then
            table.remove(self.active_sources, i)
        end
    end
end

function AudioManager:load_assets()
    local dir = "assets/sounds/"
    
    for id, filename in pairs(self.SOUNDS) do
        local path = dir .. filename
        -- Check if file exists using love.filesystem
        if love.filesystem.getInfo(path) then
             -- Load as static for short SFX
            local success, source = pcall(love.audio.newSource, path, "static")
            if success then
                self.sources[id] = source
                print("[AudioManager] Loaded: " .. filename)
            else
                print("[AudioManager] Failed to load: " .. filename .. " (" .. tostring(source) .. ")")
            end
        else
            print("[AudioManager] Missing asset: " .. filename)
        end
    end
end

function AudioManager:play(sound_id, params)
    if not self.enabled then return end
    
    local source = self.sources[sound_id]
    if source then
        -- Clone for polyphony (overlapping sounds)
        local clone = source:clone()
        clone:setVolume(self.volume * (params and params.volume or 1.0))
        
        -- Pitch Logic
        local pitch = 1.0
        if params and params.pitch then
            pitch = params.pitch
        else
            -- Default random variation
            local cents_variation = (love.math.random() < 0.5) and 20 or 40
            local cents = (love.math.random() < 0.5) and cents_variation or -cents_variation
            pitch = 2 ^ (cents / 2200)
        end
        clone:setPitch(pitch)
        
        clone:play()
        
        -- Store reference to prevent Garbage Collection
        table.insert(self.active_sources, clone)
        
        local filename = self.SOUNDS[sound_id] or "unknown"
        
        -- Get caller information (2 levels up: this function -> play -> caller)
        local info = debug.getinfo(2, "Sln")
        local caller = "unknown"
        if info then
            if info.name then
                caller = info.name
            elseif info.source and info.currentline then
                -- If no function name, show file:line
                caller = string.format("%s:%d", info.short_src, info.currentline)
            end
        end
        
        Debug:log("AUDIO", "PLAYING: %s (%s) from %s", sound_id, filename, caller)
    else
        -- Silent fail / Debug log
        Debug:log("AUDIO", "Warning: Sound not loaded: %s", tostring(sound_id))
    end
end

function AudioManager:set_volume(v)
    self.volume = math.max(0, math.min(1, v))
end

function AudioManager:toggle_mute()
    self.enabled = not self.enabled
    return self.enabled
end

return AudioManager
