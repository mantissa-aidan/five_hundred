import random
from typing import List
from .card import Card, Suit, Rank

class Deck:
    def __init__(self):
        self.cards: List[Card] = []
        self.create_deck()

    def create_deck(self):
        """Creates a standard 43-card deck for 500."""
        self.cards = []
        all_suits = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS]
        # Ranks from 5 to Ace for all suits
        value_ranks = [
            Rank.FIVE, Rank.SIX, Rank.SEVEN, Rank.EIGHT, Rank.NINE,
            Rank.TEN, Rank.JACK, Rank.QUEEN, Rank.KING, Rank.ACE
        ]
        for suit_val in all_suits:
            for rank_val in value_ranks:
                self.cards.append(Card(suit_val, rank_val)) # 40 cards

        # Add the two 4s that are kept.
        # Wikipedia: "Either the two black 4s are removed, or the 4 of spades and 4 of diamonds are removed..."
        # This means two 4s of the same color are kept (e.g. red 4s or black 4s).
        # Let's keep the 4 of Hearts and 4 of Diamonds (red 4s).
        self.cards.append(Card(Suit.HEARTS, Rank.FOUR))
        self.cards.append(Card(Suit.DIAMONDS, Rank.FOUR))
        # Add the Joker
        self.cards.append(Card(Suit.NO_TRUMP, Rank.JOKER))
        # Total: 40 (5-A) + 2 (4s) + 1 (Joker) = 43 cards.

    def shuffle(self):
        """Shuffles the cards in the deck."""
        random.shuffle(self.cards)

    def deal(self, num_cards: int) -> List[Card]:
        """Deals a specified number of cards from the top of the deck."""
        if num_cards < 0:
            raise ValueError("Number of cards to deal cannot be negative.")
        if num_cards > len(self.cards):
            raise ValueError("Not enough cards in deck to deal.")
        
        dealt_cards = self.cards[:num_cards]
        self.cards = self.cards[num_cards:]
        return dealt_cards

    def __len__(self):
        return len(self.cards)

    def __repr__(self):
        return f"Deck({len(self.cards)} cards)"
 