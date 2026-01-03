-- Helper to allow requiring modules from src
package.path = package.path .. ";five_hundred_love/?.lua;?.lua"

-- Mock 'love' table if missing
if not love then
    love = {
        filesystem = {
            read = function(path)
                local f = io.open(path, "r")
                if not f then return nil end
                local c = f:read("*a")
                f:close()
                return c
            end
        },
        math = math
    }
end

local Game = require "src.core.game"
local Bot = require "src.ai.bot"
local Player = require "src.core.player"

print("--- Starting Headless Logic Test ---")

-- Setup Game with 1 Bot and 3 Dummy Players (or 4 Bots)
-- We need to manually construct because Game:init uses Player.new by default
-- But we want to inject Bots.
-- I'll modify the players after init.

local game = Game.new({"Bot1", "Bot2", "Bot3", "Bot4"}, {"Team A", "Team B"})

-- Replace with Bots using real weights
local weights_path = "five_hundred_love/assets/weights.json"
local bot1 = Bot.new("Bot1", weights_path)
local bot2 = Bot.new("Bot2", weights_path)
local bot3 = Bot.new("Bot3", weights_path)
local bot4 = Bot.new("Bot4", weights_path)

game.players = {bot1, bot2, bot3, bot4}
-- Re-link teams
game.teams[1].players = {bot1, bot3}
game.teams[2].players = {bot2, bot4}

game:start_new_round()

-- Simulation Loop
local max_steps = 1000
local step = 0

while step < max_steps do
    step = step + 1
    
    if game.state == Game.STATE.GAME_OVER or game.state == Game.STATE.ROUND_OVER then
        print("Round/Game Over reached!")
        break
    end
    
    local p_idx = game.current_player_idx
    local player = game.players[p_idx]
    
    if game.state == Game.STATE.BIDDING then
       -- Bot Bid
       local action, params = player:decide_bid(game)
       if action == "bid" then
           local success, err = game:player_bid(p_idx, params[1], params[2], params[3])
           if not success then
               print("Bid failed: " .. err .. ". Force Pass.")
               game:player_pass(p_idx)
           end
       elseif action == "pass" then
           game:player_pass(p_idx)
       end
       
    elseif game.state == Game.STATE.KITTY then
        -- Simple discard (Bot logic for kitty not fully implemented in decide_bid?)
        -- Bot.decide_bid returns BID actions.
        -- We need decide_discard?
        -- My Bot.lua only has decide_bid and decide_play.
        -- I need to implement decide_discard or just hack it here.
        
        -- Hack: Discard first 3 cards
        local discards = {player.hand[1], player.hand[2], player.hand[3]}
        game:player_discard_kitty(p_idx, discards)
        
    elseif game.state == Game.STATE.PLAYING then
        -- Bot Play
        local playable = game:get_playable_cards(player, game.lead_suit)
        local card = player:decide_play(game, playable)
        
        local success, err = game:player_play_card(p_idx, card)
        if not success then
            print("Play failed: " .. (err or "Unknown") .. ". Force generic play.")
            -- If bot failed, try first playable
            game:player_play_card(p_idx, playable[1])
        end
    end
end

if step >= max_steps then
    print("Test timed out (max steps)")
else
    print("Test finished successfully.")
end
