local Game = require "src.core.game"
local TableView = require "src.ui.table_view"
local ChatLog = require "src.ui.chat_log"
local CardRenderer = require "src.ui.card_renderer"
local AudioManager = require "src.core.audio_manager"
local NNStrategy = require "src.ai.nn_strategy"
local HumanStrategy = require "src.ai.human_strategy"
local RandomStrategy = require "src.ai.random_strategy"
local Config = require "src.config"
local AudioManager = require "src.core.audio_manager"

-- Global Audio Manager
gAudioManager = nil


-- Player strategies (indexed by player position 1-4)
gStrategies = {}  -- Global so TableView can access for debug info

-- Global Game State
gGame = nil
gTableView = nil
gBiddingView = nil
gScoreStars = nil
gDebugMode = Config.debug.auto_start
gChatLog = nil
gAudioManager = nil

-- Global Resources
gFonts = {}

-- Game state flags
gPaused = false

-- Chat log instance
-- gChatLog = nil -- Moved to global game state

-- AI pacing timer
local ai_timer = 0
local AI_DELAY = Config.game.ai_delay

-- Async Loading State
local gAppState = "LOADING" -- "LOADING" or "GAME"
local gLoaderThread = nil
local gLoaderChannel = nil

-- Reload UI Helper
local function register_callbacks()
    -- Register Game Logging Hooks
    gGame:set_on_phase_change(function(phase, data)
        if phase == "BIDDING" then
            gChatLog:add_message("System", {"Bidding Started", "Dealer: " .. data.dealer_name}, false, Config.colors.system_color)
        elseif phase == "KITTY" then
            gChatLog:add_message("System", {data.winner_name .. " won bid", "Choosing Kitty..."}, false, Config.colors.system_color)
            if gAudioManager then gAudioManager:play("BID_WON", {volume=0.9}) end
        elseif phase == "PLAYING" then
            gChatLog:add_message("System", {"Play Started"}, false, Config.colors.system_color)
        elseif phase == "TRICK_START" then
            gChatLog:add_message("System", {"Trick " .. data.trick_num .. "/10"}, false, {0.4, 0.4, 0.4})
        elseif phase == "REDEAL" then
            gChatLog:add_message("System", {"All passed. Redeal."}, false, {1, 0.5, 0})
            if gAudioManager then gAudioManager:play("SHUFFLE", {volume=0.8}) end
        end
    end)
    
    gGame:set_on_bid_made(function(player, bid)
        if not gAudioManager then return end
        
        if bid.type == "PASS" then
             gAudioManager:play("BTN_CLICK_1", {volume=0.3}) -- Quiet pass
        else
            -- Progressive Logic
            local suit_pitch = {
                [0] = 0.8, -- Clubs (Wood)
                [1] = 1.0, -- Diamonds (Glass)
                [2] = 0.9, -- Hearts (Warm)
                [3] = 1.2, -- Spades (Sharp)
                [4] = 1.1  -- NT (Ethereal)
            }
            local base_pitch = suit_pitch[bid.suit] or 1.0
            
            -- Progressive Heaviness (Tricks 6..10)
            local weight = (bid.tricks - 6) / 4 -- 0.0 to 1.0
            if weight < 0 then weight = 0 end
            
            -- Higher bid = Deeper pitch (heavier) + Louder
            local pitch_mod = weight * 0.3
            local vol_mod = weight * 0.4
            
            local final_pitch = base_pitch - pitch_mod
            local final_vol = 0.6 + vol_mod
            
            gAudioManager:play("BID_MADE", {pitch=final_pitch, volume=final_vol})
        end
    end)
    
    gGame:set_on_contract_set(function(bid)
        local suit_names = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="No Trump"}
        local suit_str = suit_names[bid.suit] or tostring(bid.suit)
        gChatLog:add_message("System", {"Contract: " .. bid.tricks .. " " .. suit_str, "By " .. bid.player.name}, false, {0.8, 0.8, 0.2})
        -- BID_WON played in phase change KITTY or here? Logic says here is safer for contract win.
        if gAudioManager then gAudioManager:play("BID_WON", {volume=0.9}) end
    end)
    
    gGame:set_on_card_play(function(player_idx, card)
        local power = gGame:get_card_power(card)
        local is_self = (gGame.players[player_idx].name == "You")
        
        if is_self then
             print(string.format("[DEBUG] Card Played: %s | Power: %.2f", tostring(card), power))
        end
        
        if gAudioManager then 
            -- Self play is louder, High power is louder
            local base_vol = is_self and 0.8 or 0.4
            
            -- Power boosts volume and lowers pitch (heavier)
            local vol = math.min(1.0, base_vol + (power * 0.3))
            local pitch = 1.0 - (power * 0.2) -- 0.8 to 1.0
            
            gAudioManager:play("CARD_FLIP", {volume=vol, pitch=pitch}) 
        end
        
        -- Forward to TableView for animation with Power
        if gTableView and gTableView.on_card_played then
            gTableView:on_card_played(player_idx, card, power)
        end
    end)
    
    gGame:set_on_trick_complete(function(data)
        local suit_names = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="No Trump"}
        local trump_str = suit_names[data.trump_suit] or "?"
        local lead_str = suit_names[data.lead_suit] or "?"
        local card_str = tostring(data.winning_card)
        
        -- Build message showing all cards
        local msgs = {string.format("Trick %d: %s won with %s", data.trick_num, data.winner.name, card_str)}
        table.insert(msgs, string.format("Lead: %s, Trump: %s", lead_str, trump_str))
        
        local col = {0.5, 0.5, 0.5}
        local is_friendly = (data.winner.name == "You" or data.winner.name == "Partner")
        
        if data.winner.name == "You" then
            col = {0.2, 0.8, 0.2}
        elseif data.winner.name == "Partner" then
            col = {0.2, 0.6, 0.2}
        end
        gChatLog:add_message("System", msgs, false, col)
        
        if gTableView and gTableView.on_trick_complete then
            gTableView:on_trick_complete(data)
        end
        
        -- Audio & Shake
        if gAudioManager then
            if is_friendly then
                gAudioManager:play("TRICK_WON", {volume=0.9})
            else
                gAudioManager:play("TRICK_LOST", {volume=0.8})
            end
        end
    end)
    
    gGame:set_on_round_end(function(data)
        if gTableView and gTableView.anim then
            gTableView.anim:skip_all()
        end

        gChatLog:add_message("System", {
            "Round Over",
            "Team A: " .. data.team_a_score,
            "Team B: " .. data.team_b_score
        }, false, {1, 0.8, 0})
        
        if gAudioManager then
            if data.contract_made then
                gAudioManager:play("BID_WON", {volume=1.0})
            else
                gAudioManager:play("BID_LOST", {volume=0.9})
            end
        end
    end)
    
    -- Dealing animation
    gGame:set_on_deal_complete(function()
        if gTableView and gTableView.animate_deal then
            gTableView:animate_deal()
        end
    end)
end

local run_tests -- Forward declaration

local function reload_ui()
    print("[Main] Reloading UI...")
    
    -- Reload Config
    package.loaded["src.config"] = nil
    Config = require "src.config"
    AI_DELAY = Config.game.ai_delay
    gDebugMode = Config.debug.auto_start
    
    -- Re-init Chat Log (persisting messages)
    local old_msgs = gChatLog and gChatLog.messages or {}
    
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local chat_width = Config.layout.chat_width
    
    gChatLog = ChatLog.new(screen_w - chat_width, 0, chat_width, screen_h)
    gChatLog.messages = old_msgs
    gChatLog:scroll_to_bottom()
    
    -- Re-init TableView
    gTableView = TableView.new(gGame)
    gTableView:resize(screen_w, screen_h)
    
    -- Re-register Callbacks (in case logic changed)
    register_callbacks()
    
    -- Run Tests
    if run_tests then run_tests() end
end

run_tests = function()
    print("[Main] Running Tests...")
    local TestRunner = require "tests.test_runner"
    TestRunner.reset()
    
    local test_modules = {
        "tests.test_card",
        "tests.test_deck",
        "tests.test_player",
        "tests.test_team",
        "tests.test_bid",
        "tests.test_game",
        "tests.test_strategy",
        "tests.test_view_logic",
        "tests.test_regression",
    }
    
    local total_failed = 0
    
    for _, mod_name in ipairs(test_modules) do
        package.loaded[mod_name] = nil -- Force reload
        local success, err = pcall(require, mod_name)
        if not success then
            local err_msg = "Error loading " .. mod_name .. ": " .. tostring(err)
            print(err_msg)
            if gChatLog then gChatLog:add_message("System", {err_msg}, false, {1, 0, 0}) end
            total_failed = total_failed + 1
        end
    end
    
    local passed = TestRunner.run()
    
    if gChatLog then
        if passed then
            gChatLog:add_message("System", {"Tests Passed ✓"}, false, {0.2, 0.8, 0.2})
        else
            gChatLog:add_message("System", {"Tests Failed ✗"}, false, {1, 0.2, 0.2})
        end
    end
end

-- Helper to format probability lines for chat
local function format_probs(top_actions, pass_prob)
    local lines = {}
    for i, a in ipairs(top_actions) do
        table.insert(lines, string.format("%s: %.1f%%", a.label, a.prob * 100))
    end
    if pass_prob then
        table.insert(lines, string.format("Pass: %.1f%%", pass_prob * 100))
    end
    return lines
end


-- Render Canvas & Shader
local gCanvas = nil
local gCRTShader = nil
local gTime = 0
gScreenShake = 0

function love.load()
    -- Initialize RNG
    math.randomseed(os.time())
    -- Pop a few random numbers to clear any startup bias
    math.random()
    math.random()
    math.random()
    -- Hot Reload Setup (Lurker)
    lurker = require "src.ext.lurker"
    lurker.path = "src" -- Only scan src directory
    lurker.interval = 2 -- Scan every 2 seconds to reduce file I/O stutter on Windows
    lurker.postswap = reload_ui -- Call this after swap
    
    -- Load Unicode font (DejaVu Sans has suit symbols ♠♣♦♥)
    -- Also loading Lambda for UI
    gFonts = {
        small = love.graphics.newFont("assets/fonts/Lambda-Regular.ttf", 16),
        medium = love.graphics.newFont("assets/fonts/Lambda-Regular.ttf", 24),
        large = love.graphics.newFont("assets/fonts/Lambda-Regular.ttf", 48),
        symbols = love.graphics.newFont("assets/fonts/DejaVuSans.ttf", 18) -- Fallback for suits if needed?
    }
    -- Actually Lambda might not have suits. 
    -- If Lambda lacks Unicode suits, we might need a fallback or stick to emoji/images.
    -- For now set default to medium.
    love.graphics.setFont(gFonts.medium)
    
    -- Initialize Game
    local player_names = {"You", "Bot 1", "Partner", "Bot 3"}
    local team_names = {"Team A", "Team B"}
    
    gGame = Game.new(player_names, team_names)
    gStrategies[1] = HumanStrategy.new()
    
    -- Initialize View
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local chat_width = Config.layout.chat_width
    
    -- Setup Canvas & Shader
    gCanvas = love.graphics.newCanvas(screen_w, screen_h)
    gCanvas:setFilter("nearest", "nearest")
    
    -- Initialize Audio
    gAudioManager = AudioManager.new()
    print("[Main] AudioManager Initialized")
    
    local shader_code = love.filesystem.read("src/shaders/crt.glsl")
    if shader_code then
        gCRTShader = love.graphics.newShader(shader_code)
        print("[Main] CRT Shader Loaded")
    else
        print("[Main] Could not find src/shaders/crt.glsl")
    end
    
    gChatLog = ChatLog.new(screen_w - chat_width, 0, chat_width, screen_h)
    gTableView = TableView.new(gGame)
    
    gChatLog:add_message("System", {"Game started!", "Loading AI..."}, false, {0.3, 0.5, 0.3})
    
    register_callbacks()
    
    -- Start Async Loading
    if love.filesystem.getInfo("assets/weights.json") then
        gLoaderThread = love.thread.newThread("src/ai/loader_thread.lua")
        gLoaderThread:start("assets/weights.json")
        gLoaderChannel = love.thread.getChannel("ai_load")
        gAppState = "LOADING"
    else
        print("[Main] No weights found, starting with Random bots")
        gStrategies[2] = RandomStrategy.new()
        gStrategies[3] = RandomStrategy.new()
        gStrategies[4] = RandomStrategy.new()
        gGame:start_new_round()
        gAppState = "GAME"
    end
    
    print("Five Hundred - Love2D Version Started")
end

function love.update(dt)
    if Config.debug.hot_reload then
        lurker.update() -- Check for file changes
    end
    gTime = gTime + dt
    
    -- Update Chat Animation
    if gChatLog then 
        gChatLog:update(dt) 
        
        -- Continuous Layout Update during animation
        if gTableView then
             local w, h = love.graphics.getDimensions()
             local chat_w = Config.layout.chat_width
             local slide = chat_w * gChatLog.anim_progress
             
             local game_w = w - slide
             gTableView:resize(game_w, h)
             gChatLog:resize(w - slide, 0, chat_w, h)
        end
    end
    
    if gScreenShake > 0 then
        gScreenShake = gScreenShake - dt * 5 -- Decay
        if gScreenShake < 0 then gScreenShake = 0 end
    end
    
    if gAudioManager then gAudioManager:update(dt) end
    
    if gAppState == "LOADING" then
        -- Check channel for loaded weights
        local msg = gLoaderChannel:pop()
        if msg then
            if type(msg) == "table" then
                -- Apply Weights
                print("[Main] AI Weights Loaded Async")
                gChatLog:add_message("System", {"AI Ready"}, false, {0.2, 0.8, 0.2})
                
                gStrategies[2] = NNStrategy.new(msg)
                gStrategies[3] = NNStrategy.new(msg)
                gStrategies[4] = NNStrategy.new(msg)
                
                gGame:start_new_round()
                gAppState = "GAME"
            elseif type(msg) == "string" and msg == "error" then
                print("[Main] Error loading AI weights")
                gAppState = "GAME" -- Fallback to random bots (already set if nil)
                gGame:start_new_round()
            end
        end
        return -- Skip game update while loading
    end
    
    -- Game Logic Update
    if gAppState == "GAME" then
        -- Block game updates during animations
        if gTableView.anim:is_busy() then
            gTableView:update(dt)
            gChatLog:update(dt)
            return
        end
        
        if gGame.state == "BIDDING" or gGame.state == "PLAYING" or gGame.state == "KITTY" then
            local p_idx = gGame.current_player_idx
            local strategy = gStrategies[p_idx]
            
            -- Only bots need updating from main (Humans act via UI events)
            if strategy and not strategy.is_human then
                if not strategy.last_action_time then strategy.last_action_time = love.timer.getTime() end

                if not strategy.last_action_time then strategy.last_action_time = love.timer.getTime() end
                
                -- Wait for Visual Turn Sync (Flash then Trick)
                if gTableView.visual_current_player_idx ~= p_idx then
                     -- Visuals haven't caught up yet. Wait.
                else
                    -- Visuals are ready. Check "Thinking Time" relative to Turn Start (Flash).
                    local time_since_turn_start = love.timer.getTime() - (gTableView.turn_start_time or 0)
                    local MIN_THINK_TIME = 0.8 -- Wait 0.8s after flash before playing
                    
                    if time_since_turn_start > MIN_THINK_TIME and love.timer.getTime() - strategy.last_action_time > AI_DELAY then
                   if gGame.state == "BIDDING" then
                       local action, params = strategy:decide_bid(gGame, p_idx)
                       if action == "pass" then
                           gGame:player_pass(p_idx)
                           gChatLog:add_message(gGame.players[p_idx].name, {"Passed"}, false)
                       elseif action == "bid" and params then
                           local success = gGame:player_bid(p_idx, params[1], params[2], params[3])
                           if success then
                               local suit_names = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="No Trump"}
                               local msg = string.format("Bids %d %s", params[1], suit_names[params[2]] or "?")
                               gChatLog:add_message(gGame.players[p_idx].name, {msg}, false)
                           else
                               gGame:player_pass(p_idx)
                               gChatLog:add_message(gGame.players[p_idx].name, {"Passed"}, false)
                           end
                       end
                   elseif gGame.state == "PLAYING" then
                       local player = gGame.players[p_idx]
                       local playable = gGame:get_playable_cards(player, gGame.lead_suit)

                       local card = strategy:decide_play(gGame, p_idx, playable)
                       if card then
                           gGame:player_play_card(p_idx, card)
                       end
                   elseif gGame.state == "KITTY" then
                       local discards = strategy:decide_discard(gGame, p_idx)
                       if discards then
                           gGame:player_discard_kitty(p_idx, discards)
                           gChatLog:add_message(gGame.players[p_idx].name, {"Discarded kitty"}, false)
                       end
                   end
                   strategy.last_action_time = love.timer.getTime()
                end
                end -- End time check
            end
        end
    end
    
    gTableView:update(dt)
    gChatLog:update(dt)
end

function love.keypressed(key)
    if key == "escape" then
        gPaused = not gPaused
    elseif key == "d" then
        gDebugMode = not gDebugMode
        gChatLog:add_message("System", {"Debug mode: " .. (gDebugMode and "ON" or "OFF")}, false, {0.5, 0.5, 0.3})
    elseif key == "m" then
        if gAudioManager then 
            local enabled = gAudioManager:toggle_mute()
            if gChatLog then gChatLog:add_message("System", {enabled and "Audio Unmuted" or "Audio Muted"}, true) end
        end
    -- Debug: Force Round Over
    elseif key == 'o' and gDebugMode then
        if gGame then
             gGame.state = "ROUND_OVER"
             local p = gGame.players[1]
             gGame.winning_bid = {player = p, tricks = 7, suit = "CLUBS"}
             gGame.teams[1].score = 100
             gGame.teams[2].score = 200
        end
    elseif key == "space" then
        if gPaused then return end
        -- Skip dealing animation first
        if gTableView and gTableView.anim:is_dealing() then
            gTableView:skip_dealing_animation()
        elseif gGame.state == "BIDDING" and gGame.current_player_idx == 1 then
            gGame:player_pass(1)
            gChatLog:add_message("You", {"Passed"}, true)
        elseif gGame.state == "TRICK_OVER" then
            gGame:next_trick()
        end
    elseif key == "r" then
        reload_ui()
        gChatLog:add_message("System", {"UI Reloaded"}, false, {0.3, 0.5, 0.3})
    elseif key == "n" then
        gGame:start_new_round()
        -- Recreate TableView to reset BiddingView animation state
        gTableView = TableView.new(gGame)
        if gChatLog then gChatLog:clear() end
        gChatLog:add_message("System", {"New round started"}, false, {0.3, 0.5, 0.3})
        gPaused = false
    elseif key == "p" then
        if gChatLog then 
            gChatLog:toggle_visibility() 
        end
    end
end

function love.wheelmoved(x, y)
    if gChatLog then
        gChatLog:scroll(y)
    end
end

function love.resize(w, h)
    gCanvas = love.graphics.newCanvas(w, h)
    gCanvas:setFilter("nearest", "nearest")
    
    local chat_width = Config.layout.chat_width
    local game_w = w
    
    if gChatLog then
        if gChatLog.visible then
            -- Game takes left portion, Chat takes right portion
            game_w = w - chat_width
            gChatLog:resize(game_w, 0, chat_width, h)
        else
            -- Game takes full width
            game_w = w
        end
    end
    
    if gTableView then
        gTableView:resize(game_w, h)
    end
end

function love.draw()
    -- Render to Canvas
    love.graphics.setCanvas(gCanvas)
    love.graphics.clear()
    
    -- Apply Screen Shake
    love.graphics.push()
    if gScreenShake > 0 then
        local dx = love.math.random(-1, 1) * gScreenShake * 10
        local dy = love.math.random(-1, 1) * gScreenShake * 10
        love.graphics.translate(dx, dy)
    end
    
    gTableView:draw()
    gChatLog:draw()
    
    -- Draw Loading Overlay
    if gAppState == "LOADING" then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        
        love.graphics.setColor(1, 1, 1)
        local cx = love.graphics.getWidth() / 2
        local cy = love.graphics.getHeight() / 2
        love.graphics.printf("Loading AI Strategy...", 0, cy - 10, love.graphics.getWidth(), "center")
    end
    
    -- Draw pause overlay
    if gPaused then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        
        love.graphics.setColor(1, 1, 1)
        local cx = love.graphics.getWidth() / 2
        local cy = love.graphics.getHeight() / 2
        
        love.graphics.printf("PAUSED", 0, cy - 60, love.graphics.getWidth(), "center")
        love.graphics.printf("ESC - Resume", 0, cy - 20, love.graphics.getWidth(), "center")
        love.graphics.printf("D - Toggle Debug Mode (" .. (gDebugMode and "ON" or "OFF") .. ")", 0, cy + 10, love.graphics.getWidth(), "center")
        love.graphics.printf("R - Reload UI  |  N - New Round", 0, cy + 40, love.graphics.getWidth(), "center")
    end
    
    -- Debug mode indicator
    if gDebugMode and not gPaused then
        love.graphics.setColor(1, 0.5, 0, 0.8)
        love.graphics.rectangle("fill", 5, 5, 100, 25, 5)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("DEBUG ON", 15, 10)
    end
    
    love.graphics.pop() -- End Shake
    
    love.graphics.setCanvas() -- Reset to Screen
    
    -- Draw Canvas with Shader
    love.graphics.setColor(1, 1, 1)
    if gCRTShader and false then -- Disabled for now
        gCRTShader:send("canvasSize", {love.graphics.getWidth(), love.graphics.getHeight()})
        gCRTShader:send("time", gTime)
        love.graphics.setShader(gCRTShader)
    end
    
    love.graphics.draw(gCanvas, 0, 0)
    love.graphics.setShader()
end

function love.mousepressed(x, y, button, istouch, presses)
    if gPaused then return end
    if button == 1 then
        gTableView:check_click(x, y)
    end
end
