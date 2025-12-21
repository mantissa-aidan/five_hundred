import pytest
import numpy as np
from unittest.mock import MagicMock, patch
from five_hundred.env import FiveHundredEnv
from five_hundred.card import Card, Suit, Rank
from five_hundred.bid import Bid, BidType
from five_hundred.player import Player
from five_hundred.team import Team

@pytest.fixture
def env_setup():
    with patch('five_hundred.env.start_server_thread'), \
         patch('threading.Thread'):
        env = FiveHundredEnv(verbose=False, start_server=False)
        env.game = MagicMock(spec=env.game)
        p1 = Player("Agent")
        p2 = Player("Bot1")
        p3 = Player("Bot2")
        p4 = Player("Bot3")
        env.game.players = [p1, p2, p3, p4]
        env.game.teams = [
            Team("Team 1", [p1, p3]),
            Team("Team 2", [p2, p4])
        ]
        env.game.cards_played_this_round = []
        env.game.winning_bid = None
        env.game.trump_suit = None
        env.game.bids_this_round = []
        return env

def test_expanded_obs_content(env_setup):
    env = env_setup
    
    # Setup a complex state
    # 1. Winning Bid: 7 Spades by Partner (Seat 2)
    winning_bid = Bid(env.game.players[2], 7, Suit.SPADES, BidType.SUIT_TRUMP)
    env.game.winning_bid = winning_bid
    env.game.trump_suit = Suit.SPADES
    
    # 2. Tricks won: 3 for my team, 2 for enemy
    env.game.players[0].increment_tricks_won()
    env.game.players[0].increment_tricks_won()
    env.game.players[2].increment_tricks_won() # My team total 3
    env.game.players[1].increment_tricks_won()
    env.game.players[3].increment_tricks_won() # Enemy team total 2
    
    # 3. Bidding history: Agent passed, Bot1 bid 6C, Partner bid 7S, Bot3 passed
    env.game.bids_this_round = [
        "Agent passes",
        Bid(env.game.players[1], 6, Suit.CLUBS, BidType.SUIT_TRUMP),
        winning_bid,
        "Bot3 passes"
    ]
    
    # Process Obs
    raw_obs = {'phase': 'PLAY', 'hand': []}
    state = env._process_obs(raw_obs)
    
    # Check Contract Info (starts at 329)
    # Tricks: 7 - 5 = 2. So index 329 + 2 = 331 should be 1
    assert state[331] == 1, "Tricks needed (7) should be at index 331"
    
    # Suit: Spades is 0. So index 335 + 0 = 335 should be 1
    assert state[335] == 1, "Suit (Spades) should be at index 335"
    
    # Bidder: Seat 2 - Seat 0 = rel 2. So index 340 + 2 = 342 should be 1
    assert state[342] == 1, "Bidder (Partner) should be at index 342"
    
    # Check Tricks Won (starts at 344)
    assert state[344] == pytest.approx(0.3), f"My team tricks (3) should be 0.3, got {state[344]}"
    assert state[345] == pytest.approx(0.2), f"Enemy team tricks (2) should be 0.2, got {state[345]}"
    
    # Check Bidding History (starts at 346)
    # Seat 0 (Agent): Pass (0). Index 346 + 0 = 346 should be 1
    assert state[346] == 1, "Agent Pass should be at 346"
    
    # Seat 1 (Bot1): 6 Clubs. 
    # 6C code = 1 + (0*5) + 1 = 2. Index 346 + 28 + 2 = 376 should be 1
    assert state[376] == 1, "Bot1 6C should be at 376"
    
    # Seat 2 (Partner): 7 Spades.
    # 7S code = 1 + (1*5) + 0 = 6. Index 346 + 56 + 6 = 408 should be 1
    assert state[408] == 1, "Partner 7S should be at 408"
    
    # Seat 3 (Bot3): Pass (0). Index 346 + 84 + 0 = 430 should be 1
    assert state[430] == 1, "Bot3 Pass should be at 430"

if __name__ == "__main__":
    pytest.main([__file__])
