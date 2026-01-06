-- HUD View for Five Hundred Love
-- Displays contract info, trick counts, game score, and round-over modal

local Utils = require "src.core.utils"

local HUDView = Utils.class("HUDView")

function HUDView:init(game, width, height)
    self.game = game
    self.width = width
    self.height = height
    self.center_x = width / 2
    self.center_y = height / 2

    -- Trick score state with animation
    self.us_score = 0
    self.them_score = 0
    self.us_scale = {val = 1, vel = 0, target = 1}
    self.them_scale = {val = 1, vel = 0, target = 1}

    -- Round over state
    self.round_over_sound_played = false
    self.round_over_btn_rect = nil
end

function HUDView:resize(width, height)
    self.width = width
    self.height = height
    self.center_x = width / 2
    self.center_y = height / 2
end

function HUDView:update(dt)
    -- Update score tracking
    local p1 = self.game.players[1] and self.game.players[1].tricks_won_this_round or 0
    local p2 = self.game.players[2] and self.game.players[2].tricks_won_this_round or 0
    local p3 = self.game.players[3] and self.game.players[3].tricks_won_this_round or 0
    local p4 = self.game.players[4] and self.game.players[4].tricks_won_this_round or 0

    local us = p1 + p3
    local them = p2 + p4

    -- Trigger scale animation when score increases
    if us > self.us_score then self.us_scale.val = 1.5 end
    self.us_score = us

    if them > self.them_score then self.them_scale.val = 1.5 end
    self.them_score = them

    -- Integrate scale springs
    local k = 150
    local d = 10
    local function spring(prop, dt)
        local diff = 1.0 - prop.val
        local force = diff * k
        prop.vel = prop.vel * (1 - d * dt) + force * dt
        prop.val = prop.val + prop.vel * dt
    end
    spring(self.us_scale, dt)
    spring(self.them_scale, dt)

    -- Reset round over sound flag when not in ROUND_OVER state
    if self.game.state ~= "ROUND_OVER" then
        self.round_over_sound_played = false
    end
end

function HUDView:draw()
    local x, y = 20, 20
    local w, h = 260, 320

    -- Panel BG
    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", x, y, w, h, 12, 12)

    -- Border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 12, 12)

    local left_pad = x + 15
    local cursor_y = y + 15

    -- Data Prep
    local bid = self.game.winning_bid
    local suits = {[0]="CLUBS", [1]="DIAMONDS", [2]="HEARTS", [3]="SPADES", [4]="NO TRUMP"}
    local tricks_bid = 0
    local suit_str = "..."
    local declarer_name = "..."
    local team_goal = 0
    local role_text = "..."
    local role_color = {1, 1, 1}

    if bid then
        tricks_bid = bid.tricks
        suit_str = suits[bid.suit]
        declarer_name = bid.player.name

        local declarer_idx = bid.player.index
        local is_attacking = (declarer_idx == 1 or declarer_idx == 3)

        if is_attacking then
            team_goal = bid.tricks
            role_text = "OFFENSE (ATTACKING)"
            role_color = {0.4, 1, 0.4}
        else
            team_goal = 11 - bid.tricks
            role_text = "DEFENSE (STOP THEM)"
            role_color = {1, 0.6, 0.2}
        end
    elseif self.game.highest_bid then
        tricks_bid = self.game.highest_bid.tricks
        suit_str = suits[self.game.highest_bid.suit]
        declarer_name = self.game.highest_bid.player.name .. " (Prov)"
        team_goal = "?"
    end

    -- 1. CONTRACT HEADER (Medium)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end

    local header_text = string.format("%d %s", tricks_bid, suit_str)
    if not bid and not self.game.highest_bid then header_text = "BIDDING..." end

    love.graphics.printf(header_text, x, cursor_y, w, "center")
    cursor_y = cursor_y + 35

    -- 2. DETAILS (Small)
    love.graphics.setColor(0.9, 0.9, 0.9)
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end

    if bid or self.game.highest_bid then
        love.graphics.print("By " .. declarer_name, left_pad, cursor_y)
        cursor_y = cursor_y + 20

        if bid then
            love.graphics.setColor(role_color)
            love.graphics.print(role_text, left_pad, cursor_y)
            cursor_y = cursor_y + 20

            love.graphics.setColor(1, 1, 0.5)
            love.graphics.print("TEAM GOAL: WIN " .. team_goal, left_pad, cursor_y)
            cursor_y = cursor_y + 30
        else
            cursor_y = cursor_y + 50
        end
    else
        cursor_y = cursor_y + 50
    end

    -- 3. TRICKS (Medium Header)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.print("TRICKS", left_pad, cursor_y)

    cursor_y = cursor_y + 30

    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end

    -- Won
    love.graphics.setColor(0.4, 1, 0.4)
    love.graphics.print(tostring(self.us_score), left_pad + 20, cursor_y - 5)

    -- Lost
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.print(tostring(self.them_score), left_pad + 140, cursor_y - 5)

    -- Labels (Small)
    cursor_y = cursor_y + 45
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end

    love.graphics.setColor(0.4, 1, 0.4)
    love.graphics.print("WON", left_pad + 25, cursor_y)

    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.print("LOST", left_pad + 145, cursor_y)

    cursor_y = cursor_y + 35

    -- 4. SCORE (Medium Header)
    love.graphics.setColor(1, 1, 1)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.print("SCORE", left_pad, cursor_y)

    local team_a_score = self.game.teams[1] and self.game.teams[1].score or 0
    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end

    cursor_y = cursor_y + 30
    if team_a_score >= 0 then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(1, 0.5, 0.5)
    end
    love.graphics.print(tostring(team_a_score), left_pad + 50, cursor_y - 5)

    -- To 500 (Small)
    cursor_y = cursor_y + 45
    love.graphics.setColor(0.6, 0.6, 0.6)
    if gFonts and gFonts.small then love.graphics.setFont(gFonts.small) end
    love.graphics.print("(to 500)", left_pad + 55, cursor_y)
end

function HUDView:draw_round_over_modal()
    -- Semi-transparent overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)

    -- Modal Box
    local w, h = 500, 400
    local x = self.center_x - w / 2
    local y = self.center_y - h / 2

    love.graphics.setColor(0.1, 0.1, 0.1, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 15, 15)

    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", x, y, w, h, 15, 15)

    -- Determine Result
    local bid = self.game.winning_bid
    if not bid then return end

    local declarer_team = bid.player.team
    local tricks_won = 0
    if declarer_team == self.game.teams[1] then
        tricks_won = self.us_score
    else
        tricks_won = self.them_score
    end

    local success = tricks_won >= bid.tricks

    local is_user_team = (declarer_team == self.game.teams[1])
    local result_text = ""
    local color = {1, 1, 1}

    if is_user_team then
        if success then
            result_text = "YOU WON!"
            color = {0.4, 1, 0.4}
        else
            result_text = "YOU LOST!"
            color = {1, 0.4, 0.4}
        end
    else
        if success then
            result_text = "THEY WON!"
            color = {1, 0.4, 0.4}
        else
            result_text = "THEY LOST!"
            color = {0.4, 1, 0.4}
        end
    end

    -- Play Sound once per modal appearance
    if not self.round_over_sound_played then
        if gAudioManager then
            if is_user_team then
                if success then gAudioManager:play("WIN")
                else gAudioManager:play("LOSE") end
            else
                if success then gAudioManager:play("LOSE")
                else gAudioManager:play("WIN") end
            end
        end
        self.round_over_sound_played = true
    end

    if gFonts and gFonts.large then love.graphics.setFont(gFonts.large) end
    love.graphics.setColor(color)
    love.graphics.printf(result_text, x, y + 40, w, "center")

    -- New Scores
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.setColor(1, 1, 1)

    local team_a_score = self.game.teams[1].score
    local team_b_score = self.game.teams[2].score

    love.graphics.printf("Team A: " .. team_a_score, x, y + 120, w, "center")
    love.graphics.printf("Team B: " .. team_b_score, x, y + 160, w, "center")

    -- Continue Button
    local btn_w, btn_h = 200, 60
    local btn_x = self.center_x - btn_w / 2
    local btn_y = self.center_y + 100

    love.graphics.setColor(0.2, 0.6, 0.2)
    love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 8, 8)

    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", btn_x, btn_y, btn_w, btn_h, 8, 8)

    love.graphics.printf("Next Round", btn_x, btn_y + 15, btn_w, "center")

    -- Store for click detection
    self.round_over_btn_rect = {x = btn_x, y = btn_y, w = btn_w, h = btn_h}
end

-- Get button rect for click detection (used by TableView)
function HUDView:get_round_over_btn_rect()
    return self.round_over_btn_rect
end

return HUDView
