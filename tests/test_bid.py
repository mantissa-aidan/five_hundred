import pytest
from five_hundred.bid import Bid, BidType, SUIT_BID_ORDER, MISERE_POINTS, OPEN_MISERE_POINTS, AVONDALE_POINTS_TABLE
from five_hundred.player import Player
from five_hundred.card import Suit

@pytest.fixture
def p1():
    return Player("Player1")

def test_bid_creation_standard_suit(p1):
    """Test creation of a standard suit bid."""
    bid = Bid(player=p1, tricks=7, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP)
    assert bid.player == p1
    assert bid.tricks == 7
    assert bid.suit == Suit.SPADES
    assert bid.bid_type == BidType.SUIT_TRUMP
    assert bid.points == 140 # 7 Spades
    assert str(bid) == "Player1 bids 7 Spades (140 pts)"
    assert repr(bid) == "Bid(Player: Player1, Tricks: 7, Suit: Spades, Type: Suit Trump, Points: 140)"

def test_bid_creation_no_trump(p1):
    """Test creation of a No Trump bid."""
    # Suit can be explicitly Suit.NO_TRUMP for BidType.NO_TRUMP or handled by BidType only
    bid = Bid(player=p1, tricks=8, suit=Suit.NO_TRUMP, bid_type=BidType.NO_TRUMP)
    assert bid.bid_type == BidType.NO_TRUMP
    assert bid.suit == Suit.NO_TRUMP # Or check if it's internally set if suit=None was passed
    assert bid.points == 320 # 8 No Trump
    assert str(bid) == "Player1 bids 8 No Trump (320 pts)"

def test_bid_creation_misere(p1):
    """Test creation of a Misere bid."""
    # Tricks for Misere can be 0 or a conventional value, points define its rank
    bid = Bid(player=p1, tricks=0, suit=None, bid_type=BidType.MISERE) 
    assert bid.bid_type == BidType.MISERE
    assert bid.points == MISERE_POINTS
    assert str(bid) == "Player1 bids Misere (250 pts)"

def test_bid_creation_open_misere(p1):
    """Test creation of an Open Misere bid."""
    bid = Bid(player=p1, tricks=0, suit=None, bid_type=BidType.OPEN_MISERE)
    assert bid.bid_type == BidType.OPEN_MISERE
    assert bid.points == OPEN_MISERE_POINTS
    assert str(bid) == "Player1 bids Open Misere (500 pts)"

def test_invalid_bid_creation(p1):
    """Test invalid bid creations."""
    # Suit_Trump bid with no suit
    with pytest.raises(ValueError, match="Suit must be specified and cannot be No Trump for a SUIT_TRUMP bid."):
        Bid(player=p1, tricks=6, suit=None, bid_type=BidType.SUIT_TRUMP)
    # Suit_Trump bid with NO_TRUMP suit
    with pytest.raises(ValueError, match="Suit must be specified and cannot be No Trump for a SUIT_TRUMP bid."):
        Bid(player=p1, tricks=6, suit=Suit.NO_TRUMP, bid_type=BidType.SUIT_TRUMP)
    # Bid tricks out of range (too low for suit/NT)
    with pytest.raises(ValueError, match="Suit/No-Trump bids must be for 6-10 tricks."):
        Bid(player=p1, tricks=5, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP)
    # Bid tricks out of range (too high for suit/NT)
    with pytest.raises(ValueError, match="Tricks must be between 0 and 10."):
        Bid(player=p1, tricks=11, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP)
    # Invalid tricks for points calculation
    with pytest.raises(ValueError, match="Invalid number of tricks for bidding: 5"):
        # This error is caught by _calculate_points if trick validation in __init__ is bypassed or different
        # Forcing it by creating a Bid with tricks=5 and then trying to access points if init check fails.
        # However, the init check for trick range (6-10) is now stricter.
        bad_bid = Bid(player=p1, tricks=6, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP) # Valid part
        bad_bid.tricks = 5 # Manually set to invalid to test _calculate_points
        bad_bid._calculate_points() # This would raise error


def test_bid_point_calculation_all_suits(p1):
    """Test point calculation for all suits and trick levels."""
    for tricks, points_row in AVONDALE_POINTS_TABLE.items():
        for i, suit_enum in enumerate(SUIT_BID_ORDER):
            expected_points = points_row[i]
            if suit_enum == Suit.NO_TRUMP:
                bid = Bid(player=p1, tricks=tricks, suit=Suit.NO_TRUMP, bid_type=BidType.NO_TRUMP)
            else:
                bid = Bid(player=p1, tricks=tricks, suit=suit_enum, bid_type=BidType.SUIT_TRUMP)
            assert bid.points == expected_points, f"Bid: {tricks} {suit_enum.value if suit_enum else 'None'}"

def test_bid_comparison(p1):
    """Test bid comparison (greater than, less than)."""
    bid_6s = Bid(p1, 6, Suit.SPADES, BidType.SUIT_TRUMP)     # 40
    bid_6c = Bid(p1, 6, Suit.CLUBS, BidType.SUIT_TRUMP)       # 60
    bid_6nt = Bid(p1, 6, Suit.NO_TRUMP, BidType.NO_TRUMP)    # 120
    bid_7s = Bid(p1, 7, Suit.SPADES, BidType.SUIT_TRUMP)     # 140
    bid_misere = Bid(p1, 0, None, BidType.MISERE)            # 250
    bid_8s = Bid(p1, 8, Suit.SPADES, BidType.SUIT_TRUMP)     # 240 (Misere is > 8S)
    bid_8c = Bid(p1, 8, Suit.CLUBS, BidType.SUIT_TRUMP)       # 260 (Misere is < 8C)
    bid_10h = Bid(p1, 10, Suit.HEARTS, BidType.SUIT_TRUMP)   # 500
    bid_open_misere = Bid(p1, 0, None, BidType.OPEN_MISERE) # 500
    bid_10nt = Bid(p1, 10, Suit.NO_TRUMP, BidType.NO_TRUMP) # 520

    assert bid_6c > bid_6s
    assert bid_6nt > bid_6c
    assert bid_7s > bid_6nt
    
    # Misere ranking based on points (250)
    assert bid_misere > bid_8s  # 250 > 240
    assert bid_8c > bid_misere  # 260 > 250
    assert bid_misere > bid_7s  # 250 > 140

    # Open Misere ranking (500 pts)
    # If Open Misere and 10H are both 500, their direct comparison might be equal in rank
    # The > and < operators are strict. If points are equal, neither is greater.
    # Game logic would handle first-bidder-wins for equal rank.
    assert not (bid_open_misere > bid_10h) and not (bid_10h > bid_open_misere) # Equal points
    assert bid_10nt > bid_open_misere # 520 > 500
    assert bid_10nt > bid_10h

    assert bid_6s < bid_6c
    assert bid_open_misere < bid_10nt

def test_bid_equality(p1):
    """Test bid equality."""
    bid1 = Bid(p1, 7, Suit.DIAMONDS, BidType.SUIT_TRUMP) # 180
    bid2 = Bid(p1, 7, Suit.DIAMONDS, BidType.SUIT_TRUMP) # 180
    bid3 = Bid(p1, 7, Suit.HEARTS, BidType.SUIT_TRUMP)   # 200
    p2 = Player("Player2")
    bid4_other_player = Bid(p2, 7, Suit.DIAMONDS, BidType.SUIT_TRUMP)

    assert bid1 == bid2
    assert bid1 != bid3
    assert bid1 != bid4_other_player
    assert bid1 != "not a bid"

    misere1 = Bid(p1, 0, None, BidType.MISERE)
    misere2 = Bid(p1, 0, None, BidType.MISERE)
    assert misere1 == misere2 