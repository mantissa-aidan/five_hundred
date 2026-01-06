-- ScoringEngine.lua
-- Core scoring system for roguelike mode
-- Processes scoring events and updates RunState

local ScoringConfig = require "src.config.scoring"

local ScoringEngine = {}
ScoringEngine.__index = ScoringEngine

function ScoringEngine.new(run_state)
    local self = setmetatable({}, ScoringEngine)

    self.run_state = run_state
    self.current_trick_cards = {}  -- Store card points for current trick

    return self
end

-- Score a card being played
-- context = {card, player_id, is_trump, is_bower}
function ScoringEngine:score_card_played(context)
    local rank = context.card.rank
    local is_trump = context.is_trump or false
    local is_bower = context.is_bower or false

    -- Get active modifiers for card scoring
    local modifiers = self.run_state:get_modifiers_by_type("SCORING")

    -- Calculate points
    local points = ScoringConfig.calculate_card_points(rank, is_trump, is_bower, modifiers)

    -- Store for trick calculation
    table.insert(self.current_trick_cards, points)

    -- Add to round score
    self.run_state:add_score(points)

    -- Update streaks (if applicable)
    self:update_card_streaks(context)

    return points
end

-- Score a trick being won
-- context = {winner_player_id, trick_number}
function ScoringEngine:score_trick_won(context)
    local winner_id = context.winner_player_id

    -- Get streak multiplier
    local streak_count = self.run_state.streak_states.consecutive_tricks.count
    local streak_multiplier = ScoringConfig.get_streak_multiplier("consecutive_tricks", streak_count)

    -- Get active modifiers
    local modifiers = self.run_state:get_modifiers_by_type("SCORING")

    -- Calculate trick points
    local points = ScoringConfig.calculate_trick_points(
        self.current_trick_cards,
        streak_multiplier,
        modifiers
    )

    -- Add to round score
    self.run_state:add_score(points)

    -- Update consecutive tricks streak
    self:update_trick_streak(winner_id)

    -- Clear trick cards for next trick
    self.current_trick_cards = {}

    -- Update stats
    self.run_state.stats.total_tricks_won = self.run_state.stats.total_tricks_won + 1

    return points
end

-- Score contract result
-- context = {bid_value, success, is_defending}
function ScoringEngine:score_contract(context)
    local bid_value = context.bid_value
    local success = context.success
    local is_defending = context.is_defending or false

    local points
    if is_defending then
        points = ScoringConfig.calculate_defense_bonus(bid_value, success)
    else
        points = ScoringConfig.calculate_contract_bonus(bid_value, success)
    end

    -- Add to round score
    self.run_state:add_score(points)

    -- Update stats
    if not is_defending then
        if success then
            self.run_state.stats.contracts_made = self.run_state.stats.contracts_made + 1
        else
            self.run_state.stats.contracts_failed = self.run_state.stats.contracts_failed + 1
        end
    end

    return points
end

-- Update streak when a trick is won
function ScoringEngine:update_trick_streak(winner_id)
    local streak = self.run_state.streak_states.consecutive_tricks

    if streak.player_id == winner_id then
        -- Same player won again, increment streak
        streak.count = streak.count + 1
    else
        -- Different player won, reset streak
        streak.count = 1
        streak.player_id = winner_id
    end

    -- Update in run state
    self.run_state:update_streak("consecutive_tricks", streak)
end

-- Update streaks based on card played
function ScoringEngine:update_card_streaks(context)
    -- TODO: Implement suit streak tracking
    -- TODO: Implement trump streak tracking
    -- TODO: Implement high card streak tracking

    -- For now, just increment stats
    self.run_state.stats.total_cards_played = self.run_state.stats.total_cards_played + 1
end

-- Check if subgoal is met at end of round
function ScoringEngine:check_subgoal()
    if self.run_state:is_subgoal_met() then
        -- Subgoal met, advance to next round
        return true, "Subgoal met!"
    else
        -- Subgoal failed, game over
        self.run_state:trigger_game_over(
            string.format("Failed to meet subgoal: %d / %d",
                self.run_state.round_score,
                self.run_state.subgoal_target)
        )
        return false, "Game Over"
    end
end

-- Reset engine for new round
function ScoringEngine:new_round()
    self.current_trick_cards = {}
    self.run_state:advance_round()
end

-- Get scoring summary for display
function ScoringEngine:get_score_summary()
    return {
        total_score = self.run_state.total_score,
        round_score = self.run_state.round_score,
        subgoal_target = self.run_state.subgoal_target,
        current_round = self.run_state.current_round,
        progress = self.run_state:get_subgoal_progress(),
        consecutive_streak = self.run_state.streak_states.consecutive_tricks.count,
        is_game_over = self.run_state.is_game_over,
    }
end

-- Get detailed stats for end game screen
function ScoringEngine:get_detailed_stats()
    return {
        total_score = self.run_state.total_score,
        rounds_survived = self.run_state.current_round,
        total_tricks_won = self.run_state.stats.total_tricks_won,
        contracts_made = self.run_state.stats.contracts_made,
        contracts_failed = self.run_state.stats.contracts_failed,
        highest_streak = self.run_state.stats.highest_streak,
        powerups_collected = self.run_state.stats.powerups_collected,
        game_over_reason = self.run_state.game_over_reason,
    }
end

return ScoringEngine
