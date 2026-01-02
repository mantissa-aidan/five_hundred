-- ChatLog View
-- Scrollable chat-style log for game actions

local Utils = require "src.core.utils"

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
    self.message_gap = 8
    
    -- Colors
    self.bg_color = {0.1, 0.1, 0.15, 1.0} -- Opaque background
    self.self_color = {0.2, 0.5, 0.8}
    self.other_color = {0.3, 0.3, 0.35}
    self.system_color = {0.4, 0.4, 0.2}
end

function ChatLog:resize(x, y, w, h)
    self.x = x
    self.y = y
    self.width = w
    self.height = h
    self:scroll_to_bottom()
end

-- Add a message to the log
-- sender: name to display
-- lines: table of strings (each line of the message)
-- is_self: true if from human player (right-aligned)
-- color: optional override color
function ChatLog:add_message(sender, lines, is_self, color)
    local msg = {
        sender = sender,
        lines = lines,
        is_self = is_self,
        color = color,
        timestamp = love.timer.getTime()
    }
    table.insert(self.messages, msg)
    
    -- Auto-scroll to bottom
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
        -- Sender line + content lines + gap
        total = total + self.line_height + (#msg.lines * self.line_height) + self.message_gap
    end
    return total
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
    local bubble_max_width = content_width * 0.85
    
    for _, msg in ipairs(self.messages) do
        local bubble_width = bubble_max_width
        local bubble_height = self.line_height + (#msg.lines * self.line_height)
        
        local bubble_x
        if msg.is_self then
            -- Right-aligned
            bubble_x = self.x + self.width - self.padding - bubble_width
            love.graphics.setColor(self.self_color)
        elseif msg.sender == "System" then
            -- Center for system messages
            bubble_x = self.x + (self.width - bubble_width) / 2
            love.graphics.setColor(msg.color or self.system_color)
        else
            -- Left-aligned
            bubble_x = self.x + self.padding
            love.graphics.setColor(msg.color or self.other_color)
        end
        
        -- Draw bubble background
        love.graphics.rectangle("fill", bubble_x, draw_y, bubble_width, bubble_height, 5)
        
        -- Draw sender name
        love.graphics.setColor(1, 1, 1)
        if msg.is_self then
            love.graphics.printf(msg.sender, bubble_x, draw_y + 2, bubble_width - 5, "right")
        else
            love.graphics.print(msg.sender, bubble_x + 5, draw_y + 2)
        end
        
        -- Draw content lines
        love.graphics.setColor(0.9, 0.9, 0.9)
        for i, line in ipairs(msg.lines) do
            if msg.is_self then
                love.graphics.printf(line, bubble_x, draw_y + self.line_height * i, bubble_width - 5, "right")
            else
                love.graphics.print(line, bubble_x + 5, draw_y + self.line_height * i)
            end
        end
        
        draw_y = draw_y + bubble_height + self.message_gap
    end
    
    -- Reset scissor
    love.graphics.setScissor()
    
    -- Scroll indicator (if scrollable)
    local total_height = self:get_total_height()
    local visible_height = self.height - 30
    if total_height > visible_height then
        local scroll_ratio = self.scroll_offset / (total_height - visible_height)
        local indicator_height = math.max(20, visible_height * (visible_height / total_height))
        local indicator_y = self.y + 25 + scroll_ratio * (visible_height - indicator_height)
        
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.rectangle("fill", self.x + self.width - 8, indicator_y, 5, indicator_height, 2)
    end
end

return ChatLog
