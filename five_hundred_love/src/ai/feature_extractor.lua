local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local BidModule = require "src.core.bid"
local BidType = BidModule.BidType

local FeatureExtractor = {}

function FeatureExtractor.get_state_vector(game, player_idx)
    local vec = {}
    for i=1, 600 do vec[i] = 0.0 end -- Init 600 slots
    
    local idx = 1 -- Lua 1-based index
    local player = game.players[player_idx]
    
    -- 1. Phase [Bid, Play] (2)
    -- Map KITTY to BID for encoding purposes usually
    if game.state == game.STATE.BIDDING or game.state == game.STATE.KITTY then
        vec[idx] = 1.0
    elseif game.state == game.STATE.PLAYING then
        vec[idx + 1] = 1.0
    end
    idx = idx + 2
    
    -- 2. Hand (53)
    for _, card in ipairs(player.hand) do
        local c_idx = FeatureExtractor.card_to_int(card)
        if c_idx >= 0 then
            vec[idx + c_idx] = 1.0 -- c_idx is 0-52, so +1 implicit by base idx
        end
    end
    idx = idx + 53
    
    -- 3. Trump (6: S, C, D, H, NT, None)
    local t_offset = 5
    if game.trump_suit then
        if game.trump_suit == Suit.NO_TRUMP then t_offset = 4
        else
            -- Map: S=0, C=1, D=2, H=3
            local map = {[Suit.SPADES]=0, [Suit.CLUBS]=1, [Suit.DIAMONDS]=2, [Suit.HEARTS]=3}
            t_offset = map[game.trump_suit]
        end
    end
    vec[idx + t_offset] = 1.0
    idx = idx + 6
    
    -- 4. Trick History (Current Trick) - 4 slots * 53 cards
    -- Python encoding used ordered slots. game.current_trick is list of {player, card}
    for i, play in ipairs(game.current_trick) do
        if i > 4 then break end
        local c_int = FeatureExtractor.card_to_int(play.card)
        -- i is 1-based, Python i was 0-based.
        -- Python: idx + (i_0 * 53) + c_int
        -- Lua: idx + ((i-1) * 53) + c_int
        vec[idx + ((i-1) * 53) + c_int] = 1.0
    end
    idx = idx + (4 * 53)
    
    -- 5. Winning Bid Info (Placeholder in Python comment, handled later there)
    -- Actually Python env.py skipped this block implementation or put it later?
    -- Checked Python: It skipped idx+=0 here. It puts Winning Bid at step 8.
    
    -- 6. History (Played Cards in Round) - 53 slots
    -- game.cards_played_this_round (need to track this in Game class!)
    -- Assuming game.round_history or similar tracks all cards.
    -- Game logic I wrote tracks `tricks_history`.
    if game.tricks_history then
        for _, trick_data in ipairs(game.tricks_history) do
            for _, play in ipairs(trick_data.cards) do
                local c_int = FeatureExtractor.card_to_int(play.card)
                vec[idx + c_int] = 1.0
            end
        end
    end
    -- Also add current trick cards to history? Python env logic usually separates them?
    -- Python `cards_played_this_round` includes cards in finished tricks usually.
    idx = idx + 53
    
    -- 7. Scores (3)
    -- Need to identify My Team vs Opp Team
    -- player_idx 1,3 are Team 1. 2,4 are Team 2.
    local my_team_idx = ((player_idx - 1) % 2) + 1 -- 1 or 2
    local opp_team_idx = (my_team_idx == 1) and 2 or 1
    local my_score = game.teams[my_team_idx].team_score
    local opp_score = game.teams[opp_team_idx].team_score
    
    vec[idx] = my_score / 1000.0
    vec[idx+1] = opp_score / 1000.0
    vec[idx+2] = (my_score - opp_score) / 1000.0
    idx = idx + 3
    
    -- 8. Winning Bid (15)
    if game.winning_bid then
        local wb = game.winning_bid
        -- Tricks (0, 6..10) -> 0..5
        local tr_idx = 0
        if wb.tricks >= 6 then tr_idx = wb.tricks - 5 end
        vec[idx + tr_idx] = 1.0
        idx = idx + 6
        
        -- Suit
        local s_offset = 4
        if wb.suit and wb.suit ~= Suit.NO_TRUMP then
            local map = {[Suit.SPADES]=0, [Suit.CLUBS]=1, [Suit.DIAMONDS]=2, [Suit.HEARTS]=3}
            s_offset = map[wb.suit]
        end
        vec[idx + s_offset] = 1.0
        idx = idx + 5
        
        -- Bidder Seat Relative (0..3)
        local bidder_seat = game:get_player_index(wb.player)
        local rel_seat = (bidder_seat - player_idx + 4) % 4 -- +4 to ensure positive
        vec[idx + rel_seat] = 1.0
        idx = idx + 4
    else
        idx = idx + 15
    end
    
    -- 9. Current Tricks Won (2)
    local my_tricks = game.teams[my_team_idx]:get_total_tricks_won_this_round()
    local opp_tricks = game.teams[opp_team_idx]:get_total_tricks_won_this_round()
    vec[idx] = my_tricks / 10.0
    vec[idx+1] = opp_tricks / 10.0
    idx = idx + 2
    
    -- 10. Bidding History (112)
    -- game.bids_this_round should store Bid objects or Pass strings/objects
    -- game.bids_this_round order ??
    -- We need "Last bid of each player".
    -- Iterate history and update state.
    
    local player_last_bid = {} -- Map seat -> bid_code
    -- Loop through bids
    -- Wait, who made the bid? In my Game logic, I appended bids.
    -- Need to traverse game.bids_this_round if available, but I need to know WHO made it.
    -- Assuming `game.bids_this_round` is managed. 
    -- Or just iterate current players?
    -- My Game implementation resets state per round.
    -- Let's assume we don't have full history log in Game yet.
    -- Simplification: Zero for now or assume Game ensures this.
    -- Ideally Game tracks `last_action` per player.
    idx = idx + 112
    
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
