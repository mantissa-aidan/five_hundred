from .player import Player
from .card import Card, Suit, Rank
from .bid import Bid, BidType
from typing import List, Optional, Tuple, Dict, Any
import requests
import json
import time

# Global Queue for inter-thread communication
# The Server thread puts actions here, Player thread reads them.
CMD_QUEUE = None 

def set_cmd_queue(q):
    global CMD_QUEUE
    CMD_QUEUE = q

class WebHumanPlayer(Player):
    def __init__(self, name: str):
        super().__init__(name)
        
    def _wait_for_input(self, context_type, data, error=None):
        from .play_game_server import set_human_pending_action # forward ref
        set_human_pending_action(context_type, data, error=error)
        
        if error:
            print(f"Human Input Requested (RETRY due to Error: {error}): {context_type}")
        else:
            print(f"Human Input Requested: {context_type}")
        
        # 2. Block until command received
        if CMD_QUEUE:
            cmd = CMD_QUEUE.get(block=True)
            # cmd is expected to be the Result (e.g. Bid object, Card object)
            set_human_pending_action(None, None) # Clear
            return cmd
        return None

    def decide_bid(self, current_highest_bid: Optional[Bid], bids_this_round: List[Bid], **kwargs) -> Tuple[str, Optional[Tuple]]:
        data = {
            'hand': [str(c) for c in self.hand],
            'current_bid': str(current_highest_bid) if current_highest_bid else "None",
            'history': [str(b) for b in bids_this_round]
        }
        
        # Block
        response = self._wait_for_input('BID', data)
        # Response: {'action': 'pass'} or {'action': 'bid', 'tricks': 7, 'suit': 'HEARTS'}
        
        if response.get('action') == 'pass':
            return ("pass", None)
        else:
            t = int(response['tricks'])
            # Parse Suit
            s_str = response['suit']
            if s_str == 'NT' or s_str == 'NO_TRUMP':
                suit = None
                b_type = BidType.NO_TRUMP
            else:
                suit = Suit[s_str] # SPADES, etc
                b_type = BidType.SUIT_TRUMP
                
            return ("bid", (t, suit, b_type))

    def decide_kitty_exchange(self, kitty: List[Card], winning_bid: Bid) -> List[Card]:
        # Sort hand with the winning trump suit
        self.sort_hand(winning_bid.suit)
        
        data = {
            'hand': [str(c) for c in self.hand], # 13 cards
            'kitty': [str(c) for c in kitty]
        }
        
        response = self._wait_for_input('KITTY', data)
        
        indices = response['indices']
        discards = []
        for i in indices:
            discards.append(self.hand[int(i)])
            
        return discards

    def decide_play_card(self, playable_cards: List[Card], trick_suit: Optional[Suit], trump_suit: Optional[Suit], current_trick_cards: List[Tuple[Any, Card]]) -> Card:
        # Sort hand to match UI always
        self.sort_hand(trump_suit)
        
        data = {
            'hand': [str(c) for c in self.hand],
            'playable': [str(c) for c in playable_cards],
            'trick': [str(c) for _, c in current_trick_cards]
        }
        
        error_msg = None
        while True:
            response = self._wait_for_input('PLAY', data, error=error_msg)
            
            # The UI should send 'card_index' which is index into self.hand
            if 'card_index' in response:
                hand_idx = int(response['card_index'])
                
                if 0 <= hand_idx < len(self.hand):
                    chosen_card = self.hand[hand_idx]
                    
                    if chosen_card in playable_cards:
                        return chosen_card
                    else:
                        # Card is in hand, but not playable (e.g. wrong suit)
                        if trick_suit:
                            error_msg = f"Invalid move: You must follow suit ({trick_suit.name}) if possible."
                        else:
                            error_msg = "Invalid move: You cannot play that card now."
                else:
                    error_msg = "Invalid card selection."
            else:
                error_msg = "No card selected."

    def sort_hand(self, trump_suit: Optional[Suit] = None, game_suit_order: Optional[List[Suit]] = None):
        """Sorts the hand for the UI, grouping Bowers and Joker with the Trump suit."""
        # Standard Suit Priority: HEARTS, DIAMONDS, CLUBS, SPADES
        suit_prio = {Suit.HEARTS: 0, Suit.DIAMONDS: 1, Suit.CLUBS: 2, Suit.SPADES: 3, Suit.NO_TRUMP: 4}
        
        # Left Bower Suit Helper
        left_bower_suit = None
        if trump_suit == Suit.SPADES: left_bower_suit = Suit.CLUBS
        elif trump_suit == Suit.CLUBS: left_bower_suit = Suit.SPADES
        elif trump_suit == Suit.DIAMONDS: left_bower_suit = Suit.HEARTS
        elif trump_suit == Suit.HEARTS: left_bower_suit = Suit.DIAMONDS

        def sort_key(card: Card):
            # Special ranks for Trump/Bowers/Joker
            effective_suit = card.suit
            effective_rank = card.rank.value
            
            # Joker is highest trump
            if card.rank == Rank.JOKER:
                effective_suit = trump_suit if trump_suit and trump_suit != Suit.NO_TRUMP else Suit.NO_TRUMP
                effective_rank = 1000 # Highest
            # Right Bower
            elif trump_suit and card.rank == Rank.JACK and card.suit == trump_suit:
                effective_suit = trump_suit
                effective_rank = 900
            # Left Bower
            elif trump_suit and card.rank == Rank.JACK and card.suit == left_bower_suit:
                effective_suit = trump_suit
                effective_rank = 800
            # Regular Trump
            elif trump_suit and card.suit == trump_suit:
                effective_rank += 100 # Ensure Ace of Trump (114) is above Ace of others (14)
            
            p = suit_prio.get(effective_suit, 99)
            return (p, -effective_rank)
            
        self.hand.sort(key=sort_key)
