local Game = require "src.core.game"
local TableView = require "src.ui.table_view"
local NNStrategy = require "src.ai.nn_strategy"
local HumanStrategy = require "src.ai.human_strategy"
local RandomStrategy = require "src.ai.random_strategy"

-- Player strategies (indexed by player position 1-4)
local strategies = {}

-- AI pacing timer
local ai_timer = 0
local AI_DELAY = 0.5 -- seconds between bot actions

function love.load()
    -- Initialize Game
    local player_names = {"Human", "Bot 1", "Partner", "Bot 3"}
    local team_names = {"Team A", "Team B"}
    
    gGame = Game.new(player_names, team_names)
    
    -- Setup strategies for each player
    -- Player 1 = Human, others = NN bots
    strategies[1] = HumanStrategy.new()
    
    -- Try to load NN strategy, fall back to Random if weights not available
    local nn_ok, nn_strat = pcall(function()
        return NNStrategy.new("assets/weights.json")
    end)
    
    if nn_ok then
        strategies[2] = nn_strat
        strategies[3] = NNStrategy.new("assets/weights.json")
        strategies[4] = NNStrategy.new("assets/weights.json")
    else
        print("[Controller] NN weights not found, using Random strategy")
        strategies[2] = RandomStrategy.new()
        strategies[3] = RandomStrategy.new()
        strategies[4] = RandomStrategy.new()
    end
    
    gGame:start_new_round()
    
    -- Initialize View
    gTableView = TableView.new(gGame)
    
    print("Five Hundred - Love2D Version Started")
end

function love.update(dt)
    gTableView:update(dt)
    
    -- Get current action request
    local action_type, player_idx = gGame:get_action_request()
    
    if not action_type or not player_idx then
        return -- Nothing to do (game over, etc)
    end
    
    local strategy = strategies[player_idx]
    
    -- If human strategy, wait for UI input
    if strategy:requires_input() then
        return
    end
    
    -- Bot strategies - add delay for pacing
    ai_timer = ai_timer + dt
    if ai_timer < AI_DELAY then
        return
    end
    ai_timer = 0
    
    -- Execute bot action based on action type
    if action_type == "BID" then
        local action, params = strategy:decide_bid(gGame, player_idx)
        if action == "pass" then
            gGame:player_pass(player_idx)
        elseif action == "bid" and params then
            gGame:player_bid(player_idx, params[1], params[2], params[3])
        end
        
    elseif action_type == "DISCARD" then
        local discards = strategy:decide_discard(gGame, player_idx)
        if discards then
            gGame:player_discard_kitty(player_idx, discards)
        end
        
    elseif action_type == "PLAY" then
        local player = gGame.players[player_idx]
        local playable = gGame:get_playable_cards(player, gGame.lead_suit)
        local card = strategy:decide_play(gGame, player_idx, playable)
        if card then
            gGame:player_play_card(player_idx, card)
        end
    end
end

function love.keypressed(key)
    if key == "space" then
        -- Auto-pass for debugging
        if gGame.state == "BIDDING" and gGame.current_player_idx == 1 then
            gGame:player_pass(1)
        elseif gGame.state == "TRICK_OVER" then
            gGame:next_trick()
        end
    elseif key == "r" then
        gGame:start_new_round()
    end
end

function love.draw()
    gTableView:draw()
end

function love.mousepressed(x, y, button, istouch, presses)
    if button == 1 then
        gTableView:check_click(x, y)
    end
end
