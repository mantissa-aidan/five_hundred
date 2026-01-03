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
from .utils_rl import card_to_int, int_to_card, get_state_vector, decode_action

class FiveHundredEnv:
    def __init__(self, verbose=False, start_server=True):
        self.verbose = verbose
        # Start server
        if start_server:
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
        
        # Metrics
        self.invalid_moves = 0
    
    # ... (other code) ...

    def _log_handler(self, msg):
         # Helper to inject into Game
         log_message(msg)
         if self.verbose:
             print(msg)

    def _run_game(self, opponent_agents=None):
        try:
            player_names = ["Agent", "Opp1", "Opp2", "Opp3"]
            team_names = ["Team Agent", "Team Opponents"]
            
            # Default bot config
            bot_config = {1: "easy", 2: "easy", 3: "easy"}
            
            # Setup RLPlayer (Agent)
            self.rl_player = RLPlayer("Agent", self.action_queue, self.obs_queue)
            
            self.game = Game(player_names, team_names, bot_config, verbose=self.verbose)
            # Override _log
            self.game._log = self._log_handler
            
            # Inject RL player into slot 0
            self.game.players[0] = self.rl_player 
            self.game.teams[0].players[0] = self.rl_player 

            # Inject Opponents if provided
            if opponent_agents:
                from .direct_rl_player import DirectRLPlayer
                for i, agent in enumerate(opponent_agents):
                    seat_idx = i + 1 # 1, 2, 3
                    if seat_idx < 4:
                        opp_p = DirectRLPlayer(f"Opp{i+1}", agent, seat_idx)
                        self.game.players[seat_idx] = opp_p
                        
                        # Assign to team
                        # 0 & 2 are Team A (Agent & Opp2)
                        # 1 & 3 are Team B (Opp1 & Opp3)
                        if seat_idx == 2:
                            self.game.teams[0].players[1] = opp_p
                        else:
                            team_idx_in_team = 0 if seat_idx == 1 else 1
                            self.game.teams[1].players[team_idx_in_team] = opp_p
 
            
            # Start Rounds Loop
            while not self.game.game_over:
                self.game.start_new_round()
                
            # Game Over - Record Win
            # Who won?
            winning_team = max(self.game.teams, key=lambda t: t.team_score)
            from five_hundred.server import record_win
            record_win(winning_team.name)
            
            self.obs_queue.put({"done": True, "info": f"Game Finished. Winner: {winning_team.name}"})
            
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
        self.invalid_moves = 0
        
        # Start new game thread
        # Start new game thread
        # We need to pass opponent_agents if they exist, but reset() doesn't accept args usually.
        # We can store them in __init__? Or allowed reset args.
        self.game_thread = threading.Thread(target=self._run_game, args=(self.opponent_agents if hasattr(self, 'opponent_agents') else None,), daemon=True)
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
        
        # Check validity using the mask from the PREVIOUS observation
        is_valid = True
        if hasattr(self, 'last_mask'):
            if self.last_mask[action_idx] == 0:
                is_valid = False
        
        if not is_valid:
            # PENALTY for invalid move
            reward = -10 # Punishment
            self.invalid_moves += 1
            info = {'invalid': True}
            
            # Send FALLBACK action to keep game alive
            if self.last_phase == 'BID':
                self.action_queue.put(("pass", None))
            elif self.last_phase == 'PLAY':
                # We need to send a valid card index? Or a special "random" flag?
                # The _decode_action handles indices. We need to find *any* valid index.
                valid_indices = np.where(self.last_mask == 1)[0]
                if len(valid_indices) > 0:
                    fallback_idx = valid_indices[0]
                    self.action_queue.put(self._decode_action(fallback_idx))
                else:
                    # Should not happen if mask is correct?
                    self.action_queue.put(0) # Hopeless fallback
            else:
                 self.action_queue.put(action_obj)
                 
        else:
             # Send VALID action to game
             self.action_queue.put(action_obj)
             reward = 0 # Calculated later
             info = {}
        
        # Wait for next obs
        raw_obs = self.obs_queue.get()
        
        # Calculate Reward
        # reward = 0 # OLD: Resetting here wiped out the penalty. 
        # We rely on reward being set in the valid/invalid block above.
        done = False
        # info = {} 
        info['invalid_moves'] = self.invalid_moves
        
        if raw_obs.get('done'):
            done = True
            # Final game result reward
            # Win/Loss
            # Final game result reward
            # Win/Loss
            # if self.rl_player.score > 0: reward += 10 # Arbitrary
            # Check game.teams[0].score ?
            # Since threads share memory, self.game is accessible!
            team_score = self.game.teams[0].team_score
            
            # Simple reward: 
            # If we were punishing invalid moves, we accumulate that?
            # Step reward is just immediate.
            # Terminal reward: Normalized Score
            reward += team_score / 100.0 # Normalize 500 -> 5
            
            # Game Over Penalty/Bonus? (Already in score)
            
            # State vector size changed to 600
            return np.zeros(600, dtype=np.float32), reward, done, info
        
        # Intermediate rewards: Reward Shaping
        # Reward winning tricks to encourage valid play and strategy
        current_tricks = self.rl_player.tricks_won_this_round
        if current_tricks > self.previous_tricks_won:
            reward += 0.1 # Won a trick (Dense reward)
            # print("DEBUG: Reward +0.1 for trick win")
            self.previous_tricks_won = current_tricks
            
        # Check if we just made a bet? (Handled in obs phase maybe)
        
        processed_obs = self._process_obs(raw_obs)
        if hasattr(self, 'last_mask'):
            info['mask'] = self.last_mask
            
        return processed_obs, reward, done, info

    # --- Encoding Helpers (Delegated to utils_rl) ---
    def _card_to_int(self, card: Card) -> int:
        return card_to_int(card)

    def _int_to_card(self, idx: int) -> Optional[Card]:
        return int_to_card(idx)

    def _get_state_vector(self, obs: Dict) -> np.ndarray:
        return get_state_vector(obs)


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
            
            # EXCEPTION: User requested to ignore Misere/Open Misere for now.
            # Grid: 0=Pass, 1-25=Suits, 26=Misere, 27=OpenMisere
            mask[26] = 0
            mask[27] = 0
        
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
            
            hand = obs.get('hand', [])
            playable = obs.get('playable_cards', [])
            
            if not hand:
                return mask # All zeros
            
            # Use Global Card ID masking
            for card in playable:
                idx = self._card_to_int(card)
                if 0 <= idx < self.action_space_size:
                    mask[idx] = 1
                    
        elif phase == 'KITTY':
            # Allow discarding any card in hand
            hand = obs.get('hand', [])
            for card in hand:
                idx = self._card_to_int(card)
                if 0 <= idx < self.action_space_size:
                    mask[idx] = 1

        return mask

    def _process_obs(self, raw_obs):
        # Update last phase
        self.last_phase = raw_obs.get('phase', 'UNKNOWN')
        
        # INJECT Game State (History & Scores) that RLPlayer doesn't send
        if self.game and isinstance(raw_obs, dict):
            # History
            raw_obs['played_history'] = list(self.game.cards_played_this_round)
            
            # Scores
            team_0 = self.game.teams[0] # Training Agent's Team
            team_1 = self.game.teams[1] # Opponents
            
            raw_obs['my_score'] = team_0.team_score
            raw_obs['opp_score'] = team_1.team_score
            
            # Expanded Info
            raw_obs['agent_seat'] = 0 # RL Agent is always at seat 0 in FiveHundredEnv
            
            # Contract
            if self.game.winning_bid:
                raw_obs['winning_bid_obj'] = self.game.winning_bid
                raw_obs['bidder_seat'] = self.game.players.index(self.game.winning_bid.player)
                
            # Tricks Won
            raw_obs['tricks_my_team'] = sum(p.tricks_won_this_round for p in team_0.players)
            raw_obs['tricks_opp_team'] = sum(p.tricks_won_this_round for p in team_1.players)
            
            # Bidding History (Simplified: Last action of each player)
            raw_obs['bidding_history_one_hot'] = {}
            for item in self.game.bids_this_round:
                # bids_this_round contains either Bid objects or "Name passes" strings?
                # Let's check game.player_passes_bid
                if isinstance(item, str) and "passes" in item:
                    # Find player
                    for i, p in enumerate(self.game.players):
                        if p.name in item:
                            raw_obs['bidding_history_one_hot'][i] = 0 # Pass
                            break
                elif hasattr(item, 'player'):
                    p_idx = self.game.players.index(item.player)
                    # Encode bid to 1-27
                    # This logic should match _decode_action in reverse
                    bid_code = 0
                    if item.bid_type == BidType.MISERE: bid_code = 26
                    elif item.bid_type == BidType.OPEN_MISERE: bid_code = 27
                    else:
                        # 1..25
                        tr_idx = item.tricks - 6
                        s_map = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3, Suit.NO_TRUMP: 4}
                        s_idx = s_map.get(item.suit, 4) if item.bid_type == BidType.SUIT_TRUMP or item.bid_type == BidType.NO_TRUMP else 4
                        bid_code = 1 + (tr_idx * 5) + s_idx
                    raw_obs['bidding_history_one_hot'][p_idx] = bid_code
        
        # Publish UI
        if isinstance(raw_obs, dict) and self.game:
            # Reconstruct UI state similar to before...
            ui_state = {
                "phase": self.last_phase,
                "trump": str(self.game.trump_suit) if self.game.trump_suit else None,
                "contract": str(self.game.winning_bid) if self.game.winning_bid else None,
                "hands": [[{"rank": c.rank.name, "suit": c.suit.name} for c in p.hand] for p in self.game.players],
                "scores": [t.team_score for t in self.game.teams],
                "tricks_won": [t.get_total_tricks_won_this_round() for t in self.game.teams],
                "contract_level": self.game.winning_bid.tricks if self.game.winning_bid else 0,
                "contract_suit": str(self.game.winning_bid.suit).replace("Suit.", "") if self.game.winning_bid and self.game.winning_bid.suit else ("NT" if self.game.winning_bid else None),
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
        return decode_action(action_idx, self.last_phase)

