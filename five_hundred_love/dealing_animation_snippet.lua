-- Add after play_card_animation function (around line 124)

function TableView:play_card_animation_delayed(card, start_x, start_y, end_x, end_y, duration, delay, on_complete)
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
                
                self:play_card_animation_delayed(card, deck_x, deck_y, end_x, end_y, 0.2, delay, function()
                    -- Card landed
                    if round == 10 and p_idx == 4 then
                        -- Last card dealt, now deal kitty
                        self:deal_kitty(delay + card_delay)
                    end
                end)
                
                delay = delay + card_delay
            end
        end
    end
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
        local total_width = (hand_size - 1) * 60
        local start_x = -total_width / 2
        local card_x = start_x + (card_idx - 1) * 60
        local card_y = 0
        
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
