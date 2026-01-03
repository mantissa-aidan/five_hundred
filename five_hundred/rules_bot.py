from .player import Player
from .card import Card, Suit, Rank
from .bid import Bid, BidType
from .heuristic import calculate_hand_strength, get_effective_suit, get_card_play_value, determine_trick_winner_index
from typing import List, Optional, Tuple, Dict

class RulesBot(Player):
    """
    A deterministic, rules-based bot for generating pre-training data.
    Uses heuristics for bidding and sensible rules for card play.
    """
    def __init__(self, name: str, difficulty: str = "medium"):
        super().__init__(name)
        self.difficulty = difficulty

    def decide_bid(self, current_highest_bid: Optional[Bid], bids_this_round: List[Bid], player_has_bid_this_round: dict, player_has_passed_auction: dict) -> Tuple[str, Optional[Tuple]]:
        """
        Decides bid based on refined heuristic (Suit Length + High Cards).
        User Strategy:
        - Suit Bid: >5 cards of suit, >=2 high cards (J,Q,K,A,Joker). 
          Bid = NumCards + 1 (Kitty) + 1 (Partner) - 6? No, bid level starts at 6.
          Actually user said: "bid the number cards I hold plus one in the kity and one in the kitty and one from my partner".
          Interpreted as: Tricks = Count(Suit) + 1 (Kitty) + 1 (Partner average contribution).
          So if I have 5 Spades, I expect 5+1+1 = 7 tricks. Bid 7 Spades.
        - NT Bid: Needs 5 "face cards" (High cards). 
          Bid logic same? (Count + ?). Usually implies strong hand.
        """
        best_bid_tuple = None
        max_tricks = 0
        
        # Helper for "High Scoring Card" check (J, Q, K, A, Joker, Right/Left Bower)
        def count_high_cards(hand, trump=None):
            count = 0
            for card in hand:
                if card.rank == Rank.JOKER: count += 1
                elif card.rank in [Rank.ACE, Rank.KING, Rank.QUEEN, Rank.JACK]: count += 1
                # Note: Right/Left Bower handled by rank check (Jack is counted)
            return count

        # 1. Suit Bids
        for suit in [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS]:
            # Count cards of this suit (including Joker as trump)
            suit_cards = [c for c in self.hand if get_effective_suit(c, suit) == suit]
            count = len(suit_cards)
            
            # Check High Cards (in hand, but relevant to this suit/general strength)
            high_count = count_high_cards(self.hand, suit)
            
            # User Rule: >5 cards (meaning >=6?) or "more than 5" usually means >=6. 
            # But "5 cards of one suit" is often standard minimum. Let's assume >=5.
            # "At least two are high scoring cards"
            
            tricks = 0
            if count >= 5 and high_count >= 2:
                # "Bid number cards I hold + 1 (kitty) + 1 (partner)"
                predicted_tricks = count + 1 + 1
                tricks = min(10, predicted_tricks) 
            
            # Fallback to points-based heuristic if this rule doesn't trigger 
            # (e.g. strong hand but only 4 trumps)
            else:
                strength = calculate_hand_strength(self.hand, trump_suit=suit)
                if strength >= 35: tricks = 7 # Conservative fallback
                elif strength >= 24: tricks = 6
                
            if tricks > max_tricks:
                max_tricks = tricks
                best_bid_tuple = (tricks, suit, BidType.SUIT_TRUMP)

        # 2. No Trump Bid
        # "Need 5 face cards"
        high_cards_any = count_high_cards(self.hand, None)
        if high_cards_any >= 5:
            # Strong NT hand.
            # Tricks? Maybe simplified: 7NT usually with that strength.
            # Or use points:
            nt_strength = calculate_hand_strength(self.hand, trump_suit=None)
            nt_tricks = 0
            if nt_strength >= 60: nt_tricks = 8
            elif nt_strength >= 45: nt_tricks = 7
            elif nt_strength >= 35: nt_tricks = 6
            
            # Prefer NT if tricks >= max_suit_tricks
            if nt_tricks >= max_tricks and nt_tricks > 0:
                 best_bid_tuple = (nt_tricks, None, BidType.NO_TRUMP)
                 
        # 3. Misere (Keep existing logic as simplified fallback)
        misere_strength = calculate_hand_strength(self.hand, is_misere=True)
        if misere_strength > 45 and (not current_highest_bid or current_highest_bid.tricks < 8):
             best_bid_tuple = (0, None, BidType.MISERE)

        # 4. Validity Check
        if best_bid_tuple:
            tricks, suit, b_type = best_bid_tuple
            potential_score = self._get_bid_score(tricks, suit, b_type)
            if current_highest_bid:
                current_score = self._get_bid_score(current_highest_bid.tricks, current_highest_bid.suit, current_highest_bid.bid_type)
            else:
                current_score = 0
            
            if potential_score > current_score:
                return ("bid", best_bid_tuple)

        return ("pass", None)

    def _get_bid_score(self, tricks, suit, b_type):
        if b_type == BidType.MISERE: return 250
        if b_type == BidType.OPEN_MISERE: return 500
        
        base_scores = {6: 0, 7: 100, 8: 200, 9: 300, 10: 400}
        suit_scores = {Suit.SPADES: 40, Suit.CLUBS: 60, Suit.DIAMONDS: 80, Suit.HEARTS: 100, Suit.NO_TRUMP: 120}
        
        if suit is None and b_type == BidType.NO_TRUMP: s_score = 120
        else: s_score = suit_scores.get(suit, 0)
        
        return base_scores.get(tricks, 0) + s_score

    def decide_kitty_exchange(self, kitty: List[Card], winning_bid: Bid) -> List[Card]:
        """Discard weakest cards."""
        self.sort_hand(trump_suit=winning_bid.suit if winning_bid else None)
        
        trump = winning_bid.suit if winning_bid else None
        
        # Improved Context-Aware Discard:
        # Avoid discarding singletons of off-suits (unless necessary) to keep optionality?
        # Actually in 500, voiding a suit is GOOD (can trump it).
        # So we SHOULD discard all cards of a weak suit if possible.
        
        to_discard = []
        temp_hand = list(self.hand)
        
        # Value tuple: (is_trump_related, suit_length, card_value)
        # We want to discard: Non-trump, Short suits (to void), Low value.
        
        suit_counts = {}
        for c in temp_hand:
            s_eff = get_effective_suit(c, trump)
            suit_counts[s_eff] = suit_counts.get(s_eff, 0) + 1
            
        candidates = []
        for c in temp_hand:
            eff_suit = get_effective_suit(c, trump)
            is_trump = (eff_suit == trump) if trump else False
            val = get_card_play_value(c, eff_suit, trump)
            s_len = suit_counts.get(eff_suit, 0)
            
            # Priority Score (Lower = Dump First)
            # 1. Non-Trump Low Cards in Short Suits (Void strategy)
            # 2. Non-Trump Low Cards
            # 3. Trump Low Cards
            
            score = val # Base value is 4-14
            if is_trump: score += 1000
            
            # Bonus for keeping long suits (length > 4)? 
            # Or bonus for discarding from Short suits to create void (Length <= 2)?
            if not is_trump and s_len <= 2:
                score -= 50 # Encourage flushing these
                
            candidates.append((c, score))
            
        candidates.sort(key=lambda x: x[1])
        
        for i in range(3):
            to_discard.append(candidates[i][0])
            
        return to_discard

    def decide_play_card(self, playable_cards: List[Card], trick_suit: Optional[Suit], trump_suit: Optional[Suit], current_trick_cards: List[Tuple[Player, Card]]) -> Card:
        """
        Sensible card play logic.
        """
        if not playable_cards: return None
        if len(playable_cards) == 1: return playable_cards[0]

        # 1. Leading
        if not current_trick_cards:
            return self._decide_lead(playable_cards, trump_suit)
            
        # 2. Following
        return self._decide_follow(playable_cards, trick_suit, trump_suit, current_trick_cards)

    def _decide_lead(self, playable: List[Card], trump: Optional[Suit]) -> Card:
        # Lead Boss Trumps if possible to draw out opponents' trumps
        high_trumps = []
        for c in playable:
            eff = get_effective_suit(c, trump)
            if eff == trump:
                if c.rank in [Rank.JOKER, Rank.JACK, Rank.ACE, Rank.KING, Rank.QUEEN]:
                    high_trumps.append(c)
        
        if high_trumps:
            high_trumps.sort(key=lambda c: get_card_play_value(c, trump, trump), reverse=True)
            return high_trumps[0]
            
        # Otherwise lead best non-trump
        playable.sort(key=lambda c: get_card_play_value(c, get_effective_suit(c, trump), trump), reverse=True)
        return playable[0]

    def _decide_follow(self, playable: List[Card], trick_suit: Suit, trump: Optional[Suit], history: List[Tuple[Player, Card]]) -> Card:
        cards_played = [c for p, c in history]
        winning_idx = determine_trick_winner_index(cards_played, trump)
        winning_card = cards_played[winning_idx]
        winning_player = history[winning_idx][0]
        
        is_partner_winning = False
        if hasattr(self, 'game_ref') and self.game_ref:
            try:
                my_team = None
                for t in self.game_ref.teams:
                     if self in t.players: my_team = t; break
                if my_team and winning_player in my_team.players: is_partner_winning = True
            except: pass

        current_best_val = get_card_play_value(winning_card, trick_suit, trump)
        
        # Categorize
        winning_candidates = []
        losing_candidates = []
        
        for c in playable:
            val = get_card_play_value(c, trick_suit, trump)
            if val > current_best_val:
                winning_candidates.append((c, val))
            else:
                losing_candidates.append((c, val))
                
        winning_candidates.sort(key=lambda x: x[1])
        losing_candidates.sort(key=lambda x: x[1])
        
        if is_partner_winning:
            # Partner winning. Play lowest loser.
            if losing_candidates:
                return losing_candidates[0][0]
            else:
                return winning_candidates[0][0] # Must overtake
                
        else:
            # Opponent winning. Try to win.
            if winning_candidates:
                return winning_candidates[0][0] # Lowest winner
            
            # Can't win normally.
            # User Rule: "Rules based bot should also deterministically know how to play a trump card on a trick it is losing."
            # This happens when I am void in trick_suit (so I can play any card), and I have trumps.
            # `playable_cards` already filters for legality (must follow suit). 
            # If I'm here in `else` (opponent winning) and `winning_candidates` is empty, it means either:
            # a) I have suit but my cards are lower.
            # b) I don't have suit, but I don't have trumps or trumps lower than current winner (if current winner is trump).
            
            # Check if I am void in trick_suit (implicitly true if I play a trump when trick_suit != trump)
            # `winning_candidates` handled the case where my Trump > Current Best.
            # So if I'm here, I can't beat the current card.
            # BUT: Maybe I can trump if the current winner is NOT a trump?
            # Wait, get_card_play_value handles trump power. 
            # If current_best_val is a Trump(1000+), and I have a lower Trump, I can't win.
            # If current_best_val is Non-Trump(100+), and I have ANY trump, my trump val > current_best_val.
            # So `winning_candidates` logic ALREADY covers "play a trump to win".
            
            # Is there a nuance? "Deterministically know how to play a trump".
            # Maybe previously it wasn't aggressive enough?
            # My current logic: `if winning_candidates: return winning_candidates[0][0]`
            # This selects the CHEAPEST card that WINS. 
            # If a low trump wins (2 of Spades vs Ace of Diamonds), it will pick it.
            # This seems correct per user request.
            
            # Fallback: Play lowest loser (save good cards).
            if losing_candidates:
                return losing_candidates[0][0]
                
        return playable[0]
