-- Neural Network Strategy
-- Uses trained Dueling DQN for bid and play decisions

local Utils = require "src.core.utils"
local Strategy = require "src.ai.strategy"
local Net = require "src.ai.net"
local FeatureExtractor = require "src.ai.feature_extractor"
local json = require "src.ext.json"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Suit = CardModule.Suit
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local NNStrategy = Utils.class("NNStrategy")
setmetatable(NNStrategy, {__index = Strategy})

function NNStrategy:init(weights_path)
    -- Load neural network weights
    local content = love.filesystem.read(weights_path)
    if not content then
        local f = io.open(weights_path, "r")
        if f then content = f:read("*a"); f:close() end
    end
    
    if not content then
        error("NNStrategy: Could not load weights from " .. weights_path)
    end
    
    local weights = json.decode(content)
    self.bid_net = Net.new(weights["bidding"])
    self.play_net = Net.new(weights["playing"])
    
    print("[NNStrategy] Neural network loaded successfully")
end

function NNStrategy:decide_bid(game, player_idx)
    local player = game.players[player_idx]
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    local logits = self.bid_net:forward(vec)
    
    -- Find best valid bid (mask out Misere 26, 27)
    local max_val = -1e9
    local max_idx = 0 -- 0 = Pass
    
    for i = 1, #logits do
        local action_idx = i - 1 -- 0-based
        local valid = true
        
        -- Mask Misere (not trained)
        if action_idx == 26 or action_idx == 27 then valid = false end
        
        -- Mask lower bids
        if action_idx >= 1 and action_idx <= 25 and game.highest_bid then
            local adj = action_idx - 1
            local tricks = 6 + math.floor(adj / 5)
            local s_idx = adj % 5
            local suits = {[0]=Suit.SPADES, [1]=Suit.CLUBS, [2]=Suit.DIAMONDS, [3]=Suit.HEARTS, [4]=Suit.NO_TRUMP}
            local suit = suits[s_idx]
            local bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            
            local temp_bid = Bid.new(player, tricks, suit, bid_type)
            if not (temp_bid > game.highest_bid) then
                valid = false
            end
        end
        
        if valid and logits[i] > max_val then
            max_val = logits[i]
            max_idx = action_idx
        end
    end
    
    -- Decode action
    if max_idx == 0 then
        return "pass", nil
    else
        local action, params = FeatureExtractor.decode_action(max_idx, "BID")
        return action, params
    end
end

function NNStrategy:decide_play(game, player_idx, playable_cards)
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    local logits = self.play_net:forward(vec)
    
    -- Find best playable card
    local best_card = playable_cards[1]
    local max_val = -1e9
    
    for _, card in ipairs(playable_cards) do
        local c_idx = FeatureExtractor.card_to_int(card)
        local val = logits[c_idx + 1] -- 1-based Lua index
        if val > max_val then
            max_val = val
            best_card = card
        end
    end
    
    return best_card
end

function NNStrategy:decide_discard(game, player_idx)
    -- Simple heuristic: discard lowest value cards
    -- TODO: Could train a dedicated discard network
    local player = game.players[player_idx]
    local hand = player.hand
    
    -- Sort by rank (ascending)
    local sorted = {}
    for _, card in ipairs(hand) do table.insert(sorted, card) end
    table.sort(sorted, function(a, b) return a.rank < b.rank end)
    
    -- Return first 3 (lowest)
    return {sorted[1], sorted[2], sorted[3]}
end

-- Get top N actions with probabilities for debug display
-- action_type: "BID" or "PLAY"
function NNStrategy:get_top_actions(game, player_idx, action_type, n)
    n = n or 5
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    local logits
    
    if action_type == "BID" then
        logits = self.bid_net:forward(vec)
    else
        logits = self.play_net:forward(vec)
    end
    
    -- Compute softmax
    local max_logit = -1e9
    for _, v in ipairs(logits) do
        if v > max_logit then max_logit = v end
    end
    
    local exp_sum = 0
    local exp_vals = {}
    for i, v in ipairs(logits) do
        exp_vals[i] = math.exp(v - max_logit) -- Numerical stability
        exp_sum = exp_sum + exp_vals[i]
    end
    
    local probs = {}
    for i, ev in ipairs(exp_vals) do
        probs[i] = ev / exp_sum
    end
    
    -- Create action list with probabilities
    local actions = {}
    for i, prob in ipairs(probs) do
        local action_idx = i - 1
        local label = ""
        
        if action_type == "BID" then
            if action_idx == 0 then
                label = "Pass"
            elseif action_idx >= 1 and action_idx <= 25 then
                local adj = action_idx - 1
                local tricks = 6 + math.floor(adj / 5)
                local s_idx = adj % 5
                local suit_chars = {"♠", "♣", "♦", "♥", "NT"}
                label = tostring(tricks) .. suit_chars[s_idx + 1]
            elseif action_idx == 26 then
                label = "Mis"
            elseif action_idx == 27 then
                label = "OMis"
            end
        else
            -- PLAY - card index
            local card = FeatureExtractor.int_to_card(action_idx)
            if card then
                local rank_chars = {[4]="4",[5]="5",[6]="6",[7]="7",[8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",[14]="A",[15]="JK"}
                local suit_chars = {[Suit.SPADES]="♠",[Suit.CLUBS]="♣",[Suit.DIAMONDS]="♦",[Suit.HEARTS]="♥",[Suit.NO_TRUMP]=""}
                label = (rank_chars[card.rank] or "?") .. (suit_chars[card.suit] or "")
            else
                label = "?"
            end
        end
        
        table.insert(actions, {label = label, prob = prob, idx = action_idx})
    end
    
    -- Sort by probability descending
    table.sort(actions, function(a, b) return a.prob > b.prob end)
    
    -- Return top N
    local result = {}
    for i = 1, math.min(n, #actions) do
        table.insert(result, actions[i])
    end
    
    return result
end

-- Check if this is an NN strategy (for debug display)
function NNStrategy:is_nn()
    return true
end

return NNStrategy

