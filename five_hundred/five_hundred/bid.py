from enum import Enum, auto
from typing import Optional
from .card import Suit # Assuming Suit enum is in card.py
# from .player import Player # Circular import risk, consider passing player object or ID

class BidType(Enum):
    SUIT_TRUMP = "Suit Trump"
    NO_TRUMP = "No Trump"
    MISERE = "Misere"
    OPEN_MISERE = "Open Misere"

# Defines the hierarchy of suits for bidding and scoring.
# Lower index = lower precedence for bidding, lower score for same trick count.
# No_Trump is highest for standard bids.
# Misere bids have fixed scores and specific places in the bidding hierarchy.

#Loved her, married her, killed her, buried her
SUIT_BID_ORDER = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP]

# Points table for successful bids (tricks won >= bid tricks)
# Format: (tricks, suit_index) -> points
# Suit_index corresponds to SUIT_BID_ORDER
# This is based on the "Avondale" scoring. Other tables exist.
AVONDALE_POINTS_TABLE = {
    # (Tricks, Suit_Spades, Suit_Clubs, Suit_Diamonds, Suit_Hearts, No_Trump)
    6:  (40,  60,  80,  100, 120),
    7:  (140, 160, 180, 200, 220),
    8:  (240, 260, 280, 300, 320),
    9:  (340, 360, 380, 400, 420),
    10: (440, 460, 480, 500, 520),
}
MISERE_POINTS = 250
OPEN_MISERE_POINTS = 500 # Can also be 330 or other values based on variation

class Bid:
    def __init__(self, player, tricks: int, suit: Optional[Suit], bid_type: BidType):
        self.player = player
        self.tricks: int = tricks
        self.suit: Optional[Suit] = suit
        self.bid_type: BidType = bid_type

        # Perform validation checks before calculating points
        if not (0 <= self.tricks <= 10): # Tricks 0 for Misere
            raise ValueError("Tricks must be between 0 and 10.")

        if self.bid_type == BidType.SUIT_TRUMP:
            if self.suit is None or self.suit == Suit.NO_TRUMP:
                raise ValueError("Suit must be specified and cannot be No Trump for a SUIT_TRUMP bid.")
            if not (6 <= self.tricks <= 10):
                 raise ValueError("Suit/No-Trump bids must be for 6-10 tricks.")
        elif self.bid_type == BidType.NO_TRUMP:
            if not (6 <= self.tricks <= 10):
                 raise ValueError("Suit/No-Trump bids must be for 6-10 tricks.")
            # self.suit will be None or Suit.NO_TRUMP as passed by user, can be canonicalized later if needed
        elif self.bid_type in [BidType.MISERE, BidType.OPEN_MISERE]:
            if self.tricks != 0:
                raise ValueError("Misere bids must be for 0 tricks.")
            # self.suit is typically None for Misere, or can be forced to NO_TRUMP
            self.suit = Suit.NO_TRUMP # Canonicalize for Misere type bids

        self.points: int = self._calculate_points()

    def _calculate_points(self) -> int:
        if self.bid_type == BidType.MISERE:
            return MISERE_POINTS
        if self.bid_type == BidType.OPEN_MISERE:
            return OPEN_MISERE_POINTS
        
        if self.bid_type == BidType.SUIT_TRUMP and self.suit is not None and self.suit != Suit.NO_TRUMP:
            if self.tricks not in AVONDALE_POINTS_TABLE:
                raise ValueError(f"Invalid number of tricks for bidding: {self.tricks}")
            try:
                suit_idx = SUIT_BID_ORDER.index(self.suit)
                return AVONDALE_POINTS_TABLE[self.tricks][suit_idx]
            except (ValueError, IndexError):
                raise ValueError(f"Invalid suit for bidding: {self.suit}")
        elif self.bid_type == BidType.NO_TRUMP:
            if self.tricks not in AVONDALE_POINTS_TABLE:
                raise ValueError(f"Invalid number of tricks for NT bidding: {self.tricks}")
            try:
                suit_idx = SUIT_BID_ORDER.index(Suit.NO_TRUMP) # Last index for No Trump
                return AVONDALE_POINTS_TABLE[self.tricks][suit_idx]
            except IndexError:
                 raise ValueError("Error calculating No Trump points.") # Should not happen
        raise ValueError(f"Unknown bid type or parameters for point calculation: {self.bid_type}, {self.suit}")

    def get_bidding_rank(self) -> int:
        """Calculates a rank for the bid to determine precedence. Higher is better."""
        # This defines the order: 6S < 6C < ... < 6NT < Misere < 7S ... < Open Misere < 10NT etc.
        # Exact placement of Misere/Open Misere can vary. Wikipedia: Misere (250pts) between 8S and 8C.
        # Open Misere (500pts) between 10D and 10H.
        # For Avondale, typical hierarchy might be by points.
        # A common alternative system for ranking bids:
        # 1. Number of tricks (higher is better)
        # 2. Suit (Hearts > Diamonds > Clubs > Spades, NT highest for same trick count)
        # 3. Special bids (Misere, Open Misere) inserted at specific point values.
        
        # Using points directly for ranking is simplest if points are unique and ordered.
        # Avondale table ensures this for standard bids.
        # Misere (250): after 8S (240) and before 8C (260)
        # Open Misere (500): after 10H (500) or sometimes 10D (480) and before 10NT (520)
        # Let's ensure our points for Misere/Open Misere fit this logic.
        # Our Misere points (250) fit. Our Open Misere (500) fits.
        return self.points

    def __gt__(self, other: 'Bid') -> bool:
        """Compare this bid to another bid to see if this one is greater."""
        if not isinstance(other, Bid):
            return NotImplemented
        # Higher points mean a higher bid.
        # If points are equal, the first bid of that value wins (not handled here, but in game logic)
        return self.get_bidding_rank() > other.get_bidding_rank()

    def __lt__(self, other: 'Bid') -> bool:
        return other > self

    def __ge__(self, other: 'Bid') -> bool:
        return self > other or self == other

    def __le__(self, other: 'Bid') -> bool:
        return self < other or self == other

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Bid):
            return NotImplemented
        return (self.player == other.player and 
                self.tricks == other.tricks and 
                self.suit == other.suit and 
                self.bid_type == other.bid_type and
                self.points == other.points)

    def __repr__(self) -> str:
        if self.bid_type == BidType.MISERE:
            return f"Bid(Player: {self.player.name}, Misere, Points: {self.points})"
        if self.bid_type == BidType.OPEN_MISERE:
            return f"Bid(Player: {self.player.name}, Open Misere, Points: {self.points})"
        
        suit_display_name = "No Trump" # Default for NO_TRUMP type or if suit is NO_TRUMP
        if self.bid_type == BidType.SUIT_TRUMP and self.suit is not None and self.suit != Suit.NO_TRUMP:
            suit_display_name = self.suit.name.title() # Get 'Spades', 'Hearts', etc.
            
        return f"Bid(Player: {self.player.name}, Tricks: {self.tricks}, Suit: {suit_display_name}, Type: {self.bid_type.value}, Points: {self.points})"

    def __str__(self) -> str:
        if self.bid_type == BidType.MISERE:
            return f"{self.player.name} bids Misere ({self.points} pts)"
        if self.bid_type == BidType.OPEN_MISERE:
            return f"{self.player.name} bids Open Misere ({self.points} pts)"

        suit_display_name = "No Trump" # Default for NO_TRUMP type or if suit is NO_TRUMP
        if self.bid_type == BidType.SUIT_TRUMP and self.suit is not None and self.suit != Suit.NO_TRUMP:
            suit_display_name = self.suit.name.title() # Get 'Spades', 'Hearts', etc.
            
        return f"{self.player.name} bids {self.tricks} {suit_display_name} ({self.points} pts)" 