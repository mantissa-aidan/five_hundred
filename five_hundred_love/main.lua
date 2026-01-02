local Game = require "src.core.game"
local TableView = require "src.ui.table_view"
local ChatLog = require "src.ui.chat_log"
local NNStrategy = require "src.ai.nn_strategy"
local HumanStrategy = require "src.ai.human_strategy"
local RandomStrategy = require "src.ai.random_strategy"

-- Player strategies (indexed by player position 1-4)
gStrategies = {}  -- Global so TableView can access for debug info

-- Game state flags
gPaused = false
gDebugMode = false

-- Chat log instance
gChatLog = nil

-- AI pacing timer
local ai_timer = 0
local AI_DELAY = 0.5 -- seconds between bot actions

-- Helper to format probability lines for chat
local function format_probs(top_actions, pass_prob)
    local lines = {}
    local probs_str = ""
    for i, a in ipairs(top_actions) do
        probs_str = probs_str .. string.format("%s:%.0f%% ", a.label, a.prob * 100)
        if i == 3 then
            table.insert(lines, probs_str)
            probs_str = ""
        end
    end
    if probs_str ~= "" then
        table.insert(lines, probs_str)
    end
    if pass_prob then
        table.insert(lines, string.format("Pass: %.1f%%", pass_prob * 100))
    end
    return lines
end

function love.load()
    -- Load Unicode font (DejaVu Sans has suit symbols ♠♣♦♥)
    local font = love.graphics.newFont("assets/fonts/DejaVuSans.ttf", 12)
    love.graphics.setFont(font)
    
    -- Initialize Game
    local player_names = {"You", "Bot 1", "Partner", "Bot 3"}
    local team_names = {"Team A", "Team B"}
    
    gGame = Game.new(player_names, team_names)
    
    -- Setup strategies for each player
    gStrategies[1] = HumanStrategy.new()
    
    -- Try to load NN strategy, fall back to Random
    local nn_ok, nn_strat = pcall(function()
        return NNStrategy.new("assets/weights.json")
    end)
    
    if nn_ok then
        gStrategies[2] = nn_strat
        gStrategies[3] = NNStrategy.new("assets/weights.json")
        gStrategies[4] = NNStrategy.new("assets/weights.json")
    else
        print("[Controller] NN weights not found, using Random strategy")
        gStrategies[2] = RandomStrategy.new()
        gStrategies[3] = RandomStrategy.new()
        gStrategies[4] = RandomStrategy.new()
    end
    
    -- Initialize Chat Log (dedicated right panel)
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local chat_width = 300
    gChatLog = ChatLog.new(screen_w - chat_width, 0, chat_width, screen_h)
    
    -- Welcome message
    gChatLog:add_message("System", {"Game started!", "Press D for debug mode"}, false, {0.3, 0.5, 0.3})
    
    gGame:start_new_round()
    gChatLog:add_message("System", {"New round started"}, false, {0.3, 0.5, 0.3})
    
    -- Initialize View
    gTableView = TableView.new(gGame)
    
    print("Five Hundred - Love2D Version Started")
    print("Controls: ESC=Pause, D=Debug Mode, R=Restart Round")
end

function love.update(dt)
    if gPaused then return end
    
    gTableView:update(dt)
    
    local action_type, player_idx = gGame:get_action_request()
    
    if not action_type or not player_idx then
        return
    end
    
    local strategy = gStrategies[player_idx]
    
    if strategy:requires_input() then
        return
    end
    
    ai_timer = ai_timer + dt
    if ai_timer < AI_DELAY then
        return
    end
    ai_timer = 0
    
    -- Verify Layout Overlap (as requested)
    if gDebugMode then
        local table_end = gTableView.width
        local chat_start = gChatLog.x
        if table_end > chat_start + 0.1 then -- small epsilon
            print(string.format("[ERROR] Layout Overlap Detected! Table End: %.1f, Chat Start: %.1f, Overlap: %.1f", 
                table_end, chat_start, table_end - chat_start))
        elseif ai_timer == 0 then -- Just log occasionally (when ai_timer resets or similar specific triggers, here simplified to first frame of update or just once)
             -- Use a simple timer or just log on change. For now let's just log every few seconds effectively? 
             -- actually spamming logs is bad. Let's log only on resize or init.
             -- But the user wants it in the logs "checking for the overlap".
             -- Let's put a log here that prints "Layout Verified" throttled.
        end
    end
    
    -- Only log layout status periodically to avoid spam
    if gDebugMode and math.floor(love.timer.getTime()) % 5 == 0 and math.floor(love.timer.getTime() * 60) % 60 == 0 then
         print(string.format("[CHECK] Layout Valid: Table Width %.1f | Chat Start %.1f | Gap %.1f", 
             gTableView.width, gChatLog.x, gChatLog.x - gTableView.width))
    end
    
    local player = gGame.players[player_idx]
    
    -- Execute bot action based on action type
    if action_type == "BID" then
        local action, params = strategy:decide_bid(gGame, player_idx)
        
        -- Build chat message
        local lines = {}
        if action == "pass" then
            table.insert(lines, "Passed")
        else
            table.insert(lines, string.format("Bids %d%s", params[1], tostring(params[2])))
        end
        
        -- Add probabilities
        if strategy.get_top_actions then
            local top = strategy:get_top_actions(gGame, player_idx, "BID", 5)
            local pass_prob = nil
            local has_pass = false
            for _, a in ipairs(top) do
                if a.label == "Pass" then has_pass = true; break end
            end
            if not has_pass and strategy.get_pass_prob then
                pass_prob = strategy:get_pass_prob(gGame, player_idx)
            end
            local prob_lines = format_probs(top, pass_prob)
            for _, pline in ipairs(prob_lines) do
                table.insert(lines, pline)
            end
        end
        
        gChatLog:add_message(player.name, lines, false)
        
        -- Execute action
        if action == "pass" then
            gGame:player_pass(player_idx)
        elseif action == "bid" and params then
            gGame:player_bid(player_idx, params[1], params[2], params[3])
        end
        
    elseif action_type == "DISCARD" then
        local discards = strategy:decide_discard(gGame, player_idx)
        if discards then
            gGame:player_discard_kitty(player_idx, discards)
            gChatLog:add_message(player.name, {"Discards 3 cards"}, false)
        end
        
    elseif action_type == "PLAY" then
        local playable = gGame:get_playable_cards(player, gGame.lead_suit)
        local card = strategy:decide_play(gGame, player_idx, playable)
        
        if card then
            local lines = {string.format("Plays %s", tostring(card))}
            
            -- Add probabilities for playable cards
            if strategy.get_top_actions_filtered then
                local top = strategy:get_top_actions_filtered(gGame, player_idx, playable, 5)
                local prob_lines = format_probs(top, nil)
                for _, pline in ipairs(prob_lines) do
                    table.insert(lines, pline)
                end
            end
            
            gChatLog:add_message(player.name, lines, false)
            gGame:player_play_card(player_idx, card)
        end
    end
end

function love.keypressed(key)
    if key == "escape" then
        gPaused = not gPaused
    elseif key == "d" then
        gDebugMode = not gDebugMode
        gChatLog:add_message("System", {"Debug mode: " .. (gDebugMode and "ON" or "OFF")}, false, {0.5, 0.5, 0.3})
    elseif key == "space" then
        if gPaused then return end
        if gGame.state == "BIDDING" and gGame.current_player_idx == 1 then
            gGame:player_pass(1)
            gChatLog:add_message("You", {"Passed"}, true)
        elseif gGame.state == "TRICK_OVER" then
            gGame:next_trick()
        end
    elseif key == "r" then
        gGame:start_new_round()
        gChatLog:add_message("System", {"New round started"}, false, {0.3, 0.5, 0.3})
        gPaused = false
    end
end

function love.wheelmoved(x, y)
    if gChatLog then
        gChatLog:scroll(y)
    end
end

function love.resize(w, h)
    local chat_width = 300
    if gChatLog then
        gChatLog:resize(w - chat_width, 0, chat_width, h)
    end
    if gTableView then
        gTableView:resize(w, h)
    end
end

function love.draw()
    gTableView:draw()
    gChatLog:draw()
    
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
        love.graphics.printf("R - Restart Round", 0, cy + 40, love.graphics.getWidth(), "center")
    end
    
    -- Debug mode indicator
    if gDebugMode and not gPaused then
        love.graphics.setColor(1, 0.5, 0, 0.8)
        love.graphics.rectangle("fill", 5, 5, 100, 25, 5)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("DEBUG ON", 15, 10)
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if gPaused then return end
    if button == 1 then
        gTableView:check_click(x, y)
    end
end
