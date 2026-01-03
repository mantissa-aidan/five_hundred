local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local Deck = Utils.class("Deck")

function Deck:init()
    self.cards = {}
    self:create_deck()
end

function Deck:create_deck()
    self.cards = {}
    local all_suits = {Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS}
    local value_ranks = {
        Rank.FIVE, Rank.SIX, Rank.SEVEN, Rank.EIGHT, Rank.NINE,
        Rank.TEN, Rank.JACK, Rank.QUEEN, Rank.KING, Rank.ACE
    }
    
    -- Standard 40 cards (5-A)
    for _, suit in ipairs(all_suits) do
        for _, rank in ipairs(value_ranks) do
            table.insert(self.cards, Card.new(suit, rank))
        end
    end
    
    -- Two Red 4s (Hearts, Diamonds)
    table.insert(self.cards, Card.new(Suit.HEARTS, Rank.FOUR))
    table.insert(self.cards, Card.new(Suit.DIAMONDS, Rank.FOUR))
    
    -- Joker
    table.insert(self.cards, Card.new(Suit.NO_TRUMP, Rank.JOKER))
end

function Deck:shuffle()
    -- Standard Fisher-Yates
    for i = #self.cards, 2, -1 do
        local j = math.random(i)
        self.cards[i], self.cards[j] = self.cards[j], self.cards[i]
    end
end

function Deck:deal(num_cards)
    if num_cards < 0 then error("Cannot deal negative cards") end
    if num_cards > #self.cards then error("Not enough cards in deck") end
    
    local dealt = {}
    for i = 1, num_cards do
        -- Pop from front (or back is more efficient in Lua, but deal() usually implies top)
        -- Removing from index 1 shifts eveything, which is O(N).
        -- But N is small (43).
        table.insert(dealt, table.remove(self.cards, 1))
    end
    return dealt
end

function Deck:__len__()
    return #self.cards
end

function Deck:__tostring()
    return string.format("Deck(%d cards)", #self.cards)
end

return Deck
