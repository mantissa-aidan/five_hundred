local Utils = require "src.core.utils"
local Debug = require "src.config.debug"

local AudioManager = Utils.class("AudioManager")

AudioManager.SOUNDS = {
    CARD_SLIDE = "Card_Deal_4.wav",
    CARD_FLIP = "Card_Deal_4.wav",
    CARD_HOVER = "pop.wav",
    DEAL = "deal_2.wav",
    CLICK = "click.wav",
    ALERT = "alert.wav",
    WIN = "win.wav",
    LOSE = "lose.wav",
    SHUFFLE = "shuffle.wav",
    
    -- UI Sounds (Aliased to existing assets)
    BTN_HOVER_1 = "low.wav", -- Standard Button
    BTN_CLICK_1 = "tom.wav",
    
    BID_HOVER = "low.wav",   -- Bidding Grid
    BID_CLICK = "tom.wav",       -- Thud for selection
    
    NEXT_TRICK_HOVER = "low.wav", -- Tick sound
    NEXT_TRICK_CLICK = "high.wav"
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

function AudioManager:play(sound_id)
    if not self.enabled then return end
    
    local source = self.sources[sound_id]
    if source then
        -- Clone for polyphony (overlapping sounds)
        local clone = source:clone()
        clone:setVolume(self.volume)
        
        -- Random pitch variation: ±50 or ±100 cents (for testing - will reduce later)
        -- Pick random variation: 50 or 100 cents
        local cents_variation = (love.math.random() < 0.5) and 50 or 100
        -- Random direction: up or down
        local cents = (love.math.random() < 0.5) and cents_variation or -cents_variation
        -- Convert cents to pitch ratio: pitch = 2^(cents/1200)
        local pitch = 2 ^ (cents / 2200)
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
