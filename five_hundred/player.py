from typing import List, Optional
from .card import Card, Suit, Rank

class Player:
    def __init__(self, name: str):
        self.name: str = name
        self.hand: List[Card] = []
        self.score: int = 0 # Individual score, team score might be managed elsewhere
        self.tricks_won_this_round: int = 0

    def add_card_to_hand(self, card: Card):
        """Adds a single card to the player's hand."""
        self.hand.append(card)

    def add_cards_to_hand(self, cards: List[Card]):
        """Adds multiple cards to the player's hand."""
        self.hand.extend(cards)

    def play_card(self, card_to_play: Card) -> Card:
        """Removes and returns a specific card from the player's hand."""
        if card_to_play not in self.hand:
            raise ValueError(f"Card {card_to_play} not in player's hand.")
        self.hand.remove(card_to_play)
        return card_to_play

    def sort_hand(self, trump_suit: Optional[Suit] = None, game_suit_order: Optional[List[Suit]] = None):
        """Sorts the player's hand. 
        Can be sorted by a specific suit order, then by rank (descending).
        If trump_suit is provided, trump cards come first, then other suits.
        Joker is usually the highest card.
        Note: Detailed card ranking (Bowers, Joker based on trump) will be complex 
        and might be better handled by a separate utility or within the Game logic 
        when determining playable cards or trick winners.
        For now, a simple sort by suit then rank.
        """
        # This is a placeholder for a more sophisticated sorting logic
        # that considers trump, bowers, joker value etc.
        # Standard sort order: Spades, Clubs, Diamonds, Hearts (example)
        # For now, just sort by suit enum order then by a predefined rank order.
        
        # Define a basic rank order (Ace high, Joker highest)
        # This will need to be dynamic based on trump suit in the actual game.
        rank_order = {rank: i for i, rank in enumerate(list(Rank))} # Ensure Ace is higher than King

        def sort_key(card: Card):
            suit_priority = list(Suit).index(card.suit)
            rank_priority = rank_order.get(card.rank, -1) # Joker might need special handling
            if card.rank == Rank.JOKER: # Make Joker highest
                return (-1, -1) # Arbitrary high priority
            return (suit_priority, -rank_priority) # -rank_priority for descending rank

        self.hand.sort(key=sort_key)


    def reset_for_new_round(self):
        """Resets hand and tricks won for a new round."""
        self.hand = []
        self.tricks_won_this_round = 0

    def increment_score(self, points: int):
        self.score += points

    def increment_tricks_won(self): 
        self.tricks_won_this_round += 1

    def __repr__(self):
        return f"Player({self.name}, Score: {self.score}, Hand: {len(self.hand)} cards, Tricks Won: {self.tricks_won_this_round})"

    def __str__(self):
        return f"{self.name} (Score: {self.score})" 