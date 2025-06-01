from typing import List, Optional, Dict, Tuple
from enum import Enum, auto
from .card import Card, Suit, Rank
from .deck import Deck
from .player import Player
from .team import Team
from .bid import Bid, BidType, MISERE_POINTS, OPEN_MISERE_POINTS # Assuming Bid class is in bid.py

class Game:
    def __init__(self, player_names: List[str], team_names: List[str]):
        if len(player_names) != 4:
            raise ValueError("Standard 500 game requires 4 players.")
        if len(team_names) != 2:
            raise ValueError("Standard 500 game requires 2 teams.")

        self.players: List[Player] = [Player(name) for name in player_names]
        # Assign players to teams: P0,P2 to T0; P1,P3 to T1 (standard partnership)
        self.teams: List[Team] = [
            Team(team_names[0], [self.players[0], self.players[2]]),
            Team(team_names[1], [self.players[1], self.players[3]])
        ]
        self.deck: Deck = Deck()
        self.kitty: List[Card] = []
        self.current_dealer_idx: int = 0 # Player index
        self.current_bidder_idx: int = 0 # Player index
        self.trump_suit: Optional[Suit] = None
        self.winning_bid: Optional[Bid] = None
        self.game_over: bool = False
        self.game_point_target: int = 500 # Standard game point

        # Bidding specific state - may be better to reset per round
        self.highest_bid_this_round: Optional[Bid] = None
        self.bids_this_round: List[Bid] = [] # History of bids in the current auction
        self.player_has_bid_this_round: Dict[Player, bool] = {player: False for player in self.players}
        self.player_has_passed_auction: Dict[Player, bool] = {player: False for player in self.players}
        self.passes_this_round: int = 0 # Number of consecutive passes in current bidding sequence
        self.last_bidder: Optional[Player] = None # The player who made the current highest_bid_this_round

    def _deal_cards(self):
        """Deals cards to players and the kitty according to 500 rules."""
        self.deck = Deck() # Get a fresh, shuffled deck
        self.deck.shuffle()
        self.kitty = []

        for player in self.players:
            player.reset_for_new_round() # Clear hands and round tricks
        for team in self.teams:
            team.reset_for_new_round() # Clear team bid status and player states

        # Dealing pattern: 3 to each player, 1 to kitty, 4 to each, 1 to kitty, 3 to each, 1 to kitty
        # Total 10 cards per player, 3 to kitty.
        deal_sequence = [(3, 'player'), (1, 'kitty'), 
                         (4, 'player'), (1, 'kitty'), 
                         (3, 'player'), (1, 'kitty')]

        for num_cards, recipient_type in deal_sequence:
            if recipient_type == 'kitty':
                self.kitty.extend(self.deck.deal(num_cards))
            elif recipient_type == 'player':
                for player in self.players:
                    player.add_cards_to_hand(self.deck.deal(num_cards))
        
        # Verify deal
        # (Standard 4 player game, 43 card deck)
        # Each player gets 10 cards = 40 cards. Kitty gets 3 cards.
        # Total cards dealt = 40 + 3 = 43 cards.
        assert len(self.kitty) == 3
        for player in self.players:
            assert len(player.hand) == 10
        assert len(self.deck) == 0 # Deck should be empty after dealing

    def _determine_next_player_idx(self, current_player_idx: int) -> int:
        """Gets the index of the next player in clockwise order."""
        return (current_player_idx + 1) % len(self.players)

    def start_new_round(self):
        """Starts a new round: sets dealer, deals cards, starts bidding."""
        if self.game_over:
            print("Game is over. Cannot start a new round.")
            return

        print(f"\n--- Starting New Round ---")
        # Rotate dealer: current_dealer_idx is the dealer from the *previous* round.
        # The new dealer for *this* round is the next player.
        self.current_dealer_idx = self._determine_next_player_idx(self.current_dealer_idx)
        
        dealer = self.players[self.current_dealer_idx]
        print(f"{dealer.name} is the dealer.")

        self._deal_cards()
        # For testing, show hands:
        # for p in self.players: print(f"{p.name}'s hand: {p.hand}")
        # print(f"Kitty: {self.kitty}")

        self.winning_bid = None
        self.trump_suit = None
        self.bids_this_round = []
        self.highest_bid_this_round = None
        self.player_has_bid_this_round = {p: False for p in self.players}
        self.player_has_passed_auction = {p: False for p in self.players}
        self.passes_this_round = 0 # Reset passes for the new bidding round

        # Bidding starts with the player to the left of the dealer.
        bidder_idx = self._determine_next_player_idx(self.current_dealer_idx)
        print(f"Bidding will start with {self.players[bidder_idx].name}.")
        self.run_bidding_round(bidder_idx) # Activate the bidding round

    # --- Bidding Phase Methods (to be expanded) ---
    def player_attempts_bid(self, player: Player, tricks: int, suit: Optional[Suit], bid_type: BidType) -> bool:
        """Allows a player to attempt to make a bid. Returns True if successful."""
        if self.player_has_passed_auction[player]:
            print(f"{player.name} cannot bid after passing.")
            return False

        try:
            potential_bid = Bid(player, tricks, suit, bid_type)
        except ValueError as e:
            print(f"Invalid bid parameters for {player.name}: {e}")
            return False

        if self.highest_bid_this_round is None or potential_bid > self.highest_bid_this_round:
            # Rule: A player who has bid may only bid again if there has been an intervening bid.
            # This means they cannot bid if they are already the self.last_bidder
            if self.last_bidder == player:
                print(f"{player.name}, you cannot bid again without an intervening bid.")
                return False
            
            print(f"{player.name} bids {potential_bid.tricks} {potential_bid.suit.value if potential_bid.suit else potential_bid.bid_type.value} (Points: {potential_bid.points})")
            self.highest_bid_this_round = potential_bid
            self.bids_this_round.append(potential_bid)
            self.player_has_bid_this_round[player] = True # Mark that this player has made a bid
            self.last_bidder = player # This player is now the one holding the highest bid
            self.passes_this_round = 0 # Successful bid resets consecutive passes
            return True
        else:
            print(f"{player.name}, your bid of {potential_bid.points} pts is not higher than current bid of {self.highest_bid_this_round.points} pts.")
            return False

    def player_passes_bid(self, player: Player):
        """Handles a player passing."""
        print(f"{player.name} passes.")
        self.player_has_passed_auction[player] = True
        self.passes_this_round += 1 # Increment passes when a player formally passes

    def _get_player_bid_action(self, player: Player) -> Tuple[str, Optional[Tuple]]:
        """
        Placeholder for getting player's bid or pass action.
        In a real game, this would involve UI/input.
        For simulation/testing, we can predefine actions or use simple AI.
        Returns:
            A tuple: (action_type: str, action_params: Optional[tuple])
            action_type: "bid" or "pass"
            action_params: (tricks, suit, bid_type) if action_type is "bid", else None
        """
        # ---- Player Action Simulation (to be replaced by actual input/AI) ----
        # Example: Player 0 bids 6S if no current bid, others pass.
        # This simulation needs to be more dynamic for proper testing of the auction.
        if self.highest_bid_this_round is None:
            if player == self.players[0]: # First player to bid (if P0 is to left of dealer)
                print(f"SIM: {player.name} considering initial bid.")
                # Simple initial bid for P0
                return ("bid", (6, Suit.SPADES, BidType.SUIT_TRUMP))
            else:
                print(f"SIM: {player.name} considering pass (no initial bid from P0).")
                return ("pass", None)
        else:
            # If there's a bid, other players will pass in this simple simulation
            # A real AI would decide whether to overbid.
            if player != self.last_bidder: # Don't let last bidder pass immediately
                 print(f"SIM: {player.name} considering pass over existing bid.")
                 return ("pass", None)
            else: # Last bidder's turn again (after others passed or bid)
                # This situation should be handled by the re-bidding rule in player_attempts_bid
                # For simulation, if it's last_bidder's turn again, they also pass (ending auction)
                print(f"SIM: {player.name} (last bidder) passes as others passed back.")
                return ("pass", None)

        # Fallback: pass
        # print(f"SIM: {player.name} defaults to pass.")
        # return ("pass", None)

    def run_bidding_round(self, starting_bidder_idx: int):
        """Manages the entire bidding auction among players."""
        print("\n--- Bidding Phase ---")
        num_players = len(self.players)
        current_bidder_idx = starting_bidder_idx
        
        bidding_active = True
        consecutive_passes_since_last_bid = 0
        total_passes_this_auction = 0 # Tracks total passes to detect if all 4 pass initially

        while bidding_active:
            current_player = self.players[current_bidder_idx]
            action_taken_this_turn = False

            if self.player_has_passed_auction[current_player]:
                print(f"{current_player.name} has already passed. Passing automatically.")
                # No need to call self.player_passes_bid() again, already marked.
                # It still counts as a pass for ending the auction.
                consecutive_passes_since_last_bid += 1
                total_passes_this_auction +=1 # Still counts towards all players passing
                action_taken_this_turn = True
            else:
                print(f"\nIt is {current_player.name}'s turn to bid.")
                # --- Get Player Action (Bid or Pass) ---
                # This is where you'd get input from the player or AI.
                # Using placeholder for now.
                action_type, action_params = self._get_player_bid_action(current_player)
                # --- End Get Player Action ---

                if action_type == "bid":
                    tricks, suit, bid_type = action_params
                    if self.player_attempts_bid(current_player, tricks, suit, bid_type):
                        consecutive_passes_since_last_bid = 0 # Successful bid resets passes
                        total_passes_this_auction = 0 # A bid means not all passed
                        action_taken_this_turn = True
                    else:
                        # Bid attempt failed (e.g., too low, already passed, tried to rebid self)
                        # Treat as a pass for auction flow, player might choose to pass formally next if applicable
                        print(f"{current_player.name}'s bid attempt failed. Turn continues (player might pass or try valid bid).")
                        # Forcing a pass here if bid fails for simplicity of simulation flow.
                        # In a real game, they'd get another chance to make a *valid* bid or pass.
                        self.player_passes_bid(current_player)
                        consecutive_passes_since_last_bid += 1
                        total_passes_this_auction +=1
                        action_taken_this_turn = True

                elif action_type == "pass":
                    self.player_passes_bid(current_player)
                    consecutive_passes_since_last_bid += 1
                    total_passes_this_auction +=1
                    action_taken_this_turn = True
            
            if not action_taken_this_turn:
                # This case should ideally not be reached if _get_player_bid_action always returns a valid action
                # or if a failed bid is handled. For safety, assume pass.
                print(f"Warning: No action taken by {current_player.name}, defaulting to pass.")
                self.player_passes_bid(current_player)
                consecutive_passes_since_last_bid += 1
                total_passes_this_auction +=1

            # Check auction end conditions
            # 1. A bid is on the table, and 3 consecutive players passed since that bid.
            if self.highest_bid_this_round is not None and consecutive_passes_since_last_bid >= num_players - 1:
                self.winning_bid = self.highest_bid_this_round
                bidding_active = False
                print(f"--- Bidding Ended --- Winner: {self.winning_bid.player.name} with {self.winning_bid}")
            # 2. No bid has been made, and all players have had a chance to act and passed.
            #    total_passes_this_auction will be num_players if everyone passes in sequence.
            elif self.highest_bid_this_round is None and total_passes_this_auction >= num_players:
                print("All players passed. Round is dead.")
                self.winning_bid = None 
                bidding_active = False
            
            if not bidding_active:
                break

            current_bidder_idx = self._determine_next_player_idx(current_bidder_idx)
            # Loop continues until bidding_active is false.

        if self.winning_bid:
            self.trump_suit = self.winning_bid.suit if self.winning_bid.bid_type != BidType.NO_TRUMP else Suit.NO_TRUMP
            # Handle Misere/Open Misere trump (effectively NO_TRUMP for card play, Joker highest)
            if self.winning_bid.bid_type == BidType.MISERE or self.winning_bid.bid_type == BidType.OPEN_MISERE:
                self.trump_suit = Suit.NO_TRUMP # Joker is the only trump
            
            declarer = self.winning_bid.player
            print(f"{declarer.name} won the bid with {self.winning_bid.tricks} {self.winning_bid.suit.value if self.winning_bid.suit else self.winning_bid.bid_type.value}.")
            if self.trump_suit:
                print(f"Trump suit is {self.trump_suit.value}.")
            self._handle_kitty_exchange(declarer)
        else:
            print("No winning bid. Round ends. (Consider re-deal or next dealer)")
            # Optionally: self.start_new_round() or pass to next dealer automatically

    def _handle_kitty_exchange(self, declarer: Player):
        """Allows the declarer to exchange cards with the kitty, with a basic discard strategy."""
        print(f"\n--- Kitty Exchange Phase ---")
        print(f"{declarer.name} is exchanging with the kitty.")
        print(f"Kitty contains: {self.kitty}")
        
        declarer.add_cards_to_hand(self.kitty)
        self.kitty = [] # Kitty is now empty
        # print(f"{declarer.name}'s hand before discard (13 cards): {declarer.hand}")
        declarer.sort_hand() # Sorts Joker > Trumps (by rank) > Other suits (by rank)
        print(f"{declarer.name}'s sorted hand (13 cards): {declarer.hand}")

        num_to_discard = len(declarer.hand) - 10
        discards: List[Card] = []

        if num_to_discard <= 0: # Should not happen with 3 kitty cards
            print(f"{declarer.name} has 10 or fewer cards, no discard needed.")
        elif self.winning_bid.bid_type in [BidType.MISERE, BidType.OPEN_MISERE]:
            # Misere discard strategy: discard highest cards
            # Hand is sorted Joker > Ace > King ... (effectively highest to lowest)
            # So, pop from the beginning of the sorted list (which are the highest cards)
            print(f"SIM: {declarer.name} (Misere bid) discarding highest cards.")
            for _ in range(num_to_discard):
                if declarer.hand:
                    discards.append(declarer.hand.pop(0)) # Pop from front (highest)
        else:
            # Suit or No-Trump bid discard strategy
            print(f"SIM: {declarer.name} (Suit/NT bid) discarding strategically.")
            temp_hand = list(declarer.hand) # Work with a copy
            
            trumps_in_hand: List[Card] = []
            non_trumps_in_hand: List[Card] = []

            # Identify trumps (Joker, Bowers, cards of trump suit)
            # Note: self.trump_suit is set before this method is called.
            # For No_Trump bids, self.trump_suit is Suit.NO_TRUMP.
            # Joker is always a trump in effect, regardless of self.trump_suit for actual suit bids.

            actual_trump_suit_for_play = self.trump_suit
            if self.winning_bid.bid_type == BidType.NO_TRUMP or \
               self.winning_bid.bid_type == BidType.MISERE or \
               self.winning_bid.bid_type == BidType.OPEN_MISERE:
                actual_trump_suit_for_play = Suit.NO_TRUMP # Joker is the only effective trump

            for card in temp_hand:
                is_trump_card = False
                if card.rank == Rank.JOKER:
                    is_trump_card = True
                elif actual_trump_suit_for_play != Suit.NO_TRUMP:
                    if card.suit == actual_trump_suit_for_play:
                        is_trump_card = True
                    elif card.rank == Rank.JACK: # Check for Bowers
                        left_bower_suit = None
                        if actual_trump_suit_for_play == Suit.SPADES: left_bower_suit = Suit.CLUBS
                        elif actual_trump_suit_for_play == Suit.CLUBS: left_bower_suit = Suit.SPADES
                        elif actual_trump_suit_for_play == Suit.DIAMONDS: left_bower_suit = Suit.HEARTS
                        elif actual_trump_suit_for_play == Suit.HEARTS: left_bower_suit = Suit.DIAMONDS
                        if card.suit == left_bower_suit:
                            is_trump_card = True 
               
                if is_trump_card:
                    trumps_in_hand.append(card)
                else:
                    non_trumps_in_hand.append(card)
            
            # Sort non-trumps: lowest to highest (for easier pop from end)
            # Player.sort_hand sorts high to low. We need to define card_value for sorting or reverse.
            # For simplicity with current sort: Player.sort_hand sorts Ace high.
            # So the end of non_trumps_in_hand (if sorted by player.sort_hand logic) would be lowest.
            # Let's use a simple rank value for sorting discards (lower is better to discard)
            def get_card_discard_value(c: Card, is_misere: bool) -> int:
                # For Misere, higher value is better to discard.
                # For Trump/NT, lower value is better to discard (among non-trumps or low trumps).
                # This needs to align with how Player.sort_hand works or be independent.
                # Player.sort_hand puts Joker first, then suits, then rank high-low.
                # So, to discard low non-trumps, we want to pick from the *end* of a sorted list of non-trumps.
                # To discard low trumps, from the *end* of a sorted list of trumps (excluding Joker/Bowers if possible).
                
                # Simplified: Use default sort order (Ace high, Joker highest)
                # Non-trumps: discard from the end of the sorted list (lowest non-trumps)
                # Trumps: discard from the end of the sorted list (lowest trumps, but try to keep Joker/Bowers)
                # This is implicitly handled by player.sort_hand() and popping from end of sub-lists.
                return c.rank.value # This is enum order, not game rank. Not ideal directly.
                # Let's just rely on the main hand sort and iterate.

            # Discard non-trumps first, lowest ones first
            # The main hand is sorted high-to-low. So iterate and pick from those not in trumps_in_hand.
            # A bit complex to pick lowest non-trump from a combined sorted list. 
            # Simpler: sort non_trumps_in_hand from low to high value, then pop.
            
            # Re-sort non_trumps_in_hand by rank (ascending - 4 low, Ace high) for discarding
            # This is crude, doesn't perfectly align with Player.sort_hand internal values for Joker etc.
            # but okay for a basic strategy.
            non_trumps_in_hand.sort(key=lambda c: (c.rank.value, c.suit.value)) # Sort low rank first

            for _ in range(num_to_discard):
                if not declarer.hand: break # Should not happen
                
                card_to_discard = None
                if non_trumps_in_hand:
                    card_to_discard = non_trumps_in_hand.pop(0) # Discard lowest non-trump
                    if card_to_discard in trumps_in_hand: # Should not happen if logic is right
                        # This might occur if a card is somehow both (e.g. a bug in Bower ID elsewhere)
                        # or if list management is tricky. Safe removal:
                        if card_to_discard in trumps_in_hand:
                            trumps_in_hand.remove(card_to_discard)
                elif trumps_in_hand:
                    # Have to discard trumps. Sort trumps low to high to discard lowest.
                    # Avoid Joker/Bowers if other trumps exist.
                    # Key for sorting: Joker (0), Bowers (1), Other Trumps (2), then by rank, then suit.
                    trumps_in_hand.sort(key=lambda c: (
                        0 if c.rank == Rank.JOKER else
                        (1 if c.rank == Rank.JACK and 
                            (c.suit == actual_trump_suit_for_play or # Right Bower
                             (actual_trump_suit_for_play == Suit.SPADES and c.suit == Suit.CLUBS) or 
                             (actual_trump_suit_for_play == Suit.CLUBS and c.suit == Suit.SPADES) or 
                             (actual_trump_suit_for_play == Suit.DIAMONDS and c.suit == Suit.HEARTS) or 
                             (actual_trump_suit_for_play == Suit.HEARTS and c.suit == Suit.DIAMONDS)
                            ) # End of Left Bower check
                         else 2), # Other trumps
                        c.rank.value, 
                        c.suit.value
                    ))
                    
                    if trumps_in_hand: # Still have trumps to discard
                        card_to_discard = trumps_in_hand.pop(0) # Discard lowest trump (that isn't Joker/Bower if others exist)
                else:
                    # Should have cards if num_to_discard > 0 and hand is not empty
                    # Fallback: if logic above fails to select, and hand has cards, pop from overall hand.
                    # The main hand is sorted high-low, so this discards the current lowest overall.
                    if declarer.hand: 
                        print(f"SIM: Discard strategy led to empty non_trump/trump lists, but still need to discard.")
                        card_to_discard = declarer.hand[-1] # Lowest from already sorted hand

                if card_to_discard:
                    if card_to_discard in declarer.hand: 
                        declarer.hand.remove(card_to_discard)
                        discards.append(card_to_discard)
                    else:
                        # This indicates an issue: card selected for discard was not in the main hand copy.
                        # This might happen if card_to_discard came from a sublist (trumps_in_hand, non_trumps_in_hand)
                        # that wasn't perfectly in sync or if the card was already removed.
                        # The primary removal should be from `declarer.hand`.
                        print(f"SIM: Warning - card_to_discard {card_to_discard} not found in declarer.hand directly. Trying fallback.")
                        if declarer.hand and len(discards) < num_to_discard :
                             fallback_discard = declarer.hand.pop() # Pop from the end (lowest of sorted hand)
                             discards.append(fallback_discard)
                             print(f"SIM: Fallback discard from declarer.hand: {fallback_discard}")
                elif len(discards) < num_to_discard and declarer.hand:
                    # If no card was selected by the strategy (e.g. all lists became empty prematurely)
                    print(f"SIM: No card selected by strategy, but still need to discard. Fallback.")
                    fallback_discard = declarer.hand.pop() # Pop from the end (lowest of sorted hand)
                    discards.append(fallback_discard)
                    print(f"SIM: Fallback discard due to no selection: {fallback_discard}")

        assert len(declarer.hand) == 10, f"Declarer hand size not 10, but {len(declarer.hand)}"
        print(f"{declarer.name} discarded: {discards}")
        print(f"{declarer.name}'s final hand (10 cards): {declarer.hand}")
        print(f"--- End Kitty Exchange ---")

        # After kitty exchange, proceed to play the round
        self._play_round(declarer)

    def _determine_lead_player_for_first_trick(self, declarer: Player) -> Player:
        """Determines who leads the first trick.
        - Standard/No-Trump: Player to declarer's left.
        - Misere/Open Misere: Declarer leads.
        """
        if self.winning_bid.bid_type in [BidType.MISERE, BidType.OPEN_MISERE]:
            return declarer
        else:
            declarer_idx = self.players.index(declarer)
            return self.players[self._determine_next_player_idx(declarer_idx)]

    def _play_round(self, declarer: Player):
        """Manages the playing of 10 tricks in a round."""
        print("\n--- Play Phase ---")
        if not self.winning_bid:
            print("Cannot play round without a winning bid.")
            return

        current_trick_leader = self._determine_lead_player_for_first_trick(declarer)
        print(f"{current_trick_leader.name} leads the first trick.")

        for trick_num in range(1, 11): # 10 tricks
            print(f"\n-- Trick {trick_num} --")
            trick_winner_player = self._play_trick(current_trick_leader)
            current_trick_leader = trick_winner_player # Winner of trick leads next
            # For now, let's assume declarer's team wins all tricks for testing scoring later
            # This is a major placeholder
            # print(f"Playing trick {trick_num} (actual logic TBD). Leader: {current_trick_leader.name}")
            # if trick_num % 2 == 0: # Simulate alternating trick winners for testing
            #      # Assign trick to declarer's team for now
            #     declarer_team = [t for t in self.teams if declarer in t.players][0]
            #     # Find a player in that team to attribute the trick to (e.g., declarer)
            #     declarer.increment_tricks_won() 
            #     print(f"Trick {trick_num} won by {declarer.name} (placeholder)")
            #     current_trick_leader = declarer # Declarer leads again
            # else:
            #     # Assign to other team (first player of other team)
            #     non_declarer_team = [t for t in self.teams if declarer not in t.players][0]
            #     opponent_player = non_declarer_team.players[0]
            #     opponent_player.increment_tricks_won()
            #     print(f"Trick {trick_num} won by {opponent_player.name} (placeholder)")
            #     current_trick_leader = opponent_player
            
        # After 10 tricks, proceed to scoring
        self._score_round(declarer) # Call scoring after the round
        print("\n--- End of Play Phase --- ")

    def _get_playable_cards(self, player: Player, trick_suit: Optional[Suit]) -> List[Card]:
        """Determines which cards a player can legally play in the current trick."""
        hand = player.hand
        if not trick_suit: # Player is leading the trick
            return list(hand) # Can lead any card

        # Player must follow suit if possible
        cards_of_trick_suit = [card for card in hand if card.suit == trick_suit]
        
        # Special handling for Joker and Bowers if they are the only cards of the trick_suit
        # or if player cannot follow suit.
        # The Joker can always be played, but its role in winning depends on context (e.g. if it's trump led).
        # If trump is led, and player only has Joker of trumps, they can play it.
        # If non-trump is led, and player has no cards of that suit, they can play Joker.

        # Bower considerations (if trump suit is active):
        # If the trick_suit is the trump suit, and player has a Bower, it's a valid play.
        # If the trick_suit is NOT trump, but a Bower IS trump, player can play it if they cannot follow trick_suit.

        # Simplified logic for now: Must follow suit if they have it.
        # If not, can play any card (trump, Joker, or other suit).
        # More precise rules for what constitutes "following suit" with Joker/Bowers needs care.
        # For example, if hearts are trump and diamonds are led, and player has only Jack of Hearts (Left Bower),
        # is that "following suit" if they have no diamonds? No, Jack of Hearts is a trump card.
        
        # If player has cards of the suit led (trick_suit)
        if cards_of_trick_suit:
            # If the Joker is in hand and its suit is NO_TRUMP, it *could* be played
            # even if player can follow suit, under some interpretations (e.g. to win a trick).
            # However, strict rule is usually follow suit if possible. Joker is not of the trick_suit.
            # For now, if they have trick_suit, they must play it.
            return cards_of_trick_suit
        
        # If player cannot follow suit, they can play any card.
        return list(hand) 

    def _play_trick(self, lead_player: Player) -> Player:
        """Manages the playing of a single trick and determines the winner."""
        current_trick_cards: Dict[Player, Card] = {}
        trick_suit: Optional[Suit] = None
        
        num_players = len(self.players)
        current_player_idx = self.players.index(lead_player)

        print(f"Lead player for this trick: {lead_player.name}")

        for i in range(num_players):
            current_player = self.players[current_player_idx]
            playable_cards = self._get_playable_cards(current_player, trick_suit)

            if not playable_cards:
                # This should not happen if players always have cards during the 10 tricks
                raise Exception(f"Player {current_player.name} has no cards to play!")

            # --- Player Card Choice Simulation ---
            # In a real game, player chooses. For simulation, play the first playable card.
            # A better simulation/AI would choose strategically.
            chosen_card = playable_cards[0] 
            # ---- End Player Card Choice Simulation ---
            
            current_player.play_card(chosen_card) # Removes card from hand
            current_trick_cards[current_player] = chosen_card
            print(f"{current_player.name} plays: {chosen_card}")

            if i == 0: # Lead card sets the trick_suit (unless it's Joker in some rules)
                trick_suit = chosen_card.suit
                if chosen_card.rank == Rank.JOKER and self.trump_suit != Suit.NO_TRUMP:
                    # If Joker leads a trump game, it makes the trick a trump trick.
                    # (Or player nominates suit if that's a house rule - not implemented here)
                    # For simplicity, if Joker leads, trick is effectively trump suit.
                    trick_suit = self.trump_suit 
                elif chosen_card.rank == Rank.JOKER and self.trump_suit == Suit.NO_TRUMP:
                    # If Joker leads a No-Trump game, the suit is... what? Highest other card?
                    # Standard: Joker is its own suit. For now, let trick_suit be NO_TRUMP.
                    trick_suit = Suit.NO_TRUMP 
            
            current_player_idx = self._determine_next_player_idx(current_player_idx)

        # Determine winner of the trick
        winning_card_in_trick: Optional[Card] = None
        trick_winner: Optional[Player] = None

        # The actual trump suit for this game round (set after bidding)
        game_trump_suit = self.trump_suit if self.trump_suit is not None else Suit.NO_TRUMP 
        # If Joker led and it's a trump game, the trick_suit was already set to game_trump_suit
        # If Joker led a NT game, trick_suit became NO_TRUMP.

        for player, card_played in current_trick_cards.items():
            if winning_card_in_trick is None:
                winning_card_in_trick = card_played
                trick_winner = player
            else:
                strength_current_card = self._get_card_strength_in_trick(card_played, trick_suit, game_trump_suit)
                strength_winning_card = self._get_card_strength_in_trick(winning_card_in_trick, trick_suit, game_trump_suit)
                if strength_current_card > strength_winning_card:
                    winning_card_in_trick = card_played
                    trick_winner = player
        
        if trick_winner is None or winning_card_in_trick is None: # Should not happen
            raise Exception("Could not determine trick winner.")

        trick_winner.increment_tricks_won()
        print(f"Trick won by {trick_winner.name} with {winning_card_in_trick}.")
        return trick_winner

    def _get_card_strength_in_trick(self, card: Card, trick_suit: Suit, current_trump_suit: Suit) -> int:
        """Determines the strength of a card within a specific trick context.
        Higher value means stronger card.
        Considers Joker, Bowers, trump suit, and then face value.
        This will be crucial for _play_trick.
        """
        # Define ranking within a suit (Ace high)
        # This needs to be carefully adapted from the general Rank enum order.
        # For example, Rank.JACK might be low, but a Bower is very high.
        rank_values = {
            Rank.JOKER: 100, # Absolute highest
            Rank.ACE: 14,
            Rank.KING: 13,
            Rank.QUEEN: 12,
            Rank.JACK: 11, # Base value, Bowers will override
            Rank.TEN: 10,
            Rank.NINE: 9,
            Rank.EIGHT: 8,
            Rank.SEVEN: 7,
            Rank.SIX: 6,
            Rank.FIVE: 5,
            Rank.FOUR: 4
        }
        
        strength = rank_values.get(card.rank, 0)

        # Is the card the Joker?
        if card.rank == Rank.JOKER:
            return rank_values[Rank.JOKER] # Joker is always highest

        is_trump_suit_game = current_trump_suit != Suit.NO_TRUMP

        # Check for Bowers if it's a trump game
        if is_trump_suit_game:
            # Right Bower (Jack of trump suit)
            if card.rank == Rank.JACK and card.suit == current_trump_suit:
                return 90 # Higher than any other trump except Joker
            
            # Left Bower (Jack of same color as trump suit)
            left_bower_suit = None
            if current_trump_suit == Suit.SPADES: left_bower_suit = Suit.CLUBS
            elif current_trump_suit == Suit.CLUBS: left_bower_suit = Suit.SPADES
            elif current_trump_suit == Suit.DIAMONDS: left_bower_suit = Suit.HEARTS
            elif current_trump_suit == Suit.HEARTS: left_bower_suit = Suit.DIAMONDS
            
            if card.rank == Rank.JACK and card.suit == left_bower_suit:
                return 80 # Higher than any other trump except Joker & Right Bower

        # Card is of the trump suit (and not a Bower, already handled)
        if is_trump_suit_game and card.suit == current_trump_suit:
            strength += 50 # Elevate trump cards above non-trump leads
            return strength

        # Card follows the suit led (trick_suit) and it's not a trump game or card is not trump
        if card.suit == trick_suit:
            return strength # Normal rank value
            
        # Card does not follow suit and is not trump (cannot win unless all others are also non-followers)
        return 0 # Lowest strength if not following suit and not trump

    # --- Game State Checks ---
    def check_game_over(self) -> bool:
        """Checks if any team has reached 500 points (win) or -500 points (loss)."""
        for team in self.teams:
            if team.team_score >= 500:
                print(f"Game Over! {team.name} wins with {team.team_score} points!")
                self.game_over = True
                return True
            if team.team_score <= -500: # Losing condition
                # Determine other team as winner
                other_team = [t for t in self.teams if t != team][0]
                print(f"Game Over! {team.name} reaches {team.team_score} points. {other_team.name} wins!")
                self.game_over = True
                return True
        return False

    def __repr__(self):
        return f"Game(Players: {len(self.players)}, Teams: {len(self.teams)}, Dealer: {self.players[self.current_dealer_idx].name})"

    def _score_round(self, declarer: Player):
        """Calculates and applies scores after a round of play."""
        print("\n--- Scoring Phase ---")
        if not self.winning_bid:
            print("No winning bid this round. No scores to calculate.")
            return

        contracting_player = self.winning_bid.player
        contracting_team: Optional[Team] = None
        opponent_team: Optional[Team] = None

        for team in self.teams:
            if contracting_player in team.players:
                contracting_team = team
            else:
                opponent_team = team
        
        if not contracting_team or not opponent_team:
            raise Exception("Could not determine contracting and opponent teams.")

        tricks_won_by_contracting_team = contracting_team.get_total_tricks_won_this_round()
        # tricks_won_by_opponent_team = opponent_team.get_total_tricks_won_this_round()
        # Total tricks are 10. So opponent_tricks = 10 - tricks_won_by_contracting_team

        bid_details = self.winning_bid
        bid_points = bid_details.points
        bid_tricks_target = bid_details.tricks

        print(f"Contract was: {bid_details}")
        print(f"{contracting_team.name} (declarer: {contracting_player.name}) won {tricks_won_by_contracting_team} tricks.")

        if bid_details.bid_type == BidType.SUIT_TRUMP or bid_details.bid_type == BidType.NO_TRUMP:
            if tricks_won_by_contracting_team >= bid_tricks_target:
                # Contract made
                points_to_award = bid_points
                # Avondale Slam rule: if bid < 250 points and all 10 tricks taken, score 250.
                if tricks_won_by_contracting_team == 10 and bid_points < 250:
                    points_to_award = 250
                    print(f"Slam! All 10 tricks taken, bid was {bid_points}, awarding 250 points.")
                
                contracting_team.update_score(points_to_award)
                print(f"{contracting_team.name} scores {points_to_award} points.")
            else:
                # Contract failed (set/euchred)
                contracting_team.update_score(-bid_points) # Lose points for the bid
                print(f"{contracting_team.name} failed contract, loses {bid_points} points.")
                # Opponent scoring for breaking contract (e.g., 10 pts per trick they took)
                # This rule varies. Wikipedia: "no points are scored by the opponents, although some rule books state otherwise"
                # For now, no points for opponents if contract broken, unless it's a specific setting.
                # Let's assume for now opponents don't score for breaking a standard bid.

        elif bid_details.bid_type == BidType.MISERE:
            # Misere: declarer (not team) must win 0 tricks.
            # Tricks won by the player who bid Misere:
            misere_bidder_tricks_won = contracting_player.tricks_won_this_round
            if misere_bidder_tricks_won == 0:
                contracting_team.update_score(MISERE_POINTS)
                print(f"{contracting_team.name} (bidder {contracting_player.name}) successfully made Misere, scores {MISERE_POINTS} points.")
            else:
                contracting_team.update_score(-MISERE_POINTS)
                print(f"{contracting_team.name} (bidder {contracting_player.name}) failed Misere by taking {misere_bidder_tricks_won} trick(s), loses {MISERE_POINTS} points.")
                # Opponent scoring for breaking Misere (e.g. 10 pts per trick taken by misere bidder)
                # This also varies. Some rules might give opponents points.
                # For now, no specific opponent scoring for failed Misere.

        elif bid_details.bid_type == BidType.OPEN_MISERE:
            open_misere_bidder_tricks_won = contracting_player.tricks_won_this_round
            if open_misere_bidder_tricks_won == 0:
                contracting_team.update_score(OPEN_MISERE_POINTS)
                print(f"{contracting_team.name} (bidder {contracting_player.name}) successfully made Open Misere, scores {OPEN_MISERE_POINTS} points.")
            else:
                contracting_team.update_score(-OPEN_MISERE_POINTS)
                print(f"{contracting_team.name} (bidder {contracting_player.name}) failed Open Misere by taking {open_misere_bidder_tricks_won} trick(s), loses {OPEN_MISERE_POINTS} points.")

        print(f"Current Scores:")
        for team in self.teams:
            print(f"  {team.name}: {team.team_score}")
        
        self.check_game_over()

    def _reset_bidding_state(self):
        self.highest_bid_this_round = None
        self.bids_this_round = []
        self.player_has_bid_this_round = {player: False for player in self.players}
        self.player_has_passed_auction = {player: False for player in self.players}
        self.passes_this_round = 0 # Reset passes for the new bidding round
        self.last_bidder = None # Reset last bidder

# Example usage (conceptual)
if __name__ == '__main__':
    game = Game(["Alice", "Bob", "Charlie", "David"], ["Team A/C", "Team B/D"])
    game.start_new_round() # Deals, sets up for bidding
    
    # Simulate a bidding process (simplified)
    # Player to left of dealer (player 1 if dealer is 0)
    current_bidder = game.players[game._determine_next_player_idx(game.current_dealer_idx)]
    
    # game.player_attempts_bid(current_bidder, 6, Suit.SPADES, BidType.SUIT_TRUMP)
    # game.player_passes_bid(game.players[ (game.players.index(current_bidder) + 1) % 4])
    # ... bidding continues ...

    # Once bidding is done, winning_bid and trump_suit would be set.
    # Then kitty exchange, then play tricks, then score round.
    # game.check_game_over() 