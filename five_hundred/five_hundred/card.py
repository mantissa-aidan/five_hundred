import enum

class Suit(enum.Enum):
    SPADES = "Spades"
    CLUBS = "Clubs"
    DIAMONDS = "Diamonds"
    HEARTS = "Hearts"
    NO_TRUMP = "No Trump" # For Joker and representing no-trump game state

class Rank(enum.Enum):
    FOUR = "4"
    FIVE = "5"
    SIX = "6"
    SEVEN = "7"
    EIGHT = "8"
    NINE = "9"
    TEN = "10"
    JACK = "Jack"
    QUEEN = "Queen"
    KING = "King"
    ACE = "Ace"
    JOKER = "Joker"

class Card:
    def __init__(self, suit: Suit, rank: Rank):
        if rank == Rank.JOKER and suit != Suit.NO_TRUMP:
            raise ValueError("Joker must have suit NO_TRUMP")
        if rank != Rank.JOKER and suit == Suit.NO_TRUMP:
            raise ValueError("Only Joker can have suit NO_TRUMP")

        self.suit = suit
        self.rank = rank

    def __repr__(self):
        if self.rank == Rank.JOKER:
            return "Joker"
        return f"{self.rank.value} of {self.suit.value}"

    def __eq__(self, other):
        if not isinstance(other, Card):
            return NotImplemented
        return self.suit == other.suit and self.rank == other.rank

    def __hash__(self):
        # Required for putting cards in sets or using as dict keys
        return hash((self.suit, self.rank)) 