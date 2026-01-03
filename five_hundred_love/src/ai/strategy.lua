-- Strategy Interface
-- Base class for all player decision-making strategies

local Utils = require "src.core.utils"

local Strategy = Utils.class("Strategy")

-- Called when a bid decision is needed
-- Returns: action_type ("pass" or "bid"), params (nil or {tricks, suit, bid_type})
function Strategy:decide_bid(game, player_idx)
    error("Strategy:decide_bid() not implemented")
end

-- Called when a card play decision is needed
-- Returns: Card to play (must be in playable_cards)
function Strategy:decide_play(game, player_idx, playable_cards)
    error("Strategy:decide_play() not implemented")
end

-- Called when kitty discard decision is needed
-- Returns: Table of 3 cards to discard
function Strategy:decide_discard(game, player_idx)
    error("Strategy:decide_discard() not implemented")
end

-- Returns true if this strategy requires UI input (human players)
function Strategy:requires_input()
    return false
end

return Strategy
