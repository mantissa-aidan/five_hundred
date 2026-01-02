local Utils = require "src.core.utils"
local CardModule = require "src.core.card"
local Deck = require "src.core.deck"
local Player = require "src.core.player"
local Team = require "src.core.team"
local BidModule = require "src.core.bid"
local Net = require "src.ai.net"
local FeatureExtractor = require "src.ai.feature_extractor"
local json = require "src.ext.json"
local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local Game = Utils.class("Game")

-- Game States
    Game.STATE = {
    WAITING = "WAITING",
    BIDDING = "BIDDING",
    KITTY = "KITTY",
    PLAYING = "PLAYING",
    TRICK_OVER = "TRICK_OVER",
    ROUND_OVER = "ROUND_OVER",
    GAME_OVER = "GAME_OVER"
}

-- ... (Keep existing code) ...


function Game:init(player_names, team_names, weights_path)
    self.players = {}
    for _, name in ipairs(player_names) do
        table.insert(self.players, Player.new(name))
    end
    
    self.teams = {
        Team.new(team_names[1], {self.players[1], self.players[3]}),
        Team.new(team_names[2], {self.players[2], self.players[4]})
    }
    
    self.deck = Deck.new()
    self.kitty = {}
    self.state = Game.STATE.WAITING
    self.dealer_idx = 1 -- 1-based index for Lua
    self.current_player_idx = 1
    
    self.winning_bid = nil
    self.trump_suit = nil
    
    -- Load Neural Network Bot Brain (shared by all bots)
    self.bot_brain = nil
    if weights_path then
        local content = love.filesystem.read(weights_path)
        if not content then
            local f = io.open(weights_path, "r")
            if f then content = f:read("*a"); f:close() end
        end
        if content then
            local weights = json.decode(content)
            self.bot_brain = {
                bid_net = Net.new(weights["bidding"]),
                play_net = Net.new(weights["playing"])
            }
            print("[AI] Neural network bot brain loaded!")
        else
            print("[AI] Warning: Could not load weights, using simple bot")
        end
    end
    
    -- Bidding State
    self.bids_this_round = {}
    self.highest_bid = nil
    self.passed_players = {} -- Set of players who passed
    self.consecutive_passes = 0
    
    -- Play State
    self.tricks_history = {}
    self.current_trick = {} -- List of {player=p, card=c}
    self.lead_suit = nil -- Suit of the first card in trick
    self.round_history = {}
    
    self.message_log = {}
    self.on_card_play_callback = nil
end

function Game:set_on_card_play(callback)
    self.on_card_play_callback = callback
end

function Game:log(msg)
    print("[GAME] " .. msg)
    table.insert(self.message_log, msg)
end

function Game:start_new_round()
    if self.state == Game.STATE.GAME_OVER then return end
    
    self:log("Starting New Round")
    self.dealer_idx = (self.dealer_idx % 4) + 1
    self:deal_cards()
    
    -- Reset Round State
    self.state = Game.STATE.BIDDING
    self.winning_bid = nil
    self.trump_suit = nil
    self.bids_this_round = {}
    self.highest_bid = nil
    self.passed_players = {}
    self.consecutive_passes = 0
    self.tricks_history = {}
    self.current_trick = {}
    
    -- Bidding starts left of dealer
    self.current_player_idx = (self.dealer_idx % 4) + 1
    self:log("Bidding starts with " .. self.players[self.current_player_idx].name)
end

function Game:deal_cards()
    self.deck:create_deck()
    self.deck:shuffle()
    self.kitty = {}
    
    for _, p in ipairs(self.players) do p:reset_for_new_round() end
    for _, t in ipairs(self.teams) do t:reset_for_new_round() end
    
    -- Deal pattern: 3, 3, 3, 3, Kitty 1 ... (Simplified for functionality)
    -- Total 10 each, 3 kitty.
    -- Just deal 10 each then 3 to kitty for simplicity unless exact order matters deeply for shuffling RNG
    local cards = self.deck:deal(43)
    local idx = 1
    
    -- Distribute (following standard 3-1-4-1-3-1 pattern simulation)
    -- Or just give 10 to each
    for i=1,4 do
        for k=1,10 do
            self.players[i]:add_card_to_hand(cards[idx])
            idx = idx + 1
        end
        self.players[i]:sort_hand()
    end
    for k=1,3 do
        table.insert(self.kitty, cards[idx])
        idx = idx + 1
    end
end

-- --- Rules Engine Methods ---

function Game:get_effective_suit(card, trump_suit)
    if card.rank == Rank.JOKER then
        return (trump_suit and trump_suit ~= Suit.NO_TRUMP) and trump_suit or Suit.NO_TRUMP
    end
    
    if not trump_suit or trump_suit == Suit.NO_TRUMP then
        return card.suit
    end
    
    -- Bower Logic
    local left_bower_suit = nil
    if trump_suit == Suit.SPADES then left_bower_suit = Suit.CLUBS
    elseif trump_suit == Suit.CLUBS then left_bower_suit = Suit.SPADES
    elseif trump_suit == Suit.DIAMONDS then left_bower_suit = Suit.HEARTS
    elseif trump_suit == Suit.HEARTS then left_bower_suit = Suit.DIAMONDS
    end
    
    if card.rank == Rank.JACK and card.suit == left_bower_suit then
        return trump_suit
    end
    
    return card.suit
end

function Game:get_playable_cards(player, trick_lead_suit)
    if not trick_lead_suit then return player.hand end -- Lead any card
    
    local following = {}
    local any_cards = player.hand
    
    -- Find cards that match effective suit
    for _, card in ipairs(any_cards) do
        if self:get_effective_suit(card, self.trump_suit) == trick_lead_suit then
            table.insert(following, card)
        end
    end
    
    -- Include Joker in 'following' if trick_lead_suit is Trump? 
    -- Handled by get_effective_suit(Joker) returning Trump. 
    -- So `following` should encompass all legal follows.
    
    -- Special case: Joker and Bowers are effectively trump. 
    -- If lead is Trump, they are in `following`.
    -- If lead is NOT Trump, but player has NO cards of lead_suit, they can play Trump (renege?).
    -- Wait, if you can follow suit, you MUST.
    
    if #following > 0 then
        return following
    else
        return any_cards -- Can play any card (discard/trump)
    end
end

function Game:get_card_strength(card, lead_suit, trump_suit)
    local eff_suit = self:get_effective_suit(card, trump_suit)
    
    -- Base strength table
    local rank_val = {
        [Rank.FOUR]=4, [Rank.FIVE]=5, [Rank.SIX]=6, [Rank.SEVEN]=7, [Rank.EIGHT]=8,
        [Rank.NINE]=9, [Rank.TEN]=10, [Rank.JACK]=11, [Rank.QUEEN]=12, [Rank.KING]=13, [Rank.ACE]=14,
        [Rank.JOKER]=100
    }
    
    local val = rank_val[card.rank] or 0
    
    -- Adjust for Bowers
    if card.rank == Rank.JACK and eff_suit == trump_suit then
        if card.suit == trump_suit then val = 20 -- Right Bower
        else val = 19 -- Left Bower
        end
    end
    
    local score = 0
    if card.rank == Rank.JOKER then
        score = 1000 -- Always highest?
        -- Unless No Trump and Joker led vs ??? 
        -- In Suit game, Joker > RB > LB > A...
    elseif eff_suit == trump_suit then
        score = 500 + val
    elseif eff_suit == lead_suit then
        score = 100 + val
    else
        score = val -- Off suit
    end
    
    return score
end

-- --- Action Handlers ---

function Game:player_bid(player_idx, tricks, suit, type)
    if self.state ~= Game.STATE.BIDDING then return false, "Not bidding phase" end
    if player_idx ~= self.current_player_idx then return false, "Not your turn" end
    
    local player = self.players[player_idx]
    if self.passed_players[player] then return false, "Already passed" end
    
    -- Construct Bid
    local success, new_bid = pcall(Bid.new, player, tricks, suit, type)
    if not success then return false, new_bid end -- new_bid is error msg
    
    -- Check against highest
    if self.highest_bid and not (new_bid > self.highest_bid) then
        return false, "Bid must be higher"
    end
    
    -- Apply
    self.highest_bid = new_bid
    self:log(tostring(new_bid))
    self.consecutive_passes = 0
    self:advance_turn()
    return true
end

function Game:player_pass(player_idx)
    if self.state ~= Game.STATE.BIDDING then return false end
    if player_idx ~= self.current_player_idx then return false end
    
    local player = self.players[player_idx]
    self.passed_players[player] = true
    self:log(player.name .. " passes")
    self.consecutive_passes = self.consecutive_passes + 1
    
    self:check_bidding_end()
    if self.state == Game.STATE.BIDDING then
        self:advance_turn()
    end
    return true
end

function Game:advance_turn()
    -- Find next player who hasn't passed (unless all passed)
    local start_idx = self.current_player_idx
    for i=1,4 do
        self.current_player_idx = (self.current_player_idx % 4) + 1
        local p = self.players[self.current_player_idx]
        if not self.passed_players[p] then
            break
        end
    end
end

function Game:check_bidding_end()
    -- Count total active players (not passed)
    local active_count = 0
    for _, p in ipairs(self.players) do
        if not self.passed_players[p] then active_count = active_count + 1 end
    end
    
    -- If only 1 player left and a bid exists -> Win
    if self.highest_bid and active_count == 1 then
        self.winning_bid = self.highest_bid
        self:log("Winning Bid: " .. tostring(self.winning_bid))
        self.state = Game.STATE.KITTY
        -- Setup Kitty phase
        self.current_player_idx = self:get_player_index(self.winning_bid.player)
        self.trump_suit = (self.winning_bid.bid_type == BidType.NO_TRUMP or 
                           self.winning_bid.bid_type == BidType.MISERE or 
                           self.winning_bid.bid_type == BidType.OPEN_MISERE) 
                           and Suit.NO_TRUMP or self.winning_bid.suit
                           
        -- Give Kitty Logic
        local declarer = self.players[self.current_player_idx]
        declarer:add_cards_to_hand(self.kitty)
        declarer:sort_hand()
        self:log("Kitty given to " .. declarer.name)
        
    elseif not self.highest_bid and active_count == 0 then
        -- Or 4 consecutive passes if no bid?
        -- `consecutive_passes` logic handles the initial "Everyone passes" case
        self:log("All passed. Redeal.")
        self:start_new_round() 
    elseif not self.highest_bid and self.consecutive_passes >= 4 then
         self:log("All passed (Consecutive). Redeal.")
         self:start_new_round()
    end
end

function Game:player_discard_kitty(player_idx, discards)
    if self.state ~= Game.STATE.KITTY then return false end
    if player_idx ~= self.current_player_idx then return false end
    
    local player = self.players[player_idx]
    if #discards ~= 3 then return false, "Must discard 3 cards" end
    
    -- Process discards
    for _, card in ipairs(discards) do
        player:play_card(card) -- Removes from hand
    end
    self:log("Discard complete")
    
    -- Start Play
    self.state = Game.STATE.PLAYING
    self.lead_suit = nil
    self.current_trick = {}
    -- Leader is declarer (current player)
end

function Game:player_play_card(player_idx, card)
    if self.state ~= Game.STATE.PLAYING then return false end
    if player_idx ~= self.current_player_idx then return false end
    
    local player = self.players[player_idx]
    local playable = self:get_playable_cards(player, self.lead_suit)
    
    -- Verify card is playable
    local is_valid = false
    effective_play = card -- Might need to find exact instance if passing copy
    for _, c in ipairs(playable) do
        if c == card then is_valid = true; break end
    end
    if not is_valid then return false, "Invalid card" end
    
    -- Execute Play
    -- Check if it's HUMAN (P1) - TableView handles their animation via dry-run + callback
    -- BUT for simplicity/uniformity, maybe we trigger here for everyone?
    -- Issue: Human plays via TableView -> Animation -> Game:play() logic.
    -- If we animate here again, we duplicate.
    -- Solution: TableView logic remains for P1 dry-run. Or better:
    -- Game logic notifies. TableView handles.
    
    -- Actually, simpler:
    -- If we have a callback, invoke it.
    
    if self.on_card_play_callback then
        self.on_card_play_callback(player_idx, card)
    end

    player:play_card(card)
    table.insert(self.current_trick, {player=player, card=card})
    
    if #self.current_trick == 1 then
        self.lead_suit = self:get_effective_suit(card, self.trump_suit)
    end
    
    if #self.current_trick == 4 then
        self:resolve_trick()
    else
        self.current_player_idx = (self.current_player_idx % 4) + 1
    end
    
    return true
end

function Game:resolve_trick()
    local winner = nil
    local best_score = -1
    
    for _, play in ipairs(self.current_trick) do
        local score = self:get_card_strength(play.card, self.lead_suit, self.trump_suit)
        if score > best_score then
            best_score = score
            winner = play.player
        end
    end
    
    winner:increment_tricks_won()
    self:log("Trick won by " .. winner.name)
    table.insert(self.tricks_history, {winner=winner, cards=self.current_trick})
    
    if #self.tricks_history == 10 then
        self:score_round()
    else
        self.state = Game.STATE.TRICK_OVER
        self.last_trick_winner = winner
    end
end

function Game:next_trick()
    if self.state ~= Game.STATE.TRICK_OVER then return end
    
    self.current_trick = {}
    self.lead_suit = nil
    self.current_player_idx = self:get_player_index(self.last_trick_winner)
    self.state = Game.STATE.PLAYING
    self.last_trick_winner = nil
end

function Game:score_round()
    self:log("Round Over")
    -- Scoring logic (simplified)
    local declarer = self.winning_bid.player
    local tricks = declarer.tricks_won_this_round
    -- Check partner tricks too!
    local declarer_team = nil
    for _, t in ipairs(self.teams) do
        for _, p in ipairs(t.players) do if p == declarer then declarer_team = t end end
    end
    local total_tricks = declarer_team:get_total_tricks_won_this_round()
    
    if total_tricks >= self.winning_bid.tricks then
        self:log("Contract Made!")
        declarer_team:update_score(self.winning_bid.points)
    else
        self:log("Contract Failed!")
        declarer_team:update_score(-self.winning_bid.points)
    end
    
    self.state = Game.STATE.ROUND_OVER
end

function Game:get_player_index(player)
    for i, p in ipairs(self.players) do if p == player then return i end end
    return -1
end

function Game:update(dt)
    -- State updates
    if self.state == Game.STATE.GAME_OVER then return end
    
    -- Bot Logic
    -- If current player is not P1 (Human), take action
    if self.current_player_idx ~= 1 then
        self.ai_timer = (self.ai_timer or 0) + dt
        if self.ai_timer > 1.0 then -- 1 second delay
            self.ai_timer = 0
            self:do_bot_action()
        end
    end
end

function Game:do_bot_action()
    local p_idx = self.current_player_idx
    local player = self.players[p_idx]
    
    if self.state == Game.STATE.BIDDING then
        if self.bot_brain then
            -- Neural Network Bid Decision
            local vec = FeatureExtractor.get_state_vector(self, p_idx)
            local logits = self.bot_brain.bid_net:forward(vec)
            
            -- Find best valid bid (mask out Misere 26, 27)
            -- Also need to mask bids lower than current highest
            local max_val = -1e9
            local max_idx = 0 -- 0 = Pass
            
            for i = 1, #logits do
                local action_idx = i - 1 -- 0-based
                local valid = true
                
                -- Mask Misere (not trained)
                if action_idx == 26 or action_idx == 27 then valid = false end
                
                -- Mask lower bids (if there's already a highest bid)
                if action_idx >= 1 and action_idx <= 25 and self.highest_bid then
                    local adj = action_idx - 1
                    local tricks = 6 + math.floor(adj / 5)
                    local s_idx = adj % 5
                    local suits = {[0]=Suit.SPADES, [1]=Suit.CLUBS, [2]=Suit.DIAMONDS, [3]=Suit.HEARTS, [4]=Suit.NO_TRUMP}
                    local suit = suits[s_idx]
                    local bid_type = (suit == Suit.NO_TRUMP) and BidType.NO_TRUMP or BidType.SUIT_TRUMP
                    
                    local temp_bid = Bid.new(player, tricks, suit, bid_type)
                    if not (temp_bid > self.highest_bid) then
                        valid = false
                    end
                end
                
                if valid and logits[i] > max_val then
                    max_val = logits[i]
                    max_idx = action_idx
                end
            end
            
            -- Execute action
            if max_idx == 0 then
                self:player_pass(p_idx)
            else
                local action, params = FeatureExtractor.decode_action(max_idx, "BID")
                if action == "bid" and params then
                    self:player_bid(p_idx, params[1], params[2], params[3])
                else
                    self:player_pass(p_idx)
                end
            end
        else
            -- Fallback: Simple bot always passes
            self:player_pass(p_idx)
        end
        
    elseif self.state == Game.STATE.KITTY then
        -- Bot discards first 3 cards (simplified)
        local discards = {player.hand[1], player.hand[2], player.hand[3]}
        self:player_discard_kitty(p_idx, discards)
        
    elseif self.state == Game.STATE.PLAYING then
        local playable = self:get_playable_cards(player, self.lead_suit)
        
        if self.bot_brain and #playable > 0 then
            -- Neural Network Play Decision
            local vec = FeatureExtractor.get_state_vector(self, p_idx)
            local logits = self.bot_brain.play_net:forward(vec)
            
            -- Find best playable card
            local best_card = playable[1]
            local max_val = -1e9
            
            for _, card in ipairs(playable) do
                local c_idx = FeatureExtractor.card_to_int(card)
                local val = logits[c_idx + 1] -- 1-based Lua index
                if val > max_val then
                    max_val = val
                    best_card = card
                end
            end
            
            self:player_play_card(p_idx, best_card)
        elseif #playable > 0 then
            -- Fallback: Play first valid card
            self:player_play_card(p_idx, playable[1])
        end
    end
end

return Game
