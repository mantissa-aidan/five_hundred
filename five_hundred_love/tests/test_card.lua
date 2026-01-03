-- Tests for Card module
local TestRunner = require "tests.test_runner"
local CardModule = require "src.core.card"

local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_error = TestRunner.assert_error

describe("Card", function()

    it("creates a standard card correctly", function()
        local card = Card.new(Suit.SPADES, Rank.ACE)
        assert_equal(Suit.SPADES, card.suit)
        assert_equal(Rank.ACE, card.rank)
        assert_false(card:is_joker())
    end)

    it("creates a Joker correctly", function()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)
        assert_equal(Suit.NO_TRUMP, joker.suit)
        assert_equal(Rank.JOKER, joker.rank)
        assert_true(joker:is_joker())
    end)

    it("auto-corrects Joker suit to NO_TRUMP", function()
        local joker = Card.new(Suit.HEARTS, Rank.JOKER)
        assert_equal(Suit.NO_TRUMP, joker.suit, "Joker should have NO_TRUMP suit")
        assert_true(joker:is_joker())
    end)

    it("throws error for non-Joker with NO_TRUMP suit", function()
        assert_error(function()
            Card.new(Suit.NO_TRUMP, Rank.ACE)
        end, "Should throw error for regular card with NO_TRUMP suit")
    end)

    it("compares cards for equality", function()
        local card1 = Card.new(Suit.HEARTS, Rank.KING)
        local card2 = Card.new(Suit.HEARTS, Rank.KING)
        local card3 = Card.new(Suit.CLUBS, Rank.KING)

        assert_true(card1 == card2, "Same cards should be equal")
        assert_false(card1 == card3, "Different suit cards should not be equal")
    end)

    it("converts to string correctly", function()
        local card = Card.new(Suit.DIAMONDS, Rank.TEN)
        local str = tostring(card)
        assert_true(string.find(str, "Ten") ~= nil, "Should contain rank name")
        assert_true(string.find(str, "Diamonds") ~= nil, "Should contain suit name")
    end)

    it("Joker converts to string as 'Joker'", function()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)
        assert_equal("Joker", tostring(joker))
    end)

end)

describe("Suit", function()

    it("has correct enum values", function()
        assert_equal(0, Suit.CLUBS)
        assert_equal(1, Suit.DIAMONDS)
        assert_equal(2, Suit.HEARTS)
        assert_equal(3, Suit.SPADES)
        assert_equal(4, Suit.NO_TRUMP)
    end)

end)

describe("Rank", function()

    it("has correct enum values", function()
        assert_equal(4, Rank.FOUR)
        assert_equal(5, Rank.FIVE)
        assert_equal(10, Rank.TEN)
        assert_equal(11, Rank.JACK)
        assert_equal(14, Rank.ACE)
        assert_equal(100, Rank.JOKER)
    end)

end)

return TestRunner
