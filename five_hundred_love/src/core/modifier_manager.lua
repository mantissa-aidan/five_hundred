-- ModifierManager.lua
-- Manages active modifiers and applies their effects

local Modifier = require "src.core.modifier"
local ModifierRegistry = require "src.core.modifier_registry"

local ModifierManager = {}
ModifierManager.__index = ModifierManager

function ModifierManager.new(run_state)
    local self = setmetatable({}, ModifierManager)

    self.run_state = run_state
    self.max_active = 3  -- Maximum active modifiers

    return self
end

-- Get currently active modifiers from run state
function ModifierManager:get_active()
    return self.run_state.active_modifiers or {}
end

-- Add a modifier (by ID or instance)
function ModifierManager:add(modifier_or_id)
    local modifier
    if type(modifier_or_id) == "string" then
        modifier = ModifierRegistry.create(modifier_or_id)
    else
        modifier = modifier_or_id
    end

    if not modifier then
        return false, "Invalid modifier"
    end

    local active = self:get_active()
    if #active >= self.max_active then
        return false, "Maximum modifiers reached"
    end

    table.insert(self.run_state.active_modifiers, modifier)
    self.run_state.stats.powerups_collected = self.run_state.stats.powerups_collected + 1

    return true, modifier
end

-- Remove a modifier by index
function ModifierManager:remove(index)
    local active = self:get_active()
    if index > 0 and index <= #active then
        return table.remove(self.run_state.active_modifiers, index)
    end
    return nil
end

-- Remove a modifier by ID
function ModifierManager:remove_by_id(id)
    local active = self:get_active()
    for i, mod in ipairs(active) do
        if mod.id == id then
            return table.remove(self.run_state.active_modifiers, i)
        end
    end
    return nil
end

-- Check if a specific modifier is active
function ModifierManager:has(id)
    for _, mod in ipairs(self:get_active()) do
        if mod.id == id then
            return true
        end
    end
    return false
end

-- Apply all active modifiers of a type to a value
-- context: Information about what's being scored (card, trick, etc.)
-- value: The base value to modify
-- mod_type: Filter to specific modifier type (optional)
function ModifierManager:apply(context, value, mod_type)
    local result = value

    for _, mod in ipairs(self:get_active()) do
        -- Filter by type if specified
        if not mod_type or mod.type == mod_type then
            -- Check if modifier applies to this context
            if mod:applies_to(context) then
                result = mod:apply(context, result)
            end
        end
    end

    return result
end

-- Apply scoring modifiers to card play
function ModifierManager:apply_card_scoring(card, is_trump, is_bower, base_points)
    local context = {
        card = card,
        is_trump = is_trump,
        is_bower = is_bower,
        is_card_scoring = true,
    }

    return self:apply(context, base_points, Modifier.TYPE.SCORING)
end

-- Apply scoring modifiers to trick win
function ModifierManager:apply_trick_scoring(trick_cards, streak_multiplier, base_points)
    local context = {
        trick_cards = trick_cards,
        streak_multiplier = streak_multiplier,
        is_trick_scoring = true,
    }

    return self:apply(context, base_points, Modifier.TYPE.SCORING)
end

-- Apply scoring modifiers to contract bonus
function ModifierManager:apply_contract_scoring(bid_value, success, is_defending, base_points)
    local context = {
        bid_value = bid_value,
        success = success,
        is_defending = is_defending,
        is_contract_scoring = true,
    }

    return self:apply(context, base_points, Modifier.TYPE.SCORING)
end

-- Check for snap condition (matching partner's rank)
function ModifierManager:check_snap(trick_cards, player_team)
    -- Only check if snap modifier is active
    if not self:has("snap_bonus") then
        return false
    end

    -- Find cards played by team members
    -- trick_cards is array of {player, card} pairs
    local team_ranks = {}
    for _, play in ipairs(trick_cards) do
        -- Check if player is on the same team
        local player_idx = play.player.index
        local is_team_member = (player_idx == 1 or player_idx == 3)  -- Team A (player + partner)

        if is_team_member then
            local rank = play.card.rank
            if team_ranks[rank] then
                -- Found a matching rank - SNAP!
                return true
            end
            team_ranks[rank] = true
        end
    end

    return false
end

-- Tick all modifier durations (called at end of trick or round)
function ModifierManager:tick(tick_type)
    local to_remove = {}

    for i, mod in ipairs(self:get_active()) do
        mod:tick(tick_type)
        if mod:is_expired() then
            table.insert(to_remove, i)
        end
    end

    -- Remove expired modifiers (in reverse order to preserve indices)
    for i = #to_remove, 1, -1 do
        table.remove(self.run_state.active_modifiers, to_remove[i])
    end

    return #to_remove  -- Return count of removed modifiers
end

-- Get count of active modifiers
function ModifierManager:count()
    return #self:get_active()
end

-- Check if can add more modifiers
function ModifierManager:can_add()
    return self:count() < self.max_active
end

-- Clear all modifiers
function ModifierManager:clear()
    self.run_state.active_modifiers = {}
end

return ModifierManager
