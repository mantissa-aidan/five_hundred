-- Random Strategy
-- Picks random valid actions - useful for testing and baseline

local Utils = require "src.core.utils"
local Strategy = require "src.ai.strategy"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Suit = CardModule.Suit
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local RandomStrategy = Utils.class("RandomStrategy")
setmetatable(RandomStrategy, {__index = Strategy})

function RandomStrategy:init()
    -- No initialization needed
end

function RandomStrategy:decide_bid(game, player_idx)
    -- 70% chance to pass, 30% chance to make a valid bid
    if math.random() < 0.7 then
        return "pass", nil
    end
    
    local player = game.players[player_idx]
    
    -- Find all valid bids
    local valid_bids = {}
    for tricks = 6, 10 do
        for s_idx, suit in ipairs({Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP}) do
            local bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            local temp_bid = Bid.new(player, tricks, suit, bid_type)
            
            if not game.highest_bid or temp_bid > game.highest_bid then
                table.insert(valid_bids, {tricks, suit, bid_type})
            end
        end
    end
    
    if #valid_bids == 0 then
        return "pass", nil
    end
    
    -- Pick random valid bid
    local choice = valid_bids[math.random(#valid_bids)]
    return "bid", choice
end

function RandomStrategy:decide_play(game, player_idx, playable_cards)
    -- Pick random playable card
    return playable_cards[math.random(#playable_cards)]
end

function RandomStrategy:decide_discard(game, player_idx)
    -- Discard first 3 cards (simple)
    local player = game.players[player_idx]
    return {player.hand[1], player.hand[2], player.hand[3]}
end

return RandomStrategy
