import pytest
import numpy as np
import queue
from five_hundred.env import FiveHundredEnv
from five_hundred.rl_player import RLPlayer
from five_hundred.card import Card, Suit, Rank
from five_hundred.game import Game
from unittest.mock import MagicMock

def test_mask_playback_consistency():
    """
    Simulates the exact loop of Observation -> Mask -> Action -> RLPlayer Execution
    to check for valid move rejection.
    """
    # Setup
    action_queue = queue.Queue()
    obs_queue = queue.Queue()
    player = RLPlayer("TestAgent", action_queue, obs_queue)
    env = FiveHundredEnv(verbose=False)
    
    # Create a scenario
    # Hand: [AS, KC, QD]
    # Playable: [QD] (Must follow Diamonds?)
    hand = [
        Card(Suit.SPADES, Rank.ACE), # Index 0
        Card(Suit.CLUBS, Rank.KING), # Index 1
        Card(Suit.DIAMONDS, Rank.QUEEN) # Index 2
    ]
    playable = [Card(Suit.DIAMONDS, Rank.QUEEN)] # Only QD valid
    
    player.hand = list(hand) # Copy
    
    # 1. Player generates Observation (mocking decide_play_card internal logic)
    obs = {
        'phase': 'PLAY',
        'hand': player.hand,
        'playable_cards': playable,
        'trick_suit': Suit.DIAMONDS,
        'trump_suit': None,
        'current_trick': []
    }
    
    # 2. Env processes Observation and generates Mask
    # Note: env._get_action_mask uses obs
    env.last_phase = 'PLAY'
    mask = env._get_action_mask(obs)
    
    # Calculate expected ID for QD
    qd_id = env._card_to_int(playable[0])
    print(f"QD ID: {qd_id}")
    
    # Expectation: Only Index `qd_id` should be 1.
    assert mask[qd_id] == 1, "QD should be valid"
    assert np.sum(mask) == 1, "Only 1 card should be valid"
    
    # 3. Agent chooses valid action
    action_idx = qd_id
    decoded_action = env._decode_action(action_idx) # Should be Card(QD)
    assert isinstance(decoded_action, Card)
    assert decoded_action == playable[0]
    
    # 4. Env sends action to player
    
    # 5. RLPlayer (logic from decide_play_card) validates action
    # New Logic: Checks if decoded_action (Card) is in playable
    chosen_card = decoded_action
    
    final_card = None
    if isinstance(chosen_card, Card):
        if chosen_card in playable:
            final_card = chosen_card
        else:
            print(f"FAIL: Card {chosen_card} not in playable")
             
    # Assert
    assert final_card == playable[0], f"Expected QD, got {final_card}"
    
    print("\nSUCCESS: Logic matches for simple case.")

def test_mask_consistency_with_sorting():
    """
    Tests if sorting the hand IN PLACE affects the logic while obs is pending?
    This is the tricky race condition hypothesis.
    """
    action_queue = queue.Queue()
    obs_queue = queue.Queue()
    player = RLPlayer("TestAgent", action_queue, obs_queue)
    env = FiveHundredEnv(verbose=False)
    
    # Hand unordered: [QD, AS, KC]
    hand = [
        Card(Suit.DIAMONDS, Rank.QUEEN), # Playable
        Card(Suit.SPADES, Rank.ACE), 
        Card(Suit.CLUBS, Rank.KING) 
    ]
    playable = [Card(Suit.DIAMONDS, Rank.QUEEN)]
    player.hand = list(hand)
    
    # Obs generated
    obs = {
        'phase': 'PLAY',
        'hand': player.hand, # Reference!
        'playable_cards': playable
    }
    
    # Env calculates mask based on IDs
    env.last_phase = 'PLAY' # CRITICAL FIX
    mask = env._get_action_mask(obs)
    
    qd_id = env._card_to_int(playable[0])
    assert mask[qd_id] == 1
    
    # HYPOTHETICAL DISASTER:
    # Player sorts hand *after* obs sent
    player.hand.sort() 
    print(f"Sorted Hand: {player.hand}")
    
    # Agent picks valid action ID (Global ID for QD)
    action_idx = qd_id
    
    # Player receives Card object from Env
    decoded_card = env._decode_action(action_idx)
    
    # Player checks validity
    is_valid = decoded_card in playable
    
    print(f"Action {action_idx} (Card {decoded_card}). Playable? {is_valid}")
    
    assert is_valid, "Sorting SHOULD NOT break VALIDITY now!"

if __name__ == "__main__":
    test_mask_playback_consistency()
    test_mask_consistency_with_sorting() 
