local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local BidModule = require "src.core.bid"
local BidType = BidModule.BidType

local FeatureExtractor = {}

function FeatureExtractor.get_state_vector(game, player_idx)
    local vec = {}
    for i=1, 466 do vec[i] = 0.0 end
    
    local idx = 1
    local player = game.players[player_idx]
    
    -- 1. Phase [Bid, Play] (2)
    if game.state == "BIDDING" or game.state == "KITTY" then -- String states in Lua?
        -- Actually Game.lua uses "BIDDING", "KITTY", "PLAYING"
        -- Python utils_rl maps BIDDING/KITTY -> BID (vec[0]=1)
        vec[idx] = 1.0
    elseif game.state == "PLAYING" then -- Maps to PLAY (vec[1]=1)
        vec[idx + 1] = 1.0
    end
    idx = idx + 2
    
    -- 2. Hand (53)
    for _, card in ipairs(player.hand) do
        local c_idx = FeatureExtractor.card_to_int(card)
        if c_idx >= 0 then vec[idx + c_idx] = 1.0 end
    end
    idx = idx + 53
    
    -- 3. Trump (6)
    local t_offset = 5 -- None
    if game.trump_suit then
        if game.trump_suit == Suit.NO_TRUMP then t_offset = 4
        else
            local map = {[Suit.SPADES]=0, [Suit.CLUBS]=1, [Suit.DIAMONDS]=2, [Suit.HEARTS]=3}
            t_offset = map[game.trump_suit]
        end
    end
    vec[idx + t_offset] = 1.0
    idx = idx + 6
    
    -- 4. Current Trick (212) - 4 slots * 53
    for i, play in ipairs(game.current_trick) do
        if i > 4 then break end
        local c_int = FeatureExtractor.card_to_int(play.card)
        -- i is 1-based. Python i is 0-based.
        -- Slot offset: (i-1) * 53
        vec[idx + ((i-1) * 53) + c_int] = 1.0
    end
    idx = idx + (4 * 53)
    
    -- 6. Played History (53) - Cards played in round
    if game.cards_played_this_round then
        for _, card in ipairs(game.cards_played_this_round) do
             local c_int = FeatureExtractor.card_to_int(card)
             vec[idx + c_int] = 1.0
        end
    end
    idx = idx + 53
    
    -- 7. Scores (3)
    -- Identify Team
    -- Lua Index 1 (P1) -> Team 1 (Indices 1,3)
    -- Index 2 (P2) -> Team 2 (Indices 2,4)
    local my_team_idx = ((player_idx - 1) % 2) + 1
    local opp_team_idx = (my_team_idx == 1) and 2 or 1
    
    local my_score = game.teams[my_team_idx].score or 0
    local opp_score = game.teams[opp_team_idx].score or 0
    
    vec[idx] = my_score / 1000.0
    vec[idx+1] = opp_score / 1000.0
    vec[idx+2] = (my_score - opp_score) / 1000.0
    idx = idx + 3
    
    -- 8. Winning Bid (15)
    if game.winning_bid then
        local wb = game.winning_bid
        -- Tricks (0 or 6-10)
        local tr_idx = 0
        if wb.tricks >= 6 then tr_idx = wb.tricks - 5 end
        vec[idx + tr_idx] = 1.0
        idx = idx + 6
        
        -- Suit
        local s_offset = 4 -- NoTrump/None
        if wb.suit and wb.suit ~= Suit.NO_TRUMP then
            local map = {[Suit.SPADES]=0, [Suit.CLUBS]=1, [Suit.DIAMONDS]=2, [Suit.HEARTS]=3}
            s_offset = map[wb.suit]
        end
        vec[idx + s_offset] = 1.0
        idx = idx + 5
        
        -- Bidder Seat Relative
        local bidder_seat = game:get_player_index(wb.player)
        -- Lua indices 1-4. Python 0-3.
        -- Python: (bidder - agent) % 4
        -- Lua: ((bidder - 1) - (agent - 1)) % 4 => (bidder - agent) % 4
        -- If result negative, +4.
        local rel_seat = (bidder_seat - player_idx) % 4
        vec[idx + rel_seat] = 1.0
        idx = idx + 4
    else
        idx = idx + 15
    end
    
    -- 9. Tricks Won (2)
    -- Need to sum tricks won by team players in current round
    local my_tricks = 0
    for _, p in ipairs(game.teams[my_team_idx].players) do my_tricks = my_tricks + (p.tricks_won_round or 0) end
    local opp_tricks = 0
    for _, p in ipairs(game.teams[opp_team_idx].players) do opp_tricks = opp_tricks + (p.tricks_won_round or 0) end
    
    vec[idx] = my_tricks / 10.0
    vec[idx+1] = opp_tricks / 10.0
    idx = idx + 2
    
    -- 10. Bidding History One-Hot (112)
    -- Iterate game.bids_this_round
    local last_bids = {} -- [seat_idx (1-4)] -> bid_code
    
    if game.bids_this_round then
        for _, item in ipairs(game.bids_this_round) do
            -- item is Bid object (with PASS support now)
            local p_idx_h = game:get_player_index(item.player)
            local bid_code = 0 -- Pass default
            
            if item.bid_type ~= BidType.PASS then
                 if item.bid_type == BidType.MISERE then bid_code = 26
                 elseif item.bid_type == BidType.OPEN_MISERE then bid_code = 27
                 else
                     -- Suit Bid
                     local tr_idx = item.tricks - 6
                     local eff_suit = item.suit
                     if item.bid_type == BidType.NO_TRUMP then eff_suit = Suit.NO_TRUMP end
                     
                     local s_map = {[Suit.SPADES]=0, [Suit.CLUBS]=1, [Suit.DIAMONDS]=2, [Suit.HEARTS]=3, [Suit.NO_TRUMP]=4}
                     local s_idx = s_map[eff_suit] or 4
                     bid_code = 1 + (tr_idx * 5) + s_idx
                 end
            end
            
            last_bids[p_idx_h] = bid_code
        end
    end
    
    -- Write to vector relative to agent
    for i=0, 3 do
        local seat_idx = ((player_idx - 1 + i) % 4) + 1
        local code = last_bids[seat_idx]
        if code then
             vec[idx + code] = 1.0
        end
        idx = idx + 28
    end
    
    -- 11. Suit Counts (4)
    local counts = {[Suit.SPADES]=0, [Suit.CLUBS]=0, [Suit.DIAMONDS]=0, [Suit.HEARTS]=0}
    for _, card in ipairs(player.hand) do
        if card.suit ~= Suit.NO_TRUMP and card.rank ~= Rank.JOKER then
             counts[card.suit] = counts[card.suit] + 1
        end
        -- Joker? Python utils_rl assumes Joker suit?
        -- utils_rl: if card.suit in suit_counts...
        -- Joker has NO_TRUMP usually. NO_TRUMP is not in suit_counts keys.
        -- So Joker is skipped in counts. Correct.
    end
     
    vec[idx] = counts[Suit.SPADES] / 13.0
    vec[idx+1] = counts[Suit.CLUBS] / 13.0
    vec[idx+2] = counts[Suit.DIAMONDS] / 13.0
    vec[idx+3] = counts[Suit.HEARTS] / 13.0
    idx = idx + 4
    
    -- 12. Void indicators (4)
    vec[idx] = (counts[Suit.SPADES] == 0) and 1.0 or 0.0
    vec[idx+1] = (counts[Suit.CLUBS] == 0) and 1.0 or 0.0
    vec[idx+2] = (counts[Suit.DIAMONDS] == 0) and 1.0 or 0.0
    vec[idx+3] = (counts[Suit.HEARTS] == 0) and 1.0 or 0.0
    idx = idx + 4
    
    return vec
end

function FeatureExtractor.card_to_int(card)
    if card.rank == Rank.JOKER then return 52 end
    -- Rank 4=0 ... Ace=10
    local r_idx = math.max(0, card.rank - 4)
    local s_idx = 0
    if card.suit == Suit.CLUBS then s_idx = 1
    elseif card.suit == Suit.DIAMONDS then s_idx = 2
    elseif card.suit == Suit.HEARTS then s_idx = 3
    end
    -- SPADES is 0
    return (s_idx * 13) + r_idx
end

function FeatureExtractor.int_to_card(idx)
    if idx == 52 then return CardModule.Card.new(Suit.NO_TRUMP, Rank.JOKER) end
    if idx < 0 or idx > 51 then return nil end
    
    local s_val = math.floor(idx / 13)
    local r_val = (idx % 13) + 4
    
    local suits = {[0]=Suit.SPADES, [1]=Suit.CLUBS, [2]=Suit.DIAMONDS, [3]=Suit.HEARTS}
    return CardModule.Card.new(suits[s_val], r_val)
end

function FeatureExtractor.decode_action(action_idx, phase)
    if phase == "BID" then
        if action_idx == 0 then return "pass", nil end
        if action_idx >= 1 and action_idx <= 25 then
            local adj = action_idx - 1
            local tricks = 6 + math.floor(adj / 5)
            local s_idx = adj % 5
            local suits = {[0]=Suit.SPADES, [1]=Suit.CLUBS, [2]=Suit.DIAMONDS, [3]=Suit.HEARTS, [4]=Suit.NO_TRUMP}
            local suit = suits[s_idx]
            local type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            return "bid", {tricks, suit, type}
        elseif action_idx == 26 then
            return "bid", {0, Suit.NO_TRUMP, BidType.MISERE}
        elseif action_idx == 27 then
            return "bid", {0, Suit.NO_TRUMP, BidType.OPEN_MISERE}
        end
    elseif phase == "PLAY" then
        local c = FeatureExtractor.int_to_card(action_idx)
        return "play", c
    end
    return "pass", nil
end

return FeatureExtractor
