-- Tests for Round Over Logic and Transitions
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
local assert_not_nil = TestRunner.assert_not_nil
local assert_nil = TestRunner.assert_nil

-- Helper to create a fresh game
local function create_game()
    return Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
end

-- Helper to force game into Round Over state
local function setup_round_over(game)
    game:start_new_round()
    
    -- Mock a winning bid
    -- Dealer is 2 (rotated from 1), so P3 starts.
    -- Sequence: P3(Pass), P4(Pass), P1(Bid), P2(Pass), P3(Pass), P4(Pass)
    game:player_pass(3)
    game:player_pass(4)
    game:player_bid(1, 7, Suit.SPADES, BidType.SUIT_TRUMP)
    game:player_pass(2)
    game:player_pass(3)
    game:player_pass(4)
    
    -- Discard
    local declarer = game.players[1]
    local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}
    game:player_discard_kitty(1, discards)
    
    -- Mock tricks
    -- Player 1 wins 7 tricks
    game.players[1].tricks_won_this_round = 7
    game.players[3].tricks_won_this_round = 0
    
    -- Score it
    game:score_round()
    
    return game
end

describe("Round Over State", function()

    it("enters ROUND_OVER state after scoring", function()
        local game = create_game()
        setup_round_over(game)
        
        assert_equal(Game.STATE.ROUND_OVER, game.state)
    end)

    it("requests NEXT_ROUND action", function()
        local game = create_game()
        setup_round_over(game)
        
        local action, idx = game:get_action_request()
        assert_equal("NEXT_ROUND", action)
    end)

    it("updates scores correctly before state change", function()
        local game = create_game()
        setup_round_over(game)
        
        -- 7 Spades = 140 pts
        assert_equal(140, game.teams[1].score)
        assert_equal(0, game.teams[2].score)
    end)

end)

describe("Transition to Next Round", function()

    it("starts new round on request", function()
        local game = create_game()
        setup_round_over(game)
        
        game:start_new_round()
        
        assert_equal(Game.STATE.BIDDING, game.state)
    end)
    
    it("preserves scores in new round", function()
        local game = create_game()
        setup_round_over(game)
        
        local score_before = game.teams[1].score
        game:start_new_round()
        
        assert_equal(score_before, game.teams[1].score)
    end)
    
    it("resets round data (bids, tricks)", function()
        local game = create_game()
        setup_round_over(game)
        
        game:start_new_round()
        
        assert_nil(game.winning_bid)
        assert_nil(game.trump_suit)
        assert_equal(0, #game.tricks_history)
    end)
    
    it("rotates dealer", function()
        local game = create_game()
        local d1 = game.dealer_idx
        setup_round_over(game)
        
        game:start_new_round()
        
        -- Dealer should move 1 -> 2
        -- Note: setup_round_over calls start_new_round once (dealer 1->2), then we call it again (2->3)
        -- Wait, create_game sets dealer=1. start_new_round increments dealer.
        -- So initial start -> dealer=2.
        -- setup_round_over finishes round.
        -- calling start_new_round again -> dealer=3.
        
        -- Let's check explicitly
        local g2 = create_game()
        g2.dealer_idx = 1
        g2:start_new_round() -- resets to 2
        
        -- manually finish
        g2.state = Game.STATE.ROUND_OVER
        g2:start_new_round() -- resets to 3
        
        assert_equal(3, g2.dealer_idx)
    end)

end)

return TestRunner
