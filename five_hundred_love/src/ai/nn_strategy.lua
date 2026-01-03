-- Neural Network Strategy for PPO Agent
-- Uses trained PPO policy with shared trunk + dual heads

local Utils = require "src.core.utils"
local Strategy = require "src.ai.strategy"
local FeatureExtractor = require "src.ai.feature_extractor"
local json = require "src.ext.json"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Suit = CardModule.Suit
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local NNStrategy = Utils.class("NNStrategy")
setmetatable(NNStrategy, {__index = Strategy})

-- Simple helper for linear layer forward pass
local function linear_forward(input, weight, bias)
    local out_dim = #weight
    local in_dim = #weight[1]
    
    if #input ~= in_dim then
        error(string.format("Input dim mismatch: expected %d, got %d", in_dim, #input))
    end
    
    local out = {}
    for i = 1, out_dim do
        local sum = 0
        local w_row = weight[i]
        for j = 1, in_dim do
            sum = sum + w_row[j] * input[j]
        end
        if bias then sum = sum + bias[i] end
        out[i] = sum
    end
    return out
end

-- ReLU activation
local function relu(input)
    local out = {}
    for i, v in ipairs(input) do
        out[i] = v > 0 and v or 0
    end
    return out
end

function NNStrategy:init(weights_source)
    local weights
    
    if type(weights_source) == "table" then
        weights = weights_source
    else
        -- Load neural network weights from file
        local path = weights_source
        local content = love.filesystem.read(path)
        if not content then
            local f = io.open(path, "r")
            if f then content = f:read("*a"); f:close() end
        end
        
        if not content then
            error("NNStrategy: Could not load weights from " .. path)
        end
        
        weights = json.decode(content)
    end

    -- Store PPO weights
    -- Structure: shared_fc1, shared_fc2, actor_bid, actor_play
    
    -- DEBUG: Print what keys we actually received
    print("[NNStrategy] Received weights with keys:")
    for k, v in pairs(weights) do
        print("  - " .. tostring(k))
    end
    
    self.shared_fc1 = weights.shared_fc1
    self.shared_fc2 = weights.shared_fc2
    self.actor_bid = weights.actor_bid
    self.actor_play = weights.actor_play
    
    if not self.shared_fc1 or not self.shared_fc2 or not self.actor_bid or not self.actor_play then
        error("NNStrategy: Missing required weights (shared_fc1, shared_fc2, actor_bid, actor_play)")
    end
    
    print("[NNStrategy] PPO neural network loaded successfully")
end

-- Forward pass through shared trunk
function NNStrategy:forward_shared(input_vec)
    -- Layer 1: Linear(466, 256) + ReLU
    local h1 = linear_forward(input_vec, self.shared_fc1.weight, self.shared_fc1.bias)
    h1 = relu(h1)
    
    -- Layer 2: Linear(256, 128) + ReLU
    local h2 = linear_forward(h1, self.shared_fc2.weight, self.shared_fc2.bias)
    h2 = relu(h2)
    
    return h2
end

-- Forward pass through bid head
function NNStrategy:forward_bid(features)
    return linear_forward(features, self.actor_bid.weight, self.actor_bid.bias)
end

-- Forward pass through play head
function NNStrategy:forward_play(features)
    return linear_forward(features, self.actor_play.weight, self.actor_play.bias)
end

function NNStrategy:decide_bid(game, player_idx)
    local player = game.players[player_idx]
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    
    -- Forward pass: Input -> Shared -> Actor Bid
    local features = self:forward_shared(vec)
    local logits = self:forward_bid(features)
    
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
    
    -- Forward pass: Input -> Shared -> Actor Play
    local features = self:forward_shared(vec)
    local logits = self:forward_play(features)
    
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
function NNStrategy:get_top_actions(game, player_idx, action_type, n)
    n = n or 5
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    local features = self:forward_shared(vec)
    local logits
    
    if action_type == "BID" then
        logits = self:forward_bid(features)
    else
        logits = self:forward_play(features)
    end
    
    -- Compute softmax over valid actions
    local valid_logits = {}
    
    for i, v in ipairs(logits) do
        local action_idx = i - 1
        local is_valid = true
        
        if action_type == "BID" then
            -- Mask Misere
            if action_idx == 26 or action_idx == 27 then is_valid = false end
            
            -- Mask lower bids
            if action_idx >= 1 and action_idx <= 25 and game.highest_bid then
                local adj = action_idx - 1
                local tricks = 6 + math.floor(adj / 5)
                local s_idx = adj % 5
                local suits = {[0]=Suit.SPADES, [1]=Suit.CLUBS, [2]=Suit.DIAMONDS, [3]=Suit.HEARTS, [4]=Suit.NO_TRUMP}
                local suit = suits[s_idx]
                local bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
                
                local temp_bid = Bid.new(game.players[player_idx], tricks, suit, bid_type)
                if not (temp_bid > game.highest_bid) then
                    is_valid = false
                end
            end
        end
        
        if is_valid then
            table.insert(valid_logits, {idx = action_idx, val = v})
        end
    end
    
    -- Compute Softmax
    local max_logit = -1e9
    for _, item in ipairs(valid_logits) do
        if item.val > max_logit then max_logit = item.val end
    end
    
    local exp_sum = 0
    for _, item in ipairs(valid_logits) do
        item.exp = math.exp(item.val - max_logit)
        exp_sum = exp_sum + item.exp
    end
    
    local probs = {}
    for _, item in ipairs(valid_logits) do
        probs[item.idx] = item.exp / exp_sum
    end
    
    -- Create action list
    local actions = {}
    for _, item in ipairs(valid_logits) do
        local action_idx = item.idx
        local prob = probs[action_idx]
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
            end
        else
            local card = FeatureExtractor.int_to_card(action_idx)
            if card then
                local rank_chars = {[4]="4",[5]="5",[6]="6",[7]="7",[8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",[14]="A",[100]="JK"}
                local suit_chars = {[Suit.SPADES]="♠",[Suit.CLUBS]="♣",[Suit.DIAMONDS]="♦",[Suit.HEARTS]="♥",[Suit.NO_TRUMP]=""}
                label = (rank_chars[card.rank] or "?") .. (suit_chars[card.suit] or "")
            end
        end
        
        table.insert(actions, {label = label, prob = prob, idx = action_idx})
    end
    
    -- Sort by probability
    table.sort(actions, function(a, b) return a.prob > b.prob end)
    
    -- Return top N
    local result = {}
    for i = 1, math.min(n, #actions) do
        table.insert(result, actions[i])
    end
    
    return result
end

function NNStrategy:get_top_actions_filtered(game, player_idx, playable_cards, n)
    n = n or 5
    local vec = FeatureExtractor.get_state_vector(game, player_idx)
    local features = self:forward_shared(vec)
    local logits = self:forward_play(features)
    
    -- Build playable set
    local playable_set = {}
    for _, card in ipairs(playable_cards) do
        local idx = FeatureExtractor.card_to_int(card)
        playable_set[idx] = card
    end
    
    -- Softmax over playable
    local max_logit = -1e9
    for idx, _ in pairs(playable_set) do
        if logits[idx + 1] > max_logit then
            max_logit = logits[idx + 1]
        end
    end
    
    local exp_sum = 0
    local exp_vals = {}
    for idx, _ in pairs(playable_set) do
        exp_vals[idx] = math.exp(logits[idx + 1] - max_logit)
        exp_sum = exp_sum + exp_vals[idx]
    end
    
    local actions = {}
    for idx, card in pairs(playable_set) do
        local prob = exp_vals[idx] / exp_sum
        local rank_chars = {[4]="4",[5]="5",[6]="6",[7]="7",[8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",[14]="A",[100]="JK"}
        local suit_chars = {[Suit.SPADES]="♠",[Suit.CLUBS]="♣",[Suit.DIAMONDS]="♦",[Suit.HEARTS]="♥",[Suit.NO_TRUMP]=""}
        local label = (rank_chars[card.rank] or "?") .. (suit_chars[card.suit] or "")
        table.insert(actions, {label = label, prob = prob, card = card})
    end
    
    table.sort(actions, function(a, b) return a.prob > b.prob end)
    
    local result = {}
    for i = 1, math.min(n, #actions) do
        table.insert(result, actions[i])
    end
    
    return result
end

function NNStrategy:is_nn()
    return true
end

return NNStrategy
