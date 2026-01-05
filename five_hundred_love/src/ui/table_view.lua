local CardRenderer = require "src.ui.card_renderer"
local Utils = require "src.core.utils"
local BiddingView = require "src.ui.bidding_view"
local Config = require "src.config"
local Card = require "src.core.card"
local Suit = Card.Suit

local HAND_SPREAD_HUMAN = 90
local HAND_SPREAD_BOT = 30
local HAND_Y_OFFSET = -60

local TableView = Utils.class("TableView")
local ParticleSystem = require "src.ui.particle_system"

function TableView:init(game)
    self.game = game
    
    -- Layout Config - table takes left portion, leaving space for chat on right
    local chat_width = Config.layout.chat_width
    self.width = love.graphics.getWidth() - chat_width
    self.height = love.graphics.getHeight()
    
    self.card_scale = 1.3  -- Larger cards per user request
    -- Center of game area (not full screen)
    self.center_x = self.width / 2
    self.center_y = self.height / 2
    
    self.bidding_view = BiddingView.new(game, self.width, self.height)
    self.selected_discards = {} -- Set of card indices for P1
    self.animations = {} -- List of {type, card, start_pos, end_pos, t, duration}
    self.pending_animations = {} -- Delayed animations waiting to start
    self.particles = ParticleSystem.new()
    self.dragged_card = nil
    self.drag_offset = {x=0, y=0}
    
    -- Hook Animation Callback
    game:set_on_card_play(function(p_idx, card)
        self:on_card_played(p_idx, card)
    end)
    
    -- UI Polish State
    self.turn_alphas = {0,0,0,0} -- Alpha for each player's turn indicator
    self.hud_state = {
        us_score=0, them_score=0,
        us_scale={val=1, vel=0, target=1},
        them_scale={val=1, vel=0, target=1}
    }
    
    -- Animation State
    self.is_animating = false
    self.animation_delay_timer = 0
    self.animation_delay_duration = 1.0 -- Slower pace (was 0.3)
    
    -- Background Shader Setup
    self.bg_shader = love.graphics.newShader("src/shaders/background.glsl")
    print("[TableView] Shader loaded:", self.bg_shader)
    self.bg_time = 0
    
    self.last_hovered_idx = nil
    
    -- Per-player hand springs for smooth reorganization
    self.hand_springs = {
        [1] = {},  -- P1 (human)
        [2] = {},  -- P2 (bot)
        [3] = {},  -- P3 (bot)
        [4] = {}   -- P4 (bot)
    }
    
    -- Turn Animation State
    self.last_player_idx = nil
    self.visual_current_player_idx = game.current_player_idx -- Decoupled visual state
    self.turn_start_time = 0
    self.last_game_state = "WAITING"
    
    -- Visual Action Queue (for sequencing events)
    self.action_queue = {}
end

function TableView:resize(w, h)
    -- Recalculate dimensions (chat log takes fixed 300px)
    -- Recalculate dimensions (chat log takes fixed 300px)
    local chat_width = Config.layout.chat_width
    self.width = w - chat_width
    self.height = h
    self.center_x = self.width / 2
    self.center_y = self.height / 2
    
    -- Resize child views
    if self.bidding_view then
        self.bidding_view:resize(self.width, self.height)
    end
end

function TableView:on_card_played(p_idx, card)
    if p_idx == 1 then 
        if gAudioManager then gAudioManager:play("CARD_SLIDE") end
        return 
    end -- P1 cards don't animate
    
    -- Determine start position based on player index
    -- P2 (Left): 50, center_y
    -- P3 (Top): center_x, 50
    -- P4 (Right): width-50, center_y
    local start_x, start_y
    if p_idx == 2 then start_x, start_y = 50, self.center_y
    elseif p_idx == 3 then start_x, start_y = self.center_x, 50
    elseif p_idx == 4 then start_x, start_y = self.width - 50, self.center_y
    else return end
    
    -- Calculate end position - must match EXACTLY where draw_current_trick draws the card
    -- draw_current_trick translates to (center_x, center_y) then draws at (offset.x - 40, offset.y - 55)
    local positions = {
        [1] = {x=0, y=90},  -- Bottom
        [2] = {x=-120, y=0}, -- Left
        [3] = {x=0, y=-90}, -- Top
        [4] = {x=120, y=0}   -- Right
    }
    local offset = positions[p_idx]
    
    -- Absolute position: center + offset - card adjustments
    local end_x = self.center_x + offset.x - 40
    local end_y = self.center_y + offset.y - 55
    
    -- Get card index in hand  
    local card_idx = nil
    local player = self.game.players[p_idx]
    if player then
        for i, c in ipairs(player.hand) do
            if c == card then
                card_idx = i
                break
            end
        end
    end
    
    self.card_land_times = self.card_land_times or {}
    
    self:play_card_animation(p_idx, card, start_x, start_y, end_x, end_y, 0.3, card_idx, function()
        -- Mark when card landed
        self.card_land_times[card] = love.timer.getTime()
    end)
end

function TableView:play_card_animation(p_idx, card, start_x, start_y, end_x, end_y, duration, card_idx, on_complete, start_scale)
    self.is_animating = true -- Block game updates
    
    if gAudioManager then gAudioManager:play("CARD_SLIDE") end
    
    table.insert(self.animations, {
        type = "FLY_IN",
        card = card,
        player_idx = p_idx,  -- Track which player this animation belongs to
        start_pos = {x=start_x, y=start_y},
        end_pos = {x=end_x, y=end_y},
        t = 0,
        duration = duration,
        target_idx = card_idx,
        on_complete = on_complete,
        start_scale = start_scale or 1.0
    })
    
    -- Queue Current Turn State to apply AFTER animation
    -- This captures the state *after* the card is played (which logic has already processed)
    -- But since logic has processed it, game.current_player_idx is ALREADY the next player.
    -- So we want to capture that specific "Next Player" index and enforce it later.
    
    table.insert(self.action_queue, {
        type = "UPDATE_TURN",
        player_idx = self.game.current_player_idx -- This is the FUTURE turn (Next Player)
    })
end

function TableView:update_animations(dt)
    -- Update pending animations (delayed starts)
    for i = #self.pending_animations, 1, -1 do
        local pending = self.pending_animations[i]
        pending.delay = pending.delay - dt
        if pending.delay <= 0 then
            -- Play deal sound when animation actually starts
            if pending.type == "FLY_IN" and gAudioManager then
                gAudioManager:play("DEAL")
            end
            
            -- Start the animation
            table.insert(self.animations, {
                type = pending.type,
                card = pending.card,
                start_pos = pending.start_pos,
                end_pos = pending.end_pos,
                t = 0,
                duration = pending.duration,
                target_idx = pending.target_idx,
                on_complete = pending.on_complete,
                start_scale = pending.start_scale
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
            table.remove(self.animations, i)
            
            -- Start delay timer after animation completes
            if #self.animations == 0 and #self.pending_animations == 0 then
                self.animation_delay_timer = self.animation_delay_duration
            end
        end
    end
    
    -- Handle post-animation delay (blocks game logic but not animation updates)
    if self.animation_delay_timer > 0 then
        self.animation_delay_timer = self.animation_delay_timer - dt
        if self.animation_delay_timer <= 0 then
            self.is_animating = false -- Unblock game
        end
    end
end

function TableView:play_card_animation_delayed(card, start_x, start_y, end_x, end_y, duration, delay, on_complete, start_scale)
    self.is_animating = true
    
    table.insert(self.pending_animations, {
        type = "FLY_IN",
        card = card,
        start_pos = {x=start_x, y=start_y},
        end_pos = {x=end_x, y=end_y},
        duration = duration,
        delay = delay,
        target_idx = nil,
        on_complete = on_complete,
        start_scale = 1.0
    })
end

function TableView:animate_deal()
    -- Clear any existing animations
    self.animations = {}
    self.pending_animations = {}
    self.dealing_in_progress = true
    self.is_animating = true
    self.dealt_cards = {} -- Track which cards have been dealt (landed)
    
    print("[DEAL] Starting deal animation")
    
    local deck_x = self.center_x
    local deck_y = self.center_y
    local delay = 0
    local card_delay = 0.05 -- 50ms between each card
    
    -- Deal 10 cards to each player in rotation
    for round = 1, 10 do
        for p_idx = 1, 4 do
            local card = self.game.players[p_idx].hand[round]
            if card then
                local end_x, end_y = self:get_deal_target_position(p_idx, round)
                
                print(string.format("[DEAL] Queueing card %d for P%d: %s -> (%.1f, %.1f) delay=%.2f", 
                    round, p_idx, tostring(card), end_x, end_y, delay))
                
                -- Capture card reference for callback
                local card_ref = card
                self:play_card_animation_delayed(card, deck_x, deck_y, end_x, end_y, 0.2, delay, function()
                    -- Mark card as dealt
                    self.dealt_cards[card_ref] = true
                    
                    if round == 10 and p_idx == 4 then
                        -- Last card dealt, now deal kitty
                        self:deal_kitty(delay + card_delay)
                    end
                end)
                
                delay = delay + card_delay
            end
        end
    end
    
    print(string.format("[DEAL] Queued %d pending animations", #self.pending_animations))
end

function TableView:deal_kitty(start_delay)
    local deck_x = self.center_x
    local deck_y = self.center_y
    local card_delay = 0.05
    
    -- Deal 3 kitty cards to center
    for i = 1, 3 do
        if self.game.kitty and self.game.kitty[i] then
            local card = self.game.kitty[i]
            -- Kitty cards stay near center, slightly offset
            local end_x = deck_x + (i - 2) * 30 - 40
            local end_y = deck_y - 100
            
            local delay = start_delay + (i - 1) * card_delay
            self:play_card_animation_delayed(card, deck_x, deck_y, end_x, end_y, 0.2, delay, function()
                if i == 3 then
                    -- All cards dealt
                    self.dealing_in_progress = false
                end
            end)
        end
    end
end

function TableView:get_deal_target_position(p_idx, card_idx)
    -- Calculate where card should land in player's hand
    if p_idx == 1 then
        -- Bottom player (human) - use hand layout
        local hand_size = 10
        local total_width = (hand_size - 1) * HAND_SPREAD_HUMAN
        local start_x = -total_width / 2
        local card_x = start_x + (card_idx - 1) * HAND_SPREAD_HUMAN
        local card_y = HAND_Y_OFFSET
        
        return self.center_x + card_x, self.height - 100 + card_y
    else
        -- Other players - just approximate positions (they won't show individual cards anyway)
        if p_idx == 2 then
            return 100, self.center_y
        elseif p_idx == 3 then
            return self.center_x, 100
        else -- p_idx == 4
            return self.width - 100, self.center_y
        end
    end
end

function TableView:skip_dealing_animation()
    -- Clear all animations
    self.animations = {}
    self.pending_animations = {}
    self.dealing_in_progress = false
    self.is_animating = false
    self.animation_delay_timer = 0
end

-- ...



function TableView:update_hand_springs(dt)
    if not self.hand_springs then 
        self.hand_springs = {
            [1] = {}, [2] = {}, [3] = {}, [4] = {}
        }
    end
    
    local player = self.game.players[1]
    if not player then return end
    
    local hand_size = #player.hand
    local player_springs = self.hand_springs[1]  -- P1 springs
    
    -- Ensure spring state exists
    for i=1, hand_size do
        if not player_springs[i] then
            -- Calculate initial position for new spring
            local spread = 90
            local start_x = -((hand_size - 1) * spread) / 2
            local initial_x = start_x + (i-1) * spread
            
            player_springs[i] = {
                x = {val=initial_x, vel=0, target=initial_x},  -- Position interpolation
                scale = {val=1, vel=0, target=1},
                pitch = {val=0, vel=0, target=0},
                roll  = {val=0, vel=0, target=0}
            }
        end
    end
    
    -- 1. Detect Hover (Logic reused from draw)
    local spread = 90
    local start_x = -((hand_size - 1) * spread) / 2
    local mx, my = love.mouse.getPosition()
    local hovered_idx = nil
    
    -- Need to check if over hand area generally first?
    -- Only check if game allows interaction
    if self.game.state == "PLAYING" or self.game.state == "KITTY" or self.game.state == "BIDDING" then
         -- Iterate backwards for Z-order
         for i = hand_size, 1, -1 do
             local card_x = start_x + (i-1) * spread
             local card_y = -60
             if self.selected_discards[i] then card_y = card_y - 20 end
             
             local screen_x = self.center_x + card_x
             local screen_y = (self.height - 100) + card_y
             
             -- Correct Dimensions (from CardRenderer logic)
             -- CardWidth(140) * RenderScale(0.6) * self.card_scale(1.3) ~= 109
             -- CardHeight(190) * RenderScale(0.6) * self.card_scale(1.3) ~= 148
             local w = 109
             local h = 148
             
             -- Hit test
             if mx >= screen_x and mx <= screen_x + w and
                my >= screen_y and my <= screen_y + h then
                 hovered_idx = i
                 break
             end
         end
    end

    
    -- Play sound on hover change
    if hovered_idx ~= self.last_hovered_idx then
        if hovered_idx and gAudioManager then
             gAudioManager:play("CARD_HOVER")
        end
        self.last_hovered_idx = hovered_idx
    end
    -- 2. Update Spring Targets and Integrate
    local stiffness = 600
    local damping = 40  -- Increased from 25 to reduce bounciness
    
    for i=1, hand_size do
        local s = player_springs[i]
        local is_hovering = (i == hovered_idx)
        
        -- Update X position target (for smooth reorganization)
        local target_x = start_x + (i-1) * spread
        s.x.target = target_x
        
        -- Targets
        if is_hovering then
            s.scale.target = 1.25
            
            -- Calculate tilt targets
            local card_x = start_x + (i-1) * spread
            local card_y = -60
            local center_x = self.center_x + card_x
            local center_y = (self.height - 100) + card_y + 55
            
            local diff_x = mx - center_x
            local diff_y = my - center_y
            
            s.pitch.target = (diff_y / 60) * -0.15 
            s.roll.target = (diff_x / 40) * -0.15
        else
            s.scale.target = 1.0
            
            -- Idle animation adds to target? Or just add sine wave in draw?
            -- Let's keep spring target at 0 (flat), and add sine wave on top in Draw.
            -- This separates physics (interaction) from ambient motion.
            s.pitch.target = 0
            s.roll.target = 0
        end
        
        -- Physics Step
        -- Integrate all springs
        local function integrate_spring(spring, dt, k, d)
            local f = -k * (spring.val - spring.target) - d * spring.vel
            spring.vel = spring.vel + f * dt
            spring.val = spring.val + spring.vel * dt
        end
        
        integrate_spring(s.x, dt, stiffness, damping)  -- Position
        integrate_spring(s.scale, dt, stiffness, damping)
        integrate_spring(s.pitch, dt, stiffness, damping)
        integrate_spring(s.roll, dt, stiffness, damping)
    end
end

function TableView:update_all_player_springs(dt)
    -- Update position springs for ALL players (smooth reorganization after card removal)
    if not self.hand_springs then return end
    
    local stiffness = 600
    local damping = 40  -- Increased from 25 to reduce bounciness
    
    for player_idx = 1, 4 do
        local player = self.game.players[player_idx]
        if player then
            local hand_size = #player.hand
            local player_springs = self.hand_springs[player_idx]
            
            if player_springs then
                -- Determine spread for this player
                local is_human = (player_idx == 1)
                local spread = is_human and HAND_SPREAD_HUMAN or HAND_SPREAD_BOT
                local start_x = -((hand_size - 1) * spread) / 2
                
                -- Update spring targets and integrate
                for i = 1, hand_size do
                    if player_springs[i] then
                        local s = player_springs[i]
                        
                        -- Update position target
                        local target_x = start_x + (i-1) * spread
                        s.x.target = target_x
                        
                        -- Integrate position spring
                        local f = -stiffness * (s.x.val - s.x.target) - damping * s.x.vel
                        s.x.vel = s.x.vel + f * dt
                        s.x.val = s.x.val + s.x.vel * dt
                    end
                end
            end
        end
    end
end

function TableView:update(dt)
    self.bg_time = self.bg_time + dt
    self:update_animations(dt)
    self:update_hand_springs(dt)  -- P1 hover/interaction springs
    self:update_all_player_springs(dt)  -- Position springs for all players
    -- self.particles:update(dt)
    if self.bidding_view then self.bidding_view:update(dt) end

    -- Process Action Queue (if not animating and no delay)
    if #self.action_queue > 0 and not self.is_animating and self.animation_delay_timer <= 0 then
        local action = table.remove(self.action_queue, 1)
        if action.type == "UPDATE_TURN" then
            if self.visual_current_player_idx ~= action.player_idx then
                self.visual_current_player_idx = action.player_idx
                self.turn_start_time = love.timer.getTime()
                self.last_player_idx = action.player_idx
                
                -- Turn Alert
                if action.player_idx == 1 and gAudioManager then
                    gAudioManager:play("ALERT")
                end
            end
        end
    end
    
    -- Detect Game State Turn Changes and Queue Them
    if self.game.current_player_idx ~= self.visual_current_player_idx then
         -- Only apply change if NOTHING is happening (idle)
         if not self.is_animating and self.animation_delay_timer <= 0 then
             self.visual_current_player_idx = self.game.current_player_idx
             self.turn_start_time = love.timer.getTime() -- Trigger flash
             self.last_player_idx = self.visual_current_player_idx
             
             -- Turn Alert
             if self.visual_current_player_idx == 1 and gAudioManager then
                 gAudioManager:play("ALERT")
             end
         end
    end
    
    -- Detect Game State Changes (e.g. Kitty Reveal)
    if self.game.state ~= self.last_game_state then
        if self.game.state == "KITTY" then
            if gAudioManager then gAudioManager:play("CARD_FLIP") end
        end
        self.last_game_state = self.game.state
    end
    
    -- Reset Round Over Sound Flag
    if self.game.state ~= "ROUND_OVER" then
        self.round_over_sound_played = false
    end
    
    -- Update Turn Indicators using VISUAL state
    local current_p = self.visual_current_player_idx
    
    for i=1, 4 do
        local target = (current_p == i and (self.game.state == "PLAYING" or self.game.state == "BIDDING")) and 1.0 or 0.0
        if self.game.state == "GAME_OVER" then target = 0 end
        
        -- Smooth Fade
        self.turn_alphas[i] = self.turn_alphas[i] + (target - self.turn_alphas[i]) * 5 * dt
    end
    
    -- Update HUD Score Animation
    local p1 = self.game.players[1] and self.game.players[1].tricks_won_this_round or 0
    local p2 = self.game.players[2] and self.game.players[2].tricks_won_this_round or 0
    local p3 = self.game.players[3] and self.game.players[3].tricks_won_this_round or 0
    local p4 = self.game.players[4] and self.game.players[4].tricks_won_this_round or 0
    
    local us = p1 + p3
    local them = p2 + p4
    
    if us > self.hud_state.us_score then self.hud_state.us_scale.val = 1.5 end
    self.hud_state.us_score = us
    
    if them > self.hud_state.them_score then self.hud_state.them_scale.val = 1.5 end
    self.hud_state.them_score = them
    
    -- Scale Springs
    local k = 150; local d = 10
    local function spring(prop, dt)
         local diff = 1.0 - prop.val
         local force = diff * k
         prop.vel = prop.vel * (1 - d*dt) + force*dt
         prop.val = prop.val + prop.vel * dt
    end
    spring(self.hud_state.us_scale, dt)
    spring(self.hud_state.them_scale, dt)

    -- Update drag position
    if self.dragged_card then
        if not love.mouse.isDown(1) then
            self:on_drag_end()
        end
    end
end

function TableView:on_trick_complete(data)
    -- Spawn particles at winner's location
    local winner_idx = -1
    for i, p in ipairs(self.game.players) do
        if p == data.winner then winner_idx = i; break end
    end
    
    local pos_map = {
        [1] = {x=self.center_x, y=self.height - 100},
        [2] = {x=110, y=self.center_y},
        [3] = {x=self.center_x, y=50},
        [4] = {x=self.width - 110, y=self.center_y}
    }
    
    local pos = pos_map[winner_idx]
    if pos then
         self.particles:emit({
             x = pos.x, 
             y = pos.y, 
             count = 50,
             speed = 300,
             life = 1.5,
             color = {1, 0.8, 0.2}, -- Gold
             gravity = 500
         })
    end
end

function TableView:draw()
    
    -- Clip to game area (don't draw into chat panel)
    love.graphics.setScissor(0, 0, self.width, self.height)
    
    -- Draw Background (Green Felt) - only in game area
    -- Draw Background (Green Felt) - only in game area
    love.graphics.setColor(Config.colors.background)
    
    if self.bg_shader then
        love.graphics.setShader(self.bg_shader)
        self.bg_shader:send("time", self.bg_time)
        self.bg_shader:send("resolution", {self.width, self.height})
    end
    
    -- Draw simple full-screen rect
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    
    love.graphics.setShader() 
    
    self:draw_hud()
    self:draw_tricks_history()
    
    -- Draw Players
    self:draw_player_hand(1, self.center_x, self.height - 100, true) -- Bottom (Human)
    self:draw_player_hand(2, 110, self.center_y, false, -math.pi/2) -- Left (moved in from 50)
    self:draw_player_hand(3, self.center_x, 50, false, 0) -- Top
    self:draw_player_hand(4, self.width - 110, self.center_y, false, math.pi/2) -- Right (moved in from 50)
    
    self:draw_current_trick()
    self:draw_kitty()
    
    
    if self.game.state == "BIDDING" and not self.dealing_in_progress then
        self.bidding_view:draw()
    end
    
    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        self:draw_discard_ui()
    end
    
    if self.game.state == "TRICK_OVER" then
        self:draw_next_trick_btn()
    end
    
    if self.game.state == "ROUND_OVER" then
        self:draw_round_over_modal()
    end
    
    -- Draw Animations (including dealing)
    for _, anim in ipairs(self.animations) do
        if anim.type == "FLY_IN" then
            local progress = anim.t / anim.duration
            -- Smooth easing without overshoot
            local function easeOutCubic(x)
                return 1 - math.pow(1 - x, 3)
            end
            local t = easeOutCubic(progress)
            
            local curr_x = anim.start_pos.x + (anim.end_pos.x - anim.start_pos.x) * t
            local curr_y = anim.start_pos.y + (anim.end_pos.y - anim.start_pos.y) * t
            
            
            -- Simple params - no stretch
            local params = {scale_x = 1, scale_y = 1, rotation = 0, shadow_offset = 10}
            
            -- Draw at interpolated position (already includes the -40 offset)
            -- Draw face down for dealing animation, face up for trick animations
            local face_up = not self.dealing_in_progress
            CardRenderer.draw_card(anim.card, curr_x, curr_y, self.card_scale, face_up, false, params)
        end
    end
    
    -- Skip hint during dealing
    if self.dealing_in_progress then
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.printf("Press SPACE to skip", 0, self.height - 30, self.width, "center")
    end
    
    -- Debug overlay
    if gDebugMode then
        self:draw_debug_overlay()
    end
    
    -- Reset scissor so chat can render
    love.graphics.setScissor()
    
    -- Draw Particles (Global coordinates, on top)
    -- if self.particles then self.particles:draw() end
end

function TableView:draw_debug_overlay()
    -- Get current action type
    local action_type, player_idx = self.game:get_action_request()
    if not action_type then return end
    
    -- Only show during BID or PLAY phases
    if action_type ~= "BID" and action_type ~= "PLAY" then return end
    
    -- Draw probabilities near each bot's position
    local bot_positions = {
        [2] = {x = 120, y = self.center_y - 100},  -- Left bot
        [3] = {x = self.center_x - 150, y = 120},  -- Top bot  
        [4] = {x = self.width - 320, y = self.center_y - 100}  -- Right bot
    }
    
    for p_idx, pos in pairs(bot_positions) do
        local strategy = gStrategies and gStrategies[p_idx]
        if strategy and strategy.is_nn and strategy:is_nn() then
            local top_actions
            local extra_info = ""
            
            if action_type == "PLAY" then
                -- Use filtered probs (only playable cards)
                local player = self.game.players[p_idx]
                local playable = self.game:get_playable_cards(player, self.game.lead_suit)
                if strategy.get_top_actions_filtered and #playable > 0 then
                    top_actions = strategy:get_top_actions_filtered(self.game, p_idx, playable, 5)
                else
                    top_actions = {}
                end
            else
                -- BID phase
                top_actions = strategy:get_top_actions(self.game, p_idx, action_type, 5)
                
                -- Check if Pass is in top 5, if not, add it
                local has_pass = false
                for _, a in ipairs(top_actions) do
                    if a.label == "Pass" then has_pass = true; break end
                end
                if not has_pass and strategy.get_pass_prob then
                    local pass_prob = strategy:get_pass_prob(self.game, p_idx)
                    extra_info = string.format("Pass: %.1f%%", pass_prob * 100)
                end
            end
            
            -- Draw semi-transparent background
            love.graphics.setColor(0, 0, 0, 0.7)
            local box_height = 90 + (extra_info ~= "" and 15 or 0)
            love.graphics.rectangle("fill", pos.x, pos.y, 200, box_height, 5)
            
            -- Draw header
            love.graphics.setColor(1, 0.5, 0)
            love.graphics.print(self.game.players[p_idx].name .. " (" .. action_type .. ")", pos.x + 5, pos.y + 3)
            
            -- Draw top actions
            love.graphics.setColor(1, 1, 1)
            for i, action in ipairs(top_actions) do
                local pct = string.format("%.1f%%", action.prob * 100)
                local text = action.label .. ": " .. pct
                love.graphics.print(text, pos.x + 5, pos.y + 5 + i * 14)
            end
            
            -- Draw extra info (Pass prob if not in top 5)
            if extra_info ~= "" then
                love.graphics.setColor(0.7, 0.7, 0.7)
                love.graphics.print(extra_info, pos.x + 5, pos.y + 5 + (#top_actions + 1) * 14)
            end
        end
    end
end

function TableView:draw_next_trick_btn()
    local btn_w, btn_h = 200, 60
    local btn_x = self.center_x - btn_w/2
    local btn_y = self.height - 180 -- Above hand
    
    love.graphics.setColor(0.2, 0.6, 1.0)
    love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 10)
    
    love.graphics.setColor(1,1,1)
    love.graphics.printf("Next Trick", btn_x, btn_y + 15, btn_w, "center")
    
    self.next_trick_btn_rect = {x=btn_x, y=btn_y, w=btn_w, h=btn_h}
end

function TableView:draw_discard_ui()
    local count = 0
    for _ in pairs(self.selected_discards) do count = count + 1 end
    
    if count == 3 then
        local btn_w, btn_h = 160, 50
        local btn_x = self.center_x - btn_w/2
        local btn_y = self.height - 250
        
        love.graphics.setColor(1, 0.5, 0)
        love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 10)
        
        love.graphics.setColor(1,1,1)
        love.graphics.print("Discard 3 Cards", btn_x + 20, btn_y + 15)
        
        -- Store button rect for click check
        self.discard_btn_rect = {x=btn_x, y=btn_y, w=btn_w, h=btn_h}
    else
        self.discard_btn_rect = nil
        love.graphics.setColor(1,1,1)
        love.graphics.print("Select 3 cards to discard", self.center_x - 100, self.height - 250)
    end
end


function TableView:draw_tricks_history()
    love.graphics.setColor(1, 1, 1, 0.5)
    -- love.graphics.print("Tricks History: " .. #self.game.tricks_history, 10, 70)
end

function TableView:draw_status_info()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("State: " .. self.game.state, 10, 10)
    
    if self.game.trump_suit then
        local suit_names = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="NoTrump"}
        love.graphics.print("Trump: " .. suit_names[self.game.trump_suit], 10, 30)
    end
    
    if self.game.winning_bid then
        love.graphics.print("Contract: " .. tostring(self.game.winning_bid), 10, 50)
    end
    
    -- Last Log
    if #self.game.message_log > 0 then
        love.graphics.print("Log: " .. self.game.message_log[#self.game.message_log], 10, self.height - 20)
    end
end

function TableView:draw_player_hand(player_idx, x, y, is_human, rotation)
    local player = self.game.players[player_idx]
    if not player then return end
    
    
    local hand_size = #player.hand
    
    -- Tighter spread for bots (Fan), Normal for human
    local spread = is_human and HAND_SPREAD_HUMAN or HAND_SPREAD_BOT  
    local start_x = -((hand_size - 1) * spread) / 2
    
    love.graphics.push()
    love.graphics.translate(x, y)
    if rotation then love.graphics.rotate(rotation) end
    
    -- Turn Indicator (Spotlight)
    -- Turn Indicator (Spotlight)
    -- Turn Indicator (Spotlight) removed - Integrating into existing white box below
    
    
    -- Draw Indicator if turn_alpha > 0
    local alpha = self.turn_alphas[player_idx]
    if alpha > 0.01 then
        local w_hand = (hand_size - 1) * spread + 80 * self.card_scale
        local rx = start_x - 40 * self.card_scale - 20
        local ry = -60 - 20
        local rw = w_hand + 40
        local rh = 110 * self.card_scale + 40
        -- Adjust for selected
        if is_human then ry = ry - 20; rh = rh + 20 end
        
        love.graphics.setColor(1, 1, 1, alpha * 0.8) 
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", rx, ry, rw, rh, 15, 15)
        
        -- Glow / Flash Fill
        -- Calculate Pulse based on turn start time (reusing logic)
        local flash_alpha = 0
        if self.visual_current_player_idx == player_idx and self.game.state == "PLAYING" then
             local t = love.timer.getTime()
             local elapsed = t - (self.turn_start_time or 0)
             local flash_dur = 1.0
             local attack_dur = 0.1
             
             local p = 0
             if elapsed < attack_dur then
                 p = elapsed / attack_dur
             else
                 local decay_t = (elapsed - attack_dur) / (flash_dur - attack_dur)
                 p = 1.0 - math.min(1.0, math.max(0.0, decay_t))
                 p = p * p 
             end
             flash_alpha = p
        end
        
        -- Base transparency is alpha * 0.1
        -- Add flash on top
        local final_fill_alpha = (alpha * 0.1) + (flash_alpha * 0.8) -- Flash makes it bright
        
        if flash_alpha > 0.01 then love.graphics.setBlendMode("add") end
        love.graphics.setColor(1, 1, 1, final_fill_alpha)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 15, 15)
        love.graphics.setBlendMode("alpha")
    end

    -- Name Tag
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(player.name, -30, -80)
    
    -- Bid Indicator
    if self.game.state == "BIDDING" and self.game.player_last_action then
        local action = self.game.player_last_action[player_idx]
        if action then
            -- Position: "centre side of hand"
            -- Hand is centered at (x,y) with local coordinates.
            -- Local (0,0) is center of hand arc.
            -- Cards are at y approx -60 to -110?
            -- "Centre side" depends on rotation logic.
            -- Actually, simpler: draw below hand (positive Y in local space) or above (negative Y)?
            -- User said "centre side of the hand".
            -- For P1 (Bottom), "centre side" is probably towards board center (Up/Negative Y)
            -- For P3 (Top), also towards board center (which is "Up" in local space relative to hand? No, rotated 180).
            -- Let's just draw it "above" the hand in local space (negative Y), so it's between hand and center of table.
            
            local y_offset = -120 
            
            love.graphics.setColor(1, 0.8, 0.2) -- Goldish
            local text = ""
            if action.type == "PASS" then
                text = "PASS"
                love.graphics.printf(text, -100, y_offset, 200, "center")
            else
                -- Format: "7 [Symbol] (Score)"
                local suit_sym = "?"
                if action.suit == Suit.SPADES then suit_sym = "♠"
                elseif action.suit == Suit.CLUBS then suit_sym = "♣"
                elseif action.suit == Suit.HEARTS then suit_sym = "♥"
                elseif action.suit == Suit.DIAMONDS then suit_sym = "♦"
                elseif action.suit == Suit.NO_TRUMP then suit_sym = "NT"
                end
                
                text = string.format("%d %s (%d)", action.tricks, suit_sym, action.score)
                
                -- Fallback font for symbol if needed, but let's try standard font first or switch
                -- Using standard print for now, symbols might need fallback font if Lambda doesn't support them.
                -- User mentioned Suit Symbols fallback was added to CardRenderer.
                -- Let's try to just print for now, if symbols fail we switch to fallback.
                
                -- Actually, let's use the fallback font explicitly for the symbol to be safe, 
                -- or ensure the main font has them. Lambda likely doesn't.
                -- So we construct the string carefully.
                
                -- Draw "7 "
                local font = love.graphics.getFont()
                local w7 = font:getWidth(action.tricks .. " ")
                local wSym = 0
                local wScore = font:getWidth(" (" .. action.score .. ")")
                
                -- Approximate width of symbol (assume 20px?)
                -- Better approach: Draw centered.
                
                love.graphics.printf(text, -100, y_offset, 200, "center")
            end
            love.graphics.setColor(1, 1, 1)
        end
    end
    
    -- Cards
    -- Cards
    
    -- Store card rects only for Human/Bottom for clicking
    
    -- Store card rects only for Human/Bottom for clicking
    if is_human then self.hand_card_rects = {} end
    
    local animating_indices = {}
    if self.animations then
        for _, anim in ipairs(self.animations) do
            -- Only skip rendering if animation belongs to THIS player
            if anim.type == "FLY_IN" and anim.target_idx and anim.player_idx == player_idx then
                animating_indices[anim.target_idx] = true
            end
        end
    end
    
    -- Calculate Drag Target Index (Visual Slot)
    local drag_target_idx = nil
    if is_human and self.dragged_card then
        local mx, my = love.mouse.getPosition()
        local local_mx = mx - x
        local initial_idx = math.floor((local_mx - start_x) / spread) + 1
        
        if initial_idx < 1 then initial_idx = 1 end
        if initial_idx > hand_size then initial_idx = hand_size end
        drag_target_idx = initial_idx
        self.drag_target_idx = drag_target_idx
    else
        if is_human then self.drag_target_idx = nil end
    end

    -- Ensure springs exist
    if not self.hand_springs then self.hand_springs = {} end
    
    local deferred_draws = {}

    for i, card in ipairs(player.hand) do
        -- During dealing, only show cards that have landed
        if self.dealing_in_progress and not (self.dealt_cards and self.dealt_cards[card]) then
            -- Skip this card - it hasn't been dealt yet
        else
            local visual_idx = i
            if drag_target_idx then
                local d_idx = self.dragged_card.idx
                if i < d_idx and i >= drag_target_idx then
                    visual_idx = i + 1
                elseif i > d_idx and i <= drag_target_idx then
                    visual_idx = i - 1
                end
            end

            -- Init spring if missing (for ALL players now, not just human)
            local player_springs = self.hand_springs[player_idx]
            if not player_springs then
                self.hand_springs[player_idx] = {}
                player_springs = self.hand_springs[player_idx]
            end
            
            if not player_springs[i] then
                -- Calculate initial position for new spring
                local initial_x = start_x + (visual_idx-1) * spread
                player_springs[i] = {
                    x = {val=initial_x, vel=0, target=initial_x},
                    scale = {val=1, vel=0, target=1},
                    pitch = {val=0, vel=0, target=0},
                    roll = {val=0, vel=0, target=0}
                }
            end
            local spring = player_springs[i]
            
            -- Don't skip cards during animation - let springs handle smooth transitions
            if is_human and self.dragged_card and self.dragged_card.idx == i then
                -- Skip rendered dragged card (user is dragging it)
            else
                -- Calculate card position using interpolated spring value
                local card_x = spring.x.val
                
                local card_y = HAND_Y_OFFSET
                
                -- Fan Logic for Opponents
                local fan_rot = 0
                if not is_human then
                     -- Curve: Center is higher, Edges lower (Positive Y is down)
                     local center = (hand_size + 1) / 2
                     local dist = math.abs(visual_idx - center)
                     local signed_dist = visual_idx - center
                     
                     -- Push up at edges (Inverted Fan)
                     card_y = card_y - (dist * dist) * 1.5 
                     
                     -- Rotate (Left tilts right, Right tilts left)
                     -- User requested "rotate other way"
                     fan_rot = -signed_dist * 0.1 -- radians
                end
                
                if is_human and self.selected_discards[i] then
                    card_y = card_y - 20
                end
                
                -- Highlight current player
                -- Highlight removed (moved to spotlight)
                
                local show_face = is_human or gDebugMode or (self.game.state == "GAME_OVER")
                local params = {scale_x = 1, scale_y = 1, kx = 0, ky = 0, shadow_offset = 5, rotation = fan_rot}
                
                -- PHYSICS & AMBIENT (Human Only)
                local should_defer = false
                
                if is_human and spring then
                    local physics_scale = spring.scale.val
                    local physics_pitch = spring.pitch.val
                    local physics_roll = spring.roll.val
                    
                    -- Add Ambient Motion (Sine Wave)
                    local t = love.timer.getTime()
                    local seed = i * 123.456
                    local ambient_y = 0
                    local ambient_rot = 0
                    
                    if physics_scale < 1.05 then
                        local phase_y = seed
                        local phase_rot = seed * 0.7
                        -- Faster wobble
                        local speed_y = 2.0 + math.sin(seed)*0.5 
                        local speed_rot = 1.5 + math.cos(seed)*0.5 
                        
                        ambient_y = math.sin(t * speed_y + phase_y) * 1.5
                        ambient_rot = math.cos(t * speed_rot + phase_rot) * 0.015
                    end
                    
                    card_y = card_y + ambient_y
                    params.rotation = ambient_rot
                    
                    params.scale_x = physics_scale
                    params.scale_y = physics_scale
                    params.kx = physics_pitch
                    params.ky = physics_roll
                    
                    params.shadow_offset = 5 + (physics_scale > 1 and (physics_scale - 1.0) * 100 or 0)
                    
                     if physics_scale > 1.01 then should_defer = true end
                end
                
                -- Draw Logic
                local draw_op = {card=card, x=card_x - 40, y=card_y, scale=self.card_scale, show=show_face, params=params}
                
                if should_defer then
                    table.insert(deferred_draws, draw_op)
                else
                    CardRenderer.draw_card(card, draw_op.x, draw_op.y, draw_op.scale, draw_op.show, false, draw_op.params)
                end
                
                if is_human then
                     -- Use correct dimensions matching hit-test
                     local w = 109  -- CardWidth(140) * RenderScale(0.6) * card_scale(1.3)
                     local h = 148  -- CardHeight(190) * RenderScale(0.6) * card_scale(1.3)
                     
                     table.insert(self.hand_card_rects, {
                         idx = i,
                         x = card_x - 40,  -- Still need -40 for draw offset
                         y = card_y, 
                         w = w, 
                         h = h,
                         cx = card_x, 
                         cy = card_y + 74,  -- Half of 148
                     })
                end
            end
        end
    end
    
    -- Draw Deferred Cards
    for _, op in ipairs(deferred_draws) do
        CardRenderer.draw_card(op.card, op.x, op.y, op.scale, op.show, true, op.params)
    end
    
    love.graphics.pop()
    
    -- Render Dragged Card Last (Global Coords)
    if self.dragged_card and is_human then
        local mx, my = love.mouse.getPosition()
        local d = self.dragged_card
        local draw_x = mx - d.offset_x 
        local draw_y = my - d.offset_y
        
        local params = {scale_x=1.2, scale_y=1.2, rotation=0, shadow_offset=20}
        CardRenderer.draw_card(d.card, draw_x, draw_y, self.card_scale, true, false, params)
    end
end

function TableView:draw_current_trick()
    love.graphics.push()
    love.graphics.translate(self.center_x, self.center_y)
    
    -- Draw Placemat
    love.graphics.setColor(0, 0, 0, 0.3) -- Semi-transparent black
    local pw, ph = 340, 340 -- Size to cover the cross of cards
    love.graphics.rectangle("fill", -pw/2, -ph/2, pw, ph, 40, 40) -- Rounded corners
    love.graphics.setColor(1, 1, 1, 1)

    local trick = self.game.current_trick
    if not trick or #trick == 0 then 
        love.graphics.pop()
        return 
    end
    
    local positions = {
        [1] = {x=0, y=90},  -- Bottom Played
        [2] = {x=-120, y=0}, -- Left Played
        [3] = {x=0, y=-90}, -- Top Played
        [4] = {x=120, y=0}   -- Right Played
    }
    
    -- Matrix pushed/translated above
    
    -- Filter animating cards
    local animating_set = {}
    if self.animations then
        for _, anim in ipairs(self.animations) do
            if anim.type == "FLY_IN" and anim.card then
                animating_set[anim.card] = true
            end
        end
    end
    
    for _, play in ipairs(trick) do
        if not animating_set[play.card] then
            -- We need to find which "seat" this player belongs to relative to P1
            -- Assuming P1 is always bottom seat (index 1)
            -- Seat Index = play.player index
            -- Visually P1 is bottom. P2 Left, P3 Top, P4 Right.
            
            -- This logic must match the draw_player_hand logic.
            -- We can just find the index of the player in self.game.players
            local p_idx = -1
            for i,p in ipairs(self.game.players) do 
                if p == play.player then p_idx = i; break end
            end
            
            if positions[p_idx] then
                local offset = positions[p_idx]
                local card_x = offset.x - 40 -- Adjust for card width
                local card_y = offset.y - 55 -- Adjust for card height
                
                -- Trick Juice: Idle Float (disabled for recently landed cards)
                local t = love.timer.getTime()
                local seed = p_idx * 123.456 -- Different seed per seat
                
                local phase_y = seed
                local phase_rot = seed * 0.7
                local speed_y = 2.0 + math.sin(seed)*0.5 
                local speed_rot = 1.5 + math.cos(seed)*0.5 
                
                -- Fade in float animation over 0.5 seconds after landing
                local float_strength = 1.0
                if self.card_land_times and self.card_land_times[play.card] then
                    local time_since_land = t - self.card_land_times[play.card]
                    float_strength = math.min(1.0, time_since_land / 0.5)
                end
                
                local ambient_y = math.sin(t * speed_y + phase_y) * 2.0 * float_strength
                local ambient_rot = math.cos(t * speed_rot + phase_rot) * 0.02 * float_strength
                
                card_y = card_y + ambient_y
                
                CardRenderer.draw_card(play.card, card_x, card_y, self.card_scale, true, false, {
                    scale_x = 1, -- Base scale for params
                    scale_y = 1, 
                    shadow_offset = 10, -- Higher shadow for played cards
                    rotation = ambient_rot
                })
            end
        end
    end
    
    love.graphics.pop()
end

function TableView:draw_kitty()
    if self.game.state == "KITTY" then
       -- If P1 is declarer, show kitty text? 
       -- Actually kitty cards are already in hand.
    end
end


function TableView:draw_hud()
    local x, y = 20, 20
    local w, h = 260, 320 -- Compact panel (Fits above hand)
    
    -- Panel BG
    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", x, y, w, h, 12, 12)
    
    -- Border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 12, 12)
    
    local left_pad = x + 15
    local cursor_y = y + 15
    
    -- Data Prep
    local bid = self.game.winning_bid
    local suits = {[0]="CLUBS", [1]="DIAMONDS", [2]="HEARTS", [3]="SPADES", [4]="NO TRUMP"}
    local tricks_bid = 0
    local suit_str = "..."
    local declarer_name = "..."
    local human_team = self.game.players[1].team
    local team_goal = 0
    local role_text = "..."
    local role_color = {1, 1, 1}
    
    if bid then
        tricks_bid = bid.tricks
        suit_str = suits[bid.suit]
        declarer_name = bid.player.name
        
        -- Logic: Declarer is Player Index 1 (User) or 3 (Partner) -> Attacking
        local declarer_idx = bid.player.index
        local is_attacking = (declarer_idx == 1 or declarer_idx == 3)
        
        if is_attacking then
            team_goal = bid.tricks
            role_text = "OFFENSE (ATTACKING)"
            role_color = {0.4, 1, 0.4} -- Green
        else
            -- Extending: if bid is 7, they need 7. We need to win enough to stop them.
            -- Total 10. They need X. We need 10 - X + 1.
            team_goal = 11 - bid.tricks
            role_text = "DEFENSE (STOP THEM)"
            role_color = {1, 0.6, 0.2} -- Orange
        end
    elseif self.game.highest_bid then
        tricks_bid = self.game.highest_bid.tricks
        suit_str = suits[self.game.highest_bid.suit]
        declarer_name = self.game.highest_bid.player.name .. " (Prov)"
        team_goal = "?"
    end

    -- 1. CONTRACT HEADER (Medium)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    
    local header_text = string.format("%d %s", tricks_bid, suit_str)
    if not bid and not self.game.highest_bid then header_text = "BIDDING..." end
    
    love.graphics.printf(header_text, x, cursor_y, w, "center")
    
    cursor_y = cursor_y + 35
    
    -- 2. DETAILS (Small)
    love.graphics.setColor(0.9, 0.9, 0.9)
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end
    
    if bid or self.game.highest_bid then
        love.graphics.print("By " .. declarer_name, left_pad, cursor_y)
        cursor_y = cursor_y + 20
        
        if bid then
            -- Role
            love.graphics.setColor(role_color)
            love.graphics.print(role_text, left_pad, cursor_y)
            cursor_y = cursor_y + 20
            
            -- Goal
            love.graphics.setColor(1, 1, 0.5) -- Yellowish for goal
            love.graphics.print("TEAM GOAL: WIN " .. team_goal, left_pad, cursor_y)
            cursor_y = cursor_y + 30
        else
            cursor_y = cursor_y + 50
        end
    else
        cursor_y = cursor_y + 50
    end
    
    -- 3. TRICKS (Medium Header)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.print("TRICKS", left_pad, cursor_y)
    
    -- Big Numbers (Large) adjacent
    local us = self.hud_state.us_score
    local them = self.hud_state.them_score
    
    cursor_y = cursor_y + 30
    
    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end
    
    -- Won
    love.graphics.setColor(0.4, 1, 0.4)
    love.graphics.print(tostring(us), left_pad + 20, cursor_y - 5)
    
    -- Lost
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.print(tostring(them), left_pad + 140, cursor_y - 5)
    
    -- Labels (Small) underneath
    cursor_y = cursor_y + 45
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end
    
    love.graphics.setColor(0.4, 1, 0.4)
    love.graphics.print("WON", left_pad + 25, cursor_y)
    
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.print("LOST", left_pad + 145, cursor_y)
    
    cursor_y = cursor_y + 35
    
    -- 4. SCORE (Medium Header)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.print("SCORE", left_pad, cursor_y)
    
    -- Score Value (Large)
    local team_a_score = self.game.teams[1] and self.game.teams[1].score or 0
    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end
    
    -- Right align score? Or just offset
    cursor_y = cursor_y + 30
    if team_a_score >= 0 then love.graphics.setColor(1,1,1) else love.graphics.setColor(1, 0.5, 0.5) end
    love.graphics.print(tostring(team_a_score), left_pad + 50, cursor_y - 5)
    
    -- To 500 (Small)
    cursor_y = cursor_y + 45
    love.graphics.setColor(0.6, 0.6, 0.6)
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end
    love.graphics.print("(to 500)", left_pad + 55, cursor_y)
end

function TableView:check_click(x, y)
    -- Pass click to bidding view if active
    if self.game.state == "BIDDING" then
        if self.bidding_view then
            self.bidding_view:check_click(x, y)
        end
        return
    end
    
    -- Trick Over: Next Trick
    if self.game.state == "TRICK_OVER" then
        -- Use the rect stored during draw to ensure sync
        if self.next_trick_btn_rect then
            local b = self.next_trick_btn_rect
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                if gAudioManager then gAudioManager:play("CLICK") end
                self.game:next_trick()
                return true
            end
        end
        return false -- Eat clicks
    end
    
    -- Round Over: Next Round
    if self.game.state == "ROUND_OVER" then
        if self.round_over_btn_rect then
            local b = self.round_over_btn_rect
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                if gAudioManager then 
                    gAudioManager:play("CLICK") 
                    gAudioManager:play("SHUFFLE") 
                end
                self.game:start_new_round()
                return true
            end
        end
        return true -- Eat all clicks
    end
    
    -- Pass click to Kitty Discard UI
    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        -- Check Discard Button
        if self.discard_btn_rect then
            local b = self.discard_btn_rect
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                -- Perform Discard
                local discards = {}
                local indices = {}
                for idx, _ in pairs(self.selected_discards) do table.insert(indices, idx) end
                table.sort(indices, function(a,b) return a > b end) -- Sort desc to remove safely?
                -- Actually we just pass card objects to game logic
                
                local p_hand = self.game.players[1].hand
                for _, idx in ipairs(indices) do
                    table.insert(discards, p_hand[idx])
                end
                
                self.game:player_discard_kitty(1, discards)
                self.selected_discards = {}
                if gAudioManager then gAudioManager:play("CLICK") end
                return true
            end
        end
        
        -- Check Hand Cards
        -- Transform x,y to local space of hand (center_x, height-100)
        local local_x = x - self.center_x
        local local_y = y - (self.height - 100)
        
        -- Check in reverse order (top rendered first)
        if self.hand_card_rects then
            for i = #self.hand_card_rects, 1, -1 do
                local r = self.hand_card_rects[i]
                if local_x >= r.x and local_x <= r.x + r.w and local_y >= r.y and local_y <= r.y + r.h then
                    -- Toggle selection
                    if self.selected_discards[r.idx] then
                        self.selected_discards[r.idx] = nil
                    else
                         -- Check limit
                         local count = 0
                         for _ in pairs(self.selected_discards) do count = count + 1 end
                         if count < 3 then
                             self.selected_discards[r.idx] = true
                         end
                    end
                    return true
                end
            end
        end
    
    
    elseif self.game.state == "PLAYING" and self.game.current_player_idx == 1 then
        -- Play Card / Drag Start
        local local_x = x - self.center_x
        local local_y = y - (self.height - 100)
        
        -- Prevent clicking while animating
        for _, anim in ipairs(self.animations) do
             if anim.target_idx then return true end -- Busy
        end
        
        if self.hand_card_rects then
            for i = #self.hand_card_rects, 1, -1 do
                local r = self.hand_card_rects[i]
                if local_x >= r.x and local_x <= r.x + r.w and local_y >= r.y and local_y <= r.y + r.h then
                    local card = self.game.players[1].hand[r.idx]
                    
                    -- Start Dragging
                    -- Calculate offset: Mouse - Card TopLeft
                    -- Note: r.x = card_x - 40. r.y = card_y.
                    -- Start_x passed to animation is center_x + r.x
                    -- Start_y passed to animation is (height-100) + r.y
                    
                    -- Card TopLeft on screen:
                    local screen_card_x = self.center_x + r.x
                    local screen_card_y = (self.height - 100) + r.y
                    
                    self.dragged_card = {
                        card = card,
                        idx = r.idx,
                        orig_x = r.x,
                        orig_y = r.y,
                        start_mx = x,
                        start_my = y,
                        offset_x = x - screen_card_x,
                        offset_y = y - screen_card_y
                    }
                    return true
                end
            end
        end
    end
    
    return false
end

function TableView:draw_round_over_modal()
    -- Semi-transparent overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    
    -- Modal Box
    local w, h = 500, 400
    local x = self.center_x - w/2
    local y = self.center_y - h/2
    
    love.graphics.setColor(0.1, 0.1, 0.1, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 15, 15)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", x, y, w, h, 15, 15)
    
    -- Determine Result
    local bid = self.game.winning_bid
    if not bid then return end -- Safety
    
    local declarer_team = bid.player.team
    local tricks_won = 0
    -- Count tricks won by declarer team based on self.hud_state
    -- Using hud_state requires it being up to date.
    if declarer_team == self.game.teams[1] then
        tricks_won = self.hud_state.us_score
    else
        tricks_won = self.hud_state.them_score
    end
    
    local success = tricks_won >= bid.tricks
    
    local is_user_team = (declarer_team == self.game.teams[1])
    local result_text = ""
    local color = {1, 1, 1}
    
    if is_user_team then
        if success then
            result_text = "YOU WON!"
            color = {0.4, 1, 0.4} -- Green
        else
            result_text = "YOU LOST!"
            color = {1, 0.4, 0.4} -- Red
        end
    else
        if success then
            result_text = "THEY WON!"
            color = {1, 0.4, 0.4} -- Red (Bad for us)
        else
            result_text = "THEY LOST!"
            color = {0.4, 1, 0.4} -- Green (Good for us)
        end
    end
    

    
    -- Play Sound once per modal appearance
    if not self.round_over_sound_played then
        if gAudioManager then
            if is_user_team then
                 if success then gAudioManager:play("WIN")
                 else gAudioManager:play("LOSE") end
            else
                 -- They won/lost
                 if success then gAudioManager:play("LOSE") -- Bad for us
                 else gAudioManager:play("WIN") end -- Good for us
            end
        end
        self.round_over_sound_played = true
    end
    
    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end
    love.graphics.setColor(color)
    love.graphics.printf(result_text, x, y + 40, w, "center")
    
    -- New Scores
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.setColor(1, 1, 1)
    
    local team_a_score = self.game.teams[1].score
    local team_b_score = self.game.teams[2].score
    
    love.graphics.printf("Team A: " .. team_a_score, x, y + 120, w, "center")
    love.graphics.printf("Team B: " .. team_b_score, x, y + 160, w, "center")
    
    -- Continue Button
    local btn_w, btn_h = 200, 60
    local btn_x = self.center_x - btn_w/2
    local btn_y = self.center_y + 100
    
    love.graphics.setColor(0.2, 0.6, 0.2)
    love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 8, 8)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", btn_x, btn_y, btn_w, btn_h, 8, 8)
    
    love.graphics.printf("Next Round", btn_x, btn_y + 15, btn_w, "center")
    
    -- Store for click detection
    self.round_over_btn_rect = {x = btn_x, y = btn_y, w = btn_w, h = btn_h}
end

function TableView:on_drag_end()
    if not self.dragged_card then return end
    
    -- Play immediate audio feedback
    if gAudioManager then gAudioManager:play("CLICK") end
    
    local d = self.dragged_card
    self.dragged_card = nil
    
    local mx, my = love.mouse.getPosition()
    
    -- Dist from center (Drop Target)
    local dist_center = math.sqrt((mx - self.center_x)^2 + (my - self.center_y)^2)
    
    -- Dist from start (Click vs Drag)
    local dist_drag = math.sqrt((mx - d.start_mx)^2 + (my - d.start_my)^2)
    
    local should_play = false
    local start_scale = 1.2
    
    -- If dropped near center OR clicked (moved very little)
    if dist_center < 150 then
        should_play = true
        start_scale = 1.2
    elseif dist_drag < 10 then
        should_play = true
        start_scale = 1.1 -- Click scale
    end
    
    
    if should_play then
        -- Play Card Logic
        local card = d.card
        local p = self.game.players[1]
        local playable = self.game:get_playable_cards(p, self.game.lead_suit)
        local is_valid = false
        for _, c in ipairs(playable) do if c == card then is_valid = true break end end
        
        if is_valid then
            -- Determine anim start pos
            local start_x, start_y
            if dist_drag < 10 then
                 -- From Hand Pos
                 start_x = self.center_x + d.orig_x
                 start_y = (self.height - 100) + d.orig_y
            else
                 -- From Mouse Pos - Offset
                 start_x = mx - d.offset_x
                 start_y = my - d.offset_y
            end
            
            local start_scale = 1.0
            
            -- Use same position calculation as on_card_played
            local positions = {
                [1] = {x=0, y=90},  -- Bottom Played
            }
            local offset = positions[1]
            local end_x = self.center_x + offset.x - 40
            local end_y = self.center_y + offset.y - 55
            
            -- Track when this card lands
            self.card_land_times = self.card_land_times or {}
            
            
            self:play_card_animation(1, card, start_x, start_y, end_x, end_y, 0.3, d.idx, function()
                self.particles:emit({
                    x = end_x, 
                    y = end_y, 
                    count = 15,
                    speed = 150,
                    color = {1, 1, 0.5} 
                })
                
                -- Mark when card landed
                self.card_land_times[card] = love.timer.getTime()
                
                local success, err = self.game:player_play_card(1, card)
                if success then
                    if gChatLog then gChatLog:add_message("You", {string.format("Plays %s", tostring(card))}, true) end
                end
            end, start_scale) 
            return
        else
            -- Invalid: Shake/Reject?
            print("Invalid Move")
        end
    else
        -- REORDER LOGIC
        -- If dropped in hand area (not center), apply reorder
        if self.drag_target_idx and self.drag_target_idx ~= d.idx then
             local hand = self.game.players[1].hand
             local new_idx = self.drag_target_idx
             
             -- Process reorder
             table.remove(hand, d.idx)
             table.insert(hand, new_idx, d.card)
             -- No animation needed, next draw will show correct order
        end
    end
    
    -- Snap back (handled by next draw)
end

return TableView
