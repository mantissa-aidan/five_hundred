
local CardAtlas = {}
local CardModule = require "src.core.card" -- To verify enums

-- We need manual mapping because our enums (0,1,2,3) might not match XML names strictly
local SuitNames = {
    [0] = "Clubs",
    [1] = "Diamonds",
    [2] = "Hearts",
    [3] = "Spades"
}

-- XML names are: 2, 3, ..., 10, J, Q, K, A
-- Our Ranks are 2..14 (11=J, 12=Q, 13=K, 14=A)
local RankNames = {
    [11] = "J", [12] = "Q", [13] = "K", [14] = "A"
}

function CardAtlas.load()
    CardAtlas.image = love.graphics.newImage("assets/cards/playingCards.png")
    CardAtlas.back_image = love.graphics.newImage("assets/cards/playingCardBacks.png")
    
    local w, h = CardAtlas.image:getDimensions()
    CardAtlas.quads = {} -- [suit][rank] -> Quad
    
    -- Parse XML manually (simple regex)
    local xml_content = love.filesystem.read("assets/cards/playingCards.xml")
    
    if not xml_content then
        print("Error: Could not load playingCards.xml")
        return
    end
    
    -- Identify texture size from regex? No, just match subtextures.
    -- Pattern: <SubTexture name="cardClubs10.png" x="560" y="760" width="140" height="190"/>
    for name, x, y, cw, ch in xml_content:gmatch('SubTexture name="([^"]+)" x="(%d+)" y="(%d+)" width="(%d+)" height="(%d+)"') do
        -- name e.g. "cardClubs10.png"
        -- Parse name to get Suit and Rank
        -- Remove "card" prefix and ".png" suffix
        local clean = name:gsub("card", ""):gsub(".png", "")
        
        -- Special case: Joker
        if clean == "Joker" then
            CardAtlas.joker_quad = love.graphics.newQuad(tonumber(x), tonumber(y), tonumber(cw), tonumber(ch), w, h)
        else
            -- Split Suit and Rank
            -- Suits are Clubs, Diamonds, Hearts, Spades
            -- Rank is remainder
            local suit_str = nil
            local rank_str = nil
            
            for _, s in pairs({"Clubs", "Diamonds", "Hearts", "Spades"}) do
                if clean:find(s) == 1 then -- Starts with suit
                    suit_str = s
                    rank_str = clean:sub(#s + 1)
                    break
                end
            end
            
            if suit_str and rank_str then
                -- Map back to enums
                local suit_enum = nil
                for k, v in pairs(SuitNames) do 
                    if v == suit_str then suit_enum = k; break end 
                end
                
                local rank_enum = tonumber(rank_str)
                if not rank_enum then
                    -- Face card
                    if rank_str == "J" then rank_enum = 11
                    elseif rank_str == "Q" then rank_enum = 12
                    elseif rank_str == "K" then rank_enum = 13
                    elseif rank_str == "A" then rank_enum = 14 end
                end
                
                if suit_enum and rank_enum then
                    if not CardAtlas.quads[suit_enum] then CardAtlas.quads[suit_enum] = {} end
                    CardAtlas.quads[suit_enum][rank_enum] = love.graphics.newQuad(tonumber(x), tonumber(y), tonumber(cw), tonumber(ch), w, h)
                end
            end
        end
    end
    
    -- Setup Back Quad (Card 1 from backs sheet?)
    -- Assuming backs sheet is simple or also XML. 
    -- User provided valid png. Let's assume full image or grab first rect.
    -- Assuming 140x190
    local bw, bh = CardAtlas.back_image:getDimensions()
    -- Usually these packs have multiple backs. Let's use the full image properly or crop.
    -- Default to blue back (usually top left if multiple).
    -- Actually user provided png. Let's assume it has multiple backs.
    -- Let's arbitrarily pick the Red/Blue one at 0,0 or 140,0.
    -- Kenney cards are 140x190.
    CardAtlas.back_quad = love.graphics.newQuad(140, 0, 140, 190, bw, bh) -- 2nd one (usually blue)
end

function CardAtlas.get_quad(card)
    if not CardAtlas.image then CardAtlas.load() end
    
    if card:is_joker() then
        return CardAtlas.joker_quad
    end
    
    if CardAtlas.quads[card.suit] then
        return CardAtlas.quads[card.suit][card.rank]
    end
    return nil
end

function CardAtlas.get_back_quad()
    if not CardAtlas.image then CardAtlas.load() end
    return CardAtlas.back_quad
end

return CardAtlas
