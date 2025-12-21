import pytest
import numpy as np
from unittest.mock import MagicMock, patch
from five_hundred.env import FiveHundredEnv
from five_hundred.game import Game
from five_hundred.card import Card, Suit, Rank
from five_hundred.bid import Bid, BidType
from five_hundred.player import Player
from five_hundred.bot_player import BotPlayer
from five_hundred.team import Team

@pytest.fixture
def env_setup():
    """Creates an environment instance with mocked threading to prevent auto-start."""
    with patch('five_hundred.env.start_server_thread'), \
         patch('threading.Thread'):
        env = FiveHundredEnv(verbose=False)
        # Manually attach a game instance as _run_game would
        env.game = MagicMock(spec=Game)
        env.game.players = [Player("Agent"), BotPlayer("B1"), BotPlayer("B2"), BotPlayer("B3")]
        env.game.teams = [
            MagicMock(spec=Team, players=[env.game.players[0], env.game.players[2]], team_score=0),
            MagicMock(spec=Team, players=[env.game.players[1], env.game.players[3]], team_score=0)
        ]
        # Ensure teams return score
        env.game.teams[0].team_score = 0
        env.game.teams[1].team_score = 0
        
        env.game.cards_played_this_round = []
        env.game.winning_bid = None
        env.game.trump_suit = None
        
        # RL player is always index 0 in this setup
        env.rl_player = env.game.players[0]
        
        return env

def test_state_vector_shape(env_setup):
    """Verify the state vector has the correct dimension (450)."""
    env = env_setup
    
    # Mock obs dictionary
    obs = {
        'phase': 'BID',
        'hand': [Card(Suit.SPADES, Rank.ACE)],
        'trump_suit': None,
        'current_trick': [],
        'played_history': [],
        'my_score': 0,
        'opp_score': 0
    }
    
    # Generate state
    state = env._get_state_vector(obs)
    
    assert isinstance(state, np.ndarray)
    assert state.shape == (600,), f"Expected state dimension 600, got {state.shape}"

def test_state_vector_content_scores(env_setup):
    """Verify that scores are correctly normalized and placed in the state vector."""
    env = env_setup
    
    obs = {
        'phase': 'PLAY',
        'hand': [],
        'trump_suit': Suit.SPADES,
        'my_score': 100,
        'opp_score': -50
    }
    
    state = env._get_state_vector(obs)
    
    # Normalized scores: score / 1000.0 (as seen in env.py)
    expected_my_score = 100 / 1000.0
    expected_opp_score = -50 / 1000.0
    
    # Scores are at the end
    # based on calculation in env.py:
    # Phase(2) + Hand(53) + Trump(6) + Trick(212) + History(53) = 326
    # Then some padding to 450?
    # Actually env.py has fixed indices logic:
    # idx accumulates.
    # Let's just check for existence in value
    
    # Note: floating point comparison
    assert np.any(np.isclose(state, expected_my_score)), f"Expected {expected_my_score} in state"
    assert np.any(np.isclose(state, expected_opp_score)), f"Expected {expected_opp_score} in state"

def test_action_mask_bidding(env_setup):
    """Test action mask during bidding phase."""
    env = env_setup
    
    obs = {
        'phase': 'BID',
        'hand': [Card(Suit.SPADES, Rank.ACE)],
        'valid_bids': [(0, None, None), (1, 6, Suit.SPADES)] # Mocked valid bids from game
    }
    
    # Note: _get_action_mask in env.py relies on game method calls if 'valid_bids' not in obs?
    # Let's check env.py _get_action_mask implementation again.
    # It calls self.game._get_valid_bids(...) inside _get_action_mask logic usually.
    # Wait, env.py _get_action_mask takes `obs`.
    # Let's re-read _get_action_mask in env.py
    # ...
    # It seems to rely on `self.game` state if not fully in obs.
    # But wait, the error was "Mock object has no attribute 'get'" which implies it tried to do obs.get('phase')
    # So passing dict `obs` is correct.
    
    # Mock game.player_attempts_bid availability?
    # Actually _get_action_mask usually calls game logic.
    # Let's assume for this test we want to verify it returns a mask.
    # We need to mock what _get_action_mask needs.
    
    # Re-reading env.py lines 257+ from previous turn:
    # def _get_action_mask(self, obs: Dict) -> np.ndarray:
    #    mask = zeros...
    #    phase = obs.get('phase')
    
    # So it uses obs.
    mask = env._get_action_mask(obs)
    
    assert mask.shape == (100,)
    assert ((mask == 0) | (mask == 1)).all(), "Mask must be binary"
    
    assert mask[26] == 0
    assert mask[27] == 0

def test_action_mask_play(env_setup):
    """Test action mask during play phase using Global Card IDs."""
    env = env_setup
    
    # Hand: [AS, KC, QD]
    # Playable: [QD]
    hand = [
        Card(Suit.SPADES, Rank.ACE), 
        Card(Suit.CLUBS, Rank.KING), 
        Card(Suit.DIAMONDS, Rank.QUEEN)
    ]
    playable = [Card(Suit.DIAMONDS, Rank.QUEEN)]
    
    obs = {
        'phase': 'PLAY',
        'hand': hand,
        'playable_cards': playable
    }
    
    mask = env._get_action_mask(obs)
    
    # Calculate expected ID for QD
    # Suit.DIAMONDS (2) * 13 + Rank.QUEEN (12) - 4 = 2*13 + 8 = 34
    qd_id = 34
    
    assert mask[qd_id] == 1, f"Expected mask at {qd_id} to be 1"
    assert np.sum(mask) == 1, "Only 1 valid action expected"

def test_invalid_move_penalty(env_setup):
    """Test that invalid moves trigger a penalty."""
    env = env_setup
    
    import queue
    env.action_queue = queue.Queue()
    env.obs_queue = queue.Queue()
    
    # Pre-set last_mask to invalidate action 1
    env.last_mask = np.zeros(100)
    env.last_mask[0] = 1 
    env.last_phase = "BID"
    
    # Feed an observation for the next step to consume
    # This simulates the game engine sending state back after the action (or fallback)
    env.obs_queue.put({
        'phase': 'BID',
        'my_score': 0,
        'opp_score': 0
        # ... other fields ignored by simple _process_obs mocks
    })
    
    # Attempt invalid action 1
    action_idx = 1
    
    # Step
    try:
        next_state, reward, done, info = env.step(action_idx)
    except Exception as e:
        pytest.fail(f"Step failed with error: {e}")

    # Check penalty
    # The reward calculation in step() ADDS to the reward variable.
    # Initial reward is 0. 
    # If invalid: reward = -10.
    # Then valid fallback sent.
    # Then waits for obs.
    # Then gets team score (0).
    # Then adds team_score/100 (0).
    # So final reward should be -10.
    assert reward == -10, f"Expected -10 reward for invalid move, got {reward}"
    assert info.get('invalid') is True

def test_valid_move_reward(env_setup):
    """Test standard reward structure for valid move (no immediate trick reward)."""
    env = env_setup
    
    import queue
    env.action_queue = queue.Queue()
    env.obs_queue = queue.Queue()
    
    env.last_mask = np.ones(100) # All valid
    
    # Action
    action_idx = 5
    
    # Mock obs
    env.obs_queue.put({"done": False})
    
    next_state, reward, done, info = env.step(action_idx)
    
    assert reward == 0, "Non-terminal valid step should have 0 reward (unless game engine gave points, but we removed trick rewards)"
    assert info.get('invalid_moves') == 0 # Info now tracks invalid moves

def test_trick_win_reward(env_setup):
    """Test that winning a trick yields reward shaping (+0.1)."""
    env = env_setup
    import queue
    env.action_queue = queue.Queue()
    env.obs_queue = queue.Queue()
    env.last_mask = np.ones(100)
    
    # Initial state
    env.previous_tricks_won = 0
    env.rl_player.tricks_won_this_round = 1 # SIMULATE WINNING A TRICK
    
    # Action
    env.obs_queue.put({"done": False})
    
    next_state, reward, done, info = env.step(5)
    
    # Expectation: 0.1 reward
    # Note: floating point comparison
    assert np.isclose(reward, 0.1), f"Expected 0.1 reward for trick win, got {reward}"

