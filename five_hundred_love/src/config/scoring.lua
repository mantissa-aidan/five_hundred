-- Scoring Configuration for Roguelike Mode
-- Defines all scoring values, multipliers, and formulas

local ScoringConfig = {
    mode = "ROGUELIKE",

    -- Card base point values (before multipliers)
    -- These are applied when a card is played
    card_values = {
        [4]   = 10,    -- FOUR
        [5]   = 20,    -- FIVE
        [6]   = 30,    -- SIX
        [7]   = 40,    -- SEVEN
        [8]   = 50,    -- EIGHT
        [9]   = 100,   -- NINE
        [10]  = 150,   -- TEN
        [11]  = 200,   -- JACK
        [12]  = 300,   -- QUEEN
        [13]  = 400,   -- KING
        [14]  = 500,   -- ACE
        [100] = 1000,  -- JOKER
    },

    -- Multipliers
    trump_multiplier = 1.5,  -- Multiply card value by this if trump
    bower_multiplier = 2.0,  -- Extra multiplier for bowers (right/left jack)

    -- Trick scoring
    trick_base_points = 2000,  -- Base points awarded for winning a trick

    -- Contract scoring (multiplied by bid value, then by 100)
    -- Example: 7 Spades = 140 base bid value
    contract_success_multiplier = 3.0,  -- Multiply bid value by 3.0, then by 100
    contract_fail_multiplier = 0.5,     -- Reduced points, not negative

    -- Defense scoring (when defending against a contract)
    defense_success_multiplier = 2.0,  -- Multiply bid value by 2.0, then by 100
    defense_fail_multiplier = 0.3,     -- Reduced points

    -- Streak configurations
    streaks = {
        -- Consecutive tricks won (linear growth)
        consecutive_tricks = {
            curve = "LINEAR",
            base_multiplier = 1.0,
            increment = 0.2,  -- Each trick adds 0.2x (1.2x, 1.4x, 1.6x, ...)
        },

        -- Same suit played consecutively (exponential growth)
        same_suit_played = {
            curve = "EXPONENTIAL",
            base_multiplier = 1.0,
            exponent = 1.3,  -- Each consecutive suit: 1.0, 1.3, 1.69, 2.197, ...
        },

        -- Trump cards played in a row (threshold-based)
        trump_streak = {
            curve = "THRESHOLD",
            thresholds = {
                [3] = 1.5,  -- 3 trump cards: 1.5x
                [5] = 2.0,  -- 5 trump cards: 2.0x
                [7] = 3.0,  -- 7 trump cards: 3.0x
            },
        },

        -- High cards played in a row (J, Q, K, A, Joker)
        high_card_streak = {
            curve = "THRESHOLD",
            threshold_rank = 11,  -- JACK or higher
            thresholds = {
                [3] = 1.3,
                [5] = 1.8,
                [7] = 2.5,
            },
        },
    },

    -- Difficulty scaling
    difficulty = {
        curve_type = "EXPONENTIAL",  -- or "LINEAR"
        starting_target = 50000,
        exponential_multiplier = 1.5,  -- 1.5x per round
        linear_increment = 100000,  -- For linear mode: +100k per round
    },

    -- Powerup drop chances (0-1)
    powerup_drops = {
        trick_win = 0.10,         -- 10% chance on trick win
        round_end = 0.50,         -- 50% chance at round end
        contract_success = 0.80,  -- 80% on contract made
        streak_milestone = 1.0,   -- 100% at 5-trick streak
    },
}

-- Helper functions for calculating scores

-- Calculate card play points
function ScoringConfig.calculate_card_points(rank, is_trump, is_bower, modifiers)
    modifiers = modifiers or {}

    local base_value = ScoringConfig.card_values[rank] or 0
    local multiplier = 1.0

    -- Apply trump multiplier
    if is_trump then
        multiplier = multiplier * ScoringConfig.trump_multiplier
    end

    -- Apply bower multiplier
    if is_bower then
        multiplier = multiplier * ScoringConfig.bower_multiplier
    end

    -- Apply modifier multipliers (TODO: implement when modifiers are added)
    for _, mod in ipairs(modifiers) do
        if mod.apply_to_card then
            multiplier = multiplier * (mod.multiplier or 1.0)
        end
    end

    return math.floor(base_value * multiplier)
end

-- Calculate trick points
function ScoringConfig.calculate_trick_points(cards_in_trick, streak_multiplier, modifiers)
    modifiers = modifiers or {}
    streak_multiplier = streak_multiplier or 1.0

    -- Sum all card values in trick
    local card_sum = 0
    for _, card_points in ipairs(cards_in_trick) do
        card_sum = card_sum + card_points
    end

    -- Base trick bonus
    local total = ScoringConfig.trick_base_points + card_sum

    -- Apply streak multiplier
    total = total * streak_multiplier

    -- Apply modifiers (TODO: implement when modifiers are added)
    for _, mod in ipairs(modifiers) do
        if mod.apply_to_trick then
            total = total * (mod.multiplier or 1.0)
        end
    end

    return math.floor(total)
end

-- Calculate contract bonus
function ScoringConfig.calculate_contract_bonus(bid_value, success)
    local multiplier = success and ScoringConfig.contract_success_multiplier
                                or ScoringConfig.contract_fail_multiplier
    return math.floor(bid_value * multiplier * 100)
end

-- Calculate defense bonus
function ScoringConfig.calculate_defense_bonus(bid_value, success)
    local multiplier = success and ScoringConfig.defense_success_multiplier
                                or ScoringConfig.defense_fail_multiplier
    return math.floor(bid_value * multiplier * 100)
end

-- Calculate streak multiplier based on configuration
function ScoringConfig.get_streak_multiplier(streak_name, count)
    local config = ScoringConfig.streaks[streak_name]
    if not config then
        return 1.0
    end

    if config.curve == "LINEAR" then
        return config.base_multiplier + (config.increment * count)
    elseif config.curve == "EXPONENTIAL" then
        if count == 0 then
            return config.base_multiplier
        end
        return config.base_multiplier * math.pow(config.exponent, count)
    elseif config.curve == "THRESHOLD" then
        -- Find highest threshold met
        local multiplier = 1.0
        for threshold, mult in pairs(config.thresholds) do
            if count >= threshold and mult > multiplier then
                multiplier = mult
            end
        end
        return multiplier
    end

    return 1.0
end

return ScoringConfig
