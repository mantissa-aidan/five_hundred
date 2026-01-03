"""
PPO (Proximal Policy Optimization) Agent for Five Hundred Card Game

Key architectural decisions:
1. Shared trunk for feature extraction
2. Separate actor heads for bidding vs playing
3. Separate critic heads (value of bid ≠ value of card)
4. Critical action masking to prevent illegal moves
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.distributions import Categorical
import numpy as np

class PPOPolicy(nn.Module):
    """
    PPO Policy with dual heads for bidding and playing.
    
    Architecture:
        Shared Trunk (466 → 256 → 128)
        ├── Actor Bid Head (128 → 28)
        ├── Actor Play Head (128 → 53)
        ├── Critic Bid Head (128 → 1)
        └── Critic Play Head (128 → 1)
    """
    
    def __init__(self, state_dim=466):
        super().__init__()
        
        # Shared Feature Extractor (The "Trunk")
        self.shared = nn.Sequential(
            nn.Linear(state_dim, 256),
            nn.ReLU(),
            nn.Linear(256, 128),
            nn.ReLU()
        )
        
        # ACTOR Heads (Policy π)
        # Output logits (pre-softmax) for action probabilities
        self.actor_bid = nn.Linear(128, 26)   # 26 bid actions (No Misere)
        self.actor_play = nn.Linear(128, 53)  # 53 card actions
        
        # CRITIC Heads (Value V)
        # Separate because "Value of a Bid" (Game Score) 
        # is different from "Value of a Card" (Trick Count)
        self.critic_bid = nn.Linear(128, 1)
        self.critic_play = nn.Linear(128, 1)
        
        # Initialize weights
        self._initialize_weights()
    
    def _initialize_weights(self):
        """Orthogonal initialization for better training stability"""
        for module in self.modules():
            if isinstance(module, nn.Linear):
                nn.init.orthogonal_(module.weight, gain=np.sqrt(2))
                nn.init.constant_(module.bias, 0.0)
    
    def forward(self):
        """
        Do not use forward() directly. Use get_action_and_value() instead.
        This enforces phase-specific processing.
        """
        raise NotImplementedError("Use get_action_and_value() with phase='BID' or 'PLAY'")
    
    def get_action_and_value(self, state, phase, action=None, mask=None):
        """
        Core PPO interface - handles both inference and training.
        
        Args:
            state: Tensor [batch, 466] or [466] - game state
            phase: str - 'BID' or 'PLAY'/'KITTY'
            action: Tensor (optional) - for training, re-evaluate this action
            mask: Tensor (optional) - legal action mask [batch, action_dim]
        
        Returns:
            action: Selected action (if action=None) or input action
            log_prob: Log probability of the action
            entropy: Entropy of the distribution (for exploration bonus)
            value: State value estimate V(s)
        """
        # Handle both single state and batch
        if state.dim() == 1:
            state = state.unsqueeze(0)
            single_state = True
        else:
            single_state = False
        
        # Extract features
        features = self.shared(state)
        
        # Phase-specific heads
        if phase == 'BID':
            logits = self.actor_bid(features)
            value = self.critic_bid(features)
        else:  # PLAY or KITTY
            logits = self.actor_play(features)
            value = self.critic_play(features)
        
        # CRITICAL: Action Masking
        # Set logits of illegal moves to negative infinity
        # This ensures softmax assigns 0 probability to invalid actions
        if mask is not None:
            if mask.dim() == 1:
                mask = mask.unsqueeze(0)
            # Convert mask to boolean (1 = legal, 0 = illegal)
            logits = logits.masked_fill(~mask.bool(), float('-inf'))
        
        # Create categorical distribution over actions
        probs = Categorical(logits=logits)
        
        # 1. Inference Mode: Sample action from policy
        if action is None:
            action = probs.sample()
        
        # 2. Training Mode: Evaluate provided action
        log_prob = probs.log_prob(action)
        entropy = probs.entropy()
        
        # Squeeze single-state outputs
        if single_state:
            action = action.squeeze(0)
            log_prob = log_prob.squeeze(0)
            entropy = entropy.squeeze(0)
            value = value.squeeze(0)
        
        return action, log_prob, entropy, value
    
    def get_value(self, state, phase):
        """
        Get value estimate without sampling action (for bootstrapping)
        
        Args:
            state: Tensor [batch, 466] - game state
            phase: str - 'BID' or 'PLAY'
        
        Returns:
            value: Tensor [batch, 1] - state value V(s)
        """
        if state.dim() == 1:
            state = state.unsqueeze(0)
        
        features = self.shared(state)
        
        if phase == 'BID':
            value = self.critic_bid(features)
        else:
            value = self.critic_play(features)
        
        return value

    def save(self, path):
        """Save model weights"""
        torch.save({
            'model_state_dict': self.state_dict(),
            'architecture': {
                'state_dim': 466,
                'bid_actions': 28,
                'play_actions': 53
            }
        }, path)
    
    def load(self, path, device='cpu'):
        """Load model weights"""
        checkpoint = torch.load(path, map_location=device)
        self.load_state_dict(checkpoint['model_state_dict'])
        return checkpoint.get('architecture', {})


class RolloutBuffer:
    """
    Storage for on-policy rollout data.
    PPO collects N steps, computes advantages, updates, then discards.
    """
    
    def __init__(self, buffer_size=2048):
        self.buffer_size = buffer_size
        self.clear()
    
    def clear(self):
        """Reset buffer for new rollout"""
        self.states = []
        self.actions = []
        self.log_probs = []
        self.rewards = []
        self.dones = []
        self.values = []
        self.masks = []
        self.phases = []
        self.ptr = 0
    
    def add(self, state, action, log_prob, reward, done, value, mask, phase):
        """Add a transition to the buffer"""
        self.states.append(state)
        self.actions.append(action)
        self.log_probs.append(log_prob)
        self.rewards.append(reward)
        self.dones.append(done)
        self.values.append(value)
        self.masks.append(mask)
        self.phases.append(phase)
        self.ptr += 1
    
    def is_full(self):
        """Check if buffer is ready for training"""
        return self.ptr >= self.buffer_size
    
    def get(self):
        """
        Retrieve all data as tensors.
        
        Returns:
            Dictionary with all rollout data as stacked tensors
        """
        return {
            'states': torch.stack(self.states),
            'actions': torch.stack(self.actions),
            'log_probs': torch.stack(self.log_probs),
            'rewards': torch.tensor(self.rewards, dtype=torch.float32),
            'dones': torch.tensor(self.dones, dtype=torch.float32),
            'values': torch.stack(self.values),
            'masks': torch.stack(self.masks),
            'phases': self.phases  # Keep as list (strings)
        }
    
    def compute_advantages(self, next_value, gamma=0.99, gae_lambda=0.95):
        """
        Compute Generalized Advantage Estimation (GAE).
        
        Args:
            next_value: Value of the state after the last transition
            gamma: Discount factor
            gae_lambda: GAE lambda parameter (bias-variance tradeoff)
        
        Returns:
            advantages: Tensor [buffer_size] - advantage estimates
            returns: Tensor [buffer_size] - value targets (V + A)
        """
        advantages = []
        gae = 0
        
        # Convert lists to tensors
        values = torch.stack(self.values).squeeze()
        device = values.device
        
        rewards = torch.tensor(self.rewards, dtype=torch.float32).to(device)
        dones = torch.tensor(self.dones, dtype=torch.float32).to(device)
        
        # Append next_value for bootstrapping
        values_extended = torch.cat([values, next_value.unsqueeze(0)])
        
        # Compute GAE backwards through time
        for t in reversed(range(len(rewards))):
            if t == len(rewards) - 1:
                next_value_t = next_value
            else:
                next_value_t = values_extended[t + 1]
            
            # TD error: δ_t = r_t + γ·V(s_(t+1)) - V(s_t)
            delta = rewards[t] + gamma * next_value_t * (1 - dones[t]) - values[t]
            
            # GAE: A_t = δ_t + γ·λ·A_(t+1)
            gae = delta + gamma * gae_lambda * (1 - dones[t]) * gae
            advantages.insert(0, gae)
        
        advantages = torch.stack(advantages)
        
        # Debug Device
        if advantages.device != values.device:
             print(f"DEVICE MISMATCH: Adv={advantages.device} Val={values.device}")
             advantages = advantages.to(values.device)
             
        returns = advantages + values  # V + A = target for critic
        
        # Normalize advantages (improves training stability)
        advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)
        
        return advantages, returns


def transfer_dqn_to_ppo(dqn_path, ppo_model, device='cpu'):
    """
    Transfer weights from pretrained DQN to PPO architecture.
    
    Strategy:
        1. DQN feature extractor → PPO shared trunk
        2. DQN bid head → PPO actor_bid
        3. DQN play head → PPO actor_play
        4. Initialize critic heads randomly (no DQN equivalent)
    
    Args:
        dqn_path: Path to pretrained DQN checkpoint
        ppo_model: PPOPolicy instance
        device: torch device
    
    Returns:
        success: bool - whether transfer succeeded
    """
    try:
        print(f"Loading DQN checkpoint from {dqn_path}...")
        dqn_checkpoint = torch.load(dqn_path, map_location=device)
        
        # Extract DQN state dict
        if 'model_state_dict' in dqn_checkpoint:
            dqn_state = dqn_checkpoint['model_state_dict']
        else:
            dqn_state = dqn_checkpoint
        
        ppo_state = ppo_model.state_dict()
        
        # Transfer shared trunk (feature extractor)
        print("Transferring shared trunk...")
        # DQN: bid_net.0.weight → PPO: shared.0.weight
        trunk_mapping = [
            ('bid_net.0', 'shared.0'),  # First hidden layer
            ('bid_net.2', 'shared.2'),  # Second hidden layer
        ]
        
        for dqn_prefix, ppo_prefix in trunk_mapping:
            for param_type in ['weight', 'bias']:
                dqn_key = f'{dqn_prefix}.{param_type}'
                ppo_key = f'{ppo_prefix}.{param_type}'
                
                if dqn_key in dqn_state and ppo_key in ppo_state:
                    ppo_state[ppo_key] = dqn_state[dqn_key]
                    print(f"  ✓ {dqn_key} → {ppo_key}")
        
        # Transfer actor heads
        print("Transferring actor heads...")
        head_mapping = [
            ('bid_net.4', 'actor_bid'),    # Bid output layer
            ('play_net.4', 'actor_play'),  # Play output layer
        ]
        
        for dqn_prefix, ppo_prefix in head_mapping:
            for param_type in ['weight', 'bias']:
                dqn_key = f'{dqn_prefix}.{param_type}'
                ppo_key = f'{ppo_prefix}.{param_type}'
                
                if dqn_key in dqn_state and ppo_key in ppo_state:
                    src = dqn_state[dqn_key]
                    dst = ppo_state[ppo_key]
                    
                    if src.shape != dst.shape:
                        print(f"  ⚠️ Slicing {dqn_key} {src.shape} -> {dst.shape}")
                        # Slice output dimension (dim 0)
                        if src.shape[0] > dst.shape[0]:
                             ppo_state[ppo_key] = src[:dst.shape[0]]
                        else:
                             print(f"  ❌ Shape mismatch unresolvable: {src.shape} vs {dst.shape}")
                    else:
                        ppo_state[ppo_key] = src
                    
                    print(f"  ✓ {dqn_key} → {ppo_key}")
        
        # Load transferred weights
        ppo_model.load_state_dict(ppo_state)
        
        print("✅ Weight transfer complete!")
        print("⚠️  Critic heads initialized randomly (no DQN equivalent)")
        
        return True
        
    except Exception as e:
        print(f"❌ Weight transfer failed: {e}")
        return False
