import pytest
from five_hundred.game import Game
from five_hundred.player import Player
from five_hundred.team import Team
from five_hundred.card import Card, Suit, Rank
from five_hundred.bid import Bid, BidType
from unittest.mock import MagicMock, patch
import contextlib # For the context manager
from typing import List, Optional

PLAYER_NAMES = ["P1", "P2", "P3", "P4"]
TEAM_NAMES = ["T1/3", "T2/4"]

@pytest.fixture
def game_setup():
    """Provides a Game instance for testing."""
    return Game(PLAYER_NAMES, TEAM_NAMES)

def test_game_creation(game_setup):
    """Test the basic setup of the game, players, and teams."""
    game = game_setup
    assert len(game.players) == 4
    assert len(game.teams) == 2

    # Check player assignments to teams
    assert game.players[0] in game.teams[0].players
    assert game.players[2] in game.teams[0].players
    assert game.players[1] in game.teams[1].players
    assert game.players[3] in game.teams[1].players

    assert game.teams[0].name == TEAM_NAMES[0]
    assert game.teams[1].name == TEAM_NAMES[1]

    assert game.current_dealer_idx == 0 # Initial dealer
    assert game.winning_bid is None
    assert game.trump_suit is None
    assert not game.game_over
    assert repr(game) == f"Game(Players: 4, Teams: 2, Dealer: {PLAYER_NAMES[0]})"

def test_invalid_game_creation():
    """Test game creation with invalid parameters."""
    with pytest.raises(ValueError, match="Standard 500 game requires 4 players."):
        Game(["P1", "P2"], TEAM_NAMES)
    with pytest.raises(ValueError, match="Standard 500 game requires 2 teams."):
        Game(PLAYER_NAMES, ["Team1"])

def test_deal_cards(game_setup):
    """Test the card dealing mechanism."""
    game = game_setup
    # Call _deal_cards directly for this test, normally called by start_new_round
    game._deal_cards() 

    assert len(game.kitty) == 3
    for player in game.players:
        assert len(player.hand) == 10
    assert len(game.deck.cards) == 0 # Deck should be empty

    # Check all cards are unique across all hands and kitty
    all_dealt_cards = list(game.kitty)
    for player in game.players:
        all_dealt_cards.extend(player.hand)
    assert len(all_dealt_cards) == 43
    assert len(set(all_dealt_cards)) == 43

def test_start_new_round(game_setup):
    """Test starting a new round, including dealer rotation and dealing."""
    game = game_setup
    initial_dealer_idx = game.current_dealer_idx

    # Mock player actions to prevent input() calls during this logic test
    def mock_pass_action(player_obj):
        return ("pass", None)
    
    original_get_bid_action = game._get_player_bid_action
    game._get_player_bid_action = mock_pass_action # Apply mock

    try:
        game.start_new_round() # First round, dealer should rotate
        assert game.current_dealer_idx == (initial_dealer_idx + 1) % 4
        assert game.players[game.current_dealer_idx].name == PLAYER_NAMES[(initial_dealer_idx + 1) % 4]

        # Start another round to test dealer rotation again
        current_dealer_idx_after_round1 = game.current_dealer_idx
        game.start_new_round() # Second round, mock should still be active
        assert game.current_dealer_idx == (current_dealer_idx_after_round1 + 1) % 4

    finally:
        game._get_player_bid_action = original_get_bid_action # Restore original method

    # Commented out hand assertions as they depend on full playout
    # ... (rest of commented assertions) ...

def test_player_attempts_bid(game_setup):
    """Test player bidding attempts."""
    game = game_setup
    # game.start_new_round() # Don't run full round simulation if we want to test attempts_bid in isolation
    bidder = game.players[0]
    bidder2 = game.players[1]

    # Reset bidding state for clean test of player_attempts_bid
    game._reset_bidding_state() # Resets highest_bid_this_round, etc.
    game.current_bidder_idx = game.players.index(bidder) # Set current bidder if necessary for player_attempts_bid logic

    # Successful first bid
    assert game.player_attempts_bid(bidder, 6, Suit.SPADES, BidType.SUIT_TRUMP)
    assert game.highest_bid_this_round is not None
    assert game.highest_bid_this_round.player == bidder
    assert game.highest_bid_this_round.tricks == 6
    assert game.highest_bid_this_round.suit == Suit.SPADES
    assert game.highest_bid_this_round.points == 40
    assert game.passes_this_round == 0
    assert game.player_has_bid_this_round[bidder]

    # Attempt lower bid by another player
    assert game.player_attempts_bid(bidder2, 6, Suit.CLUBS, BidType.SUIT_TRUMP) # 6C (60pts) is > 6S (40pts)
    assert game.highest_bid_this_round.player == bidder2
    assert game.highest_bid_this_round.points == 60

    # Original bidder attempts a lower/equal bid (should fail)
    assert not game.player_attempts_bid(bidder, 6, Suit.CLUBS, BidType.SUIT_TRUMP) # Equal to current highest, should fail
    assert not game.player_attempts_bid(bidder, 6, Suit.SPADES, BidType.SUIT_TRUMP) # Lower than current highest

    # Original bidder attempts a higher bid
    assert game.player_attempts_bid(bidder, 7, Suit.SPADES, BidType.SUIT_TRUMP) # 7S (140pts)
    assert game.highest_bid_this_round.player == bidder
    assert game.highest_bid_this_round.points == 140

    # Test Misere bid
    assert game.player_attempts_bid(bidder2, 0, None, BidType.MISERE) # Misere (250pts)
    assert game.highest_bid_this_round.bid_type == BidType.MISERE
    assert game.highest_bid_this_round.points == 250

    # Invalid bid parameters
    assert not game.player_attempts_bid(bidder, 5, Suit.HEARTS, BidType.SUIT_TRUMP) # Invalid tricks

    # Attempt same bid by same player (not allowed)
    assert not game.player_attempts_bid(bidder, 6, Suit.SPADES, BidType.SUIT_TRUMP)

def test_player_passes_bid(game_setup):
    """Test player passing."""
    game = game_setup
    
    # Reset to clean state and do not run start_new_round to avoid confusing auction state
    game._reset_bidding_state()
    
    # Test basic pass functionality
    game.player_passes_bid(game.players[0])
    assert game.passes_this_round == 1
    assert game.player_has_passed_auction[game.players[0]]
    
    game.player_passes_bid(game.players[1])
    assert game.passes_this_round == 2
    assert game.player_has_passed_auction[game.players[1]]

    # If a bid is made after passes, passes reset to 0
    game.player_attempts_bid(game.players[2], 6, Suit.DIAMONDS, BidType.SUIT_TRUMP)
    assert game.passes_this_round == 0

    # Player who passed before cannot bid again
    assert not game.player_attempts_bid(game.players[0], 8, Suit.SPADES, BidType.SUIT_TRUMP)
    assert not game.player_attempts_bid(game.players[1], 8, Suit.SPADES, BidType.SUIT_TRUMP)
    
    # But they can still formally pass again
    game.player_passes_bid(game.players[0])
    assert game.passes_this_round == 1  # Increments from 0 after bid reset
    
    game.player_passes_bid(game.players[1])
    assert game.passes_this_round == 2

def test_check_game_over(game_setup):
    """Test game over conditions."""
    game = game_setup
    team1 = game.teams[0]
    team2 = game.teams[1]

    assert not game.check_game_over()
    assert not game.game_over

    team1.update_score(500)
    assert game.check_game_over()
    assert game.game_over

    # Reset for next test
    game.game_over = False
    team1.team_score = 0

    team2.update_score(510)
    assert game.check_game_over()
    assert game.game_over

    game.game_over = False
    team2.team_score = 0

    team1.update_score(-500)
    assert game.check_game_over()
    assert game.game_over

    game.game_over = False
    team1.team_score = 0

    team2.update_score(-550)
    assert game.check_game_over()
    assert game.game_over

def test_get_card_strength_in_trick(game_setup):
    """Test the _get_card_strength_in_trick method for various scenarios."""
    game = game_setup # Provides a game instance to call the method
    
    # Test cards
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_h = Card(Suit.HEARTS, Rank.ACE)
    king_h = Card(Suit.HEARTS, Rank.KING)
    jack_h = Card(Suit.HEARTS, Rank.JACK) # Potential Right Bower
    jack_d = Card(Suit.DIAMONDS, Rank.JACK) # Potential Left Bower if Hearts trump
    ace_s = Card(Suit.SPADES, Rank.ACE)
    king_s = Card(Suit.SPADES, Rank.KING)
    jack_s = Card(Suit.SPADES, Rank.JACK) # Potential Right Bower
    jack_c = Card(Suit.CLUBS, Rank.JACK) # Potential Left Bower if Spades trump
    ten_s = Card(Suit.SPADES, Rank.TEN)
    five_d = Card(Suit.DIAMONDS, Rank.FIVE)

    # Scenario 1: Hearts are trump, Hearts are led
    trump = Suit.HEARTS
    led = Suit.HEARTS
    assert game._get_card_strength_in_trick(joker, led, trump) == 100 # Joker
    assert game._get_card_strength_in_trick(jack_h, led, trump) == 90  # Right Bower (JH)
    assert game._get_card_strength_in_trick(jack_d, led, trump) == 80  # Left Bower (JD)
    assert game._get_card_strength_in_trick(ace_h, led, trump) > game._get_card_strength_in_trick(king_h, led, trump) # Ace of trump > King of trump
    assert game._get_card_strength_in_trick(king_h, led, trump) > 50 # Trump vs non-trump base
    assert game._get_card_strength_in_trick(ace_s, led, trump) == 0 # Spade is off-suit, not trump

    # Scenario 2: Spades are trump, Hearts are led
    trump = Suit.SPADES
    led = Suit.HEARTS
    assert game._get_card_strength_in_trick(joker, led, trump) == 100
    assert game._get_card_strength_in_trick(jack_s, led, trump) == 90  # Right Bower (JS)
    assert game._get_card_strength_in_trick(jack_c, led, trump) == 80  # Left Bower (JC)
    assert game._get_card_strength_in_trick(ace_s, led, trump) > game._get_card_strength_in_trick(ten_s, led, trump) # Ace of trump > Ten of trump
    assert game._get_card_strength_in_trick(ten_s, led, trump) > 50 # Trump
    assert game._get_card_strength_in_trick(ace_h, led, trump) < 50 and game._get_card_strength_in_trick(ace_h, led, trump) > 0 # Following lead suit (Hearts)
    assert game._get_card_strength_in_trick(king_h, led, trump) < game._get_card_strength_in_trick(ace_h, led, trump)
    assert game._get_card_strength_in_trick(five_d, led, trump) == 0 # Diamond is off-suit, not trump

    # Scenario 3: No Trump game, Spades are led
    trump = Suit.NO_TRUMP
    led = Suit.SPADES
    assert game._get_card_strength_in_trick(joker, led, trump) == 100 # Joker is only trump
    assert game._get_card_strength_in_trick(ace_s, led, trump) == 14   # Ace of Spades (follows suit)
    assert game._get_card_strength_in_trick(king_s, led, trump) == 13  # King of Spades (follows suit)
    assert game._get_card_strength_in_trick(ace_h, led, trump) == 0    # Hearts is off-suit
    assert game._get_card_strength_in_trick(jack_s, led, trump) == 11 # Jack of Spades (just a spade)
    assert game._get_card_strength_in_trick(jack_c, led, trump) == 0   # Clubs is off-suit

    # Scenario 4: Hearts are trump, Spades are led (testing Bower's ability to trump)
    trump = Suit.HEARTS
    led = Suit.SPADES
    assert game._get_card_strength_in_trick(jack_h, led, trump) == 90  # Right Bower (JH) trumps Spades led
    assert game._get_card_strength_in_trick(jack_d, led, trump) == 80  # Left Bower (JD) trumps Spades led
    assert game._get_card_strength_in_trick(ace_h, led, trump) > 50  # Ace of Hearts (trump) trumps Spades led
    assert game._get_card_strength_in_trick(ace_s, led, trump) < 50 and game._get_card_strength_in_trick(ace_s, led, trump) > 0 # Ace of Spades (follows suit)
    assert game._get_card_strength_in_trick(five_d, led, trump) == 0   # Off-suit non-trump

    # Scenario 5: Comparing non-trump cards of the led suit
    trump = Suit.HEARTS # Trump suit doesn't matter if cards are not trump and not Bowers
    led = Suit.SPADES
    assert game._get_card_strength_in_trick(ace_s, led, trump) > game._get_card_strength_in_trick(king_s, led, trump)
    assert game._get_card_strength_in_trick(king_s, led, trump) > game._get_card_strength_in_trick(ten_s, led, trump)

def test_get_playable_cards(game_setup):
    """Test the _get_playable_cards method."""
    game = game_setup
    player = game.players[0]

    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_h = Card(Suit.HEARTS, Rank.ACE)
    king_h = Card(Suit.HEARTS, Rank.KING)
    ten_s = Card(Suit.SPADES, Rank.TEN)
    five_d = Card(Suit.DIAMONDS, Rank.FIVE)
    ace_c = Card(Suit.CLUBS, Rank.ACE)

    # Scenario 1: Leading a trick (no trick_suit yet)
    player.hand = [ace_h, ten_s, joker]
    playable = game._get_playable_cards(player, None)
    assert len(playable) == 3
    assert ace_h in playable
    assert ten_s in playable
    assert joker in playable

    # Scenario 2: Must follow suit (Hearts led)
    player.hand = [ace_h, king_h, ten_s, joker, five_d]
    playable = game._get_playable_cards(player, Suit.HEARTS)
    assert len(playable) == 2
    assert ace_h in playable
    assert king_h in playable
    assert ten_s not in playable
    assert joker not in playable # Joker is not HEARTS, player CAN follow suit
    assert five_d not in playable

    # Scenario 3: Cannot follow suit (Clubs led, no Clubs in hand)
    player.hand = [ace_h, ten_s, joker, five_d]
    # game.trump_suit = Suit.HEARTS # Trump suit doesn't directly affect _get_playable_cards basic logic
    playable = game._get_playable_cards(player, Suit.CLUBS)
    assert len(playable) == 4 # All cards are playable
    assert ace_h in playable
    assert ten_s in playable
    assert joker in playable
    assert five_d in playable

    # Scenario 4: Has only Joker, cannot follow suit (Clubs led)
    player.hand = [joker]
    playable = game._get_playable_cards(player, Suit.CLUBS)
    assert len(playable) == 1
    assert joker in playable

    # Scenario 5: Must follow suit (Spades), has Joker but also Spades
    player.hand = [ten_s, joker, ace_h]
    playable = game._get_playable_cards(player, Suit.SPADES)
    assert len(playable) == 1
    assert ten_s in playable
    assert joker not in playable
    assert ace_h not in playable

    # Scenario 6: Cannot follow suit (Hearts led), has Joker and other off-suit cards
    player.hand = [ten_s, joker, five_d, ace_c]
    playable = game._get_playable_cards(player, Suit.HEARTS)
    assert len(playable) == 4
    assert ten_s in playable
    assert joker in playable
    assert five_d in playable
    assert ace_c in playable

    # Scenario 7: Empty hand (should not happen in valid play, but test robustness)
    player.hand = []
    playable = game._get_playable_cards(player, Suit.HEARTS)
    assert len(playable) == 0

def test_get_playable_cards_bower_regression(game_setup):
    """Regression test for the 'Bower Suit' bug.
    Ensures that if a Left Bower is led, players must follow with Trump, not the original suit.
    """
    game = game_setup
    player = game.players[0]
    
    # Set Diamonds as Trump
    game.trump_suit = Suit.DIAMONDS
    
    # Human has some Diamonds and the Jack of Hearts (Left Bower)
    jack_h = Card(Suit.HEARTS, Rank.JACK) # Effective Diamond (Trump)
    ace_d = Card(Suit.DIAMONDS, Rank.ACE)
    ten_h = Card(Suit.HEARTS, Rank.TEN)   # Off-suit
    
    player.hand = [jack_h, ace_d, ten_h]
    
    # Case 1: Human leads the Jack of Hearts
    # The trick suit should effectively become DIAMONDS
    effective_suit_led = game._get_effective_suit(jack_h, game.trump_suit)
    assert effective_suit_led == Suit.DIAMONDS
    
    # Case 2: Someone ELSE leads the Jack of Hearts, Human must follow suit
    # If Diamonds are led (or J of Hearts is led), Human MUST play their Diamonds (including J of Hearts)
    playable = game._get_playable_cards(player, Suit.DIAMONDS)
    
    assert len(playable) == 2
    assert jack_h in playable # Left Bower is a Diamond now
    assert ace_d in playable  # Regular Diamond
    assert ten_h not in playable # Ten of Hearts is NOT a Diamond, even though it shares J of Hearts' print suit.

    # Case 3: Hearts are led, Human has Hearts, but J of Hearts is NOT a Heart
    playable_hearts = game._get_playable_cards(player, Suit.HEARTS)
    assert len(playable_hearts) == 1
    assert ten_h in playable_hearts
    assert jack_h not in playable_hearts # Should NOT be allowed to play J of Hearts here!

def test_play_trick(game_setup):
    """Test the _play_trick method, including trick winner determination using test mode card choice."""
    game = game_setup
    p1, p2, p3, p4 = game.players[0], game.players[1], game.players[2], game.players[3]

    # Card definitions
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_h, king_h, queen_h, ten_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.QUEEN), Card(Suit.HEARTS, Rank.TEN)
    jack_h = Card(Suit.HEARTS, Rank.JACK)
    jack_d = Card(Suit.DIAMONDS, Rank.JACK) # Left Bower if Hearts trump
    ace_s, king_s, queen_s, ten_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN), Card(Suit.SPADES, Rank.TEN)
    five_c = Card(Suit.CLUBS, Rank.FIVE)
    card_DA = Card(Suit.DIAMONDS, Rank.ACE)
    card_C6 = Card(Suit.CLUBS, Rank.SIX)
    card_C7 = Card(Suit.CLUBS, Rank.SEVEN)
    card_C4 = Card(Suit.CLUBS, Rank.FOUR)

    # --- Scenario 1: Simple follow suit, highest card wins --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.NO_TRUMP
    p1.hand = [ace_h, king_s]
    p2.hand = [king_h, ace_s]
    p3.hand = [queen_h, ten_s]
    p4.hand = [ten_h, five_c]

    def scenario1_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return king_s 
        if player == p2: return ace_s  
        if player == p3: return ten_s  
        if player == p4: return five_c 
        raise ValueError(f"Unexpected player {player.name} in S1 logic")
    game._test_mode_card_choice_logic = scenario1_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p2 
    assert p2.tricks_won_this_round == 1
    assert p1.hand == [ace_h] and p2.hand == [king_h] and p3.hand == [queen_h] and p4.hand == [ten_h]

    # --- Scenario 2: Trump wins (Hearts are trump, Spades led by P1, P4 trumps highest) --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.HEARTS
    p1.hand = [ace_s, card_DA]
    p2.hand = [ten_h, five_c]
    p3.hand = [king_s, card_C6]
    p4.hand = [ace_h, card_C7]
    def scenario2_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return ace_s  
        if player == p2: return ten_h  
        if player == p3: return king_s 
        if player == p4: return ace_h  
        raise ValueError(f"Unexpected player {player.name} in S2 logic")
    game._test_mode_card_choice_logic = scenario2_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p4 
    assert p4.tricks_won_this_round == 1
    assert p1.hand == [card_DA] and p2.hand == [five_c] and p3.hand == [card_C6] and p4.hand == [card_C7]

    # --- Scenario 3: Joker wins (Hearts are trump, Spades led by P1, P3 plays Joker) --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.HEARTS
    p1.hand = [ace_s, ten_h]
    p2.hand = [king_s, five_c]
    p3.hand = [joker, card_C4]
    p4.hand = [ace_h, king_h]
    def scenario3_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return ace_s
        if player == p2: return king_s
        if player == p3: return joker 
        if player == p4: return ace_h
        raise ValueError(f"Unexpected player {player.name} in S3 logic")
    game._test_mode_card_choice_logic = scenario3_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p3 
    assert p3.tricks_won_this_round == 1
    assert p1.hand == [ten_h] and p2.hand == [five_c] and p3.hand == [card_C4] and p4.hand == [king_h]

    # --- Scenario 4: Right Bower wins --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.HEARTS # Right: Jack_H, Left: Jack_D
    p1.hand = [ace_s, ten_s]      
    p2.hand = [jack_h, five_c]    
    p3.hand = [king_s, queen_s]   
    p4.hand = [ace_h, king_h]     
    def scenario4_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return ten_s 
        if player == p2: return jack_h 
        if player == p3: return king_s 
        if player == p4: return ace_h  
        raise ValueError(f"Unexpected player {player.name} in S4 logic")
    game._test_mode_card_choice_logic = scenario4_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p2 
    assert p2.tricks_won_this_round == 1
    assert p1.hand == [ace_s] and p2.hand == [five_c] and p3.hand == [queen_s] and p4.hand == [king_h]

    # --- Scenario 5: Left Bower wins --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.HEARTS # Right: Jack_H, Left: Jack_D
    p1.hand = [ace_s, ten_s]        
    p2.hand = [king_h, five_c]      
    p3.hand = [king_s, queen_s]     
    p4.hand = [jack_d, queen_h]     
    def scenario5_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return ten_s  
        if player == p2: return king_h 
        if player == p3: return king_s 
        if player == p4: return jack_d 
        raise ValueError(f"Unexpected player {player.name} in S5 logic")
    game._test_mode_card_choice_logic = scenario5_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p4 
    assert p4.tricks_won_this_round == 1
    assert p1.hand == [ace_s] and p2.hand == [five_c] and p3.hand == [queen_s] and p4.hand == [queen_h]

    # --- Scenario 6: Joker leads a trump game --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.SPADES
    p1.hand = [joker, ace_h]    
    p2.hand = [ace_s, king_h]   
    p3.hand = [king_s, queen_h] 
    p4.hand = [ten_s, ten_h]    
    def scenario6_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return joker 
        if player == p2: return ace_s 
        if player == p3: return king_s
        if player == p4: return ten_s 
        raise ValueError(f"Unexpected player {player.name} in S6 logic")
    game._test_mode_card_choice_logic = scenario6_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p1 
    assert p1.tricks_won_this_round == 1
    assert p1.hand == [ace_h] and p2.hand == [king_h] and p3.hand == [queen_h] and p4.hand == [ten_h]

    # --- Scenario 7: Joker leads a No Trump game --- 
    for p_ in game.players: p_.reset_for_new_round()
    game.trump_suit = Suit.NO_TRUMP
    p1.hand = [joker, ace_h]    
    p2.hand = [ace_s, king_h]   
    p3.hand = [king_s, queen_h] 
    p4.hand = [ten_s, ten_h]    
    def scenario7_logic(player: Player, playable: List[Card], trick_s: Optional[Suit], trump_s: Optional[Suit]) -> Card:
        if player == p1: return joker 
        if player == p2: return ace_s 
        if player == p3: return king_s
        if player == p4: return ten_s 
        raise ValueError(f"Unexpected player {player.name} in S7 logic")
    game._test_mode_card_choice_logic = scenario7_logic
    winner = game._play_trick(lead_player=p1)
    game._test_mode_card_choice_logic = None
    assert winner == p1 
    assert p1.tricks_won_this_round == 1
def test_score_round(game_setup):
    """Test the _score_round method for various bid outcomes."""
    game = game_setup
    p1, p2, p3, p4 = game.players[0], game.players[1], game.players[2], game.players[3]
    team_ac = game.teams[0] # P1, P3
    team_bd = game.teams[1] # P2, P4

    # --- Helper to reset scores and tricks for each scenario ---
    def reset_for_scenario():
        team_ac.team_score = 0
        team_bd.team_score = 0
        for player in game.players:
            player.score = 0 # Individual score (if tracked, though team score is primary)
            player.tricks_won_this_round = 0
        game.winning_bid = None
        game.trump_suit = None
        game.game_over = False
    
    # Scenario 1: Suit bid, contract made (6 Spades, P1 declarer, Team A/C wins 7 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p1, tricks=6, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP) # 40 points
    game.trump_suit = Suit.SPADES
    p1.tricks_won_this_round = 4
    p3.tricks_won_this_round = 3 # Team A/C wins 7 tricks
    game._score_round(declarer=p1)
    assert team_ac.team_score == 40
    assert team_bd.team_score == 0

    # Scenario 2: Suit bid, contract failed (7 Hearts, P2 declarer, Team B/D wins 6 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p2, tricks=7, suit=Suit.HEARTS, bid_type=BidType.SUIT_TRUMP) # 7H is 200 points
    game.trump_suit = Suit.HEARTS
    p2.tricks_won_this_round = 3
    p4.tricks_won_this_round = 3 # Team B/D wins 6 tricks, needed 7
    game._score_round(declarer=p2)
    assert team_bd.team_score == -200 # Contract failed, -bid_points
    assert team_ac.team_score == 0

    # Scenario 3: No Trump bid, contract made with Avondale Slam (8 No Trump, P3 declarer, Team A/C wins 10 tricks)
    # Bid is 8NT = 320 points. Slam for 10 tricks if bid < 250. This bid is > 250, so no slam bonus here.
    # Correction: Avondale slam is if actual bid points < 250, and 10 tricks won, then score 250. 
    # If bid is 320, and 10 tricks won, score 320.
    reset_for_scenario()
    game.winning_bid = Bid(player=p3, tricks=8, suit=Suit.NO_TRUMP, bid_type=BidType.NO_TRUMP) # 320 points
    game.trump_suit = Suit.NO_TRUMP
    p1.tricks_won_this_round = 5
    p3.tricks_won_this_round = 5 # Team A/C wins 10 tricks
    game._score_round(declarer=p3)
    assert team_ac.team_score == 320 
    assert team_bd.team_score == 0

    # Scenario 3b: Suit bid, contract made with Avondale Slam (6 Spades, P1 declarer, Team A/C wins 10 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p1, tricks=6, suit=Suit.SPADES, bid_type=BidType.SUIT_TRUMP) # 40 points
    game.trump_suit = Suit.SPADES
    p1.tricks_won_this_round = 10 # All 10 tricks
    p3.tricks_won_this_round = 0 
    game._score_round(declarer=p1)
    assert team_ac.team_score == 250 # Slam bonus applies (bid 40 < 250, won 10)
    assert team_bd.team_score == 0

    # Scenario 4: Misere bid, successful (P4 declarer, P4 wins 0 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p4, tricks=0, suit=None, bid_type=BidType.MISERE) # 250 points
    game.trump_suit = Suit.NO_TRUMP # Misere implies No Trump for play
    # P4 (declarer) must win 0 tricks.
    p4.tricks_won_this_round = 0
    # Other players can win tricks, does not affect P4 Misere outcome
    p1.tricks_won_this_round = 5 
    p2.tricks_won_this_round = 5
    game._score_round(declarer=p4)
    assert team_bd.team_score == 250
    assert team_ac.team_score == 0

    # Scenario 5: Misere bid, failed (P1 declarer, P1 wins 1 trick)
    reset_for_scenario()
    game.winning_bid = Bid(player=p1, tricks=0, suit=None, bid_type=BidType.MISERE) # 250 points
    game.trump_suit = Suit.NO_TRUMP
    p1.tricks_won_this_round = 1 # P1 failed Misere
    game._score_round(declarer=p1)
    assert team_ac.team_score == -250
    assert team_bd.team_score == 0

    # Scenario 6: Open Misere bid, successful (P2 declarer, P2 wins 0 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p2, tricks=0, suit=None, bid_type=BidType.OPEN_MISERE) # 500 points
    game.trump_suit = Suit.NO_TRUMP
    p2.tricks_won_this_round = 0
    game._score_round(declarer=p2)
    assert team_bd.team_score == 500
    assert team_ac.team_score == 0
    assert game.game_over # Reached 500 points

    # Scenario 7: Open Misere bid, failed (P3 declarer, P3 wins 2 tricks)
    reset_for_scenario()
    game.winning_bid = Bid(player=p3, tricks=0, suit=None, bid_type=BidType.OPEN_MISERE) # 500 points
    game.trump_suit = Suit.NO_TRUMP
    p3.tricks_won_this_round = 2
    game._score_round(declarer=p3)
    assert team_ac.team_score == -500
    assert team_bd.team_score == 0
    assert game.game_over # Reached -500 points

    # Scenario 8: No winning bid (e.g., all passed)
    reset_for_scenario()
    game.winning_bid = None
    # Give some tricks to players to ensure they are ignored
    p1.tricks_won_this_round = 5
    p2.tricks_won_this_round = 5
    game._score_round(declarer=p1) # Declarer doesn't matter if no winning_bid
    assert team_ac.team_score == 0
    assert team_bd.team_score == 0
    assert not game.game_over

# Define the context manager for full round test mocking
@contextlib.contextmanager
def FullRoundMocker(game: Game, mock_bid_action=None, mock_deal_cards=None, mock_kitty_exchange=None, mock_play_round=None):
    original_get_bid_action = game._get_player_bid_action
    original_deal_cards = game._deal_cards
    original_handle_kitty_exchange = game._handle_kitty_exchange
    original_play_round = game._play_round
    # Note: _score_round is usually called by the mocked _play_round, so we don't typically mock _score_round itself at this level.

    if mock_bid_action:
        game._get_player_bid_action = mock_bid_action
    if mock_deal_cards:
        game._deal_cards = mock_deal_cards
    if mock_kitty_exchange:
        game._handle_kitty_exchange = mock_kitty_exchange
    if mock_play_round:
        game._play_round = mock_play_round
    
    try:
        yield
    finally:
        game._get_player_bid_action = original_get_bid_action
        game._deal_cards = original_deal_cards
        game._handle_kitty_exchange = original_handle_kitty_exchange
        game._play_round = original_play_round

def test_full_round_suit_bid_contract_made(game_setup):
    game = game_setup
    p1 = game.players[0]
    p3 = game.players[2] # P1's partner
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_s, king_s, queen_s, jack_s, ten_s, nine_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN), Card(Suit.SPADES, Rank.JACK), Card(Suit.SPADES, Rank.TEN), Card(Suit.SPADES, Rank.NINE)
    ace_h, king_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING)
    ace_d = Card(Suit.DIAMONDS, Rank.ACE)
    
    h4, d4, c5 = Card(Suit.HEARTS, Rank.FOUR), Card(Suit.DIAMONDS, Rank.FOUR), Card(Suit.CLUBS, Rank.FIVE)
    kitty_cards_to_use = [h4, d4, c5]
    p1_hand_cards = [joker, ace_s, king_s, queen_s, jack_s, ten_s, nine_s, ace_h, king_h, ace_d]

    game.current_dealer_idx = 2 
    
    # --- Define Mocks ---
    def mock_bid_action_p1_6s_others_pass(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (6, Suit.SPADES, BidType.SUIT_TRUMP))
            else: 
                return ("pass", None) 
        else: 
            return ("pass", None)

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        other_cards = [Card(s, r) for s in [Suit.CLUBS, Suit.DIAMONDS] for r in list(Rank) if r != Rank.JOKER and r not in [Rank.FOUR, Rank.FIVE]][:30]
        game.players[1].hand = other_cards[0:10]
        game.players[2].hand = other_cards[10:20]
        game.players[3].hand = other_cards[20:30]
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = []

    original_score_round = game._score_round # Keep a reference to the original score_round

    def mock_kitty_exchange_p1_discards(declarer):
        if declarer == p1:
            declarer.add_cards_to_hand(list(kitty_cards_to_use)) 
            cards_to_discard_p1 = [ace_h, king_h, ace_d]
            for card in cards_to_discard_p1:
                if card in declarer.hand:
                    declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            game.kitty = [] 
            # game._play_round(declarer) # Removed redundant call
        else: 
            # Fallback to original if needed, though not expected here
            game.original_handle_kitty_exchange(declarer) 


    def mock_play_round_p1_team_wins_7_tricks(declarer):
        if declarer == p1: 
            p1.tricks_won_this_round = 7 
            p3.tricks_won_this_round = 0 
            game.players[1].tricks_won_this_round = 2 
            game.players[3].tricks_won_this_round = 1 
        original_score_round(declarer) # Call the original scoring method

    team_ac.team_score = 0
    team_bd.team_score = 0
    
    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_6s_others_pass,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_p1_discards,
                         mock_play_round=mock_play_round_p1_team_wins_7_tricks):
        game.start_new_round()

    # Assertions remain the same
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.suit == Suit.SPADES
    assert game.winning_bid.tricks == 6
    
    contracting_team_tricks = team_ac.get_total_tricks_won_this_round()
    assert contracting_team_tricks == 7

    expected_score = game.winning_bid.points # Score for 6 Spades is 40 if made
    assert team_ac.team_score == expected_score, f"Expected team score {expected_score}, got {team_ac.team_score}"
    assert team_bd.team_score == 0 
    
    assert not game.game_over

def test_full_round_suit_bid_contract_failed(game_setup):
    game = game_setup
    p1 = game.players[0]
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions (as in the original test)
    ace_s, king_s, queen_s, jack_s, ten_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN), Card(Suit.SPADES, Rank.JACK), Card(Suit.SPADES, Rank.TEN)
    nine_s, eight_s, seven_s, six_s, five_s = Card(Suit.SPADES, Rank.NINE), Card(Suit.SPADES, Rank.EIGHT), Card(Suit.SPADES, Rank.SEVEN), Card(Suit.SPADES, Rank.SIX), Card(Suit.SPADES, Rank.FIVE)
    ace_h, king_h, queen_h, jack_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.QUEEN), Card(Suit.HEARTS, Rank.JACK)
    ace_d, king_d, queen_d, jack_d = Card(Suit.DIAMONDS, Rank.ACE), Card(Suit.DIAMONDS, Rank.KING), Card(Suit.DIAMONDS, Rank.QUEEN), Card(Suit.DIAMONDS, Rank.JACK)
    ace_c, king_c, queen_c, jack_c = Card(Suit.CLUBS, Rank.ACE), Card(Suit.CLUBS, Rank.KING), Card(Suit.CLUBS, Rank.QUEEN), Card(Suit.CLUBS, Rank.JACK)
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    h4, d4, c5 = Card(Suit.HEARTS, Rank.FOUR), Card(Suit.DIAMONDS, Rank.FOUR), Card(Suit.CLUBS, Rank.FIVE)

    kitty_cards_to_use = [h4, d4, c5] # P1 will get these weak cards

    game.current_dealer_idx = 2 # P1 bids first

    # --- Define Mocks for this test --- 
    def mock_bid_action_p1_6s_others_pass(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (6, Suit.SPADES, BidType.SUIT_TRUMP)) 
            else: return ("pass", None)
        else: return ("pass", None)

    # P1 (declarer) gets a weak spade hand, opponents get strong spades
    p1_hand_cards = [nine_s, eight_s, seven_s, ace_h, king_h, ace_d, king_d, ace_c, king_c, Card(Suit.HEARTS, Rank.TEN)]
    p2_hand_cards = [ace_s, king_s, six_s, queen_h, jack_h, queen_d, jack_d, queen_c, jack_c, Card(Suit.CLUBS, Rank.TEN)]
    p3_hand_cards = [five_s, Card(Suit.HEARTS, Rank.NINE), Card(Suit.HEARTS, Rank.EIGHT), Card(Suit.DIAMONDS, Rank.NINE), Card(Suit.DIAMONDS, Rank.EIGHT), Card(Suit.DIAMONDS, Rank.SEVEN), Card(Suit.DIAMONDS, Rank.SIX), Card(Suit.CLUBS, Rank.NINE), Card(Suit.CLUBS, Rank.EIGHT), Card(Suit.CLUBS, Rank.SEVEN)]
    p4_hand_cards = [joker, queen_s, jack_s, ten_s, Card(Suit.HEARTS, Rank.FIVE), Card(Suit.HEARTS, Rank.SIX), Card(Suit.DIAMONDS, Rank.TEN), Card(Suit.DIAMONDS, Rank.FIVE), Card(Suit.CLUBS, Rank.SIX), Card(Suit.CLUBS, Rank.FOUR)]
    # Ensure no duplicates
    all_cards_pre_deal = p1_hand_cards + p2_hand_cards + p3_hand_cards + p4_hand_cards + kitty_cards_to_use
    assert len(all_cards_pre_deal) == 43
    assert len(set(all_cards_pre_deal)) == 43, "Duplicates in test_full_round_suit_bid_contract_failed hand setup"

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        game.players[1].hand = list(p2_hand_cards)
        game.players[2].hand = list(p3_hand_cards)
        game.players[3].hand = list(p4_hand_cards)
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = [] 

    original_score_round = game._score_round

    def mock_kitty_exchange_contract_failed(declarer):
        if declarer == p1: # P1 is declarer
            declarer.add_cards_to_hand(list(kitty_cards_to_use))
            # P1 discards the kitty cards (h4, d4, c5) as they are likely worse than hand
            cards_to_discard = list(kitty_cards_to_use)
            for card in cards_to_discard:
                if card in declarer.hand:
                    declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            game.kitty = []
    def mock_play_round_contract_failed(declarer):
        if declarer == p1: # P1 bid 6 Spades
            # Simulate P1/P3 winning few tricks (e.g., 3)
            game.players[0].tricks_won_this_round = 2 # P1
            game.players[2].tricks_won_this_round = 1 # P3 (partner)
            game.players[1].tricks_won_this_round = 4 # P2 (opponent)
            game.players[3].tricks_won_this_round = 3 # P4 (opponent)
        original_score_round(declarer)

    team_ac.team_score = 0
    team_bd.team_score = 0
    
    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_6s_others_pass,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_contract_failed,
                         mock_play_round=mock_play_round_contract_failed):
        game.start_new_round()

    # Assertions (remain mostly the same as original test)
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.tricks == 6
    assert game.winning_bid.suit == Suit.SPADES
    assert game.trump_suit == Suit.SPADES

    contracting_team_tricks = team_ac.get_total_tricks_won_this_round()
    assert contracting_team_tricks < 6, f"Contract should fail. Expected < 6 tricks, got {contracting_team_tricks}."
    
    expected_score = -game.winning_bid.points # Should be -40 for 6S
    assert team_ac.team_score == expected_score
    assert team_bd.team_score == 0
    
    assert not game.game_over

def test_full_round_no_trump_bid_contract_made(game_setup):
    game = game_setup
    p1 = game.players[0]
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions (as in original test)
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_s, king_s, queen_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN)
    ace_h, king_h, queen_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.QUEEN)
    ace_d, king_d = Card(Suit.DIAMONDS, Rank.ACE), Card(Suit.DIAMONDS, Rank.KING)
    ace_c, king_c = Card(Suit.CLUBS, Rank.ACE), Card(Suit.CLUBS, Rank.KING)
    s5, h4, c6 = Card(Suit.SPADES, Rank.FIVE), Card(Suit.HEARTS, Rank.FOUR), Card(Suit.CLUBS, Rank.SIX)

    kitty_cards_to_use = [s5, h4, c6]
    game.current_dealer_idx = 2 # P1 bids first

    # --- Define Mocks --- 
    def mock_bid_action_p1_7nt_others_pass(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (7, Suit.NO_TRUMP, BidType.NO_TRUMP)) 
            else: return ("pass", None)
        else: return ("pass", None)

    p1_hand_cards = [joker, ace_s, king_s, ace_h, king_h, ace_d, king_d, ace_c, king_c, Card(Suit.SPADES, Rank.TEN)]
    # Define other player hands ensuring uniqueness and card count (as in original test, simplified for brevity here)
    p2_hand_cards = [queen_s, Card(Suit.SPADES, Rank.NINE), Card(Suit.HEARTS, Rank.TEN), Card(Suit.HEARTS, Rank.NINE), Card(Suit.DIAMONDS, Rank.TEN), Card(Suit.DIAMONDS, Rank.NINE), Card(Suit.CLUBS, Rank.TEN), Card(Suit.CLUBS, Rank.NINE), Card(Suit.CLUBS, Rank.EIGHT), Card(Suit.CLUBS, Rank.SEVEN)]
    p3_hand_cards = [Card(Suit.SPADES, Rank.EIGHT), Card(Suit.SPADES, Rank.SEVEN), Card(Suit.HEARTS, Rank.EIGHT), Card(Suit.HEARTS, Rank.SEVEN), Card(Suit.DIAMONDS, Rank.EIGHT), Card(Suit.DIAMONDS, Rank.SEVEN), Card(Suit.DIAMONDS, Rank.SIX), Card(Suit.CLUBS, Rank.FIVE), Card(Suit.CLUBS, Rank.FOUR), Card(Suit.HEARTS, Rank.SIX)]
    p4_hand_cards = [queen_h, Card(Suit.SPADES, Rank.SIX), Card(Suit.HEARTS, Rank.FIVE), Card(Suit.DIAMONDS, Rank.QUEEN), Card(Suit.DIAMONDS, Rank.JACK), Card(Suit.CLUBS, Rank.QUEEN), Card(Suit.CLUBS, Rank.JACK), Card(Suit.SPADES, Rank.JACK), Card(Suit.DIAMONDS, Rank.FIVE), Card(Suit.DIAMONDS, Rank.FOUR)]
    all_cards_pre_deal = p1_hand_cards + p2_hand_cards + p3_hand_cards + p4_hand_cards + kitty_cards_to_use
    assert len(all_cards_pre_deal) == 43 and len(set(all_cards_pre_deal)) == 43, "Duplicates/wrong count in NT test hand setup"

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        game.players[1].hand = list(p2_hand_cards)
        game.players[2].hand = list(p3_hand_cards)
        game.players[3].hand = list(p4_hand_cards)
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = []

    original_score_round = game._score_round

    def mock_kitty_exchange_nt(declarer):
        if declarer == p1:
            declarer.add_cards_to_hand(list(kitty_cards_to_use))
            # P1 discards the kitty cards (s5, h4, c6) as they are low
            cards_to_discard = list(kitty_cards_to_use)
            for card in cards_to_discard:
                if card in declarer.hand:
                    declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            game.kitty = []
    def mock_play_round_nt_contract_made(declarer):
        if declarer == p1: # P1 bid 7 NT
            # Simulate P1/P3 winning 8 tricks
            game.players[0].tricks_won_this_round = 5 # P1
            game.players[2].tricks_won_this_round = 3 # P3 (partner)
            game.players[1].tricks_won_this_round = 1 # P2 (opponent)
            game.players[3].tricks_won_this_round = 1 # P4 (opponent)
        original_score_round(declarer)

    team_ac.team_score = 0
    team_bd.team_score = 0

    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_7nt_others_pass,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_nt,
                         mock_play_round=mock_play_round_nt_contract_made):
        game.start_new_round()

    # Assertions (remain mostly the same as original test)
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.tricks == 7
    assert game.winning_bid.suit == Suit.NO_TRUMP
    assert game.trump_suit == Suit.NO_TRUMP

    contracting_team_tricks = team_ac.get_total_tricks_won_this_round()
    expected_bid_points = 220 # 7 No Trump
    if contracting_team_tricks >= 7:
        score_to_assert = 250 if contracting_team_tricks == 10 and expected_bid_points < 250 else expected_bid_points
        assert team_ac.team_score == score_to_assert
        assert team_bd.team_score == 0
    else:
        assert team_ac.team_score == -expected_bid_points
        assert team_bd.team_score == 0

    assert not game.game_over

def test_full_round_misere_bid_successful(game_setup):
    game = game_setup
    p1 = game.players[0] # Declarer
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions (as in original test)
    s4, s5, s8 = Card(Suit.SPADES, Rank.FOUR), Card(Suit.SPADES, Rank.FIVE), Card(Suit.SPADES, Rank.EIGHT)
    h4, h5, h9 = Card(Suit.HEARTS, Rank.FOUR), Card(Suit.HEARTS, Rank.FIVE), Card(Suit.HEARTS, Rank.NINE)
    d4, d5, d7 = Card(Suit.DIAMONDS, Rank.FOUR), Card(Suit.DIAMONDS, Rank.FIVE), Card(Suit.DIAMONDS, Rank.SEVEN)
    c4, c5 = Card(Suit.CLUBS, Rank.FOUR), Card(Suit.CLUBS, Rank.FIVE)
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_s, king_s, queen_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN)
    ace_h, king_h, ten_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.TEN)
    ace_d, king_d = Card(Suit.DIAMONDS, Rank.ACE), Card(Suit.DIAMONDS, Rank.KING)
    ace_c, king_c, queen_c = Card(Suit.CLUBS, Rank.ACE), Card(Suit.CLUBS, Rank.KING), Card(Suit.CLUBS, Rank.QUEEN)
    # Other cards for P3, P4
    s6,s7,s9,sJ,s10 = Card(Suit.SPADES, Rank.SIX), Card(Suit.SPADES, Rank.SEVEN), Card(Suit.SPADES, Rank.NINE), Card(Suit.SPADES, Rank.JACK), Card(Suit.SPADES, Rank.TEN)
    h6,h7,h8,hJ,hQ = Card(Suit.HEARTS, Rank.SIX), Card(Suit.HEARTS, Rank.SEVEN), Card(Suit.HEARTS, Rank.EIGHT), Card(Suit.HEARTS, Rank.JACK), Card(Suit.HEARTS, Rank.QUEEN)
    d6,d8,d10,dJ,dQ = Card(Suit.DIAMONDS, Rank.SIX), Card(Suit.DIAMONDS, Rank.EIGHT), Card(Suit.DIAMONDS, Rank.TEN), Card(Suit.DIAMONDS, Rank.JACK), Card(Suit.DIAMONDS, Rank.QUEEN)
    c6,c7,c8,c9,c10,cJ = Card(Suit.CLUBS, Rank.SIX), Card(Suit.CLUBS, Rank.SEVEN), Card(Suit.CLUBS, Rank.EIGHT), Card(Suit.CLUBS, Rank.NINE), Card(Suit.CLUBS, Rank.TEN), Card(Suit.CLUBS, Rank.JACK)

    kitty_cards_to_use = [ace_s, king_h, d7] 
    game.current_dealer_idx = 2 # P1 bids first

    # --- Define Mocks --- 
    def mock_bid_action_p1_misere_others_pass(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (0, None, BidType.MISERE)) 
            else: return ("pass", None)
        else: return ("pass", None)

    p1_hand_cards = [s4, s5, h4, h5, d4, d5, c4, c5, s8, h9]
    p2_hand_cards = [joker, king_s, queen_s, ace_h, ten_h, ace_d, king_d, ace_c, king_c, queen_c]
    p3_hand_cards = [s6, h6, d6, c6, s7, h7, d8, c7, s9, hJ]
    p4_hand_cards = [s10, sJ, hQ, h8, d10, dJ, dQ, c10, cJ, c8]
    all_cards_pre_deal = p1_hand_cards + p2_hand_cards + p3_hand_cards + p4_hand_cards + kitty_cards_to_use
    assert len(all_cards_pre_deal) == 43 and len(set(all_cards_pre_deal)) == 43, "Duplicates/wrong count in Misere Success hand setup"

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        game.players[1].hand = list(p2_hand_cards)
        game.players[2].hand = list(p3_hand_cards)
        game.players[3].hand = list(p4_hand_cards)
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = []

    original_score_round = game._score_round

    def mock_kitty_exchange_misere_successful(declarer):
        if declarer == p1:
            declarer.add_cards_to_hand(list(kitty_cards_to_use)) # Gets AS, KH, D7
            # P1 has S4,S5,H4,H5,D4,D5,C4,C5,S8,H9 + AS,KH,D7
            # Expected discard for Misere: AS, KH, S8 (or H9, D7 - depends on exact strategy)
            # The game's _handle_kitty_exchange has Misere logic to discard highest non-Joker.
            # We can rely on that or force discards.
            # Forcing discard for test predictability:
            cards_to_discard = [ace_s, king_h, s8] # Assuming S8 is higher than H9, D7 in a sort
            temp_hand_for_discard = sorted(declarer.hand, key=lambda c: game._get_card_strength_in_trick(c, None, Suit.NO_TRUMP), reverse=True)
            actual_discards = temp_hand_for_discard[:3]
            # print(f"MISERE MOCK: P1 Hand before discard: {declarer.hand}")
            # print(f"MISERE MOCK: P1 Kitty received: {kitty_cards_to_use}")
            # print(f"MISERE MOCK: P1 Auto-selected discards by strength: {actual_discards}")

            for card in actual_discards: # Discard 3 highest cards as per Misere rule
                if card in declarer.hand:
                    declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            game.kitty = []
            # print(f"MISERE MOCK: P1 Hand after discard: {declarer.hand}")
    def mock_play_round_misere_successful(declarer):
        if declarer == p1: # P1 bid Misere
            # Simulate P1 (declarer) winning 0 tricks
            game.players[0].tricks_won_this_round = 0
            # Distribute other tricks
            game.players[1].tricks_won_this_round = 5
            game.players[2].tricks_won_this_round = 0 # Partner
            game.players[3].tricks_won_this_round = 5
        original_score_round(declarer)

    team_ac.team_score = 0
    team_bd.team_score = 0

    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_misere_others_pass,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_misere_successful,
                         mock_play_round=mock_play_round_misere_successful):
        game.start_new_round()

    # Assertions (remain mostly the same as original test)
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.bid_type == BidType.MISERE
    assert game.trump_suit == Suit.NO_TRUMP

    declarer_tricks_won = game.players[0].tricks_won_this_round
    misere_points = 250
    if declarer_tricks_won == 0:
        assert team_ac.team_score == misere_points
        assert team_bd.team_score == 0
    else:
        assert team_ac.team_score == -misere_points
        assert team_bd.team_score == 0
    
    if abs(team_ac.team_score) < 500 and abs(team_bd.team_score) < 500:
        assert not game.game_over

def test_full_round_misere_bid_failed(game_setup):
    game = game_setup
    p1 = game.players[0] # Declarer
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions (as in original test)
    joker, ace_s, king_s, queen_s = Card(Suit.NO_TRUMP, Rank.JOKER), Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.QUEEN)
    four_c, four_d, four_h = Card(Suit.CLUBS, Rank.FOUR), Card(Suit.DIAMONDS, Rank.FOUR), Card(Suit.HEARTS, Rank.FOUR)
    five_s, five_c, five_d, five_h = Card(Suit.SPADES, Rank.FIVE), Card(Suit.CLUBS, Rank.FIVE), Card(Suit.DIAMONDS, Rank.FIVE), Card(Suit.HEARTS, Rank.FIVE)
    six_c, six_d = Card(Suit.CLUBS, Rank.SIX), Card(Suit.DIAMONDS, Rank.SIX)
    four_s = Card(Suit.SPADES, Rank.FOUR)
    six_h, seven_c, seven_d, seven_h = Card(Suit.HEARTS, Rank.SIX), Card(Suit.CLUBS, Rank.SEVEN), Card(Suit.DIAMONDS, Rank.SEVEN), Card(Suit.HEARTS, Rank.SEVEN)
    eight_c, eight_d, eight_h = Card(Suit.CLUBS, Rank.EIGHT), Card(Suit.DIAMONDS, Rank.EIGHT), Card(Suit.HEARTS, Rank.EIGHT)
    nine_c, nine_d = Card(Suit.CLUBS, Rank.NINE), Card(Suit.DIAMONDS, Rank.NINE)
    ten_s, nine_s, eight_s, seven_s = Card(Suit.SPADES, Rank.TEN), Card(Suit.SPADES, Rank.NINE), Card(Suit.SPADES, Rank.EIGHT), Card(Suit.SPADES, Rank.SEVEN)
    king_c, queen_c, jack_c, ten_c = Card(Suit.CLUBS, Rank.KING), Card(Suit.CLUBS, Rank.QUEEN), Card(Suit.CLUBS, Rank.JACK), Card(Suit.CLUBS, Rank.TEN)
    king_h, queen_h = Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.QUEEN)
    six_s = Card(Suit.SPADES, Rank.SIX)
    nine_h, ten_h, jack_h = Card(Suit.HEARTS, Rank.NINE), Card(Suit.HEARTS, Rank.TEN), Card(Suit.HEARTS, Rank.JACK)
    ace_d, king_d, queen_d, jack_d, ten_d, ace_h_p4 = Card(Suit.DIAMONDS, Rank.ACE), Card(Suit.DIAMONDS, Rank.KING), Card(Suit.DIAMONDS, Rank.QUEEN), Card(Suit.DIAMONDS, Rank.JACK), Card(Suit.DIAMONDS, Rank.TEN), Card(Suit.HEARTS, Rank.ACE)

    game.current_dealer_idx = 2 # P1 bids first

    # --- Define Mocks --- 
    def mock_bid_action_p1_misere_others_pass(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (0, None, BidType.MISERE))
            else: return ("pass", None)
        else: return ("pass", None)

    p1_hand_cards = [ace_s, four_c, four_d, four_h, five_s, five_c, five_d, five_h, six_c, six_d]
    kitty_cards_to_use = [joker, king_s, queen_s] # P1 discards these
    p2_hand_cards = [four_s, six_h, seven_c, seven_d, seven_h, eight_c, eight_d, eight_h, nine_c, nine_d]
    p3_hand_cards = [ten_s, nine_s, eight_s, seven_s, king_c, queen_c, jack_c, ten_c, king_h, queen_h]
    p4_hand_cards = [six_s, nine_h, ten_h, jack_h, ace_d, king_d, queen_d, jack_d, ten_d, ace_h_p4]
    all_cards_pre_deal = p1_hand_cards + p2_hand_cards + p3_hand_cards + p4_hand_cards + kitty_cards_to_use
    assert len(all_cards_pre_deal) == 43 and len(set(all_cards_pre_deal)) == 43, "Duplicates/wrong count in Misere Failed hand setup"

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        game.players[1].hand = list(p2_hand_cards)
        game.players[2].hand = list(p3_hand_cards)
        game.players[3].hand = list(p4_hand_cards)
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = []

    original_score_round = game._score_round

    def mock_kitty_exchange_misere_failed(declarer):
        if declarer == p1:
            declarer.add_cards_to_hand(list(kitty_cards_to_use))
            # P1 gets Joker, KS, QS. Original hand has AS.
            # Game logic for Misere discard should discard Joker, KS, QS.
            # So P1 is left with AS, 4c,4d,4h, 5s,5c,5d,5h, 6c,6d
            # This test expects P1 to be forced to play AS and win a trick.
            
            # Simulate the game's auto-discard for Misere (highest 3 non-Joker cards, or Joker if it's one of highest)
            # In this case, Joker, KS, QS are picked up. Original hand has AS.
            # After adding kitty, hand is: AS, 4c,4d,4h, 5s,5c,5d,5h, 6c,6d, Joker, KS, QS
            # Highest are: Joker, AS, KS (or QS). So these should be discarded.
            # Let's ensure AS is kept for the test's purpose.
            temp_hand = sorted(declarer.hand, key=lambda c: game._get_card_strength_in_trick(c, None, Suit.NO_TRUMP), reverse=True)
            
            # This test is designed so P1 is forced to keep Ace of Spades.
            # The auto-discard in game.py would pick Joker, King S, Queen S.
            # So P1 is left with Ace S and all the low cards.
            cards_to_remove_for_test = [joker, king_s, queen_s]
            for card in cards_to_remove_for_test:
                if card in declarer.hand:
                     declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            assert ace_s in declarer.hand # Ensure Ace of Spades is kept
            game.kitty = []
    def mock_play_round_misere_failed(declarer):
        if declarer == p1: # P1 bid Misere
            # Simulate P1 (declarer) winning 1 trick (the Ace of Spades)
            game.players[0].tricks_won_this_round = 1 
            # Distribute other tricks
            game.players[1].tricks_won_this_round = 3
            game.players[2].tricks_won_this_round = 3 # Partner
            game.players[3].tricks_won_this_round = 3
        original_score_round(declarer)

    team_ac.team_score = 0
    team_bd.team_score = 0

    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_misere_others_pass,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_misere_failed,
                         mock_play_round=mock_play_round_misere_failed):
        game.start_new_round()

    # Assertions
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.bid_type == BidType.MISERE
    assert game.trump_suit == Suit.NO_TRUMP

    declarer_tricks_won = game.players[0].tricks_won_this_round
    assert declarer_tricks_won > 0, f"Misere contract should fail. Expected P1 to win >0 tricks, got {declarer_tricks_won}."

    misere_penalty = -250
    assert team_ac.team_score == misere_penalty
    assert team_bd.team_score == 0
    
    if abs(team_ac.team_score) < 500 and abs(team_bd.team_score) < 500:
        assert not game.game_over

def test_full_round_open_misere_bid_successful(game_setup):
    game = game_setup
    p1 = game.players[0] # Declarer
    team_ac = game.teams[0]
    team_bd = game.teams[1]

    # Card definitions
    s4, s5, sQ = Card(Suit.SPADES, Rank.FOUR), Card(Suit.SPADES, Rank.FIVE), Card(Suit.SPADES, Rank.QUEEN)
    h4, h5 = Card(Suit.HEARTS, Rank.FOUR), Card(Suit.HEARTS, Rank.FIVE)
    d4, d5 = Card(Suit.DIAMONDS, Rank.FOUR), Card(Suit.DIAMONDS, Rank.FIVE)
    c4, c5, c6, c7 = Card(Suit.CLUBS, Rank.FOUR), Card(Suit.CLUBS, Rank.FIVE), Card(Suit.CLUBS, Rank.SIX), Card(Suit.CLUBS, Rank.SEVEN)
    joker = Card(Suit.NO_TRUMP, Rank.JOKER)
    ace_s, king_s, jack_s = Card(Suit.SPADES, Rank.ACE), Card(Suit.SPADES, Rank.KING), Card(Suit.SPADES, Rank.JACK)
    ace_h, king_h, ten_h = Card(Suit.HEARTS, Rank.ACE), Card(Suit.HEARTS, Rank.KING), Card(Suit.HEARTS, Rank.TEN)
    ace_d, king_d = Card(Suit.DIAMONDS, Rank.ACE), Card(Suit.DIAMONDS, Rank.KING)
    ace_c, king_c, queen_c = Card(Suit.CLUBS, Rank.ACE), Card(Suit.CLUBS, Rank.KING), Card(Suit.CLUBS, Rank.QUEEN)
    s6,s7,s8,s9,s10 = Card(Suit.SPADES, Rank.SIX),Card(Suit.SPADES, Rank.SEVEN),Card(Suit.SPADES, Rank.EIGHT),Card(Suit.SPADES, Rank.NINE),Card(Suit.SPADES, Rank.TEN)
    h6,h7,h8,h9,hJ = Card(Suit.HEARTS, Rank.SIX),Card(Suit.HEARTS, Rank.SEVEN),Card(Suit.HEARTS, Rank.EIGHT),Card(Suit.HEARTS, Rank.NINE),Card(Suit.HEARTS, Rank.JACK)
    d6,d7,d8,d9,d10,dJ = Card(Suit.DIAMONDS, Rank.SIX),Card(Suit.DIAMONDS, Rank.SEVEN),Card(Suit.DIAMONDS, Rank.EIGHT),Card(Suit.DIAMONDS, Rank.NINE),Card(Suit.DIAMONDS, Rank.TEN),Card(Suit.DIAMONDS, Rank.JACK)
    c8,c9,c10,cJ = Card(Suit.CLUBS, Rank.EIGHT),Card(Suit.CLUBS, Rank.NINE),Card(Suit.CLUBS, Rank.TEN),Card(Suit.CLUBS, Rank.JACK)

    kitty_cards_to_use = [ace_s, king_h, sQ] 
    game.current_dealer_idx = 2

    # --- Define Mocks --- 
    def mock_bid_action_p1_open_misere(player_obj):
        if player_obj == game.players[0]:
            if game.highest_bid_this_round is None:
                return ("bid", (0, None, BidType.OPEN_MISERE))
            else: return ("pass", None)
        else: return ("pass", None)

    p1_hand_cards = [s4, s5, h4, h5, d4, d5, c4, c5, c6, c7]
    p2_hand_cards = [joker, king_s, jack_s, ace_h, ten_h, ace_d, king_d, ace_c, king_c, queen_c]
    p3_hand_cards = [s6, s7, h6, h7, d6, d7, c8, c9, s8, h8]
    p4_hand_cards = [s9, s10, h9, hJ, d8, d9, d10, c10, cJ, dJ]
    all_cards_pre_deal = p1_hand_cards + p2_hand_cards + p3_hand_cards + p4_hand_cards + kitty_cards_to_use
    assert len(all_cards_pre_deal) == 43 and len(set(all_cards_pre_deal)) == 43, "Duplicates/wrong count in Open Misere hand setup"

    def mock_deal_cards_custom():
        for p_ in game.players: p_.reset_for_new_round()
        for t_ in game.teams: t_.reset_for_new_round()
        game.players[0].hand = list(p1_hand_cards)
        game.players[1].hand = list(p2_hand_cards)
        game.players[2].hand = list(p3_hand_cards)
        game.players[3].hand = list(p4_hand_cards)
        game.kitty = list(kitty_cards_to_use)
        game.deck.cards = []

    original_score_round = game._score_round

    def mock_kitty_exchange_open_misere(declarer):
        if declarer == p1:
            declarer.add_cards_to_hand(list(kitty_cards_to_use)) 
            cards_to_discard = [ace_s, king_h, sQ] # P1 discards these high cards
            for card in cards_to_discard:
                if card in declarer.hand:
                    declarer.hand.remove(card)
            assert len(declarer.hand) == 10
            game.kitty = []
            # For Open Misere, hand is exposed. Not strictly needed for mock if play_round is fully mocked.
            # print(f"OPEN MISERE MOCK: {declarer.name}'s hand is exposed: {declarer.hand}") 

    def mock_play_round_open_misere_successful(declarer):
        if declarer == p1:
            game.players[0].tricks_won_this_round = 0
            game.players[1].tricks_won_this_round = 5 
            game.players[2].tricks_won_this_round = 0 
            game.players[3].tricks_won_this_round = 5
        original_score_round(declarer)

    team_ac.team_score = 0
    team_bd.team_score = 0

    with FullRoundMocker(game,
                         mock_bid_action=mock_bid_action_p1_open_misere,
                         mock_deal_cards=mock_deal_cards_custom,
                         mock_kitty_exchange=mock_kitty_exchange_open_misere,
                         mock_play_round=mock_play_round_open_misere_successful):
        game.start_new_round()

    # Assertions
    assert game.winning_bid is not None
    assert game.winning_bid.player == p1
    assert game.winning_bid.bid_type == BidType.OPEN_MISERE
    assert game.trump_suit == Suit.NO_TRUMP

    declarer_tricks_won = game.players[0].tricks_won_this_round
    open_misere_points = 500 
    if declarer_tricks_won == 0:
        assert team_ac.team_score == open_misere_points
        assert team_bd.team_score == 0
        assert game.game_over
    else:
        assert team_ac.team_score == -open_misere_points
        assert team_bd.team_score == 0
        assert game.game_over

# More tests to come for full bidding round, kitty exchange, playing tricks, scoring etc. 