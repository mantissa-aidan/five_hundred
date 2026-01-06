-- Tests for UI Animation Systems
-- Tests BiddingView fly-in animation and ChatLog slide animation

local TestRunner = require "tests.test_runner"
local BiddingView = require "src.ui.bidding_view"
local ChatLog = require "src.ui.chat_log"
local Game = require "src.core.game"

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false

-- Mock AudioManager to avoid sound spam in tests
local mock_audio_calls = {}
_G.gAudioManager = {
    play = function(self, sound_id)
        table.insert(mock_audio_calls, sound_id)
    end
}

local function reset_mock_audio()
    mock_audio_calls = {}
end

describe("BiddingView Animation - Initialization", function()
    
    it("starts with intro_progress at 0.0", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        assert_equal(0.0, view.intro_progress, "intro_progress should start at 0.0")
    end)
    
    it("starts with was_active as false", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        assert_false(view.was_active, "was_active should start as false")
    end)

end)

describe("BiddingView Animation - Trigger Logic", function()
    
    it("triggers animation when BIDDING state starts and dealing is complete", function()
        reset_mock_audio()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        -- Start a round to enter BIDDING state
        game:start_new_round()
        
        -- Update with dealing_in_progress = false
        view:update(0.016, false)
        
        assert_true(view.was_active, "was_active should be true after trigger")
        assert_equal(0.0, view.intro_progress, "intro_progress should reset to 0.0 on trigger")
        assert_true(#mock_audio_calls > 0, "Should play sound on trigger")
    end)
    
    it("does NOT trigger animation while dealing is in progress", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        game:start_new_round()
        
        -- Update with dealing_in_progress = true
        view:update(0.016, true)
        
        assert_false(view.was_active, "was_active should remain false during dealing")
    end)
    
    it("only triggers animation once per bidding session", function()
        reset_mock_audio()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        game:start_new_round()
        
        -- First update - should trigger
        view:update(0.016, false)
        local first_call_count = #mock_audio_calls
        
        -- Second update - should NOT trigger again
        view:update(0.016, false)
        
        assert_equal(first_call_count, #mock_audio_calls, "Should not play sound again")
    end)

end)

describe("BiddingView Animation - Progress", function()
    
    it("progresses toward 1.0 over time", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        game:start_new_round()
        view:update(0.016, false) -- Trigger
        
        local initial_progress = view.intro_progress
        
        -- Simulate several frames
        for i = 1, 10 do
            view:update(0.016, false)
        end
        
        assert_true(view.intro_progress > initial_progress, "Progress should increase over time")
        assert_true(view.intro_progress <= 1.0, "Progress should not exceed 1.0")
    end)
    
    it("approaches 1.0 asymptotically", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        game:start_new_round()
        view:update(0.016, false)
        
        -- Simulate many frames
        for i = 1, 100 do
            view:update(0.016, false)
        end
        
        assert_true(view.intro_progress >= 0.99, "Progress should be very close to 1.0 after many frames")
    end)

end)

describe("BiddingView Animation - State Reset", function()
    
    it("resets animation when leaving BIDDING state", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        -- Enter and animate
        game:start_new_round()
        view:update(0.016, false)
        for i = 1, 10 do
            view:update(0.016, false)
        end
        
        assert_true(view.was_active, "Should be active during BIDDING")
        
        -- Leave BIDDING state (simulate passing to next phase)
        game.state = "KITTY"
        view:update(0.016, false)
        
        assert_false(view.was_active, "was_active should reset when leaving BIDDING")
        assert_equal(0.0, view.intro_progress, "intro_progress should reset to 0.0")
    end)
    
    it("can re-trigger animation in new bidding session", function()
        reset_mock_audio()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        -- First bidding session
        game:start_new_round()
        view:update(0.016, false)
        game.state = "KITTY"
        view:update(0.016, false)
        
        local first_sound_count = #mock_audio_calls
        
        -- Second bidding session
        game:start_new_round()
        view:update(0.016, false)
        
        assert_true(#mock_audio_calls > first_sound_count, "Should trigger animation again in new session")
    end)

end)

describe("BiddingView Animation - Hot-Reload Safety", function()
    
    it("initializes intro_progress if nil", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        -- Simulate hot-reload by setting to nil
        view.intro_progress = nil
        
        game:start_new_round()
        view:update(0.016, false)
        
        assert_true(view.intro_progress ~= nil, "intro_progress should be initialized")
        assert_true(type(view.intro_progress) == "number", "intro_progress should be a number")
    end)
    
    it("initializes was_active if nil", function()
        local game = Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
        local view = BiddingView.new(game, 1920, 1080)
        
        view.was_active = nil
        
        game:start_new_round()
        view:update(0.016, false)
        
        assert_true(view.was_active ~= nil, "was_active should be initialized")
        assert_true(type(view.was_active) == "boolean", "was_active should be a boolean")
    end)

end)

describe("ChatLog Animation - Initialization", function()
    
    it("starts visible with anim_progress at 1.0", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        
        assert_true(chat.visible, "ChatLog should start visible")
        assert_equal(1.0, chat.anim_progress, "anim_progress should start at 1.0")
        assert_equal(1.0, chat.target_progress, "target_progress should start at 1.0")
    end)

end)

describe("ChatLog Animation - Toggle Behavior", function()
    
    it("sets target_progress to 0 when hiding", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        
        chat:toggle_visibility() -- Hide
        
        assert_false(chat.visible, "visible should be false")
        assert_equal(0.0, chat.target_progress, "target_progress should be 0.0")
    end)
    
    it("sets target_progress to 1 when showing", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        
        chat:toggle_visibility() -- Hide
        chat:toggle_visibility() -- Show
        
        assert_true(chat.visible, "visible should be true")
        assert_equal(1.0, chat.target_progress, "target_progress should be 1.0")
    end)

end)

describe("ChatLog Animation - Progress Interpolation", function()
    
    it("animates toward target_progress over time", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        chat:toggle_visibility() -- Hide (target = 0)
        
        local initial_progress = chat.anim_progress
        
        -- Simulate several frames
        for i = 1, 10 do
            chat:update(0.016)
        end
        
        assert_true(chat.anim_progress < initial_progress, "Progress should decrease toward 0")
        assert_true(chat.anim_progress >= 0.0, "Progress should not go below 0")
    end)
    
    it("settles near target value", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        chat:toggle_visibility() -- Hide
        
        -- Simulate many frames
        for i = 1, 200 do
            chat:update(0.016)
        end
        
        assert_true(chat.anim_progress < 0.01, "Progress should be very close to 0")
    end)

end)

describe("ChatLog Animation - Hot-Reload Safety", function()
    
    it("initializes animation state if missing", function()
        local chat = ChatLog.new(0, 0, 300, 400)
        
        -- Simulate hot-reload
        chat.anim_progress = nil
        chat.target_progress = nil
        
        chat:update(0.016)
        
        assert_true(chat.anim_progress ~= nil, "anim_progress should be initialized")
        assert_true(chat.target_progress ~= nil, "target_progress should be initialized")
    end)

end)

return TestRunner
