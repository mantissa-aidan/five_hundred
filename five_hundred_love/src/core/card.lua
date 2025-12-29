local Utils = require "src.core.utils"

local Suit = {
    CLUBS = 0,
    DIAMONDS = 1,
    HEARTS = 2,
    SPADES = 3,
    NO_TRUMP = 4
}

local Rank = {
    FOUR = 4,
    FIVE = 5,
    SIX = 6,
    SEVEN = 7,
    EIGHT = 8,
    NINE = 9,
    TEN = 10,
    JACK = 11,
    QUEEN = 12,
    KING = 13,
    ACE = 14,
    JOKER = 100
}

-- Reversals for string formatting
local SuitNames = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades", [4]="NoTrump"}
local RankNames = {[4]="Four", [5]="Five", [6]="Six", [7]="Seven", [8]="Eight", 
                   [9]="Nine", [10]="Ten", [11]="Jack", [12]="Queen", [13]="King", 
                   [14]="Ace", [100]="Joker"}

local Card = Utils.class("Card")

function Card:init(suit, rank)
    if rank == Rank.JOKER then
        if suit ~= Suit.NO_TRUMP then
            suit = Suit.NO_TRUMP
        end
    elseif suit == Suit.NO_TRUMP then
        error("NO_TRUMP suit is reserved for Joker only.")
    end
    
    self.suit = suit
    self.rank = rank
end

function Card:is_joker()
    return self.rank == Rank.JOKER
end

function Card:__tostring()
    if self:is_joker() then
        return "Joker"
    end
    return string.format("%s of %s", RankNames[self.rank] or self.rank, SuitNames[self.suit] or self.suit)
end

function Card.__eq(a, b)
    return a.suit == b.suit and a.rank == b.rank
end

return {
    Card = Card,
    Suit = Suit,
    Rank = Rank
}
