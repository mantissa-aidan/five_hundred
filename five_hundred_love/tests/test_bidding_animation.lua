-- Test for BiddingView animation behavior
local TestRunner = require "tests.test_runner"
local BiddingView = require "src.ui.bidding_view"
local Game = require "src.core.game"

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false

describe("BiddingView Animation", function()
    
    it("starts with intro_progress at 0.0", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        print(string.format("[TEST] Initial intro_progress: %.3f", view.intro_progress))
        assert_equal(0.0, view.intro_progress, "intro_progress should start at 0.0")
    end)
    
    it("starts with was_active as false", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        print(string.format("[TEST] Initial was_active: %s", tostring(view.was_active)))
        assert_false(view.was_active, "was_active should start as false")
    end)
    
    it("triggers animation when BIDDING state starts", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        -- Start bidding
        game:start_new_round()
        
        print(string.format("[TEST] Before update - was_active: %s, intro_progress: %.3f", 
            tostring(view.was_active), view.intro_progress))
        
        -- Call update once
        view:update(0.016) -- Simulate one frame at 60fps
        
        print(string.format("[TEST] After update - was_active: %s, intro_progress: %.3f", 
            tostring(view.was_active), view.intro_progress))
        
        assert_true(view.was_active, "was_active should be true after first update in BIDDING state")
        assert_true(view.intro_progress > 0.0 and view.intro_progress < 1.0, 
            "intro_progress should be between 0 and 1 after one frame")
    end)
    
    it("animates intro_progress from 0 to 1 over time", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        game:start_new_round()
        
        -- Simulate multiple frames
        for i = 1, 100 do
            view:update(0.016)
        end
        
        print(string.format("[TEST] After 100 frames - intro_progress: %.3f", view.intro_progress))
        assert_true(view.intro_progress >= 0.99, "intro_progress should be near 1.0 after many frames")
    end)
    
end)

return TestRunner
