-- Human Strategy
-- Returns nil to signal "waiting for UI input"

local Utils = require "src.core.utils"
local Strategy = require "src.ai.strategy"

local HumanStrategy = Utils.class("HumanStrategy")
setmetatable(HumanStrategy, {__index = Strategy})

function HumanStrategy:init()
    -- No initialization needed
end

function HumanStrategy:decide_bid(game, player_idx)
    -- Return nil to signal controller that we're waiting for UI input
    return nil, nil
end

function HumanStrategy:decide_play(game, player_idx, playable_cards)
    -- Return nil to signal waiting for UI input
    return nil
end

function HumanStrategy:decide_discard(game, player_idx)
    -- Return nil to signal waiting for UI input
    return nil
end

function HumanStrategy:requires_input()
    return true
end

return HumanStrategy
