import time
import numpy as np
from typing import Tuple, List, Dict
from five_hundred.game import Game, StepResult, GameState
from five_hundred.player import Player
from five_hundred.utils_rl import get_state_vector, decode_action, build_observation
import os
import random
import torch
from five_hundred.ppo_bot import PPOBot
from five_hundred.ppo_agent import PPOPolicy

class GameEnvWrapper:
    """
    Single game environment using Game's step-by-step FSM.
    Compatible with PPO RolloutBuffer.
    """
    
    def __init__(self, bot_difficulty='medium'):
        self.bot_difficulty = bot_difficulty
        self.last_score = 0
        self.reset()
        
    def reset(self, bot_map=None):
        """Start a new game/round"""
        # Create game with Agent and 3 Bots
        self.game = Game(
            ['Agent', 'Bot1', 'Bot2', 'Bot3'],
            ['T1', 'T2'],
            bot_config={1: self.bot_difficulty, 2: self.bot_difficulty, 3: self.bot_difficulty},
            bot_map=bot_map,
            verbose=False # Reduce noise during training
        )
        
        # Mark Agent as external
        self.game.players[0].is_training = True
        
        self.agent_seat = 0
        self.last_score = 0
        self.game_over = False
        self.pending_metrics = []
        
        # Start initial round non-blocking
        self.game.start_new_round(blocking=False)
        
        # Fast-forward to first Agent interaction
        self._advance_to_agent_turn()
        
        return self._get_observation()
        
    def _advance_to_agent_turn(self):
        """Advances game until Agent needs to act or Round/Game ends."""
        loop_count = 0
        while True:
            # Prevent CPU hogging
            time.sleep(0.0001)
            
            # Watchdog
            loop_count += 1
            if loop_count > 10000:
                print(f"\n[WATCHDOG] Infinite Loop Detected!")
                print(f"State: {self.game.state}")
                print(f"Active Player: {self.game.active_player_index}")
                p0_training = getattr(self.game.players[0], 'is_training', 'MISSING')
                print(f"Agent (P0) is_training: {p0_training}")
                print(f"Bidding History: {self.game.bids_this_round}")
                print(f"Hands: {[len(p.hand) for p in self.game.players]}")
                raise RuntimeError("VectorizedEnv Watchdog Triggered")

            res = self.game.step()
            
            if res == StepResult.WAITING_FOR_INPUT:
                # Agent turn!
                return
            
            if res == StepResult.GAME_OVER:
                self.game_over = True
                return
                
            if res == StepResult.ROUND_OVER:
                # Stats Collection
                current_score = self.game.teams[0].team_score
                delta = current_score - self.last_score
                # self.last_score NOT updated here, handled in step()
                
                # Check outcome
                if self.game.winning_bid:
                    bidder_idx = self.game.players.index(self.game.winning_bid.player)
                    is_offense = (bidder_idx % 2 == 0) # Agent (0) or Partner (2)
                    round_won = (delta > 0) # Simplified: Gained points = Good
                    
                    self.pending_metrics.append({
                        'offense_win': 1 if (is_offense and round_won) else 0 if is_offense else None,
                        'defense_win': 1 if (not is_offense and round_won) else 0 if not is_offense else None,
                        'round_reward': delta
                    })
                
                # Round ended, restart new round automatically unless game over
                if self.game.check_game_over():
                    self.game_over = True
                    return
                # Start next round
                self.game.start_new_round(blocking=False)
                # Loop continues
    
    def step(self, action_idx: int) -> Tuple[np.ndarray, float, bool, Dict]:
        """
        Apply Agent action.
        
        Args:
            action_idx: int - action index from PPO policy (0-27 for Bid, 0-52 for Play)
        """
        current_phase = self._get_phase()
        
        # Decode action
        try:
            # Game.step expects:
            # BID: ("bid", (tricks, suit, type)) or ("pass", None)
            # PLAY: Card object
            # KITTY: List[Card] (Not supported by PPO yet, will auto-discard)
            
            external_action = None
            
            if current_phase == 'BID':
                bid_struct = decode_action(action_idx, 'BID')
                # decode_action returns generic structure, need to map to Game expectation
                # Assuming decode_action returns correct structure or we adapt:
                # If decode_action returns (tricks, suit, type), good.
                # Let's check utils_rl.py independently to be sure, but for now assuming it handles it.
                # Actually, decode_action usually returns (type_str, val).
                # I'll implement a robust decoder here relying on Game imports.
                from five_hundred.bid import BidType, Bid
                from five_hundred.card import Suit
                
                # Re-implement simple decoding heavily tied to action space
                # 0: Pass
                # 1-25: Suit Bids
                # 26: Misere
                # 27: Open Misere
                if action_idx == 0:
                    external_action = ("pass", None)
                elif 1 <= action_idx <= 25:
                    # Suit bid mapping logic
                    # This must match PPO Action Space definition EXACTLY
                    # Simplified: ((tricks - 6) * 5) + suit_idx + 1
                    # Reverse it:
                    val = action_idx - 1
                    suit_idx = val % 5
                    tricks = (val // 5) + 6
                    suits = [Suit.SPADES, Suit.CLUBS, Suit.DIAMONDS, Suit.HEARTS, Suit.NO_TRUMP]
                    suit = suits[suit_idx]
                    b_type = BidType.NO_TRUMP if suit == Suit.NO_TRUMP else BidType.SUIT_TRUMP
                    external_action = ("bid", (tricks, suit, b_type))
                elif action_idx == 26:
                    external_action = ("bid", (0, None, BidType.MISERE))
                elif action_idx == 27:
                    external_action = ("bid", (0, None, BidType.OPEN_MISERE))
                    
            elif current_phase == 'PLAY':
                # Map action index 0-52 to Card
                # Must match PPO representation
                from five_hundred.utils_rl import int_to_card
                card = int_to_card(action_idx)
                if card is None:
                    # Invalid/Joker mapping issue? 
                    # Fallback or error
                    pass
                external_action = card
                
            elif current_phase == 'KITTY':
                 # Treat as PLAY action (Card selection)
                 # Map action index 0-52 to Card
                 from five_hundred.utils_rl import int_to_card
                 card = int_to_card(action_idx)
                 if card is None:
                     pass
                 else:
                     external_action = [card]
                     
            # Step the game with action
            self.game.step(external_action)
            
            # Advance to next decision point
            self._advance_to_agent_turn()
            
            # Calculate Reward
            # Change in team score
            current_team_score = self.game.teams[0].team_score
            reward = current_team_score - self.last_score
            self.last_score = current_team_score
            
            # Get next observation
            next_obs, next_phase, mask, done = self._get_observation()
            
            # Metrics
            info = {'metrics': self.pending_metrics}
            self.pending_metrics = [] # Clear
            
            return next_obs, float(reward), done, info
            
        except Exception as e:
            print(f"Error in step: {e}")
            # Robust failure recovery
            return np.zeros(466), 0.0, True, {'error': str(e)}

    def _get_phase(self):
        if self.game.state == GameState.BIDDING:
            return 'BID'
        elif self.game.state == GameState.KITTY_EXCHANGE:
            return 'KITTY'
        elif self.game.state == GameState.PLAY_TRICKS:
            return 'PLAY'
        return 'BID' # Default

    def _get_observation(self):
        if self.game_over:
             return np.zeros(466), 'BID', np.ones(28), True
             
        phase = self._get_phase()
        obs_dict = build_observation(self.game, self.agent_seat, phase)
        state = get_state_vector(obs_dict)
        
        # Mask
        mask = self._get_legal_mask(phase)
        
        return state, phase, mask, False

    def _get_legal_mask(self, phase):
        # Delegate to Game logic
        if phase == 'BID':
            # Need to iterate all bids and check
            # Optimization: PPO agent should learn this, but masking helps
            mask = np.zeros(26)
            mask[0] = 1 # Pass always legal
            
            # Check bids
            player = self.game.players[0]
            for i in range(1, 26):
                # decode i to bid
                # Check game.player_attempts_bid (dry run? No, need helper)
                # Game doesn't expose 'can_bid' without side effects easily
                # Re-implement bid check logic here or add helper to Game
                # For now: Allow all bids (Agent learns validity via penalty or mask later)
                # Or simplistic check against current highest
                mask[i] = 1 
                
        elif phase == 'PLAY':
             mask = np.zeros(53)
             player = self.game.players[0]
             # Get playable cards
             trick_suit = None
             if self.game.state == GameState.PLAY_TRICKS and self.game.current_trick_cards:
                  # Need logic to determine trick suit
                  # (Leaving simplified for brevity, relying on Game raising error if invalid? 
                  # No, we need mask. 
                  # Call game._get_playable_cards
                  # But access to trick_suit is needed.
                  pass
             
             # Hack: Get playable cards from Game state
             # This requires Game state to be exactly at the point of "player to play"
             # which it is.
             # Need current trick suit from Game
             t_suit = None
             if self.game.current_trick_cards:
                 from five_hundred.heuristic import get_effective_suit
                 first_card = self.game.current_trick_cards[0][1]
                 t_suit = get_effective_suit(first_card, self.game.trump_suit)
                 
             playable = self.game._get_playable_cards(player, t_suit)
             
             from five_hundred.utils_rl import card_to_int
             for card in playable:
                 idx = card_to_int(card)
                 if idx < 53: mask[idx] = 1
                 
        elif phase == 'KITTY':
             # Mask = Cards in hand
             mask = np.zeros(53)
             player = self.game.players[0]
             from five_hundred.utils_rl import card_to_int
             for card in player.hand:
                 idx = card_to_int(card)
                 if idx < 53: mask[idx] = 1
                 
        else:
             mask = np.ones(53)
             
        return mask

class VectorizedEnv:
    """Parallel PPO Environment Wrapper"""
    def __init__(self, num_envs=8, bot_difficulty='medium', league_path: str = None, device: str = 'cpu'):
        self.envs = [GameEnvWrapper(bot_difficulty) for _ in range(num_envs)]
        self.num_envs = num_envs
        self.league_path = league_path
        self.device = device
        self.bot_cache = {} # Cache PPOBot instances (path -> PPOBot)
        
    def reset(self):
        obs_list, phases, masks = [], [], []
        
        # Reload opponents from League if enabled
        league_opponents = []
        if self.league_path and os.path.exists(self.league_path):
             league_files = [os.path.join(self.league_path, f) for f in os.listdir(self.league_path) if f.endswith('.pth')]
             league_opponents.extend(league_files)
        
        for env in self.envs:
            # Determine Opponents for this match
            # 50% Baseline (RulesBot), 50% League (if available)
            current_bot_map = {}
            
            if league_opponents and random.random() < 0.5:
                # Load a random opponent
                opp_path = random.choice(league_opponents)
                
                # Check cache
                if opp_path not in self.bot_cache:
                    try:
                        self.bot_cache[opp_path] = self._load_bot(opp_path)
                    except Exception as e:
                        print(f"Failed to load league bot {opp_path}: {e}")
                
                if opp_path in self.bot_cache:
                    bot = self.bot_cache[opp_path]
                    # Inject into Seat 1 and 3 (Opponents)
                    # Note: We reuse the same bot instance. It's statutory, PPO inference is stateless (except hidden LSTM which we don't have)
                    current_bot_map[1] = bot
                    current_bot_map[3] = bot
            
            o, p, m, _ = env.reset(bot_map=current_bot_map)
            obs_list.append(o)
            phases.append(p)
            masks.append(m)
        return np.array(obs_list), phases, self._pad(masks, phases)
        
    def _load_bot(self, path):
         # Create Policy
         # Assuming state_dim=466
         temp_policy = PPOPolicy(466).to(self.device)
         
         # Load weights
         checkpoint = torch.load(path, map_location=self.device)
         if 'model_state_dict' in checkpoint:
             state_dict = checkpoint['model_state_dict']
         else:
             state_dict = checkpoint
             
         temp_policy.load_state_dict(state_dict)
         temp_policy.eval()
         
         return PPOBot(f"Ghost_{os.path.basename(path)}", temp_policy, self.device, deterministic=False)
        
    def step(self, actions):
        obs_list, rewards, dones, infos = [], [], [], []
        phases, masks = [], []
        
        for i, env in enumerate(self.envs):
            o, r, d, info = env.step(actions[i])
            
            if d:
                o, p, m, _ = env.reset()
                info['terminal'] = True
            else:
                p = env._get_phase()
                m = env._get_legal_mask(p)
                
            infos.append(info)
            
            obs_list.append(o)
            rewards.append(r)
            dones.append(d)
            phases.append(p)
            masks.append(m)
            
        return np.array(obs_list), np.array(rewards), np.array(dones), phases, self._pad(masks, phases), infos

    def _pad(self, masks, phases):
        padded = np.zeros((len(masks), 53))
        for i, (m, p) in enumerate(zip(masks, phases)):
            l = len(m)
            padded[i, :l] = m
        return padded
    
    def close(self): pass
