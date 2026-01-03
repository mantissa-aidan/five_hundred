local Utils = require "src.core.utils"
local json = require "src.ext.json"

local Net = Utils.class("Net")

-- Dueling DQN Architecture:
-- feature: Sequential layers -> embedding
-- advantage: Sequential layers -> advantage per action
-- value: Sequential layers -> single value

function Net:init(weights_dict)
    -- Parse feature, advantage, and value heads
    self.feature_layers = self:parse_sequential(weights_dict, "feature")
    self.advantage_layers = self:parse_sequential(weights_dict, "advantage")
    self.value_layers = self:parse_sequential(weights_dict, "value")
end

function Net:parse_sequential(weights_dict, prefix)
    local layers = {}
    
    -- Find max layer index for this prefix
    local max_idx = -1
    for k, _ in pairs(weights_dict) do
        local pattern = prefix .. "%.(%d+)%.weight"
        local idx_str = string.match(k, pattern)
        if idx_str then
            local idx = tonumber(idx_str)
            if idx > max_idx then max_idx = idx end
        end
    end
    
    -- Build layer sequence
    for i = 0, max_idx do
        local w_key = string.format("%s.%d.weight", prefix, i)
        local b_key = string.format("%s.%d.bias", prefix, i)
        
        if weights_dict[w_key] then
            -- Linear layer
            table.insert(layers, {
                type = "Linear",
                weight = weights_dict[w_key],
                bias = weights_dict[b_key]
            })
        else
            -- Check if it's a ReLU (odd indices in PyTorch Sequential with Linear+ReLU pattern)
            -- Heuristic: If no weight at this index but we have weights at previous odd index
            if i % 2 == 1 then
                table.insert(layers, { type = "ReLU" })
            end
        end
    end
    
    return layers
end

function Net:forward(input_vec)
    -- Feature embedding
    local x = self:forward_sequential(input_vec, self.feature_layers)
    
    -- Advantage stream
    local advantage = self:forward_sequential(x, self.advantage_layers)
    
    -- Value stream
    local value = self:forward_sequential(x, self.value_layers)
    
    -- Dueling combination: Q = V + (A - mean(A))
    local mean_adv = 0
    for _, v in ipairs(advantage) do mean_adv = mean_adv + v end
    mean_adv = mean_adv / #advantage
    
    local q_values = {}
    for i, a in ipairs(advantage) do
        q_values[i] = value[1] + (a - mean_adv)
    end
    
    return q_values
end

function Net:forward_sequential(input, layers)
    local x = input
    for _, layer in ipairs(layers) do
        if layer.type == "Linear" then
            x = self:linear_forward(x, layer.weight, layer.bias)
        elseif layer.type == "ReLU" then
            x = self:relu_forward(x)
        end
    end
    return x
end

function Net:linear_forward(input, weight, bias)
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

function Net:relu_forward(input)
    local out = {}
    for i, v in ipairs(input) do
        out[i] = v > 0 and v or 0
    end
    return out
end

return Net
