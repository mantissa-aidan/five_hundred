-- ScoringEngine.lua
-- Core scoring system for roguelike mode
-- Processes scoring events and updates RunState

local ScoringConfig = require "src.config.scoring"
local ModifierManager = require "src.core.modifier_manager"

local ScoringEngine = {}
ScoringEngine.__index = ScoringEngine

function ScoringEngine.new(run_state)
    local self = setmetatable({}, ScoringEngine)

    self.run_state = run_state
    self.current_trick_cards = {}  -- Store card points for current trick
    self.current_trick_plays = {}  -- Store full play info for snap detection

    -- Initialize modifier manager
    self.modifier_manager = ModifierManager.new(run_state)

    return self
end

-- Get the modifier manager (for external access)
function ScoringEngine:get_modifier_manager()
    return self.modifier_manager
end

-- Score a card being played
-- context = {card, player_id, is_trump, is_bower, player}
function ScoringEngine:score_card_played(context)
    local card = context.card
    local rank = card.rank
    local is_trump = context.is_trump or false
    local is_bower = context.is_bower or false

    -- Calculate base points from config
    local points = ScoringConfig.calculate_card_points(rank, is_trump, is_bower, {})

    -- Apply modifier bonuses to card scoring
    points = self.modifier_manager:apply_card_scoring(card, is_trump, is_bower, points)

    -- Store for trick calculation
    table.insert(self.current_trick_cards, points)

    -- Store play info for snap detection
    table.insert(self.current_trick_plays, {
        player = context.player or {index = context.player_id},
        card = card
    })

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

    -- Get ALL streak multipliers and combine them
    local consecutive_mult = ScoringConfig.get_streak_multiplier(
        "consecutive_tricks",
        self.run_state.streak_states.consecutive_tricks.count
    )

    local suit_mult = ScoringConfig.get_streak_multiplier(
        "same_suit_played",
        self.run_state.streak_states.same_suit_played.count
    )

    local trump_mult = ScoringConfig.get_streak_multiplier(
        "trump_streak",
        self.run_state.streak_states.trump_streak.count
    )

    local high_card_mult = ScoringConfig.get_streak_multiplier(
        "high_card_streak",
        self.run_state.streak_states.high_card_streak.count
    )

    -- Combine all multipliers (multiplicative stacking)
    local combined_multiplier = consecutive_mult * suit_mult * trump_mult * high_card_mult

    -- Calculate base trick points
    local points = ScoringConfig.calculate_trick_points(
        self.current_trick_cards,
        combined_multiplier,
        {}
    )

    -- Check for snap condition (matching partner's rank)
    local snap_triggered = self.modifier_manager:check_snap(self.current_trick_plays, 1)

    -- Apply modifier bonuses to trick scoring
    points = self.modifier_manager:apply_trick_scoring(
        self.current_trick_plays,
        combined_multiplier,
        points
    )

    -- Apply snap bonus if triggered
    if snap_triggered then
        points = points * 10
        self.snap_triggered = true  -- Flag for UI feedback
    else
        self.snap_triggered = false
    end

    -- Add to round score
    self.run_state:add_score(points)

    -- Update consecutive tricks streak
    self:update_trick_streak(winner_id)

    -- Clear trick data for next trick
    self.current_trick_cards = {}
    self.current_trick_plays = {}

    -- Update stats
    self.run_state.stats.total_tricks_won = self.run_state.stats.total_tricks_won + 1

    -- Tick modifier durations
    self.modifier_manager:tick("TRICK")

    return points
end

-- Score contract result
-- context = {bid_value, success, is_defending}
function ScoringEngine:score_contract(context)
    local bid_value = context.bid_value
    local success = context.success
    local is_defending = context.is_defending or false

    -- Calculate base contract points
    local points
    if is_defending then
        points = ScoringConfig.calculate_defense_bonus(bid_value, success)
    else
        points = ScoringConfig.calculate_contract_bonus(bid_value, success)
    end

    -- Apply modifier bonuses to contract scoring
    points = self.modifier_manager:apply_contract_scoring(bid_value, success, is_defending, points)

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

    -- Tick modifier durations at round end
    self.modifier_manager:tick("ROUND")

    return points
end

-- Update streak when a trick is won
-- Only counts consecutive wins by P1's team (Team A: players 1 and 3)
function ScoringEngine:update_trick_streak(winner_id)
    local streak = self.run_state.streak_states.consecutive_tricks

    -- Check if winner is on P1's team (Team A = players 1 and 3)
    local is_team_a = (winner_id == 1 or winner_id == 3)

    if is_team_a then
        -- Team A won, increment streak
        streak.count = streak.count + 1
        streak.player_id = winner_id
    else
        -- Opponent won, reset streak
        streak.count = 0
        streak.player_id = nil
    end

    -- Update in run state
    self.run_state:update_streak("consecutive_tricks", streak)
end

-- Update streaks based on card played
-- Only tracks P1's cards (player_id == 1)
function ScoringEngine:update_card_streaks(context)
    local card = context.card
    local is_trump = context.is_trump
    local player_id = context.player_id

    -- Increment stats for all players
    self.run_state.stats.total_cards_played = self.run_state.stats.total_cards_played + 1

    -- Only track streaks for P1
    if player_id ~= 1 then
        return
    end

    -- Suit streak: Track consecutive cards of same suit played by P1
    local suit_streak = self.run_state.streak_states.same_suit_played
    if suit_streak.suit == card.suit then
        suit_streak.count = suit_streak.count + 1
    else
        suit_streak.count = 1
        suit_streak.suit = card.suit
    end
    self.run_state:update_streak("same_suit_played", suit_streak)

    -- Trump streak: Track consecutive trump cards played by P1
    local trump_streak = self.run_state.streak_states.trump_streak
    if is_trump then
        trump_streak.count = trump_streak.count + 1
    else
        trump_streak.count = 0
    end
    self.run_state:update_streak("trump_streak", trump_streak)

    -- High card streak: Track consecutive high cards played by P1 (Jack or higher)
    local high_card_streak = self.run_state.streak_states.high_card_streak
    local is_high_card = (card.rank >= 11)  -- Jack=11, Queen=12, King=13, Ace=14, Joker=100
    if is_high_card then
        high_card_streak.count = high_card_streak.count + 1
    else
        high_card_streak.count = 0
    end
    self.run_state:update_streak("high_card_streak", high_card_streak)
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
