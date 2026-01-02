local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

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
end

function BiddingView:resize(container_w, container_h)
    self.container_w = container_w
    self.container_h = container_h
    self.base_x = (self.container_w - self.width) / 2
    self.base_y = (self.container_h - self.height) / 2
    self:create_buttons()
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
            
            table.insert(self.buttons, {
                x = bx, y = by, w = cell_w, h = cell_h,
                text = tostring(trick_count),
                type = "SELECT_BID",
                suit = suit,
                tricks = trick_count,
                bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
            })
        end
    end
    
    -- Misere Buttons (DISABLED - Bot not trained on these yet, curriculum learning planned)
    -- TODO: Re-enable when curriculum learning adds Misere support
    --[[
    local misc_y = start_y + 5 * (cell_h + 10) + 20
    table.insert(self.buttons, {
        x = start_x, y = misc_y, w = 100, h = 40,
        text = "Misere",
        type = "SELECT_BID",
        suit = Suit.NO_TRUMP,
        tricks = 0,
        bid_type = BidType.MISERE
    })
    
    table.insert(self.buttons, {
        x = start_x + 120, y = misc_y, w = 120, h = 40,
        text = "Open Misere",
        type = "SELECT_BID",
        suit = Suit.NO_TRUMP,
        tricks = 0,
        bid_type = BidType.OPEN_MISERE
    })
    --]]
    local misc_y = start_y + 5 * (cell_h + 10) + 20 -- Keep for action button positioning
    
    -- Action Buttons Area
    local action_y = misc_y + 60
    
    -- Pass Button (Immediate action)
    table.insert(self.buttons, {
        x = self.base_x + 50, y = action_y, w = 100, h = 50,
        text = "Pass",
        type = "PASS"
    })
    
    -- Submit Button (Requires selection)
    table.insert(self.buttons, {
        x = self.base_x + self.width - 150, y = action_y, w = 100, h = 50,
        text = "Place Bid",
        type = "SUBMIT"
    })
end

function BiddingView:update_layout()
    -- Recalculate position using stored container dimensions (game area, not full screen)
    self.base_x = (self.container_w - self.width) / 2
    self.base_y = (self.container_h - self.height) / 2
    self:create_buttons()
end

function BiddingView:draw()
    if self.game.state ~= "BIDDING" then return end
    
    self:update_layout()
    
    -- Overlay Background
    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", self.base_x, self.base_y, self.width, self.height, 10)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Bidding Phase - Select a Bid", self.base_x + 20, self.base_y + 20)
    
    local suit_labels = {[Suit.SPADES]="Spades", [Suit.CLUBS]="Clubs", 
                         [Suit.DIAMONDS]="Diamonds", [Suit.HEARTS]="Hearts", 
                         [Suit.NO_TRUMP]="No Trump"}
                         
    -- Draw Row Labels
    local cell_h = 40
    local start_y = self.base_y + 80
    for r, suit in ipairs({Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP}) do
         love.graphics.print(suit_labels[suit], self.base_x + 20, start_y + (r-1)*(cell_h+10) + 10)
    end
    
    -- Draw Buttons
    for _, btn in ipairs(self.buttons) do
        local color = {0.3, 0.3, 0.3} -- Default Gray
        local can_click = true
        
        if btn.type == "SELECT_BID" then
             local valid = is_valid_bid(self.game, btn.tricks, btn.suit, btn.bid_type)
             if valid then
                 if self.selected_bid and 
                    self.selected_bid.tricks == btn.tricks and 
                    self.selected_bid.suit == btn.suit and
                    self.selected_bid.bid_type == btn.bid_type then
                      color = {0.8, 0.6, 0.0} -- Selected (Gold/Orange)
                 else
                      color = {0.3, 0.6, 0.3} -- Valid (Green)
                 end
             else
                 color = {0.2, 0.2, 0.2} -- Invalid (Dark Gray)
                 can_click = false
             end
             
        elseif btn.type == "PASS" then
             color = {0.6, 0.3, 0.3} -- Red
             
        elseif btn.type == "SUBMIT" then
             if self.selected_bid then
                 color = {0.2, 0.5, 1.0} -- Blue
             else
                 color = {0.2, 0.2, 0.2} -- Disabled
                 can_click = false
             end
        end
        
        love.graphics.setColor(unpack(color))
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5)
        
        love.graphics.setColor(1, 1, 1)
        if not can_click then love.graphics.setColor(0.5, 0.5, 0.5) end
        love.graphics.printf(btn.text, btn.x, btn.y + (btn.h/2 - 7), btn.w, "center")
    end
end

function BiddingView:check_click(x, y)
    if self.game.state ~= "BIDDING" then return false end
    if self.game.current_player_idx ~= 1 then return false end
    
    -- Ensure positions are up to date before hit testing
    self:update_layout()
    
    for _, btn in ipairs(self.buttons) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            
            if btn.type == "PASS" then
                if gChatLog then gChatLog:add_message("You", {"Passed"}, true) end
                self.game:player_pass(1)
                self.selected_bid = nil
                return true
                
            elseif btn.type == "SELECT_BID" then
                 if is_valid_bid(self.game, btn.tricks, btn.suit, btn.bid_type) then
                     self.selected_bid = {tricks=btn.tricks, suit=btn.suit, bid_type=btn.bid_type}
                     return true
                 end
                 
            elseif btn.type == "SUBMIT" then
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
                        return true
                     else
                        print("Bid Error: " .. tostring(err))
                     end
                 end
            end
        end
    end
    return false
end

return BiddingView
