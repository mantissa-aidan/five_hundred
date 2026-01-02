-- Tests for Team module
local TestRunner = require "tests.test_runner"
local Team = require "src.core.team"
local Player = require "src.core.player"

local describe = TestRunner.describe
local it = TestRunner.it
local assert_equal = TestRunner.assert_equal
local assert_true = TestRunner.assert_true
local assert_false = TestRunner.assert_false
local assert_error = TestRunner.assert_error

describe("Team", function()

    it("creates a team with name and 2 players", function()
        local p1 = Player.new("Alice")
        local p2 = Player.new("Bob")
        local team = Team.new("Team Alpha", {p1, p2})

        assert_equal("Team Alpha", team.name)
        assert_equal(2, #team.players)
        assert_equal(p1, team.players[1])
        assert_equal(p2, team.players[2])
        assert_equal(0, team.team_score)
        assert_false(team.has_bid_this_round)
    end)

    it("throws error for more than 2 players", function()
        local p1 = Player.new("Alice")
        local p2 = Player.new("Bob")
        local p3 = Player.new("Charlie")

        assert_error(function()
            Team.new("Too Big", {p1, p2, p3})
        end, "Should throw error for team with more than 2 players")
    end)

    it("updates score correctly", function()
        local team = Team.new("Team Alpha", {Player.new("Alice"), Player.new("Bob")})
        assert_equal(0, team.team_score)

        team:update_score(100)
        assert_equal(100, team.team_score)

        team:update_score(50)
        assert_equal(150, team.team_score)

        team:update_score(-200)
        assert_equal(-50, team.team_score)
    end)

    it("calculates total tricks won this round", function()
        local p1 = Player.new("Alice")
        local p2 = Player.new("Bob")
        local team = Team.new("Team Alpha", {p1, p2})

        assert_equal(0, team:get_total_tricks_won_this_round())

        p1.tricks_won_this_round = 3
        p2.tricks_won_this_round = 2

        assert_equal(5, team:get_total_tricks_won_this_round())
    end)

    it("resets for new round", function()
        local p1 = Player.new("Alice")
        local p2 = Player.new("Bob")
        local team = Team.new("Team Alpha", {p1, p2})

        team.has_bid_this_round = true
        p1.tricks_won_this_round = 4
        p2.tricks_won_this_round = 3

        team:reset_for_new_round()

        assert_false(team.has_bid_this_round)
        assert_equal(0, p1.tricks_won_this_round)
        assert_equal(0, p2.tricks_won_this_round)
    end)

    it("converts to string with name and score", function()
        local team = Team.new("Team Alpha", {Player.new("Alice"), Player.new("Bob")})
        team:update_score(250)

        local str = tostring(team)
        assert_true(string.find(str, "Team Alpha") ~= nil)
        assert_true(string.find(str, "250") ~= nil)
    end)

end)

return TestRunner
