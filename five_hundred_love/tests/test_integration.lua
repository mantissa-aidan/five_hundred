-- Integration test for full game loop
local TestRunner = require "tests.test_runner"
local Game = require "src.core.game"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Suit = CardModule.Suit
local BidType = BidModule.BidType

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_not_nil = TestRunner.assert_not_nil

describe("Full Game Integration", function()

    it("plays multiple rounds until a team reaches 500 points", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        
        local rounds_played = 0
        local max_rounds = 20 -- Safety limit to prevent infinite loop
        
        while game.state ~= Game.STATE.GAME_OVER and rounds_played < max_rounds do
            -- Start new round
            game:start_new_round()
            rounds_played = rounds_played + 1
            
            -- Simple: whoever starts bidding, bid high and others pass
            game:player_bid(game.current_player_idx, 8, Suit.SPADES, BidType.SUIT_TRUMP)
            game:player_pass(game.current_player_idx)
            game:player_pass(game.current_player_idx)
            game:player_pass(game.current_player_idx)
            
            assert_equal(Game.STATE.KITTY, game.state, "Should be in KITTY state after bidding")
            
            -- Discard kitty
            local declarer = game.players[game.current_player_idx]
            local discards = {declarer.hand[1], declarer.hand[2], declarer.hand[3]}
            game:player_discard_kitty(game.current_player_idx, discards)
            
            assert_equal(Game.STATE.PLAYING, game.state, "Should be in PLAYING state after discard")
            
            -- Give bidder's team 8 tricks to make contract
            local bidder_team_idx = (game.current_player_idx == 1 or game.current_player_idx == 3) and 1 or 2
            
            for _, p in ipairs(game.players) do
                p.tricks_won_this_round = 0
            end
            
            if bidder_team_idx == 1 then
                game.players[1].tricks_won_this_round = 4
                game.players[3].tricks_won_this_round = 4
            else
                game.players[2].tricks_won_this_round = 4
                game.players[4].tricks_won_this_round = 4
            end
            
            -- Score the round
            game:score_round()
            
            -- State should be ROUND_OVER or GAME_OVER
            local valid_state = game.state == Game.STATE.ROUND_OVER or game.state == Game.STATE.GAME_OVER
            assert_true(valid_state, "Should be in ROUND_OVER or GAME_OVER state after scoring")
            
            -- Check if game should be over
            local team_a_score = game.teams[1].score
            local team_b_score = game.teams[2].score
            
            if team_a_score >= 500 or team_b_score >= 500 or team_a_score <= -500 or team_b_score <= -500 then
                -- Game should end
                break
            end
        end
        
        -- Verify we played multiple rounds
        assert_true(rounds_played > 1, "Should have played multiple rounds")
        assert_true(rounds_played < max_rounds, "Should not hit safety limit")
        
        -- Verify at least one team reached the score limit
        local team_a_score = game.teams[1].score
        local team_b_score = game.teams[2].score
        
        local game_ended = team_a_score >= 500 or team_b_score >= 500 or 
                          team_a_score <= -500 or team_b_score <= -500
        
        assert_true(game_ended, "Game should end when a team reaches score limit")
        
        print(string.format("[Integration Test] Game ended after %d rounds. Final scores: Team A: %d, Team B: %d", 
            rounds_played, team_a_score, team_b_score))
    end)

end)

return TestRunner
