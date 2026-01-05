local TestRunner = require "tests.test_runner"
local Game = require "src.core.game"
local AudioManager = require "src.core.audio_manager"

-- Audio Integration Tests
TestRunner.describe("Audio Integration", function()
    
    TestRunner.it("verifies AudioManager SOUNDS table is complete", function()
        TestRunner.assert(AudioManager.SOUNDS.CARD_SLIDE ~= nil, "CARD_SLIDE should exist")
        TestRunner.assert(AudioManager.SOUNDS.CARD_FLIP ~= nil, "CARD_FLIP should exist")
        TestRunner.assert(AudioManager.SOUNDS.CLICK ~= nil, "CLICK should exist")
        TestRunner.assert(AudioManager.SOUNDS.ALERT ~= nil, "ALERT should exist")
        TestRunner.assert(AudioManager.SOUNDS.WIN ~= nil, "WIN should exist")
        TestRunner.assert(AudioManager.SOUNDS.LOSE ~= nil, "LOSE should exist")
        TestRunner.assert(AudioManager.SOUNDS.SHUFFLE ~= nil, "SHUFFLE should exist")
    end)
    
    TestRunner.it("can create game and trigger on_card_play callback", function()
        local player_names = {"Test Player", "Bot 1", "Bot 2", "Bot 3"}
        local team_names = {"Team A", "Team B"}
        local game = Game.new(player_names, team_names)
        
        game:start_new_round()
        
        -- Setup callback to track calls
        local callback_triggered = false
        game:set_on_card_play(function(p_idx, card)
            callback_triggered = true
        end)
        
        -- Force playing state
        game.state = "PLAYING"
        game.winning_bid = {tricks = 6, suit = 0, player = game.players[1], score = 40}
        game.trump_suit = 0
        game.current_player_idx = 2
        
        -- Play a card
        local card = game.players[2].hand[1]
        game:player_play_card(2, card)
        
        TestRunner.assert(callback_triggered == true, "card play callback should be triggered")
    end)
    
    TestRunner.it("can detect state transitions to KITTY", function()
        local player_names = {"Test Player", "Bot 1", "Bot 2", "Bot 3"}
        local team_names = {"Team A", "Team B"}
        local game = Game.new(player_names, team_names)
        
        game:start_new_round()
        
        -- Force kitty state
        local last_state = game.state
        game.state = "KITTY"
        game.winning_bid = {tricks = 6, suit = 0, player = game.players[1], score = 40}
        
        -- Verify state changed
        TestRunner.assert(last_state ~= "KITTY", "should have started in different state")
        TestRunner.assert(game.state == "KITTY", "should now be in KITTY state")
    end)
    
    TestRunner.it("can create AudioManager and play sounds", function()
        local manager = AudioManager.new()
        
        -- These won't actually make sound in headless mode,
        -- but should not crash
        manager:play(manager.SOUNDS.CLICK)
        manager:play(manager.SOUNDS.CARD_SLIDE)
        
        -- Should complete without error
        TestRunner.assert(true, "should not crash when playing sounds")
    end)
end)

return true
