local Utils = require "src.core.utils"
local Config = require "src.config"

local Button = Utils.class("Button")

function Button:init(x, y, w, h, text, type, callback)
    self.x = x or 0
    self.y = y or 0
    self.w = w or 100
    self.h = h or 40
    self.text = text or "Button"
    
    -- "type" determines sound profile: 'normal', 'bid', 'action'
    self.type = type or "normal"
    
    self.callback = callback
    
    -- State
    self.hovered = false
    self.pressed = false
    self.spring = {val=1, target=1, vel=0}
    self.disabled = false
    
    -- Style
    self.color = {0.3, 0.3, 0.3}     -- Default gray
    self.hover_color = {0.4, 0.4, 0.45}
    self.press_color = {0.2, 0.2, 0.2}
    self.text_color = {1, 1, 1}
    self.corner_radius = 5
end

function Button:update(dt)
    -- Physics
    local s = self.spring
    local diff = s.target - s.val
    local k = 300 -- Stiffness
    local d = 20  -- Damping
    local f = diff * k
    s.vel = s.vel * (1 - d*dt) + f*dt
    s.val = s.val + s.vel * dt
    
    if self.disabled then 
        self.spring.target = 1.0
        return 
    end
    
    -- Hover Detection
    local mx, my = love.mouse.getPosition()
    local was_hovered = self.hovered
    self.hovered = (mx >= self.x and mx <= self.x + self.w and
                    my >= self.y and my <= self.y + self.h)
                    
    -- Hover Entry
    if self.hovered and not was_hovered then
        s.target = 1.15 -- Scale up on hover
        self:play_sound("HOVER")
    elseif not self.hovered and was_hovered then
        s.target = 1.0
    end
end

function Button:draw(alpha)
    alpha = alpha or 1.0
    love.graphics.push()
    
    -- Center pivot for scaling
    local cx = self.x + self.w/2
    local cy = self.y + self.h/2
    love.graphics.translate(cx, cy)
    love.graphics.scale(self.spring.val)
    love.graphics.translate(-self.w/2, -self.h/2)
    -- Now drawing at 0,0 relative to button top-left
    
    -- Background
    local col = self.color
    if self.disabled then
        col = {0.2, 0.2, 0.2}
    elseif self.hovered then
        col = self.hover_color
    end
    
    local r, g, b = unpack(col)
    love.graphics.setColor(r, g, b, 1.0 * alpha)
    love.graphics.rectangle("fill", 0, 0, self.w, self.h, self.corner_radius)
    
    -- Text
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    if self.disabled then
        love.graphics.setColor(0.5, 0.5, 0.5, 1.0 * alpha)
    else
        local tr, tg, tb = unpack(self.text_color)
        love.graphics.setColor(tr, tg, tb, 1.0 * alpha)
    end
    
    local font = love.graphics.getFont()
    local th = font:getHeight()
    local ty = (self.h - th) / 2
    love.graphics.printf(self.text, 0, ty, self.w, "center")
    
    love.graphics.pop()
end

function Button:click()
    if self.disabled then return end
    
    self:play_sound("CLICK")
    
    -- Small punch effect on click
    self.spring.vel = -10 
    
    if self.callback then
        self.callback()
    end
    return true
end

function Button:play_sound(event)
    if not gAudioManager then return end
    
    -- Map generic events to specific asset IDs based on button type
    local sfx_id = nil
    
    if self.type == "action" then -- e.g. Next Trick
        sfx_id = (event == "HOVER") and "NEXT_TRICK_HOVER" or "NEXT_TRICK_CLICK"
    elseif self.type == "bid" then
        sfx_id = (event == "HOVER") and "BID_HOVER" or "BID_CLICK"
    else -- "normal"
        sfx_id = (event == "HOVER") and "BTN_HOVER_1" or "BTN_CLICK_1"
    end
    
    if sfx_id then
        gAudioManager:play(sfx_id)
    end
end

return Button
