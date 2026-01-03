import numpy as np
from .card import Card, Suit, Rank
from .bid import Bid, BidType
from typing import Dict, Any, Tuple, List, Optional

# --- Encoding Helpers ---
def card_to_int(card: Card) -> int:
    if card.rank == Rank.JOKER:
        return 52
    
    # Suits: Spades=0, Clubs=1, Diamonds=2, Hearts=3
    suit_map = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3}
    # Ranks: 4=0 ... Ace=10
    rank_idx = card.rank.value - 4
    return suit_map.get(card.suit, 0) * 13 + rank_idx

def int_to_card(idx: int) -> Optional[Card]:
    if idx == 52:
        return Card(Suit.NO_TRUMP, Rank.JOKER)
    
    if not (0 <= idx <= 51):
        return None
        
    suit_val = idx // 13
    rank_val = (idx % 13) + 4
    
    # Map back to enums
    suit_map_inv = {0: Suit.SPADES, 1: Suit.CLUBS, 2: Suit.DIAMONDS, 3: Suit.HEARTS}
    curr_suit = suit_map_inv.get(suit_val)
    curr_rank = Rank(rank_val) # Assuming Rank enum values match 4..14
    
    return Card(curr_suit, curr_rank)

def get_state_vector(obs: Dict) -> np.ndarray:
    # Size: 466 (458 original + 4 suit counts + 4 void flags)
    vec = np.zeros(466, dtype=np.float32)
    idx = 0
    
    # 1. Phase [Bid, Play]
    phase = obs.get('phase')
    if phase == 'BID': vec[idx] = 1
    elif phase == 'KITTY': vec[idx] = 1 # Treat as special/bid
    elif phase == 'PLAY': vec[idx+1] = 1
    idx += 2
    
    # 2. Hand (53)
    hand = obs.get('hand', [])
    for card in hand:
        c_idx = card_to_int(card)
        if 0 <= c_idx <= 52:
            vec[idx + c_idx] = 1
    idx += 53
    
    # 3. Trump (6: S, C, D, H, NT, None)
    trump = obs.get('trump_suit')
    # Map Suit to 0-3, NT to 4, None to 5
    t_idx = 5
    if trump:
        if trump == Suit.NO_TRUMP: t_idx = 4
        else: t_idx = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3}.get(trump, 5)
    vec[idx + t_idx] = 1
    idx += 6
    
    # 4. Trick History (Current Trick) - 4 slots * 53 cards
    current_trick = obs.get('current_trick', []) # List of (Player, Card)
    for i, (player, card) in enumerate(current_trick):
        if i >= 4: break
        c_int = card_to_int(card)
        vec[idx + (i * 53) + c_int] = 1
    idx += (4 * 53)
    
    # 6. History (Played Cards) - 53 slots
    played_history = obs.get('played_history', [])
    for card in played_history:
            c_idx = card_to_int(card)
            if 0 <= c_idx <= 52:
                vec[idx + c_idx] = 1
    idx += 53

    # 7. Scores (Normalized) - 3 slots (My, Opp, Delta)
    my_score = obs.get('my_score', 0)
    opp_score = obs.get('opp_score', 0)
    vec[idx] = my_score / 1000.0
    vec[idx+1] = opp_score / 1000.0
    vec[idx+2] = (my_score - opp_score) / 1000.0 # Explicit Delta
    idx += 3

    # 8. Winning Bid / Contract Info (15)
    winning_bid = obs.get('winning_bid_obj')
    if winning_bid:
        # Tricks (0 for Misere, 6-10 for standard)
        tr_idx = 0
        if winning_bid.tricks >= 6: tr_idx = winning_bid.tricks - 5 
        vec[idx + tr_idx] = 1
        idx += 6
        
        # Suit
        s_map = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3, Suit.NO_TRUMP: 4}
        s_idx = s_map.get(winning_bid.suit or (Suit.NO_TRUMP if winning_bid.bid_type != BidType.SUIT_TRUMP else None), 4)
        vec[idx + s_idx] = 1
        idx += 5
        
        # Bidder (Seat relative to agent)
        agent_seat = obs.get('agent_seat', 0)
        bidder_seat = obs.get('bidder_seat', 0)
        rel_seat = (bidder_seat - agent_seat) % 4
        vec[idx + rel_seat] = 1
        idx += 4
    else:
        idx += 15

    # 9. Current Tricks Won (2)
    tricks_my_team = obs.get('tricks_my_team', 0)
    tricks_opp_team = obs.get('tricks_opp_team', 0)
    vec[idx] = tricks_my_team / 10.0
    vec[idx+1] = tricks_opp_team / 10.0
    idx += 2

    # 10. Bidding History (Simplified) (112)
    bidding_history = obs.get('bidding_history_one_hot', {}) # {player_idx: bid_idx}
    for i in range(4):
        agent_seat = obs.get('agent_seat', 0)
        seat_idx = (agent_seat + i) % 4
        bid_idx = bidding_history.get(seat_idx)
        if bid_idx is not None:
            # 0=Pass, 1-25=Suits, 26=Misere, 27=OpenMisere
            vec[idx + bid_idx] = 1
        idx += 28
    
    # 11. Suit Counts (4 floats - normalized to [0,1]) - NEW 
    # Critical for void detection and bidding strategy
    hand = obs.get('hand', [])
    suit_counts = {Suit.SPADES: 0, Suit.CLUBS: 0, Suit.DIAMONDS: 0, Suit.HEARTS: 0}
    for card in hand:
        if card.suit in suit_counts:
            suit_counts[card.suit] += 1
    
    vec[idx] = suit_counts[Suit.SPADES] / 13.0
    vec[idx+1] = suit_counts[Suit.CLUBS] / 13.0
    vec[idx+2] = suit_counts[Suit.DIAMONDS] / 13.0
    vec[idx+3] = suit_counts[Suit.HEARTS] / 13.0
    idx += 4
    
    # 12. Void Indicators (4 binary flags) - NEW
    # Explicit void signals for faster learning
    vec[idx] = 1.0 if suit_counts[Suit.SPADES] == 0 else 0.0
    vec[idx+1] = 1.0 if suit_counts[Suit.CLUBS] == 0 else 0.0
    vec[idx+2] = 1.0 if suit_counts[Suit.DIAMONDS] == 0 else 0.0
    vec[idx+3] = 1.0 if suit_counts[Suit.HEARTS] == 0 else 0.0
    idx += 4

    return vec

def decode_action(action_idx: int, phase: str) -> Any:
    # EXCLUDE MISERE logic handled in MASKING, not here.
    
    if phase == 'BID':
        if action_idx == 0:
            return ("pass", None)
            
        # Map 1..25 to 6S..10NT
        if 1 <= action_idx <= 25:
            adjusted_idx = action_idx - 1
            tricks = 6 + (adjusted_idx // 5)
            suit_idx = adjusted_idx % 5
            
            # Order: Spades, Clubs, Diamonds, Hearts, No Trump
            suits = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, None]
            chosen_suit = suits[suit_idx]
            
            if chosen_suit is None:
                return ("bid", (tricks, Suit.NO_TRUMP, BidType.NO_TRUMP))
            else:
                return ("bid", (tricks, chosen_suit, BidType.SUIT_TRUMP))
        
        # Misere / Open Misere
        elif action_idx == 26:
            return ("bid", (0, None, BidType.MISERE))
        elif action_idx == 27:
            return ("bid", (0, None, BidType.OPEN_MISERE))
            
        return ("pass", None)
        
    elif phase == 'PLAY' or phase == 'KITTY':
        return int_to_card(action_idx)
        
    return ("pass", None)
