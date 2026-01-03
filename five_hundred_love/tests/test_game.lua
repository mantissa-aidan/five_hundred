-- Tests for Game module
local TestRunner = require "tests.test_runner"
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
local assert_nil = TestRunner.assert_nil
local assert_not_nil = TestRunner.assert_not_nil
local assert_error = TestRunner.assert_error

-- Helper to create a fresh game
local function create_game()
    return Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
end

describe("Game Initialization", function()

    it("creates a game with 4 players", function()
        local game = create_game()
        assert_equal(4, #game.players)
        assert_equal("P1", game.players[1].name)
        assert_equal("P4", game.players[4].name)
    end)

    it("creates a game with 2 teams", function()
        local game = create_game()
        assert_equal(2, #game.teams)
        assert_equal("Team A", game.teams[1].name)
        assert_equal("Team B", game.teams[2].name)
    end)

    it("assigns players to correct teams", function()
        local game = create_game()
        -- Team 1: P1, P3  Team 2: P2, P4
        assert_equal(game.players[1], game.teams[1].players[1])
        assert_equal(game.players[3], game.teams[1].players[2])
        assert_equal(game.players[2], game.teams[2].players[1])
        assert_equal(game.players[4], game.teams[2].players[2])
    end)

    it("starts in WAITING state", function()
        local game = create_game()
        assert_equal(Game.STATE.WAITING, game.state)
    end)

    it("initializes with nil winning bid and trump", function()
        local game = create_game()
        assert_nil(game.winning_bid)
        assert_nil(game.trump_suit)
    end)

end)

describe("Game States", function()

    it("has all required states", function()
        assert_not_nil(Game.STATE.WAITING)
        assert_not_nil(Game.STATE.BIDDING)
        assert_not_nil(Game.STATE.KITTY)
        assert_not_nil(Game.STATE.PLAYING)
        assert_not_nil(Game.STATE.TRICK_OVER)
        assert_not_nil(Game.STATE.ROUND_OVER)
        assert_not_nil(Game.STATE.GAME_OVER)
    end)

end)

describe("Dealing Cards", function()

    it("deals 10 cards to each player", function()
        local game = create_game()
        game:deal_cards()

        for i, player in ipairs(game.players) do
            assert_equal(10, #player.hand, "Player " .. i .. " should have 10 cards")
        end
    end)

    it("creates a kitty of 3 cards", function()
        local game = create_game()
        game:deal_cards()
        assert_equal(3, #game.kitty)
    end)

    it("deals all 43 cards", function()
        local game = create_game()
        game:deal_cards()

        local total = #game.kitty
        for _, player in ipairs(game.players) do
            total = total + #player.hand
        end
        assert_equal(43, total)
    end)

    it("deals unique cards", function()
        local game = create_game()
        game:deal_cards()

        local seen = {}
        local function check_card(card)
            local key = card.suit .. "-" .. card.rank
            if seen[key] then
                error("Duplicate card found: " .. tostring(card))
            end
            seen[key] = true
        end

        for _, card in ipairs(game.kitty) do check_card(card) end
        for _, player in ipairs(game.players) do
            for _, card in ipairs(player.hand) do check_card(card) end
        end
    end)

end)

describe("Starting New Round", function()

    it("transitions to BIDDING state", function()
        local game = create_game()
        game:start_new_round()
        assert_equal(Game.STATE.BIDDING, game.state)
    end)

    it("rotates dealer", function()
        local game = create_game()
        local initial_dealer = game.dealer_idx

        game:start_new_round()

        assert_equal((initial_dealer % 4) + 1, game.dealer_idx)
    end)

    it("sets current player to left of dealer", function()
        local game = create_game()
        game:start_new_round()

        -- Dealer becomes 2 (after rotation from 1)
        -- Current player should be left of dealer, which is 3
        assert_equal((game.dealer_idx % 4) + 1, game.current_player_idx)
    end)

    it("resets bidding state", function()
        local game = create_game()
        game.highest_bid = "some_old_bid"
        game.winning_bid = "some_old_bid"

        game:start_new_round()

        assert_nil(game.highest_bid)
        assert_nil(game.winning_bid)
        assert_equal(0, game.consecutive_passes)
    end)

end)

describe("Effective Suit Calculation", function()

    it("returns actual suit for non-trump games", function()
        local game = create_game()
        game.trump_suit = nil

        local card = Card.new(Suit.HEARTS, Rank.ACE)
        assert_equal(Suit.HEARTS, game:get_effective_suit(card, nil))
    end)

    it("returns actual suit for cards in No Trump", function()
        local game = create_game()
        local card = Card.new(Suit.HEARTS, Rank.JACK)

        assert_equal(Suit.HEARTS, game:get_effective_suit(card, Suit.NO_TRUMP))
    end)

    it("returns trump for Joker in suit games", function()
        local game = create_game()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)

        assert_equal(Suit.SPADES, game:get_effective_suit(joker, Suit.SPADES))
        assert_equal(Suit.HEARTS, game:get_effective_suit(joker, Suit.HEARTS))
    end)

    it("returns NO_TRUMP for Joker in No Trump games", function()
        local game = create_game()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)

        assert_equal(Suit.NO_TRUMP, game:get_effective_suit(joker, Suit.NO_TRUMP))
    end)

    it("left bower is considered trump suit", function()
        local game = create_game()
        -- When Spades is trump, Jack of Clubs is left bower
        local jack_clubs = Card.new(Suit.CLUBS, Rank.JACK)

        assert_equal(Suit.SPADES, game:get_effective_suit(jack_clubs, Suit.SPADES))
    end)

    it("right bower stays in trump suit", function()
        local game = create_game()
        local jack_spades = Card.new(Suit.SPADES, Rank.JACK)

        assert_equal(Suit.SPADES, game:get_effective_suit(jack_spades, Suit.SPADES))
    end)

    it("non-jack cards keep original suit even when trump", function()
        local game = create_game()
        local ace_hearts = Card.new(Suit.HEARTS, Rank.ACE)

        assert_equal(Suit.HEARTS, game:get_effective_suit(ace_hearts, Suit.SPADES))
    end)

end)

describe("Card Strength Calculation", function()

    it("Joker is always strongest", function()
        local game = create_game()
        local joker = Card.new(Suit.NO_TRUMP, Rank.JOKER)

        local strength = game:get_card_strength(joker, Suit.HEARTS, Suit.SPADES)
        assert_equal(1000, strength)
    end)

    it("right bower beats left bower", function()
        local game = create_game()
        local right = Card.new(Suit.SPADES, Rank.JACK)
        local left = Card.new(Suit.CLUBS, Rank.JACK)  -- Left bower when Spades is trump

        local right_strength = game:get_card_strength(right, Suit.SPADES, Suit.SPADES)
        local left_strength = game:get_card_strength(left, Suit.SPADES, Suit.SPADES)

        assert_true(right_strength > left_strength, "Right bower should beat left bower")
    end)

    it("trump beats led suit", function()
        local game = create_game()
        local trump_card = Card.new(Suit.SPADES, Rank.FIVE)
        local led_ace = Card.new(Suit.HEARTS, Rank.ACE)

        local trump_strength = game:get_card_strength(trump_card, Suit.HEARTS, Suit.SPADES)
        local led_strength = game:get_card_strength(led_ace, Suit.HEARTS, Suit.SPADES)

        assert_true(trump_strength > led_strength, "Any trump should beat led suit")
    end)

    it("led suit beats off suit", function()
        local game = create_game()
        local led_card = Card.new(Suit.HEARTS, Rank.FIVE)
        local off_ace = Card.new(Suit.DIAMONDS, Rank.ACE)

        local led_strength = game:get_card_strength(led_card, Suit.HEARTS, Suit.SPADES)
        local off_strength = game:get_card_strength(off_ace, Suit.HEARTS, Suit.SPADES)

        assert_true(led_strength > off_strength, "Led suit should beat off suit")
    end)

    it("higher rank beats lower rank in same suit", function()
        local game = create_game()
        local ace = Card.new(Suit.HEARTS, Rank.ACE)
        local five = Card.new(Suit.HEARTS, Rank.FIVE)

        local ace_strength = game:get_card_strength(ace, Suit.HEARTS, Suit.SPADES)
        local five_strength = game:get_card_strength(five, Suit.HEARTS, Suit.SPADES)

        assert_true(ace_strength > five_strength)
    end)

end)

describe("Playable Cards", function()

    it("returns all cards when leading", function()
        local game = create_game()
        game:deal_cards()
        local player = game.players[1]

        local playable = game:get_playable_cards(player, nil)
        assert_equal(#player.hand, #playable)
    end)

    it("must follow suit when able", function()
        local game = create_game()
        local player = game.players[1]
        player.hand = {
            Card.new(Suit.HEARTS, Rank.ACE),
            Card.new(Suit.HEARTS, Rank.KING),
            Card.new(Suit.SPADES, Rank.ACE),
        }
        game.trump_suit = Suit.SPADES

        local playable = game:get_playable_cards(player, Suit.HEARTS)

        assert_equal(2, #playable, "Should only return hearts")
        for _, card in ipairs(playable) do
            assert_equal(Suit.HEARTS, card.suit)
        end
    end)

    it("can play any card when void in led suit", function()
        local game = create_game()
        local player = game.players[1]
        player.hand = {
            Card.new(Suit.SPADES, Rank.ACE),
            Card.new(Suit.CLUBS, Rank.KING),
        }
        game.trump_suit = Suit.SPADES

        local playable = game:get_playable_cards(player, Suit.HEARTS)

        assert_equal(2, #playable, "Should return all cards when void")
    end)

end)

describe("Bidding Actions", function()

    it("accepts valid first bid", function()
        local game = create_game()
        game:start_new_round()
        local bidder_idx = game.current_player_idx

        local success, err = game:player_bid(bidder_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        assert_true(success, err)
        assert_not_nil(game.highest_bid)
        assert_equal(40, game.highest_bid.points)
    end)

    it("rejects bid when not current player", function()
        local game = create_game()
        game:start_new_round()
        local wrong_player = (game.current_player_idx % 4) + 1

        local success, err = game:player_bid(wrong_player, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        assert_false(success)
    end)

    it("rejects lower bid than current highest", function()
        local game = create_game()
        game:start_new_round()

        -- First player bids 6 Clubs (60 points)
        game:player_bid(game.current_player_idx, 6, Suit.CLUBS, BidType.SUIT_TRUMP)

        -- Second player tries 6 Spades (40 points)
        local success, err = game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        assert_false(success)
    end)

    it("accepts higher bid", function()
        local game = create_game()
        game:start_new_round()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        local success = game:player_bid(game.current_player_idx, 6, Suit.CLUBS, BidType.SUIT_TRUMP)

        assert_true(success)
        assert_equal(60, game.highest_bid.points)
    end)

    it("player can pass", function()
        local game = create_game()
        game:start_new_round()
        local passer_idx = game.current_player_idx

        local success = game:player_pass(passer_idx)

        assert_true(success)
        assert_equal(1, game.consecutive_passes)
        assert_true(game.passed_players[game.players[passer_idx]])
    end)

    it("rejects bid from passed player", function()
        local game = create_game()
        game:start_new_round()
        local p1_idx = game.current_player_idx

        game:player_pass(p1_idx)
        local current = game.current_player_idx
        game:player_bid(current, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        -- After cycling, p1 tries to bid again
        while game.current_player_idx ~= p1_idx and game.state == Game.STATE.BIDDING do
            game:player_pass(game.current_player_idx)
        end

        if game.state == Game.STATE.BIDDING then
            local success = game:player_bid(p1_idx, 7, Suit.HEARTS, BidType.SUIT_TRUMP)
            assert_false(success, "Passed player should not be able to bid")
        end
    end)

end)

describe("Bidding End Conditions", function()

    it("transitions to KITTY when one player remains with bid", function()
        local game = create_game()
        game:start_new_round()

        -- One player bids, others pass
        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        assert_equal(Game.STATE.KITTY, game.state)
        assert_not_nil(game.winning_bid)
    end)

    it("redeals when all pass without bid", function()
        local game = create_game()
        game:start_new_round()
        local initial_dealer = game.dealer_idx

        -- All pass
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        -- Should have started a new round
        assert_equal(Game.STATE.BIDDING, game.state)
        assert_not_nil(game.dealer_idx)
    end)

end)

describe("Kitty Phase", function()

    it("gives kitty to winning bidder", function()
        local game = create_game()
        game:start_new_round()

        local bidder_idx = game.current_player_idx
        game:player_bid(bidder_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        assert_equal(Game.STATE.KITTY, game.state)
        -- Bidder should have 13 cards (10 + 3 kitty)
        assert_equal(13, #game.players[bidder_idx].hand)
    end)

    it("requires discarding 3 cards", function()
        local game = create_game()
        game:start_new_round()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer_idx = game.current_player_idx
        local declarer = game.players[declarer_idx]
        local discards = {declarer.hand[1], declarer.hand[2]}  -- Only 2

        local success, err = game:player_discard_kitty(declarer_idx, discards)

        assert_false(success)
    end)

    it("transitions to PLAYING after discard", function()
        local game = create_game()
        game:start_new_round()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer_idx = game.current_player_idx
        local declarer = game.players[declarer_idx]
        local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}

        game:player_discard_kitty(declarer_idx, discards)

        assert_equal(Game.STATE.PLAYING, game.state)
        assert_equal(10, #declarer.hand)
    end)

end)

describe("Playing Phase", function()

    local function setup_play_phase()
        local game = create_game()
        game:start_new_round()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer = game.players[game.current_player_idx]
        local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}
        game:player_discard_kitty(game.current_player_idx, discards)

        return game
    end

    it("allows current player to play card", function()
        local game = setup_play_phase()
        local player_idx = game.current_player_idx
        local player = game.players[player_idx]
        local card = player.hand[1]

        local success, err = game:player_play_card(player_idx, card)

        assert_true(success, err)
        assert_equal(1, #game.current_trick)
    end)

    it("rejects play from non-current player", function()
        local game = setup_play_phase()
        local wrong_idx = (game.current_player_idx % 4) + 1
        local player = game.players[wrong_idx]
        local card = player.hand[1]

        local success = game:player_play_card(wrong_idx, card)

        assert_false(success)
    end)

    it("sets lead suit on first play", function()
        local game = setup_play_phase()
        local player = game.players[game.current_player_idx]

        -- Find a hearts card
        local hearts_card = nil
        for _, card in ipairs(player.hand) do
            if game:get_effective_suit(card, game.trump_suit) == Suit.HEARTS then
                hearts_card = card
                break
            end
        end

        if hearts_card then
            game:player_play_card(game.current_player_idx, hearts_card)
            assert_equal(Suit.HEARTS, game.lead_suit)
        end
    end)

    it("advances to next player after play", function()
        local game = setup_play_phase()
        local initial_player = game.current_player_idx
        local player = game.players[initial_player]
        local card = player.hand[1]

        game:player_play_card(initial_player, card)

        assert_equal((initial_player % 4) + 1, game.current_player_idx)
    end)

end)

describe("Trick Resolution", function()

    local function play_full_trick(game)
        for i = 1, 4 do
            local player = game.players[game.current_player_idx]
            local playable = game:get_playable_cards(player, game.lead_suit)
            game:player_play_card(game.current_player_idx, playable[1])
        end
    end

    local function setup_and_play_trick()
        local game = create_game()
        game:start_new_round()

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local declarer = game.players[game.current_player_idx]
        local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}
        game:player_discard_kitty(game.current_player_idx, discards)

        play_full_trick(game)
        return game
    end

    it("records trick in history after 4 cards played", function()
        local game = setup_and_play_trick()
        assert_equal(1, #game.tricks_history)
    end)

    it("transitions to TRICK_OVER after 4 cards", function()
        local game = setup_and_play_trick()
        assert_equal(Game.STATE.TRICK_OVER, game.state)
    end)

    it("awards trick to winner", function()
        local game = setup_and_play_trick()
        local winner = game.tricks_history[1].winner
        assert_equal(1, winner.tricks_won_this_round)
    end)

    it("next_trick resets for new trick", function()
        local game = setup_and_play_trick()
        game:next_trick()

        assert_equal(Game.STATE.PLAYING, game.state)
        assert_equal(0, #game.current_trick)
        assert_nil(game.lead_suit)
    end)

end)

describe("Action Request", function()

    it("returns BID during bidding", function()
        local game = create_game()
        game:start_new_round()

        local action, idx = game:get_action_request()
        assert_equal("BID", action)
        assert_equal(game.current_player_idx, idx)
    end)

    it("returns DISCARD during kitty", function()
        local game = create_game()
        game:start_new_round()
        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)
        game:player_pass(game.current_player_idx)

        local action, idx = game:get_action_request()
        assert_equal("DISCARD", action)
    end)

    it("returns nil for WAITING state", function()
        local game = create_game()
        local action, idx = game:get_action_request()
        assert_nil(action)
    end)

end)

describe("Player Turn Check", function()

    it("correctly identifies current player turn", function()
        local game = create_game()
        game:start_new_round()

        assert_true(game:is_player_turn(game.current_player_idx))
        assert_false(game:is_player_turn((game.current_player_idx % 4) + 1))
    end)

end)

return TestRunner
