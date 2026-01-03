
import json
import numpy as np
import os
from five_hundred.vectorized_env import GameEnvWrapper
from five_hundred.utils_rl import get_state_vector
from five_hundred.card import Suit, Rank, Card
from five_hundred.bid import BidType, Bid
from five_hundred.player import Player
from five_hundred.bot_player import BotPlayer
from enum import Enum

class NumpyEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.integer):
            return int(obj)
        if isinstance(obj, np.floating):
            return float(obj)
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, Enum):
            return obj.name
        if isinstance(obj, Bid):
            return bid_to_dict(obj)
        if isinstance(obj, (Player, BotPlayer)):
            return obj.name
        if isinstance(obj, Card):
            return card_to_str(obj)
        try:
            return super(NumpyEncoder, self).default(obj)
        except TypeError:
            return str(obj)

def card_to_str(card):
    # Map Card object to string like "AH", "TD", "Joker"
    if card.rank.name == 'JOKER': return "Joker"
    r_map = {'FOUR': '4', 'FIVE': '5', 'SIX': '6', 'SEVEN': '7', 'EIGHT': '8', 
             'NINE': '9', 'TEN': 'T', 'JACK': 'J', 'QUEEN': 'Q', 'KING': 'K', 'ACE': 'A'}
    s_map = {'SPADES': 'S', 'CLUBS': 'C', 'DIAMONDS': 'D', 'HEARTS': 'H'}
    return f"{r_map[card.rank.name]}{s_map[card.suit.name]}"

def bid_to_dict(bid):
    if not bid: return None
    
    # Handle String Pass (Python Game implementation uses strings for passes sometimes)
    if isinstance(bid, str) and "passes" in bid:
        # "Name passes"
        name = bid.replace(" passes", "").strip()
        return {"type": "PASS", "player": name}
        
    # Map Bid object to dictionary
    # Assuming bid has structure or is string 'PASS'
    if hasattr(bid, 'bid_type'):
         name = bid.bid_type.name
         if name == 'PASS': return {"type": "PASS", "player": bid.player.name if bid.player else "?"}
         return {
            "tricks": bid.tricks,
            "suit": bid.suit.name if bid.suit else None,
            "type": name,
            "player": bid.player.name
         }
    return None

def parse_card_str(s):
    # s is "Nine of Hearts" or "Joker"
    if s == "Joker": return "Joker"
    parts = s.split(' of ')
    if len(parts) != 2: return s # Fallback
    r_name = parts[0].upper()
    s_name = parts[1].upper()
    
    # Map back to 2-char
    r_map = {'FOUR': '4', 'FIVE': '5', 'SIX': '6', 'SEVEN': '7', 'EIGHT': '8', 
             'NINE': '9', 'TEN': 'T', 'JACK': 'J', 'QUEEN': 'Q', 'KING': 'K', 'ACE': 'A'}
    s_map = {'SPADES': 'S', 'CLUBS': 'C', 'DIAMONDS': 'D', 'HEARTS': 'H'}
    
    return f"{r_map.get(r_name, '?')}{s_map.get(s_name, '?')}"

def main():
    print("Generating Golden Data...")
    # ... (rest of main)
    # Inside ticks_history loop:
    # "cards": [{"card": parse_card_str(c_str), "player": p_name} for p_name, c_str in t['cards']]

    
    # Init Env
    env = GameEnvWrapper()
    env.reset()
    
    # We want to capture states in different phases (BID, PLAY)
    # So we'll step through a game randomly and capture snapshots
    
    snapshots = []
    
    # Force some actions to create history
    # 1. BID PHASE
    # Agent is Player 0.
    # We step until it's agent's turn.
    
    # The Loop
    for _ in range(50): # 50 steps should be enough to get deep into a game
        # Get Obs
        try:
             obs = env._get_obs()
        except:
             # Fallback if _get_obs() isn't exposed or needs args
             # Env might use utils_rl directly
             from five_hundred.utils_rl import build_observation, get_state_vector
             # We need 'phase'
             phase = env._get_phase()
             obs_dict = build_observation(env.game, 0, phase=phase) # Agent is 0
             obs = get_state_vector(obs_dict)
             
        game = env.game
        
        # Capture Snapshot
        snapshot = {
            "phase": env._get_phase(),
            "my_idx": 0, # Agent is always P0
            "hands": [[card_to_str(c) for c in p.hand] for p in game.players],
            "tricks_won": [p.tricks_won_this_round for p in game.players], # Add this
            "dealer_idx": game.current_dealer_idx, # 0-3
            "current_player": game.active_player_index,
            "trump": game.trump_suit.name if game.trump_suit else None,
            "bids_history": [bid_to_dict(b) for b in game.bids_this_round], 
            "tricks_history": [
                {
                    "cards": [{"card": parse_card_str(c_str), "player": p_name} for p_name, c_str in t['cards']]
                }
                for t in game.finished_tricks
            ],
            "cards_played": [card_to_str(c) for c in game.cards_played_this_round], # Flat list source of truth
            "current_trick": [{"card": card_to_str(c), "player": game.players.index(p)} for p, c in game.current_trick_cards],
            "scores": [t.team_score for t in game.teams],
            "winning_bid": bid_to_dict(game.winning_bid) if game.winning_bid else None,
            
            # THE GOLDEN VECTOR
            "expected_vector": obs.tolist() if isinstance(obs, np.ndarray) else obs
        }
        
        # Add tricks history logic if needed
        # (Skipping complex trick history serialization for now, but will need it for perfect parity)
        
        snapshots.append(snapshot)
        
        # Step Randomly
        phase = env._get_phase()
        mask = env._get_legal_mask(phase)
        legal_indices = np.where(mask == 1)[0]
        if len(legal_indices) == 0: break
        
        action = np.random.choice(legal_indices)
        _, _, done, _ = env.step(action)
        
        if done: env.reset()

    # Save
    os.makedirs("five_hundred_love/tests", exist_ok=True)
    with open("five_hundred_love/tests/golden_data.json", "w") as f:
        json.dump(snapshots, f, indent=2, cls=NumpyEncoder)
        
    print(f"Saved {len(snapshots)} snapshots to golden_data.json")

if __name__ == "__main__":
    main()
