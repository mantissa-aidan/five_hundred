import pytest
from five_hundred.deck import Deck
from five_hundred.card import Card, Suit, Rank # For checking specific cards

def test_deck_creation():
    """Test that a new deck has 43 unique cards."""
    deck = Deck()
    assert len(deck.cards) == 43
    assert len(set(deck.cards)) == 43 # Check for uniqueness

    # Spot check a few cards
    assert Card(Suit.NO_TRUMP, Rank.JOKER) in deck.cards
    assert Card(Suit.HEARTS, Rank.ACE) in deck.cards
    assert Card(Suit.SPADES, Rank.FIVE) in deck.cards
    assert Card(Suit.DIAMONDS, Rank.FOUR) in deck.cards # One of the kept 4s
    assert Card(Suit.HEARTS, Rank.FOUR) in deck.cards # The other kept 4

    # Check that removed 4s are not present
    assert Card(Suit.SPADES, Rank.FOUR) not in deck.cards
    assert Card(Suit.CLUBS, Rank.FOUR) not in deck.cards

def test_deck_shuffle():
    """Test that shuffling changes the order of cards."""
    deck1 = Deck()
    deck2 = Deck()
    
    original_order = list(deck1.cards) # Take a copy
    deck1.shuffle()
    shuffled_order = deck1.cards

    # It's highly improbable that shuffle results in the exact same order for a 43 card deck.
    # Or that it matches another unshuffled deck.
    assert shuffled_order != original_order
    assert shuffled_order != deck2.cards # deck2 is unshuffled here.

    # Ensure all original cards are still present after shuffle
    assert len(shuffled_order) == 43
    assert set(shuffled_order) == set(original_order)

def test_deck_deal():
    """Test dealing cards from the deck."""
    deck = Deck()
    initial_deck_size = len(deck)

    # Deal 10 cards (a player's hand)
    hand_size = 10
    hand = deck.deal(hand_size)
    assert len(hand) == hand_size
    assert len(deck.cards) == initial_deck_size - hand_size

    # Deal 3 cards (the kitty)
    kitty_size = 3
    kitty = deck.deal(kitty_size)
    assert len(kitty) == kitty_size
    assert len(deck.cards) == initial_deck_size - hand_size - kitty_size

    # Check that dealt cards are unique and were removed from deck
    all_dealt_cards = hand + kitty
    assert len(set(all_dealt_cards)) == hand_size + kitty_size
    for card in all_dealt_cards:
        assert card not in deck.cards

def test_deal_too_many_cards():
    """Test dealing more cards than are in the deck."""
    deck = Deck()
    with pytest.raises(ValueError, match="Not enough cards in deck to deal."):
        deck.deal(len(deck.cards) + 1)

def test_deal_all_cards():
    """Test dealing all cards from the deck."""
    deck = Deck()
    all_cards = deck.deal(len(deck.cards))
    assert len(all_cards) == 43
    assert len(deck.cards) == 0

def test_deal_negative_cards():
    """Test dealing a negative number of cards."""
    deck = Deck()
    with pytest.raises(ValueError, match="Number of cards to deal cannot be negative."):
        deck.deal(-1)

def test_deck_representation():
    """Test the string representation of the deck."""
    deck = Deck()
    assert repr(deck) == "Deck(43 cards)"
    deck.deal(10)
    assert repr(deck) == "Deck(33 cards)" 