-- Animation Manager for Five Hundred Love
-- Handles card fly-in animations, dealing sequences, and timing

local Utils = require "src.core.utils"

local AnimationManager = Utils.class("AnimationManager")

function AnimationManager:init(audio_manager)
    -- Dependencies (optional, with fallback to global)
    self.audio = audio_manager or gAudioManager

    -- Animation queues
    self.animations = {}           -- Active animations
    self.pending_animations = {}   -- Delayed start queue

    -- Blocking state
    self.is_animating = false
    self.animation_delay_timer = 0
    self.animation_delay_duration = 1.0  -- Post-animation pause

    -- Dealing state
    self.dealing_in_progress = false
    self.dealt_cards = {}          -- {[card] = true} for cards that have landed
    self.card_land_times = {}      -- {[card] = timestamp} for float dampening
end

-- Queue an immediate animation
function AnimationManager:queue(params)
    self.is_animating = true

    if params.play_sound ~= false and self.audio then
        self.audio:play(params.sound or "CARD_SLIDE")
    end

    table.insert(self.animations, {
        type = params.type or "FLY_IN",
        card = params.card,
        player_idx = params.player_idx,
        start_pos = {x = params.start_x, y = params.start_y},
        end_pos = {x = params.end_x, y = params.end_y},
        t = 0,
        duration = params.duration or 0.3,
        target_idx = params.card_idx,
        on_complete = params.on_complete,
        start_scale = params.start_scale or 1.0,
        start_rot = params.start_rot or 0,
        end_rot = params.end_rot or 0,
        power = params.power -- Store power level
    })

    return self
end

-- Queue a delayed animation (for dealing sequences)
function AnimationManager:queue_delayed(params)
    self.is_animating = true

    table.insert(self.pending_animations, {
        type = params.type or "FLY_IN",
        card = params.card,
        start_pos = {x = params.start_x, y = params.start_y},
        end_pos = {x = params.end_x, y = params.end_y},
        duration = params.duration or 0.2,
        delay = params.delay or 0,
        target_idx = params.card_idx,
        on_complete = params.on_complete,
        start_scale = params.start_scale or 1.0,
        start_rot = params.start_rot or 0,
        end_rot = params.end_rot or 0,
        sound = params.sound or "DEAL"
    })

    return self
end

-- Queue a turn update action (processed after animation completes)
function AnimationManager:queue_action(action)
    self.action_queue = self.action_queue or {}
    table.insert(self.action_queue, action)
    return self
end

-- Get and clear the action queue
function AnimationManager:pop_actions()
    local actions = self.action_queue or {}
    self.action_queue = {}
    return actions
end

-- Process animation frames
function AnimationManager:update(dt)
    -- Update pending animations (delayed starts)
    for i = #self.pending_animations, 1, -1 do
        local pending = self.pending_animations[i]
        pending.delay = pending.delay - dt
        if pending.delay <= 0 then
            -- Play deal sound when animation actually starts
            if pending.type == "FLY_IN" and self.audio then
                self.audio:play(pending.sound or "DEAL")
            end

            -- Move to active queue
            table.insert(self.animations, {
                type = pending.type,
                card = pending.card,
                start_pos = pending.start_pos,
                end_pos = pending.end_pos,
                t = 0,
                duration = pending.duration,
                target_idx = pending.target_idx,
                on_complete = pending.on_complete,
                start_scale = pending.start_scale,
                start_rot = pending.start_rot,
                end_rot = pending.end_rot
            })
            table.remove(self.pending_animations, i)
        end
    end

    -- Update active animations
    for i = #self.animations, 1, -1 do
        local anim = self.animations[i]
        anim.t = anim.t + dt
        if anim.t >= anim.duration then
            if anim.on_complete then anim.on_complete() end
            
            -- Slam Shake for high power cards
            if (anim.power or 0) > 0.7 then
                gScreenShake = 1.5
            end
            
            table.remove(self.animations, i)

            -- Start delay timer after all animations complete
            if #self.animations == 0 and #self.pending_animations == 0 then
                self.animation_delay_timer = self.animation_delay_duration
            end
        end
    end

    -- Handle post-animation delay
    if self.animation_delay_timer > 0 then
        self.animation_delay_timer = self.animation_delay_timer - dt
        if self.animation_delay_timer <= 0 then
            self.is_animating = false
        end
    end
end

-- Check if animations are blocking game logic
function AnimationManager:is_busy()
    return self.is_animating
end

-- Check if in post-animation delay
function AnimationManager:in_delay()
    return self.animation_delay_timer > 0
end

-- Skip all animations and reset state
function AnimationManager:skip_all()
    self.animations = {}
    self.pending_animations = {}
    self.dealing_in_progress = false
    self.is_animating = false
    self.animation_delay_timer = 0
end

-- Start a dealing sequence
function AnimationManager:start_dealing()
    self.animations = {}
    self.pending_animations = {}
    self.dealing_in_progress = true
    self.is_animating = true
    self.dealt_cards = {}
    self.card_land_times = {}
end

-- Mark a card as dealt (landed)
function AnimationManager:mark_card_dealt(card)
    self.dealt_cards[card] = true
    self.card_land_times[card] = love.timer.getTime()
end

-- End dealing sequence
function AnimationManager:finish_dealing()
    self.dealing_in_progress = false
end

-- Check if a card is currently animating
function AnimationManager:is_card_animating(card)
    for _, anim in ipairs(self.animations) do
        if anim.card == card then return true end
    end
    for _, anim in ipairs(self.pending_animations) do
        if anim.card == card then return true end
    end
    return false
end

-- Get set of all currently animating cards
function AnimationManager:get_animating_cards()
    local cards = {}
    for _, anim in ipairs(self.animations) do
        if anim.card then cards[anim.card] = true end
    end
    for _, anim in ipairs(self.pending_animations) do
        if anim.card then cards[anim.card] = true end
    end
    return cards
end

-- Get when a card landed (for float dampening)
function AnimationManager:get_card_land_time(card)
    return self.card_land_times[card]
end

-- Check if a card has been dealt (for rendering during deal animation)
function AnimationManager:is_card_dealt(card)
    return self.dealt_cards[card] == true
end

-- Get active animations for rendering
function AnimationManager:get_animations()
    return self.animations
end

-- Check if dealing is in progress
function AnimationManager:is_dealing()
    return self.dealing_in_progress
end

return AnimationManager
