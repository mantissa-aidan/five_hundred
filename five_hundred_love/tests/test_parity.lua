
-- Test Parity with Python
local TestRunner = require "tests.test_runner"
local FeatureExtractor = require "src.ai.feature_extractor"
local Game = require "src.core.game"
local json = require "src.ext.json"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

-- Helper to read file
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

-- Helper to reconstruct logic
-- Since we are testing FeatureExtractor, we need a Game object that "looks" like the snapshot.
local function hydrate_game(game, snapshot)
    local Suit = CardModule.Suit
    local Rank = CardModule.Rank
    local Bid = BidModule.Bid
    local BidType = BidModule.BidType

    -- 1. Phase
    -- Python phase is "BID", "PLAY"
    -- Lua Game needs "BIDDING", "PLAYING"
    local p_map = {['BID']="BIDDING", ['PLAY']="PLAYING", ['KITTY']="KITTY", ['TRICK_OVER']="TRICK_OVER"}
    game.state = p_map[snapshot.phase] or snapshot.phase
    
    -- 2. Hands
    -- snapshot.hands is list of list of strings ["AH", ..]
    -- We need to overwrite game.players[i].hand
    for i, p_hand_strs in ipairs(snapshot.hands) do
        local hand = {}
        for _, s in ipairs(p_hand_strs) do
             -- Parse "AH" -> Rank.ACE, Suit.HEARTS
             -- Actually, CardModule might have helper? Utils?
             -- Let's just create raw cards manually or add helper
             -- Assuming "AH" format:
             if s == "Joker" then
                 table.insert(hand, CardModule.Card.new(Suit.NO_TRUMP, Rank.JOKER))
             else
                  local r_char = string.sub(s, 1, 1)
                  local s_char = string.sub(s, 2, 2)
                  
                  -- Debug
                  -- print("Parsing: " .. s .. " R=" .. r_char .. " S=" .. s_char)


                 local r_map = {['4']=Rank.FOUR, ['5']=Rank.FIVE, ['6']=Rank.SIX, ['7']=Rank.SEVEN, ['8']=Rank.EIGHT, 
                                ['9']=Rank.NINE, ['T']=Rank.TEN, ['J']=Rank.JACK, ['Q']=Rank.QUEEN, ['K']=Rank.KING, ['A']=Rank.ACE}
                 local s_map = {['S']=Suit.SPADES, ['C']=Suit.CLUBS, ['D']=Suit.DIAMONDS, ['H']=Suit.HEARTS}
                 
                 table.insert(hand, CardModule.Card.new(s_map[s_char], r_map[r_char]))
             end
        end
        game.players[i].hand = hand
        for j, c in ipairs(hand) do if not c.rank then error("Nil Rank for card: " .. p_hand_strs[j]) end end
    end
    
    -- 3. Dealer & Current Player
    game.dealer_idx = snapshot.dealer_idx + 1 -- Python 0-indexed -> Lua 1-indexed
    game.current_player_idx = snapshot.current_player + 1
    
    -- 4. Trump
    if snapshot.trump then
        local s_map_full = {['SPADES']=Suit.SPADES, ['CLUBS']=Suit.CLUBS, ['DIAMONDS']=Suit.DIAMONDS, ['HEARTS']=Suit.HEARTS, ['NO_TRUMP']=Suit.NO_TRUMP}
        game.trump_suit = s_map_full[snapshot.trump]
    else
        game.trump_suit = nil
    end

    -- 5. Bids History (CRITICAL: This is missing in Game.lua currently!)
    game.bids_this_round = {}
    for _, b_dict in ipairs(snapshot.bids_history) do
        if b_dict.type == "PASS" then
             -- Logic for pass? Usually just tracked in game but FeatureExtractor needs linear history.
             local b = {bid_type=BidType.PASS, player={name=b_dict.player}}
             -- Find actual player obj
             for _, p in ipairs(game.players) do if p.name == b_dict.player then b.player = p end end
             table.insert(game.bids_this_round, b)
        else
             local s_map_full = {['SPADES']=Suit.SPADES, ['CLUBS']=Suit.CLUBS, ['DIAMONDS']=Suit.DIAMONDS, ['HEARTS']=Suit.HEARTS, ['NO_TRUMP']=Suit.NO_TRUMP}
             local b = Bid.new(nil, b_dict.tricks, s_map_full[b_dict.suit], BidType[b_dict.type])
             b.player = {name=b_dict.player} -- Mock player ref
             -- Find actual player obj
             for _, p in ipairs(game.players) do if p.name == b_dict.player then b.player = p end end
             table.insert(game.bids_this_round, b)
        end
    end
    
    -- 6. Tricks History
    game.tricks_history = {}
    if snapshot.tricks_history then
         for _, t_data in ipairs(snapshot.tricks_history) do
             local trick = {cards={}}
             for _, c_dict in ipairs(t_data.cards) do
                  -- Parse Card (Duplicated logic)
                  local s = c_dict.card
                  local card = nil
                  if s == "Joker" then card = CardModule.Card.new(Suit.NO_TRUMP, Rank.JOKER)
                  else
                      local r_char = string.sub(s, 1, 1)
                      local s_char = string.sub(s, 2, 2)
                      local r_map = {['4']=Rank.FOUR, ['5']=Rank.FIVE, ['6']=Rank.SIX, ['7']=Rank.SEVEN, ['8']=Rank.EIGHT, 
                                     ['9']=Rank.NINE, ['T']=Rank.TEN, ['J']=Rank.JACK, ['Q']=Rank.QUEEN, ['K']=Rank.KING, ['A']=Rank.ACE}
                      local s_map = {['S']=Suit.SPADES, ['C']=Suit.CLUBS, ['D']=Suit.DIAMONDS, ['H']=Suit.HEARTS}
                      card = CardModule.Card.new(s_map[s_char], r_map[r_char])
                      if not card.rank then error("Nil Rank Tricks History: " .. s) end
                  end
                  
                  -- Find player by name
                  local p_obj
                  for _, p in ipairs(game.players) do if p.name == c_dict.player then p_obj = p end end
                  
                  table.insert(trick.cards, {
                      card = card,
                      player = p_obj
                  })
             end
             table.insert(game.tricks_history, trick)
         end
    end
    
    -- Tricks Won
    if snapshot.tricks_won then
        for i, count in ipairs(snapshot.tricks_won) do
            game.players[i].tricks_won_round = count
        end
    end
    
    -- 7. Current Trick
    game.current_trick = {}
    for _, c_dict in ipairs(snapshot.current_trick) do
         -- c_dict = {card="AH", player=0}
         -- Need to parse card again (Copy-paste logic above or refactor)
         local s = c_dict.card
         local card = nil
         -- Parse (Duplicated logic for speed)
         if s == "Joker" then card = CardModule.Card.new(Suit.NO_TRUMP, Rank.JOKER)
         else
             local r_char = string.sub(s, 1, 1)
             local s_char = string.sub(s, 2, 2)
             local r_map = {['4']=Rank.FOUR, ['5']=Rank.FIVE, ['6']=Rank.SIX, ['7']=Rank.SEVEN, ['8']=Rank.EIGHT, 
                            ['9']=Rank.NINE, ['T']=Rank.TEN, ['J']=Rank.JACK, ['Q']=Rank.QUEEN, ['K']=Rank.KING, ['A']=Rank.ACE}
             local s_map = {['S']=Suit.SPADES, ['C']=Suit.CLUBS, ['D']=Suit.DIAMONDS, ['H']=Suit.HEARTS}
             card = CardModule.Card.new(s_map[s_char], r_map[r_char])
         end
         
         table.insert(game.current_trick, {
             card = card,
             player = game.players[c_dict.player + 1]
         })
    end
    
    -- 8. Cards Played This Round (New)
    game.cards_played_this_round = {}
    if snapshot.cards_played then
        for _, s in ipairs(snapshot.cards_played) do
             -- Parse Card (Duplicated logic again - should refactor helper but copy-paste is safer for now)
             local card = nil
             if s == "Joker" then card = CardModule.Card.new(Suit.NO_TRUMP, Rank.JOKER)
             else
                  local r_char = string.sub(s, 1, 1)
                  local s_char = string.sub(s, 2, 2)
                  local r_map = {['4']=Rank.FOUR, ['5']=Rank.FIVE, ['6']=Rank.SIX, ['7']=Rank.SEVEN, ['8']=Rank.EIGHT, 
                                 ['9']=Rank.NINE, ['T']=Rank.TEN, ['J']=Rank.JACK, ['Q']=Rank.QUEEN, ['K']=Rank.KING, ['A']=Rank.ACE}
                  local s_map = {['S']=Suit.SPADES, ['C']=Suit.CLUBS, ['D']=Suit.DIAMONDS, ['H']=Suit.HEARTS}
                  card = CardModule.Card.new(s_map[s_char], r_map[r_char])
             end
             table.insert(game.cards_played_this_round, card)
        end
    end
    
    game.scores = {snapshot.scores[1], snapshot.scores[2]} -- Python Team 0/1 -> Lua Team 1/2? Lua teams index 1,2
    -- game.teams[1].score = ... logic? FeatureExtractor reads game.teams[1].score
    game.teams[1].score = snapshot.scores[1]
    game.teams[2].score = snapshot.scores[2]
    
    -- Winning Bid
    if snapshot.winning_bid then
       local wb_dict = snapshot.winning_bid
       local b
       if wb_dict.type == "PASS" then
           b = BidModule.Bid.new(nil, 0, nil, BidType.PASS) -- Should not be winning bid usually?
       else
           local s_map_full = {['SPADES']=Suit.SPADES, ['CLUBS']=Suit.CLUBS, ['DIAMONDS']=Suit.DIAMONDS, ['HEARTS']=Suit.HEARTS, ['NO_TRUMP']=Suit.NO_TRUMP}
           b = Bid.new(nil, wb_dict.tricks, s_map_full[wb_dict.suit], BidType[wb_dict.type])
       end
       -- Find Player
       for _, p in ipairs(game.players) do if p.name == wb_dict.player then b.player = p end end
       game.winning_bid = b
    end
end

TestRunner.describe("Feature Parity", function()
    local golden_path = "five_hundred_love/tests/golden_data.json"
    local content = read_file(golden_path)
    
    if not content then
        print("Skipping Parity Tests: golden_data.json not found")
        return
    end
    
    local snapshots = json.decode(content)
    
    TestRunner.it("should match Python feature vectors", function()
        local matches = 0
        local total = #snapshots
        local max_diff = 0
        
        for i, snap in ipairs(snapshots) do
            -- Names must match Python names for history mapping
            local game = Game.new({"Agent", "Bot1", "Bot2", "Bot3"}, {"T1", "T2"})
            hydrate_game(game, snap)
            
            -- Run Feature Extractor
            -- Lua Agent index is 1 (P1). Python was P0.
            -- snapshot.my_idx is 0. Python P0 -> Lua P1.
            local vec = FeatureExtractor.get_state_vector(game, snap.my_idx + 1)
            
            -- Compare
            if #vec ~= #snap.expected_vector then
                error(string.format("Vector length mismatch: Lua %d vs Python %d", #vec, #snap.expected_vector))
            end
            
            local diff_sum = 0
            for j=1, #vec do
                local d = math.abs(vec[j] - snap.expected_vector[j])
                diff_sum = diff_sum + d
                if d > 1e-4 then
                    print(string.format("Mismatch at index %d: Lua %.4f Py %.4f", j, vec[j], snap.expected_vector[j]))
                end
            end
            
            if diff_sum > 0.01 then
                -- Fail
                print("Snapshot " .. i .. " Failed. Diff Sum: " .. diff_sum)
                if i == 1 then break end -- Stop after first failure
            else
                matches = matches + 1
            end
        end
        
        TestRunner.assert_equal(total, matches, "Some snapshots did not match")
    end)
end)

return TestRunner
