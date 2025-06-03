from typing import List, Optional, Dict, Tuple, Callable
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
        self._test_mode_card_choice_logic: Optional[Callable[[Player, List[Card], Optional[Suit], Optional[Suit]], Card]] = None # Test hook

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
        Gets player's bid or pass action via user input.
        """
        print(f"\n{player.name}'s turn to bid.")
        player.sort_hand() # Ensure hand is sorted for display
        print(f"Your hand: {player.hand}")

        if self.highest_bid_this_round:
            print(f"Current highest bid: {self.highest_bid_this_round}")
        else:
            print("No bids yet.")
        
        print("Bidding options: 'bid' or 'pass'")
        
        while True:
            action = input("Enter your action ('bid' or 'pass'): ").strip().lower()
            if action == "pass":
                return ("pass", None)
            elif action == "bid":
                try:
                    print("\n--- Place Your Bid ---")
                    
                    # Get tricks (6-10 for suit/NT, 0 for Misere/Open Misere)
                    while True:
                        try:
                            tricks_str = input("Enter number of tricks (6-10, or 0 for Misere bids): ")
                            tricks = int(tricks_str)
                            # Basic validation, Bid class will do more
                            if not (0 <= tricks <= 10):
                                print("Invalid number of tricks. Must be 0 (for Misere) or between 6 and 10.")
                                continue
                            break
                        except ValueError:
                            print("Invalid input. Please enter a number.")

                    # Get BidType
                    print("Bid Types:")
                    bid_type_options = {i+1: bt for i, bt in enumerate(BidType)}
                    for i, bt in bid_type_options.items():
                        print(f"  {i}. {bt.name.replace('_', ' ').title()}")
                    
                    bid_type_choice = None
                    while bid_type_choice is None:
                        try:
                            bt_idx_str = input(f"Choose bid type (1-{len(bid_type_options)}): ")
                            bt_idx = int(bt_idx_str)
                            if bt_idx in bid_type_options:
                                bid_type_choice = bid_type_options[bt_idx]
                            else:
                                print(f"Invalid choice. Please enter a number between 1 and {len(bid_type_options)}.")
                        except ValueError:
                            print("Invalid input. Please enter a number.")
                    
                    chosen_bid_type = bid_type_choice

                    # Handle Misere/Open Misere tricks automatically
                    if chosen_bid_type == BidType.MISERE or chosen_bid_type == BidType.OPEN_MISERE:
                        if tricks != 0:
                            print(f"For {chosen_bid_type.name}, tricks are automatically 0. Adjusting.")
                        tricks = 0 # Enforce 0 tricks for Misere types
                        chosen_suit = None # No suit for Misere bids
                        return ("bid", (tricks, chosen_suit, chosen_bid_type))

                    # Get Suit for Suit Trump or No Trump bids
                    if chosen_bid_type == BidType.NO_TRUMP:
                        if tricks < 6:
                             print("No Trump bids must be for 6-10 tricks. Please re-bid.")
                             continue # Restart bid input
                        chosen_suit = Suit.NO_TRUMP # Special case for NT, Bid class handles it
                        return ("bid", (tricks, chosen_suit, chosen_bid_type))
                    elif chosen_bid_type == BidType.SUIT_TRUMP:
                        if not (6 <= tricks <= 10):
                            print("Suit Trump bids must be for 6-10 tricks. Please re-bid.")
                            continue # Restart bid input
                        
                        print("Suits:")
                        suit_options = {i+1: s for i, s in enumerate([Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS])}
                        for i, s_opt in suit_options.items():
                            print(f"  {i}. {s_opt.name.title()}")
                        
                        suit_choice = None
                        while suit_choice is None:
                            try:
                                s_idx_str = input(f"Choose suit (1-{len(suit_options)}): ")
                                s_idx = int(s_idx_str)
                                if s_idx in suit_options:
                                    suit_choice = suit_options[s_idx]
                                else:
                                    print(f"Invalid choice. Please enter a number between 1 and {len(suit_options)}.")
                            except ValueError:
                                print("Invalid input. Please enter a number.")
                        chosen_suit = suit_choice
                        return ("bid", (tricks, chosen_suit, chosen_bid_type))
                    else:
                        # Should not happen if BidTypes are handled above
                        print("Error: Unexpected bid type. Please try again.")
                        continue

                except Exception as e: # Catch any unexpected errors during input
                    print(f"An error occurred during bid input: {e}. Please try again.")
                    # Loop again for fresh input
            else:
                print("Invalid action. Please enter 'bid' or 'pass'.")

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
        """Allows the declarer to exchange cards with the kitty via user input."""
        print(f"\n--- Kitty Exchange Phase ---")
        print(f"{declarer.name}, you won the bid: {self.winning_bid}")
        print(f"Kitty contained: {self.kitty}")
        
        declarer.add_cards_to_hand(self.kitty)
        self.kitty = [] 
        declarer.sort_hand() 

        print(f"\n{declarer.name}'s hand with kitty cards (13 cards total):")
        for i, card in enumerate(declarer.hand):
            print(f"  {i+1}. {card}")

        num_to_discard = len(declarer.hand) - 10
        discards: List[Card] = []
        discard_indices: List[int] = []

        print(f"You must discard {num_to_discard} card(s).")
        
        if num_to_discard <= 0:
            print("No discard necessary.")
        else:
            for i in range(num_to_discard):
                while True:
                    try:
                        card_idx_str = input(f"Choose card to discard #{i+1} (enter number 1-{len(declarer.hand)}): ").strip()
                        card_idx_one_based = int(card_idx_str)
                        card_idx_zero_based = card_idx_one_based - 1

                        if not (0 <= card_idx_zero_based < len(declarer.hand)):
                            print("Invalid card number. Please choose from the list.")
                            continue
                        if card_idx_zero_based in discard_indices:
                            print("You've already selected that card to discard. Choose a different one.")
                            continue
                        
                        discard_indices.append(card_idx_zero_based)
                        break 
                    except ValueError:
                        print("Invalid input. Please enter a number.")
            
            # Sort indices in reverse order to avoid issues when removing from list
            discard_indices.sort(reverse=True)
            
            for idx_to_remove in discard_indices:
                discards.append(declarer.hand.pop(idx_to_remove))
        
        assert len(declarer.hand) == 10, f"Declarer hand size not 10, but {len(declarer.hand)}"
        print(f"\n{declarer.name} discarded: {discards}")
        print(f"{declarer.name}'s final hand (10 cards): {declarer.hand}")

        if self.winning_bid.bid_type == BidType.OPEN_MISERE:
            print(f"{declarer.name}'s hand is now open for Open Misere: {declarer.hand}")
            # In a real CLI/GUI, this hand would remain visible to all players.

        print(f"--- End Kitty Exchange ---")
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

    def _get_player_card_choice_for_test(self, player: Player, playable_cards: List[Card], trick_suit: Optional[Suit], current_trump_suit: Optional[Suit]) -> Card:
        """Used by _play_trick in test mode to get a card based on scenario logic."""
        if self._test_mode_card_choice_logic:
            chosen_card = self._test_mode_card_choice_logic(player, playable_cards, trick_suit, current_trump_suit)
            if chosen_card not in playable_cards:
                raise ValueError(f"Test logic for {player.name} chose unplayable card {chosen_card} from {playable_cards}")
            return chosen_card
        raise RuntimeError("Test mode card choice logic not set!")

    def _play_trick(self, lead_player: Player) -> Player:
        """Manages the playing of a single trick, getting card choices from users, and determines the winner."""
        current_trick_cards: Dict[Player, Card] = {}
        trick_suit: Optional[Suit] = None
        
        num_players = len(self.players)
        current_player_idx = self.players.index(lead_player)

        print(f"Lead player for this trick: {lead_player.name}")

        for i in range(num_players):
            current_player = self.players[current_player_idx]
            current_player.sort_hand() # Keep hand sorted for display consistency
            playable_cards = self._get_playable_cards(current_player, trick_suit)

            if not playable_cards:
                print(f"Error: {current_player.name} has no playable cards. This should not happen.")
                # Handle this gracefully, maybe by auto-passing or erroring out the trick/round.
                # For now, let's assume this indicates a test setup or game logic error.
                # If game could continue, a rule for unplayable cards (e.g. misdeal) would apply.
                raise ValueError(f"{current_player.name} has no playable cards. Hand: {current_player.hand}, Trick Suit: {trick_suit}, Trump: {self.trump_suit}")

            chosen_card = None
            if self._test_mode_card_choice_logic: # TEST MODE HOOK
                chosen_card = self._get_player_card_choice_for_test(current_player, playable_cards, trick_suit, self.trump_suit)
            else: # Normal CLI input mode
                print(f"\n{current_player.name}'s turn to play a card.")
                print(f"Your hand: {current_player.hand}")
                if trick_suit:
                    print(f"Suit led: {trick_suit.name}")
                else:
                    print("You are leading this trick.")
                if self.trump_suit and self.trump_suit != Suit.NO_TRUMP:
                    print(f"Trump suit: {self.trump_suit.name}")
                
                print("Playable cards:")
                for idx, card_option in enumerate(playable_cards):
                    print(f"  {idx+1}. {card_option}")

                while chosen_card is None:
                    try:
                        choice_str = input(f"Choose card to play (1-{len(playable_cards)}): ")
                        choice_idx = int(choice_str) - 1
                        if 0 <= choice_idx < len(playable_cards):
                            chosen_card = playable_cards[choice_idx]
                        else:
                            print(f"Invalid choice. Please enter a number between 1 and {len(playable_cards)}. ")
                    except ValueError:
                        print("Invalid input. Please enter a number.")
            
            print(f"{current_player.name} plays: {chosen_card}")
            current_player.play_card(chosen_card)
            current_trick_cards[current_player] = chosen_card

            if i == 0: # First card played in the trick sets the trick_suit (unless it's a Joker in a trump game)
                trick_suit = chosen_card.suit
                if self.trump_suit and self.trump_suit != Suit.NO_TRUMP and chosen_card.is_joker():
                    trick_suit = self.trump_suit # Joker led in trump game makes trick suit trump
                elif chosen_card.is_joker() and (not self.trump_suit or self.trump_suit == Suit.NO_TRUMP):
                    trick_suit = Suit.NO_TRUMP # Joker led in NT game, trick is NT (Joker's "suit")

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