from typing import List, Optional
from .card import Card, Suit, Rank

def calculate_hand_strength(hand: List[Card], trump_suit: Optional[Suit] = None, is_misere: bool = False) -> float:
    """
    Calculates a heuristic strength score for a hand.
    Higher score means better hand (more likely to win tricks), unless is_misere is True.
    """
    score = 0.0
    
    if is_misere:
        # For Misere, we want low cards. High cards are bad.
        # Simple heuristic: sum of ranks (where Joker is huge). Lower is better.
        # We can return negated sum, so higher 'strength' still means better for the objective.
        for card in hand:
            if card.rank == Rank.JOKER:
                score -= 50 # Terrible for misere
            elif card.rank.value >= Rank.EIGHT.value: # 8 and up are risky
                score -= (card.rank.value - 7) * 2 # Penalty scales with height
            elif card.rank.value <= Rank.SEVEN.value:
                score += 5 # Good low card
        return score

    # Standard / No Trump logic
    for card in hand:
        # Joker is always good
        if card.rank == Rank.JOKER:
            score += 25 if trump_suit else 15 # More valuable in trump (trump control) than NT? Or same.
            continue
        
        # Check for Bowers if trump is set
        is_trump = False
        is_right_bower = False
        is_left_bower = False
        
        if trump_suit and trump_suit != Suit.NO_TRUMP:
            if card.suit == trump_suit:
                is_trump = True
                if card.rank == Rank.JACK:
                    is_right_bower = True
            
            # Left Bower check
            left_bower_suit = None
            if trump_suit == Suit.SPADES: left_bower_suit = Suit.CLUBS
            elif trump_suit == Suit.CLUBS: left_bower_suit = Suit.SPADES
            elif trump_suit == Suit.DIAMONDS: left_bower_suit = Suit.HEARTS
            elif trump_suit == Suit.HEARTS: left_bower_suit = Suit.DIAMONDS
            
            if card.suit == left_bower_suit and card.rank == Rank.JACK:
                is_left_bower = True
                is_trump = True # Functionally a trump

        if is_right_bower:
            score += 20
        elif is_left_bower:
            score += 15
        elif is_trump:
            # Trump values
            if card.rank == Rank.ACE: score += 10
            elif card.rank == Rank.KING: score += 7
            elif card.rank == Rank.QUEEN: score += 5
            elif card.rank == Rank.JACK: score += 3 # Regular Jack if missed bower check logic? No, Right Bower caught.
            elif card.rank == Rank.TEN: score += 2
            else: score += 1 # Low trump value
        else:
            # Side suits (or NT)
            if card.rank == Rank.ACE: score += 4
            elif card.rank == Rank.KING: score += 3
            elif card.rank == Rank.QUEEN: score += 2
            elif card.rank == Rank.JACK: score += 1
            # 10s and lower worth minimal unless it's a long suit (not handling distribution yet)

    return score

def get_effective_suit(card: Card, trump_suit: Optional[Suit]) -> Suit:
    """Returns the effective suit of a card, accounting for Joker and Bowers."""
    if card.rank == Rank.JOKER:
        return trump_suit if trump_suit else Suit.NO_TRUMP 
    
    if trump_suit and trump_suit != Suit.NO_TRUMP:
        if card.suit == trump_suit:
            return trump_suit
        
        # Left Bower Check
        left_bower_suit = None
        if trump_suit == Suit.SPADES: left_bower_suit = Suit.CLUBS
        elif trump_suit == Suit.CLUBS: left_bower_suit = Suit.SPADES
        elif trump_suit == Suit.DIAMONDS: left_bower_suit = Suit.HEARTS
        elif trump_suit == Suit.HEARTS: left_bower_suit = Suit.DIAMONDS
        
        if card.suit == left_bower_suit and card.rank == Rank.JACK:
            return trump_suit
            
    return card.suit

def get_card_play_value(card: Card, lead_suit: Suit, trump_suit: Optional[Suit]) -> int:
    """Returns a numerical value for comparing cards in a trick."""
    eff_suit = get_effective_suit(card, trump_suit)
    
    # 1. Trumps
    if trump_suit and eff_suit == trump_suit:
        if card.rank == Rank.JOKER: return 2000 
        if card.rank == Rank.JACK and card.suit == trump_suit: return 1500 # RB
        if card.rank == Rank.JACK and card.suit != trump_suit: return 1400 # LB
        return 1000 + card.rank.value
        
    # 2. Lead Suit
    if eff_suit == lead_suit:
        return 100 + card.rank.value
        
    # 3. Off Suit
    return card.rank.value 

def determine_trick_winner_index(trick_cards: List[Card], trump_suit: Optional[Suit]) -> int:
    """Returns the index of the winning card in the list."""
    if not trick_cards: return -1
        
    lead_suit = get_effective_suit(trick_cards[0], trump_suit)
    best_idx = 0
    best_val = get_card_play_value(trick_cards[0], lead_suit, trump_suit)
    
    for i in range(1, len(trick_cards)):
        val = get_card_play_value(trick_cards[i], lead_suit, trump_suit)
        if val > best_val:
            best_val = val
            best_idx = i
            
    return best_idx
