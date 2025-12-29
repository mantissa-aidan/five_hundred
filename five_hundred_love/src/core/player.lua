local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local Player = Utils.class("Player")

function Player:init(name)
    self.name = name
    self.hand = {}
    self.score = 0
    self.tricks_won_this_round = 0
end

function Player:add_card_to_hand(card)
    table.insert(self.hand, card)
end

function Player:add_cards_to_hand(cards)
    for _, card in ipairs(cards) do
        table.insert(self.hand, card)
    end
end

function Player:play_card(card_to_play)
    -- Find and remove card
    for i, card in ipairs(self.hand) do
        if card == card_to_play then -- Uses Card.__eq if defined in metatable
            table.remove(self.hand, i)
            return card
        end
    end
    error("Card not in hand")
end

function Player:sort_hand()
    -- Sort by Suit (value) then Rank (value descending)
    -- Lua sort: returns true if a < b
    table.sort(self.hand, function(a, b)
        if a.suit ~= b.suit then
            return a.suit < b.suit
        else
            -- Joker check? 
            -- Rank.JOKER is 100, Ace is 14.
            -- If we want descending rank:
            return a.rank > b.rank
        end
    end)
end

function Player:reset_for_new_round()
    self.hand = {}
    self.tricks_won_this_round = 0
end

function Player:increment_score(points)
    self.score = self.score + points
end

function Player:increment_tricks_won()
    self.tricks_won_this_round = self.tricks_won_this_round + 1
end

function Player:__tostring()
    return string.format("%s (Score: %d)", self.name, self.score)
end

return Player
