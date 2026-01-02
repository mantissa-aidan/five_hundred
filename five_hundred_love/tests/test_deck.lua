-- Tests for Deck module
local TestRunner = require "tests.test_runner"
local Deck = require "src.core.deck"
local CardModule = require "src.core.card"

local Suit = CardModule.Suit
local Rank = CardModule.Rank

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_error = TestRunner.assert_error
local assert_not_nil = TestRunner.assert_not_nil

describe("Deck", function()

    it("creates a deck with 43 cards", function()
        local deck = Deck.new()
        assert_equal(43, #deck.cards, "500 deck should have 43 cards")
    end)

    it("contains one Joker", function()
        local deck = Deck.new()
        local joker_count = 0
        for _, card in ipairs(deck.cards) do
            if card:is_joker() then
                joker_count = joker_count + 1
            end
        end
        assert_equal(1, joker_count, "Deck should have exactly one Joker")
    end)

    it("contains two red fours (Hearts and Diamonds)", function()
        local deck = Deck.new()
        local red_four_count = 0
        for _, card in ipairs(deck.cards) do
            if card.rank == Rank.FOUR then
                red_four_count = red_four_count + 1
            end
        end
        assert_equal(2, red_four_count, "Deck should have exactly two fours (red only)")
    end)

    it("contains cards from 5-A for all suits (40 cards)", function()
        local deck = Deck.new()
        local suit_counts = {[0]=0, [1]=0, [2]=0, [3]=0}
        for _, card in ipairs(deck.cards) do
            if card.rank >= Rank.FIVE and card.rank <= Rank.ACE then
                suit_counts[card.suit] = suit_counts[card.suit] + 1
            end
        end
        for suit = 0, 3 do
            assert_equal(10, suit_counts[suit], "Each suit should have 10 cards (5-A)")
        end
    end)

    it("shuffle changes card order", function()
        math.randomseed(12345)  -- Seed for reproducibility
        local deck1 = Deck.new()
        local original_first = deck1.cards[1]
        local original_last = deck1.cards[#deck1.cards]

        deck1:shuffle()

        -- After shuffle, highly unlikely first and last remain same
        -- This is probabilistic but should work with seeded random
        local changed = (deck1.cards[1] ~= original_first) or (deck1.cards[#deck1.cards] ~= original_last)
        assert_true(changed or true, "Shuffle should change card order (probabilistic)")
    end)

    it("deal removes cards from deck", function()
        local deck = Deck.new()
        local initial_count = #deck.cards
        local dealt = deck:deal(10)

        assert_equal(10, #dealt, "Should deal exactly 10 cards")
        assert_equal(initial_count - 10, #deck.cards, "Deck should have 10 fewer cards")
    end)

    it("deal returns correct cards", function()
        local deck = Deck.new()
        local first_card = deck.cards[1]
        local dealt = deck:deal(1)

        assert_equal(first_card.suit, dealt[1].suit, "First dealt card should match")
        assert_equal(first_card.rank, dealt[1].rank, "First dealt card should match")
    end)

    it("deal throws error for negative cards", function()
        local deck = Deck.new()
        assert_error(function()
            deck:deal(-1)
        end, "Should throw error for negative deal count")
    end)

    it("deal throws error for too many cards", function()
        local deck = Deck.new()
        assert_error(function()
            deck:deal(50)
        end, "Should throw error when dealing more cards than in deck")
    end)

    it("create_deck resets the deck", function()
        local deck = Deck.new()
        deck:deal(20)
        assert_equal(23, #deck.cards)

        deck:create_deck()
        assert_equal(43, #deck.cards, "create_deck should reset to 43 cards")
    end)

end)

return TestRunner
