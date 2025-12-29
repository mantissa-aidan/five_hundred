local Utils = require "src.core.utils"

local Team = Utils.class("Team")

function Team:init(name, players)
    if #players > 2 then error("Team size limit 2") end
    self.name = name
    self.players = players
    self.team_score = 0
    self.has_bid_this_round = false
end

function Team:update_score(points)
    self.team_score = self.team_score + points
end

function Team:get_total_tricks_won_this_round()
    local total = 0
    for _, p in ipairs(self.players) do
        total = total + p.tricks_won_this_round
    end
    return total
end

function Team:reset_for_new_round()
    self.has_bid_this_round = false
    for _, p in ipairs(self.players) do
        p:reset_for_new_round()
    end
end

function Team:__tostring()
    return string.format("%s (Score: %d)", self.name, self.team_score)
end

return Team
