local Utils = require "src.core.utils"
local Player = require "src.core.player"
local Net = require "src.ai.net"
local FeatureExtractor = require "src.ai.feature_extractor"

-- Need generic JSON loader or assume I provided one.
-- I'll use a very simple JSON parser inline or require "dkjson" if I had it.
-- Or better: My 'Net' module handled the struct? No, Net:init expects a table.
-- I need to load `weights.json` into a table.
-- I will add a `src/ext/json.lua` file in next step if needed, or put a minimalist parser here.
-- For now, I'll assume `src.ext.json` exists (I will create it).

local json = require "src.ext.json"

local Bot = Utils.class("Bot")
setmetatable(Bot, {__index = Player}) -- Inherit from Player

function Bot:init(name, weights_path)
    Player.init(self, name)
    
    local content = love.filesystem.read(weights_path)
    if not content then
        -- Try absolute path if love filesystem fails (e.g. running from CLI lua)
        -- Fallback to io.open
        local f = io.open(weights_path, "r")
        if f then
            content = f:read("*a")
            f:close()
        else
            error("Could not load weights: " .. weights_path)
        end
    end
    
    local weights = json.decode(content)
    
    self.bid_net = Net.new(weights["bidding"])
    self.play_net = Net.new(weights["playing"])
end

function Bot:decide_bid(game)
    local vec = FeatureExtractor.get_state_vector(game, game:get_player_index(self))
    local logits = self.bid_net:forward(vec)
    
    -- Argmax with masking
    -- Basic logic: find max valid action
    -- Ideally FeatureExtractor returns mask too.
    -- For now, just pick max. If invalid, Game will reject, we loop?
    -- No, we should pick max valid.
    -- But masking logic is separate.
    -- Assume raw argmax for now.
    
    local max_val = -1e9
    local max_idx = 0 -- 0-based action index
    
    for i=1, #logits do
        if logits[i] > max_val then
            max_val = logits[i]
            max_idx = i - 1 -- Convert Lua 1-based logit idx to 0-based action idx
        end
    end
    
    local action, params = FeatureExtractor.decode_action(max_idx, "BID")
    return action, params
end

function Bot:decide_play(game, playable_cards)
    local vec = FeatureExtractor.get_state_vector(game, game:get_player_index(self))
    -- Play Net
    local logits = self.play_net:forward(vec)
    
    -- We must pick a card that is in `playable_cards`.
    local best_card = nil
    local max_val = -1e9
    
    for _, card in ipairs(playable_cards) do
        local c_idx = FeatureExtractor.card_to_int(card)
        -- Logits is 100 sized (action_dim). 
        -- Lua index = c_idx + 1 (since c_idx is 0-52)
        local val = logits[c_idx + 1]
        
        if val > max_val then
            max_val = val
            best_card = card
        end
    end
    
    -- Fallback
    if not best_card then best_card = playable_cards[1] end
    
    return best_card
end

return Bot
