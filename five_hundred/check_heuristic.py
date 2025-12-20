from five_hundred.card import Card, Suit, Rank
from five_hundred.heuristic import calculate_hand_strength

# Test Case 1: High Trump Hand
trump_suit = Suit.SPADES
hand1 = [
    Card(Suit.NO_TRUMP, Rank.JOKER), # 25
    Card(Suit.SPADES, Rank.JACK),    # Right Bower -> 20
    Card(Suit.CLUBS, Rank.JACK),     # Left Bower -> 15
    Card(Suit.SPADES, Rank.ACE),     # 10
    Card(Suit.HEARTS, Rank.ACE)      # 4
]
# Expected: 25 + 20 + 15 + 10 + 4 = 74
score1 = calculate_hand_strength(hand1, trump_suit)
print(f"Hand 1 Score (Trumps): {score1} (Expected ~74)")

# Test Case 2: No Trump High Cards
hand2 = [
    Card(Suit.NO_TRUMP, Rank.JOKER), # 15 (NT)
    Card(Suit.SPADES, Rank.ACE),     # 4
    Card(Suit.HEARTS, Rank.ACE),     # 4
    Card(Suit.CLUBS, Rank.ACE),      # 4
    Card(Suit.DIAMONDS, Rank.ACE)    # 4
]
# Expected: 15 + 4*4 = 31
score2 = calculate_hand_strength(hand2, None)
print(f"Hand 2 Score (NT): {score2} (Expected ~31)")

# Test Case 3: Misere
hand3 = [
    Card(Suit.SPADES, Rank.FOUR),  # +5
    Card(Suit.CLUBS, Rank.FIVE),   # +5
    Card(Suit.HEARTS, Rank.ACE),   # High penalty? (14-7)*2 = 14 penalty -> -14
    Card(Suit.NO_TRUMP, Rank.JOKER) # -50
]
# Expected: 5 + 5 - 14 - 50 = -54
score3 = calculate_hand_strength(hand3, None, is_misere=True)
print(f"Hand 3 Score (Misere): {score3} (Expected ~-54)")
