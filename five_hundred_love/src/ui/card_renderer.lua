local CardModule = require "src.core.card"
local Suit = CardModule.Suit
local Rank = CardModule.Rank

local CardRenderer = {}

local CardWidth = 80
local CardHeight = 110

local TiltShader = love.graphics.newShader("src/shaders/tilt.glsl")

-- Unicode suit symbols (requires DejaVu Sans font)
local SuitChars = {
    [Suit.CLUBS] = "♣",
    [Suit.DIAMONDS] = "♦",
    [Suit.HEARTS] = "♥",
    [Suit.SPADES] = "♠",
    [Suit.NO_TRUMP] = "NT"
}

local RankChars = {
    [Rank.FOUR] = "4", [Rank.FIVE] = "5", [Rank.SIX] = "6", [Rank.SEVEN] = "7",
    [Rank.EIGHT] = "8", [Rank.NINE] = "9", [Rank.TEN] = "10", [Rank.JACK] = "J",
    [Rank.QUEEN] = "Q", [Rank.KING] = "K", [Rank.ACE] = "A", [Rank.JOKER] = "JKR"
}

-- Cache for card canvases to avoid redrawing every frame
local CardCanvasCache = {}
local BackCanvas = nil
local Mesh = nil 

function CardRenderer.get_card_canvas(card)
    local key = tostring(card)
    if not CardCanvasCache[key] then
        local prev_canvas = love.graphics.getCanvas()
        
        local canvas = love.graphics.newCanvas(CardWidth, CardHeight)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0,0,0,0) -- Transparent
        
        -- RESET TRANSFORM for Canvas Drawing
        love.graphics.push()
        love.graphics.origin()
        
        -- Draw background
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, CardWidth, CardHeight, 5)
        
        -- Draw Border
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 0, 0, CardWidth, CardHeight, 5)
        
        -- Determine Color
        if card.suit == Suit.DIAMONDS or card.suit == Suit.HEARTS then
            love.graphics.setColor(0.8, 0, 0, 1) -- Red
        else
            love.graphics.setColor(0, 0, 0, 1) -- Black
        end
        
        local scale = 1.0 
        
        if card:is_joker() then
            love.graphics.setColor(0.5, 0, 0.5, 1)
            local r_str = RankChars[card.rank]
            love.graphics.print(r_str, 5, 5, 0, scale, scale)
            love.graphics.print("★", CardWidth/2 - 10, CardHeight/2 - 15, 0, 2, 2)
        else
            local r_str = RankChars[card.rank]
            local s_str = SuitChars[card.suit]
            
            -- Top Left
            love.graphics.print(r_str, 5, 5, 0, scale, scale)
            love.graphics.print(s_str, 5, 20, 0, scale, scale)
            
            -- Center Large Suit
            love.graphics.print(s_str, CardWidth/2 - 10, CardHeight/2 - 15, 0, 2, 2)
            
            -- Bottom Right (Rotated)
            love.graphics.push()
            love.graphics.translate(CardWidth - 5, CardHeight - 5)
            love.graphics.rotate(math.pi)
            love.graphics.print(r_str, 0, 0, 0, scale, scale)
            love.graphics.print(s_str, 0, 15, 0, scale, scale)
            love.graphics.pop()
        end
        
        love.graphics.pop() -- Restore Transform
        love.graphics.setCanvas(prev_canvas)
        CardCanvasCache[key] = canvas
    end
    return CardCanvasCache[key]
end

function CardRenderer.get_back_canvas()
    if not BackCanvas then
        local prev_canvas = love.graphics.getCanvas()
        
        BackCanvas = love.graphics.newCanvas(CardWidth, CardHeight)
        love.graphics.setCanvas(BackCanvas)
        
        -- RESET TRANSFORM
        love.graphics.push()
        love.graphics.origin()
        
        -- Draw Background
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, CardWidth, CardHeight, 5)
        
        -- Draw Border
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 0, 0, CardWidth, CardHeight, 5)
        
        -- Draw Pattern
        love.graphics.setColor(0.2, 0.4, 0.8, 1)
        love.graphics.rectangle("fill", 5, 5, CardWidth - 10, CardHeight - 10, 2)
        
        love.graphics.pop() -- Restore
        love.graphics.setCanvas(prev_canvas)
    end
    return BackCanvas
end

function CardRenderer.draw_card(card, x, y, scale, face_up, hovered, params)
    if not Mesh then
        -- Init generic mesh with EXPLICIT format (Position + UV + Color)
        -- Centered Mesh (-W/2 to W/2) for easier rotation
        local format = {
            {"VertexPosition", "float", 2},
            {"VertexTexCoord", "float", 2},
            {"VertexColor", "byte", 4}
        }
        Mesh = love.graphics.newMesh(format, 4, "fan", "static")
        
        local w, h = CardWidth, CardHeight
        local hw, hh = w/2, h/2
        local c = {255, 255, 255, 255}
        
        -- Static Vertices (Centered)
        Mesh:setVertex(1, -hw, -hh, 0, 0, unpack(c)) -- TL
        Mesh:setVertex(2,  hw, -hh, 1, 0, unpack(c)) -- TR
        Mesh:setVertex(3,  hw,  hh, 1, 1, unpack(c)) -- BR
        Mesh:setVertex(4, -hw,  hh, 0, 1, unpack(c)) -- BL
    end

    scale = scale or 1
    params = params or {}
    
    local scale_x = params.scale_x or 1.0
    local scale_y = params.scale_y or 1.0
    local rotation = params.rotation or 0
    local kx = params.kx or 0 -- Tilt X (Up/Down) -> Perspective Top/Bottom width
    local ky = params.ky or 0 -- Tilt Y (Left/Right) -> Perspective Left/Right height
    local shadow_off = params.shadow_offset or 5
    
    -- Dimensions
    local w, h = CardWidth, CardHeight
    
    if hovered then
        y = y - 10
        shadow_off = shadow_off + 10
    end
    
    -- Texture
    local canvas
    if face_up then
        canvas = CardRenderer.get_card_canvas(card)
    else
        canvas = CardRenderer.get_back_canvas()
    end
    Mesh:setTexture(canvas)
    
    -- Draw Shadow (3D Mesh to match card shape)
    love.graphics.setColor(0, 0, 0, 0.4)
    
    love.graphics.setShader(TiltShader)
    TiltShader:send("pitch", kx)
    TiltShader:send("roll", ky)
    
    -- Draw Shadow using Mesh (No Texture for solid shape)
    Mesh:setTexture(nil)
    
    love.graphics.push()
    love.graphics.translate(x + w*scale/2 + shadow_off, y + h*scale/2 + shadow_off)
    love.graphics.rotate(rotation)
    love.graphics.scale(scale * scale_x, scale * scale_y)
    love.graphics.draw(Mesh, 0, 0)
    love.graphics.pop()
    
    -- Draw Card Mesh with Shader
    love.graphics.setColor(1, 1, 1, 1)
    Mesh:setTexture(canvas) -- Restore canvas texture for main card
    
    love.graphics.push()
    love.graphics.translate(x + w*scale/2, y + h*scale/2) 
    love.graphics.rotate(rotation)
    love.graphics.scale(scale * scale_x, scale * scale_y)
    love.graphics.draw(Mesh, 0, 0)
    love.graphics.pop()
    
    love.graphics.setShader() -- Reset
end

return CardRenderer
