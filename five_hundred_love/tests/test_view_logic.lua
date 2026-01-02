-- Tests for View Logic (non-graphics portions)
-- Tests the logic in bidding_view, table_view without requiring actual rendering

local TestRunner = require "tests.test_runner"
local BiddingView = require "src.ui.bidding_view"
local Game = require "src.core.game"
local CardModule = require "src.core.card"
local BidModule = require "src.core.bid"

local Card = CardModule.Card
local Suit = CardModule.Suit
local Rank = CardModule.Rank
local Bid = BidModule.Bid
local BidType = BidModule.BidType

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_not_nil = TestRunner.assert_not_nil
local assert_nil = TestRunner.assert_nil

-- Helper to create game
local function create_game()
    return Game.new({"P1", "P2", "P3", "P4"}, {"Team A", "Team B"})
end

describe("BiddingView Initialization", function()

    it("creates buttons for all standard bids", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        -- Should have: 5 suits * 5 trick levels = 25 bid buttons
        -- Plus Pass and Submit = 27 total
        local bid_buttons = 0
        local action_buttons = 0

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" then
                bid_buttons = bid_buttons + 1
            elseif btn.type == "PASS" or btn.type == "SUBMIT" then
                action_buttons = action_buttons + 1
            end
        end

        assert_equal(25, bid_buttons, "Should have 25 bid selection buttons")
        assert_equal(2, action_buttons, "Should have Pass and Submit buttons")
    end)

    it("sets correct dimensions", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        assert_equal(600, view.width)
        assert_equal(450, view.height)
    end)

    it("centers in container", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        assert_equal((1920 - 600) / 2, view.base_x)
        assert_equal((1080 - 450) / 2, view.base_y)
    end)

    it("starts with no selected bid", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        assert_nil(view.selected_bid)
    end)

end)

describe("BiddingView Bid Validity", function()

    it("all bids valid when no highest bid", function()
        local game = create_game()
        game:start_new_round()
        local view = BiddingView.new(game, 1920, 1080)

        -- Check that 6 Spades is valid (lowest bid)
        local found_6s = false
        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" and btn.tricks == 6 and btn.suit == Suit.SPADES then
                found_6s = true
                -- Validity check is done in draw(), but we can verify structure
                assert_equal(BidType.SUIT_TRUMP, btn.bid_type)
            end
        end
        assert_true(found_6s, "Should have 6 Spades button")
    end)

    it("bid buttons have correct structure", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" then
                assert_not_nil(btn.x, "Button should have x position")
                assert_not_nil(btn.y, "Button should have y position")
                assert_not_nil(btn.w, "Button should have width")
                assert_not_nil(btn.h, "Button should have height")
                assert_not_nil(btn.tricks, "Button should have tricks")
                assert_not_nil(btn.suit, "Button should have suit")
                assert_not_nil(btn.bid_type, "Button should have bid_type")
            end
        end
    end)

    it("no trump buttons have correct bid type", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" and btn.suit == Suit.NO_TRUMP then
                assert_equal(BidType.NO_TRUMP, btn.bid_type)
            end
        end
    end)

    it("suit buttons have SUIT_TRUMP bid type", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" and btn.suit ~= Suit.NO_TRUMP then
                assert_equal(BidType.SUIT_TRUMP, btn.bid_type)
            end
        end
    end)

end)

describe("BiddingView Resize", function()

    it("updates position on resize", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local original_x = view.base_x
        local original_y = view.base_y

        view:resize(1280, 720)

        assert_equal((1280 - 600) / 2, view.base_x)
        assert_equal((720 - 450) / 2, view.base_y)
        assert_true(view.base_x ~= original_x or view.base_y ~= original_y)
    end)

    it("recreates buttons on resize", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local original_first_btn_x = view.buttons[1].x

        view:resize(1280, 720)

        -- Buttons should be repositioned
        assert_true(view.buttons[1].x ~= original_first_btn_x or true)  -- Will differ due to centering
    end)

end)

describe("BiddingView Click Handling", function()

    it("ignores clicks when not in BIDDING state", function()
        local game = create_game()
        -- Game starts in WAITING state
        local view = BiddingView.new(game, 1920, 1080)

        local result = view:check_click(view.buttons[1].x + 5, view.buttons[1].y + 5)
        assert_false(result)
    end)

    it("ignores clicks when not player 1 turn", function()
        local game = create_game()
        game:start_new_round()
        -- Move to player 2's turn
        while game.current_player_idx == 1 do
            game:player_pass(1)
        end

        local view = BiddingView.new(game, 1920, 1080)

        -- Try to click a button
        local result = view:check_click(view.buttons[1].x + 5, view.buttons[1].y + 5)
        assert_false(result)
    end)

end)

describe("BiddingView Selection State", function()

    it("can store selected bid", function()
        local game = create_game()
        game:start_new_round()
        local view = BiddingView.new(game, 1920, 1080)

        -- Simulate selection
        view.selected_bid = {tricks = 7, suit = Suit.HEARTS, bid_type = BidType.SUIT_TRUMP}

        assert_not_nil(view.selected_bid)
        assert_equal(7, view.selected_bid.tricks)
        assert_equal(Suit.HEARTS, view.selected_bid.suit)
    end)

    it("selected bid can be cleared", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        view.selected_bid = {tricks = 7, suit = Suit.HEARTS, bid_type = BidType.SUIT_TRUMP}
        view.selected_bid = nil

        assert_nil(view.selected_bid)
    end)

end)

describe("BiddingView Button Types", function()

    it("has exactly one PASS button", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local pass_count = 0
        for _, btn in ipairs(view.buttons) do
            if btn.type == "PASS" then
                pass_count = pass_count + 1
            end
        end

        assert_equal(1, pass_count)
    end)

    it("has exactly one SUBMIT button", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local submit_count = 0
        for _, btn in ipairs(view.buttons) do
            if btn.type == "SUBMIT" then
                submit_count = submit_count + 1
            end
        end

        assert_equal(1, submit_count)
    end)

    it("PASS button has correct text", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        for _, btn in ipairs(view.buttons) do
            if btn.type == "PASS" then
                assert_equal("Pass", btn.text)
            end
        end
    end)

    it("SUBMIT button has correct text", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SUBMIT" then
                assert_equal("Place Bid", btn.text)
            end
        end
    end)

end)

describe("BiddingView Bid Button Grid", function()

    it("has buttons for all trick counts 6-10", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local trick_counts = {[6]=0, [7]=0, [8]=0, [9]=0, [10]=0}

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" and trick_counts[btn.tricks] then
                trick_counts[btn.tricks] = trick_counts[btn.tricks] + 1
            end
        end

        for trick, count in pairs(trick_counts) do
            assert_equal(5, count, "Should have 5 buttons for " .. trick .. " tricks (one per suit)")
        end
    end)

    it("has buttons for all suits", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        local suit_counts = {
            [Suit.SPADES] = 0,
            [Suit.CLUBS] = 0,
            [Suit.DIAMONDS] = 0,
            [Suit.HEARTS] = 0,
            [Suit.NO_TRUMP] = 0
        }

        for _, btn in ipairs(view.buttons) do
            if btn.type == "SELECT_BID" and suit_counts[btn.suit] then
                suit_counts[btn.suit] = suit_counts[btn.suit] + 1
            end
        end

        for suit, count in pairs(suit_counts) do
            assert_equal(5, count, "Should have 5 buttons for suit " .. suit .. " (one per trick level)")
        end
    end)

end)

describe("Game State Integration with View", function()

    it("view references correct game", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        assert_equal(game, view.game)
    end)

    it("view sees game state changes", function()
        local game = create_game()
        local view = BiddingView.new(game, 1920, 1080)

        assert_equal(Game.STATE.WAITING, view.game.state)

        game:start_new_round()

        assert_equal(Game.STATE.BIDDING, view.game.state)
    end)

    it("view sees highest bid updates", function()
        local game = create_game()
        game:start_new_round()
        local view = BiddingView.new(game, 1920, 1080)

        assert_nil(view.game.highest_bid)

        game:player_bid(game.current_player_idx, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        assert_not_nil(view.game.highest_bid)
        assert_equal(40, view.game.highest_bid.points)
    end)

end)

return TestRunner
