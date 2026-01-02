-- ChatLog View
-- Scrollable chat-style log for game actions

local Utils = require "src.core.utils"
local Config = require "src.config"

local ChatLog = Utils.class("ChatLog")

function ChatLog:init(x, y, w, h)
    self.x = x
    self.y = y
    self.width = w
    self.height = h
    
    self.messages = {}
    self.scroll_offset = 0
    self.line_height = 18
    self.padding = 10
    self.padding_bottom = 15
    self.message_gap = 8
    
    -- Colors
    self.bg_color = Config.colors.chat_bg
    self.self_color = {0.2, 0.4, 0.7}
    self.other_color = {0.3, 0.3, 0.35}
    self.system_color = {0.25, 0.35, 0.25}
    
    -- Avatar colors
    self.avatar_colors = Config.colors.avatar
end

function ChatLog:resize(x, y, w, h)
    self.x = x
    self.y = y
    self.width = w
    self.height = h
    self:scroll_to_bottom()
end

function ChatLog:update(dt)
    -- No per-frame update needed yet
end

-- Add a message to the log
function ChatLog:add_message(sender, lines, is_self, color)
    local msg = {
        sender = sender,
        lines = lines,
        is_self = is_self,
        color = color,
        timestamp = love.timer.getTime()
    }
    table.insert(self.messages, msg)
    self:scroll_to_bottom()
end

function ChatLog:scroll_to_bottom()
    local total_height = self:get_total_height()
    local visible_height = self.height - 2 * self.padding
    self.scroll_offset = math.max(0, total_height - visible_height)
end

function ChatLog:get_total_height()
    local total = 0
    for _, msg in ipairs(self.messages) do
        total = total + self.line_height + (#msg.lines * self.line_height) + self.message_gap
    end
    return total + self.padding_bottom
end

function ChatLog:scroll(delta)
    self.scroll_offset = self.scroll_offset - delta * 30
    local max_scroll = math.max(0, self:get_total_height() - (self.height - 2 * self.padding))
    self.scroll_offset = math.max(0, math.min(self.scroll_offset, max_scroll))
end

function ChatLog:draw()
    -- Background
    love.graphics.setColor(self.bg_color)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 5)
    
    -- Border
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 5)
    
    -- Title
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Game Log", self.x + self.padding, self.y + 5)
    
    -- Set up scissor for clipping
    love.graphics.setScissor(self.x, self.y + 25, self.width, self.height - 25)
    
    local draw_y = self.y + 30 - self.scroll_offset
    local content_width = self.width - 2 * self.padding
    local bubble_max_width = content_width * 0.8
    local avatar_size = 24
    
    for _, msg in ipairs(self.messages) do
        local bubble_width = bubble_max_width
        local bubble_height = self.line_height + (#msg.lines * self.line_height)
        
        -- Alignment Logic (Swapped as requested)
        -- Self/System -> LEFT taking up left side
        -- Bots -> RIGHT taking up right side
        
        local bubble_x
        local avatar_x
        
        local is_left_side = msg.is_self or msg.sender == "System"
        
        if is_left_side then
            -- Left (You / System)
            avatar_x = self.x + self.padding
            bubble_x = avatar_x + avatar_size + 10
            
            love.graphics.setColor(msg.is_self and self.self_color or self.system_color)
        else
            -- Right (Bots / Others)
            avatar_x = self.x + self.width - self.padding - avatar_size
            bubble_x = avatar_x - 10 - bubble_width
            
            love.graphics.setColor(msg.color or self.other_color)
        end
        
        -- Draw Bubble
        love.graphics.rectangle("fill", bubble_x, draw_y, bubble_width, bubble_height, 5)
        
        -- Draw Avatar
        local ac = self.avatar_colors[msg.sender] or {0.5, 0.5, 0.5}
        love.graphics.setColor(ac)
        love.graphics.circle("fill", avatar_x + avatar_size/2, draw_y + avatar_size/2, avatar_size/2)
        
        -- Avatar Initial
        love.graphics.setColor(1, 1, 1)
        local initial = string.sub(msg.sender, 1, 1)
        love.graphics.printf(initial, avatar_x, draw_y + 4, avatar_size, "center")
        
        -- Draw Sender Name (Inside bubble or above? Inside for now)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print(msg.sender, bubble_x + 5, draw_y + 2)
        
        -- Draw Content Lines
        love.graphics.setColor(1, 1, 1)
        for i, line in ipairs(msg.lines) do
            love.graphics.print(line, bubble_x + 5, draw_y + self.line_height * i)
        end
        
        draw_y = draw_y + bubble_height + self.message_gap
    end
    
    -- Reset scissor
    love.graphics.setScissor()
    
    -- Scroll indicator
    local total_height = self:get_total_height()
    local visible_height = self.height - 30
    if total_height > visible_height then
        local scroll_ratio = self.scroll_offset / (total_height - visible_height)
        local indicator_height = math.max(20, visible_height * (visible_height / total_height))
        local indicator_y = self.y + 25 + scroll_ratio * (visible_height - indicator_height)
        
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.rectangle("fill", self.x + self.width - 5, indicator_y, 4, indicator_height, 2)
    end
end

return ChatLog
