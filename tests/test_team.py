import pytest
from five_hundred.team import Team
from five_hundred.player import Player
from five_hundred.card import Card, Suit, Rank # For player hand setup if needed

@pytest.fixture
def players_fixture():
    p1 = Player("Alice")
    p2 = Player("Bob")
    return [p1, p2]

@pytest.fixture
def team_fixture(players_fixture):
    return Team("Team Alpha", players_fixture)

def test_team_creation(team_fixture, players_fixture):
    """Test basic team creation."""
    team = team_fixture
    p1, p2 = players_fixture

    assert team.name == "Team Alpha"
    assert team.players == [p1, p2]
    assert team.team_score == 0
    assert not team.has_bid_this_round
    assert str(team) == "Team Alpha (Score: 0)"
    assert repr(team) == f"Team(Team Alpha, Players: [{p1.name}, {p2.name}], Score: 0)"

def test_team_creation_invalid_player_count():
    """Test team creation with invalid number of players."""
    p1 = Player("Solo")
    p_too_many1 = Player("Uno")
    p_too_many2 = Player("Dos")
    p_too_many3 = Player("Tres")

    with pytest.raises(ValueError, match="Team must consist of 1 or 2 players for standard 500."):
        Team("Empty Team", [])
    with pytest.raises(ValueError, match="Team must consist of 1 or 2 players for standard 500."):
        Team("Overfull Team", [p_too_many1, p_too_many2, p_too_many3])
    
    # Test valid creation with 1 player (might be useful for some variants or testing)
    try:
        team_single = Team("Solo Team", [p1])
        assert len(team_single.players) == 1
    except ValueError:
        pytest.fail("Team creation with 1 player should be allowed by current check.")

def test_team_update_score(team_fixture):
    """Test updating team score."""
    team = team_fixture
    team.update_score(150)
    assert team.team_score == 150
    team.update_score(-30)
    assert team.team_score == 120
    assert str(team) == "Team Alpha (Score: 120)"

def test_get_total_tricks_won(team_fixture, players_fixture):
    """Test calculating total tricks won by the team."""
    team = team_fixture
    p1, p2 = players_fixture

    assert team.get_total_tricks_won_this_round() == 0
    p1.increment_tricks_won()
    p1.increment_tricks_won()
    assert team.get_total_tricks_won_this_round() == 2
    p2.increment_tricks_won()
    assert team.get_total_tricks_won_this_round() == 3

def test_team_reset_for_new_round(team_fixture, players_fixture):
    """Test resetting team and player state for a new round."""
    team = team_fixture
    p1, p2 = players_fixture

    # Simulate a round
    team.update_score(100)
    team.has_bid_this_round = True
    p1.add_card_to_hand(Card(Suit.HEARTS, Rank.ACE)) # Give p1 a card
    p1.increment_tricks_won()
    p2.increment_tricks_won()

    team.reset_for_new_round()

    assert team.team_score == 100 # Score should persist
    assert not team.has_bid_this_round
    assert p1.tricks_won_this_round == 0
    assert p2.tricks_won_this_round == 0
    assert p1.hand == []
    assert p2.hand == []
    assert repr(team) == f"Team(Team Alpha, Players: [{p1.name}, {p2.name}], Score: 100)" 