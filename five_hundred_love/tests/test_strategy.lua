-- Tests for AI Strategy modules
local TestRunner = require "tests.test_runner"
local Strategy = require "src.ai.strategy"
local RandomStrategy = require "src.ai.random_strategy"
local Game = require "src.core.game"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local BidType = BidModule.BidType

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_not_nil = TestRunner.assert_not_nil
local assert_error = TestRunner.assert_error
local assert_contains = TestRunner.assert_contains

-- Helper to create game and advance to specific state
local function create_game_in_bidding()
    local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
    game:start_new_round()
    return game
end

local function create_game_in_playing()
    local game = create_game_in_bidding()

    game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
    game:player_pass(game.current_player_idx)
    game:player_pass(game.current_player_idx)
    game:player_pass(game.current_player_idx)

    local declarer = game.players[game.current_player_idx]
    local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}
    game:player_discard_kitty(game.current_player_idx, discards)

    return game
end

describe("Strategy Base Class", function()

    it("throws error for unimplemented decide_bid", function()
        local strategy = Strategy.new()
        assert_error(function()
            strategy:decide_bid({}, 1)
        end)
    end)

    it("throws error for unimplemented decide_play", function()
        local strategy = Strategy.new()
        assert_error(function()
            strategy:decide_play({}, 1, {})
        end)
    end)

    it("throws error for unimplemented decide_discard", function()
        local strategy = Strategy.new()
        assert_error(function()
            strategy:decide_discard({}, 1)
        end)
    end)

    it("requires_input returns false by default", function()
        local strategy = Strategy.new()
        assert_false(strategy:requires_input())
    end)

end)

describe("RandomStrategy", function()

    it("can be instantiated", function()
        local strategy = RandomStrategy.new()
        assert_not_nil(strategy)
    end)

    it("requires_input returns false", function()
        local strategy = RandomStrategy.new()
        assert_false(strategy:requires_input())
    end)

end)

describe("RandomStrategy Bidding", function()

    it("returns pass or bid action", function()
        math.randomseed(os.time())
        local strategy = RandomStrategy.new()
        local game = create_game_in_bidding()

        local action, params = strategy:decide_bid(game, game.current_player_idx)

        assert_true(action == "pass" or action == "bid",
            "Action should be 'pass' or 'bid', got: " .. tostring(action))
    end)

    it("bid action includes valid parameters", function()
        math.randomseed(12345)  -- Seed for reproducibility
        local strategy = RandomStrategy.new()
        local game = create_game_in_bidding()

        -- Try multiple times to get a bid
        local got_bid = false
        for i = 1, 50 do
            local action, params = strategy:decide_bid(game, game.current_player_idx)
            if action == "bid" then
                got_bid = true
                assert_not_nil(params, "Bid should have parameters")
                assert_equal(3, #params, "Bid params should be {tricks, suit, bid_type}")
                assert_true(params[1] >= 6 and params[1] <= 10, "Tricks should be 6-10")
                break
            end
        end
        -- Note: It's possible (though unlikely with 70% pass rate) to get all passes
    end)

    it("only returns valid bids higher than current", function()
        math.randomseed(42)
        local strategy = RandomStrategy.new()
        local game = create_game_in_bidding()

        -- Make a high bid first
        game:player_bid(game.current_player_idx, 8, Suit.HEARTS, BidType.SUIT_TRUMP)

        for i = 1, 20 do
            local action, params = strategy:decide_bid(game, game.current_player_idx)
            if action == "bid" then
                -- Create the bid to check points
                local player = game.players[game.current_player_idx]
                local test_bid = BidModule.Bid.new(player, params[1], params[2], params[3])
                assert_true(test_bid.points > game.highest_bid.points,
                    "Bid should be higher than current highest")
            end
        end
    end)

end)

describe("RandomStrategy Card Play", function()

    it("returns a card from playable cards", function()
        local strategy = RandomStrategy.new()
        local game = create_game_in_playing()

        local player_idx = game.current_player_idx
        local player = game.players[player_idx]
        local playable = game:get_playable_cards(player, game.lead_suit)

        local card = strategy:decide_play(game, player_idx, playable)

        assert_not_nil(card)
        assert_contains(playable, card, "Played card should be in playable cards")
    end)

    it("consistently returns valid cards", function()
        local strategy = RandomStrategy.new()
        local game = create_game_in_playing()

        for i = 1, 10 do
            local player_idx = game.current_player_idx
            local player = game.players[player_idx]
            local playable = game:get_playable_cards(player, game.lead_suit)

            local card = strategy:decide_play(game, player_idx, playable)
            assert_contains(playable, card)
        end
    end)

end)

describe("RandomStrategy Discard", function()

    it("returns 3 cards", function()
        local strategy = RandomStrategy.new()
        local game = create_game_in_bidding()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer_idx = game.current_player_idx
        local discards = strategy:decide_discard(game, declarer_idx)

        assert_not_nil(discards)
        assert_equal(3, #discards)
    end)

    it("returns cards from player hand", function()
        local strategy = RandomStrategy.new()
        local game = create_game_in_bidding()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer_idx = game.current_player_idx
        local declarer = game.players[declarer_idx]
        local discards = strategy:decide_discard(game, declarer_idx)

        for _, discard in ipairs(discards) do
            local found = false
            for _, hand_card in ipairs(declarer.hand) do
                if hand_card == discard then
                    found = true
                    break
                end
            end
            assert_true(found, "Discard should be from player's hand")
        end
    end)

end)

describe("Strategy Integration", function()

    it("can play a full bidding round with RandomStrategy", function()
        math.randomseed(54321)
        local game = create_game_in_bidding()
        local strategies = {}
        for i = 1, 4 do
            strategies[i] = RandomStrategy.new()
        end

        local max_iterations = 100
        local iteration = 0

        while game.state == Game.STATE.BIDDING and iteration < max_iterations do
            iteration = iteration + 1
            local player_idx = game.current_player_idx
            local action, params = strategies[player_idx]:decide_bid(game, player_idx)

            if action == "pass" then
                game:player_pass(player_idx)
            elseif action == "bid" then
                local success = game:player_bid(player_idx, params[1], params[2], params[3])
                if not success then
                    game:player_pass(player_idx)
                end
            end
        end

        assert_true(iteration < max_iterations, "Bidding should complete")
        assert_true(game.state == Game.STATE.KITTY or game.state == Game.STATE.BIDDING,
            "Should end in KITTY or restart BIDDING")
    end)

    it("can play multiple tricks with RandomStrategy", function()
        math.randomseed(98765)
        local game = create_game_in_playing()
        local strategies = {}
        for i = 1, 4 do
            strategies[i] = RandomStrategy.new()
        end

        -- Play 3 tricks
        for trick = 1, 3 do
            for play = 1, 4 do
                if game.state ~= Game.STATE.PLAYING then break end

                local player_idx = game.current_player_idx
                local player = game.players[player_idx]
                local playable = game:get_playable_cards(player, game.lead_suit)

                local card = strategies[player_idx]:decide_play(game, player_idx, playable)
                game:player_play_card(player_idx, card)
            end

            if game.state == Game.STATE.TRICK_OVER then
                game:next_trick()
            end
        end

        assert_true(#game.tricks_history >= 3, "Should have played at least 3 tricks")
    end)

end)

return TestRunner
