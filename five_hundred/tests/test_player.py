import pytest
from five_hundred.player import Player
from five_hundred.card import Card, Suit, Rank
from five_hundred.bid import Bid, BidType # For testing bid-related logic in player if any

@pytest.fixture
def player_setup():
    player = Player("Test Player")
    cards_to_add = [
        Card(Suit.HEARTS, Rank.ACE),
        Card(Suit.SPADES, Rank.KING),
        Card(Suit.DIAMONDS, Rank.TEN),
        Card(Suit.NO_TRUMP, Rank.JOKER),
        Card(Suit.CLUBS, Rank.FIVE)
    ]
    player.add_cards_to_hand(cards_to_add)
    return player, cards_to_add

def test_player_creation():
    """Test basic player creation."""
    player = Player("Alice")
    assert player.name == "Alice"
    assert player.hand == []
    assert player.score == 0
    assert player.tricks_won_this_round == 0
    assert str(player) == "Alice (Score: 0)"
    assert repr(player) == "Player(Alice, Score: 0, Hand: 0 cards, Tricks Won: 0)"

def test_add_card_to_hand(player_setup):
    """Test adding single and multiple cards to hand."""
    player, initial_cards = player_setup
    assert len(player.hand) == len(initial_cards)
    for card in initial_cards:
        assert card in player.hand

    new_card = Card(Suit.HEARTS, Rank.QUEEN)
    player.add_card_to_hand(new_card)
    assert len(player.hand) == len(initial_cards) + 1
    assert new_card in player.hand

def test_play_card(player_setup):
    """Test playing a card from hand."""
    player, initial_cards = player_setup
    card_to_play = initial_cards[0] # Play the Ace of Hearts
    
    played_card = player.play_card(card_to_play)
    assert played_card == card_to_play
    assert card_to_play not in player.hand
    assert len(player.hand) == len(initial_cards) - 1

def test_play_card_not_in_hand(player_setup):
    """Test playing a card that is not in the hand."""
    player, _ = player_setup
    non_existent_card = Card(Suit.SPADES, Rank.FOUR) # Assuming Rank.FOUR is not in standard deck/hand
    with pytest.raises(ValueError, match="Card .* not in player's hand."):
        player.play_card(non_existent_card)

def test_player_score_and_tricks(player_setup):
    """Test score and trick incrementing."""
    player, _ = player_setup
    player.increment_score(120)
    assert player.score == 120
    player.increment_score(-20)
    assert player.score == 100

    player.increment_tricks_won()
    player.increment_tricks_won()
    assert player.tricks_won_this_round == 2
    assert repr(player) == f"Player(Test Player, Score: 100, Hand: {len(player.hand)} cards, Tricks Won: 2)"

def test_reset_for_new_round(player_setup):
    """Test resetting player state for a new round."""
    player, _ = player_setup
    player.increment_score(50)
    player.increment_tricks_won()

    player.reset_for_new_round()
    assert player.hand == []
    assert player.tricks_won_this_round == 0
    # Score should persist across rounds
    assert player.score == 50 
    assert repr(player) == "Player(Test Player, Score: 50, Hand: 0 cards, Tricks Won: 0)"

def test_sort_hand_simple(player_setup):
    """Test basic hand sorting (exact order depends on enum and rank logic)."""
    player, _ = player_setup
    # Hand before sort: H_A, S_K, D_10, Joker, C_5
    # Expected (example, depends on Suit enum order and Rank values):
    # Joker, S_K, C_5, D_10, H_A  (if Suit order is SPADES, CLUBS, DIAMONDS, HEARTS, NO_TRUMP and NO_TRUMP Joker is first)
    # Current sort key: Joker highest, then by Suit enum index, then by reversed Rank enum index (effectively Ace high)
    # Suit enum: SPADES, CLUBS, DIAMONDS, HEARTS, NO_TRUMP
    # Rank enum (reversed for sorting): JOKER, ACE, KING, ..., FOUR

    player.hand = [
        Card(Suit.HEARTS, Rank.ACE),  #HA
        Card(Suit.SPADES, Rank.KING), #SK
        Card(Suit.DIAMONDS, Rank.TEN),#D10
        Card(Suit.NO_TRUMP, Rank.JOKER), #Joker
        Card(Suit.CLUBS, Rank.FIVE),  #C5
        Card(Suit.SPADES, Rank.ACE)   #SA
    ]
    player.sort_hand()
    
    # Expected order with current sort_key:
    # Joker (NO_TRUMP, JOKER) -> (-1,-1)
    # King of Spades (SPADES, KING) -> (0, -Rank.KING_idx)
    # Ace of Spades (SPADES, ACE) -> (0, -Rank.ACE_idx)
    # Five of Clubs (CLUBS, FIVE) -> (1, -Rank.FIVE_idx)
    # Ten of Diamonds (DIAMONDS, TEN) -> (2, -Rank.TEN_idx)
    # Ace of Hearts (HEARTS, ACE) -> (3, -Rank.ACE_idx)

    # Let's verify specific behaviors: Joker first, then suits grouped, then ranks within suits.
    # Note: This test depends on the current simple sort implementation.
    # It should be updated if sort_hand logic becomes more complex (e.g., considering trump).

    sorted_hand = player.hand
    assert sorted_hand[0] == Card(Suit.NO_TRUMP, Rank.JOKER)
    
    # Find indices of suits to check grouping and internal order
    spades_indices = [i for i, card in enumerate(sorted_hand) if card.suit == Suit.SPADES]
    clubs_indices = [i for i, card in enumerate(sorted_hand) if card.suit == Suit.CLUBS]
    
    # Check Spades are together and sorted Ace > King
    if len(spades_indices) > 1:
        assert spades_indices[-1] - spades_indices[0] == len(spades_indices) -1
        ace_spades_pos = -1
        king_spades_pos = -1
        for i in spades_indices:
            if sorted_hand[i].rank == Rank.ACE:
                ace_spades_pos = i
            if sorted_hand[i].rank == Rank.KING:
                king_spades_pos = i
        assert ace_spades_pos < king_spades_pos # Ace comes before King due to -rank_priority

    # This is a basic check. More robust sorting tests needed if logic evolves.
    # For now, just check Joker is first and other cards exist.
    assert len(sorted_hand) == 6
    original_cards_set = set([
        Card(Suit.HEARTS, Rank.ACE),
        Card(Suit.SPADES, Rank.KING),
        Card(Suit.DIAMONDS, Rank.TEN),
        Card(Suit.NO_TRUMP, Rank.JOKER),
        Card(Suit.CLUBS, Rank.FIVE),
        Card(Suit.SPADES, Rank.ACE)
    ])
    assert set(sorted_hand) == original_cards_set

# Further tests could involve sorting with a trump suit specified, etc. 