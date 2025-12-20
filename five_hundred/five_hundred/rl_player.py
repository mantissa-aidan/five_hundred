from .bot_player import BotPlayer
from .card import Card, Suit
from .bid import Bid, BidType
from typing import List, Optional, Tuple, Dict, Any
import queue

class RLPlayer(BotPlayer):
    def __init__(self, name: str, action_queue: queue.Queue, observation_queue: queue.Queue):
        super().__init__(name, difficulty="RL")
        self.action_queue = action_queue
        self.observation_queue = observation_queue

    def _get_action(self, observation: Dict[str, Any]) -> Any:
        """Sends observation to env and waits for action."""
        self.observation_queue.put(observation)
        return self.action_queue.get(block=True)

    def decide_bid(self, current_highest_bid: Optional[Bid], bids_this_round: List[Bid], player_has_bid_this_round: dict, player_has_passed_auction: dict) -> Tuple[str, Optional[Tuple]]:
        
        # Serialize state for RL
        # Note: In a full implementation, we'd convert this to tensors here or in the env.
        # Sending raw objects for now to let Env handle encoding.
        obs = {
            'phase': 'BID',
            'hand': self.hand,
            'current_highest_bid': current_highest_bid,
            'bids_this_round': bids_this_round,
            'my_bid_history': player_has_bid_this_round.get(self, False),
            'has_passed': player_has_passed_auction.get(self, False)
        }
        
        action_data = self._get_action(obs)
        # action_data expected format: ('bid', (tricks, suit, type)) or ('pass', None)
        return action_data

    def decide_kitty_exchange(self, kitty: List[Card], winning_bid: Bid) -> List[Card]:
        # Bot hand already has kitty at this point (13 cards)
        obs = {
            'phase': 'KITTY',
            'hand': self.hand, # 13 cards
            'winning_bid': winning_bid,
            'kitty_original': kitty
        }
        
        # Expect action to be list of 3 cards to discard
        discards = self._get_action(obs)
        return discards

    def decide_play_card(self, playable_cards: List[Card], trick_suit: Optional[Suit], trump_suit: Optional[Suit], current_trick_cards: List[Tuple[Any, Card]]) -> Card:
        
        obs = {
            'phase': 'PLAY',
            'hand': self.hand,
            'playable_cards': playable_cards,
            'trick_suit': trick_suit,
            'trump_suit': trump_suit,
            'current_trick': current_trick_cards
        }
        
        # Expect action to be the Card object to play OR index in playable_cards
        chosen_card = self._get_action(obs)
        
        if isinstance(chosen_card, int):
            return playable_cards[chosen_card]
        return chosen_card
