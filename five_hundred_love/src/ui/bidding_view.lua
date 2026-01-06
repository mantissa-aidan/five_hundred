local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"
local Button = require "src.ui.button"

local Suit = CardModule.Suit
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local BiddingView = Utils.class("BiddingView")

local function is_valid_bid(game, bid_tricks, bid_suit, bid_type)
        if not game.highest_bid then return true end
        local temp_bid = Bid.new(game.players[1], bid_tricks, bid_suit, bid_type)
        return temp_bid > game.highest_bid
end

function BiddingView:init(game, container_w, container_h)
    self.game = game
    self.width = 600
    self.height = 450
    self.buttons = {}
    self.selected_bid = nil

    -- Layout centering within container (game area, not full screen)
    self.container_w = container_w or love.graphics.getWidth()
    self.container_h = container_h or love.graphics.getHeight()

    self.base_x = (self.container_w - self.width) / 2
    self.base_y = (self.container_h - self.height) / 2

    self:create_buttons()
    
    -- Animation State
    self.intro_progress = 0.0  -- Will be set to 0.0 when animation triggers
    self.was_active = false
end

function BiddingView:resize(container_w, container_h)
    local old_x = self.base_x or 0
    local old_y = self.base_y or 0
    
    self.container_w = container_w
    self.container_h = container_h
    self.base_x = (self.container_w - self.width) / 2
    self.base_y = (self.container_h - self.height) / 2
    
    -- If initialized, shift existing buttons instead of recreating
    if self.buttons and #self.buttons > 0 then
        local dx = self.base_x - old_x
        local dy = self.base_y - old_y
        
        for _, btn in ipairs(self.buttons) do
            btn.x = btn.x + dx
            btn.y = btn.y + dy
        end
    else
        self:create_buttons()
    end
end

function BiddingView:create_buttons()
    self.buttons = {}
    
    local cell_w = 60
    local cell_h = 40
    local start_x = self.base_x + 150
    local start_y = self.base_y + 80
    
    -- Suit Rows
    local suits = {Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP}
    local tricks = {6, 7, 8, 9, 10}
    
    for r, suit in ipairs(suits) do
        for c, trick_count in ipairs(tricks) do
            local bx = start_x + (c-1) * (cell_w + 10)
            local by = start_y + (r-1) * (cell_h + 10)
            
            local bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            
            local btn = Button.new(bx, by, cell_w, cell_h, tostring(trick_count), "bid", function()
                -- Select Bid Logic
                if is_valid_bid(self.game, trick_count, suit, bid_type) then
                    self.selected_bid = {tricks=trick_count, suit=suit, bid_type=bid_type}
                end
            end)
            
            -- Store Metadata for color logic
            btn.tricks = trick_count
            btn.suit = suit
            btn.bid_type = bid_type
            btn.is_grid_btn = true
            
            table.insert(self.buttons, btn)
        end
    end
    
    local misc_y = start_y + 5 * (cell_h + 10) + 20 
    local action_y = misc_y + 40
    
    -- Pass Button
    local pass_btn = Button.new(self.base_x + 50, action_y, 100, 50, "Pass", "action", function()
        if gChatLog then gChatLog:add_message("You", {"Passed"}, true) end
        self.game:player_pass(1)
        self.selected_bid = nil
    end)
    pass_btn.custom_color = {0.6, 0.3, 0.3} -- Red
    table.insert(self.buttons, pass_btn)
    
    -- Submit Button
    local submit_btn = Button.new(self.base_x + self.width - 150, action_y, 120, 50, "Place Bid", "action", function()
        if self.selected_bid then
             local tr, s, bt = self.selected_bid.tricks, self.selected_bid.suit, self.selected_bid.bid_type
             local success, err = self.game:player_bid(1, tr, s, bt)
             if success then
                if gChatLog then 
                    local suit_strs = {[0]="Spades",[1]="Clubs",[2]="Diamonds",[3]="Hearts",[4]="No Trump"}
                    local text = string.format("Bids %d %s", tr, suit_strs[s])
                    gChatLog:add_message("You", {text}, true) 
                end
                self.selected_bid = nil
             else
                print("Bid Error: " .. tostring(err))
             end
        end
    end)
    submit_btn.is_submit = true
    table.insert(self.buttons, submit_btn)
end

function BiddingView:update(dt, dealing_in_progress)
    -- Hot-reload safety: initialize animation state if missing
    if self.intro_progress == nil then self.intro_progress = 0.0 end
    if self.was_active == nil then self.was_active = false end
    
    if self.game.state ~= "BIDDING" then
        self.was_active = false
        self.intro_progress = 0.0  -- Reset animation progress too!
        return 
    end
    
    -- Only trigger animation when dealing is complete AND we haven't triggered yet
    if not self.was_active and not dealing_in_progress then
        self.was_active = true
        self.intro_progress = 0.0
        if gAudioManager then gAudioManager:play("CARD_SLIDE") end
    end
    
    -- Animate Intro (Fast ease out) - only if animation has been triggered
    if self.was_active then
        local speed = 12
        self.intro_progress = self.intro_progress + (1.0 - self.intro_progress) * speed * dt
    end
    
    -- Logic to update button states (colors/disabled)
    for _, btn in ipairs(self.buttons) do
        
        if btn.is_grid_btn then
            local valid = is_valid_bid(self.game, btn.tricks, btn.suit, btn.bid_type)
            
            if not valid then
                btn.disabled = true
                -- btn.color = {0.2, 0.2, 0.2} -- Keep dark gray
            else
                btn.disabled = false
                -- Check selection
                if self.selected_bid and 
                   self.selected_bid.tricks == btn.tricks and 
                   self.selected_bid.suit == btn.suit and
                   self.selected_bid.bid_type == btn.bid_type then
                      btn.color = {0.8, 0.6, 0.0} -- Selected
                else
                      btn.color = {0.3, 0.6, 0.3} -- Valid
                end
            end
            
        elseif btn.is_submit then
             if self.selected_bid then
                 btn.disabled = false
                 btn.color = {0.2, 0.5, 1.0} -- Blue
             else
                 btn.disabled = true
                 btn.color = {0.2, 0.2, 0.2}
             end
        elseif btn.custom_color then
             btn.color = btn.custom_color
        end
        
        -- Only update interactivity if animation is near complete
        -- This prevents "phantom" clicks/hovers while buttons are flying in from invalid positions
        if self.intro_progress > 0.8 then
            btn:update(dt)
        end
    end
end

function BiddingView:update_layout()
    -- Recalculate position using stored container dimensions (game area, not full screen)
    self.base_x = (self.container_w - self.width) / 2
    self.base_y = (self.container_h - self.height) / 2
    
    -- Only recreate if buttons empty (avoid resetting springs constantly)
    if #self.buttons == 0 then
        self:create_buttons()
    end
end

function BiddingView:draw()
    if self.game.state ~= "BIDDING" then return end
    if #self.buttons == 0 then self:update_layout() end
    
    love.graphics.push()
    
    -- Fly In Animation Transform
    local off_y = 100 * (1.0 - self.intro_progress) -- Slide up 100px
    love.graphics.translate(0, off_y)
    
    -- Opacity Fade
    love.graphics.setColor(1, 1, 1, self.intro_progress)
    
    -- Overlay Background
    love.graphics.setColor(0, 0, 0, 0.9 * self.intro_progress)
    love.graphics.rectangle("fill", self.base_x, self.base_y, self.width, self.height, 10)
    
    -- Header
    love.graphics.setColor(1, 1, 1, self.intro_progress)
    if gFonts and gFonts.medium then love.graphics.setFont(gFonts.medium) end
    love.graphics.print("Bidding Phase - Select a Bid", self.base_x + 20, self.base_y + 20)
    
    -- Check fonts for row labels
    local font = love.graphics.getFont()
    local cell_h = 40
    local start_y = self.base_y + 80
    
    local suit_labels = {[Suit.SPADES]="Spades", [Suit.CLUBS]="Clubs", 
                         [Suit.DIAMONDS]="Diamonds", [Suit.HEARTS]="Hearts", 
                         [Suit.NO_TRUMP]="No Trump"}
                         
    for r, suit in ipairs({Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP}) do
         love.graphics.print(suit_labels[suit], self.base_x + 20, start_y + (r-1)*(cell_h+10) + 10)
    end
    
    -- Draw Buttons with Float
    local time = love.timer.getTime()
    
    for i, btn in ipairs(self.buttons) do
        -- Idle Float (Sine Wave) - Apply externally to Button component
        -- We can just modify button Y temporarily? No, that messes up hover check.
        -- We must use translate matrix.
        local float_y = math.sin(time * 2 + i * 0.5) * 2
        
        love.graphics.push()
        love.graphics.translate(0, float_y)
        btn:draw(self.intro_progress)
        love.graphics.pop()
    end
    
    love.graphics.pop()
end

function BiddingView:check_click(x, y)
    if self.game.state ~= "BIDDING" then return false end
    if self.game.current_player_idx ~= 1 then return false end
    if self.intro_progress <= 0.8 then return false end -- Wait for animation
    
    self:update_layout()
    
    -- Delegate to buttons
    for _, btn in ipairs(self.buttons) do
        -- Check if button handles the click
        -- Note: Button:click() executes callback.
        -- We need to check if hover matches?
        -- Button:update() has run, so btn.hovered is current.
        -- HOWEVER, update() handles mouse coordinates. 
        -- If check_click(x,y) assumes global mouse, it is fine.
        -- If x,y are transformed, we should check against rect manually to be safe.
        
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if not btn.disabled then
                btn:click()
                return true
            end
        end
    end
    return false
end

return BiddingView
