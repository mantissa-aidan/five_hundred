from .player import Player
from .card import Card, Suit
from .bid import Bid, BidType
from .agent import PyTorchAgent
from typing import List, Optional, Tuple, Dict, Any
import torch

class InferencePlayer(Player):
    def __init__(self, name: str, checkpoint_path: str, action_dim=100, state_dim=600):
        super().__init__(name)
        self.agent = PyTorchAgent(state_dim=state_dim, action_dim=action_dim)
        try:
            self.agent.load(checkpoint_path)
            print(f"InferencePlayer {name} loaded model {checkpoint_path}")
        except Exception as e:
            print(f"Error loading model for {name}: {e}. Random weights will be used.")
            
        self.agent.epsilon = 0.0 # Greedy inference
        self.agent.bid_net.eval()
        self.agent.play_net.eval()

    def get_observation(self, phase, extra_data=None):
        # We need an ENV instance to encode state? 
        # Or we replicate encoding logic? Replicating is safer to avoid coupling with Threaded Env.
        # Actually, let's just make a DummyEnv wrapper or static method in Env.
        # Ideally, we pass the Game logic's state to a helper in Env.
        # For now, let's assume we can import the encoding logic.
        from .env import FiveHundredEnv
        
        # Construct raw obs dictionary
        obs = {'phase': phase, 'hand': self.hand}
        if extra_data:
            obs.update(extra_data)
            
        # We need a stateless way to encode.
        # FiveHundredEnv methods are instance methods but mostly pure.
        # Let's hack it: Create a temporary env or refactor Env to have static helpers.
        # Refactoring is best but risky. Let's instantiate a lightweight Env for encoding.
        if not hasattr(self, '_encoder_env'):
            self._encoder_env = FiveHundredEnv(verbose=False)
            
        # Manually set Env state from Obs if needed?
        # Env._get_state_vector reads from obs dict primarily.
        # But it reads 'played_history', 'scores' etc from self.game.
        # InferencePlayer is IN a game.
        # So we can direct the encoder env to look at OUR game?
        
        # Better approach:
        # Pass the current Game object to the encoder.
        # self._encoder_env.game = self.game (Wait, Player doesn't hold ref to Game usually, Game holds Player)
        # We don't have easy access to Game global state here unless passed in args.
        pass

    # ... Wait, Player methods receive game context args! 
    # decide_bid(self, current_highest_bid, bids_this_round, ...)
    
    def decide_bid(self, current_highest_bid: Optional[Bid], bids_this_round: List[Bid], player_has_bid_this_round: dict, player_has_passed_auction: dict) -> Tuple[str, Optional[Tuple]]:
        print(f"DEBUG: InferencePlayer {self.name} deciding bid...")
        from .env import FiveHundredEnv
        if not hasattr(self, 'env'): self.env = FiveHundredEnv(verbose=False, start_server=False)
        
        # Mock Observation
        obs = {
            'phase': 'BID',
            'hand': self.hand,
            'trump_suit': None, # Unknown in bid phase
            'winning_bid': current_highest_bid,
            # We need history/score context which arguments don't fully provide...
            # This is a limitation of the current Player API.
            # However, for 'The Arena', we can allow global access or simplified state.
        }
        
        # To get a valid state vector, we need:
        # Phase (Got it)
        # Hand (Got it)
        # Trump (None)
        # Contract (None)
        # Trick (None)
        # History (Cards played? None in Bid)
        # Scores? We don't have scores in arguments!
        
        # Just use what we have.
        state_vec = self.env._get_state_vector(obs)
        
        # Masking?
        # We need a mask for bidding. 
        # Env._get_action_mask handles this but needs 'hand' and 'phase'.
        # And 'last_bid' context.
        # We can reconstruct a minimal mask manually or use env.
        
        # But wait, Env._get_action_mask logic for BID is complex (valid bids > current).
        # We should use the helper.
        mask = self.env._get_action_mask(obs)
        
        # Action
        action_idx = self.agent.act(state_vec, 'BID', mask)
        
        # Decode
        action_pair = self.env._decode_action(action_idx)
        return action_pair

    def decide_kitty_exchange(self, kitty: List[Card], winning_bid: Bid) -> List[Card]:
        # Bot hand has 13 cards.
        obs = {
            'phase': 'KITTY',
            'hand': self.hand, # 13 cards
            'winning_bid': winning_bid,
            'kitty_original': kitty
        }
        
        # No easy way to encode 'KITTY' state in current Env (it just passes).
        # We fallback to greedy heuristic or random for kitty?
        # The RL agent was trained to see 'KITTY' as mostly 'BID' phase in encoding?
        # Env._get_state_vector maps KITTY to BID phase vector.
        
        # This part is tricky. Let's just discard lowest 3 cards using Heuristic for now
        # to ensure the "Clone" plays somewhat sanely given the RL might be weak here.
        # OR: We use the RL agent if it was trained on KITTY.
        # My previous checks showed KITTY support in Env was weak/fallback.
        # SAFE BET: Use Heuristic for Kitty.
        
        from .bot_player import BotPlayer
        # Create temp bot
        bp = BotPlayer("temp")
        bp.hand = self.hand
        return bp.decide_kitty_exchange(kitty, winning_bid)

    def decide_play_card(self, playable_cards: List[Card], trick_suit: Optional[Suit], trump_suit: Optional[Suit], current_trick_cards: List[Tuple[Any, Card]]) -> Card:
        from .env import FiveHundredEnv
        if not hasattr(self, 'env'): self.env = FiveHundredEnv(verbose=False, start_server=False)
        
        obs = {
            'phase': 'PLAY',
            'hand': self.hand, # Current hand
            'playable_cards': playable_cards,
            'trick_suit': trick_suit,
            'trump_suit': trump_suit,
            'current_trick': current_trick_cards,
            # Missing: Score, History
            # We will zerofill them for inference.
        }
        
        state_vec = self.env._get_state_vector(obs)
        mask = self.env._get_action_mask(obs)
        
        action_idx = self.agent.act(state_vec, 'PLAY', mask)
        
        # Decode: action_idx IS card_idx in Global Deck (0..52)
        # We must find the card in playable_cards that matches.
        
        target_card = self.env._int_to_card(action_idx)
        
        # Find exact card instance in playable to return
        for c in playable_cards:
            if c.suit == target_card.suit and c.rank == target_card.rank:
                return c
                
        # Fallback if invalid
        # print(f"InferencePlayer chosen invalid: {target_card}, Playable: {playable_cards}")
        return playable_cards[0]
