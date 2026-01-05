local Utils = require "src.core.utils"

local AudioManager = Utils.class("AudioManager")

AudioManager.SOUNDS = {
    CARD_SLIDE = "slide_1.wav",
    CARD_FLIP = "flip.wav",
    CARD_HOVER = "card_hover.wav",
    DEAL = "flip.wav",
    CLICK = "click.wav",
    ALERT = "alert.wav",
    WIN = "win.wav",
    LOSE = "lose.wav",
    SHUFFLE = "slide_2.wav" -- Substituting slide_2 for shuffle
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
        
        print("[AudioManager] PLAYING: " .. tostring(sound_id))
    else
        -- Silent fail / Debug log
        print("[AudioManager] Warning: Sound not loaded: " .. tostring(sound_id))
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
