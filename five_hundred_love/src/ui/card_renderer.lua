local CardModule = require "src.core.card"
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local CardRenderer = {}

local CardWidth = 80
local CardHeight = 110

-- Simple abbreviated chars or symbols
local SuitChars = {
    [Suit.CLUBS] = "C",
    [Suit.DIAMONDS] = "D",
    [Suit.HEARTS] = "H",
    [Suit.SPADES] = "S",
    [Suit.NO_TRUMP] = "NT"
}

local RankChars = {
    [Rank.FOUR] = "4", [Rank.FIVE] = "5", [Rank.SIX] = "6", [Rank.SEVEN] = "7",
    [Rank.EIGHT] = "8", [Rank.NINE] = "9", [Rank.TEN] = "10", [Rank.JACK] = "J",
    [Rank.QUEEN] = "Q", [Rank.KING] = "K", [Rank.ACE] = "A", [Rank.JOKER] = "JKR"
}

function CardRenderer.draw_card(card, x, y, scale, face_up, hovered)
    scale = scale or 1
    local w = CardWidth * scale
    local h = CardHeight * scale
    
    if hovered then
        y = y - 10 -- Pop up effect
    end
    
    -- Draw Background
    love.graphics.setColor(1, 1, 1) -- White
    love.graphics.rectangle("fill", x, y, w, h, 5 * scale, 5 * scale)
    
    -- Draw Border
    love.graphics.setColor(0, 0, 0)
    love.graphics.setLineWidth(2 * scale)
    love.graphics.rectangle("line", x, y, w, h, 5 * scale, 5 * scale)
    
    if not face_up then
        -- Draw Back Design (Blue pattern)
        love.graphics.setColor(0.2, 0.4, 0.8)
        love.graphics.rectangle("fill", x + 5*scale, y + 5*scale, w - 10*scale, h - 10*scale, 2*scale)
        return
    end
    
    -- Determine Color
    if card.suit == Suit.DIAMONDS or card.suit == Suit.HEARTS then
        love.graphics.setColor(0.8, 0, 0) -- Red
    else
        love.graphics.setColor(0, 0, 0) -- Black
    end
    
    if card:is_joker() then
        love.graphics.setColor(0.5, 0, 0.5) -- Purple for Joker?
        local r_str = RankChars[card.rank]
        love.graphics.print(r_str, x + 5*scale, y + 5*scale, 0, scale, scale)
        -- Center graphic
        love.graphics.print("★", x + w/2 - 5*scale, y + h/2 - 10*scale, 0, 2*scale, 2*scale)
    else
        local r_str = RankChars[card.rank]
        local s_str = SuitChars[card.suit]
        
        -- Top Left
        love.graphics.print(r_str, x + 5*scale, y + 5*scale, 0, scale, scale)
        love.graphics.print(s_str, x + 5*scale, y + 20*scale, 0, scale, scale)
        
        -- Center Large Suit
        love.graphics.print(s_str, x + w/2 - 10*scale, y + h/2 - 15*scale, 0, 2*scale, 2*scale)
        
        -- Bottom Right (Rotated?) - Simplification: Just draw normally for now
        -- love.graphics.print(r_str, x + w - 15*scale, y + h - 15*scale, 0, scale, scale)
    end
end

return CardRenderer
