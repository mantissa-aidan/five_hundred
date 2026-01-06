local CardRenderer = require "src.ui.card_renderer"
local Utils = require "src.core.utils"
local BiddingView = require "src.ui.bidding_view"
local Config = require "src.config"
local Card = require "src.core.card"
local Suit = Card.Suit
local AnimationManager = require "src.ui.animation_manager"
local HUDView = require "src.ui.hud_view"
local TrickView = require "src.ui.trick_view"
local HandView = require "src.ui.hand_view"

local TableView = Utils.class("TableView")
local ParticleSystem = require "src.ui.particle_system"
local Button = require "src.ui.button"

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

    -- Animation Manager (extracted component)
    self.anim = AnimationManager.new()

    self.particles = ParticleSystem.new()
    self.dragged_card = nil
    self.drag_offset = {x=0, y=0}
    
    -- Hook Animation Callback
    game:set_on_card_play(function(p_idx, card)
        self:on_card_played(p_idx, card)
    end)
    
    -- UI Polish State
    self.turn_alphas = {0,0,0,0} -- Alpha for each player's turn indicator

    -- HUD View (extracted component)
    self.hud_view = HUDView.new(game, self.width, self.height)

    -- Trick View (extracted component)
    self.trick_view = TrickView.new(game, self.center_x, self.center_y, self.card_scale, self.anim)

    -- Hand View (extracted component - manages spring physics)
    self.hand_view = HandView.new(game, self.card_scale, self.center_x, self.height, self.anim)
    
    -- UI Buttons
    self.next_trick_btn = Button.new(0, 0, 200, 60, "Next Trick", "action", function()
        self.game:next_trick()
    end)
    self.next_trick_btn.color = {0.2, 0.6, 1.0}
    
    self.discard_btn = Button.new(0, 0, 160, 50, "Discard 3 Cards", "normal", function()
        local to_discard = {}
        for idx, _ in pairs(self.selected_discards) do
             local card = self.game.players[1].hand[idx]
             if card then
                 table.insert(to_discard, card)
             end
        end
        local success, err = self.game:player_discard_kitty(1, to_discard)
        if success then
             print("[TableView] Discard successful, clearing selection")
             self.selected_discards = {}
             if gChatLog then gChatLog:add_message("You", {"Discard complete"}, true) end
        else
             print("Discard Failed: " .. tostring(err))
        end
    end)
    self.discard_btn.color = {1, 0.5, 0}

    -- Background Shader Setup
    self.bg_shader = love.graphics.newShader("src/shaders/background.glsl")
    print("[TableView] Shader loaded:", self.bg_shader)
    self.bg_time = 0

    -- Turn Animation State
    self.last_player_idx = nil
    self.visual_current_player_idx = game.current_player_idx -- Decoupled visual state
    self.turn_start_time = 0
    self.last_game_state = "WAITING"
    
    -- Visual Action Queue (for sequencing events)
    self.action_queue = {}
end

function TableView:resize(w, h)
    -- Recalculate dimensions
    self.width = w
    self.height = h
    self.center_x = self.width / 2
    self.center_y = self.height / 2

    -- Resize child views
    if self.bidding_view then
        self.bidding_view:resize(self.width, self.height)
    end
    if self.hud_view then
        self.hud_view:resize(self.width, self.height)
    end
    if self.trick_view then
        self.trick_view:resize(self.center_x, self.center_y)
    end
    if self.hand_view then
        self.hand_view:resize(self.center_x, self.height)
    end
    
    -- Update Button Positions
    if self.next_trick_btn then
        self.next_trick_btn.x = self.center_x - self.next_trick_btn.w/2
        self.next_trick_btn.y = self.height - 180
    end
    
    if self.discard_btn then
        self.discard_btn.x = self.center_x - self.discard_btn.w/2
        self.discard_btn.y = self.height - 250
    end
end

function TableView:on_card_played(p_idx, card)
    if p_idx == 1 then
        if gAudioManager then gAudioManager:play("CARD_SLIDE") end
        return
    end -- P1 cards don't animate

    -- Determine start position based on player index
    local start_x, start_y
    if p_idx == 2 then start_x, start_y = 50, self.center_y
    elseif p_idx == 3 then start_x, start_y = self.center_x, 50
    elseif p_idx == 4 then start_x, start_y = self.width - 50, self.center_y
    else return end

    -- Calculate end position (matches draw_current_trick)
    local positions = {
        [1] = {x=0, y=90},
        [2] = {x=-120, y=0},
        [3] = {x=0, y=-90},
        [4] = {x=120, y=0}
    }
    local offset = positions[p_idx]
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

    -- Queue animation via AnimationManager
    local anim = self.anim
    anim:queue({
        card = card,
        player_idx = p_idx,
        start_x = start_x,
        start_y = start_y,
        end_x = end_x,
        end_y = end_y,
        duration = 0.3,
        card_idx = card_idx,
        on_complete = function()
            anim:mark_card_dealt(card)
        end
    })

    -- Queue turn update action
    table.insert(self.action_queue, {
        type = "UPDATE_TURN",
        player_idx = self.game.current_player_idx
    })
end

-- Legacy wrapper for play_card_animation (used by on_drag_end)
function TableView:play_card_animation(p_idx, card, start_x, start_y, end_x, end_y, duration, card_idx, on_complete, start_scale)
    local anim = self.anim
    anim:queue({
        card = card,
        player_idx = p_idx,
        start_x = start_x,
        start_y = start_y,
        end_x = end_x,
        end_y = end_y,
        duration = duration,
        card_idx = card_idx,
        start_scale = start_scale,
        on_complete = on_complete
    })

    table.insert(self.action_queue, {
        type = "UPDATE_TURN",
        player_idx = self.game.current_player_idx
    })
end

function TableView:animate_deal()
    local anim = self.anim
    anim:start_dealing()

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
                local end_x, end_y, end_rot = self:get_deal_target_position(p_idx, round)
                end_rot = end_rot or 0

                print(string.format("[DEAL] Queueing card %d for P%d: %s -> (%.1f, %.1f) rot=%.2f",
                    round, p_idx, tostring(card), end_x, end_y, end_rot))

                -- Capture references for callback
                local card_ref = card
                local is_last_hand_card = (round == 10 and p_idx == 4)

                anim:queue_delayed({
                    card = card,
                    start_x = deck_x,
                    start_y = deck_y,
                    end_x = end_x,
                    end_y = end_y,
                    duration = 0.2,
                    delay = delay,
                    start_scale = 1.0,
                    start_rot = 0,
                    end_rot = end_rot,
                    on_complete = function()
                        anim:mark_card_dealt(card_ref)
                        if is_last_hand_card then
                            self:deal_kitty(delay)
                        end
                    end
                })

                delay = delay + card_delay
            end
        end
    end

    print(string.format("[DEAL] Queued animations"))
end

function TableView:deal_kitty(start_delay)
    local anim = self.anim
    local deck_x = self.center_x
    local deck_y = self.center_y
    local card_delay = 0.05

    -- Deal 3 kitty cards to center
    for i = 1, 3 do
        if self.game.kitty and self.game.kitty[i] then
            local card = self.game.kitty[i]
            local end_x = deck_x + (i - 2) * 30 - 40
            local end_y = deck_y - 100

            local delay = start_delay + (i - 1) * card_delay
            local is_last = (i == 3)

            anim:queue_delayed({
                card = card,
                start_x = deck_x,
                start_y = deck_y,
                end_x = end_x,
                end_y = end_y,
                duration = 0.2,
                delay = delay,
                on_complete = function()
                    if is_last then
                        anim:finish_dealing()
                    end
                end
            })
        end
    end
end

function TableView:get_deal_target_position(p_idx, card_idx)
    -- Delegate to HandView for consistency
    return self.hand_view:get_deal_target_position(p_idx, card_idx, self.center_x, self.height, 10)
end

function TableView:skip_dealing_animation()
    self.anim:skip_all()
end

function TableView:update(dt)
    self.bg_time = self.bg_time + dt
    self.anim:update(dt)

    -- Update hand springs (via HandView)
    self.hand_view:update(dt, self.dragged_card)
    -- Keep reference to springs for draw compatibility
    self.hand_springs = self.hand_view.springs
    self.last_hovered_idx = self.hand_view.last_hovered_idx

    -- self.particles:update(dt)
    if self.bidding_view then 
        -- Always update bidding view so it can animate in/out
        self.bidding_view:update(dt, self.anim:is_dealing()) 
    end

    if self.next_trick_btn and self.game.state == "TRICK_OVER" then
        self.next_trick_btn:update(dt)
    end

    if self.discard_btn and self.game.state == "KITTY" and self.game.kitty_owner_idx == 1 then
        self.discard_btn:update(dt)
    end

    -- Process Action Queue (if not animating and no delay)
    local is_idle = not self.anim:is_busy() and not self.anim:in_delay()
    if #self.action_queue > 0 and is_idle then
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
         if is_idle then
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

    -- Update Turn Indicators using VISUAL state
    local current_p = self.visual_current_player_idx

    for i=1, 4 do
        local target = (current_p == i and (self.game.state == "PLAYING" or self.game.state == "BIDDING")) and 1.0 or 0.0
        if self.game.state == "GAME_OVER" then target = 0 end

        -- Smooth Fade
        self.turn_alphas[i] = self.turn_alphas[i] + (target - self.turn_alphas[i]) * 5 * dt
    end

    -- Update HUD (via HUDView)
    if self.hud_view then
        self.hud_view:update(dt)
    end

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

    -- Draw HUD (via HUDView)
    if self.hud_view then
        self.hud_view:draw()
    end
    self:draw_tricks_history()
    
    -- Draw Players
    self:draw_player_hand(1, self.center_x, self.height - 100, true) -- Bottom (Human)
    self:draw_player_hand(2, 110, self.center_y, false, -math.pi/2) -- Left (moved in from 50)
    self:draw_player_hand(3, self.center_x, 50, false, 0) -- Top
    self:draw_player_hand(4, self.width - 110, self.center_y, false, math.pi/2) -- Right (moved in from 50)

    -- Draw current trick (via TrickView)
    if self.trick_view then
        self.trick_view:draw()
    end
    self:draw_kitty()
    
    
    if self.bidding_view and (self.game.state == "BIDDING" or self.bidding_view:is_animating()) and not self.anim:is_dealing() then
        self.bidding_view:draw()
    end

    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        self:draw_discard_ui()
    end

    if self.game.state == "TRICK_OVER" then
        self:draw_next_trick_btn()
    end

    if self.game.state == "ROUND_OVER" and self.hud_view then
        self.hud_view:draw_round_over_modal()
    end

    -- Draw Animations (via AnimationManager)
    local is_dealing = self.anim:is_dealing()
    for _, anim in ipairs(self.anim:get_animations()) do
        if anim.type == "FLY_IN" then
            local progress = anim.t / anim.duration
            local function easeOutCubic(x)
                return 1 - math.pow(1 - x, 3)
            end
            local t = easeOutCubic(progress)

            local curr_x = anim.start_pos.x + (anim.end_pos.x - anim.start_pos.x) * t
            local curr_y = anim.start_pos.y + (anim.end_pos.y - anim.start_pos.y) * t

            local s_rot = anim.start_rot or 0
            local e_rot = anim.end_rot or 0
            local curr_rot = s_rot + (e_rot - s_rot) * t

            local params = {scale_x = 1, scale_y = 1, rotation = curr_rot, shadow_offset = 10}
            local face_up = not is_dealing
            CardRenderer.draw_card(anim.card, curr_x, curr_y, self.card_scale, face_up, false, params)
        end
    end

    -- Skip hint during dealing
    if is_dealing then
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
    if self.next_trick_btn then
        self.next_trick_btn:draw()
    end
end

function TableView:draw_discard_ui()
    local count = 0
    for _ in pairs(self.selected_discards) do count = count + 1 end
    
    if count == 3 then
        if self.discard_btn then
            self.discard_btn:draw()
        end
    else
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
    local spread = is_human and HandView.SPREAD_HUMAN or HandView.SPREAD_BOT
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

    -- Get animating cards from AnimationManager
    local animating_cards = self.anim:get_animating_cards()

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
    local is_dealing = self.anim:is_dealing()

    for i, card in ipairs(player.hand) do
        -- Skip drawing if card is currently animating (to avoid duplicates)
        -- Or if dealing and not landed
        local dealing_skip = is_dealing and not self.anim:is_card_dealt(card)
        
        if dealing_skip or animating_cards[card] then
            -- Skip this card
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
                    y = {val=0, vel=0, target=0},
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

                local card_base_y = HandView.Y_OFFSET
                if spring.y then card_base_y = card_base_y + spring.y.val end
                local card_y = card_base_y
                
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
                
                if is_human and self.selected_discards[i] and self.game.state == "KITTY" then
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

    -- Sync card rects to HandView for hover detection
    if is_human and self.hand_view then
        self.hand_view.card_rects = self.hand_card_rects
    end
end

function TableView:draw_kitty()
    if self.game.state == "KITTY" then
       -- If P1 is declarer, show kitty text? 
       -- Actually kitty cards are already in hand.
    end
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
        if self.next_trick_btn then
             -- Check click against button bounds (handled by button Logic but needs triggering)
             -- Button updates hovered state.
             if x >= self.next_trick_btn.x and x <= self.next_trick_btn.x + self.next_trick_btn.w and
                y >= self.next_trick_btn.y and y <= self.next_trick_btn.y + self.next_trick_btn.h then
                 return self.next_trick_btn:click()
             end
        end
        return false
    end
    
    -- Round Over: Next Round
    if self.game.state == "ROUND_OVER" then
        local b = self.hud_view and self.hud_view:get_round_over_btn_rect()
        if b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if gAudioManager then
                gAudioManager:play("SHUFFLE")
            end
            self.game:start_new_round()
            return true
        end
        return true -- Eat all clicks
    end
    
    -- Pass click to Kitty Discard UI
    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        -- Check Discard Button
        if self.discard_btn then
             local btn = self.discard_btn
             local count = 0
             for _ in pairs(self.selected_discards) do count = count + 1 end
             
             if count == 3 then
                 if x >= btn.x and x <= btn.x + btn.w and
                    y >= btn.y and y <= btn.y + btn.h then
                     return btn:click()
                 end
             end
        end
    -- Check Hand Cards (Selection)
    local local_x = x - self.center_x
    local local_y = y - (self.height - 100)
    
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
    return true -- Consume clicks in KITTY
end -- End KITTY

if self.game.state == "PLAYING" and self.game.current_player_idx == 1 then
        -- Play Card / Drag Start
        local local_x = x - self.center_x
        local local_y = y - (self.height - 100)

        -- Prevent clicking while animating
        if self.anim:is_busy() then return true end
        
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
                    
                    -- Play sound when starting to drag
                    if gAudioManager then
                        gAudioManager:play("CARD_HOVER")
                    end
                    
                    return true
                end
            end
        end
    end
    
    return false
end

function TableView:on_drag_end()
    if not self.dragged_card then return end
    
    -- Play immediate audio feedback
    if gAudioManager then gAudioManager:play("CARD_HOVER") end
    
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

            local anim = self.anim
            self:play_card_animation(1, card, start_x, start_y, end_x, end_y, 0.3, d.idx, function()
                self.particles:emit({
                    x = end_x,
                    y = end_y,
                    count = 15,
                    speed = 150,
                    color = {1, 1, 0.5}
                })

                -- Mark when card landed
                anim:mark_card_dealt(card)

                local success, err = self.game:player_play_card(1, card)
                if success then
                    if gChatLog then gChatLog:add_message("You", {string.format("Plays %s", tostring(card))}, true) end
                end
            end, start_scale) 
            return
        else
            -- Invalid: Shake/Reject?
            print("Invalid Move")
            
            -- Smooth Snap Back
             local p_springs = self.hand_springs[1]
             if p_springs and p_springs[d.idx] then
                  local s = p_springs[d.idx]
                  s.x.val = (mx - self.center_x - d.offset_x) + 40
                  s.x.vel = 0

                  local hand_orig_y = self.height - 100
                  local base_y = HandView.Y_OFFSET
                   if self.selected_discards[d.idx] then base_y = base_y - 20 end
                   
                  local visual_y = my - hand_orig_y - d.offset_y
                  if s.y then
                       s.y.val = visual_y - base_y
                       s.y.vel = 0
                  end
             end
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
             
             -- Apply smooth snap from drop position
             local p_springs = self.hand_springs[1]
             if p_springs and p_springs[new_idx] then
                  local s = p_springs[new_idx]
                  -- Set spring to drop position so it slides to target
                  -- X: global_mx - center_x - offset_x + 40
                  s.x.val = (mx - self.center_x - d.offset_x) + 40
                  s.x.vel = 0

                  -- Y: global_my - hand_origin - offset_y - base_y
                  local hand_orig_y = self.height - 100
                  local base_y = HandView.Y_OFFSET
                  if self.selected_discards[new_idx] then base_y = base_y - 20 end
                  
                  local visual_y = my - hand_orig_y - d.offset_y
                  if s.y then
                       s.y.val = visual_y - base_y
                       s.y.vel = 0
                  end
             end
        end
    end
    
    -- Snap back (handled by next draw)
end

return TableView
