from .player import Player
from .utils_rl import get_state_vector, decode_action, card_to_int
import numpy as np
import torch
import math
from typing import Optional, Dict

def normalize_reward(score):
    """
    CRITICAL FIX (Phase 4.6): Changed divisor from 50 to 500 to prevent saturation.
    
    Old (BROKEN): tanh(-520/50) = -1.00 (saturated)
    New (FIXED):  tanh(-520/500) = -0.85 (gradient preserved)
    
    Now the network can distinguish between "small mistake" and "catastrophe."
    """
    return math.tanh(score / 500.0)

class DirectRLPlayer(Player):
    """
    A Player implementation that holds a PyTorchAgent directly appropriately
    and queries it synchronously for actions.
    Used for Opponents in Self-Play.
    """
    def __init__(self, name: str, agent_instance, seat_idx: int, is_training: bool = False, bid_epsilon=None):
        super().__init__(name)
        self.agent = agent_instance
        self.seat_idx = seat_idx
        self.game_ref = None 
        self.is_training = is_training
        self.bid_epsilon = bid_epsilon  # Override epsilon for bidding (None = use agent's epsilon)
        
        # Training state
        self.last_state = None
        self.last_action = None
        self.last_phase = None
        self.last_reward_base_score = 0
        self.last_reward_base_tricks = 0
        
        # Monte Carlo Returns: Store all transitions for this game
        # Each entry: (state, action, immediate_reward, next_state, done, phase)
        self.game_transitions = []

    def _record_transition(self, current_obs, phase, done=False):
        if not self.is_training or self.last_state is None:
            return

        # Calculate immediate reward (for MC, we'll recalculate later)
        reward = 0
        game = self.game_ref
        if game:
            my_team_idx = 0 if self.seat_idx % 2 == 0 else 1
            my_team = game.teams[my_team_idx]
            
            # 1. Delta Score (normalized with tanh)
            curr_score = my_team.team_score
            score_delta = curr_score - self.last_reward_base_score
            reward += normalize_reward(score_delta)
            self.last_reward_base_score = curr_score
            
            # 2. Tricks Won (small immediate reward)
            curr_tricks = sum(p.tricks_won_this_round for p in my_team.players)
            if curr_tricks > self.last_reward_base_tricks:
                reward += 0.1  # Reduced from 1.0 to match tanh scale
            self.last_reward_base_tricks = curr_tricks

        # Monte Carlo: Store transition in buffer instead of immediate agent.remember()
        # We'll calculate cumulative discounted returns at game end
        self.game_transitions.append({
            'state': self.last_state,
            'action': self.last_action,
            'reward': reward,
            'next_state': current_obs,
            'done': done,
            'phase': self.last_phase
        })

    def reset_training_state(self):
        self.last_state = None
        self.last_action = None
        self.last_reward_base_score = 0
        self.last_reward_base_tricks = 0
        self.game_transitions = []  # Clear MC buffer

    def get_action(self, game_state):
        pass

    # Override Bid Decision
    def decide_bid(self, current_highest_bid, bids_this_round, player_has_bid_this_round, player_has_passed_auction):
        obs = self._build_observation("BID")
        
        # Record transition from PREVIOUS action
        self._record_transition(obs, "BID")
        
        action_idx = self.agent.act(obs, "BID", valid_mask=self._get_mask("BID"))
        
        # Save for NEXT record
        self.last_state = obs
        self.last_action = action_idx
        self.last_phase = "BID"
        
        action_tuple = decode_action(action_idx, "BID")
        
        type_str, val = action_tuple
        if type_str == "pass":
            return "pass", None
        else:
            return "bid", val

    # Override Play Decision
    def decide_play_card(self, playable_cards, trick_suit, trump_suit, trick_history):
        obs = self._build_observation("PLAY")
        
        # Record transition from PREVIOUS action
        self._record_transition(obs, "PLAY")
        
        action_idx = self.agent.act(obs, "PLAY", valid_mask=self._get_mask("PLAY", playable_cards))
        
        # Save for NEXT record
        self.last_state = obs
        self.last_action = action_idx
        self.last_phase = "PLAY"
        
        card = decode_action(action_idx, "PLAY")
        
        # Validation fallback
        if card not in playable_cards:
            import random
            return random.choice(playable_cards)
            
        return card
        
    def _build_observation(self, phase):
        # We need to reconstruct the huge state dict relative to THIS seat.
        # This is tricky without reference to Game.
        # Hack: The Game instantiating us can set `self.game_ref = game`.
        # We placed it in `env.py`: `self.game.players[seat_idx] = opp_p`.
        # We can add `opp_p.game_ref = self.game` there.
        
        game = self.game_ref
        if not game:
            return np.zeros(600, dtype=np.float32) # Panic
            
        # Relative Team Logic
        # If I am seat 1 (Opp1). My Partner is Seat 3.
        # My Team is game.teams[1]. Opponent Team is game.teams[0].
        
        my_team_idx = 0
        if self in game.teams[1].players:
            my_team_idx = 1
            
        my_team = game.teams[my_team_idx]
        opp_team = game.teams[1 - my_team_idx]
        
        # Build Obs Dict similar to Env
        obs = {}
        obs['phase'] = phase
        obs['hand'] = self.hand
        obs['trump_suit'] = game.trump_suit
        
        # Trick
        obs['current_trick'] = list(getattr(game, 'current_trick_cards', []))
        obs['played_history'] = list(getattr(game, 'cards_played_this_round', []))
        
        obs['my_score'] = my_team.team_score
        obs['opp_score'] = opp_team.team_score
        
        obs['agent_seat'] = self.seat_idx # Important! State vector builder uses this for relative positioning
        
        if game.winning_bid:
            obs['winning_bid_obj'] = game.winning_bid
            obs['bidder_seat'] = game.players.index(game.winning_bid.player)
            
        obs['tricks_my_team'] = sum(p.tricks_won_this_round for p in my_team.players)
        obs['tricks_opp_team'] = sum(p.tricks_won_this_round for p in opp_team.players)
        
        # Bidding History
        obs['bidding_history_one_hot'] = {}
        for item in game.bids_this_round:
            if isinstance(item, str) and "passes" in item:
                # Find player name match
                 for i, p in enumerate(game.players):
                    if p.name in item:
                        obs['bidding_history_one_hot'][i] = 0
                        break
            elif hasattr(item, 'player'):
                p_idx = game.players.index(item.player)
                # ... same encoding logic ... 
                # Ideally, helper for encoding bid item? 
                # Let's duplicate or move to utils?
                # Move to utils_rl: encode_bid_history_item(item)
                # For now, duplicate inline to be safe/fast
                
                from .bid import BidType
                from .card import Suit
                bid_code = 0
                if item.bid_type == BidType.MISERE: bid_code = 26
                elif item.bid_type == BidType.OPEN_MISERE: bid_code = 27
                else:
                    tr_idx = item.tricks - 6
                    s_map = {Suit.SPADES: 0, Suit.CLUBS: 1, Suit.DIAMONDS: 2, Suit.HEARTS: 3, Suit.NO_TRUMP: 4}
                    s_idx = s_map.get(item.suit, 4) if item.bid_type == BidType.SUIT_TRUMP or item.bid_type == BidType.NO_TRUMP else 4
                    bid_code = 1 + (tr_idx * 5) + s_idx
                obs['bidding_history_one_hot'][p_idx] = bid_code

        return get_state_vector(obs)
        
    def _get_mask(self, phase, legal_moves=None):
        mask = np.zeros(100, dtype=np.float32) # Action space size
        if phase == 'BID':
            mask[:] = 1
            mask[26] = 0 # No Misere
            mask[27] = 0
        elif (phase == 'PLAY' or phase == 'KITTY') and legal_moves:
            for card in legal_moves:
                idx = card_to_int(card)
                if 0 <= idx < 100:
                    mask[idx] = 1
        return mask

    def finalize_training_game(self, win=False, game_score=0, agent_won_bid=False, bid_tricks=0, contract_made=False):
        if not self.is_training:
            return
        
        # HYBRID TD/MC APPROACH (Phase 3):
        # - Monte Carlo returns for BIDDING (credit assignment for game outcome)
        # - Standard TD for PLAYING (immediate rewards, low variance)
        
        # Separate transitions by phase
        bid_transitions = [t for t in self.game_transitions if t['phase'] == 'BID']
        play_transitions = [t for t in self.game_transitions if t['phase'] in ['PLAY', 'KITTY']]
        
        # Terminal reward (tanh normalized with FIXED divisor)
        terminal_reward = normalize_reward(float(game_score))
        
        # Base win/loss bonus
        if win:
            terminal_reward += 0.1
        else:
            terminal_reward -= 0.1
            
        # DYNAMIC RISK SHAPING (Phase 4.6): "The Price of Failure"
        # Makes agent feel the difference between small and catastrophic failures
        if agent_won_bid:
            if contract_made:
                # Small fixed bonus for ANY successful contract
                # (Reduced from 0.5 to prevent reckless bidding)
                terminal_reward += 0.2
            else:
                # Dynamic Penalty: Scale by bid difficulty
                # 6 Tricks (min viable) -> difficulty 0.0 -> penalty -0.1
                # 10 Tricks (max) -> difficulty 1.0 -> penalty -0.5
                difficulty = (bid_tricks - 6) / 4.0
                penalty = 0.1 + (0.4 * difficulty)
                terminal_reward -= penalty
        else:
            # Defense bonus (unchanged - this works well)
            if win:
                terminal_reward += 0.1  # Already added above, this is redundant but kept for clarity
        
        # MC RETURNS FOR BIDDING ONLY
        gamma = self.agent.gamma
        G = terminal_reward
        
        for t in reversed(range(len(bid_transitions))):
            trans = bid_transitions[t]
            done = (t == len(bid_transitions) - 1)
            
            self.agent.remember(
                state=trans['state'],
                action=trans['action'],
                reward=G,  # Monte Carlo return
                next_state=trans['next_state'],
                done=done,
                phase='BID'
            )
            
            if t > 0:
                G = trans['reward'] + gamma * G
        
        # PLAY TRANSITIONS: Already stored with immediate rewards (TD learning)
        # No update needed - they use standard TD via agent.replay()
        
        self.reset_training_state()
    
    # Kitty Discard Logic?
    def decide_kitty_exchange(self, kitty_cards, winning_bid=None):
        combined = list(self.hand) # Hand already has kitty added in Game._handle_kitty_exchange?
        # Actually, check Game.py.
        # Line 411: declarer.add_cards_to_hand(self.kitty)
        # So self.hand is already 13 cards.
        
        discards = []
        for i in range(3):
            obs = self._build_observation("KITTY")
            self._record_transition(obs, "KITTY")
            
            # Sub-hand for masking?
            # We want to discard cards from our hand.
            remaining = [c for c in self.hand if c not in discards]
            action_idx = self.agent.act(obs, "KITTY", valid_mask=self._get_mask("KITTY", remaining))
            
            self.last_state = obs
            self.last_action = action_idx
            self.last_phase = "KITTY"
            
            card = decode_action(action_idx, "KITTY")
            if card in remaining:
                discards.append(card)
            else:
                # Fallback
                import random
                c = random.choice(remaining)
                discards.append(c)
                
        return discards

