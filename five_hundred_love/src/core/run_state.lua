-- RunState.lua
-- Manages state for a roguelike run in Five Hundred

local RunState = {}
RunState.__index = RunState

function RunState.new()
    local self = setmetatable({}, RunState)

    -- Core state
    self.mode = "ROGUELIKE"
    self.current_round = 1
    self.total_score = 0
    self.round_score = 0

    -- Difficulty
    self.subgoal_target = 50000  -- Starting target
    self.difficulty_multiplier = 1.5  -- Exponential growth per round

    -- Modifiers and powerups
    self.active_modifiers = {}  -- Max 3 active modifiers
    self.powerup_inventory = {}  -- Available powerups
    self.max_active_modifiers = 3

    -- Streak tracking
    self.streak_states = {
        consecutive_tricks = {count = 0, player_id = nil},
        same_suit_played = {count = 0, suit = nil},
        trump_streak = {count = 0},
        high_card_streak = {count = 0},
    }

    -- Statistics
    self.stats = {
        total_tricks_won = 0,
        total_cards_played = 0,
        contracts_made = 0,
        contracts_failed = 0,
        highest_streak = 0,
        powerups_collected = 0,
    }

    -- Game over flag
    self.is_game_over = false
    self.game_over_reason = nil

    return self
end

-- Advance to next round
function RunState:advance_round()
    self.current_round = self.current_round + 1
    self.round_score = 0

    -- Calculate new subgoal target (exponential growth)
    self.subgoal_target = math.floor(50000 * math.pow(self.difficulty_multiplier, self.current_round - 1))

    -- Reset per-round streaks
    self.streak_states.consecutive_tricks = {count = 0, player_id = nil}
    self.streak_states.same_suit_played = {count = 0, suit = nil}
    self.streak_states.trump_streak = {count = 0}
    self.streak_states.high_card_streak = {count = 0}
end

-- Add score to current round
function RunState:add_score(points)
    self.round_score = self.round_score + points
    self.total_score = self.total_score + points
end

-- Check if subgoal is met
function RunState:is_subgoal_met()
    return self.round_score >= self.subgoal_target
end

-- Trigger game over
function RunState:trigger_game_over(reason)
    self.is_game_over = true
    self.game_over_reason = reason or "Failed to meet subgoal"
end

-- Add a modifier to active list
function RunState:add_modifier(modifier)
    if #self.active_modifiers >= self.max_active_modifiers then
        return false, "Maximum modifiers reached"
    end

    table.insert(self.active_modifiers, modifier)
    return true
end

-- Remove a modifier from active list
function RunState:remove_modifier(modifier_id)
    for i, mod in ipairs(self.active_modifiers) do
        if mod.id == modifier_id then
            table.remove(self.active_modifiers, i)
            return true
        end
    end
    return false
end

-- Get all active modifiers of a specific type
function RunState:get_modifiers_by_type(modifier_type)
    local result = {}
    for _, mod in ipairs(self.active_modifiers) do
        if mod.type == modifier_type then
            table.insert(result, mod)
        end
    end
    return result
end

-- Update streak state
function RunState:update_streak(streak_name, data)
    if self.streak_states[streak_name] then
        for key, value in pairs(data) do
            self.streak_states[streak_name][key] = value
        end

        -- Track highest streak
        if data.count and data.count > self.stats.highest_streak then
            self.stats.highest_streak = data.count
        end
    end
end

-- Get current streak multiplier for consecutive tricks
function RunState:get_consecutive_trick_multiplier()
    local count = self.streak_states.consecutive_tricks.count
    return 1.0 + (0.2 * count)
end

-- Reset a specific streak
function RunState:reset_streak(streak_name)
    if streak_name == "consecutive_tricks" then
        self.streak_states.consecutive_tricks = {count = 0, player_id = nil}
    elseif streak_name == "same_suit_played" then
        self.streak_states.same_suit_played = {count = 0, suit = nil}
    elseif streak_name == "trump_streak" then
        self.streak_states.trump_streak = {count = 0}
    elseif streak_name == "high_card_streak" then
        self.streak_states.high_card_streak = {count = 0}
    end
end

-- Get formatted total score for display
function RunState:get_formatted_score()
    local score = self.total_score
    if score >= 1000000 then
        return string.format("%.1fM", score / 1000000)
    elseif score >= 1000 then
        return string.format("%.1fk", score / 1000)
    else
        return tostring(score)
    end
end

-- Get formatted round score for display
function RunState:get_formatted_round_score()
    local score = self.round_score
    if score >= 1000000 then
        return string.format("%.1fM", score / 1000000)
    elseif score >= 1000 then
        return string.format("%.1fk", score / 1000)
    else
        return tostring(score)
    end
end

-- Get formatted subgoal target for display
function RunState:get_formatted_target()
    local score = self.subgoal_target
    if score >= 1000000 then
        return string.format("%.1fM", score / 1000000)
    elseif score >= 1000 then
        return string.format("%.1fk", score / 1000)
    else
        return tostring(score)
    end
end

-- Get subgoal progress as percentage (0-1)
function RunState:get_subgoal_progress()
    if self.subgoal_target == 0 then
        return 1.0
    end
    return math.min(1.0, self.round_score / self.subgoal_target)
end

return RunState
