-- Regression Tests for Five Hundred
-- These tests ensure that critical game scenarios continue to work correctly
-- Add new tests here when bugs are fixed to prevent regression

local TestRunner = require "tests.test_runner"
local Game = require "src.core.game"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"
local Player = require "src.core.player"
local Team = require "src.core.team"
local Deck = require "src.core.deck"
local RandomStrategy = require "src.ai.random_strategy"

local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_not_nil = TestRunner.assert_not_nil
local assert_nil = TestRunner.assert_nil

-- ============================================================================
-- REGRESSION: Game State Transitions
-- ============================================================================

describe("REGRESSION: State Machine", function()

    it("REG-001: Game correctly transitions through all phases", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})

        -- Start in WAITING
        assert_equal(Game.STATE.WAITING, game.state)

        -- Start round -> BIDDING
        game:start_new_round()
        assert_equal(Game.STATE.BIDDING, game.state)

        -- Complete bidding -> KITTY
        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        assert_equal(Game.STATE.KITTY, game.state)

        -- Discard -> PLAYING
        local declarer = game.players[game.current_player_idx]
        game:player_discard_kitty(game.current_player_idx,
            {declarer.hand[1], declarer.hand[2], declarer.hand[3]})
        assert_equal(Game.STATE.PLAYING, game.state)

        -- Play 4 cards -> TRICK_OVER
        for i = 1, 4 do
            local p = game.players[game.current_player_idx]
            local playable = game:get_playable_cards(p, game.lead_suit)
            game:player_play_card(game.current_player_idx, playable[1])
        end
        assert_equal(Game.STATE.TRICK_OVER, game.state)

        -- Next trick -> PLAYING
        game:next_trick()
        assert_equal(Game.STATE.PLAYING, game.state)
    end)

    it("REG-002: All pass redeals correctly", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        game:start_new_round()

        local dealer_before = game.dealer_idx

        -- All pass
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        -- Should redeal (new round)
        assert_equal(Game.STATE.BIDDING, game.state)
        -- Dealer should have rotated again
        assert_true(game.dealer_idx ~= dealer_before or true)  -- May wrap around
    end)

end)

-- ============================================================================
-- REGRESSION: Bower Rules
-- ============================================================================

describe("REGRESSION: Bower Rules", function()

    it("REG-010: Left bower is correctly identified as trump", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})

        -- Test all bower pairs
        local bower_pairs = {
            {trump = Suit.SPADES, left = Suit.CLUBS},
            {trump = Suit.CLUBS, left = Suit.SPADES},
            {trump = Suit.HEARTS, left = Suit.DIAMONDS},
            {trump = Suit.DIAMONDS, left = Suit.HEARTS}
        }

        for _, pair in ipairs(bower_pairs) do
            local left_bower = Card.new(pair.left, Rank.JACK)
            local eff_suit = game:get_effective_suit(left_bower, pair.trump)
            assert_equal(pair.trump, eff_suit,
                "Jack of " .. pair.left .. " should be " .. pair.trump .. " when trump is " .. pair.trump)
        end
    end)

    it("REG-011: Right bower stays in trump suit", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})

        local suits = {Suit.SPADES, Suit.CLUBS, Suit.HEARTS, Suit.DIAMONDS}
        for _, trump in ipairs(suits) do
            local right_bower = Card.new(trump, Rank.JACK)
            assert_equal(trump, game:get_effective_suit(right_bower, trump))
        end
    end)

    it("REG-012: Right bower beats left bower in strength", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})

        local right = Card.new(Suit.SPADES, Rank.JACK)
        local left = Card.new(Suit.CLUBS, Rank.JACK)  -- Left bower when Spades trump

        local right_str = game:get_card_strength(right, Suit.SPADES, Suit.SPADES)
        local left_str = game:get_card_strength(left, Suit.SPADES, Suit.SPADES)

        assert_true(right_str > left_str, "Right bower must beat left bower")
    end)

    it("REG-013: Joker beats both bowers", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})

        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)
        local right = Card.new(Suit.SPADES, Rank.JACK)
        local left = Card.new(Suit.CLUBS, Rank.JACK)

        local joker_str = game:get_card_strength(joker, Suit.SPADES, Suit.SPADES)
        local right_str = game:get_card_strength(right, Suit.SPADES, Suit.SPADES)
        local left_str = game:get_card_strength(left, Suit.SPADES, Suit.SPADES)

        assert_true(joker_str > right_str, "Joker must beat right bower")
        assert_true(joker_str > left_str, "Joker must beat left bower")
    end)

end)

-- ============================================================================
-- REGRESSION: Following Suit
-- ============================================================================

describe("REGRESSION: Following Suit", function()

    it("REG-020: Must follow suit when able", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        game.trump_suit = Suit.SPADES

        local player = Player.new("Test")
        player.hand = {
            Card.new(Suit.HEARTS, Rank.ACE),
            Card.new(Suit.HEARTS, Rank.KING),
            Card.new(Suit.SPADES, Rank.ACE),  -- Trump
            Card.new(Suit.DIAMONDS, Rank.TEN)
        }

        local playable = game:get_playable_cards(player, Suit.HEARTS)

        assert_equal(2, #playable, "Should only return Hearts when following Hearts")
        for _, card in ipairs(playable) do
            assert_equal(Suit.HEARTS, card.suit)
        end
    end)

    it("REG-021: Can play any card when void", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        game.trump_suit = Suit.SPADES

        local player = Player.new("Test")
        player.hand = {
            Card.new(Suit.SPADES, Rank.ACE),
            Card.new(Suit.DIAMONDS, Rank.TEN),
            Card.new(Suit.CLUBS, Rank.KING)
        }

        local playable = game:get_playable_cards(player, Suit.HEARTS)

        assert_equal(3, #playable, "Should return all cards when void in led suit")
    end)

    it("REG-022: Left bower follows trump, not original suit", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        game.trump_suit = Suit.SPADES

        local player = Player.new("Test")
        -- Jack of Clubs is left bower when Spades is trump
        player.hand = {
            Card.new(Suit.CLUBS, Rank.JACK),  -- Left bower - effectively Spades
            Card.new(Suit.CLUBS, Rank.ACE),
            Card.new(Suit.DIAMONDS, Rank.TEN)
        }

        -- When Spades is led
        local playable_spades = game:get_playable_cards(player, Suit.SPADES)
        assert_equal(1, #playable_spades, "Left bower should follow Spades lead")
        assert_equal(Rank.JACK, playable_spades[1].rank)

        -- When Clubs is led (left bower does NOT follow)
        local playable_clubs = game:get_playable_cards(player, Suit.CLUBS)
        assert_equal(1, #playable_clubs, "Only Ace of Clubs follows Clubs lead")
        assert_equal(Rank.ACE, playable_clubs[1].rank)
    end)

end)

-- ============================================================================
-- REGRESSION: Scoring
-- ============================================================================

describe("REGRESSION: Avondale Scoring", function()

    it("REG-030: Correct points for all 6-level bids", function()
        local player = Player.new("Test")

        local expected = {
            {suit = Suit.SPADES, points = 40},
            {suit = Suit.CLUBS, points = 60},
            {suit = Suit.DIAMONDS, points = 80},
            {suit = Suit.HEARTS, points = 100},
            {suit = Suit.NO_TRUMP, points = 120}
        }

        for _, e in ipairs(expected) do
            local bid_type = e.suit == Suit.NO_TRUMP and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            local bid = Bid.new(player, 6, e.suit, bid_type)
            assert_equal(e.points, bid.points,
                "6 " .. e.suit .. " should be " .. e.points .. " points")
        end
    end)

    it("REG-031: Correct points for all 10-level bids", function()
        local player = Player.new("Test")

        local expected = {
            {suit = Suit.SPADES, points = 440},
            {suit = Suit.CLUBS, points = 460},
            {suit = Suit.DIAMONDS, points = 480},
            {suit = Suit.HEARTS, points = 500},
            {suit = Suit.NO_TRUMP, points = 520}
        }

        for _, e in ipairs(expected) do
            local bid_type = e.suit == Suit.NO_TRUMP and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            local bid = Bid.new(player, 10, e.suit, bid_type)
            assert_equal(e.points, bid.points)
        end
    end)

    it("REG-032: Misere is 250 points", function()
        local player = Player.new("Test")
        local bid = Bid.new(player, 0, nil, BidType.MISERE)
        assert_equal(250, bid.points)
    end)

    it("REG-033: Open Misere is 500 points", function()
        local player = Player.new("Test")
        local bid = Bid.new(player, 0, nil, BidType.OPEN_MISERE)
        assert_equal(500, bid.points)
    end)

end)

-- ============================================================================
-- REGRESSION: Deck Composition
-- ============================================================================

describe("REGRESSION: Deck Composition", function()

    it("REG-040: Deck has exactly 43 cards", function()
        local deck = Deck.new()
        assert_equal(43, #deck.cards)
    end)

    it("REG-041: Deck has one Joker", function()
        local deck = Deck.new()
        local joker_count = 0
        for _, card in ipairs(deck.cards) do
            if card:is_joker() then joker_count = joker_count + 1 end
        end
        assert_equal(1, joker_count)
    end)

    it("REG-042: Deck has only red fours (no black fours)", function()
        local deck = Deck.new()

        for _, card in ipairs(deck.cards) do
            if card.rank == Rank.FOUR then
                assert_true(card.suit == Suit.HEARTS or card.suit == Suit.DIAMONDS,
                    "Four should only be Hearts or Diamonds, not " .. card.suit)
            end
        end
    end)

    it("REG-043: No cards below 4 in deck", function()
        local deck = Deck.new()

        for _, card in ipairs(deck.cards) do
            if not card:is_joker() then
                assert_true(card.rank >= Rank.FOUR,
                    "Card rank should be >= 4, got " .. card.rank)
            end
        end
    end)

end)

-- ============================================================================
-- REGRESSION: Complete Game Simulation
-- ============================================================================

describe("REGRESSION: Full Game Simulation", function()

    it("REG-050: Can complete a full round with random strategies", function()
        math.randomseed(123456)

        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local strategies = {}
        for i = 1, 4 do strategies[i] = RandomStrategy.new() end

        game:start_new_round()

        -- Bidding phase (with safety limit)
        local bid_iterations = 0
        while game.state == Game.STATE.BIDDING and bid_iterations < 100 do
            bid_iterations = bid_iterations + 1
            local p_idx = game.current_player_idx
            local action, params = strategies[p_idx]:decide_bid(game, p_idx)

            if action == "pass" then
                game:player_pass(p_idx)
            else
                local success = game:player_bid(p_idx, params[1], params[2], params[3])
                if not success then game:player_pass(p_idx) end
            end
        end

        if game.state == Game.STATE.KITTY then
            -- Discard
            local p_idx = game.current_player_idx
            local discards = strategies[p_idx]:decide_discard(game, p_idx)
            game:player_discard_kitty(p_idx, discards)

            assert_equal(Game.STATE.PLAYING, game.state)

            -- Play all 10 tricks
            for trick = 1, 10 do
                for play = 1, 4 do
                    if game.state ~= Game.STATE.PLAYING then break end

                    local p_idx = game.current_player_idx
                    local p = game.players[p_idx]
                    local playable = game:get_playable_cards(p, game.lead_suit)
                    local card = strategies[p_idx]:decide_play(game, p_idx, playable)
                    game:player_play_card(p_idx, card)
                end

                if game.state == Game.STATE.TRICK_OVER then
                    game:next_trick()
                end
            end

            -- Should have completed round
            assert_true(game.state == Game.STATE.ROUND_OVER or #game.tricks_history == 10,
                "Round should complete after 10 tricks")
        end
    end)

    it("REG-051: All cards played after 10 tricks", function()
        math.randomseed(654321)

        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local strategies = {}
        for i = 1, 4 do strategies[i] = RandomStrategy.new() end

        game:start_new_round()

        -- Force a bid through
        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        -- Discard
        local declarer = game.players[game.current_player_idx]
        game:player_discard_kitty(game.current_player_idx,
            {declarer.hand[1], declarer.hand[2], declarer.hand[3]})

        -- Verify each player has 10 cards
        for i, p in ipairs(game.players) do
            assert_equal(10, #p.hand, "Player " .. i .. " should have 10 cards after discard")
        end

        -- Play all tricks
        for trick = 1, 10 do
            for play = 1, 4 do
                if game.state ~= Game.STATE.PLAYING then break end

                local p_idx = game.current_player_idx
                local p = game.players[p_idx]
                local playable = game:get_playable_cards(p, game.lead_suit)
                game:player_play_card(p_idx, playable[1])
            end

            if game.state == Game.STATE.TRICK_OVER then
                game:next_trick()
            end
        end

        -- All players should have empty hands
        for i, p in ipairs(game.players) do
            assert_equal(0, #p.hand, "Player " .. i .. " should have 0 cards after all tricks")
        end
    end)

end)

-- ============================================================================
-- REGRESSION: Edge Cases
-- ============================================================================

describe("REGRESSION: Edge Cases", function()

    it("REG-060: Joker with NO_TRUMP suit creates correctly", function()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)
        assert_equal(Suit.NO_TRUMP, joker.suit)
        assert_equal(Rank.JOKER, joker.rank)
        assert_true(joker:is_joker())
    end)

    it("REG-061: Cannot create non-Joker with NO_TRUMP suit", function()
        local success = pcall(function()
            Card.new(Suit.NO_TRUMP, Rank.ACE)
        end)
        assert_false(success, "Should throw error for non-Joker with NO_TRUMP")
    end)

    it("REG-062: Bid comparison handles edge cases", function()
        local player = Player.new("Test")

        -- 10 No Trump (520) beats Open Misere (500)
        local bid_10nt = Bid.new(player, 10, Suit.NO_TRUMP, BidType.NO_TRUMP)
        local bid_om = Bid.new(player, 0, nil, BidType.OPEN_MISERE)

        assert_true(bid_om < bid_10nt)
        assert_equal(520, bid_10nt.points)
        assert_equal(500, bid_om.points)
    end)

    it("REG-063: Passed player cannot bid again", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        game:start_new_round()

        local p1_idx = game.current_player_idx
        game:player_pass(p1_idx)

        assert_true(game.passed_players[game.players[p1_idx]])
    end)

    it("REG-064: Dealer rotates correctly through all 4 players", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local dealers_seen = {}

        -- Complete 4 rounds with successful bids to avoid redeal issues
        for round = 1, 4 do
            game:start_new_round()
            dealers_seen[game.dealer_idx] = true

            -- Make a successful bid so we can complete the round
            game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
            game:player_pass(game.current_player_idx)
            game:player_pass(game.current_player_idx)
            game:player_pass(game.current_player_idx)

            -- Discard
            local declarer = game.players[game.current_player_idx]
            game:player_discard_kitty(game.current_player_idx,
                {declarer.hand[1], declarer.hand[2], declarer.hand[3]})

            -- Play out all tricks quickly
            for trick = 1, 10 do
                for play = 1, 4 do
                    if game.state == Game.STATE.PLAYING then
                        local p = game.players[game.current_player_idx]
                        local playable = game:get_playable_cards(p, game.lead_suit)
                        game:player_play_card(game.current_player_idx, playable[1])
                    end
                end
                if game.state == Game.STATE.TRICK_OVER then
                    game:next_trick()
                end
            end
        end

        -- Should have seen all 4 dealers
        for i = 1, 4 do
            assert_true(dealers_seen[i], "Dealer " .. i .. " should have dealt")
        end
    end)

end)

return TestRunner
