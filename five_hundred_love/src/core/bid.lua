local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Suit = CardModule.Suit

local BidType = {
    SUIT_TRUMP = "Suit Trump",
    NO_TRUMP = "No Trump",
    MISERE = "Misere",
    OPEN_MISERE = "Open Misere"
}

local MISERE_POINTS = 250
local OPEN_MISERE_POINTS = 500

-- Avondale Scoring Table
-- Keys are trick counts (6-10)
-- Values are arrays of points indexed by Suit Order: [Spades, Clubs, Diamonds, Hearts, NoTrump]
-- Note: Lua arrays are 1-indexed. We need to map Suit Enum (0-4) to 1-5.
local AVONDALE_POINTS_TABLE = {
    [6]  = {40,  60,  80,  100, 120},
    [7]  = {140, 160, 180, 200, 220},
    [8]  = {240, 260, 280, 300, 320},
    [9]  = {340, 360, 380, 400, 420},
    [10] = {440, 460, 480, 500, 520},
}

-- Map suit enum values to index in points array
-- Suit.SPADES=3?? Wait, check card.lua
-- Card.lua: SPADES=3, CLUBS=0, DIAMONDS=1, HEARTS=2, NO_TRUMP=4
-- Python SUIT_BID_ORDER = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP]
-- So mapping: 
-- SPADES(3) -> 1
-- CLUBS(0) -> 2
-- DIAMONDS(1) -> 3
-- HEARTS(2) -> 4
-- NO_TRUMP(4) -> 5
local SUIT_ORDER_MAP = {
    [Suit.SPADES] = 1,
    [Suit.CLUBS] = 2,
    [Suit.DIAMONDS] = 3,
    [Suit.HEARTS] = 4,
    [Suit.NO_TRUMP] = 5
}

local Bid = Utils.class("Bid")

function Bid:init(player, tricks, suit, bid_type)
    self.player = player
    self.tricks = tricks
    self.suit = suit
    self.bid_type = bid_type
    
    -- Validation
    if tricks < 0 or tricks > 10 then error("Tricks must be 0-10") end
    
    if bid_type == BidType.SUIT_TRUMP then
        if not suit or suit == Suit.NO_TRUMP then error("Suit required for SUIT_TRUMP") end
        if tricks < 6 then error("Suit bids must be 6+") end
    elseif bid_type == BidType.NO_TRUMP then
        if tricks < 6 then error("NT bids must be 6+") end
        self.suit = Suit.NO_TRUMP -- Canonicalize
    elseif bid_type == BidType.MISERE or bid_type == BidType.OPEN_MISERE then
        if tricks ~= 0 then error("Misere must be 0 tricks") end
        self.suit = Suit.NO_TRUMP -- Canonical for Misere
    end
    
    self.points = self:calculate_points()
end

function Bid:calculate_points()
    if self.bid_type == BidType.MISERE then return MISERE_POINTS end
    if self.bid_type == BidType.OPEN_MISERE then return OPEN_MISERE_POINTS end
    
    local suit_idx = SUIT_ORDER_MAP[self.suit]
    if not suit_idx then error("Invalid suit for points calc") end
    
    local row = AVONDALE_POINTS_TABLE[self.tricks]
    if not row then error("Invalid trick count for points calc") end
    
    return row[suit_idx]
end

function Bid:get_bidding_rank()
    return self.points
end

-- Comparison
function Bid:__lt(other)
    return self:get_bidding_rank() < other:get_bidding_rank()
end

function Bid:__le(other)
    return self:get_bidding_rank() <= other:get_bidding_rank()
end

function Bid:__tostring()
    if self.bid_type == BidType.MISERE then return string.format("%s Misere (%d)", self.player.name, self.points) end
    if self.bid_type == BidType.OPEN_MISERE then return string.format("%s Open Misere (%d)", self.player.name, self.points) end
    
    local suit_name = "No Trump"
    if self.suit and self.suit ~= Suit.NO_TRUMP then 
        -- Helper to get name? Or just hardcode common ones
        local names = {[0]="Clubs", [1]="Diamonds", [2]="Hearts", [3]="Spades"}
        suit_name = names[self.suit] or "Unknown"
    end
    
    return string.format("%s bids %d %s (%d)", self.player.name, self.tricks, suit_name, self.points)
end

return {
    Bid = Bid,
    BidType = BidType,
    MISERE_POINTS = MISERE_POINTS,
    OPEN_MISERE_POINTS = OPEN_MISERE_POINTS
}
