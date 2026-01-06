-- Hand View for Five Hundred Love
-- Renders player hands with spring physics and hover effects

local Utils = require "src.core.utils"
local CardRenderer = require "src.ui.card_renderer"

local HandView = Utils.class("HandView")

-- Layout Constants
HandView.SPREAD_HUMAN = 90
HandView.SPREAD_BOT = 30
HandView.Y_OFFSET = -60

function HandView:init(game, card_scale, center_x, height, anim_manager)
    self.game = game
    self.card_scale = card_scale
    self.center_x = center_x
    self.height = height
    self.anim = anim_manager

    -- Per-player spring state
    self.springs = {
        [1] = {}, [2] = {}, [3] = {}, [4] = {}
    }

    -- Hover state (P1 only)
    self.last_hovered_idx = nil

    -- Card hit rectangles (P1 only, for click detection)
    self.card_rects = {}

    -- Drag state (managed by TableView, but we track drag_target_idx)
    self.drag_target_idx = nil
end

function HandView:resize(center_x, height)
    self.center_x = center_x
    self.height = height
end

-- Initialize springs for a player if missing
function HandView:ensure_springs(player_idx, hand_size, is_human)
    local player_springs = self.springs[player_idx]
    local spread = is_human and HandView.SPREAD_HUMAN or HandView.SPREAD_BOT
    local start_x = -((hand_size - 1) * spread) / 2

    for i = 1, hand_size do
        if not player_springs[i] then
            local initial_x = start_x + (i - 1) * spread
            player_springs[i] = {
                x = {val = initial_x, vel = 0, target = initial_x},
                y = {val = 0, vel = 0, target = 0},
                scale = {val = 1, vel = 0, target = 1},
                pitch = {val = 0, vel = 0, target = 0},
                roll = {val = 0, vel = 0, target = 0}
            }
        end
    end
end

-- Update P1's hover/interaction springs
function HandView:update_player_springs(dt, dragged_card)
    local player = self.game.players[1]
    if not player then return end

    local hand_size = #player.hand
    self:ensure_springs(1, hand_size, true)

    local player_springs = self.springs[1]
    local spread = HandView.SPREAD_HUMAN
    local start_x = -((hand_size - 1) * spread) / 2

    -- Detect hover using cached card rects
    local mx, my = love.mouse.getPosition()
    local hovered_idx = nil

    if self.game.state == "PLAYING" or self.game.state == "KITTY" or self.game.state == "BIDDING" then
        if self.card_rects and #self.card_rects > 0 then
            local local_mx = mx - self.center_x
            local local_my = my - (self.height - 100)

            for i = #self.card_rects, 1, -1 do
                local r = self.card_rects[i]
                if local_mx >= r.x and local_mx <= r.x + r.w and
                   local_my >= r.y and local_my <= r.y + r.h then
                    hovered_idx = r.idx
                    break
                end
            end
        end
    end

    -- Play sound on hover change
    if hovered_idx ~= self.last_hovered_idx then
        if hovered_idx and gAudioManager then
            gAudioManager:play("CARD_HOVER")
        end
        self.last_hovered_idx = hovered_idx
    end

    -- Physics parameters
    local stiffness = 600
    local damping = 40

    local function integrate_spring(spring, dt, k, d)
        local f = -k * (spring.val - spring.target) - d * spring.vel
        spring.vel = spring.vel + f * dt
        spring.val = spring.val + spring.vel * dt
    end

    for i = 1, hand_size do
        local s = player_springs[i]
        local is_hovering = (i == hovered_idx)

        -- Position target
        s.x.target = start_x + (i - 1) * spread

        -- Interaction targets
        if is_hovering then
            s.scale.target = 1.25

            local card_x = start_x + (i - 1) * spread
            local card_y = HandView.Y_OFFSET
            local center_x = self.center_x + card_x
            local center_y = (self.height - 100) + card_y + 55

            local diff_x = mx - center_x
            local diff_y = my - center_y

            s.pitch.target = (diff_y / 60) * -0.15
            s.roll.target = (diff_x / 40) * -0.15
        else
            s.scale.target = 1.0
            s.pitch.target = 0
            s.roll.target = 0
        end

        -- Integrate springs
        integrate_spring(s.x, dt, stiffness, damping)
        integrate_spring(s.scale, dt, stiffness, damping)
        integrate_spring(s.pitch, dt, stiffness, damping)
        integrate_spring(s.roll, dt, stiffness, damping)
    end
end

-- Update position springs for all players (smooth reorganization)
function HandView:update_all_springs(dt)
    local stiffness = 600
    local damping = 40

    for player_idx = 1, 4 do
        local player = self.game.players[player_idx]
        if player then
            local hand_size = #player.hand
            local is_human = (player_idx == 1)
            self:ensure_springs(player_idx, hand_size, is_human)

            local player_springs = self.springs[player_idx]
            local spread = is_human and HandView.SPREAD_HUMAN or HandView.SPREAD_BOT
            local start_x = -((hand_size - 1) * spread) / 2

            for i = 1, hand_size do
                if player_springs[i] then
                    local s = player_springs[i]

                    -- Update position target
                    s.x.target = start_x + (i - 1) * spread

                    -- Integrate X spring
                    local fx = -stiffness * (s.x.val - s.x.target) - damping * s.x.vel
                    s.x.vel = s.x.vel + fx * dt
                    s.x.val = s.x.val + s.x.vel * dt

                    -- Integrate Y spring
                    if s.y then
                        s.y.target = 0
                        local fy = -stiffness * (s.y.val - s.y.target) - damping * s.y.vel
                        s.y.vel = s.y.vel + fy * dt
                        s.y.val = s.y.val + s.y.vel * dt
                    end
                end
            end
        end
    end
end

function HandView:update(dt, dragged_card)
    self:update_player_springs(dt, dragged_card)
    self:update_all_springs(dt)
end

-- Calculate deal target position for a player's card
function HandView:get_deal_target_position(p_idx, card_idx, x, y, total_cards)
    total_cards = total_cards or 10
    local is_human = (p_idx == 1)
    local spread = is_human and HandView.SPREAD_HUMAN or HandView.SPREAD_BOT
    local start_x = -((total_cards - 1) * spread) / 2
    local card_x = start_x + (card_idx - 1) * spread

    -- Calculate Fan Logic (Curve) for Opponents
    local offset_y = 0
    local offset_rot = 0
    if not is_human then
         local center = (total_cards + 1) / 2
         local dist = math.abs(card_idx - center)
         local signed_dist = card_idx - center
         
         offset_y = - (dist * dist) * 1.5
         offset_rot = - signed_dist * 0.1
    end

    -- Player position mappings
    if p_idx == 1 then
        -- Bottom (Human) - Linear
        local target_x = self.center_x + card_x - 40
        local target_y = self.height - 100 + HandView.Y_OFFSET
        return target_x, target_y, 0
    elseif p_idx == 2 then
        -- Left (rotated -90)
        -- Linear Base
        local base_x = 110 + card_x * 0.5 -- This seems to involve a shift? 
        -- Actually, if rotated -90:
        -- Global X = Hand X + Local Y * sin(-90) + Local X * cos(-90)
        -- Global Y = Hand Y + Local Y * cos(-90) - Local X * sin(-90)
        -- Let's stick to the current linear approximation but ADD the curve.
        -- Curve is along Local Y. 
        -- Local Y = offset_y.
        -- Rotated -90: Local Y maps to Global X (positive local Y -> positive global X? No.)
        -- Rotation matrix for -90 (0 -1; 1 0) -> (x,y) -> (y, -x).
        -- So Local (0, offset_y) -> (offset_y, 0).
        -- So we add offset_y to Global X.
        
        local target_x = 110 + card_x * 0.5 + offset_y
        local target_y = (self.height / 2) + card_x * 0.3
        return target_x, target_y, -math.pi / 2 + offset_rot
        
    elseif p_idx == 3 then
        -- Top (No rotation or 180?)
        -- Assuming 0 rotation based on previous code.
        -- Local Y maps to Global Y.
        local target_x = self.center_x + card_x - 40
        local target_y = 50 + HandView.Y_OFFSET + offset_y
        return target_x, target_y, 0 + offset_rot
        
    elseif p_idx == 4 then
        -- Right (rotated 90)
        -- Rotation 90 (0 1; -1 0) -> (x,y) -> (-y, x).
        -- Local (0, offset_y) -> (-offset_y, 0).
        -- So subtract offset_y from Global X.
        
        local target_x = self.center_x * 2 - 110 + card_x * 0.5 - offset_y
        local target_y = (self.height / 2) - card_x * 0.3
        return target_x, target_y, math.pi / 2 + offset_rot
    end

    return self.center_x, self.height / 2, 0
end

-- Get card rects for P1 click detection (used by TableView)
function HandView:get_card_rects()
    return self.card_rects
end

-- Set drag target index (called by TableView during drag)
function HandView:set_drag_target_idx(idx)
    self.drag_target_idx = idx
end

return HandView
