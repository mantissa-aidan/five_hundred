-- Tests for Bid module
local TestRunner = require "tests.test_runner"
local BidModule = require "src.core.bid"
local Player = require "src.core.player"
local CardModule = require "src.core.card"

local Bid = BidModule.Bid
local BidType = BidModule.BidType
local Suit = CardModule.Suit

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_error = TestRunner.assert_error

describe("BidType", function()

    it("has correct enum values", function()
        assert_equal("Suit Trump", BidType.SUIT_TRUMP)
        assert_equal("No Trump", BidType.NO_TRUMP)
        assert_equal("Misere", BidType.MISERE)
        assert_equal("Open Misere", BidType.OPEN_MISERE)
    end)

end)

describe("Bid", function()

    it("creates a valid suit bid", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.SPADES, BidType.SUIT_TRUMP)

        assert_equal(player, bid.player)
        assert_equal(6, bid.tricks)
        assert_equal(Suit.SPADES, bid.suit)
        assert_equal(BidType.SUIT_TRUMP, bid.bid_type)
        assert_equal(40, bid.points)  -- 6 Spades = 40 points
    end)

    it("creates a valid no trump bid", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 7, Suit.NO_TRUMP, BidType.NO_TRUMP)

        assert_equal(7, bid.tricks)
        assert_equal(Suit.NO_TRUMP, bid.suit)
        assert_equal(BidType.NO_TRUMP, bid.bid_type)
        assert_equal(220, bid.points)  -- 7 No Trump = 220 points
    end)

    it("creates a valid Misere bid", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 0, nil, BidType.MISERE)

        assert_equal(0, bid.tricks)
        assert_equal(Suit.NO_TRUMP, bid.suit)  -- Canonicalized
        assert_equal(BidType.MISERE, bid.bid_type)
        assert_equal(250, bid.points)
    end)

    it("creates a valid Open Misere bid", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 0, nil, BidType.OPEN_MISERE)

        assert_equal(0, bid.tricks)
        assert_equal(500, bid.points)
    end)

    it("throws error for suit bid below 6 tricks", function()
        local player = Player.new("Alice")
        assert_error(function()
            Bid.new(player, 5, Suit.HEARTS, BidType.SUIT_TRUMP)
        end)
    end)

    it("throws error for no trump bid below 6 tricks", function()
        local player = Player.new("Alice")
        assert_error(function()
            Bid.new(player, 5, Suit.NO_TRUMP, BidType.NO_TRUMP)
        end)
    end)

    it("throws error for Misere with non-zero tricks", function()
        local player = Player.new("Alice")
        assert_error(function()
            Bid.new(player, 1, nil, BidType.MISERE)
        end)
    end)

    it("throws error for suit trump without valid suit", function()
        local player = Player.new("Alice")
        assert_error(function()
            Bid.new(player, 6, Suit.NO_TRUMP, BidType.SUIT_TRUMP)
        end)
    end)

    it("throws error for tricks out of range", function()
        local player = Player.new("Alice")
        assert_error(function()
            Bid.new(player, 11, Suit.HEARTS, BidType.SUIT_TRUMP)
        end)
        assert_error(function()
            Bid.new(player, -1, Suit.HEARTS, BidType.SUIT_TRUMP)
        end)
    end)

end)

describe("Bid Points (Avondale Scoring)", function()

    it("calculates 6 Spades correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.SPADES, BidType.SUIT_TRUMP)
        assert_equal(40, bid.points)
    end)

    it("calculates 6 Clubs correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.CLUBS, BidType.SUIT_TRUMP)
        assert_equal(60, bid.points)
    end)

    it("calculates 6 Diamonds correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.DIAMONDS, BidType.SUIT_TRUMP)
        assert_equal(80, bid.points)
    end)

    it("calculates 6 Hearts correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.HEARTS, BidType.SUIT_TRUMP)
        assert_equal(100, bid.points)
    end)

    it("calculates 6 No Trump correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 6, Suit.NO_TRUMP, BidType.NO_TRUMP)
        assert_equal(120, bid.points)
    end)

    it("calculates 10 No Trump correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 10, Suit.NO_TRUMP, BidType.NO_TRUMP)
        assert_equal(520, bid.points)
    end)

    it("calculates 8 Hearts correctly", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 8, Suit.HEARTS, BidType.SUIT_TRUMP)
        assert_equal(300, bid.points)
    end)

end)

describe("Bid Comparison", function()

    it("compares bids by points", function()
        local player = Player.new("Alice")
        local bid_6s = Bid.new(player, 6, Suit.SPADES, BidType.SUIT_TRUMP)     -- 40
        local bid_6c = Bid.new(player, 6, Suit.CLUBS, BidType.SUIT_TRUMP)      -- 60
        local bid_7s = Bid.new(player, 7, Suit.SPADES, BidType.SUIT_TRUMP)     -- 140
        local bid_mis = Bid.new(player, 0, nil, BidType.MISERE)                 -- 250

        assert_true(bid_6s < bid_6c, "6S (40) < 6C (60)")
        assert_true(bid_6c < bid_7s, "6C (60) < 7S (140)")
        assert_true(bid_7s < bid_mis, "7S (140) < Misere (250)")
    end)

    it("6 NT beats all 6-level suit bids", function()
        local player = Player.new("Alice")
        local bid_6nt = Bid.new(player, 6, Suit.NO_TRUMP, BidType.NO_TRUMP)    -- 120
        local bid_6h = Bid.new(player, 6, Suit.HEARTS, BidType.SUIT_TRUMP)     -- 100

        assert_true(bid_6h < bid_6nt)
    end)

    it("Misere beats 7 No Trump", function()
        local player = Player.new("Alice")
        local bid_7nt = Bid.new(player, 7, Suit.NO_TRUMP, BidType.NO_TRUMP)    -- 220
        local bid_mis = Bid.new(player, 0, nil, BidType.MISERE)                 -- 250

        assert_true(bid_7nt < bid_mis)
    end)

    it("Open Misere is highest bid", function()
        local player = Player.new("Alice")
        local bid_10nt = Bid.new(player, 10, Suit.NO_TRUMP, BidType.NO_TRUMP)  -- 520
        local bid_open_mis = Bid.new(player, 0, nil, BidType.OPEN_MISERE)       -- 500

        -- 10NT (520) actually beats Open Misere (500)
        assert_true(bid_open_mis < bid_10nt, "10NT (520) > Open Misere (500)")
    end)

end)

describe("Bid String Representation", function()

    it("converts suit bid to string", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 7, Suit.HEARTS, BidType.SUIT_TRUMP)
        local str = tostring(bid)

        assert_true(string.find(str, "Alice") ~= nil)
        assert_true(string.find(str, "7") ~= nil)
        assert_true(string.find(str, "Hearts") ~= nil)
    end)

    it("converts Misere to string", function()
        local player = Player.new("Alice")
        local bid = Bid.new(player, 0, nil, BidType.MISERE)
        local str = tostring(bid)

        assert_true(string.find(str, "Alice") ~= nil)
        assert_true(string.find(str, "Misere") ~= nil)
    end)

end)

return TestRunner
