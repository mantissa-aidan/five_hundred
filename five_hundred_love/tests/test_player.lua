-- Tests for Player module
local TestRunner = require "tests.test_runner"
local Player = require "src.core.player"
local CardModule = require "src.core.card"

local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_error = TestRunner.assert_error

describe("Player", function()

    it("creates a player with name", function()
        local player = Player.new("Alice")
        assert_equal("Alice", player.name)
        assert_equal(0, player.score)
        assert_equal(0, player.tricks_won_this_round)
        assert_equal(0, #player.hand)
    end)

    it("adds single card to hand", function()
        local player = Player.new("Alice")
        local card = Card.new(Suit.HEARTS, Rank.ACE)

        player:add_card_to_hand(card)

        assert_equal(1, #player.hand)
        assert_equal(card, player.hand[1])
    end)

    it("adds multiple cards to hand", function()
        local player = Player.new("Alice")
        local cards = {
            Card.new(Suit.HEARTS, Rank.ACE),
            Card.new(Suit.SPADES, Rank.KING),
            Card.new(Suit.DIAMONDS, Rank.QUEEN)
        }

        player:add_cards_to_hand(cards)

        assert_equal(3, #player.hand)
    end)

    it("plays card from hand and removes it", function()
        local player = Player.new("Alice")
        local card1 = Card.new(Suit.HEARTS, Rank.ACE)
        local card2 = Card.new(Suit.SPADES, Rank.KING)

        player:add_card_to_hand(card1)
        player:add_card_to_hand(card2)
        assert_equal(2, #player.hand)

        local played = player:play_card(card1)

        assert_equal(card1.suit, played.suit)
        assert_equal(card1.rank, played.rank)
        assert_equal(1, #player.hand)
        assert_equal(card2, player.hand[1])
    end)

    it("throws error when playing card not in hand", function()
        local player = Player.new("Alice")
        local card_in_hand = Card.new(Suit.HEARTS, Rank.ACE)
        local card_not_in_hand = Card.new(Suit.SPADES, Rank.KING)

        player:add_card_to_hand(card_in_hand)

        assert_error(function()
            player:play_card(card_not_in_hand)
        end, "Should throw error for card not in hand")
    end)

    it("sorts hand by suit then rank", function()
        local player = Player.new("Alice")
        -- Add cards in random order
        player:add_card_to_hand(Card.new(Suit.HEARTS, Rank.FIVE))
        player:add_card_to_hand(Card.new(Suit.CLUBS, Rank.ACE))
        player:add_card_to_hand(Card.new(Suit.CLUBS, Rank.KING))
        player:add_card_to_hand(Card.new(Suit.HEARTS, Rank.ACE))

        player:sort_hand()

        -- Clubs (0) should come before Hearts (2)
        assert_equal(Suit.CLUBS, player.hand[1].suit)
        assert_equal(Suit.CLUBS, player.hand[2].suit)
        -- Higher rank first within suit
        assert_equal(Rank.ACE, player.hand[1].rank)
        assert_equal(Rank.KING, player.hand[2].rank)
        -- Then Hearts
        assert_equal(Suit.HEARTS, player.hand[3].suit)
        assert_equal(Suit.HEARTS, player.hand[4].suit)
    end)

    it("resets for new round", function()
        local player = Player.new("Alice")
        player:add_card_to_hand(Card.new(Suit.HEARTS, Rank.ACE))
        player.tricks_won_this_round = 3

        player:reset_for_new_round()

        assert_equal(0, #player.hand)
        assert_equal(0, player.tricks_won_this_round)
    end)

    it("increments score correctly", function()
        local player = Player.new("Alice")
        assert_equal(0, player.score)

        player:increment_score(100)
        assert_equal(100, player.score)

        player:increment_score(-50)
        assert_equal(50, player.score)
    end)

    it("increments tricks won", function()
        local player = Player.new("Alice")
        assert_equal(0, player.tricks_won_this_round)

        player:increment_tricks_won()
        assert_equal(1, player.tricks_won_this_round)

        player:increment_tricks_won()
        assert_equal(2, player.tricks_won_this_round)
    end)

    it("converts to string with name and score", function()
        local player = Player.new("Alice")
        player:increment_score(150)

        local str = tostring(player)
        assert_true(string.find(str, "Alice") ~= nil)
        assert_true(string.find(str, "150") ~= nil)
    end)

end)

return TestRunner
