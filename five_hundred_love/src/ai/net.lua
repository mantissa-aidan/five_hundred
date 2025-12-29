local Utils = require "src.core.utils"
local json = require "src.ext.json" -- Need a JSON lib. Love2D doesn't have one built-in usually? 
-- Wait, Love2D doesn't have standard JSON lib. I need to add one or use a simple parser.
-- I'll implement a simple JSON generic loader or assume 'dkjson' or similar is available or paste a small one.
-- Actually, for just weights (arrays), I can write a custom format or allow the user to provide a JSON lib.
-- I will add a simple JSON decoder.

local Net = Utils.class("Net")

function Net:init(weights_dict)
    self.layers = {}
    -- Reconstruct layers from weights_dict
    -- Expecting names like "feature.0.weight", "feature.0.bias"
    -- Sort keys to find order?
    -- Standard PyTorch Sequential: 0 is Linear, 1 is ReLU...
    
    -- Heuristic reconstruction:
    -- Find max layer index
    local max_idx = -1
    for k, _ in pairs(weights_dict) do
        local parts = {}
        for p in string.gmatch(k, "[^%.]+") do table.insert(parts, p) end
        if parts[1] == "feature" and tonumber(parts[2]) then
            local idx = tonumber(parts[2])
            if idx > max_idx then max_idx = idx end
        end
    end
    
    self.sequence = {}
    
    for i=0, max_idx do
        -- Check if we have weights for this index
        local w_key = string.format("feature.%d.weight", i)
        local b_key = string.format("feature.%d.bias", i)
        
        if weights_dict[w_key] then
            -- It's a Linear layer
            table.insert(self.sequence, {
                type = "Linear",
                weight = weights_dict[w_key], -- 2D array [out_dim][in_dim]
                bias = weights_dict[b_key]    -- 1D array [out_dim]
            })
        elseif not weights_dict[w_key] and i % 2 == 1 then
            -- Assume ReLU between Linears?
            -- PyTorch agent.py: Linear -> ReLU -> Linear...
            -- Sequential indices: 0=Linear, 1=ReLU, 2=Linear...
            table.insert(self.sequence, { type = "ReLU" })
        end
    end
    
    -- Value head ignored? Or used?
    -- The request is to play. The output of the network is Policy (logits) or Value?
    -- Agent uses epsilon-greedy on Q-values? Or is it Policy Gradient?
    -- Agent checks: `PyTorchAgent`.
    -- If DQN, output is Q-values for actions.
    -- The output layer is at the end of `feature`?
    -- Let's check `agent.py` again.
    -- `self.feature = nn.Sequential(..., nn.Linear(512, output_dim))`
    -- Ah, `feature` usually outputs embeddings? 
    -- `agent.py`: `self.feature = ... Linear(..., output_dim)`. 
    -- So `feature` contains the whole policy/Q-net.
    -- `value` is for Value estimation (Dueling DQN?), likely separate. 
    -- If simple DQN, we just need `feature` output.
end

function Net:forward(input_vec)
    local x = input_vec
    
    for _, layer in ipairs(self.sequence) do
        if layer.type == "Linear" then
            x = self:linear_forward(x, layer.weight, layer.bias)
        elseif layer.type == "ReLU" then
            x = self:relu_forward(x)
        end
    end
    
    return x
end

function Net:linear_forward(input, weight, bias)
    -- Weight shape: [out_dim][in_dim]
    -- Input shape: [in_dim]
    -- Output: [out_dim]
    local out = {}
    local out_dim = #weight
    local in_dim = #weight[1]
    
    if #input ~= in_dim then
        error(string.format("Input dim mismatch: expected %d, got %d", in_dim, #input))
    end
    
    for i=1, out_dim do
        local sum = 0
        local w_row = weight[i]
        for j=1, in_dim do
            sum = sum + w_row[j] * input[j]
        end
        if bias then sum = sum + bias[i] end
        out[i] = sum
    end
    return out
end

function Net:relu_forward(input)
    local out = {}
    for i, v in ipairs(input) do
        out[i] = v > 0 and v or 0
    end
    return out
end

return Net
