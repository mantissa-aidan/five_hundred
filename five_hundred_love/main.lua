local Game = require "src.core.game"
local TableView = require "src.ui.table_view"

function love.load()
    -- Initialize Game
    -- Names for players
    local player_names = {"Human", "Bot 1", "Partner", "Bot 3"}
    local team_names = {"Team A", "Team B"}
    
    gGame = Game.new(player_names, team_names)
    gGame:start_new_round()
    
    -- Initialize View
    gTableView = TableView.new(gGame)
    
    print("Five Hundred - Love2D Version Started")
end

function love.update(dt)
    gGame:update(dt)
    gTableView:update(dt)
    
    -- Simple input for debugging: Space to advance/pass
    
end

function love.keypressed(key)
    if key == "space" then
        -- Auto-pass for debugging
        if gGame.state == "BIDDING" then
            gGame:player_pass(gGame.current_player_idx)
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

