import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import random
import pickle
import os
from collections import deque
from .prioritized_replay import PrioritizedReplayBuffer

class BiddingNetwork(nn.Module):
    def __init__(self, input_dim, output_dim):
        super(BiddingNetwork, self).__init__()
        self.feature = nn.Sequential(
            nn.Linear(input_dim, 512),
            nn.ReLU(),
            nn.Linear(512, 512),
            nn.ReLU()
        )
        
        self.advantage = nn.Sequential(
            nn.Linear(512, 512),
            nn.ReLU(),
            nn.Linear(512, output_dim)
        )
        
        self.value = nn.Sequential(
            nn.Linear(512, 512),
            nn.ReLU(),
            nn.Linear(512, 1)
        )
        
    def forward(self, x):
        x = self.feature(x)
        adv = self.advantage(x)
        val = self.value(x)
        return val + adv - adv.mean(dim=1, keepdim=True)

class PlayingNetwork(nn.Module):
    def __init__(self, input_dim, output_dim):
        super(PlayingNetwork, self).__init__()
        self.feature = nn.Sequential(
            nn.Linear(input_dim, 512),
            nn.ReLU(),
            nn.Linear(512, 512),
            nn.ReLU()
        )
        
        self.advantage = nn.Sequential(
            nn.Linear(512, 512),
            nn.ReLU(),
            nn.Linear(512, output_dim)
        )
        
        self.value = nn.Sequential(
            nn.Linear(512, 512),
            nn.ReLU(),
            nn.Linear(512, 1)
        )
        
    def forward(self, x):
        x = self.feature(x)
        adv = self.advantage(x)
        val = self.value(x)
        return val + adv - adv.mean(dim=1, keepdim=True)

class PyTorchAgent:
    def __init__(self, state_dim=600, action_dim=100, lr=1e-4, gamma=0.99, buffer_size=50000):
        self.state_dim = state_dim
        self.action_dim = action_dim
        self.gamma = gamma
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        # Ensure MPS on Mac if available (PyTorch > 1.12)
        if torch.backends.mps.is_available():
             self.device = torch.device("mps")

        print(f"Agent initialized on device: {self.device}")

        # --- Architecture: Split Brains ---
        # Bidding Space: 0-27 (28 actions)
        # Playing Space: 0-52 (53 actions) - but we map output to 0..52
        
        # Bidding Brain
        self.bid_net = BiddingNetwork(state_dim, 28).to(self.device)
        self.target_bid_net = BiddingNetwork(state_dim, 28).to(self.device)
        self.target_bid_net.load_state_dict(self.bid_net.state_dict())
        
        # Playing Brain
        self.play_net = PlayingNetwork(state_dim, 53).to(self.device)
        self.target_play_net = PlayingNetwork(state_dim, 53).to(self.device)
        self.target_play_net.load_state_dict(self.play_net.state_dict())
        
        # Optimizers (Adam!)
        self.bid_optimizer = optim.Adam(self.bid_net.parameters(), lr=lr)
        self.play_optimizer = optim.Adam(self.play_net.parameters(), lr=lr)
        
        self.criterion = nn.MSELoss(reduction='none') # Return individual losses for PER
        
        # Memory: Prioritized Experience Replay
        self.bid_memory = PrioritizedReplayBuffer(buffer_size)
        self.play_memory = PrioritizedReplayBuffer(buffer_size)
        
        # Epsilon
        self.epsilon = 1.0
        self.epsilon_min = 0.05 # Lower floor for meaningful play
        self.epsilon_decay = 0.999995  # VERY slow decay - takes ~200k episodes to reach min

    def act(self, state, phase, valid_mask=None, bid_epsilon=None):
        """
        Returns action_idx (int).
        Uses Bidding Net if phase='BID'.
        Uses Playing Net if phase='PLAY'/'KITTY'.
        
        bid_epsilon: Optional override for epsilon during bidding phase.
                     If None, uses self.epsilon for all phases.
                     If provided, uses bid_epsilon for BID phase only.
        """
        if phase == "BID":
            brain = self.bid_net
            action_space_size = 28
            # Use bid_epsilon if provided, otherwise use self.epsilon
            epsilon_to_use = bid_epsilon if bid_epsilon is not None else self.epsilon
        elif phase in ["PLAY", "KITTY"]:
            brain = self.play_net
            action_space_size = 53
            epsilon_to_use = self.epsilon
        else:
            raise ValueError(f"Unknown phase: {phase}")
        
        # Epsilon-greedy
        if random.random() < epsilon_to_use:
            # Random valid action
            if valid_mask is not None:
                valid_indices = [i for i, v in enumerate(valid_mask[:action_space_size]) if v]
                if valid_indices:
                    return random.choice(valid_indices)
            return random.randint(0, action_space_size - 1)
        
        # Greedy (use network)
        state_tensor = torch.FloatTensor(state).unsqueeze(0).to(self.device)
        
        with torch.no_grad():
            if phase == "BID":
                q_values = brain(state_tensor).squeeze(0) # [28]
            else:
                q_values = brain(state_tensor).squeeze(0) # [53]
        
        # Apply mask
        if valid_mask is not None:
            mask_subset = torch.FloatTensor(valid_mask[:action_space_size]).to(self.device)
            q_values = q_values.masked_fill(mask_subset == 0, float('-inf'))
        
        action_idx = torch.argmax(q_values).item()
        return action_idx

    def remember(self, state, action, reward, next_state, done, phase=None):
        if phase is None:
            # Inference fallback
            is_bid = (state[0] == 1)
            phase = 'BID' if is_bid else 'PLAY'
            
        # PER: push with phase info
        if phase == 'BID':
            self.bid_memory.push(state, action, reward, next_state, done, phase)
        else:
            # KITTY and PLAY both use play_net
            self.play_memory.push(state, action, reward, next_state, done, phase)

    def replay(self, batch_size=64, freeze_bidding=False):
        """
        Train both networks using Prioritized Experience Replay.
        Returns TD-errors to update priorities in the replay buffer.
        """
        total_loss = 0.0
        
        # Train bidding network (unless frozen)
        if not freeze_bidding and len(self.bid_memory) >= batch_size:
            batch, idxs, weights = self.bid_memory.sample(batch_size)
            loss, td_errors = self.train_network_per(batch, weights, self.bid_net, self.target_bid_net, self.bid_optimizer, 28)
            self.bid_memory.update_priorities(idxs, td_errors)
            total_loss += loss
        
        # Always train playing network
        if len(self.play_memory) >= batch_size:
            batch, idxs, weights = self.play_memory.sample(batch_size)
            loss, td_errors = self.train_network_per(batch, weights, self.play_net, self.target_play_net, self.play_optimizer, 53)
            self.play_memory.update_priorities(idxs, td_errors)
            total_loss += loss
        
        return total_loss if total_loss > 0 else None

    def decay_epsilon(self):
        if self.epsilon > self.epsilon_min:
            self.epsilon *= self.epsilon_decay

    def train_network(self, batch, policy_net, target_net, optimizer, output_dim):
        states = torch.FloatTensor(np.array([x[0] for x in batch])).to(self.device)
        actions = torch.LongTensor(np.array([x[1] for x in batch])).to(self.device)
        rewards = torch.FloatTensor(np.array([x[2] for x in batch])).to(self.device)
        next_states = torch.FloatTensor(np.array([x[3] for x in batch])).to(self.device)
        dones = torch.FloatTensor(np.array([x[4] for x in batch])).to(self.device) # 1 if done, 0 else
        
        # Current Q
        # actions are 1D indices.
        # policy_net(states) -> [batch, output_dim]
        # gather -> [batch]
        
        # Valid action range check? 
        # If playing, actions are 0..52. If bidding, 0..27.
        # actions tensor should match output_dim range roughly.
        
        curr_q = policy_net(states).gather(1, actions.unsqueeze(1)).squeeze(1)
        
        # Next Q
        with torch.no_grad():
            next_q_vals = target_net(next_states)
            max_next_q = next_q_vals.max(1)[0]
            target_q = rewards + (self.gamma * max_next_q * (1 - dones))
            
            # Clip targets logic from Exp 3
            target_q = torch.clamp(target_q, -20, 20)
            
        loss = self.criterion(curr_q, target_q)
        
        optimizer.zero_grad()
        loss.backward()
        # Gradient clipping
        torch.nn.utils.clip_grad_norm_(policy_net.parameters(), 1.0)
        optimizer.step()
        
        return loss.item()

    def update_target_network(self):
        self.target_bid_net.load_state_dict(self.bid_net.state_dict())
        self.target_play_net.load_state_dict(self.play_net.state_dict())
        
    def save(self, name):
        torch.save({
            'bid': self.bid_net.state_dict(),
            'play': self.play_net.state_dict(),
            'epsilon': self.epsilon
        }, name)
        
        # Save memory separately as it's large
        mem_name = name.replace(".pth", "_memory.pkl")
        self.save_memory(mem_name)
        
    def load(self, name):
        checkpoint = torch.load(name, map_location=self.device)
        self.bid_net.load_state_dict(checkpoint['bid'])
        self.play_net.load_state_dict(checkpoint['play'])
        self.target_bid_net.load_state_dict(checkpoint['bid'])
        self.target_play_net.load_state_dict(checkpoint['play'])
        if 'epsilon' in checkpoint:
            self.epsilon = checkpoint['epsilon']
            print(f"Loaded epsilon: {self.epsilon:.4f}")
            
        mem_name = name.replace(".pth", "_memory.pkl")
        self.load_memory(mem_name)

    def save_memory(self, filename):
        try:
            with open(filename, 'wb') as f:
                pickle.dump({'bid': self.bid_memory, 'play': self.play_memory}, f)
        except Exception as e:
            print(f"Failed to save memory: {e}")

    def load_memory(self, filename):
        try:
            if os.path.exists(filename):
                with open(filename, 'rb') as f:
                    data = pickle.load(f)
                    if isinstance(data, dict):
                        self.bid_memory = data.get('bid', self.bid_memory)
                        self.play_memory = data.get('play', self.play_memory)
                    else:
                        # Migration for old legacy files
                        self.play_memory = data
                print(f"Loaded memory: {len(self.bid_memory)} bid, {len(self.play_memory)} play transitions.")
        except Exception as e:
            print(f"Failed to load memory: {e}")
    def train_network_per(self, batch, is_weights, policy_net, target_net, optimizer, output_dim):
        """
        Train network using Prioritized Experience Replay with importance sampling.
        Returns: (average_loss, td_errors_for_priority_update)
        """
        # Extract transitions from named tuples
        states = torch.FloatTensor(np.array([t.state for t in batch])).to(self.device)
        actions = torch.LongTensor(np.array([t.action for t in batch])).to(self.device)
        rewards = torch.FloatTensor(np.array([t.reward for t in batch])).to(self.device)
        next_states = torch.FloatTensor(np.array([t.next_state for t in batch])).to(self.device)
        dones = torch.FloatTensor(np.array([t.done for t in batch])).to(self.device)
        weights = torch.FloatTensor(is_weights).to(self.device)
        
        # Current Q-values
        curr_q = policy_net(states).gather(1, actions.unsqueeze(1)).squeeze(1)
        
        # Target Q-values
        with torch.no_grad():
            next_q_vals = target_net(next_states)
            max_next_q = next_q_vals.max(1)[0]
            target_q = rewards + (self.gamma * max_next_q * (1 - dones))
            # Expanded clipping for new reward scale
            target_q = torch.clamp(target_q, -100, 100)
        
        # TD-errors for priority update
        td_errors = (curr_q - target_q).detach().cpu().numpy()
        
        # Weighted loss (importance sampling)
        elementwise_loss = self.criterion(curr_q, target_q)
        loss = (elementwise_loss * weights).mean()
        
        # Backprop
        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(policy_net.parameters(), 1.0)
        optimizer.step()
        
        return loss.item(), td_errors
