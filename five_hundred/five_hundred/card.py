import enum

class Suit(enum.Enum):
    CLUBS = 0
    DIAMONDS = 1
    HEARTS = 2
    SPADES = 3
    NO_TRUMP = 4 # For Joker and representing no-trump game state

class Rank(enum.Enum):
    FOUR = 4
    FIVE = 5
    SIX = 6
    SEVEN = 7
    EIGHT = 8
    NINE = 9
    TEN = 10
    JACK = 11
    QUEEN = 12
    KING = 13
    ACE = 14
    JOKER = 100 # High value for sorting purposes

class Card:
    def __init__(self, suit: Suit, rank: Rank):
        if not isinstance(suit, Suit):
            raise TypeError("suit must be an instance of Suit enum")
        if not isinstance(rank, Rank):
            raise TypeError("rank must be an instance of Rank enum")
        
        if rank == Rank.JOKER:
            if suit != Suit.NO_TRUMP:
                suit = Suit.NO_TRUMP # Auto-correct for Joker
        elif suit == Suit.NO_TRUMP: # Non-Joker cannot have NO_TRUMP suit
            raise ValueError("NO_TRUMP suit is reserved for Joker only.")

        self.suit = suit
        self.rank = rank

    def is_joker(self) -> bool:
        """Returns True if the card is a Joker."""
        return self.rank == Rank.JOKER

    def __str__(self):
        if self.rank == Rank.JOKER:
            return "Joker"
        # Using .name for Rank and Suit to get the string representation
        return f"{self.rank.name.replace('_', ' ').title()} of {self.suit.name.title()}"

    def __repr__(self):
        if self.rank == Rank.JOKER:
            return "Card(Suit.NO_TRUMP, Rank.JOKER)" # Canonical representation for Joker
        return f"Card(Suit.{self.suit.name}, Rank.{self.rank.name})"

    def __eq__(self, other):
        if isinstance(other, Card):
            return self.suit == other.suit and self.rank == other.rank
        return False

    def __hash__(self):
        return hash((self.suit, self.rank))

    def __lt__(self, other): # For sorting
        if not isinstance(other, Card):
            return NotImplemented
        # Sort by suit value first, then by rank value for consistent ordering
        return (self.suit.value, self.rank.value) < (other.suit.value, other.rank.value) 