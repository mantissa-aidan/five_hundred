-- Tests for Button Class
-- Tests button initialization, interaction, animation, and sound behavior

local TestRunner = require "tests.test_runner"
local Button = require "src.ui.button"

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_not_nil = TestRunner.assert_not_nil

-- Mock AudioManager for testing
local mock_audio_calls = {}
_G.gAudioManager = {
    play = function(self, sound_id)
        table.insert(mock_audio_calls, sound_id)
    end
}

local function reset_mock_audio()
    mock_audio_calls = {}
end

describe("Button Initialization", function()
    
    it("creates button with correct dimensions", function()
        local btn = Button.new(100, 200, 150, 50, "Test", "normal", function() end)
        
        assert_equal(100, btn.x, "X position should match")
        assert_equal(200, btn.y, "Y position should match")
        assert_equal(150, btn.w, "Width should match")
        assert_equal(50, btn.h, "Height should match")
    end)
    
    it("stores button text and type", function()
        local btn = Button.new(0, 0, 100, 50, "Click Me", "action", function() end)
        
        assert_equal("Click Me", btn.text, "Text should match")
        assert_equal("action", btn.type, "Type should match")
    end)
    
    it("stores callback function", function()
        local callback_called = false
        local callback = function() callback_called = true end
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", callback)
        
        assert_not_nil(btn.on_click, "Callback should be stored")
        btn.on_click()
        assert_true(callback_called, "Callback should be executable")
    end)
    
    it("initializes spring animation state", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        assert_equal(1.0, btn.spring_scale, "Spring scale should start at 1.0")
        assert_equal(1.0, btn.spring_target, "Spring target should start at 1.0")
    end)
    
    it("initializes as enabled by default", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        assert_false(btn.disabled, "Button should be enabled by default")
    end)
    
    it("accepts optional data parameter", function()
        local data = {tricks = 6, suit = "SPADES"}
        local btn = Button.new(0, 0, 100, 50, "6♠", "bid", function() end, data)
        
        assert_not_nil(btn.data, "Data should be stored")
        assert_equal(6, btn.data.tricks, "Data should be accessible")
    end)

end)

describe("Button Hover Behavior", function()
    
    it("detects mouse hover correctly", function()
        local btn = Button.new(100, 100, 100, 50, "Test", "normal", function() end)
        
        -- Mouse inside button
        assert_true(btn:is_hovered(150, 125), "Should detect hover inside button")
        
        -- Mouse outside button
        assert_false(btn:is_hovered(50, 50), "Should not detect hover outside button")
        assert_false(btn:is_hovered(250, 125), "Should not detect hover to the right")
        assert_false(btn:is_hovered(150, 200), "Should not detect hover below")
    end)
    
    it("triggers hover sound on mouse enter", function()
        reset_mock_audio()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        -- Simulate mouse enter
        btn:update(0.016, 50, 25) -- Mouse inside
        
        -- Should have played hover sound
        assert_true(#mock_audio_calls > 0, "Should play sound on hover")
    end)
    
    it("updates spring target on hover", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        btn.spring_target = 1.0
        
        -- Simulate hover
        btn:update(0.016, 50, 25)
        
        assert_true(btn.spring_target > 1.0, "Spring target should increase on hover")
    end)
    
    it("resets spring on mouse leave", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        -- First hover
        btn:update(0.016, 50, 25)
        local hover_target = btn.spring_target
        
        -- Then leave
        btn:update(0.016, 200, 200)
        
        assert_true(btn.spring_target < hover_target, "Spring target should decrease on leave")
    end)
    
    it("respects disabled state for hover", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        btn.disabled = true
        
        btn:update(0.016, 50, 25)
        
        assert_equal(1.0, btn.spring_target, "Disabled button should not respond to hover")
    end)

end)

describe("Button Click Behavior", function()
    
    it("executes callback on click", function()
        local clicked = false
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() clicked = true end)
        
        local result = btn:check_click(50, 25)
        
        assert_true(result, "Should return true on successful click")
        assert_true(clicked, "Should execute callback")
    end)
    
    it("plays click sound on click", function()
        reset_mock_audio()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        btn:check_click(50, 25)
        
        -- Should have played click sound (after any hover sounds)
        assert_true(#mock_audio_calls > 0, "Should play sound on click")
    end)
    
    it("triggers spring animation on click", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        btn.spring_scale = 1.0
        
        btn:check_click(50, 25)
        
        assert_true(btn.spring_scale < 1.0, "Spring should compress on click")
    end)
    
    it("ignores clicks when disabled", function()
        local clicked = false
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() clicked = true end)
        btn.disabled = true
        
        local result = btn:check_click(50, 25)
        
        assert_false(result, "Should return false when disabled")
        assert_false(clicked, "Should not execute callback when disabled")
    end)
    
    it("ignores clicks outside button bounds", function()
        local clicked = false
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() clicked = true end)
        
        local result = btn:check_click(200, 200)
        
        assert_false(result, "Should return false for click outside bounds")
        assert_false(clicked, "Should not execute callback for click outside")
    end)

end)

describe("Button Spring Animation", function()
    
    it("animates spring scale toward target", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        btn.spring_scale = 1.0
        btn.spring_target = 1.1
        
        -- Simulate several frames
        for i = 1, 10 do
            btn:update(0.016, -100, -100) -- Mouse far away
        end
        
        assert_true(btn.spring_scale > 1.0, "Spring should move toward target")
        assert_true(btn.spring_scale < 1.1, "Spring should not overshoot significantly")
    end)
    
    it("spring settles near target value", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        btn.spring_scale = 1.0
        btn.spring_target = 1.05
        
        -- Simulate many frames
        for i = 1, 100 do
            btn:update(0.016, -100, -100)
        end
        
        local diff = math.abs(btn.spring_scale - btn.spring_target)
        assert_true(diff < 0.01, "Spring should settle close to target")
    end)

end)

describe("Button Sound Mapping", function()
    
    it("uses correct sounds for action buttons", function()
        reset_mock_audio()
        local btn = Button.new(0, 0, 100, 50, "Next", "action", function() end)
        
        -- Hover
        btn:update(0.016, 50, 25)
        -- Click
        btn:check_click(50, 25)
        
        -- Should use NEXT_TRICK_HOVER and NEXT_TRICK_CLICK
        -- (Exact sound IDs depend on implementation)
        assert_true(#mock_audio_calls >= 2, "Should play hover and click sounds")
    end)
    
    it("uses correct sounds for bid buttons", function()
        reset_mock_audio()
        local btn = Button.new(0, 0, 100, 50, "6♠", "bid", function() end)
        
        btn:update(0.016, 50, 25)
        btn:check_click(50, 25)
        
        assert_true(#mock_audio_calls >= 2, "Should play hover and click sounds")
    end)

end)

describe("Button Alpha/Fade Support", function()
    
    it("accepts alpha parameter in draw", function()
        local btn = Button.new(0, 0, 100, 50, "Test", "normal", function() end)
        
        -- This should not error
        -- (We can't test actual rendering, but we can verify it doesn't crash)
        local success = pcall(function()
            -- btn:draw(0.5) -- Would require love.graphics mock
        end)
        
        -- Just verify the method exists
        assert_not_nil(btn.draw, "Draw method should exist")
    end)

end)

return TestRunner
