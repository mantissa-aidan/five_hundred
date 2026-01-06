-- Trick View for Five Hundred Love
-- Renders current trick cards in center of table with idle float animation

local Utils = require "src.core.utils"
local CardRenderer = require "src.ui.card_renderer"

local TrickView = Utils.class("TrickView")

-- Player positions relative to center (cross pattern)
TrickView.POSITIONS = {
    [1] = {x = 0, y = 90},    -- Bottom (Human)
    [2] = {x = -120, y = 0},  -- Left
    [3] = {x = 0, y = -90},   -- Top
    [4] = {x = 120, y = 0}    -- Right
}

function TrickView:init(game, center_x, center_y, card_scale, anim_manager)
    self.game = game
    self.center_x = center_x
    self.center_y = center_y
    self.card_scale = card_scale
    self.anim = anim_manager
end

function TrickView:resize(center_x, center_y)
    self.center_x = center_x
    self.center_y = center_y
end

function TrickView:draw()
    love.graphics.push()
    love.graphics.translate(self.center_x, self.center_y)

    -- Draw Placemat
    love.graphics.setColor(0, 0, 0, 0.3)
    local pw, ph = 340, 340
    love.graphics.rectangle("fill", -pw/2, -ph/2, pw, ph, 40, 40)
    love.graphics.setColor(1, 1, 1, 1)

    local trick = self.game.current_trick
    if not trick or #trick == 0 then
        love.graphics.pop()
        return
    end

    -- Filter animating cards (via AnimationManager)
    local animating_set = self.anim:get_animating_cards()

    for _, play in ipairs(trick) do
        if not animating_set[play.card] then
            -- Find player seat index
            local p_idx = -1
            for i, p in ipairs(self.game.players) do
                if p == play.player then p_idx = i; break end
            end

            local pos = TrickView.POSITIONS[p_idx]
            if pos then
                local card_x = pos.x - 40
                local card_y = pos.y - 55

                -- Idle Float Animation (fades in after landing)
                local t = love.timer.getTime()
                local seed = p_idx * 123.456

                local phase_y = seed
                local phase_rot = seed * 0.7
                local speed_y = 2.0 + math.sin(seed) * 0.5
                local speed_rot = 1.5 + math.cos(seed) * 0.5

                -- Fade in float over 0.5 seconds after landing
                local float_strength = 1.0
                local land_time = self.anim:get_card_land_time(play.card)
                if land_time then
                    local time_since_land = t - land_time
                    float_strength = math.min(1.0, time_since_land / 0.5)
                end

                local ambient_y = math.sin(t * speed_y + phase_y) * 2.0 * float_strength
                local ambient_rot = math.cos(t * speed_rot + phase_rot) * 0.02 * float_strength

                card_y = card_y + ambient_y

                CardRenderer.draw_card(play.card, card_x, card_y, self.card_scale, true, false, {
                    scale_x = 1,
                    scale_y = 1,
                    shadow_offset = 10,
                    rotation = ambient_rot
                })
            end
        end
    end

    love.graphics.pop()
end

-- Get target position for card animation (used by AnimationManager)
function TrickView:get_card_target_position(player_idx)
    local pos = TrickView.POSITIONS[player_idx]
    if pos then
        return self.center_x + pos.x - 40, self.center_y + pos.y - 55
    end
    return self.center_x, self.center_y
end

return TrickView
