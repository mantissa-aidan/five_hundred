import pytest
from unittest.mock import patch, call # Import call for checking print calls
import io # For capturing stdout

from five_hundred.game import Game
from five_hundred.player import Player
from five_hundred.card import Suit, Rank, Card
from five_hundred.bid import BidType

PLAYER_NAMES = ["CLI_P1", "CLI_P2", "CLI_P3", "CLI_P4"]
TEAM_NAMES = ["CLI_T1/3", "CLI_T2/4"]

@pytest.fixture
def game_for_cli():
    """Provides a Game instance for CLI testing, without starting a round immediately."""
    # We might not want to deal cards immediately if we are testing specific input phases.
    game = Game(PLAYER_NAMES, TEAM_NAMES)
    # game._deal_cards() # Deal cards manually in tests if needed for context
    return game

# --- Test Bidding CLI --- #

def test_cli_bid_action_invalid_then_pass(game_for_cli, capsys):
    game = game_for_cli
    player = game.players[0]
    game.current_bidder_idx = 0 # Set P1 as current bidder

    # Simulate player hand for context (can be simplified as it's not directly used by pass)
    player.hand = [Card(Suit.SPADES, Rank.ACE)] 

    # Inputs: 
    # 1. Invalid action ("gibberish")
    # 2. Valid action ("pass") when prompted again for action
    inputs_invalid_then_pass = [
        "gibberish", # Player enters invalid text at action prompt
        "pass"       # Player then enters "pass" at the re-prompted action prompt
    ]

    with patch('builtins.input', side_effect=inputs_invalid_then_pass):
        action_type, action_params = game._get_player_bid_action(player)
    
    captured = capsys.readouterr()

    assert action_type == "pass"
    assert action_params is None

    # Check for expected prompts and error messages in captured.out
    # print(captured.out) # Uncomment to debug output
    # The input() prompt itself doesn't go to stdout. We check for the game's response.
    assert "Invalid action. Please enter 'bid' or 'pass'." in captured.out # Error for "gibberish"
    # We can also check that the initial turn message was printed:
    assert f"{player.name}'s turn to bid." in captured.out

# More CLI tests to come for kitty exchange, card play, etc. 