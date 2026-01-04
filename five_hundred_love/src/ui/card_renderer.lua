local CardAtlas = require "src.ui.card_atlas"

local CardRenderer = {}

local CardWidth = 140  -- Kenney size
local CardHeight = 190
local RenderScale = 0.6 -- Scale down to match game size (~84x114)

local TiltShader = love.graphics.newShader("src/shaders/tilt.glsl")

-- Single cached mesh
local Mesh = nil

function CardRenderer.draw_card(card, x, y, scale, face_up, hovered, params)
    -- Init Mesh if needed (Position + UV + Color)
    if not Mesh then
        local format = {
            {"VertexPosition", "float", 2},
            {"VertexTexCoord", "float", 2},
            {"VertexColor", "byte", 4}
        }
        Mesh = love.graphics.newMesh(format, 4, "fan", "dynamic") -- Dynamic for UV updates
    end

    scale = scale or 1
    -- Adjust scale for high-res assets
    scale = scale * RenderScale
    
    params = params or {}
    local scale_x = params.scale_x or 1.0
    local scale_y = params.scale_y or 1.0
    local rotation = params.rotation or 0
    local kx = params.kx or 0
    local ky = params.ky or 0
    local shadow_off = params.shadow_offset or 5
    
    local w, h = CardWidth, CardHeight
    local hw, hh = w/2, h/2
    
    if hovered then
        y = y - 10
        shadow_off = shadow_off + 10
    end
    
    -- Get Texture & Quad
    local tex, quad
    if face_up then
        tex = CardAtlas.image
        quad = CardAtlas.get_quad(card)
    else
        tex = CardAtlas.back_image
        quad = CardAtlas.get_back_quad()
    end
    
    -- Safety Fallback
    if not tex or not quad then return end -- Or draw debug
    
    -- Update UVs based on Quad
    local qx, qy, qw, qh = quad:getViewport()
    local tw, th = tex:getDimensions()
    
    local u0, v0 = qx/tw, qy/th
    local u1, v1 = (qx+qw)/tw, (qy+qh)/th
    
    -- Update Vertices (Pos + UV)
    local c = {255, 255, 255, 255}
    Mesh:setVertex(1, -hw, -hh, u0, v0, unpack(c)) -- TL
    Mesh:setVertex(2,  hw, -hh, u1, v0, unpack(c)) -- TR
    Mesh:setVertex(3,  hw,  hh, u1, v1, unpack(c)) -- BR
    Mesh:setVertex(4, -hw,  hh, u0, v1, unpack(c)) -- BL
    
    -- DRAW SHADOW (Solid Black Mesh)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.setShader(TiltShader)
    TiltShader:send("pitch", kx)
    TiltShader:send("roll", ky)
    
    -- Disable texture for shadow shape (uses white pixel or we set color uniform?)
    -- Mesh format has UVs, if we bind nil texture, love uses white.
    Mesh:setTexture(nil)
    
    love.graphics.push()
    love.graphics.translate(x + (w*scale)/2 + shadow_off, y + (h*scale)/2 + shadow_off)
    love.graphics.rotate(rotation)
    love.graphics.scale(scale * scale_x, scale * scale_y)
    love.graphics.draw(Mesh, 0, 0)
    love.graphics.pop()
    
    -- DRAW CARD (Texture)
    love.graphics.setColor(1, 1, 1, 1)
    Mesh:setTexture(tex)
    
    love.graphics.push()
    love.graphics.translate(x + (w*scale)/2, y + (h*scale)/2) 
    love.graphics.rotate(rotation)
    love.graphics.scale(scale * scale_x, scale * scale_y)
    love.graphics.draw(Mesh, 0, 0)
    love.graphics.pop()
    
    love.graphics.setShader()
end

return CardRenderer
