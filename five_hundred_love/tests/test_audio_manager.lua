local TestRunner = require "tests.test_runner"

-- AudioManager Unit Tests
TestRunner.describe("AudioManager", function()
    
    TestRunner.it("initializes with empty sources and active_sources", function()
        local AudioManager = require "src.core.audio_manager"
        local manager = AudioManager.new()
        
        TestRunner.assert(manager.sources ~= nil, "sources table should exist")
        TestRunner.assert(manager.active_sources ~= nil, "active_sources table should exist")
        TestRunner.assert(#manager.active_sources == 0, "active_sources should start empty")
        TestRunner.assert(manager.enabled == true, "should start enabled")
        TestRunner.assert(manager.volume == 1.0, "should start at full volume")
    end)
    
    TestRunner.it("clamps volume to [0, 1]", function()
        local AudioManager = require "src.core.audio_manager"
        local manager = AudioManager.new()
        
        manager:set_volume(1.5)
        TestRunner.assert(manager.volume == 1.0, "should clamp to 1.0")
        
        manager:set_volume(-0.5)
        TestRunner.assert(manager.volume == 0.0, "should clamp to 0.0")
    end)
    
    TestRunner.it("respects mute toggle", function()
        local AudioManager = require "src.core.audio_manager"
        local manager = AudioManager.new()
        
        -- Mute
        local enabled = manager:toggle_mute()
        TestRunner.assert(enabled == false, "should be muted")
        TestRunner.assert(manager.enabled == false, "enabled should be false")
        
        -- Unmute
        enabled = manager:toggle_mute()
        TestRunner.assert(enabled == true, "should be unmuted")
        TestRunner.assert(manager.enabled == true, "enabled should be true")
    end)
    
    TestRunner.it("has correct sound ID mappings", function()
        local AudioManager = require "src.core.audio_manager"
        
        TestRunner.assert(AudioManager.SOUNDS.CARD_SLIDE ~= nil, "CARD_SLIDE should be defined")
        TestRunner.assert(AudioManager.SOUNDS.CARD_FLIP ~= nil, "CARD_FLIP should be defined")
        TestRunner.assert(AudioManager.SOUNDS.CLICK ~= nil, "CLICK should be defined")
        TestRunner.assert(AudioManager.SOUNDS.WIN ~= nil, "WIN should be defined")
        TestRunner.assert(AudioManager.SOUNDS.LOSE ~= nil, "LOSE should be defined")
        TestRunner.assert(AudioManager.SOUNDS.SHUFFLE ~= nil, "SHUFFLE should be defined")
    end)
end)

return true
