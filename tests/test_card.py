import pytest
from five_hundred.card import Card, Suit, Rank

def test_card_creation():
    """Test creation of a standard card."""
    card = Card(Suit.SPADES, Rank.ACE)
    assert card.suit == Suit.SPADES
    assert card.rank == Rank.ACE
    assert str(card) == "Ace of Spades"
    assert repr(card) == "Card(Suit.SPADES, Rank.ACE)"

def test_joker_creation():
    """Test creation of a Joker card."""
    # Joker should automatically get NO_TRUMP suit
    joker = Card(Suit.NO_TRUMP, Rank.JOKER) 
    assert joker.suit == Suit.NO_TRUMP
    assert joker.rank == Rank.JOKER
    assert str(joker) == "Joker"
    assert repr(joker) == "Card(Suit.NO_TRUMP, Rank.JOKER)"

    # Test auto-correction for Joker if a different suit is provided
    joker_autocorrected = Card(Suit.HEARTS, Rank.JOKER)
    assert joker_autocorrected.suit == Suit.NO_TRUMP
    assert joker_autocorrected.rank == Rank.JOKER
    assert str(joker_autocorrected) == "Joker"
    assert repr(joker_autocorrected) == "Card(Suit.NO_TRUMP, Rank.JOKER)"

def test_invalid_regular_card_creation():
    """Test that a regular card cannot be created with NO_TRUMP suit."""
    with pytest.raises(ValueError, match="NO_TRUMP suit is reserved for Joker only."):
        Card(Suit.NO_TRUMP, Rank.ACE)

def test_card_equality():
    """Test card equality."""
    card1 = Card(Suit.HEARTS, Rank.KING)
    card2 = Card(Suit.HEARTS, Rank.KING)
    card3 = Card(Suit.CLUBS, Rank.KING)
    joker1 = Card(Suit.NO_TRUMP, Rank.JOKER)
    joker2 = Card(Suit.HEARTS, Rank.JOKER) # Will be auto-corrected

    assert card1 == card2
    assert card1 != card3
    assert card1 != joker1
    assert joker1 == joker2 # Both become canonical Jokers
    assert card1 != "Not a card"

def test_card_hashing():
    """Test card hashing for use in sets/dictionary keys."""
    card1 = Card(Suit.DIAMONDS, Rank.TEN)
    card2 = Card(Suit.DIAMONDS, Rank.TEN)
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    card_set = {card1, card2, joker}
    assert len(card_set) == 2 # card1 and card2 are the same
    assert card1 in card_set
    assert joker in card_set

def test_card_sorting():
    """Test card sorting based on suit then rank."""
    # Based on __lt__ using suit.value then rank.value
    # Suit order: CLUBS (0), DIAMONDS (1), HEARTS (2), SPADES (3), NO_TRUMP (4)
    # Rank order: FOUR (4) ... ACE (14), JOKER (100)
    
    c_4c = Card(Suit.CLUBS, Rank.FOUR)
    c_ac = Card(Suit.CLUBS, Rank.ACE)
    c_4d = Card(Suit.DIAMONDS, Rank.FOUR)
    c_jh = Card(Suit.HEARTS, Rank.JACK)
    c_as = Card(Suit.SPADES, Rank.ACE)
    jkr = Card(Suit.NO_TRUMP, Rank.JOKER)

    deck = [c_as, jkr, c_4d, c_ac, c_jh, c_4c] # Unsorted
    deck.sort() # Sorts in place using Card.__lt__

    expected_sorted_deck = [
        c_4c, c_ac,  # Clubs by rank
        c_4d,        # Diamonds
        c_jh,        # Hearts
        c_as,        # Spades
        jkr          # Joker (NO_TRUMP suit has highest value)
    ]
    assert deck == expected_sorted_deck 