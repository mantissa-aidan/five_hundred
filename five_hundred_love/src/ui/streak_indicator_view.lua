-- StreakIndicatorView.lua
-- Displays active streak indicators with animations

local Utils = require "src.core.utils"

local StreakIndicatorView = Utils.class("StreakIndicatorView")

function StreakIndicatorView:init(game, width, height)
    self.game = game
    self.width = width
    self.height = height

    -- Active streak displays
    self.streak_displays = {}
    self.flash_timer = 0
    self.pulse_scale = 1.0
end

function StreakIndicatorView:resize(width, height)
    self.width = width
    self.height = height
end

function StreakIndicatorView:update(dt)
    -- Pulse animation
    self.flash_timer = self.flash_timer + dt
    self.pulse_scale = 1.0 + math.sin(self.flash_timer * 4) * 0.1

    if not self.game:is_roguelike() then
        return
    end

    -- Update streak displays based on current state
    local streaks = self.game.run_state.streak_states
    self.streak_displays = {}

    -- Consecutive tricks (always show if > 0)
    if streaks.consecutive_tricks.count > 0 then
        table.insert(self.streak_displays, {
            label = "TRICK STREAK",
            value = streaks.consecutive_tricks.count,
            color = {0.4, 1, 0.4},
            priority = 1
        })
    end

    -- Trump streak (show if >= 3)
    if streaks.trump_streak.count >= 3 then
        table.insert(self.streak_displays, {
            label = "TRUMP STREAK",
            value = streaks.trump_streak.count,
            color = {1, 0.8, 0.2},
            priority = 2
        })
    end

    -- High card streak (show if >= 3)
    if streaks.high_card_streak.count >= 3 then
        table.insert(self.streak_displays, {
            label = "HIGH CARD STREAK",
            value = streaks.high_card_streak.count,
            color = {1, 0.4, 0.8},
            priority = 3
        })
    end

    -- Suit streak (show if >= 4)
    if streaks.same_suit_played.count >= 4 then
        table.insert(self.streak_displays, {
            label = "SUIT STREAK",
            value = streaks.same_suit_played.count,
            color = {0.4, 0.8, 1},
            priority = 4
        })
    end
end

function StreakIndicatorView:draw()
    if not self.game:is_roguelike() or #self.streak_displays == 0 then
        return
    end

    -- Draw streaks in center-top area
    local start_x = self.width / 2
    local start_y = 60
    local spacing = 45

    for i, streak in ipairs(self.streak_displays) do
        local y = start_y + (i - 1) * spacing

        -- Background panel
        local text = string.format("%s: %dx", streak.label, streak.value)
        local font = gFonts and gFonts.medium or love.graphics.getFont()
        local text_width = font:getWidth(text)
        local panel_width = text_width + 30
        local panel_height = 35

        local x = start_x - panel_width / 2

        -- Shadow
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", x + 3, y + 3, panel_width, panel_height, 8, 8)

        -- Panel
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", x, y, panel_width, panel_height, 8, 8)

        -- Border with streak color
        love.graphics.setColor(streak.color)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, panel_width, panel_height, 8, 8)

        -- Text
        love.graphics.setColor(streak.color)
        if gFonts and gFonts.medium then
            love.graphics.setFont(gFonts.medium)
        end

        -- Apply pulse scale for emphasis
        local scale = self.pulse_scale
        love.graphics.push()
        love.graphics.translate(start_x, y + panel_height / 2)
        love.graphics.scale(scale, scale)
        love.graphics.printf(text, -text_width / 2, -12, text_width, "center")
        love.graphics.pop()
    end
end

return StreakIndicatorView
