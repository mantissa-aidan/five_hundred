local CardRenderer = require "src.ui.card_renderer"
local Utils = require "src.core.utils"
local BiddingView = require "src.ui.bidding_view"
local Config = require "src.config"
local Card = require "src.core.card"
local Suit = Card.Suit

local TableView = Utils.class("TableView")
local ParticleSystem = require "src.ui.particle_system"

function TableView:init(game)
    self.game = game
    
    -- Layout Config - table takes left portion, leaving space for chat on right
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
    self.selected_discards = {} -- Set of card indices for P1
    self.animations = {} -- List of {type, card, start_pos, end_pos, t, duration}
    self.animations = {} -- List of {type, card, start_pos, end_pos, t, duration}
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
    self.animation_delay_duration = 0.3 -- Pause after each animation
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
    if p_idx == 1 then return end -- P1 cards don't animate
    
    -- Determine start position based on player index
    -- P2 (Left): 50, center_y
    -- P3 (Top): center_x, 50
    -- P4 (Right): width-50, center_y
    local start_x, start_y
    if p_idx == 2 then start_x, start_y = 50, self.center_y
    elseif p_idx == 3 then start_x, start_y = self.center_x, 50
    elseif p_idx == 4 then start_x, start_y = self.width - 50, self.center_y
    else return end
    
    -- End Pos: Center + offset matching P1 layout?
    -- Actually center is fine. draw_current_trick has offsets.
    -- Let's fly to strict center for now or match target pos.
    
    -- Target Pos logic from draw_current_trick (MUST MATCH EXACTLY!)
    local positions = {
        [1] = {x=0, y=90},  -- Bottom Played
        [2] = {x=-120, y=0}, -- Left Played
        [3] = {x=0, y=-90}, -- Top Played
        [4] = {x=120, y=0}   -- Right Played
    }
    local offset = positions[p_idx] or {x=0,y=0}
    
    -- Match the exact position from draw_current_trick
    -- draw_current_trick does: translate(center), then draws at (offset.x - 40, offset.y - 55)
    -- So absolute position is: center_x + offset.x - 40, center_y + offset.y - 55
    local anim_end_x = self.center_x + offset.x - 40
    local anim_end_y = self.center_y + offset.y - 55
    
    print(string.format("[ANIM] P%d: center=(%.1f,%.1f) offset=(%.1f,%.1f) -> target=(%.1f, %.1f)", 
        p_idx, self.center_x, self.center_y, offset.x, offset.y, anim_end_x, anim_end_y))
    
    -- Track when this card lands to disable float initially
    self.card_land_times = self.card_land_times or {}
    
    self:play_card_animation(card, start_x, start_y, anim_end_x, anim_end_y, 0.4, nil, function()
        -- Mark when card landed
        self.card_land_times[card] = love.timer.getTime()
    end)
end

function TableView:play_card_animation(card, start_x, start_y, end_x, end_y, duration, card_idx, on_complete, start_scale)
    self.is_animating = true -- Block game updates
    
    table.insert(self.animations, {
        type = "FLY_IN",
        card = card,
        start_pos = {x=start_x, y=start_y},
        end_pos = {x=end_x, y=end_y},
        t = 0,
        duration = duration,
        target_idx = card_idx,
        on_complete = on_complete,
        start_scale = start_scale or 1.0
    })
end

function TableView:update_animations(dt)
    -- Update active animations
    for i = #self.animations, 1, -1 do
        local anim = self.animations[i]
        anim.t = anim.t + dt
        if anim.t >= anim.duration then
            if anim.on_complete then anim.on_complete() end
            table.remove(self.animations, i)
            
            -- Start delay timer after animation completes
            if #self.animations == 0 then
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

-- ...



function TableView:update_hand_springs(dt)
    if not self.hand_springs then self.hand_springs = {} end
    
    local player = self.game.players[1]
    if not player then return end
    
    local hand_size = #player.hand
    
    -- Ensure spring state exists
    for i=1, hand_size do
        if not self.hand_springs[i] then
            self.hand_springs[i] = {
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
             
             local screen_x = self.center_x + card_x - 40
             local screen_y = (self.height - 100) + card_y
             
             -- Hit test
             if mx >= screen_x and mx <= screen_x + 80*self.card_scale and
                my >= screen_y and my <= screen_y + 110*self.card_scale then
                 hovered_idx = i
                 break
             end
         end
    end
    
    -- 2. Update Springs
    local stiffness = 600
    local damping = 25
    
    for i=1, hand_size do
        local s = self.hand_springs[i]
        local is_hovering = (i == hovered_idx)
        
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
        local function update_spring(prop, dt)
            local diff = prop.target - prop.val
            local force = diff * stiffness
            prop.vel = prop.vel * (1 - damping * dt) -- Damping
            prop.vel = prop.vel + force * dt
            prop.val = prop.val + prop.vel * dt
        end
        
        update_spring(s.scale, dt)
        update_spring(s.pitch, dt)
        update_spring(s.roll, dt)
    end
end

function TableView:update(dt)
    self:update_animations(dt)
    self:update_hand_springs(dt)
    self.particles:update(dt)
    if self.bidding_view then self.bidding_view:update(dt) end
    
    -- Update Turn Indicators
    local current_p = self.game.current_player_idx
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
    love.graphics.rectangle("fill", 0, 0, self.width, self.height) 
    
    self:draw_hud()
    self:draw_tricks_history()
    
    -- Draw Players
    self:draw_player_hand(1, self.center_x, self.height - 100, true) -- Bottom (Human)
    self:draw_player_hand(2, 110, self.center_y, false, -math.pi/2) -- Left (moved in from 50)
    self:draw_player_hand(3, self.center_x, 50, false, 0) -- Top
    self:draw_player_hand(4, self.width - 110, self.center_y, false, math.pi/2) -- Right (moved in from 50)
    
    self:draw_current_trick()
    self:draw_kitty()
    
    if self.game.state == "BIDDING" then
        self.bidding_view:draw()
    end
    
    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        self:draw_discard_ui()
    end
    
    if self.game.state == "TRICK_OVER" then
        self:draw_next_trick_btn()
    end
    
    -- Draw Animations
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
            CardRenderer.draw_card(anim.card, curr_x, curr_y, self.card_scale, true, false, params)
        end
    end
    
    -- Debug overlay
    if gDebugMode then
        self:draw_debug_overlay()
    end
    
    -- Reset scissor so chat can render
    love.graphics.setScissor()
    
    -- Draw Particles (Global coordinates, on top)
    self.particles:draw()
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
    local spread = is_human and 90 or 30  
    local start_x = -((hand_size - 1) * spread) / 2
    
    love.graphics.push()
    love.graphics.translate(x, y)
    if rotation then love.graphics.rotate(rotation) end
    
    
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
        
        -- Glow
        love.graphics.setColor(1, 1, 1, alpha * 0.1)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 15, 15)
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
            if anim.type == "FLY_IN" and anim.target_idx then
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
        -- Init spring if missing
        local spring = nil
        if is_human then
            if not self.hand_springs[i] then
                 self.hand_springs[i] = {
                    scale = {val=1, vel=0, target=1},
                    pitch = {val=0, vel=0, target=0},
                    roll  = {val=0, vel=0, target=0}
                }
            end
            spring = self.hand_springs[i]
        end
        
        if not animating_indices[i] then
            if is_human and self.dragged_card and self.dragged_card.idx == i then
                -- Skip rendered dragged card
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
                
                local card_x = start_x + (visual_idx-1) * spread
                local card_y = -60
                
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
                if self.game.current_player_idx == player_idx and self.game.state == "PLAYING" then
                     love.graphics.setColor(1, 1, 0)
                end
                
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
                     table.insert(self.hand_card_rects, {
                         idx = i,
                         x = card_x - 40,
                         y = card_y, 
                         w = 80 * self.card_scale, 
                         h = 110 * self.card_scale,
                         cx = card_x, 
                         cy = card_y + 55,
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
    local trick = self.game.current_trick
    if not trick or #trick == 0 then return end
    
    local positions = {
        [1] = {x=0, y=90},  -- Bottom Played
        [2] = {x=-120, y=0}, -- Left Played
        [3] = {x=0, y=-90}, -- Top Played
        [4] = {x=120, y=0}   -- Right Played
    }
    
    love.graphics.push()
    love.graphics.translate(self.center_x, self.center_y)
    
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
                
                -- Debug: print actual draw position (in local coords after translate)
                local abs_x = self.center_x + card_x
                local abs_y = self.center_y + card_y
                if not animating_set[play.card] then
                    print(string.format("[TRICK] P%d: center=(%.1f,%.1f) offset=(%.1f,%.1f) card_xy=(%.1f,%.1f) -> abs=(%.1f, %.1f)", 
                        p_idx, self.center_x, self.center_y, offset.x, offset.y, card_x, card_y, abs_x, abs_y))
                end
                
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
    local padding = 10
    local x, y = 10, 10
    local w, h = 150, 120  -- Increased height for score
    
    -- Panel BG
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    
    -- Border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)
    
    -- TRUMP INFO
    local trump_suit = self.game.trump_suit or "None"
    local bid = self.game.winning_bid
    local contract_str = "Bidding..."
    
    -- Suit Mapping
    local suits = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="NoTrump"}
    local function format_bid(tricks, suit_idx)
         return string.format("%d %s", tricks, suits[suit_idx] or "?")
    end
    
    if self.game.state == "BIDDING" then
        local highest = self.game.highest_bid
        if highest then
             contract_str = "Bid: " .. format_bid(highest.tricks, highest.suit)
        else
             contract_str = "Bidding"
        end
    elseif bid then
        contract_str = "Contract: " .. format_bid(bid.tricks, bid.suit)
        trump_suit = suits[bid.suit] or "None"
    end
    
    -- Contract Text
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.small then
        love.graphics.setFont(gFonts.small)
    end
    love.graphics.print(contract_str, x + 10, y + 10)
    
    -- TRICKS THIS ROUND
    local us = self.hud_state.us_score
    local them = self.hud_state.them_score
    
    love.graphics.print("Tricks:", x + 10, y + 35)
    
    local s_us = self.hud_state.us_scale.val
    local s_them = self.hud_state.them_scale.val
    
    -- Draw Tricks with Pop
    love.graphics.push()
    love.graphics.translate(x + 70, y + 42)
    love.graphics.scale(s_us, s_us)
    love.graphics.setColor(0.5, 1, 0.5) -- Greenish for Us
    love.graphics.print(tostring(us), -5, -7)
    love.graphics.pop()
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("-", x + 85, y + 35)
    
    love.graphics.push()
    love.graphics.translate(x + 100, y + 42)
    love.graphics.scale(s_them, s_them)
    love.graphics.setColor(1, 0.5, 0.5) -- Reddish for Them
    love.graphics.print(tostring(them), -5, -7)
    love.graphics.pop()
    
    -- TOTAL SCORE
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Score:", x + 10, y + 60)
    
    local team_a_score = self.game.teams[1] and self.game.teams[1].score or 0
    local team_b_score = self.game.teams[2] and self.game.teams[2].score or 0
    
    love.graphics.setColor(0.5, 1, 0.5)
    love.graphics.print(tostring(team_a_score), x + 70, y + 60)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("-", x + 85, y + 60)
    
    love.graphics.setColor(1, 0.5, 0.5)
    love.graphics.print(tostring(team_b_score), x + 100, y + 60)
    
    -- Goal indicator
    love.graphics.setColor(0.7, 0.7, 0.7)
    if gFonts and gFonts.small then
        love.graphics.setFont(gFonts.small)
    end
    love.graphics.print("(to 500)", x + 10, y + 85)
end

function TableView:check_click(x, y)
    if self.game.state == "BIDDING" then
        return self.bidding_view:check_click(x, y)
    end
    
    if self.game.state == "TRICK_OVER" then
        if self.next_trick_btn_rect then
            local b = self.next_trick_btn_rect
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self.game:next_trick()
                return true
            end
        end
        return false -- Eat clicks
    end
    
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

function TableView:on_drag_end()
    if not self.dragged_card then return end
    
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
                 -- Animation to center
            local start_x = mx - d.offset_x
            local start_y = my - d.offset_y
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
            
            self:play_card_animation(card, start_x, start_y, end_x, end_y, 0.3, d.idx, function()
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
        end
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
