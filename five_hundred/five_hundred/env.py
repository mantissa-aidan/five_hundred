import threading
import queue
import numpy as np
from typing import Dict, Any, Tuple, List, Optional
from .game import Game
from .rl_player import RLPlayer
from .card import Card, Suit, Rank
from .bid import Bid, BidType
from .heuristic import calculate_hand_strength
from .server import update_state, start_server_thread, log_message

class FiveHundredEnv:
    def __init__(self, verbose=False):
        self.verbose = verbose
        # Start server
        start_server_thread()
        self.action_queue = queue.Queue()
        self.obs_queue = queue.Queue()
        self.game_thread = None
        self.last_phase = "BID"
        self.rl_player = None
        self.game = None
        
        # Tracking for rewards
        self.previous_tricks_won = 0
        self.previous_score = 0
        
        # Action Space
        self.action_space_size = 100
    
    # ... (other code) ...

    def _log_handler(self, msg):
         # Helper to inject into Game
         log_message(msg)
         if self.verbose:
             print(msg)

    def _run_game(self):
        try:
            player_names = ["Agent", "Bot1", "Bot2", "Bot3"]
            team_names = ["Team Agent", "Team Bots"]
            # To fix the 'None' player issue, we must tell Game which bots to create
            bot_config = {1: "easy", 2: "easy", 3: "easy"}
            
            # Setup RLPlayer
            self.rl_player = RLPlayer("Agent", self.action_queue, self.obs_queue)
            
            self.game = Game(player_names, team_names, bot_config, verbose=self.verbose)
            # Override _log
            self.game._log = self._log_handler
            
            # Inject RL player into slot 0
            self.game.players[0] = self.rl_player 
            self.game.teams[0].players[0] = self.rl_player 
            
            # Start Round
            self.game.start_new_round()
            
            self.obs_queue.put({"done": True, "info": "Game Finished"})
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            log_message(f"ERROR: {e}")
            self.obs_queue.put({"done": True, "error": str(e)})

        


    def reset(self):
        # Join previous thread if any
        if self.game_thread and self.game_thread.is_alive():
            # Requires forcing stop? Python threads can't be killed easily.
            # We rely on game finishing or assume reset is called after done.
            # If reset called early, we might have a zombie thread.
            # For now assume mostly synchronous run-to-completion.
             pass

        self.previous_tricks_won = 0
        
        # Start new game thread
        self.game_thread = threading.Thread(target=self._run_game, daemon=True)
        self.game_thread.start()
        
        # Get first observation
        raw_obs = self.obs_queue.get()
        state = self._process_obs(raw_obs)
        info = {'mask': self.last_mask} if hasattr(self, 'last_mask') else {}
        return state, info

    def step(self, action_idx: int):
        """
        Action idx interpretation depends on phase.
        But standard RL expects generic action idx.
        We decypher action_idx based on current phase stored in self.last_phase?
        Or we assume agent knows mapping 0-100.
        """
        # Decode action
        action_obj = self._decode_action(action_idx)
        
        # Send to game
        self.action_queue.put(action_obj)
        
        # Wait for next obs
        raw_obs = self.obs_queue.get()
        
        # Calculate Reward
        reward = 0
        done = False
        info = {}
        
        if "done" in raw_obs:
            done = True
            # Final game result reward
            # Win/Loss
            if self.rl_player.score > 0: reward += 10 # Arbitrary
            # Check game.teams[0].score ?
            # Since threads share memory, self.game is accessible!
            team_score = self.game.teams[0].team_score
            reward += team_score / 10.0 # Normalize 500 -> 50
            return np.zeros(360, dtype=np.float32), reward, done, info
        
        # Intermediate rewards
        current_tricks = self.rl_player.tricks_won_this_round
        if current_tricks > self.previous_tricks_won:
            reward += 10 # Won a trick
            self.previous_tricks_won = current_tricks
            
        # Check if we just made a bet? (Handled in obs phase maybe)
        
        processed_obs = self._process_obs(raw_obs)
        if hasattr(self, 'last_mask'):
            info['mask'] = self.last_mask
            
        return processed_obs, reward, done, info

    # --- Encoding Helpers ---
    def _card_to_int(self, card: Card) -> int:
        if card.rank == Rank.JOKER:
            return 52
        
        # Suits: Spades=0, Clubs=1, Diamonds=2, Hearts=3
        suit_map = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3}
        # Ranks: 4=0 ... Ace=10 ... (Standard 500 deck usually 4-A or 2-A? Game uses 4-A logic mostly + Joker)
        # Rank values in card.py: 4..14. 
        # offset = card.rank.value - 4
        # Range 0..12
        rank_idx = card.rank.value - 4
        return suit_map.get(card.suit, 0) * 13 + rank_idx

    def _get_state_vector(self, obs: Dict) -> np.ndarray:
        # Size: 
        # Phase (2) + Hand (53) + Trump (6) + Contract (30?) + Trick (4*53) = ~300
        # Let's fix size at 360 for safety padding
        vec = np.zeros(360, dtype=np.float32)
        idx = 0
        
        # 1. Phase [Bid, Play]
        phase = obs.get('phase')
        if phase == 'BID': vec[idx] = 1
        elif phase == 'KITTY': vec[idx] = 1 # Treat as special/bid
        elif phase == 'PLAY': vec[idx+1] = 1
        idx += 2
        
        # 2. Hand (53)
        hand = obs.get('hand', [])
        for card in hand:
            c_idx = self._card_to_int(card)
            if 0 <= c_idx <= 52:
                vec[idx + c_idx] = 1
        idx += 53
        
        # 3. Trump (6: S, C, D, H, NT, None)
        trump = obs.get('trump_suit')
        # Map Suit to 0-3, NT to 4, None to 5
        t_idx = 5
        if trump:
            if trump == Suit.NO_TRUMP: t_idx = 4
            else: t_idx = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3}.get(trump, 5)
        vec[idx + t_idx] = 1
        idx += 6
        
        # 4. Trick History (Current Trick) - 4 slots * 53 cards
        # We need generic "Card played at pos 0, 1, 2, 3"
        # Since we don't know absolute seats easily here, let's just fill in order of play
        current_trick = obs.get('current_trick', []) # List of (Player, Card)
        for i, (player, card) in enumerate(current_trick):
            if i >= 4: break
            c_int = self._card_to_int(card)
            vec[idx + (i * 53) + c_int] = 1
        idx += (4 * 53)
        
        # 5. Winning Bid (Contract) info could go here too, but start with this.
        
        return vec

    def _get_action_mask(self, obs: Dict) -> np.ndarray:
        mask = np.zeros(self.action_space_size, dtype=np.float32)
        phase = obs.get('phase')
        
        if phase == 'BID':
            # Allow all bids for now, or refine based on rules?
            # Basic: Allow Pass (0) and Bids (1-27)
            # Prevent "Pass" if forced to bid? No, Pass always allowed.
            # Prevent lower bids than current?
            # RL agent should learn valid bids, but masking invalid ones speeds it up.
            # We need 'current_highest_bid' from obs to mask lower ones.
            # Simplified: Allow all. Agent learns via penalty.
            mask[:] = 1 
        
        elif phase == 'PLAY':
            # Allow Pass? No.
            # Allow Card Indices 0..size-1?
            # We map action_idx to card index in hand?
            # Wait, `_decode_action` maps `action_idx` directly to `card_idx`.
            # If I have 10 cards, actions 0..9 are Valid. 10..99 Invalid.
            # AND `playable_cards` limits this further.
            
            hand = obs.get('hand', [])
            playable = obs.get('playable_cards', [])
            
            # Mask all first
            # But wait, action space is fixed 100.
            # My logic in `step`: action_idx IS card_idx in hand.
            # So if hand has cards [A, B, C], index 0 plays A, 1 plays B...
            # Valid actions are indices of cards in 'hand' that are ALSO in 'playable'.
            
            if not hand:
                return mask # All zeros
            
            for i, card in enumerate(hand):
                if card in playable:
                    mask[i] = 1 # Valid to play card at index i
                    
        elif phase == 'KITTY':
            # Discard steps. Hand has 13 cards.
            # Action logic for kitty usually complex (choose 3).
            # If we simplify to "Choose 1 to discard" repeatedly?
            # Current RLPlayer.decide_kitty_exchange expects list of 3.
            # This environment step model breaks for that atomic "return 3 cards" action.
            # For now, let's just valid mask 0..12 and assume Env handles singular discards 
            # OR we fallback to random discard in wrapper if RL fails.
            pass

        return mask

    def _process_obs(self, raw_obs):
        # Update last phase
        self.last_phase = raw_obs.get('phase', 'UNKNOWN')
        
        # Publish UI
        if isinstance(raw_obs, dict) and self.game:
            # Reconstruct UI state similar to before...
            ui_state = {
                "phase": self.last_phase,
                "trump": str(self.game.trump_suit) if self.game.trump_suit else None,
                "contract": str(self.game.winning_bid) if self.game.winning_bid else None,
                "hands": [[{"rank": c.rank.name, "suit": c.suit.name} for c in p.hand] for p in self.game.players],
                "scores": [t.team_score for t in self.game.teams],
                "trick": []
            }
            if 'current_trick' in raw_obs:
                 ui_state['trick'] = [{'player': self.game.players.index(p), 'card': {"rank": c.rank.name, "suit": c.suit.name}} for p, c in raw_obs['current_trick']]
            update_state(ui_state)

        # Vectorize
        state_vec = self._get_state_vector(raw_obs)
        self.last_mask= self._get_action_mask(raw_obs) # Store for Info return
        
        return state_vec

    def _decode_action(self, action_idx):
        if self.last_phase == 'BID':
            if action_idx == 0:
                return ("pass", None)
                
            # Map 1..25 to 6S..10NT
            if 1 <= action_idx <= 25:
                adjusted_idx = action_idx - 1
                tricks = 6 + (adjusted_idx // 5)
                suit_idx = adjusted_idx % 5
                
                # Order: Spades, Clubs, Diamonds, Hearts, No Trump
                suits = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, None] # None for NT
                chosen_suit = suits[suit_idx]
                
                if chosen_suit is None:
                    return ("bid", (tricks, Suit.NO_TRUMP, BidType.NO_TRUMP))
                else:
                    return ("bid", (tricks, chosen_suit, BidType.SUIT_TRUMP))
            
            # Misere / Open Misere
            elif action_idx == 26:
                return ("bid", (0, None, BidType.MISERE))
            elif action_idx == 27:
                return ("bid", (0, None, BidType.OPEN_MISERE))
                
            # Fallback if agent picks invalid index
            return ("pass", None)
            
        elif self.last_phase == 'PLAY':
            # Action 0 = Play Card at index 0
            # Action N = Play Card at index N
            # If the index is out of bounds (>= hand size), rule-based fallback will handle it (play random valid).
            return action_idx 
            
        # Default fallback
        return ("pass", None)

