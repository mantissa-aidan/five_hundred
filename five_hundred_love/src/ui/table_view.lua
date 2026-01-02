local CardRenderer = require "src.ui.card_renderer"
local Utils = require "src.core.utils"
local BiddingView = require "src.ui.bidding_view"

local TableView = Utils.class("TableView")

function TableView:init(game)
    self.game = game
    self.width = love.graphics.getWidth()
    self.height = love.graphics.getHeight()
    
    -- Layout Config
    self.card_scale = 0.8
    -- Standard positions relative to center
    self.center_x = self.width / 2
    self.center_y = self.height / 2
    
    self.bidding_view = BiddingView.new(game)
    self.selected_discards = {} -- Set of card indices for P1
    self.animations = {} -- List of {type, card, start_pos, end_pos, t, duration}
    
    -- Hook Animation Callback
    game:set_on_card_play(function(p_idx, card)
        self:on_card_played(p_idx, card)
    end)
end

function TableView:on_card_played(p_idx, card)
    if p_idx == 1 then return end -- Handled by local interaction for P1
    
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
    
    -- Target Pos logic from draw_current_trick
    local positions = {
        [2] = {x=-50, y=0}, 
        [3] = {x=0, y=-50}, 
        [4] = {x=50, y=0}   
    }
    local offset = positions[p_idx] or {x=0,y=0}
    local end_x = self.center_x + offset.x - 40 -- center offset? No, positions are relative
    -- Actually draw_current_trick does translate(center). 
    -- So Global End Pos = center_x + offset.x, center_y + offset.y
    -- Note: card is drawn at (x-40, y-55). 
    -- So for center visual, we target (center_x + offset.x, center_y + offset.y - 55)
    
    local anim_end_x = self.center_x + offset.x
    local anim_end_y = self.center_y + offset.y - 55
    
    self:play_card_animation(card, start_x, start_y, anim_end_x, anim_end_y, 0.4, nil)
end

function TableView:play_card_animation(card, start_x, start_y, end_x, end_y, duration, card_idx, on_complete)
    table.insert(self.animations, {
        type = "FLY_IN",
        card = card,
        start_pos = {x=start_x, y=start_y},
        end_pos = {x=end_x, y=end_y},
        t = 0,
        duration = duration,
        target_idx = card_idx,
        on_complete = on_complete
    })
end

function TableView:update_animations(dt)
    for i = #self.animations, 1, -1 do
        local anim = self.animations[i]
        anim.t = anim.t + dt
        if anim.t >= anim.duration then
            if anim.on_complete then anim.on_complete() end
            table.remove(self.animations, i)
        end
    end
end

-- ...

function TableView:check_click(x, y)
    -- ... (Bidding, Trick Over, Kitty blocks are same) ...
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
        return false 
    end
    
    if self.game.state == "KITTY" and self.game.current_player_idx == 1 then
        -- ... (Kitty logic unmodified here, assumed safe) ...
        -- Copy back original kitty handler if needed visually but I will focus on Playing block
        if self.discard_btn_rect then
             -- ... (Same discard btn code)
             local b = self.discard_btn_rect
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                -- Perform Discard
                local discards = {}
                local indices = {}
                for idx, _ in pairs(self.selected_discards) do table.insert(indices, idx) end
                table.sort(indices, function(a,b) return a > b end) 
                
                local p_hand = self.game.players[1].hand
                for _, idx in ipairs(indices) do
                    table.insert(discards, p_hand[idx])
                end
                
                self.game:player_discard_kitty(1, discards)
                self.selected_discards = {}
                return true
            end
        end
        
        -- Hand Check Kitty
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
        -- Play Card
        local local_x = x - self.center_x
        local local_y = y - (self.height - 100)
        
        -- Prevent clicking while animating?
        for _, anim in ipairs(self.animations) do
             if anim.target_idx then return true end -- Busy
        end
        
        if self.hand_card_rects then
            for i = #self.hand_card_rects, 1, -1 do
                local r = self.hand_card_rects[i]
                if local_x >= r.x and local_x <= r.x + r.w and local_y >= r.y and local_y <= r.y + r.h then
                    local card = self.game.players[1].hand[r.idx]
                    
                    -- PRE-VALIDATE move before animating
                    -- Hack: We need to see if it's valid.
                    -- Game:player_play_card does validation but also plays.
                    -- Let's check validity manually or add a 'dry_run' flag?
                    -- Or just duplicate logic:
                    local p = self.game.players[1]
                    local playable = self.game:get_playable_cards(p, self.game.lead_suit)
                    local is_valid = false
                    for _, c in ipairs(playable) do if c == card then is_valid = true break end end
                    
                    if not is_valid then
                        print("Invalid Move: Must follow suit")
                        return true
                    end
                    
                    -- Start Animation
                    -- Global Start: x, y (from rect which is local + offset)
                    -- Rect x,y is relative to (center_x, height-100)
                    local start_x = self.center_x + r.x 
                    local start_y = (self.height - 100) + r.y -- r.y includes pop up logic
                    
                    -- End Pos: Center of table (center_x, center_y + 50) roughly where Bottom card goes
                    local end_x = self.center_x 
                    local end_y = self.center_y + 50
                    
                    self:play_card_animation(card, start_x, start_y, end_x, end_y, 0.4, r.idx, function()
                         local success, err = self.game:player_play_card(1, card)
                         if not success then print("Error playing: "..tostring(err)) end
                    end)
                    
                    return true
                end
            end
        end
    end
    
    return false
end

function TableView:update(dt)
    self:update_animations(dt)
end

function TableView:draw()
    -- Update dimensions dynamically for fullscreen/resize support
    self.width = love.graphics.getWidth()
    self.height = love.graphics.getHeight()
    self.center_x = self.width / 2
    self.center_y = self.height / 2
    
    -- Draw Background (Green Felt)
    love.graphics.clear(0.05, 0.4, 0.1) 
    
    self:draw_status_info()
    self:draw_tricks_history()
    
    -- Draw Players
    self:draw_player_hand(1, self.center_x, self.height - 100, true) -- Bottom (Human)
    self:draw_player_hand(2, 50, self.center_y, false, -math.pi/2) -- Left
    self:draw_player_hand(3, self.center_x, 50, false, 0) -- Top
    self:draw_player_hand(4, self.width - 50, self.center_y, false, math.pi/2) -- Right
    
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
            -- Simple Ease Out Quad
            local t = 1 - (1 - progress) * (1 - progress)
            
            local curr_x = anim.start_pos.x + (anim.end_pos.x - anim.start_pos.x) * t
            local curr_y = anim.start_pos.y + (anim.end_pos.y - anim.start_pos.y) * t
            
            -- Use CardRenderer directly with global coords
            CardRenderer.draw_card(anim.card, curr_x - 40, curr_y, self.card_scale, true, false)
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
    love.graphics.print("Tricks History: " .. #self.game.tricks_history, 10, 70)
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
    
    love.graphics.push()
    love.graphics.translate(x, y)
    if rotation then love.graphics.rotate(rotation) end
    
    -- Name Tag
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(player.name, -30, -80)
    
    -- Cards
    local hand_size = #player.hand
    local spread = 30
    local start_x = -((hand_size - 1) * spread) / 2
    
    -- Store card rects only for Human/Bottom for clicking
    if is_human then self.hand_card_rects = {} end
    
    local mx, my = love.mouse.getPosition()
    
    -- Filter out animating cards from hand (Stub for animation system)
    local animating_indices = {}
    if self.animations then
        for _, anim in ipairs(self.animations) do
            if anim.type == "FLY_IN" and anim.target_idx then
                animating_indices[anim.target_idx] = true
            end
        end
    end
    
    -- Pre-calculate hovered card (iterate backwards to find top-most)
    local hovered_idx = nil
    if is_human then
        for i = #player.hand, 1, -1 do
            if not animating_indices[i] then
                local card_x = start_x + (i-1) * spread
                local card_y = -60
                
                -- Determine if selected (affects Y position for hit check)
                if self.selected_discards[i] then
                    card_y = card_y - 20
                end
                
                local screen_card_x = x + card_x - 40
                local screen_card_y = y + card_y 
                
                if mx >= screen_card_x and mx <= screen_card_x + 80*self.card_scale and
                   my >= screen_card_y and my <= screen_card_y + 110*self.card_scale then
                       hovered_idx = i
                       break -- Found top-most
                end
            end
        end
    end
    
    for i, card in ipairs(player.hand) do
        if not animating_indices[i] then
            local odd_offset = 0
            local card_x = start_x + (i-1) * spread
            local card_y = -60
            
            -- Selection highlight (Pop up)
            if is_human and self.selected_discards[i] then
                card_y = card_y - 20
            end
            
            -- Hover Effect (Only if it's the specific hovered card)
            if is_human and i == hovered_idx then
               card_y = card_y - 15 -- Hover pop
            end
            
            -- Highlight current player
            if self.game.current_player_idx == player_idx and self.game.state == "PLAYING" then
                 love.graphics.setColor(1, 1, 0)
            end
            
            -- Determine if we show face
            local show_face = is_human or (self.game.state == "GAME_OVER")
            
            CardRenderer.draw_card(card, card_x - 40, card_y, self.card_scale, show_face, false)
            
            if is_human then
                 table.insert(self.hand_card_rects, {
                     idx = i,
                     x = card_x - 40,
                     y = card_y, 
                     w = 80 * self.card_scale, 
                     h = 110 * self.card_scale
                 })
            end
        end
    end
    
    love.graphics.pop()
end

function TableView:draw_current_trick()
    local trick = self.game.current_trick
    if not trick or #trick == 0 then return end
    
    local positions = {
        [1] = {x=0, y=50},  -- Bottom Played
        [2] = {x=-50, y=0}, -- Left Played
        [3] = {x=0, y=-50}, -- Top Played
        [4] = {x=50, y=0}   -- Right Played
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
                local pos = positions[p_idx]
                CardRenderer.draw_card(play.card, pos.x - 40, pos.y - 55, self.card_scale, true, false)
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
        -- Play Card
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
                    
                    -- PRE-VALIDATE move before animating
                    local p = self.game.players[1]
                    local playable = self.game:get_playable_cards(p, self.game.lead_suit)
                    local is_valid = false
                    for _, c in ipairs(playable) do if c == card then is_valid = true break end end
                    
                    if not is_valid then
                        -- Optional: Shake animation or sound?
                        print("Invalid Move: Must follow suit")
                        return true
                    end
                    
                    -- Start Animation
                    local start_x = self.center_x + r.x 
                    local start_y = (self.height - 100) + r.y
                    
                    -- End Pos: Center of table
                    local end_x = self.center_x 
                    local end_y = self.center_y + 50 - 55
                    
                    self:play_card_animation(card, start_x, start_y, end_x, end_y, 0.4, r.idx, function()
                         local success, err = self.game:player_play_card(1, card)
                         if not success then print("Error playing: "..tostring(err)) end
                    end)
                    
                    return true
                end
            end
        end
    end
    
    return false
end

return TableView
